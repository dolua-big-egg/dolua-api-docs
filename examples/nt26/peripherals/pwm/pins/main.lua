--[=[
  pwm pins demo — 列出当前型号可 PWM 的 PAD
  ============================================================================
  本 demo
  ============================================================================
    打印 pwm.pins()，对照原理图选脚。
    不占用、不出波。看完串口 log 即可。

]=]

local rt = require("rt")
local log = require("log")
local pwm = require("pwm")

local list = pwm.pins()
log.info("pwm pad count=%d", #list)

for i, p in ipairs(list) do
    log.info("[%d] pddr=%s pin=%s timer=%s mux=%s n_ch=%s apwm=%s",
             i,
             tostring(p.pddr),
             tostring(p.pin_no),
             tostring(p.timer),
             tostring(p.mux),
             tostring(p.n_ch),
             tostring(p.apwm))
end

log.info("done. pddr=芯片PAD, pin=模块管脚号, timer=正相PWM通道, n_ch=可作哪路PWMn, apwm=APWM序号")

while true do
    rt.delay(60000)
end

--[=[
  pwm.pins() -> { {pddr, pin_no, timer, mux, n_ch, apwm}, ... }

    pddr    芯片 PAD，open(INPUT_PDDR, pddr)
    pin_no  模块管脚，无引出时该字段不存在
    timer   正相 PWM 通道 0~5（FUNC5）
    mux     正相复用
    n_ch    本 PAD 可作为哪路的互补输出（没有则无此字段）
    apwm    0/1/2，F6E0 上 PIN100/101/16

  默认 start 走 timer 正相；comp 才用 n_ch；MODE_APWM 才用 apwm。

]=]
