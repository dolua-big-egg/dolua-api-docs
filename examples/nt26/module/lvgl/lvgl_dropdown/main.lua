--[=[
  lvgl_dropdown demo — 下拉选项、方向、展开
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
    ui:dropdown 建下拉框，选项用表或 "A\\nB\\nC"
    set_value 选中下标（从 0）；get_value 读下标
    set_dir 控制列表往哪边展开
    没有触摸：用 open / close 展开再收起，不要指望 ui:click
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_dropdown]"
local STEP_MS = 1200
local OPEN_MS = 900

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then dropdown", TAG)

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

local title = ui:label("dropdown")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("i=0")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local opts = { "Red", "Green", "Blue", "White" }
local dd = ui:dropdown(opts)
ui:set_size(dd, 160, 36)
ui:align(dd, lvgl.ALIGN_TOP_MID, 0, 72)
ui:set_dir(dd, lvgl.DROPDOWN_DIR_BOTTOM)
ui:set_value(dd, 0)

local sel = 0
log.info("%s cycle selected, open list every other step", TAG)

while true do
    sel = sel + 1
    if sel >= #opts then
        sel = 0
    end
    ui:set_value(dd, sel)
    local shown = ui:get_value(dd)
    ui:set_text(hint, string.format("i=%d  %s", shown, opts[shown + 1]))
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
    log.info("%s selected %d %s dir=%d", TAG, shown, opts[shown + 1], ui:get_dir(dd))

    ui:open(dd)
    rt.delay(OPEN_MS)
    ui:close(dd)
    print(string.format("%s selected %d %s, delay %d ms",
                        TAG, shown, opts[shown + 1], STEP_MS))
    rt.delay(STEP_MS)
end

--[=[
  lvgl_dropdown — ui:dropdown 下拉选项

  ui:dropdown([parent,] [options])
      options  字符串 "A\\nB\\nC" 或 { "A", "B", "C" }
  ui:set_options(dd, options)
  ui:set_value(dd, index)     从 0 起
  ui:get_value(dd)
  ui:set_dir(dd, DROPDOWN_DIR_BOTTOM | TOP | LEFT | RIGHT)
  ui:open(dd) / ui:close(dd)

  不要循环 ui:handler()。本 demo 主循环是 set_value + open/close + rt.delay。

]=]
