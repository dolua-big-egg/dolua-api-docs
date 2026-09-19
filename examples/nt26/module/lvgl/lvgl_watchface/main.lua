--[=[
  lvgl_watchface demo — 模拟指针表盘
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
    真黑底 + 圆环刻度盘：60 格、12 个主刻
    时 / 分 / 秒三条折线指针（不要给指针 set_points，刻度盘自己管点）
    12 3 6 9；屏底 HH:MM 与日期
    info.time() 读本地墙钟，约 50ms 刷新一帧
    驻网后若尚未授时，再 ntp.get(..., auto_set=true) 写钟
    ntp.get 会占住整条 Lua 引擎线程，只在后台任务里问一次
    默认字是 ASCII，不要写汉字
    不要循环 ui:handler()。
    需要已编入 LINE + SCALE 的固件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")
local info = require("info")
local lp = require("lp")
local ntp = require("ntp")

local TAG = "[lvgl_watchface]"
local STEP_MS = 50
local LINK_WAIT_MS = 60 * 1000

local COL_BG = 0x000000
local COL_BEZEL = 0x3A3A3C
local COL_MINOR = 0x636366
local COL_MAJOR = 0xF2F2F7
local COL_NUM = 0xF2F2F7
local COL_TIME = 0xFFFFFF
local COL_DATE = 0x8E8E93
local COL_HAND = 0xF2F2F7
local COL_SEC = 0xFF375F
local COL_HUB = 0xF2F2F7
local COL_HUB_IN = 0xFF375F
local COL_SYNC = 0x48484A

local WEEK = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function make_label(ui, parent, text, color)
    local lab
    if parent then
        lab = ui:label(parent, text)
    else
        lab = ui:label(text)
    end
    ui:set_text_color(lab, color)
    return lab
end

local function make_needle(ui, scale, width, color)
    local ln = ui:line(scale)
    ui:set_style(ln, {
        bg_opa = lvgl.OPA_TRANSP,
        pad = 0,
        line_width = width,
        line_color = color,
        line_rounded = true,
        clickable = false,
        scrollable = false,
    })
    return ln
end

log.info("%s lcd.new SPI0 st7789, then analog watchface", TAG)

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
    refr_ms = 33,
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

local dial = ui:obj()
ui:set_size(dial, 240, 240)
ui:align(dial, lvgl.ALIGN_TOP_MID, 0, 0)
ui:set_style(dial, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 0,
    clickable = false,
    scrollable = false,
})

local sc = ui:scale(dial)
ui:set_size(sc, 228, 228)
ui:align(sc, lvgl.ALIGN_CENTER, 0, 0)
ui:set_style(sc, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 0,
    line_width = 2,
    line_color = COL_BEZEL,
    clickable = false,
    scrollable = false,
}, lvgl.PART_MAIN)
ui:set_style(sc, {
    line_width = 1,
    line_color = COL_MINOR,
    length = 8,
    line_rounded = true,
}, lvgl.PART_ITEMS)
ui:set_style(sc, {
    line_width = 2,
    line_color = COL_MAJOR,
    length = 14,
    line_rounded = true,
}, lvgl.PART_INDICATOR)
ui:set_mode(sc, lvgl.SCALE_MODE_ROUND_INNER)
ui:set_range(sc, 0, 3600)
ui:set_angle(sc, 360)
ui:set_rotation(sc, 270)
ui:set_ticks(sc, 60, 5, false)

local num_r = 82
local function hour_num(text, deg)
    local rad = math.rad(deg - 90)
    local lab = make_label(ui, sc, text, COL_NUM)
    ui:align(lab, lvgl.ALIGN_CENTER,
             math.floor(num_r * math.cos(rad) + 0.5),
             math.floor(num_r * math.sin(rad) + 0.5))
    return lab
end

hour_num("12", 0)
hour_num("3", 90)
hour_num("6", 180)
hour_num("9", 270)

local hour_ln = make_needle(ui, sc, 5, COL_HAND)
local min_ln = make_needle(ui, sc, 3, COL_HAND)
local sec_ln = make_needle(ui, sc, 2, COL_SEC)

local hub = ui:obj(dial)
ui:set_size(hub, 14, 14)
ui:align(hub, lvgl.ALIGN_CENTER, 0, 0)
ui:set_style(hub, {
    bg = COL_HUB,
    radius = 8,
    pad = 0,
    clickable = false,
    scrollable = false,
})

local hub_in = ui:obj(hub)
ui:set_size(hub_in, 6, 6)
ui:center(hub_in)
ui:set_style(hub_in, {
    bg = COL_HUB_IN,
    radius = 8,
    pad = 0,
    clickable = false,
    scrollable = false,
})

local time_lab = make_label(ui, nil, "--:--", COL_TIME)
ui:align(time_lab, lvgl.ALIGN_BOTTOM_MID, 0, -22)

local date_lab = make_label(ui, nil, "----", COL_DATE)
ui:align(date_lab, lvgl.ALIGN_BOTTOM_MID, 0, -6)

local last_hhmm = ""
local last_date = ""

local function set_lab(lab, text, color, y, cache_key)
    if cache_key == text then
        return text
    end
    ui:set_text(lab, text)
    if color then
        ui:set_text_color(lab, color)
    end
    ui:align(lab, lvgl.ALIGN_BOTTOM_MID, 0, y)
    return text
end

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

while true do
    local t = info.time()
    if t then
        local hhmm = string.format("%02d:%02d", t.hour, t.minute)
        local wd = WEEK[(t.weekday or 0) + 1] or "SUN"
        local date = string.format("%s  %d", wd, t.day)
        if not info.time_ready() then
            date = date .. "  sync"
        end
        local ms = t.millisecond or 0
        local h12 = t.hour % 12
        last_hhmm = set_lab(time_lab, hhmm, COL_TIME, -22, last_hhmm)
        last_date = set_lab(date_lab, date, COL_DATE, -6, last_date)
        ui:set_needle(sc, hour_ln, 52, h12 * 300 + t.minute * 5)
        ui:set_needle(sc, min_ln, 74, t.minute * 60 + t.second)
        ui:set_needle(sc, sec_ln, 92, t.second * 60 + (ms * 60) // 1000)
    else
        last_hhmm = set_lab(time_lab, "--:--", COL_TIME, -22, last_hhmm)
        last_date = set_lab(date_lab, "sync", COL_SYNC, -6, last_date)
        ui:set_needle(sc, hour_ln, 52, 0)
        ui:set_needle(sc, min_ln, 74, 0)
        ui:set_needle(sc, sec_ln, 92, 0)
    end
    rt.delay(STEP_MS)
end

--[=[
  lvgl_watchface — 模拟指针表盘

  圆环刻度 + 时分秒折线指针；屏底 HH:MM 与星期日期
  授时：NITZ 优先；未就绪时 ntp.get(..., auto_set=true) 只问一次
  不要循环 ui:handler()。

]=]
