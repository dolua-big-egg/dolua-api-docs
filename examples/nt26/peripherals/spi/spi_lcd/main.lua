--[=[
  spi_lcd demo — require("lcd") 走 C 层 lcd_bus + st7789
  ============================================================================
  硬件（与 spi_st7789 相同）
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0_SCLK
      Pin67  SPI0_MOSI
      GPIO8  CS

    GPIO32  BL
    GPIO31  DC
    GPIO30  RST
    240x280，Y 偏移 20。

  ============================================================================
  与 spi_st7789 的差别
  ============================================================================
    spi_st7789：Lua 自己发 init / 开窗 / send
    本 demo：lcd.new 打开底层 lcd（SPI 或 LSPI 在 C 里封装），
             脚本只调 full / fill。同一对象以后可 lvgl.create(lcd, ...)。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")

local TAG = "[spi_lcd]"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789 CS=GPIO8 DC/RST/BL=31/30/32", TAG)

local panel, err = lcd.new({
    driver = lcd.ST7789,
    bus = lcd.SPI0,
    hz = 76 * 1000000,
    width = 240,
    height = 280,
    x_off = 0,
    y_off = 20,
    rotate = lcd.ROTATE_0,
    dc = 31,
    cs = 8,
    rst = 30,
    bl = 32,
})
if not panel then
    halt("new fail: " .. tostring(err)
         .. "  check wiring and rtu_config [uart.2] pin_map=1")
end

local info = panel:info()
local w, h = panel:size()
log.info("%s init ok driver=%s bus=%s %dx%d",
         TAG, tostring(info.driver), tostring(info.bus), w, h)

local colors = {
    { lcd.RED, "red" },
    { lcd.GREEN, "green" },
    { lcd.BLUE, "blue" },
    { lcd.WHITE, "white" },
    { lcd.BLACK, "black" },
    { lcd.YELLOW, "yellow" },
}

local i = 1
while true do
    local c = colors[i]
    log.info("%s full %s 0x%04X", TAG, c[2], c[1])
    local ok, fe = panel:full(c[1])
    if not ok then
        log.error("%s full fail: %s", TAG, tostring(fe))
    end
    i = (i % #colors) + 1
    rt.delay(1000)
end

--[=[
  spi_lcd demo — C 层 lcd 模块纯色刷屏

  require("lcd")，不要再 require("spi") 去发屏命令。
  换 LSPI：bus = lcd.LSPI0，可省略 dc/cs（硬件脚），只留 rst/bl。

  ----------------------------------------------------------------------------
  lcd.new(cfg) -> panel | nil, err
  ----------------------------------------------------------------------------
    cfg.driver   lcd.ST7789
    cfg.bus      lcd.SPI0 / SPI1 / LSPI0
    cfg.hz       SCLK，0=默认（spi 20M / lspi 40M）
    cfg.width / height / x_off / y_off / rotate
    cfg.dc cs rst bl   整数=GPIO，或 {pin=n} / {gpio=n}
    SPI 必须 dc；cs 建议给。

  panel:full(color)
  panel:fill(color)
  panel:fill(x, y, w, h, color|buf)
  panel:flush(x, y, w, h, buf)     RGB565 大端，LVGL 预留
  panel:size() -> w, h
  panel:info() -> table
  panel:deinit()

  后期：lvgl.create(panel, opts) 传入同一对象。

]=]
