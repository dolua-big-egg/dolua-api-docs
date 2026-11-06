-- gps_uart2: 用固件内置 gps 收 NMEA，不在工程里再放一份 gps.lua。
-- 一包串口进一次回调，参数是一张表，没有按句子拆开的子表。
-- 还没收到的字段是 nil，日志里打成 - 。quality 收到后 0 是真值（未定位）。
-- quality 交给脚本判断，模块不丢估算点：
--   0 未定位，1 单点，2 差分，4/5 为 RTK，6 为估算（推算）。
--   不要估算坐标时，自己判断 quality == 6。
-- 接线（NT26-PRO UART3 出厂 pin_map=0）
--   GPS TX -> 模块 RX PIN 53（LCD_CLK）
--   GPS RX -> 模块 TX PIN 52（LCD_CS），只收数可以不接
-- 回调里只打日志，不要 rt.delay。

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local info = require("info")
local gps = require("gps")

local BAUD = 9600
-- true 时 ev.raw 是本包 UART 原文，最长 1024 字节。
local KEEP_RAW = true
-- 测试 IO：改成 false 即不配置。GPIO32 输出高，GPIO28 输出低。
-- 电平用 true/false。这个接口里数字 0 也算真，写成 0 会变成高。
local IO_TEST = true
-- 句柄留在这里，避免被回收后电平丢掉。
local io32, io28

-- 空字段打成 -，避免和数值 0 混在一起。
local function txt(v)
    if v == nil then
        return "-"
    end
    return tostring(v)
end

local function num(v, fmt)
    if v == nil then
        return "-"
    end
    return string.format(fmt, v)
end

-- time = { hour, min, sec }，卫星时间，不是开机毫秒。
local function clock(t)
    if not t then
        return "-"
    end
    return string.format("%02d:%02d:%05.2f", t.hour or 0, t.min or 0, t.sec or 0)
end

-- date = { day, month, year }。
local function ymd(d)
    if not d then
        return "-"
    end
    return string.format("%04d-%02d-%02d", d.year or 0, d.month or 0, d.day or 0)
end

-- 本包更新了定位句（RMC / GGA / GNS）才进来。valid 为 false 也会进。
-- 坐标只一份：有 RMC 用 RMC，否则 GGA，再否则 GNS。
local function on_gps(ev)
    -- valid     定位句是否有效
    -- lat/lon   十进制度
    -- quality   只来自 GGA
    -- alt       海拔，米。GGA，没有则 GNS
    log.info("valid=%s lat=%s lon=%s quality=%s alt=%s",
             txt(ev.valid),
             num(ev.lat, "%.6f"),
             num(ev.lon, "%.6f"),
             txt(ev.quality),
             num(ev.alt, "%.1f"))
    -- speed_kmh / course  公里每小时、航向角。RMC 没有时用 VTG
    -- time / date          优先 RMC，否则 ZDA；时间再否则用 GGA / GNS
    log.info("kmh=%s course=%s time=%s date=%s",
             num(ev.speed_kmh, "%.2f"),
             num(ev.course, "%.1f"),
             clock(ev.time),
             ymd(ev.date))
    -- sats_used  参与解算的颗数。GGA，没有则 GNS。不是下面 sats 的长度
    -- hdop       水平精度。GGA，没有则 GNS
    -- fix_type   1 未定位，2 为 2D，3 为 3D。来自 GSA
    -- pdop/vdop  综合精度、垂直精度。有 GN 合解时用合解
    -- antenna    仅含 ANTENNA 的文本，例如 ANTENNA OK
    log.info("sats_used=%s hdop=%s fix_type=%s pdop=%s vdop=%s antenna=%s",
             txt(ev.sats_used),
             num(ev.hdop, "%.2f"),
             txt(ev.fix_type),
             num(ev.pdop, "%.2f"),
             num(ev.vdop, "%.2f"),
             txt(ev.antenna))
    -- sats 不是句子，是 GSV 拼出来的可见星，最多 32 颗。
    -- 同一系统新一轮的第 1 条只清这个系统，GP 和 BD 会同时留着。
    -- sys 系统标记（GP / BD / GN），prn 星号，elev 仰角，az 方位，snr 信噪比。
    local n = 0
    if ev.sats then
        n = #ev.sats
    end
    log.info("sats_n=%d", n)
    -- for i = 1, n do
    --     local s = ev.sats[i]
    --     log.info("sat %d sys=%s prn=%s elev=%s az=%s snr=%s",
    --              i, txt(s.sys), txt(s.prn), txt(s.elev), txt(s.az), txt(s.snr))
    -- end
    -- 本包串口原文。超过 1024 字节会被截断。
    if ev.raw then
        log.info("raw=%s", ev.raw)
    else
        log.info("raw=-")
    end
end

if IO_TEST then
    local gpio = require("gpio")
    io32 = gpio.open(gpio.BY_GPIO, 32)
    io28 = gpio.open(gpio.BY_GPIO, 28)
    io32:config(true, true)
    io28:config(true, false)
    log.info("io test gpio32=1 gpio28=0")
end

-- "fix"：本包更新了定位句才回调。改成 "all" 则任意解析成功的句子都回调。
-- 句子名（rmc、gga、gsv）不能当登记参数。
gps.on("fix", on_gps)

gps.open({
    uart = uart.UART2,
    baud = BAUD,
    -- none：不向芯片发输出配置命令，只解析进来的 NMEA。
    proto = gps.PROTO_NONE,
    keep_raw = KEEP_RAW,
    -- 固件自己登记串口。不要在回调里再 gps.datain。
    auto_reg = true,
})

log.info("gps uart=%d baud=%d keep_raw=%s", uart.UART3, BAUD, tostring(KEEP_RAW))

-- heard 看的是校验通过的 NMEA 有没有来过，以及最近一次的开机毫秒。
-- 空的 gps.fix() 不能区分「串口没接上」和「在吐数但还没定位」。
while true do
    local ok, ms = gps.heard()
    if not ok then
        log.info("no nmea")
    else
        log.info("nmea age_ms=%d", info.tick_ms() - ms)
    end
    rt.delay(10000)
end
