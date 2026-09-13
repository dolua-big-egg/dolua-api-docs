--[[ st7789 — SPI 四线 ST7789 精简驱动（命令/数据 + 开窗 + 纯色填充）

  默认 240x280，GRAM 高度 320，Y 偏移 20。
  控制脚：DC / RST / BL 用 gpio；CS 走 spi.cs_gpio。
]]

local spi = require("spi")
local gpio = require("gpio")
local rt = require("rt")

local M = {}

M.BLACK   = 0x0000
M.WHITE   = 0xFFFF
M.RED     = 0xF800
M.GREEN   = 0x07E0
M.BLUE    = 0x001F
M.YELLOW  = 0xFFE0
M.CYAN    = 0x07FF
M.MAGENTA = 0xF81F

local function out_pin(n, level)
    local io = gpio.open(gpio.BY_GPIO, n) -- 按 GPIO 编号；旧名 gpio.INPUT_GPIO
    if not io:config(true, level, gpio.PULL_UP) then
        return nil
    end
    return io
end

local function wr_cmd(self, cmd)
    self.dc:set(false)
    self.dev:set_cs(true)
    local ok, err = self.dev:send(string.char(cmd))
    self.dev:set_cs(false)
    return ok, err
end

local function wr_data(self, s)
    if not s or #s == 0 then
        return true
    end
    self.dc:set(true)
    self.dev:set_cs(true)
    local ok, err = self.dev:send(s)
    self.dev:set_cs(false)
    return ok, err
end

local function wr(self, cmd, data)
    local ok, err = wr_cmd(self, cmd)
    if not ok then
        return false, err
    end
    if data then
        return wr_data(self, data)
    end
    return true
end

local function window(self, x0, y0, x1, y1)
    local xs = x0 + self.x_off
    local xe = x1 + self.x_off
    local ys = y0 + self.y_off
    local ye = y1 + self.y_off
    local ok, err = wr(self, 0x2A, string.char(
        xs >> 8, xs & 0xFF, xe >> 8, xe & 0xFF))
    if not ok then
        return false, err
    end
    return wr(self, 0x2B, string.char(
        ys >> 8, ys & 0xFF, ye >> 8, ye & 0xFF))
end

function M.new(cfg)
    cfg = cfg or {}
    local w = cfg.width or 240
    local h = cfg.height or 280
    local obj = {
        w = w,
        h = h,
        x_off = cfg.x_off or 0,
        y_off = cfg.y_off or 20,
    }

    local dc = out_pin(cfg.dc or 31, false)
    local rst = out_pin(cfg.rst or 30, true)
    local bl = out_pin(cfg.bl or 32, false)
    if not dc or not rst or not bl then
        return nil, "gpio dc/rst/bl"
    end
    obj.dc, obj.rst, obj.bl = dc, rst, bl

    local dev, e = spi.new(cfg.spi_id or spi.SPI0, {
        bus_hz = cfg.bus_hz or (10 * 1000000),
        data_bits = 8,
        frame_format = spi.CPOL0_CPHA0,
        work_mode = spi.WORK_MODE_TX_ONLY,
        cs_gpio = {
            enabled = true,
            gpio = cfg.cs or 8,
            active_low = true,
            pull_mode = spi.PULL_UP,
        },
    })
    if not dev then
        return nil, "spi: " .. tostring(e)
    end
    obj.dev = dev
    obj.req_hz = cfg.bus_hz or (10 * 1000000)

    rst:set(false)
    rt.delay(10)
    rst:set(true)
    rt.delay(10)

    -- SLPOUT → 16bit → 倒置 → 开显示（240x280 常见最小集）
    local ok, err = wr(obj, 0x11)
    if not ok then
        return nil, "SLPOUT " .. tostring(err)
    end
    rt.delay(120)
    ok, err = wr(obj, 0x36, string.char(0x00))
    if not ok then
        return nil, "MADCTL " .. tostring(err)
    end
    ok, err = wr(obj, 0x3A, string.char(0x05))
    if not ok then
        return nil, "COLMOD " .. tostring(err)
    end
    ok, err = wr(obj, 0x21)
    if not ok then
        return nil, "INVON " .. tostring(err)
    end
    ok, err = wr(obj, 0x29)
    if not ok then
        return nil, "DISPON " .. tostring(err)
    end
    rt.delay(20)
    bl:set(true)

    return setmetatable(obj, { __index = M })
end

function M:fill(color)
    color = color or M.BLACK
    local ok, err = window(self, 0, 0, self.w - 1, self.h - 1)
    if not ok then
        return false, err
    end

    local px = string.char(color >> 8, color & 0xFF)
    local rows = 8
    local chunk = string.rep(px, self.w * rows)
    local nfull = math.floor(self.h / rows)
    local rest = self.h % rows

    self.dc:set(false)
    self.dev:set_cs(true)
    ok, err = self.dev:send(string.char(0x2C))
    if not ok then
        self.dev:set_cs(false)
        return false, err
    end
    self.dc:set(true)
    for _ = 1, nfull do
        ok, err = self.dev:send(chunk)
        if not ok then
            self.dev:set_cs(false)
            return false, err
        end
    end
    if rest > 0 then
        ok, err = self.dev:send(string.rep(px, self.w * rest))
        if not ok then
            self.dev:set_cs(false)
            return false, err
        end
    end
    self.dev:set_cs(false)
    return true
end

function M:bl_set(on)
    return self.bl:set(on and true or false)
end

-- 分频后实际 SCLK（Hz），不是 new 时传入的请求值
function M:bus_hz()
    return self.dev:get_bus_hz()
end

return M
