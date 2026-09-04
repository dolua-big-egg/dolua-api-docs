--[=[
  http → ublob 下载 demo — 先等网络，把小文件落到 ublob，再用 view 流式读
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒
    2) 打印 ublob 配额；remove 旧文件
    3) http.get 下载 https://httpbin.org/html 到 ublob（TLS_INSECURE）
    4) 核对 body 为空、body_len 和 ublob.size 一致
    5) open view，每次 read 100 字节，用 [] 包起来打印
    6) close；再打一次配额
]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local http = require("http")
local ublob = require("ublob")

-- httpbin 的一小页 HTML，几 KB，远小于 80KB 配额。响应慢是正常的。
local URL = "https://httpbin.org/html"
local FILE_NAME = "demo.bin"
local CHUNK_SIZE = 100
local LINK_WAIT_MS = 60 * 1000

local function dump_usage(tag)
    local u = ublob.usage()
    if u then
        log.info("%s used=%s limit=%s", tag, u.used, u.limit)
    else
        log.warn("%s usage=nil", tag)
    end
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 http ublob")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start http ublob download")

log.info("---- quota before ----")
dump_usage("ublob")

ublob.remove(FILE_NAME)

log.info("---- download ----")
-- 第二参是 ublob 文件名。整包进 ublob，不进 resp.body。
-- 等价：http.request({ url=URL, save=FILE_NAME, tls_mode=http.TLS_INSECURE })
-- 或    http.request({ url=URL, save=http.save.ublob(FILE_NAME), tls_mode=http.TLS_INSECURE })
local resp, err, msg = http.get(URL, FILE_NAME, {
    tls_mode = http.TLS_INSECURE,
    max_response_size = 32 * 1024,
})
if not resp then
    log.error("download fail err=%s msg=%s", err, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("status=%s %s", resp.status_code, resp.status_desc)
log.info("body_len=%s saved_file=%s lua_body_len=%s",
         resp.body_len, resp.saved_file, resp.body and #resp.body or 0)
-- save 成功时 body 应为空：整包没进 Lua 字符串。
if resp.status_code ~= 200 then
    log.error("http status not 200")
    while true do
        rt.delay(10000)
    end
end

local size, serr = ublob.size(FILE_NAME)
if size == nil then
    log.error("ublob.size fail err=%s", serr)
    while true do
        rt.delay(10000)
    end
end
log.info("ublob.size=%s http.body_len=%s", size, resp.body_len)
if size ~= (resp.body_len or 0) then
    log.error("size mismatch")
    while true do
        rt.delay(10000)
    end
end

log.info("---- view stream 100B ----")
-- open：明文挂到后台缓冲。后面每次只切 100 字节进 Lua。
local v, oerr = ublob.open(FILE_NAME)
if not v then
    log.error("open fail err=%s", oerr)
    while true do
        rt.delay(10000)
    end
end
log.info("view.size=%s", v:size())

local offset = 0
local idx = 0
local total = 0
while offset < v:size() do
    idx = idx + 1
    local chunk, nread, rerr = v:read(offset, CHUNK_SIZE)
    if chunk == nil then
        v:close()
        log.error("view.read fail idx=%s err=%s", idx, rerr)
        while true do
            rt.delay(10000)
        end
    end
    if nread == 0 then
        break
    end
    -- 用 [] 包起来，方便看每一片的边界。
    log.info("[%s]", chunk)
    total = total + nread
    offset = offset + nread
end

v:close()
log.info("view done total_read=%s expect=%s", total, size)

log.info("---- quota after ----")
dump_usage("ublob")

log.info("---- done ----")
while true do
    rt.delay(10000)
end

--[=[
  http → ublob 下载 demo — 先等网络，把小文件落到 ublob，再用 view 流式读

  http / ublob 都是独立模块：require("http")、require("ublob")。
  必须先有 PDP。本 demo 用 lp.wait_link 等驻网，超时就停。

  ============================================================================
  ublob 是什么
  ============================================================================
  系统内置的小型二进制文件系统，不是普通磁盘路径。
  和 ufs 共用配额，上限约 80KB（ublob.usage().limit）。
  只适合几十 KB 的小文件：配置、证书、一小段固件、短日志。
  再大的包请走 lfs / 外部存储，别往 ublob 里塞。

  ============================================================================
  下载到 ublob vs 直接下到 Lua / 普通文件
  ============================================================================
  普通 http.get / request（不带 save）：
    整份响应体变成 Lua 字符串 resp.body，文件有多大 Lua 堆就占多大。
    这就是「直接下到内存」。

  带 save 落到 ublob：
    响应体写入 ublob，不把整包交给 Lua。
    resp.body 是空串，resp.body_len 仍是实际长度。
    Lua 堆只留下状态码、头这些小字段，RAM 占用明显更低。

  和「直接下载到普通文件」（lfs 等）比：
    ublob 专为小对象设计，压缩落盘，打开后对流式切片读特别合适。
    容量小，别当通用文件系统用。

  下载写法（三条等价，都是覆盖写）
    http.get(url, "demo.bin", opts)
    http.request({ url=..., save="demo.bin", ... })
    http.request({ url=..., save=http.save.ublob("demo.bin"), ... })
  本 demo 用第一种。https 同样要带 tls_mode。

  下载前先 ublob.remove 清掉同名旧文件。超配额会失败（约 -21）。

  ============================================================================
  view：适合流式处理
  ============================================================================
  ublob.read(name, offset, len)
    每次都把整文件解压再切一片。偶尔读一下可以，循环读很亏。

  ublob.open(name) -> view
    打开时把明文挂到一份后台缓冲上（不占 Lua 堆里的整包字符串）。
    之后所有切片、crc、md5 都在这份缓冲上做，不必反复解压。
    适合按块处理、流式解析。用完必须 close，缓冲才释放。
    同时只能开 1 个 view，没 close 就无法再 open。

  view:read(offset, len) -> data, nread, err
    从 offset 切最多 len 字节。末尾不够就截断，nread 是实际长度。
    offset 越过末尾：空串, 0。
    每次只有这一小片进入 Lua，所以能流式处理而不把整文件变成 Lua 字符串。

  view:size()     明文总长度，和 ublob.size(name) 一致
  view:crc32([offset], [len])   在缓冲上算，不必再拷一份进 Lua
  view:md5([offset], [len])     同上，默认小写 hex
  view:close()    释放后台缓冲。GC 也会收，但业务里请显式 close

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒
    2) 打印 ublob 配额；remove 旧文件
    3) http.get 下载 https://httpbin.org/html 到 ublob（TLS_INSECURE）
    4) 核对 body 为空、body_len 和 ublob.size 一致
    5) open view，每次 read 100 字节，用 [] 包起来打印
    6) close；再打一次配额


  注：这种方式，对大文件支持友好，比如MCU OTA等，需要一次性下载，分块传输等，当然也可以直接分块下载，使用range头来下载。
  但是本demo演示存储到本地，存储位置是模块的内部文件系统 ublob ，不同的模块可用容量不一样，如果有较大的文件下载需求，几百kb或者
  几mb的文件，请使用外部挂载的flash，模块支持 http->外部flash挂载好的flashdb，和littlefs文件系统，
  请参考demo【http_file_flashdb】和【http_file_littlefs】。
  但是测试外部flash时，需要先保证flash通讯成功，最好是先使用spi的demo，把flash通讯成功了，再测试http_file_flashdb和http_file_littlefs。

]=]