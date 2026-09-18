--[=[
  lvgl_arc demo — 弧进度：范围、模式、背景角、旋转
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
    ui:arc 建弧进度（不是 arclabel）
    背景弧：set_rotation + set_bg_angle 摆成 270° 表盘
    当前值来回扫：用 set_value，不要用 set_angle
      set_angle 是指示条起止角，set_value 会按范围重算并覆盖它
    每隔几秒切换 NORMAL / REVERSE / SYMMETRICAL
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_arc]"
local STEP_MS = 33
local VALUE_STEP = 2
local FLIP_MS = 5000

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then arc", TAG)

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

local title = ui:label("arc")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("n=0")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

-- 0° 正右、90° 正下。rotation=135 再配背景 0..270，开口朝下，像表盘。
local gauge = ui:arc(0)
ui:set_size(gauge, 176, 176)
ui:align(gauge, lvgl.ALIGN_CENTER, 0, 16)
ui:set_rotation(gauge, 135)
ui:set_bg_angle(gauge, 0, 270)

local num = ui:label("0")
ui:set_text_color(num, 0xFFFFFF)
ui:align(num, lvgl.ALIGN_CENTER, 0, 16)

local modes = {
    {
        mode = lvgl.ARC_MODE_NORMAL,
        name = "normal",
        min_v = 0,
        max_v = 100,
    },
    {
        mode = lvgl.ARC_MODE_REVERSE,
        name = "reverse",
        min_v = 0,
        max_v = 100,
    },
    {
        mode = lvgl.ARC_MODE_SYMMETRICAL,
        name = "sym",
        min_v = -50,
        max_v = 50,
    },
}

local function apply_mode(item)
    ui:set_range(gauge, item.min_v, item.max_v)
    ui:set_mode(gauge, item.mode)
    ui:set_value(gauge, item.min_v)
    local min_r, max_r = ui:get_range(gauge)
    log.info("%s %s range %d..%d", TAG, item.name, min_r, max_r)
end

local mode_i = 1
apply_mode(modes[mode_i])

local value = modes[mode_i].min_v
local dir = VALUE_STEP
local elapsed = 0
log.info("%s sweep value, flip mode every %d ms", TAG, FLIP_MS)

while true do
    local item = modes[mode_i]
    value = value + dir
    if value >= item.max_v then
        value = item.max_v
        dir = -VALUE_STEP
    elseif value <= item.min_v then
        value = item.min_v
        dir = VALUE_STEP
    end

    ui:set_value(gauge, value)
    local shown = ui:get_value(gauge)
    ui:set_text(num, tostring(shown))
    ui:align(num, lvgl.ALIGN_CENTER, 0, 16)
    ui:set_text(hint, string.format("%s  n=%d", item.name, shown))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

    elapsed = elapsed + STEP_MS
    if elapsed >= FLIP_MS then
        elapsed = 0
        mode_i = mode_i + 1
        if mode_i > #modes then
            mode_i = 1
        end
        apply_mode(modes[mode_i])
        value = modes[mode_i].min_v
        dir = VALUE_STEP
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_arc — ui:arc 弧进度

  ui:arc([parent,] [value])
  ui:set_range(arc, min, max)
  ui:set_value(arc, value)                进度；会覆盖指示条角度
  ui:get_value(arc) / ui:get_range(arc)
  ui:set_mode(arc, ARC_MODE_NORMAL | REVERSE | SYMMETRICAL)
  ui:set_bg_angle(arc, start [, end])     背景轨道。0=正右，90=正下
  ui:set_rotation(arc, deg)               整圈旋转
  ui:set_angle(arc, start [, end])        指示条起止角；sweep 请用 set_value

  不要循环 ui:handler()。本 demo 主循环是 set_value + rt.delay。

]=]
