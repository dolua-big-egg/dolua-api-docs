--[=[
  lvgl_switch demo — 开关开合与多种外观
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
    ui:switch 建开关
    set_value(true/false 或 0/1) 开合；get_value 读 0/1
    set_dir 水平 / 垂直
    set_style + PART_MAIN / PART_INDICATOR / PART_KNOB 改轨道、填充、滑块
    没有触摸时用脚本改值，不要指望 ui:click 去拨 LVGL 状态
    不要循环 ui:handler()。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")

local TAG = "[lvgl_switch]"
local STEP_MS = 900

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function caption(ui, text, y)
    local lab = ui:label(text)
    ui:set_text_color(lab, 0xA0A0A0)
    ui:align(lab, lvgl.ALIGN_TOP_LEFT, 12, y)
    return lab
end

local function paint_pill(ui, sw, track, on_fill, knob, pad)
    ui:set_style(sw, {
        bg = track,
        radius = 99,
        pad = pad,
    }, lvgl.PART_MAIN)
    ui:set_style(sw, { bg = track, radius = 99 }, lvgl.PART_INDICATOR)
    ui:set_style(sw, { bg = on_fill, radius = 99 },
                 lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)
    ui:set_style(sw, { bg = knob, radius = 99 }, lvgl.PART_KNOB)
end

log.info("%s lcd.new SPI0 st7789, then switch styles", TAG)

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

local title = ui:label("switch")
ui:set_text_color(title, 0xFFFFFF)
ui:align(title, lvgl.ALIGN_TOP_MID, 0, 6)

local hint = ui:label("t=0 g=0 r=0 b=0 v=0")
ui:set_text_color(hint, 0x808090)
ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)

-- 1. 主题默认
caption(ui, "theme", 48)
local sw_theme = ui:switch()
ui:set_size(sw_theme, 56, 28)
ui:align(sw_theme, lvgl.ALIGN_TOP_RIGHT, -16, 46)

-- 2. 绿色胶囊
caption(ui, "green", 84)
local sw_green = ui:switch()
ui:set_size(sw_green, 56, 28)
ui:align(sw_green, lvgl.ALIGN_TOP_RIGHT, -16, 82)
paint_pill(ui, sw_green, 0x3A3A48, 0x34C759, 0xF5F5F7, 3)

-- 3. 红色危险
caption(ui, "red", 120)
local sw_red = ui:switch()
ui:set_size(sw_red, 56, 28)
ui:align(sw_red, lvgl.ALIGN_TOP_RIGHT, -16, 118)
paint_pill(ui, sw_red, 0x3A3A48, 0xFF3B30, 0xF5F5F7, 3)

-- 4. 大号蓝色
caption(ui, "big", 156)
local sw_big = ui:switch()
ui:set_size(sw_big, 88, 40)
ui:align(sw_big, lvgl.ALIGN_TOP_RIGHT, -16, 150)
paint_pill(ui, sw_big, 0x2C2C38, 0x0A84FF, 0xFFFFFF, 4)

-- 5. 垂直琥珀色
caption(ui, "vert", 204)
local sw_vert = ui:switch()
ui:set_dir(sw_vert, lvgl.SWITCH_DIR_VERTICAL)
ui:set_size(sw_vert, 32, 60)
ui:align(sw_vert, lvgl.ALIGN_TOP_RIGHT, -28, 196)
paint_pill(ui, sw_vert, 0x3A3A48, 0xFF9F0A, 0x1C1C1E, 3)

local sws = { sw_theme, sw_green, sw_red, sw_big, sw_vert }
local names = { "theme", "green", "red", "big", "vert" }

ui:set_value(sw_green, true)
ui:set_value(sw_big, true)

local step = 0
log.info("%s toggle styles every %d ms", TAG, STEP_MS)

while true do
    step = step + 1
    local bits = {}
    for i, sw in ipairs(sws) do
        local on = ((step + i) % 2) == 0
        ui:set_value(sw, on)
        bits[#bits + 1] = string.format("%s=%d", names[i]:sub(1, 1),
                                        ui:get_value(sw))
    end
    local line = table.concat(bits, " ")
    ui:set_text(hint, line)
    ui:align(hint, lvgl.ALIGN_TOP_MID, 0, 26)
    log.info("%s %s dir(vert)=%d", TAG, line, ui:get_dir(sw_vert))
    print(string.format("%s %s, delay %d ms", TAG, line, STEP_MS))
    rt.delay(STEP_MS)
end

--[=[
  lvgl_switch — ui:switch 开关

  ui:switch([parent])
  ui:set_value(sw, true | false | 0 | 1)
  ui:get_value(sw)                 -- 0 关，1 开
  ui:set_dir(sw, SWITCH_DIR_HORIZONTAL | VERTICAL | AUTO)
  ui:set_style(sw, props, PART_MAIN)
  ui:set_style(sw, props, PART_INDICATOR | STATE_CHECKED)
  ui:set_style(sw, props, PART_KNOB)

  不要循环 ui:handler()。本 demo 主循环是 set_value + rt.delay。

]=]
