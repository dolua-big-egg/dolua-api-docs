--[=[
  spi_lvgl demo — lcd.new 同一套屏，再交给 lvgl.create
  ============================================================================
  硬件（与 spi_lcd / spi_st7789 相同）
  ============================================================================
    SPI0（与 UART2 默认脚重叠，必须 [uart.2] pin_map=1）
      Pin29  SPI0_SCLK
      Pin67  SPI0_MOSI
      GPIO8  CS

    GPIO32  BL
    GPIO31  DC
    GPIO30  RST
    240x280，Y 偏移 20。圆角屏：顶栏时间右移、Wi‑Fi/电池左移，见 statusbar.PAD。

  ============================================================================
  对接关系
  ============================================================================
    spi_lcd  ：panel:full / fill，C 层 lcd 自己画
    本 demo ：同一 panel 交给 lvgl.create；flush_cb → lua_lcd_flush → SPI DMA
             create 之后 Lua 再 panel:full/fill/flush 会失败（lcd bound to lvgl）
             屏幕背景必须走 LVGL：opts.bg 或 ui:set_bg
             刷屏 DMA 只在 C 的 LVGL flush 里异步，Lua SPI 保持同步

  须用已编入 lua_lvgl 的 AP 固件。默认字体 Montserrat 14（ASCII + FontAwesome 子集）。
  顶栏在 statusbar.lua：HH:MM:SS + 信号 + 满电；rt.tmr_loop 每秒改 text。
  Lua 不要循环 ui:handler()。主循环 rt.delay(-1)。
  图片：ui:img / ui:set_src，只认 JPEG 和 LVGL .bin。
  源：RAM string、{ ublob = name }、{ lfs = fs, path = "..." }。
  缩放：ui:set_scale(img, scale)，256 / lvgl.SCALE_NONE 为原尺寸；set_size 只改外框。
  本例程不附带图片文件，需要时自行放进 ublob / lfs 再 set_src。
  循环缩放见同目录 lvgl_img。
  字库：ui:font / ui:set_font，只认 LVGL 点阵 .bin（压缩亦可）与 TTF（靠文件头）。
  源同样是 RAM string、{ ublob = name }、{ lfs = fs, path = "..." }。
  TTF 要带 size（省略为 14）；点阵 .bin 忽略 size。必须持有 font。
  本例程不附带字库文件。

]=]

local rt = require("rt")
local log = require("log")
local lcd = require("lcd")
local lvgl = require("lvgl")
local statusbar = require("statusbar")

local TAG = "[spi_lvgl]"

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

log.info("%s lcd.new SPI0 st7789, then lvgl.create", TAG)

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

local pre_ok, pre_err = panel:full(lcd.WHITE)
log.info("%s lcd.full before create ok=%s err=%s",
         TAG, tostring(pre_ok), tostring(pre_err))

local ok, ui = pcall(lvgl.create, panel, {
    mem_max = 384 * 1024,
    color = "rgb565",
    dpi = 130,
    refr_ms = 33,
    double_buf = true,
    full_buf = true,
    theme = "dark",
    bg = 0x00F5F5,
})
if not ok then
    halt("lvgl.create fail: " .. tostring(ui))
end

local used0, peak0, limit0 = ui:mem()
log.info("%s lvgl ok mem used=%d peak=%d limit=%d",
         TAG, used0, peak0, limit0)

local full_ok, full_err = panel:full(lcd.RED)
log.info("%s lcd.full after create ok=%s err=%s (expect fail: bound to lvgl)",
         TAG, tostring(full_ok), tostring(full_err))

local scr = ui:scr_act()
statusbar.create(ui, {
    parent = scr,
    width = w,
})

local btn = ui:btn("NT26")
ui:set_size(btn, 72, 32)
ui:set_pos(btn, 16, statusbar.H + 16)

local hint = ui:label("no touch yet")
ui:set_pos(hint, 16, 150)

local stat = ui:label("mem ...")
ui:set_pos(stat, 16, 200)
do
    local used, _, limit = ui:mem()
    ui:set_text(stat, string.format("%d/%d", used, limit))
end

log.info("%s widgets ready, delay(-1)", TAG)
rt.delay(-1)

while true do
    rt.delay(600 * 1000)
end

--[=[
  spi_lvgl demo — C 层 lcd + lvgl

  require("lcd") + require("lvgl")，不要再 require("spi") 发屏命令。
  顶栏：require("statusbar")，须在 luaproj modules 里登记 statusbar.lua。

  ----------------------------------------------------------------------------
  lvgl.create(panel, opts) -> ui
  ----------------------------------------------------------------------------
    opts.mem_max    字节上限，走 cust 堆；默认 128*1024；0=不限制
                    整屏缓冲不够时 C 会自动抬升（+64KB 给控件）
    opts.color      "rgb565"（屏 GRAM）或 "rgb888"
    opts.dpi        默认 130
    opts.refr_ms    刷屏 timer 周期；闲时 LVGL 会 pause，有脏区/动画再 resume
    opts.double_buf 可写，当前忽略；底层强制单缓冲 + 阻塞 DMA
    opts.full_buf   整屏缓冲 DIRECT，默认 true；false 则 PARTIAL
    opts.buf_mode   "partial" | "direct" | "full"（覆盖 full_buf）
    opts.buf_lines  仅 PARTIAL 条带行数，默认 20
    opts.theme      "light"（默认，浅灰底）或 "dark"
    opts.bg         可选，覆盖主题背景；lcd.RED / 0xRRGGBB；省略则用主题

  ui:handler()                仅踢一脚 C 任务（兼容）；不要循环调用
  低功耗：rt.delay(-1)，刷屏/动画由 C 层 lv_timer_handler + resume_cb 负责
  ui:mem() -> used, peak, limit
  ui:scr_act()                当前屏幕（默认父亲）
  ui:label([parent,] text)    省略 parent = 当前屏幕；主题默认样式不改
  ui:btn([parent,] [text])
  ui:obj([parent])            空白容器，走默认主题（light 下是 card）
  ui:style({...})             新建 lv_style_t，不改主题。须在 Lua 里一直拿着引用
  ui:add_style(obj, style [, selector])
  ui:remove_style(obj, style [, selector])
  ui:set_style(obj, {...} [, selector])  写到该控件的 local style / flag
  style:set({...})            改已有 style，已 add 的控件会跟着刷新
  ui:set_radius(obj, r)       仍可用；等价 local radius
  ui:set_parent(obj, parent)  相当于 lv_obj_set_parent
  ui:set_text(label, text)
  ui:set_theme("light"|"dark")
  ui:set_bg([obj,] color)     省略 obj = 当前屏幕；只改 bg_color + 不透明
  ui:set_text_color(obj, color)
  ui:set_pos(obj, x, y)
  ui:set_size(obj, w, h)
  ui:invalidate([obj])        可选；省略 obj = 当前屏幕。一般不用
  ui:refr_pause()             可嵌套。暂停 C 任务刷屏，脏区照记
  ui:refr_resume()            与 pause 配对；hold 降到 0 后下次 handler 画出完整树
                             中间有 rt.delay/wait 时用：pause → 建控件/改 style → resume
  ui:center(obj)
  ui:img([parent,] [src])     图片；src 为字节 / { data= } / { ublob= } / { lfs=, path= }
  ui:set_src(img, src|nil)    换源或清像素；只认 JPEG 与 LVGL .bin
  ui:set_scale(img, scale)    缩放像素；256 / lvgl.SCALE_NONE 原尺寸
  ui:get_scale(img)           读当前因子
  ui:font(src [, size])       字库；点阵 .bin / TTF；源同上。TTF size 默认 14
  ui:set_font(obj, font|nil)  挂字库；nil 回默认字。必须一直拿着 font
  ui:deinit()

  statusbar.create(ui, { parent, width [, bg] [, pad] })
    时间 HH:MM:SS；rt.tmr_loop(1000) 改 text。圆角用 pad（默认 18）。

  style 表字段：bg / bg_color / bg_opa（0..255 或 "cover"/"transp"）
                text / text_color / radius / pad / pad_all
                pad_top / pad_bottom / pad_left / pad_right
                border / border_width / border_color
                outline_width / shadow_width / clip_corner
                scrollable / clickable（仅 set_style，不是 lv_style 属性）
                font（ui:font 的句柄）
  lvgl.OPA_TRANSP / lvgl.OPA_COVER / lvgl.SCALE_NONE

]=]
