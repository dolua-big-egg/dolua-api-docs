--[=[
  lvgl_keyboard demo — 软键盘 + 模拟输入
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
    ui:keyboard 建软键盘（默认贴底），set_textarea 绑到文本框
    暂时没有外部触摸：用 add_text 逐字打一段，再用 set_text 逐字删掉，循环
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_keyboard]"
local STEP_MS = 400
local WORD = "HELLO"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then keyboard", TAG)

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

local title = ui:label("keyboard")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 6)

local hint = ui:label("typed=")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)

local ta = ui:textarea()
ui:set_one_line(ta, true)
ui:set_size(ta, 216, 32)
ui:align(ta, lvgl.ALIGN_TOP_MID, 0, 48)
ui:set_placeholder(ta, "type here")

local kb = ui:keyboard()
ui:set_textarea(kb, ta)

local i = 0
local deleting = false
log.info("%s type %s then delete, no touch", TAG, WORD)

while true do
    if not deleting then
        i = i + 1
        ui:add_text(ta, string.sub(WORD, i, i))
        if i >= #WORD then
            deleting = true
        end
    else
        local cur = ui:get_text(ta)
        if cur == "" then
            deleting = false
            i = 0
        else
            ui:set_text(ta, string.sub(cur, 1, #cur - 1))
        end
    end

    local shown = ui:get_text(ta)
    ui:set_text(hint, "typed=" .. shown)
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)
    log.info("%s typed=%s", TAG, shown)
    print(string.format("%s typed=%s, delay %d ms", TAG, shown, STEP_MS))
    rt.delay(STEP_MS)
end

--[=[
  lvgl_keyboard — ui:keyboard 软键盘

  kb = ui:keyboard([parent,] [textarea])
  ui:set_textarea(kb, ta)
  没有触摸：add_text 逐字，set_text 删到空再打。
  不要循环 ui:handler()。

]=]
