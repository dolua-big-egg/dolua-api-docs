--[=[
  gps_api demo — 内置 gps 模块（C 解析）
  ============================================================================
  一包 UART 一次回调。一张表：坐标 + 特色字段。keep_raw 才挂 ev.raw。

  ev = {
    valid, lat, lon,
    speed_kmh, course,
    time = { hour, min, sec },
    date = { day, month, year },
    alt, quality, sats_used, hdop,
    fix_type, pdop, vdop,
    sats = { { sys, prn, elev, az, snr }, ... },
    antenna,
    raw,
  }

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
    if ev.valid and ev.lat then
        log.info("fix lat=%.6f lon=%.6f alt=%s kmh=%s sats=%s hdop=%s",
                 ev.lat, ev.lon,
                 tostring(ev.alt),
                 tostring(ev.speed_kmh),
                 tostring(ev.sats_used),
                 tostring(ev.hdop))
        return
    end
    log.info("fix invalid valid=%s", tostring(ev.valid))
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
