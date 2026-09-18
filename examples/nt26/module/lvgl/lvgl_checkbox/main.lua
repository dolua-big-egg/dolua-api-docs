--[=[
  lvgl_checkbox demo — 复选框勾选状态
  ============================================================================
  硬件（与 spi_lcd / lvgl_demo 相同）
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
  本例测什么
  ============================================================================
    ui:checkbox 建复选框
    set_text 改旁注（默认字 ASCII）
    set_value(true/false 或 0/1) 勾选；get_value 读 0/1
    没有触摸时用脚本改值，不要指望 ui:click 去拨 LVGL 状态
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_checkbox]"
local STEP_MS = 1000

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then checkbox", TAG)

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

local title = ui:label("checkbox")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("off")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local box = ui:checkbox("LED")
ui:set_text_color(box, 0xFFFFFF)
ui:align(box, lvgl.ALIGN_CENTER, 0, -8)
ui:set_value(box, false)

local box2 = ui:checkbox("WiFi")
ui:set_text_color(box2, 0xFFFFFF)
ui:align(box2, lvgl.ALIGN_CENTER, 0, 28)
ui:set_value(box2, true)

log.info("%s toggle LED every %d ms", TAG, STEP_MS)

while true do
    local on = ui:get_value(box)
    on = (on == 0) and 1 or 0
    ui:set_value(box, on)
    ui:set_text(hint, string.format("LED=%d  WiFi=%d", on, ui:get_value(box2)))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
    log.info("%s LED=%d", TAG, on)
    rt.delay(STEP_MS)
end

--[=[
  lvgl_checkbox — ui:checkbox 勾选

  ui:checkbox([parent,] [text])
  ui:set_text(cb, text)
  ui:set_value(cb, true | false | 0 | 1)
  ui:get_value(cb)   -- 0 未勾，1 已勾

  不要循环 ui:handler()。本 demo 主循环是 set_value + rt.delay。

]=]
