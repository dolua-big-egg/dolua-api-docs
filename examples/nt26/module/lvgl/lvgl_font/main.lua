--[=[
  lvgl_font demo — 中间 120x60 图，下方一行字
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
  资源（内置文件系统，存储选 blob，勾选后再下载）
  ============================================================================
    dolua.jpg                 120x60 JPEG → 屏幕正中
    fusion-pixel-10px-10.bin  「一行脚本，万里互联」→ 图片下方
    必须持有 font。点阵 .bin 不必传 size。

  不要循环 ui:handler()。主循环 rt.delay(-1)。

]=]

local rt = require("rt")
local log = require("log")
local ublob = require("ublob")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_font]"
local PHOTO = "dolua.jpg"
local FONT_NAME = "fusion-pixel-10px-10.bin"
local SUBTITLE = "一行脚本，万里互联"

local IMG_W = 120
local IMG_H = 60
local TEXT_ADV = 28
local TEXT_H = 28
local GAP = 12

local font

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789", TAG)

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

local function blob_info(name)
    local st, serr = ublob.stat(name)
    if st then
        log.info("%s ublob %s size=%d", TAG, st.name, st.size)
    else
        log.error("%s ublob.stat %s fail: %s (勾选内置文件，存储选 blob 后再下载)",
                  TAG, name, tostring(serr))
    end
end

blob_info(PHOTO)
blob_info(FONT_NAME)

local hint = ui:label("")
ui:set_pos(hint, 8, 8)

local pic = ui:img()
local src_ok, src_err = ui:set_src(pic, { ublob = PHOTO })
if not src_ok then
    ui:set_text(hint, tostring(src_err))
    halt("set_src " .. PHOTO .. " " .. tostring(src_err))
end
ui:set_scale(pic, lvgl.SCALE_NONE)
ui:center(pic)

local fok, ferr = pcall(ui.font, ui, { ublob = FONT_NAME })
if not fok then
    ui:set_text(hint, tostring(ferr))
    halt("font " .. FONT_NAME .. " " .. tostring(ferr))
end
font = ferr

-- 9 个字 advance 28，合计 252，比屏宽 240 多一点，靠左 0 以免裁掉首字
local sub_w = TEXT_ADV * 9
local sub_x = (w - sub_w) // 2
if sub_x < 0 then
    sub_x = 0
end
local sub_y = (h - IMG_H) // 2 + IMG_H + GAP

local sub = ui:label(SUBTITLE)
ui:set_font(sub, font)
ui:set_text_color(sub, 0xF5F5F5)
ui:set_pos(sub, sub_x, sub_y)

local used, peak, limit = ui:mem()
log.info("%s ready mem used=%d peak=%d limit=%d",
         TAG, used, peak, limit)

log.info("%s widgets ready, delay(-1)", TAG)
rt.delay(-1)

while true do
    rt.delay(600 * 1000)
end

--[=[
  lvgl_font — ublob JPEG + 点阵 .bin

  ----------------------------------------------------------------------------
  下载前
  ----------------------------------------------------------------------------
    dolua.jpg                  blob，120x60
    fusion-pixel-10px-10.bin   blob，「一行脚本，万里互联」
    rtu_config [uart.2] pin_map=1

  ui:img / ui:set_src({ ublob = "dolua.jpg" })
  ui:font({ ublob = "fusion-pixel-10px-10.bin" }) / ui:set_font
  必须一直拿着 font。不要循环 ui:handler()。

]=]
