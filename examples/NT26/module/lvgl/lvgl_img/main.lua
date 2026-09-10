--[=[
  lvgl_img demo — ublob JPEG 上屏，再循环缩小 / 放大
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
  图片
  ============================================================================
    本例程不附带图片文件。工程内置文件系统放入 photo.jpg，存储位置选 blob，
    勾选后再下载。脚本只认 JPEG / LVGL .bin，靠文件头，不靠扩展名。
    ui:img / ui:set_src 的源：{ ublob = "photo.jpg" }
    解码一次挂 RGB565；图太大或 mem_max 不够会失败（no mem / decode failed）。

  ============================================================================
  缩放
  ============================================================================
    ui:set_scale(img, scale)  缩放像素。256 / lvgl.SCALE_NONE = 原尺寸。
    ui:set_size 只改外框，不会把图等比缩小。本 demo 不钉外框，每次缩放后 center。
    主循环：64 ↔ 256 来回，不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local ublob = require("ublob")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_img]"
local PHOTO = "photo.jpg"
local SCALE_MIN = 64
local SCALE_STEP = 4
local SCALE_DELAY_MS = 33

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then show ublob %s", TAG, PHOTO)

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

local st, serr = ublob.stat(PHOTO)
if st then
    log.info("%s ublob %s size=%d", TAG, st.name, st.size)
else
    log.error("%s ublob.stat %s fail: %s (勾选内置 photo.jpg，存储选 blob 后再下载)",
              TAG, PHOTO, tostring(serr))
end

-- 先建空图，再 set_src：失败时控件还在，能把原因写到标签上
local pic = ui:img()
local hint = ui:label("")
ui:set_pos(hint, 8, 8)

local src_ok, src_err = ui:set_src(pic, { ublob = PHOTO })
if not src_ok then
    ui:set_text(hint, tostring(src_err))
    log.error("%s set_src %s fail: %s", TAG, PHOTO, tostring(src_err))
    rt.delay(-1)
    while true do
        rt.delay(600 * 1000)
    end
end

ui:set_text(hint, "")
ui:set_scale(pic, lvgl.SCALE_NONE)
ui:center(pic)
local used, peak, limit = ui:mem()
log.info("%s show %s ok mem used=%d peak=%d limit=%d scale=%d",
         TAG, PHOTO, used, peak, limit, lvgl.SCALE_NONE)

local scale = lvgl.SCALE_NONE
local dir = -SCALE_STEP
log.info("%s pulse scale %d..%d", TAG, SCALE_MIN, lvgl.SCALE_NONE)

while true do
    scale = scale + dir
    if scale <= SCALE_MIN then
        scale = SCALE_MIN
        dir = SCALE_STEP
    elseif scale >= lvgl.SCALE_NONE then
        scale = lvgl.SCALE_NONE
        dir = -SCALE_STEP
    end
    ui:set_scale(pic, scale)
    ui:center(pic)
    rt.delay(SCALE_DELAY_MS)
end

--[=[
  lvgl_img — ublob JPEG → ui:img → set_scale 循环

  ----------------------------------------------------------------------------
  下载前
  ----------------------------------------------------------------------------
    1) 工程内置文件系统放入 photo.jpg（仓库不附带）
    2) 存储位置选 blob（不是 ufs）
    3) 勾选 photo.jpg 再下载；设备上文件名就是 photo.jpg

  ----------------------------------------------------------------------------
  ui:img([parent,] [src]) / ui:set_src(img, src)
  ----------------------------------------------------------------------------
    src  { ublob = "photo.jpg" }   从 ublob 读明文再解码
         { data = bytes }          RAM 整份 JPEG / .bin
         { lfs = fs, path = "..." } 已挂载 LittleFS
         nil                       清像素（仅 set_src）
    只认 JPEG（FF D8 FF）和 LVGL .bin。BMP/PNG 不支持。
    img(src) 解码失败抛错；set_src 失败回 false, 文案，原图还在。

  ----------------------------------------------------------------------------
  ui:set_scale(img, scale) / ui:get_scale(img)
  ----------------------------------------------------------------------------
    scale  256 / lvgl.SCALE_NONE = 原尺寸
           128 = 一半，512 = 两倍，0 = 不画
    只认 ui:img 句柄。失败 false, "not an image" / "bad scale" / "lvgl busy"
    不另占像素。set_size 只改外框，不会等比缩放。

  常见失败
    not found                 设备上没有这份 ublob（没勾选 / 没下到 blob）
    unsupported image format  不是 JPEG / .bin
    decode failed             头对了但解不开（损坏、超尺寸）
    no mem                    像素不够，加大 create 的 mem_max
    bad src                   空文件或名字非法

  不要循环 ui:handler()。本 demo 主循环是 set_scale + rt.delay。

]=]
