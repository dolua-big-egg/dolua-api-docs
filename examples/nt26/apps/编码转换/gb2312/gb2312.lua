--[=[
  gb2312 — UTF-8 与 GB2312 互转（外置模块）
  ============================================================================
  码表是 ublob 里的 gb2312.bin，由同目录的 gb2312.html 离线生成。
  open 用 buf.load 把明文载入字节缓冲，不进 Lua 的 700KB 堆。
  先 open 再多次转换，表一直留着；不 open 则每次转换自己加载、转完关掉。

  文件头 32 字节，小端：
    0   "GB23"
    4   版本 u16，现在是 1
    6   gb2u_kind u16：0 没有，1 稠密表，2 按 GB 码排序的记录
    8   收录字数 u32
    12  gb2u 起始偏移 u32
    16  gb2u 条数或槽数 u32
    20  u2gb 起始偏移 u32
    24  u2gb 条数 u32
    28  保留 u32，写 0
  排序记录每条 4 字节：键 u16，值 u16。
  GB 码是 (b1 << 8) | b2，写出去时先高字节再低字节。
  稠密表下标 (b1 - 0xA1) * 94 + (b2 - 0xA1)，槽里是 Unicode，0 表示空位。
  字数达到 4090 时生成器才用稠密表。

  表里没有的字、以及坏掉的字节，换成 "?"。
  0x00–0x7F 两边相同，不查表。
]=]

local buf = require("buf")

local M = {}

local HDR = 32
local DEFAULT = "gb2312.bin"
local REPL = "?"

local map
local temp = false

local function fits(size, off, count, stride)
    if count == 0 then
        return true
    end
    if off < HDR or off > size then
        return false
    end
    local bytes = count * stride
    if off + bytes > size then
        return false
    end
    return true
end

local function parse(b)
    if b:size() < HDR then
        return nil, "bad record"
    end
    if b:string(0, 4) ~= "GB23" then
        return nil, "bad record"
    end
    if b:u16(4) ~= 1 then
        return nil, "bad record"
    end
    local kind = b:u16(6)
    if kind ~= 0 and kind ~= 1 and kind ~= 2 then
        return nil, "bad record"
    end
    local hdr = {
        kind = kind,
        count = b:u32(8),
        gb2u_off = b:u32(12),
        gb2u_count = b:u32(16),
        u2gb_off = b:u32(20),
        u2gb_count = b:u32(24),
    }
    local size = b:size()
    local stride = kind == 1 and 2 or 4
    if kind ~= 0 and not fits(size, hdr.gb2u_off, hdr.gb2u_count, stride) then
        return nil, "bad record"
    end
    if not fits(size, hdr.u2gb_off, hdr.u2gb_count, 4) then
        return nil, "bad record"
    end
    return hdr
end

function M.open(name)
    if map then
        return true
    end
    if name == nil then
        name = DEFAULT
    end
    if type(name) ~= "string" or name == "" then
        return nil, "invalid param"
    end
    local b, err = buf.load(name)
    if not b then
        return nil, err
    end
    local hdr, herr = parse(b)
    if not hdr then
        b:close()
        return nil, herr
    end
    hdr.b = b
    hdr.name = name
    map = hdr
    return true
end

function M.close()
    if map then
        map.b:close()
        map = nil
    end
    temp = false
    return true
end

function M.is_open()
    return map ~= nil
end

function M.info()
    if not map then
        return nil, "closed"
    end
    return {
        name = map.name,
        count = map.count,
        kind = map.kind,
        size = map.b:size(),
        gb2u = map.gb2u_count,
        u2gb = map.u2gb_count,
    }
end

local function ensure()
    if map then
        return true
    end
    local ok, err = M.open(DEFAULT)
    if not ok then
        return nil, err
    end
    temp = true
    return true
end

local function release_temp()
    if temp then
        M.close()
    end
end

local function lookup_u(cp)
    if map.u2gb_count == 0 then
        return nil
    end
    local i, err = map.b:search_u16(map.u2gb_off, 4, map.u2gb_count, cp)
    if i == nil then
        if err ~= "not found" then
            return nil, err
        end
        return nil
    end
    local v, verr = map.b:u16(map.u2gb_off + i * 4 + 2)
    if v == nil then
        return nil, verr
    end
    return v
end

local function lookup_gb(gb)
    if map.kind == 1 then
        local b1 = gb >> 8
        local b2 = gb & 0xFF
        if b1 < 0xA1 or b1 > 0xF7 or b2 < 0xA1 or b2 > 0xFE then
            return nil
        end
        local idx = (b1 - 0xA1) * 94 + (b2 - 0xA1)
        if idx >= map.gb2u_count then
            return nil
        end
        local v, verr = map.b:u16(map.gb2u_off + idx * 2)
        if v == nil then
            return nil, verr
        end
        if v == 0 then
            return nil
        end
        return v
    end
    if map.kind ~= 2 or map.gb2u_count == 0 then
        return nil
    end
    local i, err = map.b:search_u16(map.gb2u_off, 4, map.gb2u_count, gb)
    if i == nil then
        if err ~= "not found" then
            return nil, err
        end
        return nil
    end
    local v, verr = map.b:u16(map.gb2u_off + i * 4 + 2)
    if v == nil then
        return nil, verr
    end
    return v
end

local function emit_utf8(out, cp)
    if cp < 0x80 then
        return out:append_u8(cp)
    end
    if cp < 0x800 then
        local ok, err = out:append_u8(0xC0 | (cp >> 6))
        if not ok then
            return nil, err
        end
        return out:append_u8(0x80 | (cp & 0x3F))
    end
    local ok, err = out:append_u8(0xE0 | (cp >> 12))
    if not ok then
        return nil, err
    end
    ok, err = out:append_u8(0x80 | ((cp >> 6) & 0x3F))
    if not ok then
        return nil, err
    end
    return out:append_u8(0x80 | (cp & 0x3F))
end

local function decode_utf8(s, i)
    local n = #s
    local b1 = string.byte(s, i)
    if b1 < 0x80 then
        return b1, i + 1
    end
    if b1 < 0xC2 or b1 > 0xEF then
        return nil, i + 1
    end
    if b1 < 0xE0 then
        if i + 1 > n then
            return nil, i + 1
        end
        local b2 = string.byte(s, i + 1)
        if b2 < 0x80 or b2 > 0xBF then
            return nil, i + 1
        end
        local cp = ((b1 & 0x1F) << 6) | (b2 & 0x3F)
        if cp < 0x80 then
            return nil, i + 1
        end
        return cp, i + 2
    end
    if i + 2 > n then
        return nil, i + 1
    end
    local b2 = string.byte(s, i + 1)
    local b3 = string.byte(s, i + 2)
    if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then
        return nil, i + 1
    end
    if b1 == 0xE0 and b2 < 0xA0 then
        return nil, i + 1
    end
    if b1 == 0xED and b2 >= 0xA0 then
        return nil, i + 1
    end
    local cp = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
    if cp < 0x800 or cp > 0xFFFF then
        return nil, i + 1
    end
    return cp, i + 3
end

local function abort(out, err)
    out:close()
    release_temp()
    return nil, err
end

local function finish(out)
    local text, err = out:string()
    out:close()
    release_temp()
    if text == nil then
        return nil, err
    end
    return text
end

function M.to_gb2312(s)
    if type(s) ~= "string" then
        return nil, "invalid param"
    end
    local ok, err = ensure()
    if not ok then
        return nil, err
    end
    local out, oerr = buf.alloc(#s)
    if not out then
        release_temp()
        return nil, oerr
    end
    local i = 1
    local n = #s
    while i <= n do
        local cp, nxt = decode_utf8(s, i)
        i = nxt
        if cp == nil or cp > 0x7F then
            local gb, lerr = nil, nil
            if cp ~= nil then
                gb, lerr = lookup_u(cp)
            end
            if lerr then
                return abort(out, lerr)
            end
            if gb then
                local a, e = out:append_u8(gb >> 8)
                if not a then
                    return abort(out, e)
                end
                a, e = out:append_u8(gb & 0xFF)
                if not a then
                    return abort(out, e)
                end
            else
                local a, e = out:append(REPL)
                if not a then
                    return abort(out, e)
                end
            end
        else
            local a, e = out:append_u8(cp)
            if not a then
                return abort(out, e)
            end
        end
    end
    return finish(out)
end

function M.to_utf8(s)
    if type(s) ~= "string" then
        return nil, "invalid param"
    end
    local ok, err = ensure()
    if not ok then
        return nil, err
    end
    local n = #s
    local out, oerr = buf.alloc(n + (n >> 1))
    if not out then
        release_temp()
        return nil, oerr
    end
    local i = 1
    while i <= n do
        local b1 = string.byte(s, i)
        if b1 < 0x80 then
            local a, e = out:append_u8(b1)
            if not a then
                return abort(out, e)
            end
            i = i + 1
        elseif i == n then
            local a, e = out:append(REPL)
            if not a then
                return abort(out, e)
            end
            i = i + 1
        else
            local b2 = string.byte(s, i + 1)
            local cp, lerr = lookup_gb((b1 << 8) | b2)
            if lerr then
                return abort(out, lerr)
            end
            i = i + 2
            local a, e
            if cp then
                a, e = emit_utf8(out, cp)
            else
                a, e = out:append(REPL)
            end
            if not a then
                return abort(out, e)
            end
        end
    end
    return finish(out)
end

return M
