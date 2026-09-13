--[=[
  pwm comp demo — TIMER 正相 + 互补 PWMn
  ============================================================================
  本 demo
  ============================================================================
    F6E0 PIN101 FUNC5 = PWM1 正相
    F6E0 PIN100 FUNC3 = PWM1n 互补（start 时自动配，不必再 open）
    20 kHz / 50%，示波器同时看两脚：应反相。
    适合喇叭差分、H 桥。单端 LED 不必跑本 demo。

]=]

local rt = require("rt")
local log = require("log")
local pwm = require("pwm")

local PIN_P = 101 -- PWM1
local PIN_N = 100 -- PWM1n

local ch = pwm.open(pwm.INPUT_PINNO, PIN_P)
ch:start({
    mode = pwm.MODE_TIMER,
    freq = 20000,
    duty = 50,
    clk = pwm.CLK_26M,
    stop = pwm.STOP_LOW,
    comp = { type = pwm.INPUT_PINNO, id = PIN_N },
})

local info = ch:info()
log.info("comp pwm pddr=%s n=%s timer=%s freq=%s duty=%s",
         tostring(info.pddr), tostring(info.comp_pddr),
         tostring(info.timer), tostring(info.freq), tostring(info.duty))

-- 正相反相共用一路 TIMER，改占空比两脚一起变
local duties = { 20, 50, 80 }
local idx = 1
while true do
    local d = duties[idx]
    ch:set_duty(d)
    log.info("duty=%d (P and N invert)", d)
    idx = idx + 1
    if idx > #duties then
        idx = 1
    end
    rt.delay(2000)
end

--[=[
  pwm comp demo — 互补输出

  同一路 TIMER 的正相和反相。脚本只 open 正相脚，comp 里给出 n 脚，
  start 会自动把 n 脚切到 PWMn 复用。

  ----------------------------------------------------------------------------
  opt.comp = { type = pwm.INPUT_PDDR|INPUT_PINNO, id = ... }
  ----------------------------------------------------------------------------
    n 脚的 PWMn 通道必须等于正相 PWM 号（PWM1 只能配 PWM1n）。
    互补脚不要再单独 pwm.open，否则会报 busy。
    close 时正相、互补一起释放。

  F6E0：PIN101 = PWM1，PIN100 = PWM1n

]=]
