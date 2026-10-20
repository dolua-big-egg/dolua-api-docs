--[=[
  zip_stream — 假装外部 Flash，让 zip 按偏移来要数据，再一段段解开
  ============================================================================
  下载：内置文件系统勾选 data.zip，存储位置 blob。设备上的名字就是 "data.zip"。
  包里是《剑来》前二十章，用来看流式解开后的正文。

  两条数据，方向相反：

    Flash 侧（压缩包，还没解）
      ublob.open 先把整包明文放进 view，一直留到 view:close()。
      ublob 落盘是压缩的，没有「只读文件中间某一段、其余留在盘上」的接口，
      所以这里只能整包进 view，再用 view:read(偏移, 长度) 假装 Flash 按址读取。
      zip 自己不保存这份整包。它只要字节时调用 read(ofs, n)，
      ofs 是从文件头算的绝对偏移，不是「接着上次往下读」。

    明文侧（已经解开的章节）
      z:reader 每次最多吐 READ_CHUNK 字节明文。
      这一块用 uart.sync_write 送完就可以丢掉，不用攒成一整章 string。
      sync_write 会占住 Lua 线程直到这一段进移位寄存器，系统喂狗线程插不进来，
      所以每送出一块就 sys.wdt_kick()。
      解压耗时只包住 r:read，用 info.tick_ms()（开机毫秒，精度是系统 tick）。
      发送不计入。每章打一行，全部结束后再打平均每次的毫秒和对应字节。

  zip.open 返回之前就会多次调用 read：先读文件尾找目录，再把中央目录读进来。
  之后 z:reader 解某一章，才按那一章的偏移继续要压缩字节。
  读回调里不要打日志，日志和正文走同一串口，会插进正文。
]=]

local rt = require("rt")
local log = require("log")
local zip = require("zip")
local uart = require("uart")
local ublob = require("ublob")
local sys = require("sys")
local info = require("info")

local NAME = "data.zip"
local OUT_UART = uart.UART1
-- 每次向解压器要的明文长度，也是一次 sync_write 的长度。比 10KB 密，喂狗不用再卡字节数。
local READ_CHUNK = 1024

-- read 回调被调用的次数。打开阶段和每章解开阶段分开记，方便看 miniz 要了几次数据。
local flash_pulls = 0

-- 全部成功的 r:read：次数、明文总字节、耗时总毫秒。均值在最后算。
local stat_n = 0
local stat_bytes = 0
local stat_ms = 0

-- zip.STORE = 0 原样存放，zip.DEFLATE = 8 压缩。别的方法这套库解不了。
local function method_name(m)
    if m == zip.STORE then
        return "store"
    end
    if m == zip.DEFLATE then
        return "deflate"
    end
    return tostring(m)
end

-- 打不开包就停在这里，避免后面空转着反复报错。
local function halt(msg)
    log.error("%s", msg)
    while true do
        rt.delay(10000)
    end
end

local function log_inflate(tag, count, bytes, ms)
    if count <= 0 then
        log.info("[inflate] %s count=0", tag)
        return
    end
    log.info("[inflate] %s count=%d bytes=%d ms=%d avg=%.2fms / %.1fB",
             tag, count, bytes, ms, ms / count, bytes / count)
end

-- used 是当前 Lua 堆，max 是这台虚拟机的配额上限，不是历史峰值。gc 是回收器眼里的 KB。
local function log_mem(tag)
    local used, maxb = rt.mem()
    local gc = collectgarbage("count")
    if not used or not maxb or maxb == 0 then
        log.info("[mem] %s used=%s max=%s gc=%.1fKB",
                 tag, tostring(used), tostring(maxb), gc)
        return
    end
    log.info("[mem] %s used=%d max=%d (%.1f%%) gc=%.1fKB",
             tag, used, maxb, used * 100 / maxb, gc)
end

-- view 上挂着整包明文，后面的 flash_read 都从这块内存里切。同时只能开一个 view。
local view, verr = ublob.open(NAME)
if not view then
    halt("ublob.open fail: " .. tostring(verr))
end

-- zip.open 需要知道包总长，目录在文件尾，它靠这个长度往回找。
local flash_size, szerr = view:size()
if not flash_size then
    view:close()
    halt("ublob size fail: " .. tostring(szerr))
end

-- miniz 的取数口。每次给出绝对偏移和长度，必须返回恰好 n 字节的 string。
-- 短了、类型不对、返回 nil，这一次读取会被当成失败。
-- 打开包、列目录、解某一章，都会进这个函数，而且偏移会跳，不要自己记一个读指针。
local function flash_read(ofs, n)
    flash_pulls = flash_pulls + 1
    local data, nread = view:read(ofs, n)
    if type(data) ~= "string" or nread ~= n then
        return nil
    end
    return data
end

-- 返回时中央目录已经在 zip 对象里。压缩正文仍通过 flash_read 按偏移去拿。
local z, zerr = zip.open({
    read = flash_read,
    size = flash_size,
})
if not z then
    view:close()
    halt("zip.open fail: " .. tostring(zerr))
end
log.info("zip %s size=%d open_pulls=%d", NAME, flash_size, flash_pulls)

-- 成员序号从 1 开始，含目录项。
local n, nerr = z:count()
if not n then
    z:close()
    view:close()
    halt("count fail: " .. tostring(nerr))
end
log.info("zip %s members=%d pulls=%d", NAME, n, flash_pulls)

for i = 1, n do
    -- comp_size 是这一成员的压缩长度，size 是解开后的明文长度。
    local st, serr = z:stat(i)
    if not st then
        log.error("stat %d fail: %s", i, tostring(serr))
    else
        log.info("[%d] %s method=%s comp=%d size=%d dir=%s",
                 st.index, st.name, method_name(st.method),
                 st.comp_size, st.size, tostring(st.dir))
        if st.dir then
            log.info("[%d] skip dir", i)
        else
            -- 同一时刻只能有一个 reader。它从这一章压缩数据的第一个字节开始顺序解。
            local r, rerr = z:reader(i)
            if not r then
                log.error("[%d] reader fail: %s", i, tostring(rerr))
            else
                local pulls_at_start = flash_pulls
                local ok_send = true
                local chap_n = 0
                local chap_bytes = 0
                local chap_ms = 0
                log.info("[%d] ----- %s begin -----", i, st.name)
                while true do
                    -- 正常返回一段明文。读完是 nil, "eof"。别的 nil 才是失败。
                    -- 只给 r:read 计时。后面的 sync_write 是串口时间，不放进解压统计。
                    local t0 = info.tick_ms()
                    local chunk, cerr = r:read(READ_CHUNK)
                    local dt = info.tick_ms() - t0
                    if not chunk then
                        if cerr ~= "eof" then
                            log.error("[%d] read fail: %s", i, tostring(cerr))
                            ok_send = false
                        end
                        break
                    end
                    chap_n = chap_n + 1
                    chap_bytes = chap_bytes + #chunk
                    chap_ms = chap_ms + dt
                    stat_n = stat_n + 1
                    stat_bytes = stat_bytes + #chunk
                    stat_ms = stat_ms + dt
                    -- 同步发送期间不让出。这一段进移位寄存器后才返回，切口可以落在任意字节上。
                    if not uart.sync_write(OUT_UART, chunk) then
                        log.error("[%d] sync_write fail", i)
                        ok_send = false
                        break
                    end
                    sys.wdt_kick()
                end
                r:close()
                if ok_send then
                    log.info("[%d] ----- %s end -----", i, st.name)
                end
                -- 这一章额外向 Flash 要了几次。正文长时会明显多于打开阶段。
                log.info("[%d] flash_pulls=%d", i, flash_pulls - pulls_at_start)
                log_inflate(string.format("[%d] %s", i, st.name), chap_n, chap_bytes, chap_ms)
                log_mem("after_write")
            end
        end
    end
end

-- 先关 zip 再关 view。关 view 之后 flash_read 就不能再切这块明文了。
z:close()
view:close()
log.info("zip closed pulls=%d", flash_pulls)
log_inflate("all", stat_n, stat_bytes, stat_ms)
collectgarbage("collect")
log_mem("after_close")

while true do
    rt.delay(10000)
end
