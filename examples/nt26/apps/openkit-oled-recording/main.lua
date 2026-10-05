--[=[
  openkit-oled-recording — 按住录音、松开存盘，屏上翻看最近五条
  ============================================================================
  硬件
  ============================================================================
    OpenKit 屏和麦克风共用一路 LDO，接在 NET 灯上：GPIO25 / PIN 16。
    rtu_config.conf 的 [net_led] enable=0 把这只脚交给脚本，先拉高再开 I2C。
    屏：SSD1306，硬件 I2C1，SCL PIN 57（scl_pin_map = 3），SDA PIN 66（sda_pin_map = 0），
    从地址 0x3C，128×64。
    麦克风：ES8311，模组做 I2S 主机。寄存器走硬件 I2C0。
    scl_pin_map = 2：SCL 是 PDDR 32（PIN 39）。
    sda_pin_map = 2：SDA 是 PDDR 31（PIN 38）。
    KEY0：PIN 5（GPIO20）。按住录音，松开结束。
    KEY1：PIN 19（GPIO22）。点一下翻到下一条，按住约半秒播放当前这条。
    两只键上拉，按下为低。

  ============================================================================
  本例
  ============================================================================
    列表最多五条，新的在最上。一屏四行，第五条靠 KEY1 翻出来。
    按下 KEY0 进入录音页：英文 Recording，进度条按 20 秒走。
    KEY1 点一下翻页。按住约半秒播放当前选中的那条，松手不会再翻一页。
    播放页显示 Playing 和进度，播完回列表。播放走 play_to，读 ublob 里带 AMR-WB 头的文件。
    松开，或者满 20 秒，就停录并写入 ublob，然后回到列表。
    满 20 秒时如果还按着，要先松开再按，才会开始下一条。
    录音走 record_start：回调里只把裸 AMR 帧放进表，不写盘。
    停掉之后再拼上 #!AMR-WB 头，一次写入 ublob。回调里不要 rt.delay。
    每批 5 帧（100ms）。松开时还没凑满的尾巴不会进文件。
    短于一批的按下不存。
    16 kHz AMR-WB，一条 20 秒大约 32KB。五条加起来要留在脚本区和 ublob 共用的配额里。
    播音参数用 play_ 开头，录音参数用 mic_ 开头。说明写在下面的 audio.open、PLAY 旁边。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local lcd = require("lcd")
local lvgl = require("lvgl")
local audio = require("audio")
local ublob = require("ublob")

local TAG = "[rec]"
local ROW_H = 16
local VISIBLE = 4
local THUMB_H = 12
local TRACK_H = 62
local MAX_CLIPS = 5
local SECONDS = 20
local FRAME_MS = 20
local BATCH = 5
local TOTAL = SECONDS * 1000 / FRAME_MS
local AMR_WB_HDR = "#!AMR-WB\n"
local POLL_MS = 30
local NAV_HOLD = 15

-- 播音处理。喇叭响度在下面的 play_volume（0~100）。
-- 均衡器 eq 不要写：改了它 CP 就会复位。新固件会忽略 eq = false，旧固件写了就复位。
-- 滋滋声：压缩里的 expandThreshold 是噪声门，数字是分贝×64。
-- 还嫌吵就改成 -1280（-20 dB）；人声被切掉就改回 -2304（-36 dB）。
local PLAY = {
    ans = false,
    drc = {
        on = true,
        expandThreshold = -1920, -- 噪声门 -30 dB。出厂 -2880（-45 dB）
        expandRatio = -51,       -- 压下去的力度，出厂 -51。更负更狠
    },
    agc = false,                 -- 自动增益会把滋滋声一起抬高，保持关
}

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local board_pwr = gpio.open(gpio.BY_GPIO, 25)
if not board_pwr or not board_pwr:config(true, true) then
    halt("board LDO gpio25 config fail")
end
log.info("%s board LDO on gpio25 pin16", TAG)
rt.delay(100)

local key_rec = gpio.open(gpio.BY_PINNO, 5)
local key_nav = gpio.open(gpio.BY_PINNO, 19)
if not key_rec or not key_nav then
    halt("key open fail")
end
if not key_rec:config(false, false, gpio.PULL_UP) or not key_nav:config(false, false, gpio.PULL_UP) then
    halt("key config fail")
end

local function pressed(pin)
    return pin:get() == 0
end

local panel, lcd_err = lcd.new({
    driver = lcd.SSD1306,
    bus = lcd.I2C1,
    scl_pin_map = 3,
    sda_pin_map = 0,
    hz = 400000,
    addr = 0x3C,
    width = 128,
    height = 64,
    rotate = lcd.ROTATE_0,
})
if not panel then
    halt("lcd.new fail: " .. tostring(lcd_err))
end

local ok_ui, ui = pcall(lvgl.create, panel, {
    mem_max = 128 * 1024,
    color = "rgb565",
    dpi = 96,
    refr_ms = 100,
    full_buf = true,
    bg = 0,
})
if not ok_ui then
    halt("lvgl.create fail: " .. tostring(ui))
end

local dev, open_err = audio.open(audio.ES8311, {
    i2c = audio.I2C0,
    scl_pin_map = 2,
    sda_pin_map = 2,
    rate = audio.RATE_16K,
    -- 播音
    play_volume = 60,         -- 喇叭响度 0~100，越大越响。播放中可 dev:set_play_volume(80)
    play_diff = true,         -- true 差分线出，接 CST8302A。false 单端耳机
    play = PLAY,              -- 下行降噪/压缩/增益/均衡，字段说明在上面的 PLAY
    -- 录音
    mic_gain = 8,             -- 麦克风 PGA，0~10，每档 3dB。原来 10，模拟增益大时滋滋声明显
    mic_scale = 5,            -- ADC 模拟放大，0~7，每档 6dB。原来 7 = 42dB
    mic_volume = 230,         -- 数字录音音量 0~255，191 = 0dB。模拟降下来后用数字补一点响度
})
if not dev then
    halt("audio open failed: " .. tostring(open_err))
end

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

local title = ui:label("Recording")
ui:set_text_color(title, 0xFFFFFF)
ui:set_style(title, { pad = 0, bg_opa = lvgl.OPA_TRANSP, scrollable = false })

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

local ptime = ui:label("0.0 / 20")
ui:set_text_color(ptime, 0xFFFFFF)
ui:set_style(ptime, { pad = 0, bg_opa = lvgl.OPA_TRANSP, scrollable = false })

local clips = {}
local sel = 1
local top = 1
local seq = 1
local phase = "list"
local live = false
local got = 0
local chunks = {}
local wait_up = false
local nav_n = 0

local function thumb_y(index, n)
    if n <= 1 then
        return 1
    end
    local span = TRACK_H - THUMB_H
    return 1 + (index - 1) * span // (n - 1)
end

local function park_rec()
    ui:set_pos(title, 8, 80)
    ui:set_pos(bar, 8, 96)
    ui:set_pos(ptime, 8, 112)
end

local function park_list()
    ui:set_pos(box, 1, 80)
    ui:set_pos(track, 125, 80)
    ui:set_pos(thumb, 123, 80)
    for i = 1, VISIBLE do
        ui:set_pos(labs[i], 6, 80)
    end
end

local function show_list()
    park_rec()
    local n = #clips
    if n == 0 then
        park_list()
        ui:set_text(labs[1], "Empty")
        ui:set_text_color(labs[1], 0xFFFFFF)
        ui:set_pos(labs[1], 36, 24)
        return
    end
    if sel < 1 then
        sel = 1
    end
    if sel > n then
        sel = n
    end
    if sel < top then
        top = sel
    end
    if sel > top + VISIBLE - 1 then
        top = sel - VISIBLE + 1
    end
    local slot = sel - top + 1
    ui:set_pos(box, 1, (slot - 1) * ROW_H)
    ui:set_pos(track, 125, 1)
    ui:set_pos(thumb, 123, thumb_y(sel, n))
    for i = 1, VISIBLE do
        local idx = top + i - 1
        if idx <= n then
            ui:set_text(labs[i], string.format("%d  %s", idx, clips[idx].dur))
            ui:set_pos(labs[i], 6, (i - 1) * ROW_H)
            ui:set_text_color(labs[i], (idx == sel) and 0 or 0xFFFFFF)
        else
            ui:set_text(labs[i], "")
            ui:set_pos(labs[i], 6, 80)
        end
    end
end

local function enter_rec_ui()
    park_list()
    ui:set_text(title, "Recording")
    ui:set_pos(title, 24, 8)
    ui:set_pos(bar, 8, 30)
    ui:set_value(bar, 0)
    ui:set_text(ptime, "0.0 / 20")
    ui:set_pos(ptime, 32, 46)
end

local function update_rec_ui()
    local pct = got * 100 // TOTAL
    if pct > 100 then
        pct = 100
    end
    local ms = got * FRAME_MS
    ui:set_value(bar, pct)
    ui:set_text(ptime, string.format("%d.%d / 20", ms // 1000, (ms % 1000) // 100))
end

local function dur_text(frames)
    local ms = frames * FRAME_MS
    return string.format("%d.%ds", ms // 1000, (ms % 1000) // 100)
end

local function on_amr(data, info)
    if not live then
        return
    end
    chunks[#chunks + 1] = data
    got = got + info.frames
end

local function begin_rec()
    chunks = { AMR_WB_HDR }
    got = 0
    live = true
    phase = "rec"
    enter_rec_ui()
    local started, start_err = dev:record_start(audio.AMR, BATCH, on_amr)
    if not started then
        live = false
        phase = "list"
        wait_up = true
        log.error("%s record_start failed: %s", TAG, tostring(start_err))
        show_list()
    else
        log.info("%s record", TAG)
    end
end

local function end_rec()
    live = false
    dev:record_stop()
    phase = "list"
    wait_up = true
    rt.delay(300)
    if got > 0 then
        local body = table.concat(chunks)
        chunks = {}
        local blob = string.format("r%d.amr", seq)
        seq = seq + 1
        local saved, save_err = ublob.write(blob, body)
        if not saved and #clips >= MAX_CLIPS then
            local old = table.remove(clips)
            ublob.remove(old.blob)
            saved, save_err = ublob.write(blob, body)
        end
        body = nil
        if saved then
            table.insert(clips, 1, { blob = blob, dur = dur_text(got) })
            while #clips > MAX_CLIPS do
                local old = table.remove(clips)
                ublob.remove(old.blob)
            end
            sel = 1
            top = 1
            log.info("%s saved %s %s", TAG, clips[1].blob, clips[1].dur)
        else
            log.error("%s save failed: %s", TAG, tostring(save_err))
        end
    else
        chunks = {}
        log.info("%s too short", TAG)
    end
    show_list()
end

local function play_sel()
    if #clips == 0 then
        return
    end
    local clip = clips[sel]
    wait_up = true
    phase = "play"
    park_list()
    ui:set_text(title, "Playing")
    ui:set_pos(title, 32, 8)
    ui:set_pos(bar, 8, 30)
    ui:set_value(bar, 0)
    ui:set_text(ptime, clip.dur)
    ui:set_pos(ptime, 40, 46)
    log.info("%s play %s", TAG, clip.blob)
    local ok, play_err = dev:play_to({ ublob = clip.blob }, audio.AMR, function(cur, total)
        local pct = 0
        if total > 0 then
            pct = cur * 100 // total
        end
        if pct > 100 then
            pct = 100
        end
        ui:set_value(bar, pct)
    end, 200)
    phase = "list"
    if not ok then
        log.error("%s play failed: %s", TAG, tostring(play_err))
    end
    show_list()
end

show_list()
log.info("%s ready  KEY0 hold=rec  KEY1 click=next hold=play", TAG)

while true do
    local rec_down = pressed(key_rec)
    local nav_down = pressed(key_nav)

    if phase == "rec" then
        update_rec_ui()
        if (not rec_down) or got >= TOTAL then
            end_rec()
        end
    end

    if phase == "list" then
        if wait_up then
            if not rec_down then
                wait_up = false
            end
        elseif rec_down then
            begin_rec()
        end
        if phase == "list" then
            if nav_down then
                if nav_n < NAV_HOLD then
                    nav_n = nav_n + 1
                    if nav_n == NAV_HOLD and #clips > 0 then
                        play_sel()
                    end
                end
            else
                if nav_n > 0 and nav_n < NAV_HOLD and #clips > 0 then
                    sel = sel + 1
                    if sel > #clips then
                        sel = 1
                    end
                    show_list()
                end
                nav_n = 0
            end
        end
    end

    rt.delay(POLL_MS)
end
