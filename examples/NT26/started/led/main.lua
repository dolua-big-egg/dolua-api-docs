--[=[
  led demo — 闪 开发板指示灯（GPIO 9）
  ============================================================================
  本 demo
  ============================================================================
    1) gpio.open GPIO 9（开发板指示灯）
    2) config 成输出
    3) 循环 set true/false，间隔 500ms

]=]

local rt = require("rt")
local gpio = require("gpio")

local NET_LED = 9 -- 开发板指示灯

-- 按 GPIO 编号打开（旧名 gpio.INPUT_GPIO 同值，仍可用）
local led = gpio.open(gpio.BY_GPIO, NET_LED)
led:config(true, false, gpio.PULL_AUTO)

while true do
    led:set(true)
    rt.delay(500)
    led:set(false)
    rt.delay(500)
end

--[=[
  led demo — 闪 开发板指示灯（GPIO 9）

  gpio.open(gpio.BY_GPIO, n)      使用 GPIO 编号打开（旧名 gpio.INPUT_GPIO）
  gpio.open(gpio.BY_PINNO, n)     使用模块 PIN 序号打开（旧名 gpio.INPUT_PINNO）
  io:config(is_output, init, pull) 配成输出
  io:set(true/false)               高/低电平

  主入口本身是协程，顶层 while + rt.delay 就能闪。
  本工程只演示简单的LED实现，关于GPIO的详细功能参考其他工程

  ============================================================================
  本 demo
  ============================================================================
    1) gpio.open GPIO 9（开发板指示灯）
    2) config 成输出
    3) 循环 set true/false，间隔 500ms

]=]
