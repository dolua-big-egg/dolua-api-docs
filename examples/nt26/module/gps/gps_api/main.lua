
--[=[
  gps_api demo — 内置 gps 模块（C 解析）
  ============================================================================
  一包 UART 一次回调。ev.lat / ev.lon / ev.valid 给地图；
  ev.rmc / ev.gga / … 按句取。keep_raw 才挂 ev.raw。

  接线（NT26-PRO UART3 出厂 pin_map=0）
    GPS TX → 模块 RX PIN 53（LCD_CLK）
    GPS RX → 模块 TX PIN 52（LCD_CS）（只收数可以不接）
]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local gps = require("gps")

local BAUD = 9600
local KEEP_RAW = false

local function on_gps(ev)
    if ev.raw then
        log.info("%s", ev.raw)
    end
    if ev.updated ~= "rmc" and ev.updated ~= "gga" and ev.updated ~= "gns" then
        return
    end
    local rmc = ev.rmc
    local gga = ev.gga
    if ev.valid and ev.lat then
        log.info("fix lat=%.6f lon=%.6f alt=%s kmh=%s sats=%s hdop=%s",
                 ev.lat, ev.lon,
                 tostring(gga and gga.alt),
                 tostring(rmc and rmc.speed_kmh),
                 tostring(gga and gga.sats),
                 tostring(gga and gga.hdop))
        return
    end
    log.info("fix invalid updated=%s", tostring(ev.updated))
end

gps.reg(on_gps)

gps.open({
    uart = uart.UART3,
    baud = BAUD,
    proto = gps.PROTO_NONE,
    keep_raw = KEEP_RAW,
    auto_reg = true,
})

-- gps.set_sentences({ gsv = 0 })
-- gps.set_rate(gps.RATE_MS.HZ_1)

log.info("gps uart=%d baud=%d keep_raw=%s", uart.UART3, BAUD, tostring(KEEP_RAW))

while true do
    rt.delay(10000)
end
