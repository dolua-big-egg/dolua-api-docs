--[[
  ssd1306 — 纯 Lua 的 SSD1306 OLED 驱动（走 i2c，不依赖 lcd）
  ============================================================================
  128×64 / 128×32 单色屏，I2C 7bit 地址默认 0x3C（有的板子 0x3D）。
  帧缓冲在本模块里，画点/线/方块/圆/文字只改 RAM；:flush() 才刷到屏。
  字库在 ssd1306_font.lua（ASCII 5x7 + 按需 12x12 汉字）。新增汉字改那个文件。

  用法：
    oled:text(34, 16, "doLua", 1, 2)
    oled:text(10, 36, "一行代码，万物互联", 1)
    oled:flush()

  像素色用整数 0=灭、1=亮。不要把数字 0 当成「开」（那是 gpio 布尔语义）。
]]

local font = require("ssd1306_font")

local M = {
    ADDR = 0x3C,
    WIDTH = 128,
    HEIGHT = 64,
    FONT_W = font.ASCII_W,
    FONT_H = font.ASCII_H,
    FONT_ADV = font.ASCII_ADV,
    FONT_CJK_W = font.CJK_W,
    FONT_CJK_H = font.CJK_H,
}

local CTRL_CMD = 0x00
local CTRL_DATA = 0x40
local PACK = 16
local FONT_FIRST = font.ASCII_FIRST
local FONT_LAST = font.ASCII_LAST
local FONT_COLS = font.ASCII_COLS
local FONT5x7 = font.ASCII
local FONT_CJK = font.CJK

local Dev = {}
Dev.__index = Dev

local function ink(color)
    if color == nil or color == false or color == 0 then
        return 0
    end
    return 1
end

-- 返回 codepoint, next_index。非法字节当 '?'(0x3F) 并前进 1。
local function utf8_next(s, i)
    local n = #s
    if i > n then
        return nil, i
    end
    local b = s:byte(i)
    if b < 0x80 then
        return b, i + 1
    end
    if b >= 0xF0 and i + 3 <= n then
        local b2, b3, b4 = s:byte(i + 1, i + 3)
        local cp = ((b & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F)
        return cp, i + 4
    end
    if b >= 0xE0 and i + 2 <= n then
        local b2, b3 = s:byte(i + 1, i + 2)
        local cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        return cp, i + 3
    end
    if b >= 0xC0 and i + 1 <= n then
        local b2 = s:byte(i + 1)
        local cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
        return cp, i + 2
    end
    return 0x3F, i + 1
end

local function blit_col(dev, x, y, bits, on)
    if x < 0 or x >= dev.width or bits == 0 or y >= dev.height then
        return
    end
    local w = dev.width
    local pages = dev.height // 8
    local fb = dev.fb
    local shift = y & 7
    local page = y >> 3
    local lo = (bits << shift) & 0xFF
    if page >= 0 and page < pages and lo ~= 0 then
        local idx = page * w + x + 1
        if on then
            fb[idx] = fb[idx] | lo
        else
            fb[idx] = fb[idx] & (lo ~ 0xFF)
        end
    end
    if shift == 0 then
        return
    end
    local hi = bits >> (8 - shift)
    local page2 = page + 1
    if hi ~= 0 and page2 >= 0 and page2 < pages then
        local idx = page2 * w + x + 1
        if on then
            fb[idx] = fb[idx] | hi
        else
            fb[idx] = fb[idx] & (hi ~ 0xFF)
        end
    end
end

local function pack_range(fb, i0, i1)
    local parts = {}
    local i = i0
    while i <= i1 do
        local j = i + PACK - 1
        if j > i1 then
            j = i1
        end
        parts[#parts + 1] = string.char(table.unpack(fb, i, j))
        i = j + 1
    end
    return table.concat(parts)
end

function M.new(bus, opts)
    if bus == nil then
        error("ssd1306.new: bus required")
    end
    opts = opts or {}
    local w = opts.width or M.WIDTH
    local h = opts.height or M.HEIGHT
    if w < 1 or w > 128 or h < 8 or h > 64 or (h % 8) ~= 0 then
        error("ssd1306.new: width 1..128, height 8..64 and multiple of 8")
    end
    local fb = {}
    local n = w * (h // 8)
    for i = 1, n do
        fb[i] = 0
    end
    return setmetatable({
        bus = bus,
        addr = opts.addr or M.ADDR,
        width = w,
        height = h,
        x_off = opts.x_off or 0,
        y_off = opts.y_off or 0,
        fb = fb,
    }, Dev)
end

function Dev:cmd(...)
    local n = select("#", ...)
    if n < 1 then
        return true
    end
    local t = { CTRL_CMD }
    for i = 1, n do
        t[i + 1] = select(i, ...) & 0xFF
    end
    return self.bus:write(self.addr, string.char(table.unpack(t)))
end

function Dev:init()
    local mux = self.height - 1
    local com_pins = 0x12
    if self.height <= 32 then
        com_pins = 0x02
    end
    -- 关显示 → 时钟/复用/偏移 → 电荷泵 → 页寻址 → SEG/COM → 对比度 → 开显示
    if not self:cmd(
        0xAE,
        0xD5, 0x80,
        0xA8, mux,
        0xD3, self.y_off & 0x3F,
        0x40,
        0x8D, 0x14,
        0x20, 0x02,
        0xA1, 0xC8,
        0xDA, com_pins,
        0x81, 0xCF,
        0xD9, 0xF1,
        0xDB, 0x40,
        0xA4,
        0xA6,
        0xAF
    ) then
        return false
    end
    self:fill(0)
    return self:flush()
end

function Dev:display(on)
    if on == false or on == 0 then
        return self:cmd(0xAE)
    end
    return self:cmd(0xAF)
end

function Dev:contrast(level)
    level = math.floor(tonumber(level) or 0)
    if level < 0 then
        level = 0
    elseif level > 255 then
        level = 255
    end
    return self:cmd(0x81, level)
end

function Dev:invert(on)
    if on == false or on == 0 then
        return self:cmd(0xA6)
    end
    return self:cmd(0xA7)
end

function Dev:all_on(on)
    if on == false or on == 0 then
        return self:cmd(0xA4)
    end
    return self:cmd(0xA5)
end

function Dev:fill(color)
    local v = 0
    if ink(color) == 1 then
        v = 0xFF
    end
    local fb = self.fb
    for i = 1, #fb do
        fb[i] = v
    end
end

function Dev:clear()
    self:fill(0)
    return self:flush()
end

function Dev:flush()
    local w = self.width
    local pages = self.height // 8
    local col = self.x_off & 0xFF
    local lo = col & 0x0F
    local hi = 0x10 | (col >> 4)
    local fb = self.fb
    for p = 0, pages - 1 do
        if not self:cmd(0xB0 | p, lo, hi) then
            return false
        end
        local i0 = p * w + 1
        local i1 = i0 + w - 1
        local i = i0
        while i <= i1 do
            local j = i + PACK - 1
            if j > i1 then
                j = i1
            end
            local payload = string.char(CTRL_DATA) .. pack_range(fb, i, j)
            if not self.bus:write(self.addr, payload) then
                return false
            end
            i = j + 1
        end
    end
    return true
end

function Dev:pixel(x, y, color)
    x = math.floor(x)
    y = math.floor(y)
    if x < 0 or y < 0 or x >= self.width or y >= self.height then
        return
    end
    local idx = (y >> 3) * self.width + x + 1
    local bit = 1 << (y & 7)
    local fb = self.fb
    if ink(color) == 1 then
        fb[idx] = fb[idx] | bit
    else
        fb[idx] = fb[idx] & (bit ~ 0xFF)
    end
end

function Dev:hline(x, y, w, color)
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    if w < 0 then
        x = x + w
        w = -w
    end
    for i = 0, w - 1 do
        self:pixel(x + i, y, color)
    end
end

function Dev:vline(x, y, h, color)
    x = math.floor(x)
    y = math.floor(y)
    h = math.floor(h)
    if h < 0 then
        y = y + h
        h = -h
    end
    for i = 0, h - 1 do
        self:pixel(x, y + i, color)
    end
end

function Dev:line(x0, y0, x1, y1, color)
    x0 = math.floor(x0)
    y0 = math.floor(y0)
    x1 = math.floor(x1)
    y1 = math.floor(y1)
    local dx = math.abs(x1 - x0)
    local sx = 1
    if x0 >= x1 then
        sx = -1
    end
    local dy = -math.abs(y1 - y0)
    local sy = 1
    if y0 >= y1 then
        sy = -1
    end
    local err = dx + dy
    while true do
        self:pixel(x0, y0, color)
        if x0 == x1 and y0 == y1 then
            break
        end
        local e2 = err * 2
        if e2 >= dy then
            err = err + dy
            x0 = x0 + sx
        end
        if e2 <= dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

function Dev:rect(x, y, w, h, color)
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)
    if w < 0 then
        x = x + w
        w = -w
    end
    if h < 0 then
        y = y + h
        h = -h
    end
    if w <= 0 or h <= 0 then
        return
    end
    self:hline(x, y, w, color)
    self:hline(x, y + h - 1, w, color)
    if h > 2 then
        self:vline(x, y + 1, h - 2, color)
        self:vline(x + w - 1, y + 1, h - 2, color)
    end
end

function Dev:fill_rect(x, y, w, h, color)
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)
    if w < 0 then
        x = x + w
        w = -w
    end
    if h < 0 then
        y = y + h
        h = -h
    end
    local x1 = x + w - 1
    local y1 = y + h - 1
    if x < 0 then
        x = 0
    end
    if y < 0 then
        y = 0
    end
    if x1 >= self.width then
        x1 = self.width - 1
    end
    if y1 >= self.height then
        y1 = self.height - 1
    end
    if x > x1 or y > y1 then
        return
    end
    for yy = y, y1 do
        self:hline(x, yy, x1 - x + 1, color)
    end
end

function Dev:circle(cx, cy, r, color)
    cx = math.floor(cx)
    cy = math.floor(cy)
    r = math.floor(r)
    if r < 0 then
        return
    end
    local x = r
    local y = 0
    local err = 1 - r
    while x >= y do
        self:pixel(cx + x, cy + y, color)
        self:pixel(cx + y, cy + x, color)
        self:pixel(cx - y, cy + x, color)
        self:pixel(cx - x, cy + y, color)
        self:pixel(cx - x, cy - y, color)
        self:pixel(cx - y, cy - x, color)
        self:pixel(cx + y, cy - x, color)
        self:pixel(cx + x, cy - y, color)
        y = y + 1
        if err < 0 then
            err = err + 2 * y + 1
        else
            x = x - 1
            err = err + 2 * (y - x) + 1
        end
    end
end

function Dev:char(x, y, ch, color, scale)
    x = math.floor(x)
    y = math.floor(y)
    scale = math.floor(tonumber(scale) or 1)
    if scale < 1 then
        scale = 1
    end
    local c
    if type(ch) == "string" then
        c = select(1, utf8_next(ch, 1)) or 0
    else
        c = math.floor(tonumber(ch) or 0)
    end
    local glyph = FONT_CJK[c]
    if glyph then
        local cw = M.FONT_CJK_W
        for row = 0, M.FONT_CJK_H - 1 do
            local hi = glyph:byte(row * 2 + 1)
            local lo = glyph:byte(row * 2 + 2)
            local bits = (hi << 8) | lo
            for col = 0, cw - 1 do
                if (bits & (1 << (15 - col))) ~= 0 then
                    if scale == 1 then
                        self:pixel(x + col, y + row, color)
                    else
                        self:fill_rect(x + col * scale, y + row * scale, scale, scale, color)
                    end
                end
            end
        end
        return
    end
    if c < FONT_FIRST or c > FONT_LAST then
        c = 0x3F
    end
    local off = (c - FONT_FIRST) * FONT_COLS
    local on = ink(color) == 1
    if scale == 1 then
        for col = 0, FONT_COLS - 1 do
            blit_col(self, x + col, y, FONT5x7:byte(off + col + 1), on)
        end
        return
    end
    for col = 0, FONT_COLS - 1 do
        local bits = FONT5x7:byte(off + col + 1)
        for row = 0, 7 do
            if (bits & (1 << row)) ~= 0 then
                self:fill_rect(x + col * scale, y + row * scale, scale, scale, color)
            end
        end
    end
end

function Dev:text(x, y, s, color, scale)
    s = tostring(s or "")
    x = math.floor(x)
    y = math.floor(y)
    scale = math.floor(tonumber(scale) or 1)
    if scale < 1 then
        scale = 1
    end
    local x0 = x
    local ascii_adv = M.FONT_ADV * scale
    local cjk_adv = M.FONT_CJK_W * scale
    local lh = M.FONT_H * scale
    if M.FONT_CJK_H * scale > lh then
        lh = M.FONT_CJK_H * scale
    end
    local i = 1
    while i <= #s do
        local cp
        cp, i = utf8_next(s, i)
        if cp == 10 then
            x = x0
            y = y + lh
        elseif cp ~= 13 then
            self:char(x, y, cp, color, scale)
            if FONT_CJK[cp] then
                x = x + cjk_adv
            else
                x = x + ascii_adv
            end
        end
    end
    return x, y
end

function Dev:fill_circle(cx, cy, r, color)
    cx = math.floor(cx)
    cy = math.floor(cy)
    r = math.floor(r)
    if r < 0 then
        return
    end
    for dy = -r, r do
        local xx = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        self:hline(cx - xx, cy + dy, xx * 2 + 1, color)
    end
end

return M
