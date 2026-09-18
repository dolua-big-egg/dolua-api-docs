--[=[
  lvgl_msgbox demo — 消息框、脚注按钮、关闭
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
    ui:msgbox 建模态消息框（省略父亲 = 顶层遮罩）
    标题用创建参数 / set_text；正文用 add_text
    add_footer_btn 加 No / Yes，add_close_btn 加右上角 X
    没有触摸：add_state(PRESSED) 看按下，再 ui:click；回调里 ui:close
    关闭后句柄失效，下一轮重新建框
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_msgbox]"
local PRESS_MS = 220
local SHOW_MS = 900
local GAP_MS = 700

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then msgbox", TAG)

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

local title = ui:label("msgbox")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 8)

local hint = ui:label("choice=")
ui:set_text_color(hint, 0xA0A0A0)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)

local n = 0
local names = { "No", "Yes", "X" }

local function make_box()
    local mbox = ui:msgbox("Save?", "Overwrite file?")
    local no = ui:add_footer_btn(mbox, "No")
    local yes = ui:add_footer_btn(mbox, "Yes")
    local xbtn = ui:add_close_btn(mbox)

    local function pick(name)
        n = n + 1
        ui:set_text(hint, string.format("%s  n=%d", name, n))
        ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 32)
        log.info("%s clicked %s n=%d title=%s", TAG, name, n, tostring(ui:get_text(mbox)))
        print(string.format("%s clicked %s n=%d", TAG, name, n))
        ui:close(mbox)
    end

    ui:on_click(no, function()
        pick("No")
    end)
    ui:on_click(yes, function()
        pick("Yes")
    end)
    ui:on_click(xbtn, function()
        pick("X")
    end)

    return { no, yes, xbtn }
end

local i = 0
log.info("%s simulate press+click, no touch", TAG)

while true do
    i = i + 1
    if i > #names then
        i = 1
    end
    local btns = make_box()
    local btn = btns[i]
    rt.delay(SHOW_MS)
    ui:add_state(btn, lvgl.STATE_PRESSED)
    rt.delay(PRESS_MS)
    ui:click(btn)
    ui:remove_state(btn, lvgl.STATE_PRESSED)
    rt.delay(GAP_MS)
end

--[=[
  lvgl_msgbox — ui:msgbox 消息框

  mbox = ui:msgbox([parent,] [title [, text]])
      省略 parent：模态，带顶层遮罩
      带 parent：挂到该父亲上，非模态
  ui:set_text(mbox, title)          标题（没有则创建）
  ui:get_text(mbox)                 读标题；没有标题返回 ""
  ui:add_text(mbox, text)           正文多段，每次新起一段
  btn = ui:add_footer_btn(mbox, "OK")
  x   = ui:add_close_btn(mbox)      右上角 X；ui:click 不会走底层自关
  ui:close(mbox)                    拆掉框（模态连遮罩）；之后句柄失效

  脚注按钮：on_click 里自己 close。没有触摸时先 PRESSED 再 click。
  不要循环 ui:handler()。

]=]
