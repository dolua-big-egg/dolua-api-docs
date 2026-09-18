--[=[
  lvgl_spinner demo — 转圈周期、弧长、弧线样式
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
    ui:spinner 建转圈；动画在图形任务里跑
    set_anim(t [, angle]) 改周期和弧长；get_anim 读回来
    set_style 的 arc_color / arc_width：PART_MAIN 轨道，PART_INDICATOR 转动段
    不要 set_value / set_angle，也不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_spinner]"
local STEP_MS = 1800

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function caption(ui, text, x, y)
    local lab = ui:label(text)
    ui:set_text_color(lab, 0xA0A0A0)
    ui:align(lab, lvgl.ALIGN_TOP_LEFT, x, y)
    return lab
end

local function paint_arc(ui, sp, track, fill, width)
    ui:set_style(sp, { arc_color = track, arc_width = width }, lvgl.PART_MAIN)
    ui:set_style(sp, { arc_color = fill, arc_width = width }, lvgl.PART_INDICATOR)
end

log.info("%s lcd.new SPI0 st7789, then spinner", TAG)

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

local title = ui:label("spinner")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 6)

local hint = ui:label("fast t=800")
ui:set_text_color(hint, 0x808090)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)

-- 1. 主题默认
caption(ui, "theme", 28, 48)
local sp_theme = ui:spinner()
ui:set_size(sp_theme, 64, 64)
ui:align(sp_theme, lvgl.ALIGN_TOP_LEFT, 24, 68)

-- 2. 绿色快转
caption(ui, "fast", 152, 48)
local sp_fast = ui:spinner(800, 240)
ui:set_size(sp_fast, 64, 64)
ui:align(sp_fast, lvgl.ALIGN_TOP_LEFT, 148, 68)
paint_arc(ui, sp_fast, 0x2A2A38, 0x34C759, 7)

-- 3. 蓝色粗线慢转
caption(ui, "slow", 24, 148)
local sp_slow = ui:spinner(1800, 200)
ui:set_size(sp_slow, 88, 88)
ui:align(sp_slow, lvgl.ALIGN_TOP_LEFT, 16, 168)
paint_arc(ui, sp_slow, 0x1C2430, 0x0A84FF, 12)

-- 4. 橙色短弧
caption(ui, "sweep", 148, 148)
local sp_sweep = ui:spinner(1200, 120)
ui:set_size(sp_sweep, 72, 72)
ui:align(sp_sweep, lvgl.ALIGN_TOP_LEFT, 148, 176)
paint_arc(ui, sp_sweep, 0x2A2A38, 0xFF9F0A, 6)

local periods = { 500, 800, 1400 }
local i = 1
log.info("%s four spinners; cycle fast period", TAG)

while true do
    ui:set_anim(sp_fast, periods[i], 240)
    local t, ang = ui:get_anim(sp_fast)
    ui:set_text(hint, string.format("fast t=%d a=%d", t, ang))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)
    log.info("%s fast t=%d a=%d", TAG, t, ang)
    print(string.format("%s fast t=%d a=%d, delay %d ms",
                        TAG, t, ang, STEP_MS))
    i = i + 1
    if i > #periods then
        i = 1
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_spinner — ui:spinner 转圈

  ui:spinner([parent,] [t [, angle]])
  ui:set_anim(sp, t [, angle])     t 毫秒，angle 1..360
  t, angle = ui:get_anim(sp)
  ui:set_style(sp, { arc_color = ..., arc_width = ... }, PART_MAIN)
  ui:set_style(sp, { arc_color = ..., arc_width = ... }, PART_INDICATOR)

  不要循环 ui:handler()。动画在图形任务里跑，本 demo 只改 set_anim + rt.delay。

]=]
