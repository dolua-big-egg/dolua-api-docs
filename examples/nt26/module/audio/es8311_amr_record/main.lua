--[=[
  es8311_amr_record — ES8311 经 I2C0 录 20 秒 AMR-WB，写入 ublob
  ============================================================================
  硬件
  ============================================================================
    OpenKit 电源 LDO 接在 NET 灯上：GPIO25 / PIN 16。
    rtu_config.conf 的 [net_led] enable=0 把这只脚交给脚本，先拉高再开 I2C。
    ES8311，模组做 I2S 主机。寄存器走硬件 I2C0，由 audio 自己初始化。
    scl_pin_map = 2：SCL 是 PDDR 32（PIN 39）。
    sda_pin_map = 2：SDA 是 PDDR 31（PIN 38）。
    不写寄存器时 DAC/ADC 不开，录到的不是麦克风数据。

  ============================================================================
  本例
  ============================================================================
    16 kHz、AMR-WB。录 20 秒，文件头写成 #!AMR-WB，落在 ublob「rec.amr」。
    record_to 在入口协程里会等到录完再返回。录音先全部放在内存，停掉 I2S 后再一次写入 ublob。
    写 ublob 时单次预留内存不超过 200KB：16 kHz 按最坏码率约 67 秒。
    进度回调参数是当前帧、总帧。不传回调时行为和以前一样。
    间隔单位毫秒，最快 100ms（5 帧），不传默认 1000ms。开头和结束各回调一次。
    回调里不要 rt.delay。
      dev:record_to(毫秒, { ublob = 名字 }, audio.AMR, true, function(cur, total) end, 1000)

  ============================================================================
  audio.open 参数
  ============================================================================
    rate         audio.RATE_8K 或 audio.RATE_16K。16 kHz 走 AMR-WB，8 kHz 走 AMR-NB。
    播音：
    play_volume  喇叭响度，0~100。本例只录不放，不影响录音。
    录音：
    mic_gain     麦克风前置放大（PGA），0~10，每档 3dB，10 = 30dB。
                 接口仍接受 0~15，大于 10 按 10 算。
    mic_scale    ADC 模拟放大，0~7，每档 6dB，7 = 42dB。
    mic_volume   数字录音音量，0~255。191 = 0dB，每加 1 大 0.5dB。
    总增益 = 三者相加。声音小先加 mic_volume；破音或底噪大先减 mic_scale。
    录音过程中也可以改，只传要改的字段：
      dev:set_mic({ volume = 230 })
      dev:set_mic({ gain = 8, scale = 6, volume = 200 })
    aec          回声消除。本例只录不放，关掉。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local audio = require("audio")
local ublob = require("ublob")

local BLOB = "rec.amr"
local SECONDS = 20

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
    rate = audio.RATE_16K,    -- 16 kHz，录出来是 AMR-WB；改成 RATE_8K 则是 AMR-NB
    -- 播音
    play_volume = 60,         -- 喇叭响度 0~100，本例不播放
    play_diff = true,         -- true 差分线出，接 CST8302A。false 单端耳机
    -- 录音。声音小先加 mic_volume，破音往下减。
    mic_gain = 10,            -- 麦克风 PGA，0~10，每档 3dB（10 = 30dB）
    mic_scale = 7,            -- ADC 模拟放大，0~7，每档 6dB（7 = 42dB）
    mic_volume = 215,         -- 数字录音音量，0~255，191 = 0dB，每加 1 大 0.5dB
    aec = false,              -- 回声消除关
})

if not dev then
    log.error("audio open failed: %s", tostring(open_err))
else
    log.info("record %d s 16k AMR-WB -> ublob %s", SECONDS, BLOB)
    -- 第 5 个参数是文件头，第 6 个是进度回调，第 7 个是间隔毫秒（最低 100）。
    local ok, rec_err = dev:record_to(SECONDS * 1000, { ublob = BLOB }, audio.AMR, true,
        function(cur, total)
            log.info("progress %d/%d", cur, total)
        end, 1000)
    if not ok then
        log.error("record failed: %s", tostring(rec_err))
    else
        local info, stat_err = ublob.stat(BLOB)
        if info then
            log.info("saved %s bytes=%d", info.name, info.size)
        else
            log.error("stat failed: %s", tostring(stat_err))
        end
    end
    dev:close()
end

while true do
    rt.delay(60 * 1000)
end
