--[=[
  es8311_amr_rtp_duplex — 驻网后同时录音上行、收 RTP 下行播放
  ============================================================================
  硬件
  ============================================================================
    OpenKit 电源 LDO 接在 NET 灯上：GPIO25 / PIN 16。
    rtu_config.conf 的 [net_led] enable=0 把这只脚交给脚本，先拉高再开 I2C。
    ES8311，模组做 I2S 主机。寄存器走硬件 I2C0，由 audio 自己初始化。
    scl_pin_map = 2：SCL 是 PDDR 32（PIN 39）。
    sda_pin_map = 2：SDA 是 PDDR 31（PIN 38）。

  ============================================================================
  本例
  ============================================================================
    audio.open 的 duplex = true：麦和喇叭同时开。
    AEC = true 时用正在播放的那帧当回声参考；false 时不做回声消除，喇叭声会被录进上行。
    驻网后 rtp.open 到 dolua.cn:5004。录音回调里把 AMR 拆帧发出去。
    下行不走喂流回调：play_start 不带函数，RTP 回调里 play_push 进内部缓冲。
    gap = \"plc\" 时缓冲空了让解码器补；\"silence\" 填全 0。prebuf 是开口前先攒的帧数。
    plc_max 是连续补多少拍后改回静音，下一句重新攒 prebuf。缓冲满了返回 full，丢掉这一帧。
    对端 tools/rtp_amr_relay.py --kind wb：UDP 5004 收上行并回 RTP，TCP 5005 给电脑听和说。
    16 kHz 时间戳每帧加 320。连上后的第一包带 marker。
    回调里不要 rt.delay。send 返回 busy 就计一次，不在回调里重试。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local audio = require("audio")
local lp = require("lp")
local rtp = require("rtp")

local HOST = "dolua.cn"
local PORT = 5004
local AEC = false             -- 回声消除开关，true 开 / false 关

local function halt(msg)
    log.error("%s", msg)
    while true do
        rt.delay(10000)
    end
end

local board_pwr = gpio.open(gpio.BY_GPIO, 25)
if not board_pwr:config(true, true) then
    halt("board LDO gpio25 config fail")
end
log.info("board LDO on gpio25 pin16")
rt.delay(100)

local dev, open_err = audio.open(audio.ES8311, {
    i2c = audio.I2C0,
    scl_pin_map = 2,
    sda_pin_map = 2,
    rate = audio.RATE_16K,
    -- 播音
    play_volume = 60,         -- 喇叭响度 0~100。播放中可 dev:set_play_volume(80)
    play_diff = true,         -- true 差分线出，接 CST8302A。false 单端耳机
    -- 录音
    mic_gain = 10,
    mic_scale = 7,
    mic_volume = 215,
    duplex = true,
    aec = AEC,
})

if not dev then
    log.error("audio open failed: %s", tostring(open_err))
else
    local session = nil
    local got = 0
    local sent = 0
    local dropped = 0
    local played = 0
    local full = 0
    local first = true

    local function on_amr(data, info)
        local cur = session
        if cur then
            local frames, split_err = rtp.split(data, "wb")
            if not frames then
                log.error("split %s", tostring(split_err))
            else
                local i = 1
                while i <= #frames do
                    local n, send_err = cur:send(frames[i], { marker = first })
                    first = false
                    if n then
                        sent = sent + 1
                    else
                        dropped = dropped + 1
                        if dropped <= 3 then
                            log.error("rtp send %s", tostring(send_err))
                        end
                    end
                    i = i + 1
                end
            end
        end
        got = got + info.frames
        if got % 50 == 0 then
            log.info("duplex up=%d sent=%d drop=%d play=%d full=%d", got, sent, dropped, played, full)
        end
    end

    local function on_rtp(pkt)
        if type(pkt) ~= "string" or #pkt < 13 then
            return
        end
        local ok, err = dev:play_push(pkt:sub(13))
        if ok then
            played = played + 1
        elseif err == "full" then
            full = full + 1
            if full <= 3 then
                log.error("play_push full")
            end
        elseif err ~= "idle" then
            log.error("play_push %s", tostring(err))
        end
    end

    log.info("wait link, then duplex aec=%s -> %s:%d", tostring(AEC), HOST, PORT)
    while true do
        if session then
            rt.delay(5000)
        else
            lp.wait_link(-1)
            local s, rtp_err = rtp.open({
                host = HOST,
                port = PORT,
                pt = 96,
                step = 320,
            })
            if not s then
                log.error("rtp open failed: %s", tostring(rtp_err))
                rt.delay(3000)
            else
                session = s
                first = true
                s:on(on_rtp)
                -- gap：silence 填全 0，plc 让解码器补。也可以写 audio.GAP_SILENCE / audio.GAP_PLC。
                -- prebuf：开口前先攒的帧数，每帧 20ms。0 表示来了就播。
                -- plc_max：连续补多少拍后改回静音，下一句重新攒 prebuf。
                local playing, play_err = dev:play_start(audio.AMR, {
                    gap = "plc",
                    prebuf = 3,
                    plc_max = 6,
                })
                if not playing then
                    log.error("play_start failed: %s", tostring(play_err))
                end
                local started, start_err = dev:record_start(audio.AMR, 1, on_amr)
                if not started then
                    log.error("record_start failed: %s", tostring(start_err))
                else
                    log.info("rtp duplex %s:%d", HOST, PORT)
                end
            end
        end
    end
end

while true do
    rt.delay(60 * 1000)
end
