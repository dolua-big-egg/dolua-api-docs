--[=[
  spi_lcd demo — require("lcd") 走 C 层 lcd_bus + st7789 族
  ============================================================================
  硬件
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0_SCLK
      Pin67  SPI0_MOSI
      GPIO8  CS

    GPIO32  BL
    GPIO31  DC
    GPIO30  RST
    240x280，Y 偏移见 st7789_240x280.lua。

  换 LSPI：cfg.bus = lcd.LSPI0，可省略 dc/cs（硬件脚），只留 rst/bl。
  面板参数在 st7789_240x280.lua，本文件只补总线和脚。也可把整张表直接写进 lcd.new({...})。

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

local cfg = require("st7789_240x280")
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
