--[=[
  lvgl_bar demo — 水平 / 垂直进度条、范围、RANGE 模式
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
    ui:bar 建进度条
    水平条：0..100，当前值来回扫
    RANGE 条：同一范围，起始值跟着当前值落后 20
    垂直条：BAR_DIR_VERTICAL，同一当前值
    ui:set_range / set_dir / set_value / set_start_value / set_mode / get_value
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_bar]"
local STEP_MS = 33
local VALUE_STEP = 2
local RANGE_WINDOW = 20

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then bar", TAG)

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

local title = ui:label("bar")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("n=0")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local cap_h = ui:label("H 0..100")
ui:set_text_color(cap_h, 0x808080)
ui:set_pos(cap_h, 16, 60)

local bar_h = ui:bar(0)
ui:set_size(bar_h, 176, 16)
ui:set_pos(bar_h, 16, 80)
ui:set_range(bar_h, 0, 100)
ui:set_dir(bar_h, lvgl.BAR_DIR_HORIZONTAL)
ui:set_mode(bar_h, lvgl.BAR_MODE_NORMAL)

local cap_r = ui:label("RANGE")
ui:set_text_color(cap_r, 0x808080)
ui:set_pos(cap_r, 16, 108)

local bar_r = ui:bar(0)
ui:set_size(bar_r, 176, 16)
ui:set_pos(bar_r, 16, 128)
ui:set_range(bar_r, 0, 100)
ui:set_dir(bar_r, lvgl.BAR_DIR_HORIZONTAL)
ui:set_mode(bar_r, lvgl.BAR_MODE_RANGE)
ui:set_start_value(bar_r, 0)

local cap_v = ui:label("V")
ui:set_text_color(cap_v, 0x808080)
ui:set_pos(cap_v, 204, 60)

local bar_v = ui:bar(0)
ui:set_size(bar_v, 16, 160)
ui:set_pos(bar_v, 208, 80)
ui:set_range(bar_v, 0, 100)
ui:set_dir(bar_v, lvgl.BAR_DIR_VERTICAL)
ui:set_mode(bar_v, lvgl.BAR_MODE_NORMAL)

local min_h, max_h = ui:get_range(bar_h)
local dir_h = ui:get_dir(bar_h)
local dir_v = ui:get_dir(bar_v)
log.info("%s range %d..%d dir h=%d v=%d", TAG, min_h, max_h, dir_h, dir_v)

local value = 0
local dir = VALUE_STEP
log.info("%s sweep value 0..100", TAG)

while true do
    value = value + dir
    if value >= 100 then
        value = 100
        dir = -VALUE_STEP
    elseif value <= 0 then
        value = 0
        dir = VALUE_STEP
    end

    ui:set_value(bar_h, value)
    ui:set_value(bar_v, value)

    local start_v = value - RANGE_WINDOW
    if start_v < 0 then
        start_v = 0
    end
    ui:set_start_value(bar_r, start_v)
    ui:set_value(bar_r, value)

    local shown = ui:get_value(bar_h)
    ui:set_text(hint, string.format("n=%d  start=%d", shown, start_v))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
    rt.delay(STEP_MS)
end

--[=[
  lvgl_bar — ui:bar 方向、范围、当前值

  ui:bar([parent,] [value])
  ui:set_range(bar, min, max)
  ui:set_dir(bar, BAR_DIR_HORIZONTAL | VERTICAL | AUTO)
  ui:set_mode(bar, BAR_MODE_NORMAL | RANGE | SYMMETRICAL)
  ui:set_value(bar, value [, anim])
  ui:set_start_value(bar, value [, anim])   RANGE 模式的左端
  ui:get_value(bar) / ui:get_range(bar) / ui:get_dir(bar)

  不要循环 ui:handler()。本 demo 主循环是 set_value + rt.delay。

]=]
