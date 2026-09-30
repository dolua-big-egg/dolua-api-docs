--[=[
  es8311_amr_record — ES8311 经 I2C0 录 10 秒 AMR，写入 ublob
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
    8 kHz、AMR-NB。录 10 秒，文件头写成标准 AMR，落在 ublob「rec.amr」。
    record_to 在入口协程里会等到录完再返回。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local audio = require("audio")
local ublob = require("ublob")

local BLOB = "rec.amr"
local SECONDS = 10

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
    scl_pin_map = 2,
    sda_pin_map = 2,
    rate = audio.RATE_8K,
})

if not dev then
    log.error("audio open failed: %s", tostring(open_err))
else
    log.info("record %d s -> ublob %s", SECONDS, BLOB)
    local ok, rec_err = dev:record_to(SECONDS * 1000, { ublob = BLOB }, audio.AMR, true)
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
