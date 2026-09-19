--[=[
  lvgl_canvas demo — RGB565 画布
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
    ui:canvas(w, h) 分配 RGB565 缓冲（走 mem_max）
    fill / draw_rect / draw_line / draw_label；RADIUS_CIRCLE 画圆
    不要循环成千上万次 set_px
    默认字是 ASCII，不要写汉字
    不要循环 ui:handler()。
    需要已编入 CANVAS 的固件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_canvas]"
local STEP_MS = 900

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function paint(ui, cv, step)
    local accents = { 0x0A84FF, 0x34C759, 0xFF9F0A, 0xFF453A }
    local accent = accents[((step - 1) % #accents) + 1]

    ui:fill(cv, 0x101018)
    ui:draw_rect(cv, 12, 12, 192, 196, {
        bg = 0x1C1C24,
        radius = 18,
        border = 1,
        border_color = 0x2A2A38,
    })
    ui:draw_rect(cv, 58, 28, 100, 100, {
        bg = accent,
        radius = lvgl.RADIUS_CIRCLE,
        bg_opa = 220,
    })
    ui:draw_rect(cv, 88, 58, 40, 40, {
        bg = 0x101018,
        radius = lvgl.RADIUS_CIRCLE,
    })
    ui:draw_line(cv, 36, 148, 180, 148, {
        line_width = 2,
        line_color = 0x2A2A38,
        line_rounded = true,
    })
    ui:draw_line(cv, 36, 148, 36 + step * 12, 148, {
        line_width = 4,
        line_color = accent,
        line_rounded = true,
    })
    ui:draw_label(cv, 24, 164, "canvas RGB565", { text_color = 0xFFFFFF })
    ui:draw_label(cv, 24, 184, string.format("step %d", step), {
        text_color = 0xA0A0A0,
    })
    -- 只打几个点当装饰，不要整屏 set_px
    local i
    for i = 0, 7 do
        ui:set_px(cv, 170 + i, 32 + i, 0xFFFFFF)
    end
end

log.info("%s lcd.new SPI0 st7789, then canvas", TAG)

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
    bg = 0x08080C,
})
if not ok then
    halt("lvgl.create fail: " .. tostring(ui))
end

local used0, peak0, limit0 = ui:mem()
log.info("%s lvgl ok mem used=%d peak=%d limit=%d",
         TAG, used0, peak0, limit0)

local title = ui:label("canvas")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 6)

local hint = ui:label("fill + rect + line")
ui:set_text_color(hint, 0x808090)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)

local cv, cv_err = ui:canvas(216, 220)
if not cv then
    halt("ui:canvas fail: " .. tostring(cv_err))
end
ui:align(cv, lvgl.ALIGN_TOP_MID, 0, 48)

local used1 = ui:mem()
log.info("%s after canvas mem used=%d (was %d)", TAG, used1, used0)

local step = 1
log.info("%s draw loop", TAG)

while true do
    paint(ui, cv, step)
    ui:set_text(hint, string.format("accent step=%d", step))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)
    log.info("%s step=%d", TAG, step)
    print(string.format("%s step=%d, delay %d ms", TAG, step, STEP_MS))
    step = step + 1
    if step > 8 then
        step = 1
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_canvas — ui:canvas RGB565 画布

  cv = ui:canvas([parent,] w, h)     -- 1..240 x 1..280
  ok = ui:fill(cv, color [, opa])
  ok = ui:set_px(cv, x, y, color [, opa])
  ok = ui:draw_rect(cv, x, y, w, h [, { bg=, radius=, border=, border_color=, bg_opa= }])
  ok = ui:draw_line(cv, x1, y1, x2, y2 [, { line_width=, line_color=, line_rounded= }])
  ok = ui:draw_label(cv, x, y, text [, { text_color=, font= }])

  圆角画满圆用 lvgl.RADIUS_CIRCLE。缓冲约占 w*h*2 字节。
  不要循环 ui:handler()。

]=]
