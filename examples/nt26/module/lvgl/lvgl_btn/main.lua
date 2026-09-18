--[=[
  lvgl_btn demo — 按钮、on_click、模拟点按
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
    ui:btn 建按钮（创建时带文字；按钮本身不能 set_text）
    on_click 登记点击；回调是一次性任务，可 rt.delay
    没有触摸：add_state(PRESSED) 让主题按下动画上屏，再 ui:click，再松开
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_btn]"
local PRESS_MS = 220
local STEP_MS = 700

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then btn", TAG)

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

local title = ui:label("btn")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("click=")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local n = 0

local function hook(btn, name)
    ui:on_click(btn, function(obj, ev)
        n = n + 1
        ui:set_text(hint, string.format("%s  n=%d", name, n))
        ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
        log.info("%s clicked %s n=%d ev=%s", TAG, name, n, ev.name)
        print(string.format("%s clicked %s n=%d", TAG, name, n))
    end)
end

local btn_ok = ui:btn("OK")
ui:set_size(btn_ok, 88, 40)
ui:align(btn_ok, lvgl.ALIGN_TOP_LEFT, 24, 64)
hook(btn_ok, "OK")

local btn_go = ui:btn("Go")
ui:set_size(btn_go, 88, 40)
ui:align(btn_go, lvgl.ALIGN_TOP_RIGHT, -24, 64)
ui:set_style(btn_go, { bg = 0x34C759, radius = 8 })
ui:set_style(btn_go, { bg = 0x1F7A32 }, lvgl.STATE_PRESSED)
hook(btn_go, "Go")

local btn_stop = ui:btn("Stop")
ui:set_size(btn_stop, 88, 40)
ui:align(btn_stop, lvgl.ALIGN_TOP_LEFT, 24, 120)
ui:set_style(btn_stop, { bg = 0xFF3B30, radius = 8 })
ui:set_style(btn_stop, { bg = 0xB4231A }, lvgl.STATE_PRESSED)
hook(btn_stop, "Stop")

local btn_wide = ui:btn("CLICK")
ui:set_size(btn_wide, 88, 40)
ui:align(btn_wide, lvgl.ALIGN_TOP_RIGHT, -24, 120)
ui:set_style(btn_wide, { bg = 0x0A84FF, radius = 20 })
ui:set_style(btn_wide, { bg = 0x0666C4 }, lvgl.STATE_PRESSED)
hook(btn_wide, "CLICK")

local btns = { btn_ok, btn_go, btn_stop, btn_wide }
local i = 0
log.info("%s simulate press+click, no touch", TAG)

while true do
    i = i + 1
    if i > #btns then
        i = 1
    end
    local btn = btns[i]
    ui:add_state(btn, lvgl.STATE_PRESSED)
    rt.delay(PRESS_MS)
    ui:click(btn)
    ui:remove_state(btn, lvgl.STATE_PRESSED)
    rt.delay(STEP_MS)
end

--[=[
  lvgl_btn — ui:btn 按钮

  btn = ui:btn([parent,] [text])     文字只在创建时设，按钮不能 set_text
  ui:on_click(btn, function(obj, ev) ... end)
  ui:add_state(btn, STATE_PRESSED)   主题按下态（变暗、略放大）
  ui:click(btn)                      没有触摸时用它模拟点按
  ui:remove_state(btn, STATE_PRESSED)
  ev.name == "clicked"

  click 只投递，不改按下态。要看见按压：先 add_state，delay 让出再 click / remove_state。
  不要循环 ui:handler()。

]=]
