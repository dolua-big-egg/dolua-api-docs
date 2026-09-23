--[=[
  spi_lcd_cfg — ST7789 240×270，上电序列来自外部表，不走固件内置 init
  ============================================================================
  硬件（与 spi_lcd 相同）
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0_SCLK
      Pin67  SPI0_MOSI
      GPIO8  CS

    GPIO32  BL
    GPIO31  DC
    GPIO30  RST

  ============================================================================
    和 spi_lcd 的差别
  ============================================================================
    spi_lcd 用 lcd.ST7789，可不写 init，走固件内置上电表。
    本工程用 lcd.TFT：必须带 init / offset，分辨率 240×270。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")

local TAG = "[spi_lcd_cfg]"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s external init 240x270 SPI0 CS=GPIO8 DC/RST/BL=31/30/32", TAG)

local cfg = require("st7789_240x270")
if (cfg.init == nil) or (cfg.init[1] == nil) then
    halt("panel table must contain init; lcd.TFT does not use the firmware ST7789 table")
end

cfg.bus = lcd.SPI0
cfg.hz = 76 * 1000000
cfg.rotate = lcd.ROTATE_0
cfg.dc = 31
cfg.cs = 8
cfg.rst = 30
cfg.bl = 32

local panel, err = lcd.new(cfg)
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
