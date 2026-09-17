--[[
  gps — UART GPS 快照
  ============================================================================
  回调 / gps.fix() 都是同一张 ev。屏蔽后对应子表为 nil。
  空字段是 nil。time = { hour, min, sec }，date = { day, month, year }。
  每句子表另有：type, talker, msgid；keep_raw 时还有 raw / fields。

  ev = {
    updated = "rmc",              -- 本包主更新：有 RMC 就是 rmc（一包只回调一次）
    lat, lon, valid,
    raw,                          -- 本包原始 UART 数据；keep_raw 关闭则为 nil
    rmc = { valid, status, lat, lon, speed_kn, speed_kmh, course, mode, time, date },
    gga = { valid, lat, lon, alt, geoid, age, quality, sats, hdop, time },
    gns = { valid, lat, lon, alt, mode, sats, hdop, time },
    gsa = { fix_select, fix_type, sats, pdop, hdop, vdop, system_id },
    gsv = { total, in_view, talker, raw, sats = { { prn, elev, az, snr }, ... } },
    gll = { valid, lat, lon, status, mode, time },
    vtg = { course_t, course_m, speed_kn, speed_kmh, mode },
    zda = { time, day, month, year, tz_hour, tz_min },
    gst = { time, rms, smjr, smin, orient, lat_err, lon_err, alt_err },
    txt = { total, msg, id, text },
    ack = { cmd, flag },
  }

  set_sentences({ gsv=0 })：本地不塞；proto 不是 none 时再改芯片输出。
  keep_raw：open({ keep_raw=true }) 或 gps.keep_raw(true)，才把原句挂到 ev.raw。
]]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")
local nmea = require("nmea")

local M = {
    UART = uart.UART2,
    PROTO_PMTK = "pmtk",
    PROTO_PCAS = "pcas",
    PROTO_AUTO = "auto",
    PROTO_NONE = "none",
    RATE_MS = {
        HZ_10 = 100,
        HZ_5 = 200,
        HZ_2 = 500,
        HZ_1 = 1000,
        S_2 = 2000,
        S_5 = 5000,
        S_10 = 10000,
    },
}

local TOPIC = "gps_evt"
local uart_id = uart.UART2
local proto = "none"
local started = false
local cbs_all = {}
local cbs_kind = {}
local last = {}
local allow = nil
local gsv_acc = nil
local keep_raw = false

local PCAS_BAUD = {
    [4800] = 0,
    [9600] = 1,
    [19200] = 2,
    [38400] = 3,
    [57600] = 4,
    [115200] = 5,
}

-- PMTK314：GLL RMC VTG GGA GSA GSV + 11 保留 + ZDA MCHN
local PMTK314_KEYS = { "gll", "rmc", "vtg", "gga", "gsa", "gsv" }
local NEST = {
    rmc = true, gga = true, gns = true, gsa = true, gsv = true,
    gll = true, vtg = true, zda = true, gst = true, txt = true,
    ack = true,
}

local function nest_key(typ)
    if typ == nil or typ == "bad" then
        return nil
    end
    if typ == "ack" then
        return "ack"
    end
    local k = string.lower(typ)
    if NEST[k] then
        return k
    end
    return nil
end

local function allowed(key)
    if allow == nil then
        return true
    end
    return allow[key] ~= false
end

local function refusion()
    local r, g, n = last.rmc, last.gga, last.gns
    last.lat, last.lon, last.valid = nil, nil, nil
    if r and r.lat ~= nil then
        last.lat = r.lat
    elseif g and g.lat ~= nil then
        last.lat = g.lat
    elseif n and n.lat ~= nil then
        last.lat = n.lat
    end
    if r and r.lon ~= nil then
        last.lon = r.lon
    elseif g and g.lon ~= nil then
        last.lon = g.lon
    elseif n and n.lon ~= nil then
        last.lon = n.lon
    end
    if r and r.valid ~= nil then
        last.valid = r.valid
    elseif g and g.valid ~= nil then
        last.valid = g.valid
    elseif n and n.valid ~= nil then
        last.valid = n.valid
    end
end

local function take_gsv(sent)
    local msg = sent.msg or 1
    local total = sent.total or 1
    if msg <= 1 or gsv_acc == nil then
        gsv_acc = {
            type = "GSV",
            talker = sent.talker,
            total = total,
            in_view = sent.in_view,
            sats = {},
            raw = sent.raw,
        }
    end
    local src = sent.sats or {}
    for i = 1, #src do
        gsv_acc.sats[#gsv_acc.sats + 1] = src[i]
    end
    gsv_acc.total = total
    gsv_acc.in_view = sent.in_view
    gsv_acc.talker = sent.talker
    gsv_acc.raw = sent.raw
    last.gsv = gsv_acc
    if msg >= total then
        gsv_acc = nil
    end
end

local function emit_snap(updated, seen)
    last.updated = updated
    local list = cbs_kind[updated]
    if list then
        for i = 1, #list do
            pcall(list[i], last)
        end
    end
    if seen.rmc or seen.gga or seen.gns then
        list = cbs_kind["fix"]
        if list then
            for i = 1, #list do
                pcall(list[i], last)
            end
        end
    end
    for i = 1, #cbs_all do
        pcall(cbs_all[i], last)
    end
end

local function apply_packet(list, chunk)
    local seen = {}
    local last_key = nil
    for i = 1, #list do
        local sent = list[i]
        local key = nest_key(sent.type)
        if key and allowed(key) then
            if key == "gsv" then
                take_gsv(sent)
            else
                last[key] = sent
            end
            if not keep_raw then
                local t = last[key]
                if t then
                    t.raw = nil
                    t.fields = nil
                end
            end
            seen[key] = true
            last_key = key
        end
    end
    if last_key == nil then
        return
    end
    if keep_raw then
        last.raw = chunk
    else
        last.raw = nil
    end
    refusion()
    local updated = last_key
    if seen.rmc then
        updated = "rmc"
    elseif seen.gns then
        updated = "gns"
    elseif seen.gga then
        updated = "gga"
    end
    emit_snap(updated, seen)
end

local function use_pmtk()
    return proto == "pmtk" or proto == "auto"
end

local function use_pcas()
    return proto == "pcas" or proto == "auto"
end

local function write_frame(body)
    local s = nmea.frame(body)
    log.info("gps tx %s", (s:gsub("[\r\n]", "")))
    return uart.write(uart_id, s)
end

local function worker()
    while true do
        local ok, msg = rt.mbox_recv(TOPIC)
        if ok and type(msg) == "table" then
            apply_packet(msg.list, msg.raw)
        end
    end
end

function M.datain(data)
    local list = nmea.feed(data)
    if #list == 0 then
        return
    end
    rt.mbox_send(TOPIC, { list = list, raw = data })
end

local function on_uart(_id, data, _meta)
    M.datain(data)
end

function M.on(kind, cb)
    if type(cb) ~= "function" then
        error("gps.on: callback required")
    end
    if kind == nil or kind == "all" then
        cbs_all[#cbs_all + 1] = cb
        return
    end
    if kind ~= "fix" then
        kind = string.lower(kind)
    end
    if cbs_kind[kind] == nil then
        cbs_kind[kind] = {}
    end
    local t = cbs_kind[kind]
    t[#t + 1] = cb
end

function M.reg(cb)
    M.on("all", cb)
end

function M.keep_raw(on)
    keep_raw = (on ~= false and on ~= 0)
    if not keep_raw then
        last.raw = nil
    end
    return keep_raw
end

function M.fix()
    return last
end

function M.send(body)
    return write_frame(body)
end

function M.set_rate(period_ms)
    period_ms = math.floor(tonumber(period_ms) or 1000)
    if period_ms < 100 then
        period_ms = 100
    elseif period_ms > 10000 then
        period_ms = 10000
    end
    if proto == "none" then
        return false
    end
    local ok = false
    if use_pmtk() then
        ok = write_frame("PMTK220," .. tostring(period_ms)) or ok
        rt.delay(80)
    end
    if use_pcas() then
        ok = write_frame("PCAS02," .. tostring(period_ms)) or ok
    end
    return ok
end

function M.set_sentences(en)
    en = en or {}
    if allow == nil then
        allow = {}
        for k in pairs(NEST) do
            allow[k] = true
        end
    end
    for k, v in pairs(en) do
        local on = math.floor(tonumber(v) or 0) ~= 0
        allow[k] = on
        if not on then
            last[k] = nil
            if k == "gsv" then
                gsv_acc = nil
            end
        end
    end
    refusion()
    local function n(k, d)
        local v = en[k]
        if v == nil then
            return d
        end
        return math.floor(tonumber(v) or 0)
    end
    if proto == "none" then
        return true
    end
    local ok = false
    if use_pmtk() then
        local f = {}
        for i = 1, #PMTK314_KEYS do
            f[i] = n(PMTK314_KEYS[i], 0)
        end
        if en.rmc == nil then
            f[2] = 1
        end
        if en.gga == nil then
            f[4] = 1
        end
        local t = { "PMTK314" }
        for i = 1, 6 do
            t[#t + 1] = tostring(f[i])
        end
        for _ = 1, 11 do
            t[#t + 1] = "0"
        end
        t[#t + 1] = tostring(n("zda", 0))
        t[#t + 1] = tostring(n("mchn", 0))
        ok = write_frame(table.concat(t, ",")) or ok
        rt.delay(80)
    end
    if use_pcas() then
        -- PCAS03: GGA GLL GSA GSV RMC VTG ZDA GST ...
        local body = string.format(
            "PCAS03,%d,%d,%d,%d,%d,%d,%d,%d,0,0,0,0,0",
            n("gga", 1), n("gll", 0), n("gsa", 0), n("gsv", 0),
            n("rmc", 1), n("vtg", 0), n("zda", 0), n("gst", 0)
        )
        ok = write_frame(body) or ok
    end
    return ok
end

function M.set_baud(baud)
    baud = math.floor(tonumber(baud) or 9600)
    local ok
    if proto == "pcas" then
        local idx = PCAS_BAUD[baud]
        if idx == nil then
            return false
        end
        ok = write_frame("PCAS01," .. tostring(idx))
    elseif proto == "none" then
        return false
    else
        ok = write_frame("PMTK251," .. tostring(baud))
    end
    rt.delay(200)
    uart.config(uart_id, { baudrate = baud })
    return ok
end

function M.hot_start()
    if proto == "pcas" then
        return write_frame("PCAS10,0")
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK101")
end

function M.warm_start()
    if proto == "pcas" then
        return write_frame("PCAS10,1")
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK102")
end

function M.cold_start()
    if proto == "pcas" then
        return write_frame("PCAS10,2")
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK103")
end

function M.factory_reset()
    if proto == "pcas" then
        return write_frame("PCAS10,3")
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK104")
end

function M.query_fw()
    if proto == "pcas" then
        return write_frame("PCAS06,0")
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK605")
end

-- PCAS04：1 GPS  2 BDS  3 GPS+BDS  5 GPS+GLO  7 GPS+BDS+GLO
function M.set_constellation(mode)
    mode = math.floor(tonumber(mode) or 3)
    if proto == "pcas" then
        return write_frame("PCAS04," .. tostring(mode))
    end
    if proto == "none" then
        return false
    end
    -- PMTK353,GPS,GLONASS,GALILEO,GALILEO_FULL,BEIDOU
    if mode == 1 then
        return write_frame("PMTK353,1,0,0,0,0")
    end
    if mode == 2 then
        return write_frame("PMTK353,0,0,0,0,1")
    end
    if mode == 5 then
        return write_frame("PMTK353,1,1,0,0,0")
    end
    if mode == 7 then
        return write_frame("PMTK353,1,1,0,0,1")
    end
    return write_frame("PMTK353,1,0,0,0,1")
end

function M.standby()
    if proto == "none" then
        return false
    end
    return write_frame("PMTK161,0")
end

function M.set_sbas(on)
    local v = 0
    if on ~= false and on ~= 0 then
        v = 1
    end
    if proto == "none" then
        return false
    end
    return write_frame("PMTK313," .. tostring(v))
end

function M.open(opts)
    opts = opts or {}
    uart_id = opts.uart or uart.UART2
    proto = opts.proto or "none"
    keep_raw = (opts.keep_raw == true)
    local baud = math.floor(tonumber(opts.baud) or 9600)
    nmea.reset()
    last = {}
    allow = nil
    gsv_acc = nil
    rtu.option("pass_up", false)
    rtu.option("pass_down", false)
    uart.config(uart_id, {
        baudrate = baud,
        data_bits = 8,
        stop_bits = 1,
        parity = 0,
        flow_control = 0,
    })
    if not started then
        rt.task_start(worker)
        started = true
    end
    if opts.auto_reg ~= false then
        uart.reg(uart_id, on_uart)
    end
    return true
end

function M.close()
    uart.unreg(uart_id)
end

return M
