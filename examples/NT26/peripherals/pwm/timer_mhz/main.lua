
--[=[
  pwm mhz demo — TIMER PWM 1 MHz
  ============================================================================
  本 demo
  ============================================================================
    F6E0 PIN101 PWM1，时钟 26M，频率 1 MHz，占空比 50%。
    必须用示波器（1 kHz 呼吸灯看不出 MHz）。
    26M 时钟下 1 MHz 约 26 个 tick，占空比步进大约 4%。

]=]

local rt = require("rt")
local log = require("log")
local pwm = require("pwm")

local PIN = 101 -- F6E0 PIN101 = PWM1

local ch = pwm.open(pwm.INPUT_PINNO, PIN)
ch:start({
    mode = pwm.MODE_TIMER,
    freq = 1000000,
    duty = 50,
    clk = pwm.CLK_26M,
    stop = pwm.STOP_LOW,
})

local info = ch:info()
log.info("mhz pwm pddr=%s freq=%s duty=%s clk=26M",
         tostring(info.pddr), tostring(info.freq), tostring(info.duty))

local duties = { 25, 50, 75 }
local idx = 1
while true do
    local d = duties[idx]
    local ok = ch:set_duty(d)
    log.info("set_duty %d ok=%s", d, tostring(ok))
    idx = idx + 1
    if idx > #duties then
        idx = 1
    end
    rt.delay(2000)
end

--[=[
  pwm mhz demo — 高频 PWM

  TIMER 时钟选 CLK_26M（或 CLK_102M）才能到 MHz。
  本模块默认 26M。

  freq 必须严格小于 srcClock。CLK_26M 时 1 MHz 没问题；
  再往上占空比会变粗（tick 数 = 26e6 / freq）。

  换 102M（EC718M）：clk = pwm.CLK_102M，同样 freq=1000000 时步进更细。

]=]
