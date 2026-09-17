--[[
  nmea — NMEA-0183 解析（原生 Lua，语义对齐 minmea）
  ============================================================================
  不做 C 结构体移植。校验、talker、字段拆分和常用句型与 minmea 同类。

  支持：$GxRMC $GxGGA $GxGSA $GxGSV $GxGLL $GxVTG $GxZDA $GxGST $GxGNS $GxTXT
  talker 不限 GP/GN/GL/GA/GB/BD/GQ。专有句（PMTK / PCAS）只拆字段，type=原句名。

  feed() 可重入攒行；datain 路径请保持短（完整行才 parse）。
]]

local M = {}

local buf = ""
local BUF_MAX = 1024

local function xor8(s)
    local cs = 0
    for i = 1, #s do
        cs = cs ~ s:byte(i)
    end
    return cs
end

local function split_csv(s)
    local t = {}
    local i = 1
    local n = #s
    while true do
        local j = s:find(",", i, true)
        if not j then
            t[#t + 1] = s:sub(i)
            break
        end
        t[#t + 1] = s:sub(i, j - 1)
        i = j + 1
        if i > n + 1 then
            t[#t + 1] = ""
            break
        end
    end
    return t
end

local function num(s)
    if s == nil or s == "" then
        return nil
    end
    return tonumber(s)
end

local function coord(v, hemi)
    local n = num(v)
    if n == nil or hemi == nil or hemi == "" then
        return nil
    end
    local deg = math.floor(n / 100)
    local d = deg + (n - deg * 100) / 60.0
    if hemi == "S" or hemi == "W" then
        d = -d
    end
    return d
end

local function nmea_time(s)
    if s == nil or #s < 6 then
        return nil
    end
    return {
        hour = tonumber(s:sub(1, 2)),
        min = tonumber(s:sub(3, 4)),
        sec = tonumber(s:sub(5)),
    }
end

local function nmea_date(s)
    if s == nil or #s < 6 then
        return nil
    end
    return {
        day = tonumber(s:sub(1, 2)),
        month = tonumber(s:sub(3, 4)),
        year = 2000 + (tonumber(s:sub(5, 6)) or 0),
    }
end

function M.checksum(body)
    return xor8(body)
end

function M.frame(body)
    return string.format("$%s*%02X\r\n", body, xor8(body))
end

local function parse_rmc(f, ev)
    ev.time = nmea_time(f[2])
    ev.status = f[3]
    ev.valid = (f[3] == "A")
    ev.lat = coord(f[4], f[5])
    ev.lon = coord(f[6], f[7])
    ev.speed_kn = num(f[8])
    ev.course = num(f[9])
    ev.date = nmea_date(f[10])
    ev.mode = f[12]
    if ev.speed_kn then
        ev.speed_kmh = ev.speed_kn * 1.852
    end
end

local function parse_gga(f, ev)
    ev.time = nmea_time(f[2])
    ev.lat = coord(f[3], f[4])
    ev.lon = coord(f[5], f[6])
    ev.quality = num(f[7]) or 0
    ev.sats = num(f[8])
    ev.hdop = num(f[9])
    ev.alt = num(f[10])
    ev.geoid = num(f[12])
    ev.age = num(f[14])
    ev.valid = (ev.quality ~= nil and ev.quality > 0)
end

local function parse_gns(f, ev)
    ev.time = nmea_time(f[2])
    ev.lat = coord(f[3], f[4])
    ev.lon = coord(f[5], f[6])
    ev.mode = f[7]
    ev.sats = num(f[8])
    ev.hdop = num(f[9])
    ev.alt = num(f[10])
    ev.valid = (ev.mode ~= nil and ev.mode ~= "" and ev.mode ~= "N")
end

local function parse_gsa(f, ev)
    ev.fix_select = f[2]
    ev.fix_type = num(f[3])
    local sats = {}
    for i = 4, 15 do
        local id = num(f[i])
        if id then
            sats[#sats + 1] = id
        end
    end
    ev.sats = sats
    ev.pdop = num(f[16])
    ev.hdop = num(f[17])
    ev.vdop = num(f[18])
    ev.system_id = num(f[19])
end

local function parse_gsv(f, ev)
    ev.total = num(f[2])
    ev.msg = num(f[3])
    ev.in_view = num(f[4])
    local sats = {}
    local i = 5
    while i + 3 <= #f do
        sats[#sats + 1] = {
            prn = num(f[i]),
            elev = num(f[i + 1]),
            az = num(f[i + 2]),
            snr = num(f[i + 3]),
        }
        i = i + 4
    end
    ev.sats = sats
end

local function parse_gll(f, ev)
    ev.lat = coord(f[2], f[3])
    ev.lon = coord(f[4], f[5])
    ev.time = nmea_time(f[6])
    ev.status = f[7]
    ev.mode = f[8]
    ev.valid = (f[7] == "A")
end

local function parse_vtg(f, ev)
    ev.course_t = num(f[2])
    ev.course_m = num(f[4])
    ev.speed_kn = num(f[6])
    ev.speed_kmh = num(f[8])
    ev.mode = f[10]
end

local function parse_zda(f, ev)
    ev.time = nmea_time(f[2])
    ev.day = num(f[3])
    ev.month = num(f[4])
    ev.year = num(f[5])
    ev.tz_hour = num(f[6])
    ev.tz_min = num(f[7])
end

local function parse_gst(f, ev)
    ev.time = nmea_time(f[2])
    ev.rms = num(f[3])
    ev.smjr = num(f[4])
    ev.smin = num(f[5])
    ev.orient = num(f[6])
    ev.lat_err = num(f[7])
    ev.lon_err = num(f[8])
    ev.alt_err = num(f[9])
end

local function parse_txt(f, ev)
    ev.total = num(f[2])
    ev.msg = num(f[3])
    ev.id = num(f[4])
    ev.text = f[5] or ""
end

local HAND = {
    RMC = parse_rmc,
    GGA = parse_gga,
    GNS = parse_gns,
    GSA = parse_gsa,
    GSV = parse_gsv,
    GLL = parse_gll,
    VTG = parse_vtg,
    ZDA = parse_zda,
    GST = parse_gst,
    TXT = parse_txt,
}

function M.parse(line)
    if type(line) ~= "string" or #line < 6 or line:byte(1) ~= 36 then
        return nil
    end
    local star = line:find("*", 2, true)
    if not star or star + 2 > #line then
        return nil
    end
    local body = line:sub(2, star - 1)
    local got = tonumber(line:sub(star + 1, star + 2), 16)
    if got == nil or xor8(body) ~= got then
        return nil
    end
    local f = split_csv(body)
    local msgid = f[1] or ""
    local talker, typ
    if #msgid >= 5 and msgid:sub(1, 1) ~= "P" then
        talker = msgid:sub(1, 2)
        typ = msgid:sub(3)
    else
        talker = "P"
        typ = msgid
    end
    local ev = {
        type = typ,
        talker = talker,
        msgid = msgid,
        raw = line,
        fields = f,
    }
    local fn = HAND[typ]
    if fn then
        fn(f, ev)
    elseif typ == "PMTK001" then
        ev.type = "ack"
        ev.cmd = num(f[2])
        ev.flag = num(f[3])
    end
    return ev
end

function M.reset()
    buf = ""
end

function M.feed(chunk)
    if type(chunk) ~= "string" or #chunk == 0 then
        return {}
    end
    buf = buf .. chunk
    if #buf > BUF_MAX then
        buf = buf:sub(-256)
    end
    local out = {}
    while true do
        local a = buf:find("\n", 1, true)
        if not a then
            break
        end
        local line = buf:sub(1, a - 1)
        buf = buf:sub(a + 1)
        if #line > 0 and line:byte(#line) == 13 then
            line = line:sub(1, -2)
        end
        local ev = M.parse(line)
        if ev then
            out[#out + 1] = ev
        elseif #line > 0 then
            out[#out + 1] = { type = "bad", raw = line }
        end
    end
    return out
end

return M
