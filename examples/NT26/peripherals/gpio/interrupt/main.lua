--[=[
  gpio interrupt demo — IO 回调 + 独立任务收事件
  ============================================================================
  本 demo
  ============================================================================
    GPIO 1 输入上拉，双边沿 + 20ms 滤波。
    回调里只 mbox_send，不打 log。
    独立 task 里 mbox_recv，再 log.info。
    把 IO1 对地短接/松开（或接按键），串口应看到工作任务打出的边沿。

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")

local IN_GPIO = 1
local TOPIC = "gpio1"

-- 底层会记录这个电平保持了多久，可以基于这个做一些判断，但是这个时间是较为粗略的
local function gpio_worker()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok and type(ev) == "table" then
            log.info("gpio=%d pin=%d level=%d keep_ms=%s",
                     ev.gpio or -1, ev.pin_no or -1, ev.level or -1,
                     ev.keep_ms)
        end
    end
end

-- 先把接收任务挂上：task_start 会跑到第一次 mbox_recv 再让出
rt.task_start(gpio_worker)

local din = gpio.open(gpio.INPUT_GPIO, IN_GPIO)
din:config(false, false, gpio.PULL_UP)

-- 回调必须短：只投递，立刻返回
local function on_io(gpio_id, pin_no, level, info)
    rt.mbox_send(TOPIC, {
        gpio = gpio_id,
        pin_no = pin_no,
        level = level,
        keep_ms = info and info.keep_ms or 0,
    })
end

local ok = din:reg(gpio.IRQ_BOTH, 20, on_io)
log.info("reg gpio=%d ok=%s (IRQ_BOTH, 20ms)", IN_GPIO, ok)

while true do
    rt.delay(10000)
end

--[=[
  gpio interrupt demo — IO 回调 + 独立任务收事件

  ============================================================================
  这不是“实时中断里跑 Lua”
  ============================================================================
  obj:reg 看起来像注册中断回调，底层也确实靠边沿中断把 IO 从休眠里叫醒，
  但 Lua 函数绝不会在中断服务程序里执行。

  真实路径是：

    硬件边沿 → 中断里只投递（不做业务）
             → 滤波状态机确认“电平已经稳定够久”
             → 才把一次结算结果送进 Lua 调度队列
             → 调度循环里调用你的回调

  所以它服务的是按键、插拔、开关这类低速场景。微秒级脉冲、高速码流、
  精确脉宽测量，这套接口做不到，也不该拿来做。

  ============================================================================
  强制滤波：中断只负责激活，持续条件才触发回调
  ============================================================================
  所有 Lua 注册的 IO 回调都强制带消抖，没有“零滤波、边沿立刻进 Lua”的模式。
  debounce_ms 小于下限时会被抬到下限（当前 10ms）。

  滤波在等什么：

    - 中断到来只表示“脚上可能变了”，先记录候选电平
    - 必须在滤波窗口内一直保持这个新电平（中间抖动会重新计时）
    - 窗口走满、电平仍稳定，才算一次有效变化，回调才会来
    - 短于窗口的毛刺会被丢掉，这是故意的

  因此回调里看到的是“结算后的稳定电平”，不是每一次硬件边沿。
  回调第四个参数 info.keep_ms 是上一次结算到这次结算之间维持了多久。

  ============================================================================
  为什么不能做成实时中断业务
  ============================================================================
  1) 抖动会把事件队列打爆
     机械触点、继电器、未处理的飞线，边沿可以在 1ms 内抖几十上百次。
     若每次 ISR 都生成一条 Lua 事件：队列有限，先溢出丢事件，再把调度
     循环淹没，其它 task、定时器、串口回调全部被拖死。滤波把“边沿风暴”
     收成“稳定后的一次通知”，换的就是确定性，不是实时性。

  2) Lua 本身跑不动快速中断业务
     回调跑在主脚本的调度循环里，不是独立协程，也不是轻量快速 VM。
     回调返回前，整台 Lua 调度被占住：delay 不能用（不是任务协程，会报错），
     一旦在回调里打长 log、组包、seq、死循环，后续 IO/定时/网络事件全部排队。
     解释器本身也没有中断级时延：一次 log、一次表操作，相对 GPIO 边沿都太慢。

  正确用法：回调里只做一件极短的事——把事件发出去，立刻返回。
  打印、延时、业务状态机放到独立 task 里做。本 demo 就是这个结构。

  ============================================================================
  接口
  ============================================================================
    obj:reg(irq_mode, debounce_ms, cb) -> boolean
      irq_mode      gpio.IRQ_RISING / IRQ_FALLING / IRQ_BOTH
      debounce_ms   稳定窗口，单位毫秒，强制 ≥ 10
      cb(gpio, pin_no, level, info)
                    gpio / pin_no  编号；level  结算后的 0/1
                    info.os_tick / os_tick_ms / utc_ms / keep_ms
      返回          true 成功；失败抛错
      同一脚重复 reg 会覆盖旧回调

    obj:unreg() -> boolean     取消回调

    rt.mbox_send(topic, value) -> true     广播一条邮箱事件
    rt.mbox_recv(topic [, timeout_ms]) -> ok, data
      工作任务里阻塞等；没人在等时发送会丢（广播语义，不是队列）

  ============================================================================
  本 demo
  ============================================================================
    GPIO 1 输入上拉，双边沿 + 20ms 滤波。
    回调里只 mbox_send，不打 log。
    独立 task 里 mbox_recv，再 log.info。
    把 IO1 对地短接/松开（或接按键），串口应看到工作任务打出的边沿。

]=]
