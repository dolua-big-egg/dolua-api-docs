--[=[
  lvgl_led demo — 指示灯颜色、亮度、开关
  ============================================================================
  硬件（与 spi_lcd / lvgl_demo 相同）
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0  SCLK
      Pin67  SPI0  MOSI
      GPIO8  CS
    GPIO32  BL
    GPIO31  DC
    GPIO30  RST
    240x280，Y 偏移 20。

  ============================================================================
  本例测什么
  ============================================================================
    ui:led 建指示灯；set_color 改颜色
    on / off / toggle；set_brightness 0..255
    灭不是全黑，大约 LED_BRIGHT_MIN
    默认字是 ASCII，不要写汉字
    不要循环 ui:handler()。
    需要已编入 LED 的固件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_led]"
local STEP_MS = 700

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function caption(ui, text, x, y)
    local lab = ui:label(text)
    ui:set_text_color(lab, 0x808090)
    ui:set_pos(lab, x, y)
    return lab
end

log.info("%s lcd.new SPI0 st7789, then led", TAG)

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
    halt("lcd.new fail: " .. tostring(err)
         .. "  check wiring and rtu_config [uart.2] pin_map=1")
end

local lcd_info = panel:info()
local w, h = panel:size()
log.info("%s lcd ok driver=%s bus=%s %dx%d",
         TAG, tostring(lcd_info.driver), tostring(lcd_info.bus), w, h)

local ok, ui = pcall(lvgl.create, panel, {
    mem_max = 384 * 1024,
    color = "rgb565",
    dpi = 130,
    refr_ms = 33,
    full_buf = true,
    theme = "dark",
    bg = 0x101018,
})
if not ok then
    halt("lvgl.create fail: " .. tostring(ui))
end

local used0, peak0, limit0 = ui:mem()
log.info("%s lvgl ok mem used=%d peak=%d limit=%d",
         TAG, used0, peak0, limit0)

local title = ui:label("led")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("toggle")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 28)

caption(ui, "red", 28, 56)
local led_red = ui:led(0xFF453A)
ui:set_size(led_red, 36, 36)
ui:set_pos(led_red, 28, 76)
ui:on(led_red)

caption(ui, "green", 100, 56)
local led_green = ui:led(0x34C759)
ui:set_size(led_green, 36, 36)
ui:set_pos(led_green, 104, 76)
ui:off(led_green)

caption(ui, "blue", 176, 56)
local led_blue = ui:led()
ui:set_color(led_blue, 0x0A84FF)
ui:set_size(led_blue, 36, 36)
ui:set_pos(led_blue, 180, 76)
ui:on(led_blue)

caption(ui, "bright", 16, 128)
local led_dim = ui:led(0xFF9F0A)
ui:set_size(led_dim, 48, 48)
ui:set_pos(led_dim, 96, 148)

local levels = {
    lvgl.LED_BRIGHT_MIN,
    120,
    180,
    lvgl.LED_BRIGHT_MAX,
}
local i = 1
log.info("%s cycle brightness and toggle green", TAG)

while true do
    ui:set_brightness(led_dim, levels[i])
    ui:toggle(led_green)
    local b = ui:get_brightness(led_dim)
    local g = ui:get_brightness(led_green)
    ui:set_text(hint, string.format("dim=%d green=%d", b, g))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 28)
    log.info("%s dim=%d green=%d", TAG, b, g)
    print(string.format("%s dim=%d green=%d, delay %d ms", TAG, b, g, STEP_MS))
    i = i + 1
    if i > #levels then
        i = 1
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_led — ui:led 指示灯

  led = ui:led([parent,] [color])
  ok = ui:set_color(led, color)
  ok = ui:set_brightness(led, 0..255)
  n = ui:get_brightness(led)
  ok = ui:on(led) / ui:off(led) / ui:toggle(led)

  off 后亮度约为 LED_BRIGHT_MIN，不是 0。
  不要循环 ui:handler()。

]=]
