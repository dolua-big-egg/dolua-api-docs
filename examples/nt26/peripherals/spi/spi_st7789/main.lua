
--[=[
  spi_st7789 demo — SPI0 点亮 ST7789，循环纯色刷屏
  ============================================================================
  硬件
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0_SCLK
      Pin67  SPI0_MOSI
      GPIO8  CS   （低有效，与 spi_api 相同）

    控制脚（GPIO 编号）
      GPIO32  BL
      GPIO31  DC
      GPIO30  RST

    分辨率 240x280，Y 偏移 20。

  ============================================================================
  本 demo
  ============================================================================
    1) st7789.new：复位 + 最短初始化 + 开背光
    2) 红 / 绿 / 蓝 / 白 / 黑 / 黄 全屏填充，每色 1 秒

]=]

local rt = require("rt")
local log = require("log")
local st7789 = require("st7789")

local TAG = "[st7789]"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s init SPI0 CS=GPIO8  BL/DC/RST=GPIO32/31/30  240x280", TAG)

local lcd, err = st7789.new({
    dc = 31,
    rst = 30,
    bl = 32,
    cs = 8,
    width = 240,
    height = 280,
    y_off = 20,
    bus_hz = 76 * 1000000,
})
if not lcd then
    halt("new fail: " .. tostring(err)
         .. "  check SPI wiring and rtu_config [uart.2] pin_map=1")
end

local actual, aerr = lcd:bus_hz()
log.info("%s init ok bus_hz request=%s actual=%s",
         TAG, tostring(lcd.req_hz), actual and tostring(actual) or tostring(aerr))

local colors = {
    { st7789.RED, "red" },
    { st7789.GREEN, "green" },
    { st7789.BLUE, "blue" },
    { st7789.WHITE, "white" },
    { st7789.BLACK, "black" },
    { st7789.YELLOW, "yellow" },
}

local i = 1
while true do
    local c = colors[i]
    log.info("%s fill %s 0x%04X", TAG, c[2], c[1])
    local ok, fe = lcd:fill(c[1])
    if not ok then
        log.error("%s fill fail: %s", TAG, tostring(fe))
    end
    i = (i % #colors) + 1
    rt.delay(1000)
end

--[=[
  spi_st7789 demo — SPI0 + ST7789 纯色刷屏

  面板操作在 st7789.lua。main 只负责引脚和颜色循环。

  ----------------------------------------------------------------------------
  st7789.new(cfg) -> lcd | nil, err
  ----------------------------------------------------------------------------
    cfg.spi_id / bus_hz / cs / dc / rst / bl
    cfg.width / height / x_off / y_off
    默认 SPI0、10MHz、CS=8、DC=31、RST=30、BL=32、240x280、y_off=20

  st7789:fill(color) -> boolean[, err]     RGB565，如 st7789.RED
  st7789:bl_set(on)  -> boolean
  st7789:bus_hz()    -> hz | nil, err      分频后实际 SCLK

  颜色常量：BLACK WHITE RED GREEN BLUE YELLOW CYAN MAGENTA

]=]
