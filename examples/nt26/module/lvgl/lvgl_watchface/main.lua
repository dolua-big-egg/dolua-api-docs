--[=[
  lvgl_watchface demo — Apple Watch Simple 复刻
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
  素材（内置文件系统，存储选 blob，勾选后下载）
  ============================================================================
    hour.bin    70x16   时针，LVGL RGB565，针尖朝右
    minute.bin  104x14  分针
    秒针用折线，不要每帧旋转图片。
    脚本用 { ublob = 文件名 }。

  ============================================================================
  本例测什么
  ============================================================================
    时/分：图片指针 + set_pivot + set_needle（图须朝右）；角度没变就不要重设
    秒针：折线 set_needle
    info.time() 读本地墙钟，约 200ms 刷新一帧
    驻网后若尚未授时，再 ntp.get(..., auto_set=true) 写钟
    ntp.get 会占住整条 Lua 引擎线程，只在后台任务里问一次
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local ublob = require("ublob")
local lcd = require("lcd")
local lvgl = require("lvgl")
local info = require("info")
local lp = require("lp")
local ntp = require("ntp")

local TAG = "[lvgl_watchface]"
local STEP_MS = 200
local LINK_WAIT_MS = 60 * 1000
local SEC_LEN = 108

local COL_BG = 0x000000
local COL_AZURE = 0x8A99A0

-- 与 hour.bin / minute.bin 像素尺寸一致；轴心在左缘中点
local HOUR_W, HOUR_H = 70, 16
local MIN_W, MIN_H = 104, 14

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function blob_info(name)
    local st, serr = ublob.stat(name)
    if st then
        log.info("%s ublob %s size=%d", TAG, st.name, st.size)
    else
        log.error("%s ublob.stat %s fail: %s (勾选内置 .bin，存储选 blob 后再下载)",
                  TAG, name, tostring(serr))
    end
end

local function load_hand(ui, scale, name, w, h)
    local img = ui:img(scale)
    local ok, err = ui:set_src(img, { ublob = name })
    if not ok then
        halt("set_src " .. name .. " " .. tostring(err))
    end
    ui:set_style(img, {
        bg_opa = lvgl.OPA_TRANSP,
        pad = 0,
        clickable = false,
        scrollable = false,
    })
    ui:set_pivot(img, 0, h // 2)
    ui:align(img, lvgl.ALIGN_CENTER, w // 2, 0)
    return img
end

local function make_sec(ui, scale)
    local ln = ui:line(scale)
    ui:set_style(ln, {
        bg_opa = lvgl.OPA_TRANSP,
        pad = 0,
        border = 0,
        outline_width = 0,
        line_width = 2,
        line_color = COL_AZURE,
        line_rounded = true,
        clickable = false,
        scrollable = false,
    })
    return ln
end

local function needle_if(ui, scale, needle, value, last)
    if value == last then
        return last
    end
    ui:set_needle(scale, needle, value)
    return value
end

local function sec_if(ui, scale, needle, value, last)
    if value == last then
        return last
    end
    ui:set_needle(scale, needle, SEC_LEN, value)
    return value
end

log.info("%s lcd.new SPI0 st7789, then Simple watchface", TAG)

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
local scr_w, scr_h = panel:size()
log.info("%s lcd ok driver=%s bus=%s %dx%d",
         TAG, tostring(lcd_info.driver), tostring(lcd_info.bus), scr_w, scr_h)

local ok, ui = pcall(lvgl.create, panel, {
    mem_max = 384 * 1024,
    color = "rgb565",
    dpi = 130,
    refr_ms = 100,
    full_buf = true,
    theme = "dark",
    bg = COL_BG,
})
if not ok then
    halt("lvgl.create fail: " .. tostring(ui))
end

local used0, peak0, limit0 = ui:mem()
log.info("%s lvgl ok mem used=%d peak=%d limit=%d",
         TAG, used0, peak0, limit0)

blob_info("hour.bin")
blob_info("minute.bin")

local dial = ui:obj()
ui:set_size(dial, 240, 240)
ui:align(dial, lvgl.ALIGN_CENTER, 0, 0)
ui:set_style(dial, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 0,
    border = 0,
    outline_width = 0,
    clickable = false,
    scrollable = false,
})

-- 刻度盘只当指针的极坐标。圆环走的是 arc 不是 line；刻度关掉。
local sc = ui:scale(dial)
ui:set_size(sc, 240, 240)
ui:center(sc)
ui:set_style(sc, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 0,
    border = 0,
    outline_width = 0,
    line_width = 0,
    line_opa = lvgl.OPA_TRANSP,
    arc_width = 0,
    clickable = false,
    scrollable = false,
}, lvgl.PART_MAIN)
ui:set_style(sc, {
    line_width = 0,
    line_opa = lvgl.OPA_TRANSP,
    length = 0,
}, lvgl.PART_ITEMS)
ui:set_style(sc, {
    line_width = 0,
    line_opa = lvgl.OPA_TRANSP,
    length = 0,
}, lvgl.PART_INDICATOR)
ui:set_mode(sc, lvgl.SCALE_MODE_ROUND_INNER)
ui:set_range(sc, 0, 3600)
ui:set_angle(sc, 360)
ui:set_rotation(sc, 270)
ui:set_ticks(sc, 0, 0, false)

local hour_img = load_hand(ui, sc, "hour.bin", HOUR_W, HOUR_H)
local min_img = load_hand(ui, sc, "minute.bin", MIN_W, MIN_H)
local sec_ln = make_sec(ui, sc)

local hub = ui:obj(dial)
ui:set_size(hub, 12, 12)
ui:align(hub, lvgl.ALIGN_CENTER, 0, 0)
ui:set_style(hub, {
    bg = COL_AZURE,
    radius = 8,
    pad = 0,
    border = 0,
    outline_width = 0,
    clickable = false,
    scrollable = false,
})

rt.task_start(function()
    log.info("%s wait_link %d ms", TAG, LINK_WAIT_MS)
    local linked = lp.wait_link(LINK_WAIT_MS)
    if not linked then
        log.warn("%s no network, keep local clock", TAG)
        return
    end
    if info.time_ready() then
        log.info("%s time already ready", TAG)
        return
    end
    log.info("%s ntp auto_set", TAG)
    local s = ntp.get(nil, nil, nil, nil, true)
    log.info("%s ntp %s", TAG, tostring(s))
end)

log.info("%s run clock", TAG)

local last_h = -1
local last_m = -1
local last_s = -1

while true do
    local t = info.time()
    if t then
        local h12 = t.hour % 12
        last_h = needle_if(ui, sc, hour_img, h12 * 300 + t.minute * 5, last_h)
        last_m = needle_if(ui, sc, min_img, t.minute * 60 + t.second, last_m)
        last_s = sec_if(ui, sc, sec_ln, t.second * 60, last_s)
    else
        last_h = needle_if(ui, sc, hour_img, 0, last_h)
        last_m = needle_if(ui, sc, min_img, 0, last_m)
        last_s = sec_if(ui, sc, sec_ln, 0, last_s)
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_watchface — Apple Watch Simple

  黑底、无刻度；时/分图片指针，秒针折线
  内置 hour.bin / minute.bin，存储选 blob，勾选后下载
  授时：NITZ 优先；未就绪时 ntp.get(..., auto_set=true) 只问一次
  不要循环 ui:handler()。

]=]
