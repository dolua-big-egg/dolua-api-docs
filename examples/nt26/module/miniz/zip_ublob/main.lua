--[=[
  zip_ublob demo — 从 ublob 打开 data.zip，列出成员并整份打印
  ============================================================================
    内置文件系统勾选 data.zip，存储位置 blob。下载后名字就是 ublob 的 "data.zip"。
    zip.open({ ublob = name }) 会把整包明文读进堆再按偏移解。
    本包只有 data.txt，明文约 33KB，没过 extract 的 64KB 上限，一次解成 string。
    正文用 uart.sync_write 按 1024 字节送出。同步发送不进 32KB 异步环，
    这一段进移位寄存器后才返回，切口可以落在任意字节上。
]=]

local rt = require("rt")
local log = require("log")
local zip = require("zip")
local uart = require("uart")

local NAME = "data.zip"
local OUT_UART = uart.UART1
local WRITE_CHUNK = 1024

local function write_body(s)
    local n = #s
    local i = 1
    while i <= n do
        local j = i + WRITE_CHUNK - 1
        if j > n then
            j = n
        end
        local ok = uart.sync_write(OUT_UART, s:sub(i, j))
        if not ok then
            return false
        end
        i = j + 1
    end
    return true
end

local function method_name(m)
    if m == zip.STORE then
        return "store"
    end
    if m == zip.DEFLATE then
        return "deflate"
    end
    return tostring(m)
end

local function halt(msg)
    log.error("%s", msg)
    while true do
        rt.delay(10000)
    end
end

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

local z, err = zip.open({ ublob = NAME })
if not z then
    halt("zip.open fail: " .. tostring(err))
end

local n, nerr = z:count()
if not n then
    z:close()
    halt("count fail: " .. tostring(nerr))
end
log.info("zip %s members=%d", NAME, n)

for i = 1, n do
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
            local body, berr = z:extract(i)
            if not body then
                log.error("[%d] extract fail: %s", i, tostring(berr))
            else
                log.info("[%d] ----- %s begin -----", i, st.name)
                if not write_body(body) then
                    log.error("[%d] sync_write fail", i)
                end
                log.info("[%d] ----- %s end -----", i, st.name)
                log_mem("after_write")
            end
        end
    end
end

z:close()
log.info("zip closed")
collectgarbage("collect")
log_mem("after_close")

while true do
    rt.delay(10000)
end
