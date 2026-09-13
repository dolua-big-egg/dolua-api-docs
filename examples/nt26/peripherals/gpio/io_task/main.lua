--[=[
  gpio io-task demo — 把指示灯时序交给 IO 任务，Lua 只切换模式
  ============================================================================
  本 demo
  ============================================================================
    GPIO 9 注册：常灭、常亮、慢闪、快闪、心跳。
    主循环每 4 秒 wave_set 切一种，Lua 在 delay，灯自己闪。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")

local LED_GPIO = 9

local W_OFF = 1
local W_ON = 2
local W_SLOW = 3   -- 1s 亮 / 1s 灭
local W_FAST = 4   -- 200ms 闪
local W_BEAT = 5   -- 两短一长，像心跳

-- 按 GPIO 编号打开（旧名 gpio.INPUT_GPIO 同值，仍可用）
local led = gpio.open(gpio.BY_GPIO, LED_GPIO)
led:config(true, false, gpio.PULL_AUTO)

led:wave_reg(W_OFF, 0)
led:wave_reg(W_ON, 1)
led:wave_reg(W_SLOW, {1, 1000, 1000, 0})
led:wave_reg(W_FAST, {1, 200, 200, 0})
led:wave_reg(W_BEAT, {1, 200, 200, 200, 800, 0})

local modes = {
    {id = W_SLOW, name = "slow 1s"},
    {id = W_FAST, name = "fast 200ms"},
    {id = W_BEAT, name = "heartbeat"},
    {id = W_ON,   name = "solid on"},
    {id = W_OFF,  name = "solid off"},
}

log.info("io-task ready gpio=%d, switch every 4s", LED_GPIO)

while true do
    -- 循环切换模式
    for i = 1, #modes do
        local m = modes[i]
        led:wave_set(m.id)
        log.info("wave_set id=%d %s (lua sleeping, led runs in io-task)", m.id, m.name)
        rt.delay(4000)
    end

    -- 插播两下快闪，结束后回到当前循环（此时是 W_OFF）
    led:wave_set(W_SLOW)
    led:wave_insert({1, 100, 100, 100, 100, 0})
    log.info("wave_insert burst, then back to slow")
    rt.delay(4000)
end

--[=[
  gpio io-task demo — 把指示灯时序交给 IO 任务，Lua 只切换模式

  ============================================================================
  设计理念：大量指示灯，不要用 Lua 去“高频陪跑”
  ============================================================================
  设备上常常有很多状态灯：电源、网络、服务器、告警、OTA……每盏灯自己的
  节奏还不一样。纯 Lua 有两条路，都不合适：

    1) 一盏灯一个 task
       灯一多，协程数量、唤醒次数一起涨。调度器大部分时间在切灯，而不是
       跑业务。

    2) 一个 task 按最小公约数猛转
       比如 A 灯 300ms 闪、B 灯 500ms 闪，就得大约每 100ms 醒一次去翻转对应脚。
       这是在用 Lua 当软件 PWM。解释器每次被叫醒都要跑一段脚本，事件队列、
       其它 delay、IO 回调全被拖慢；灯越多、周期越短，主业务越卡。

  IO 任务就是为这种“要较快变化、但其实只是电平节奏”的场景准备的：

    - 时序在 IO 引擎里跑，不占用 Lua 协程，也不进 Lua 调度循环
    - Lua 只负责：注册几种波形、在业务状态变化时 wave_set 切一下
    - 切走之后，闪灯与脚本并行，脚本可以继续 delay 几秒做别的事

  注意粒度：波形时长必须是 100ms 的整数倍（gpio.WAVE_QUANT_MS）。
  它解放的是“几十~几百毫秒级的指示灯”，不是示波器级的精确定时。
  30ms/50ms 那种若硬在 Lua 里陪跑，正是 IO 任务要避免的写法；落到 IO
  任务上，请改成 100ms/200ms 这类人眼可辨的节奏。

  ============================================================================
  怎么注册、怎么切换
  ============================================================================
  1) open + config 成输出
  2) wave_reg(id, 波形)  把模式写进该脚的槽位（每脚最多 8 个，id 为 1..8）
  3) wave_set(id)        循环播放该槽；常亮/常灭立刻生效，闪烁在段边界切换
  4) 过一段时间再 wave_set 另一个 id，就是“切换任务”
  5) 可选 wave_insert    插播一次，播完自动回到当前循环波形
  6) wave_stop([电平])   停掉；省略或 -1 保持当前电平，0/1 落到指定电平

  波形 payload：
    数字 0 / 1                          常灭 / 常亮
    { 起始电平, 维持ms..., 结束动作 }   循环闪
      起始电平、结束动作只能 0 或 1
      中间每一段：保持当前电平这么久，然后翻转
      维持时间 ≥ 100 且必须是 100 的倍数
    例：{1, 200, 200, 0}  → 高 200ms、低 200ms，循环

  上限（整机）：同时开 IO 任务的脚有限（当前 8 路）。指示灯用这个；
  按键/中断见 interrupt 工程，set/get/seq 见 normal 工程。

  ============================================================================
  本 demo
  ============================================================================
    GPIO 9 注册：常灭、常亮、慢闪、快闪、心跳。
    主循环每 4 秒 wave_set 切一种，Lua 在 delay，灯自己闪。

]=]
