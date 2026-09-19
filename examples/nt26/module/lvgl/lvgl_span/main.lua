--[=[
  lvgl_span demo — 富文本分段
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
    ui:span 建一组；add_span 得到的是分段句柄，不是控件
    set_text / set_style 打在分段上：颜色、字重靠默认字
    set_mode BREAK 换行；FIXED + SPAN_OVERFLOW_ELLIPSIS 裁省略号
    默认字是 ASCII，不要写汉字
    不要循环 ui:handler()。
    需要已编入 SPAN 的固件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_span]"
local STEP_MS = 1200

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then span", TAG)

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

local title = ui:label("span")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("break")
ui:set_text_color(hint, 0x808090)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 28)

-- 1. 换行富文本：品牌 + 型号 + 读数
local mix = ui:span()
ui:set_size(mix, 208, 88)
ui:align(mix, lvgl.ALIGN_TOP_MID, 0, 52)
ui:set_style(mix, { bg = 0x1C1C24, radius = 12, pad = 10 })
ui:set_mode(mix, lvgl.SPAN_MODE_BREAK)
ui:set_text_align(mix, lvgl.TEXT_ALIGN_LEFT)

local run_brand = ui:add_span(mix, "NT26")
ui:set_style(run_brand, { text_color = 0xFFFFFF })

local run_model = ui:add_span(mix, " PRO")
ui:set_style(run_model, { text_color = 0xFF9F0A })

local run_gap = ui:add_span(mix, "  ")
ui:set_style(run_gap, { text_color = 0xA0A0A0 })

local run_val = ui:add_span(mix, "12:00")
ui:set_style(run_val, { text_color = 0x0A84FF })

local run_note = ui:add_span(mix, "  mixed runs, one group")
ui:set_style(run_note, { text_color = 0x6E6E7A })

-- 2. 固定宽 + 省略号
local clip = ui:span()
ui:set_size(clip, 208, 40)
ui:align(clip, lvgl.ALIGN_TOP_MID, 0, 152)
ui:set_style(clip, { bg = 0x1C1C24, radius = 12, pad = 8 })
ui:set_mode(clip, lvgl.SPAN_MODE_FIXED)
ui:set_overflow(clip, lvgl.SPAN_OVERFLOW_ELLIPSIS)

local run_long = ui:add_span(clip, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789")
ui:set_style(run_long, { text_color = 0x34C759 })

local times = { "12:00", "12:15", "12:30", "12:45" }
local i = 1
log.info("%s two groups; cycle time run", TAG)

while true do
    ui:set_text(run_val, times[i])
    local got = ui:get_text(run_val)
    ui:set_text(hint, "val=" .. tostring(got))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 28)
    log.info("%s val=%s", TAG, tostring(got))
    print(string.format("%s val=%s, delay %d ms", TAG, tostring(got), STEP_MS))
    i = i + 1
    if i > #times then
        i = 1
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_span — ui:span 富文本分段

  spg = ui:span([parent])
  run = ui:add_span(spg [, text])     -- 分段 userdata，不是控件
  ok = ui:set_text(run, text)
  text = ui:get_text(run)
  ok = ui:set_style(run, { text_color = ... })
  ok = ui:set_mode(spg, SPAN_MODE_BREAK | "break" | "expand" | "fixed")
  ok = ui:set_overflow(spg, SPAN_OVERFLOW_ELLIPSIS | "ellipsis" | "clip")
  ok = ui:delete_span(run)            -- 或 ui:delete_span(spg, run)

  一组最多 24 段。不要循环 ui:handler()。

]=]
