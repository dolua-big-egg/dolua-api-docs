--[=[
  es8311_amr_rtp — 上电就一直录，驻网后把 AMR-WB 一直推到 dolua.cn
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
    record_start 没有时长，不调 record_stop 就一直录。
    回调里拿到的是裸 AMR（TOC + 帧体），没有 #!AMR 文件头。
    驻网前只录不发。驻网后 rtp.open，rtp.split 按帧拆开，每帧一个 RTP。
    对端用 tools/rtp_amr_relay.py --kind wb 收 UDP 5004，电脑 ffplay 连 TCP 5005。
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
local BATCH = 5

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
    volume = 60,
    mic_gain = 10,
    mic_scale = 7,
    mic_volume = 215,
})

if not dev then
    log.error("audio open failed: %s", tostring(open_err))
else
    local session = nil
    local got = 0
    local sent = 0
    local dropped = 0
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
            if session then
                log.info("push frames=%d sent=%d drop=%d", got, sent, dropped)
            else
                log.info("record frames=%d wait link", got)
            end
        end
    end

    log.info("record start, push after link -> %s:%d", HOST, PORT)
    local started, start_err = dev:record_start(audio.AMR, BATCH, on_amr)
    if not started then
        log.error("record_start failed: %s", tostring(start_err))
    else
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
                if s then
                    session = s
                    first = true
                    log.info("rtp up %s:%d", HOST, PORT)
                else
                    log.error("rtp open failed: %s", tostring(rtp_err))
                    rt.delay(3000)
                end
            end
        end
    end
end

while true do
    rt.delay(60 * 1000)
end
