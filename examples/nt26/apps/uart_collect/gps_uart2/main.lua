--[=[
  gps_uart2 demo — UART3 GPS
  ============================================================================
  回调 / gps.fix() 都是同一张快照 ev。屏蔽后对应子表为 nil。
  空字段是 nil。time = { hour, min, sec }，date = { day, month, year }。
  每句子表另有：type, talker, msgid；keep_raw 时还有 raw / fields（GSV 拼包后无 msgid/fields）。

  ev = {
    updated = "rmc",          -- 本包主更新：有 RMC 就是 rmc。一包只进一次回调
    lat, lon, valid,          -- 地图快捷：RMC 优先，否则 GGA / GNS
    raw,                      -- 本包原始 UART 数据；keep_raw 关闭则为 nil

    rmc = {                   -- $GxRMC
      valid, status,          -- status "A"/"V"；valid = (status=="A")
      lat, lon, speed_kn, speed_kmh, course, mode,
      time, date,
    },
    gga = {                   -- $GxGGA
      valid,                  -- quality > 0
      lat, lon, alt, geoid, age,
      quality, sats,          -- sats 是可见用于定位的颗数（number）
      hdop, time,
    },
    gns = {                   -- $GxGNS
      valid, lat, lon, alt, mode, sats, hdop, time,
    },
    gsa = {                   -- $GxGSA
      fix_select, fix_type,   -- "M"/"A"；1 无 2 2D 3 3D
      sats,                   -- PRN 数组 { 12, 24, ... }
      pdop, hdop, vdop, system_id,
    },
    gsv = {                   -- $GxGSV，多包已拼进 sats
      total, in_view, talker, raw,
      sats = { { prn, elev, az, snr }, ... },
    },
    gll = { valid, lat, lon, status, mode, time },
    vtg = { course_t, course_m, speed_kn, speed_kmh, mode },
    zda = { time, day, month, year, tz_hour, tz_min },
    gst = { time, rms, smjr, smin, orient, lat_err, lon_err, alt_err },
    txt = { total, msg, id, text },
    ack = { cmd, flag },      -- PMTK001
  }

  接线（NT26-PRO UART3 出厂 pin_map=0）
    GPS TX → 模块 RX PIN 53（LCD_CLK）
    GPS RX → 模块 TX PIN 52（LCD_CS）（只收数可以不接；要配模组必须接）
]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local gps = require("gps")

local BAUD = 9600
-- true：原句挂 ev.raw，在同一个回调里打；产品里改 false
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
        log.info("fix lat=%.6f lon=%.6f alt=%s kmh=%s sats=%s hdop=%s rmc=%s",
                 ev.lat, ev.lon,
                 tostring(gga and gga.alt),
                 tostring(rmc and rmc.speed_kmh),
                 tostring(gga and gga.sats),
                 tostring(gga and gga.hdop),
                 tostring(rmc and rmc.valid))
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

-- 可选：本地屏蔽 +（proto≠none 时）源头关输出
-- gps.set_sentences({ gsv = 0 })
-- gps.set_rate(gps.RATE_MS.HZ_1)

log.info("gps uart=%d baud=%d keep_raw=%s", uart.UART3, BAUD, tostring(KEEP_RAW))

while true do
    rt.delay(10000)
end

--[=[
  gps.open(opts)
    opts.uart / opts.baud / opts.proto("none"|"auto"|"pmtk"|"pcas")
    opts.keep_raw   true 才把本次原句挂到 ev.raw
    opts.auto_reg

  回调都收到同一张 ev（结构见文件头；不要长期攥着改）
    gps.reg(cb)
    gps.on("fix", cb)     本包含 RMC/GGA/GNS 时一次（和 gps.reg 是另一次登记）
    gps.on("rmc", cb)     以及 "gga" / "gsv" / "gsa" / ...

  gps.keep_raw(true|false)
  gps.set_sentences({ rmc=1, gga=1, gsv=0 })  整数 0=屏蔽
  gps.fix()  当前快照
]=]
