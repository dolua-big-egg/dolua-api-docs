--[=[
  rt tmr demo — 一次性 / 周期定时器
  ============================================================================
  本 demo
  ============================================================================
    1) tmr_once 2 秒后打一次（带参数）
    2) tmr_loop 每 1 秒打一次
    3) 主协程 delay 后 stop → start → delete
    回调跑在调度循环里，必须马上返回，不要 delay。

]=]

local rt = require("rt")
local log = require("log")

local n = 0
local loop_id

local once_id = rt.tmr_once(2000, function(tag)
    log.info("once tag=%s", tag)
end, "hello")
log.info("once id=%s", once_id)

loop_id = rt.tmr_loop(1000, function(name)
    n = n + 1
    log.info("loop %s n=%d", name, n)
end, "tick")
log.info("loop id=%s", loop_id)

rt.delay(4500)
local ok, err = rt.tmr_stop(loop_id)
log.info("stop ok=%s err=%s", ok, tostring(err))

rt.delay(2000)
ok, err = rt.tmr_start(loop_id)
log.info("start ok=%s err=%s", ok, tostring(err))

rt.delay(2500)
ok, err = rt.tmr_delete(loop_id)
log.info("delete ok=%s err=%s", ok, tostring(err))

log.info("tmr demo done")
while true do
    rt.delay(10000)
end

--[=[
  rt tmr demo — 一次性 / 周期定时器

  底层 OS 定时器到期后投到调度循环再调 Lua 回调，不是在中断里跑。
  全系统最多 8 路。不需要 mbox。

  ----------------------------------------------------------------------------
  rt.tmr_once(ms, callback[, arg1[, arg2]]) -> timer_id
  rt.tmr_loop(ms, callback[, arg1[, arg2]]) -> timer_id
  ----------------------------------------------------------------------------
    ms <= 0 按 1ms。callback 触发时原样收到 arg1/arg2。
    timer_id 从 1 起。once 触发后自动释放 slot；loop 一直占着直到 delete。

  ----------------------------------------------------------------------------
  rt.tmr_stop(id) / tmr_start(id) / tmr_delete(id) -> ok[, err]
  ----------------------------------------------------------------------------
    stop 暂停，不释放 callback。start 用创建时的 ms 再开。
    delete 停止并释放 slot。不存在返回 false, "not found"。

  不要在回调里 delay / mbox_recv / mq_recv。

  ============================================================================
  本 demo
  ============================================================================
    once 2s 打一次；loop 1s 打几次；主协程 stop 2s 再 start，然后 delete。

]=]
