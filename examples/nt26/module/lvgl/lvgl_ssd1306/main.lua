--[=[
  lvgl_ssd1306 — LVGL 刷到 SSD1306，总线是硬件 I2C0
  ============================================================================
  硬件
  ============================================================================
    硬件 I2C0（与 iic_ssd1306 同一对脚，不要再 i2c.new 占用 I2C0）
      Pin58  SDA
      Pin57  SCL
    从地址 0x3C，128×64。没接 RST 就不要填 rst。

  ============================================================================
  本例
  ============================================================================
    白底选中框、黑字，其余白字。右边是自绘的垂直滚动条。
    一屏四行，词条多过一屏时选中框留在可见区，滑块跟着当前项走。
    停在 Light / Switch / Check / Arc 时各打开一页控件，再回列表。
    1 bit 按亮度取半。背景用纯黑 0。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_ssd1306]"
local ROW_H = 16
local VISIBLE = 4
local THUMB_H = 12
local TRACK_H = 62
local ITEMS = {
    { name = "Sleep" },
    { name = "Light", page = "bar" },
    { name = "Switch", page = "switch" },
    { name = "Check", page = "check" },
    { name = "Arc", page = "arc" },
    { name = "Sound" },
    { name = "Time" },
    { name = "About" },
}

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new I2C0 ssd1306 128x64 addr=0x3C", TAG)

local panel, err = lcd.new({
    driver = lcd.SSD1306,
    bus = lcd.I2C0,
    hz = 400000,
    addr = 0x3C,
    width = 128,
    height = 64,
    rotate = lcd.ROTATE_0,
})
if not panel then
    halt("lcd.new fail: " .. tostring(err))
end

local lcd_info = panel:info()
local w, h = panel:size()
log.info("%s lcd ok driver=%s bus=%s fmt=%s %dx%d",
         TAG, tostring(lcd_info.driver), tostring(lcd_info.bus),
         tostring(lcd_info.fmt), w, h)

local ok, ui = pcall(lvgl.create, panel, {
    mem_max = 128 * 1024,
    color = "rgb565",
    dpi = 96,
    refr_ms = 100,
    full_buf = true,
    bg = 0,
})
if not ok then
    halt("lvgl.create fail: " .. tostring(ui))
end

local used0, peak0, limit0 = ui:mem()
log.info("%s lvgl ok mem used=%d peak=%d limit=%d",
         TAG, used0, peak0, limit0)

local box = ui:obj()
ui:set_size(box, 116, 15)
ui:set_style(box, {
    bg = 0xFFFFFF,
    radius = 2,
    border = 0,
    pad = 0,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
})

local labs = {}
for i = 1, VISIBLE do
    local lab = ui:label("")
    ui:set_style(lab, {
        pad = 0,
        bg_opa = lvgl.OPA_TRANSP,
        scrollable = false,
    })
    labs[i] = lab
end

local track = ui:obj()
ui:set_size(track, 1, TRACK_H)
ui:set_style(track, {
    bg = 0xFFFFFF,
    radius = 0,
    border = 0,
    pad = 0,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
})

local thumb = ui:obj()
ui:set_size(thumb, 3, THUMB_H)
ui:set_style(thumb, {
    bg = 0xFFFFFF,
    radius = 1,
    border = 0,
    pad = 0,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
})

local bar = ui:bar(0)
ui:set_size(bar, 112, 12)
ui:set_range(bar, 0, 100)
ui:set_dir(bar, lvgl.BAR_DIR_HORIZONTAL)
ui:set_mode(bar, lvgl.BAR_MODE_NORMAL)
ui:set_style(bar, {
    bg = 0,
    border = 1,
    border_color = 0xFFFFFF,
    radius = 0,
    pad = 1,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
})
ui:set_style(bar, { bg = 0xFFFFFF, radius = 0 }, lvgl.PART_INDICATOR)

local pval = ui:label("0")
ui:set_text_color(pval, 0xFFFFFF)
ui:set_style(pval, { pad = 0, bg_opa = lvgl.OPA_TRANSP, scrollable = false })

local sw = ui:switch()
ui:set_size(sw, 46, 22)
ui:set_style(sw, {
    bg = 0,
    border = 1,
    border_color = 0xFFFFFF,
    radius = 11,
    pad = 2,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
}, lvgl.PART_MAIN)
ui:set_style(sw, { bg = 0, radius = 11 }, lvgl.PART_INDICATOR)
ui:set_style(sw, { bg = 0xFFFFFF, radius = 11 },
             lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)
ui:set_style(sw, { bg = 0xFFFFFF, radius = 8 }, lvgl.PART_KNOB)
ui:set_value(sw, 0)

local cb = ui:checkbox("LED")
ui:set_text_color(cb, 0xFFFFFF)
ui:set_style(cb, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 2,
    outline_width = 0,
    shadow_width = 0,
    scrollable = false,
})
ui:set_style(cb, {
    bg = 0,
    border = 1,
    border_color = 0xFFFFFF,
    radius = 2,
}, lvgl.PART_INDICATOR)
ui:set_style(cb, {
    bg = 0xFFFFFF,
    border_color = 0xFFFFFF,
}, lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)
ui:set_value(cb, 0)

local arc = ui:arc(0)
ui:set_size(arc, 56, 56)
ui:set_range(arc, 0, 100)
ui:set_bg_angle(arc, 0, 270)
ui:set_style(arc, {
    bg_opa = lvgl.OPA_TRANSP,
    pad = 0,
    border = 0,
    outline_width = 0,
    shadow_width = 0,
    arc_color = 0xFFFFFF,
    arc_width = 2,
    scrollable = false,
})
ui:set_style(arc, { arc_color = 0xFFFFFF, arc_width = 5 }, lvgl.PART_INDICATOR)
ui:set_style(arc, { bg_opa = lvgl.OPA_TRANSP, border = 0 }, lvgl.PART_KNOB)

local top = 1

local function thumb_y(sel)
    local span = TRACK_H - THUMB_H
    return 1 + (sel - 1) * span // (#ITEMS - 1)
end

local function park_pages()
    ui:set_pos(bar, 8, 90)
    ui:set_pos(pval, 8, 110)
    ui:set_pos(sw, 40, 100)
    ui:set_pos(cb, 16, 120)
    ui:set_pos(arc, 36, 140)
end

local function park_list()
    ui:set_pos(box, 1, 80)
    ui:set_pos(track, 125, 80)
    ui:set_pos(thumb, 123, 80)
    for i = 1, VISIBLE do
        ui:set_pos(labs[i], 6, 80)
    end
end

local function show_list(sel)
    if sel < top then
        top = sel
    end
    if sel > top + VISIBLE - 1 then
        top = sel - VISIBLE + 1
    end
    park_pages()
    local slot = sel - top + 1
    ui:set_pos(box, 1, (slot - 1) * ROW_H)
    ui:set_pos(track, 125, 1)
    ui:set_pos(thumb, 123, thumb_y(sel))
    for i = 1, VISIBLE do
        local idx = top + i - 1
        ui:set_text(labs[i], ITEMS[idx].name)
        ui:set_pos(labs[i], 6, (i - 1) * ROW_H)
        ui:set_text_color(labs[i], (idx == sel) and 0 or 0xFFFFFF)
    end
end

local sel = 1
show_list(sel)
log.info("%s list %d items, scrollbar + bar/switch/check/arc", TAG, #ITEMS)

while true do
    rt.delay(650)
    sel = sel + 1
    if sel > #ITEMS then
        sel = 1
    end
    show_list(sel)
    log.info("%s sel %s", TAG, ITEMS[sel].name)

    local page = ITEMS[sel].page
    if page == "bar" then
        rt.delay(300)
        park_list()
        ui:set_pos(bar, 8, 26)
        ui:set_pos(pval, 8, 46)
        local value = 0
        while value <= 100 do
            ui:set_value(bar, value)
            ui:set_text(pval, string.format("%d", value))
            value = value + 25
            rt.delay(160)
        end
        show_list(sel)
    elseif page == "switch" then
        rt.delay(300)
        park_list()
        ui:set_pos(sw, 40, 21)
        ui:set_value(sw, 0)
        rt.delay(350)
        ui:set_value(sw, 1)
        rt.delay(450)
        ui:set_value(sw, 0)
        rt.delay(350)
        show_list(sel)
    elseif page == "check" then
        rt.delay(300)
        park_list()
        ui:set_pos(cb, 28, 22)
        ui:set_value(cb, 0)
        rt.delay(400)
        ui:set_value(cb, 1)
        rt.delay(500)
        ui:set_value(cb, 0)
        rt.delay(300)
        show_list(sel)
    elseif page == "arc" then
        rt.delay(300)
        park_list()
        ui:set_pos(arc, 36, 4)
        local value = 0
        while value <= 100 do
            ui:set_value(arc, value)
            value = value + 25
            rt.delay(160)
        end
        show_list(sel)
    end
end
