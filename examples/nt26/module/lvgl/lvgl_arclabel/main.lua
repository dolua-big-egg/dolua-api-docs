--[=[
  lvgl_arclabel demo — 沿圆弧排字
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
    ui:arclabel 建弧标签（默认字 ASCII，不要写汉字）
    整圈 360° + 居中，字始终在弧上。
    转圈用 ui:set_angle(arc, start)，不要用 set_offset：
      offset 是弧长像素，把字在窗口里平移；CLIP 下超出就裁掉，不会绕回。
    每隔几秒切换顺/逆时针。
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_arclabel]"
local ARC_TEXT = "HELLO-doLua"
local STEP_MS = 33
local DEG_STEP = 3
local FLIP_MS = 5000

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then arclabel", TAG)

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

local title = ui:label("arclabel")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("...")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_BOTTOM_MID, 0, -8)

-- 整圈窗口 + 居中：字落在弧上。CLIP 只裁超出 angle_size 的部分。
local arc = ui:arclabel(ARC_TEXT)
ui:set_size(arc, 200, 200)
ui:set_radius(arc, 82)
ui:align(arc, lvgl.ALIGN_CENTER, 0, 4)
ui:set_text_color(arc, 0xFFFFFF)
ui:set_text_align(arc, lvgl.TEXT_ALIGN_CENTER, lvgl.TEXT_ALIGN_CENTER)
ui:set_overflow(arc, lvgl.OVERFLOW_CLIP)
ui:set_offset(arc, 0)
ui:set_angle(arc, 0, 360)

local dirs = {
    { dir = lvgl.ARCLABEL_DIR_CLOCKWISE,         name = "cw" },
    { dir = lvgl.ARCLABEL_DIR_COUNTER_CLOCKWISE, name = "ccw" },
}

local function apply_dir(item, rot)
    ui:set_dir(arc, item.dir)
    ui:set_offset(arc, 0)
    ui:set_angle(arc, rot, 360)
    ui:set_text(hint, string.format("%s  start=%d", item.name, rot))
    ui:align(hint, lvgl.ALIGN_BOTTOM_MID, 0, -8)
    log.info("%s %s start=%d dir=%d", TAG, item.name, rot, ui:get_dir(arc))
end

local dir_i = 1
local rot = 0
apply_dir(dirs[dir_i], rot)

local elapsed = 0
log.info("%s spin via set_angle start, flip dir every %d ms", TAG, FLIP_MS)

while true do
    rot = rot + DEG_STEP
    if rot >= 360 then
        rot = rot - 360
    end
    ui:set_angle(arc, rot)

    elapsed = elapsed + STEP_MS
    if elapsed >= FLIP_MS then
        elapsed = 0
        dir_i = dir_i + 1
        if dir_i > #dirs then
            dir_i = 1
        end
        rot = 0
        apply_dir(dirs[dir_i], rot)
    else
        ui:set_text(hint, string.format("%s  start=%d", dirs[dir_i].name, rot))
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_arclabel — ui:arclabel 沿弧排字

  ui:arclabel([parent,] text)
  ui:set_text(arc, text)
  ui:set_text_align(arc, h [, v])
  ui:set_dir(arc, ARCLABEL_DIR_CLOCKWISE | COUNTER_CLOCKWISE)
  ui:set_angle(arc, start [, size])
      start  加到每个字上，0=正右(3 点)。改 start 才能绕圈转。
      size   可见弧长。CLIP 时超出这段的字不画。转圈请用 360。
  ui:set_radius(arc, px)                 曲率半径，不是圆角
  ui:set_offset(arc, px)                 沿弧平移（弧长像素），不是绕圈。
                                        CLIP 下偏太多字会从 3 点钟裁没；TRAILING 不吃 offset。
  ui:set_overflow(arc, CLIP | ELLIPSIS | VISIBLE)
  ui:align(obj, ALIGN_CENTER)

  不要循环 ui:handler()。本 demo 主循环是 set_angle(start) + rt.delay。

]=]
