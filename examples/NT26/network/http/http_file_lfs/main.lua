--[=[
  http → LittleFS 下载 demo（SPI 外挂 W25Qxx）
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link
    2) flash.init：整片 lfs.mount；已有文件系统直接挂。空片默认不整区预擦。
    3) 下载 https://www.baidu.com/ 到 /demo.bin
    4) 每次读 100 字节，用 [] 包起来打印

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local flash = require("flash")
local download = require("download")

local LINK_WAIT_MS = 60 * 1000

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 http lfs")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok")

log.info("---- flash.init ----")
local ok, part_or_err = flash.init()
if not ok then
    log.error("flash.init fail err=%s", part_or_err)
    log.error("check SPI wiring and rtu_config [uart.2] pin_map=1")
    while true do
        rt.delay(10000)
    end
end

local part = part_or_err
local sfud0 = flash.sfud()
log.info("jedec=%s cap=%s gran=%s", sfud0:jedec_id(), part.capacity, part.erase_gran)
log.info("lfs name=%s off=%s size=%s", part.fs.name, part.fs.offset, part.fs.size)

log.info("---- download ----")
ok, part_or_err = download.run(flash.fs())
if not ok then
    log.error("download fail err=%s", part_or_err)
else
    log.info("download ok")
end

log.info("---- done ----")
while true do
    rt.delay(10000)
end

--[=[
  http → LittleFS 下载 demo（SPI 外挂 W25Qxx）

  多文件：
    flash.lua     SPI0 + CS(GPIO8) → sfud → lfs.mount
    download.lua  http.get + save.lfs，再按 100 字节流式打印
    main.lua      等网、挂盘、开下

  硬件与 lfs_flashdb 工程一致：SPI0 + GPIO8(CS)，W25Qxx。
  LittleFS 挂整片（offset=0，size=芯片容量）。已有文件系统直接挂，空片才格式化。
  格式化/挂载进度由 flash.lua 的 on_event 打印。

  ----------------------------------------------------------------------------
  配置文件（必须改 UART2）
  ----------------------------------------------------------------------------
  SPI0 默认脚和 UART2 默认脚是同一组。不挪 UART2，SPI 和串口会抢脚，Flash 挂不上。

  rtu_config.cfg：
    [uart.2] pin_map=1     把 UART2 从默认脚挪到另一组（map1：pad 21/22）
    [lua] print_route=uart2    Lua print 改走 UART2（已经挪开的那组）
          log_route=uart2      log 也走 UART2

  日志请接 remap 之后的 UART2，不要再看原来的 UART2 默认脚。

  ----------------------------------------------------------------------------
  http.save.lfs(fs, path)
  ----------------------------------------------------------------------------
    fs    lfs.mount 返回的已挂载对象
    path  LittleFS 路径，如 "/demo.bin"
    落到 Flash，不把整包变成 Lua 字符串。resp.body 为空，body_len 仍有效。

  读：fs:open(path, "r") → f:read(100) → f:close()
    每次从 Flash 抽一片，不是 ublob 那种整包挂内存的 view。
    大文件也按块处理，Lua 堆只占当前这一片。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link
    2) flash.init：整片 lfs.mount；已有文件系统直接挂。空片默认不整区预擦。
    3) 下载 https://www.baidu.com/ 到 /demo.bin
    4) 每次读 100 字节，用 [] 包起来打印

]=]