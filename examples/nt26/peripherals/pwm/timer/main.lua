
--[=[
  pwm timer demo — TIMER 硬件 PWM 呼吸灯
  ============================================================================
  本 demo
  ============================================================================
    F6E0 PIN16（GPIO25）= PWM2。
    1 kHz，占空比 0↔100 循环，接 LED 可看到呼吸效果。
    示波器看 PIN16。不要再 gpio.open 同一颗脚。
    开发板默认是NET灯，注意rtu_config.cfg中net_led的enable=0，意思是关掉RTU的NET灯控制，由lua端的PWM控制。

]=]

local rt = require("rt")
local log = require("log")
local pwm = require("pwm")

local PIN = 16 -- F6E0 PIN16-GPIO25 NET灯 = PWM2 可以换成其他引脚测

local ch = pwm.open(pwm.INPUT_PINNO, PIN)
ch:start({
    mode = pwm.MODE_TIMER,
    freq = 1000,
    duty = 0,
    clk = pwm.CLK_26M,
    stop = pwm.STOP_LOW,
})

local info = ch:info()
log.info("timer pwm pddr=%s pin=%s ch=%s freq=%s",
         tostring(info.pddr), tostring(info.pin_no),
         tostring(info.timer), tostring(info.freq))

while true do
    for duty = 0, 100, 5 do
        ch:set_duty(duty)
        rt.delay(40)
    end
    for duty = 100, 0, -5 do
        ch:set_duty(duty)
        rt.delay(40)
    end
end

--[=[
  pwm timer demo — TIMER 硬件 PWM

  波形由 TIMER 硬件产生，不是 GPIO 翻转。open 只占脚，start 才出波。

  ----------------------------------------------------------------------------
  pwm.open(type, id) -> obj
  ----------------------------------------------------------------------------
    type  pwm.INPUT_PINNO  模块管脚号（本 demo：PIN101）
          pwm.INPUT_PDDR   芯片 PAD 地址（PIN101 = PAD49）
    失败抛错：脚不存在 / 无 PWM / 已被其它 pwm.open 占用

  ----------------------------------------------------------------------------
  obj:start(opt) -> true
  ----------------------------------------------------------------------------
    mode  pwm.MODE_TIMER（默认）
    freq  Hz，必填，必须 < 时钟（CLK_26M 时可到 MHz 级）
    duty  0~100，默认 0
    clk   pwm.CLK_40K / CLK_26M / CLK_102M，默认 26M
    stop  pwm.STOP_LOW / STOP_HIGH / STOP_HOLD，停波电平
    失败抛错

  ----------------------------------------------------------------------------
  obj:set_duty(duty) / obj:set_freq(hz) / obj:stop() / obj:close() / obj:info()
  ----------------------------------------------------------------------------
    set_duty  运行中改占空比，0~100
    set_freq  运行中改频率（内部重新 setup）
    stop      停波，脚占用还在，可再 start
    close     停波并释放 PAD（__gc 同样走这里）
    info      {pddr, pin_no, running, mode, timer, freq, duty, ...}

  不要和 gpio / I2C 同时占用同一颗 PAD。互补、APWM 见其它 pwm 工程。

]=]
