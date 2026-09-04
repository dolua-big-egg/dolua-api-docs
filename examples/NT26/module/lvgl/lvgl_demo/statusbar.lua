-- 顶栏：时间 HH:MM:SS、信号、满电。圆角屏左右留 pad。
-- 每秒 rt.tmr_loop 读 info 后改 text；回调马上返回。

local rt = require("rt")
local lcd = require("lcd")
local lvgl = require("lvgl")
local info = require("info")
local log = require("log")

local SYM_WIFI     = "\xEF\x87\xAB"  -- U+F1EB
local SYM_WARN     = "\xEF\x81\xB1"  -- U+F071
local SYM_BAT_FULL = "\xEF\x89\x80"  -- U+F240，默认满电，不绑数据

local M = {
    H = 32,
    BG = 0xFF0000,  -- RGB888，改这里换顶栏底色
    PAD = 18,       -- 右侧图标离边缘的距离
    CLOCK_X = 26,   -- 时间左边距，再往右改大这个数
}

local ui
local clock
local sig
local bat
local style_icon
local tmr_id
local last_hms = ""
local last_csq = -1

local function csq_color(csq)
    if csq == 99 or csq <= 0 then
        return lcd.RED
    elseif csq < 10 then
        return lcd.YELLOW
    elseif csq < 20 then
        return lcd.CYAN
    end
    return lcd.GREEN
end

local function bar_label(parent, text, x)
    local lab = ui:label(parent, text)
    ui:add_style(lab, style_icon)
    ui:set_pos(lab, x, 8)
    ui:set_text_color(lab, lcd.WHITE)
    return lab
end

function M.refresh()
    if ui == nil or clock == nil then
        return
    end
    local hms = info.times("%H:%M:%S")
    if type(hms) ~= "string" or hms == "" then
        hms = "--:--:--"
    end
    local csq = info.csq()
    if type(csq) ~= "number" then
        csq = 99
    end
    if hms == last_hms and csq == last_csq then
        return
    end
    last_hms = hms
    last_csq = csq
    ui:set_text(clock, hms)
    ui:set_text(sig, (csq == 99) and SYM_WARN or SYM_WIFI)
    ui:set_text_color(sig, csq_color(csq))
end

-- ui, { parent=, width=, [bg=], [pad=] }
function M.create(ui_inst, opts)
    opts = opts or {}
    ui = ui_inst
    local parent = opts.parent or ui:scr_act()
    local w = opts.width
    local h = opts.height or M.H
    local bg = opts.bg or M.BG
    local pad = opts.pad or M.PAD
    local clock_x = opts.clock_x or M.CLOCK_X
    local icon_w = 22
    local icon_gap = 8
    local bat_x = w - pad - icon_w
    local sig_x = bat_x - icon_gap - icon_w

    style_icon = ui:style({
        bg_opa = lvgl.OPA_TRANSP,
        pad = 0,
        border_width = 0,
    })

    local bar = ui:obj(parent)
    ui:set_pos(bar, 0, 0)
    ui:set_size(bar, w, h)
    ui:set_style(bar, {
        bg = bg,
        bg_opa = lvgl.OPA_COVER,
        radius = 0,
        pad = 0,
        border_width = 0,
        shadow_width = 0,
        clip_corner = false,
        scrollable = false,
        clickable = false,
    })

    clock = bar_label(bar, "--:--:--", clock_x)
    sig = bar_label(bar, SYM_WIFI, sig_x)
    bat = bar_label(bar, SYM_BAT_FULL, bat_x)

    M.refresh()

    if tmr_id then
        rt.tmr_delete(tmr_id)
        tmr_id = nil
    end
    tmr_id = rt.tmr_loop(1000, M.refresh)
    log.info("[statusbar] pad=%d clock_x=%d wifi_x=%d bat_x=%d tmr=%s",
             pad, clock_x, sig_x, bat_x, tostring(tmr_id))
    return bar
end

return M
