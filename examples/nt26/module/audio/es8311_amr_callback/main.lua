--[=[
  es8311_amr_callback — 回调里自己拼 AMR，录完再写入 ublob
  ============================================================================
  硬件
  ============================================================================
    OpenKit 电源 LDO 接在 NET 灯上：GPIO25 / PIN 16。
    rtu_config.conf 的 [net_led] enable=0 把这只脚交给脚本，先拉高再开 I2C。
    ES8311，模组做 I2S 主机。寄存器走硬件 I2C0，由 audio 自己初始化。
    scl_pin_map = 2：SCL 是 PDDR 32（PIN 39）。
    sda_pin_map = 2：SDA 是 PDDR 31（PIN 38）。

  ============================================================================
  本例和 es8311_amr_record 的差别
  ============================================================================
    那个例程走 record_to：固件在内部缓存里拼完整段，停掉 I2S 后自己写 ublob。
    本例走 record_start：固件只负责把编好的 AMR 帧交给回调，不写盘。
    脚本在启动时先准备一份缓存（Lua 表），把文件头放进去；
    回调里只把这一包裸帧追加进去；帧数到齐后停录，拼成一段，再一次写入 ublob。
    回调给的 data 没有 #!AMR 文件头。头要自己按采样率写：
      16 kHz（AMR-WB）：#!AMR-WB\n
      8 kHz（AMR-NB）：#!AMR\n
    回调形态：function(data, info)
      data        这一包 AMR 帧（TOC + 帧体），可能含多帧
      info.frames 这一包里的帧数
      info.seq    从 1 递增的包序号
      info.bytes  这一包字节数
      info.rate   采样率
      info.fmt    audio.AMR 或 audio.PCM
    回调跑在调度器上，里面不要 rt.delay，也不要写 flash。
    record_stop 会立刻拆掉回调：还没凑满一批的尾帧，以及已经投递但还没进回调的那包，都不会再交出来。
    所以本例按已经进缓存的帧数停，并且每批帧数能整除总帧数。
    停录后再等一小段，让 I2S 先停，然后才 ublob.write。录音过程中不写盘。

  ============================================================================
  audio.open 录音参数
  ============================================================================
    rate        audio.RATE_8K 或 audio.RATE_16K。16 kHz 走 AMR-WB，8 kHz 走 AMR-NB。
    volume      放音音量，0~100。本例只录不放，不影响录音。
    mic_gain    麦克风前置放大（PGA），0~10，每档 3dB，10 = 30dB。
    mic_scale   ADC 模拟放大，0~7，每档 6dB，7 = 42dB。
    mic_volume  数字录音音量，0~255。191 = 0dB，每加 1 大 0.5dB。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local audio = require("audio")
local ublob = require("ublob")

local BLOB = "cb.amr"
local SECONDS = 20
local FRAME_MS = 20
local BATCH = 5                 -- 每 5 帧（100ms）回调一次；回调里拿到的是这一批裸 AMR
local TOTAL = SECONDS * 1000 / FRAME_MS
local AMR_WB_HDR = "#!AMR-WB\n"

local function halt(msg)
    log.error("%s", msg)
    while true do
        rt.delay(10000)
    end
end

-- OpenKit 电源 LDO 由 NET 灯供电。对象留在入口协程里，避免被回收后掉电。
local board_pwr = gpio.open(gpio.BY_GPIO, 25)
if not board_pwr:config(true, true) then
    halt("board LDO gpio25 config fail")
end
log.info("board LDO on gpio25 pin16")
rt.delay(100)

local dev, open_err = audio.open(audio.ES8311, {
    i2c = audio.I2C0,
    scl_pin_map = 2,          -- SCL：PDDR 32 / PIN 39
    sda_pin_map = 2,          -- SDA：PDDR 31 / PIN 38
    rate = audio.RATE_16K,    -- 16 kHz，帧是 AMR-WB；改成 RATE_8K 时头要改成 #!AMR\n
    volume = 60,
    mic_gain = 10,            -- PGA，0~10，每档 3dB（10 = 30dB）
    mic_scale = 7,            -- ADC，0~7，每档 6dB（7 = 42dB）
    mic_volume = 215,         -- 数字音量，0~255，191 = 0dB，每加 1 大 0.5dB
})

if not dev then
    log.error("audio open failed: %s", tostring(open_err))
else
    -- 启动前就把文件头放进缓存。回调只追加裸帧，不在回调里写盘。
    local parts = { AMR_WB_HDR }
    local got = 0

    local function on_amr(data, info)
        parts[#parts + 1] = data
        got = got + info.frames
    end

    log.info("callback record %d s 16k AMR-WB, batch=%d frames", SECONDS, BATCH)
    local started, start_err = dev:record_start(audio.AMR, BATCH, on_amr)
    if not started then
        log.error("record_start failed: %s", tostring(start_err))
    else
        while got < TOTAL do
            rt.delay(50)
        end
        dev:record_stop()
        -- 等工作线程停掉 I2S / 编码，再把拼好的整段写进 ublob。
        rt.delay(300)

        local amr = table.concat(parts)
        local wok, werr = ublob.write(BLOB, amr)
        if not wok then
            log.error("ublob write failed: %s", tostring(werr))
        else
            local info, stat_err = ublob.stat(BLOB)
            if info then
                log.info("saved %s bytes=%d frames=%d", info.name, info.size, got)
            else
                log.error("stat failed: %s", tostring(stat_err))
            end
        end
    end
    dev:close()
end

while true do
    rt.delay(60 * 1000)
end
