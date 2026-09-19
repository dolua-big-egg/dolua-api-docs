--[=[
  lvgl_chart demo — 折线与柱状图
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
    ui:chart 建折线图；add_series 得到序列句柄，不是控件
    set_point_count / set_range / set_next 推点（SHIFT）
    下面一根柱状图用 set_values 一次填完
    默认字是 ASCII，不要写汉字
    不要循环 ui:handler()。
    需要已编入 CHART 的固件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_chart]"
local STEP_MS = 120
local POINTS = 24

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then chart", TAG)

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

local title = ui:label("chart")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 6)

local hint = ui:label("line SHIFT")
ui:set_text_color(hint, 0x808090)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 24)

local line = ui:chart()
ui:set_size(line, 216, 120)
ui:align(line, lvgl.ALIGN_TOP_MID, 0, 44)
ui:set_style(line, { bg = 0x1C1C24, radius = 8, pad = 6 })
ui:set_type(line, lvgl.CHART_TYPE_LINE)
ui:set_point_count(line, POINTS)
ui:set_range(line, 0, 100)
ui:set_div_count(line, 3, 5)
ui:set_update_mode(line, lvgl.CHART_UPDATE_SHIFT)

local ser_a = ui:add_series(line, 0x0A84FF)
local ser_b = ui:add_series(line, 0xFF9F0A)
ui:set_all(ser_a, 50)
ui:set_all(ser_b, 40)

local bars = ui:chart()
ui:set_size(bars, 216, 80)
ui:align(bars, lvgl.ALIGN_TOP_MID, 0, 176)
ui:set_style(bars, { bg = 0x1C1C24, radius = 8, pad = 6 })
ui:set_type(bars, lvgl.CHART_TYPE_BAR)
ui:set_point_count(bars, 8)
ui:set_range(bars, 0, 100)
ui:set_div_count(bars, 2, 4)

local ser_bar = ui:add_series(bars, 0x34C759)
ui:set_values(ser_bar, { 20, 35, 48, 62, 55, 70, 80, 44 })

local t = 0
log.info("%s push line points", TAG)

while true do
    local y1 = 50 + math.floor(40 * math.sin(t / 4))
    local y2 = 50 + math.floor(28 * math.cos(t / 5))
    ui:set_next(ser_a, y1)
    ui:set_next(ser_b, y2)
    ui:set_text(hint, string.format("a=%d b=%d", y1, y2))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 24)
    t = t + 1
    if (t % 8) == 0 then
        log.info("%s a=%d b=%d", TAG, y1, y2)
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_chart — ui:chart 折线 / 柱状

  ch = ui:chart([parent])
  ser = ui:add_series(ch, color [, axis])   -- 序列 userdata，不是控件
  ok = ui:set_type(ch, CHART_TYPE_LINE | "line" | "bar" | "curve" | "scatter")
  ok = ui:set_point_count(ch, n)            -- 1..64
  ok = ui:set_range(ch, min, max [, axis])
  ok = ui:set_next(ser, y)                  -- scatter: set_next(ser, x, y)
  ok = ui:set_values(ser, { y... })
  ok = ui:delete_series(ser)

  一组最多 8 条序列。不要循环 ui:handler()。

]=]
