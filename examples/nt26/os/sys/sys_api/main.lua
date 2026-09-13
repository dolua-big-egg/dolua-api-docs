--[=[
  sys demo — 版本 / 复位原因 / option / 延时 / 授时
  ============================================================================
  本 demo
  ============================================================================
    1) version / reset_reason
    2) option 读 print_route / log_route
    3) delay_us 只演示 100us（忙等，不参与调度）
    4) delay_ms 演示 10ms（挂起当前 OS 线程）
    5) delay_until 演示 10ms（本平台 osDelayUntil，相对当前 tick）
    6) wdt_kick 主动喂 AP/AON 硬件看门狗
    7) nitz_reg；set_ts 用当前时间回写一次
    不调用 reset / poweroff -这个在cmd_demo中会调用。

]=]

local rt = require("rt")
local log = require("log")
local sys = require("sys")
local info = require("info")

log.info("---- version ----")
local v = sys.version()
log.info("sdk=%s evb=%s", v.sdk, v.evb)
log.info("app=%s ver=%s ver_f=%s build=%s", v.app, v.ver, v.ver_f, v.build)
log.info("cmp=%s btime=%s", v.cmp, v.btime)

log.info("---- reset_reason ----")
local r = sys.reset_reason()
log.info("ap=%s %s  cp=%s %s", r.ap, r.ap_name, r.cp, r.cp_name)

log.info("---- option ----")
log.info("print_route=%s log_route=%s",
         sys.option("print_route"), sys.option("log_route"))

--[[
  delay_us 是忙等：当前 CPU 空转，Lua 调度器、其它协程、看门狗都进不去。
  API 不限制数值。传到 ms 级很容易把系统看门狗拖死复位。
  只要延时到了毫秒，就用 rt.delay（协程让出）或 sys.delay_ms（OS 线程休眠）。
]]
log.info("---- delay_us 100 (busy wait, keep it short) ----")
sys.delay_us(100)
log.info("delay_us 100 done")

--[[
  delay_ms 是挂起当前 OS 线程：Lua 虚拟机这条线程睡着，上面所有协程都停。
  注意这个是完全不参与线程调度的，是整个OS进程都停下来了，所有任务都会停止运行。
  正常情况不要使用这个api，用rt.delay这种带调度器的代替，delay_ms 主要用在时序更严格的场景，
  因为他不会出现因为其他 Lua 协程占用而没法及时返回的情况。
]]
log.info("---- delay_ms 10 ----")
sys.delay_ms(10)
log.info("delay_ms 10 done")

--[[
  delay_until 也是挂起当前 OS 线程。底层本平台 osDelayUntil：
  以调用当下的 tick 为起点再睡 ms，不是 CMSIS 文档里的绝对时刻。
  同样会让 Idle 跑起来喂狗；ms<=0 立即返回。
]]
log.info("---- delay_until 10 ----")
sys.delay_until(10)
log.info("delay_until 10 done")

--[[
  wdt_kick 清 AP 硬件 WDT，并喂 AON 看门狗。不让出调度。
  忙循环里只 kick 能避免 WDTSW，其它任务仍可能被饿死；优先 delay / rt.delay。
]]
log.info("---- wdt_kick ----")
sys.wdt_kick()
log.info("wdt_kick done")

log.info("---- set_ts (write current utc back) ----")
local ts = info.timestamp()
if ts and ts > 0 then
    log.info("set_ts %s ok=%s", ts, sys.set_ts(ts))
else
    log.info("skip set_ts, timestamp=%s", tostring(ts))
end

log.info("---- nitz_reg ----")
sys.nitz_reg(function(utc)
    log.info("nitz ts=%s", utc)
end)
log.info("nitz_reg ok (already synced => callback once now)")

while true do
    rt.delay(10000)
end

--[=[
  sys demo — 版本 / 复位原因 / option / 延时 / 授时

  require("sys")。本 demo 不调用 reset / poweroff。

  ----------------------------------------------------------------------------
  sys.delay_us(us)     忙等微秒，无调度
  ----------------------------------------------------------------------------
    底层 delay_us，当前线程空转。不让出协程，也不进 OS 调度。
    API 不截断数值。传入过长（到 ms 级）会堵住看门狗，导致系统复位。
    自己估：只适合几十~几百微秒的时序。到了毫秒请用 rt.delay。

  ----------------------------------------------------------------------------
  sys.delay_ms(ms)     挂起当前 OS 线程
  ----------------------------------------------------------------------------
    底层 osDelay。Lua 虚拟机这条线程睡着，上面所有协程都停。
    毫秒级协程延时优先 rt.delay，其它任务还能跑。

  ----------------------------------------------------------------------------
  sys.delay_until(ms)  按周期挂起当前 OS 线程
  ----------------------------------------------------------------------------
    底层本平台 osDelayUntil（vTaskDelayUntil(&now, ticks)）。
    以调用当下的 tick 为起点再睡 ms，不是绝对时刻。ms<=0 立即返回。
    同样挂起整条 Lua VM 线程。

  ----------------------------------------------------------------------------
  sys.wdt_kick()       主动喂硬件看门狗
  ----------------------------------------------------------------------------
    WDT_kick + AON feed。不让出调度。长计算分片时可用，不能替代 delay。
    但是这个 api 超级重要，如果你在做一个超级耗时的任务，且一直霸占着线程，记得主动喂一下看门狗，否则系统会复位。

  ----------------------------------------------------------------------------
  sys.option(key) / sys.option(key, value) -> value
  ----------------------------------------------------------------------------
    print_route / log_route，取值 "uart1"/"uart2"/"uart3"/"usb_at"。写非法会抛错。

  ----------------------------------------------------------------------------
  sys.version() -> { sdk, evb, cmp, app, ver, ver_f, build, btime }
  sys.reset_reason() -> { ap, cp, ap_name, cp_name }
  ----------------------------------------------------------------------------
    复位码与 sys.RST_* 一致：CLEAR POR PAD SWRESET HARDFAULT ASSERT
    WDTSW WDTHW LOCKUP AONWDT BATLOW TEMPHI FOTA EXTRST UNKNOWN

  ----------------------------------------------------------------------------
  sys.set_ts(ts) / set_ts_ms(ts_ms) -> boolean
  ----------------------------------------------------------------------------
    写本机 RAM 里的 UTC，不冒充 NITZ。ts<=0 返回 false。

  ----------------------------------------------------------------------------
  sys.nitz_reg(function(ts) ... end) -> true
  ----------------------------------------------------------------------------
    基站授时成功回调，ts 为 UTC Unix 秒。重复调用覆盖。
    注册时若已授时，会立刻回调一次。禁止在回调里再 nitz_reg。

  sys.reset() / sys.poweroff() 会复位或关机，本 demo 不调用。

  ============================================================================
  本 demo
  ============================================================================
    打印版本和复位原因；读 option；delay_us(100)；delay_ms(10)；
    delay_until(10)；wdt_kick；把当前 timestamp 写回；注册 nitz。

]=]
