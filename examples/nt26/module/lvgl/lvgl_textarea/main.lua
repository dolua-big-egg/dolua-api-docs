--[=[
  lvgl_textarea demo — 文本框、占位符、密码、逐字输入
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
    ui:textarea 建文本框
    set_one_line / set_placeholder / set_password
    没有键盘：用 add_text 逐字、set_text 整段替换
    get_text 读明文（密码模式屏上是圆点，读出来仍是原文）
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_textarea]"
local STEP_MS = 400
local WORD = "HELLO"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then textarea", TAG)

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

local title = ui:label("textarea")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("typed=")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local name = ui:textarea()
ui:set_one_line(name, true)
ui:set_size(name, 200, 36)
ui:align(name, lvgl.ALIGN_TOP_MID, 0, 64)
ui:set_placeholder(name, "name")

local pass = ui:textarea()
ui:set_one_line(pass, true)
ui:set_password(pass, true)
ui:set_size(pass, 200, 36)
ui:align(pass, lvgl.ALIGN_TOP_MID, 0, 112)
ui:set_placeholder(pass, "pass")
ui:set_text(pass, "secret")

local note = ui:textarea()
ui:set_one_line(note, false)
ui:set_size(note, 200, 88)
ui:align(note, lvgl.ALIGN_TOP_MID, 0, 160)
ui:set_placeholder(note, "notes")

local i = 0
log.info("%s type %s into name; pass stays secret", TAG, WORD)

while true do
    i = i + 1
    if i > #WORD then
        ui:set_text(name, "")
        i = 1
    end
    ui:add_text(name, string.sub(WORD, i, i))
    local shown = ui:get_text(name)
    local hidden = ui:get_text(pass)
    ui:set_text(hint, "typed=" .. shown)
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
    ui:set_text(note, string.format("name=%s\npass=%s\nlen=%d",
                                   shown, hidden, #shown))
    log.info("%s name=%s pass=%s", TAG, shown, hidden)
    print(string.format("%s name=%s pass=%s, delay %d ms",
                        TAG, shown, hidden, STEP_MS))
    rt.delay(STEP_MS)
end

--[=[
  lvgl_textarea — ui:textarea 文本框

  ui:textarea([parent,] [text])
  ui:set_one_line(ta, true|false)     先于 set_size
  ui:set_placeholder(ta, "name")
  ui:set_password(ta, true)
  ui:set_text(ta, "secret")
  ui:add_text(ta, "A")
  ui:get_text(ta)                    密码模式仍是明文

  不要循环 ui:handler()。本 demo 主循环是 add_text + get_text + rt.delay。

]=]
