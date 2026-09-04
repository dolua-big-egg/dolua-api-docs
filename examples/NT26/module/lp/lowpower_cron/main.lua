--[=[
  lowpower_cron demo — cron 五分钟对齐唤醒
  ============================================================================
  cron 是什么
  ============================================================================
    cron 是按墙上时钟对齐的调度器，不是 rt.delay 那种“再过 N 毫秒”。
    表达式是 Quartz 风格：秒 分 时 日 月 星期 [年]。
    例：0 */5 * * * ?  表示每个整 5 分钟的 0 秒（xx:00:00、xx:05:00 …）。
    必须先有正确时间（驻网后 NITZ/授时），否则算不准下一拍。
    调度用 osDelay 等到点，系统可以睡；到点 RTC 把模组拉起来再跑回调。

  ============================================================================
  本 demo
  ============================================================================
    等驻网 → 确认时间已同步 → 切 MODE_LOW_POWER_2
    → 注册 5 分钟对齐 cron，回调里只 mbox_send
    → 独立 task 收到后再打印。理想情况：每个整 5 分钟都会唤醒并打一行。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local cron = require("cron")
local info = require("info")
local sys = require("sys")

-- 秒=0，分钟 */5：墙上时钟 5 分钟对齐（不是“从现在起每 5 分钟”）
local CRON_EXPR = "0 */5 * * * ?"
local TOPIC = "cron_5min"

local function lp_wake_src_name(src)
    if src == lp.WAKE_POR then
        return "POR"
    elseif src == lp.WAKE_RTC then
        return "RTC"
    elseif src == lp.WAKE_PAD then
        return "PAD"
    elseif src == lp.WAKE_UART then
        return "UART"
    elseif src == lp.WAKE_USB then
        return "USB"
    elseif src == lp.WAKE_PWRKEY then
        return "PWRKEY"
    elseif src == lp.WAKE_CHARG then
        return "CHARG"
    end
    return "UNKNOWN"
end

-- WAKE / 模式变化打日志；业务打印放在 task 里
lp.reg_netcb(function(state, extra)
    if state == lp.WAKE then
        local src = extra or -1
        log.info("[lp.netcb] WAKE src=%s (%d) time=%s",
            lp_wake_src_name(src), src, tostring(info.times()))
    elseif state == lp.MODE_CHANGE then
        log.info("[lp.netcb] MODE_CHANGE extra=%s time=%s",
            tostring(extra), tostring(info.times()))
    end
end)

-- 先挂接收任务：回调只投递，打印在这里做
rt.task_start(function()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok then
            log.info("[task] cron 5min aligned time=%s ev=%s",
                tostring(info.times()), tostring(ev))
        end
    end
end)

-- 1) 等待驻网
log.info("wait_link ...")
local linked = lp.wait_link(-1)
log.info("wait_link ok=%s pdp=%s", tostring(linked), tostring(lp.islink()))

-- 2) 确认时间已同步（cron 按墙上时钟算下一拍，未授时不能用）
sys.nitz_reg(function(ts)
    log.info("NITZ ts=%s times=%s", tostring(ts), tostring(info.times()))
end)

log.info("wait time sync, time_ready=%s nitz_ready=%s times=%s",
    tostring(info.time_ready()), tostring(info.nitz_ready()), tostring(info.times()))
while not info.time_ready() do
    rt.delay(1000)
end
log.info("time synced times=%s time_ready=%s nitz_ready=%s",
    tostring(info.times()), tostring(info.time_ready()), tostring(info.nitz_ready()))

-- 3) 切低功耗 2，空闲后可睡；到点由 cron/RTC 拉起来
lp.set_mode(lp.MODE_LOW_POWER_2)
log.info("set MODE_LOW_POWER_2 current=%s", tostring(lp.get_mode()))

-- 4) 5 分钟对齐；回调必须立刻返回，只推事件到 task
local trigger_id, err_create = cron.create_trigger(CRON_EXPR)
if not trigger_id or trigger_id == 0 then
    log.info("create_trigger fail: %s", tostring(err_create))
    return
end
log.info("create_trigger id=%s expr=%s", tostring(trigger_id), CRON_EXPR)

local ok_bind, err_bind = cron.bind_trigger(trigger_id, function()
    rt.mbox_send(TOPIC, "tick")
end)
if not ok_bind then
    log.info("bind_trigger fail: %s", tostring(err_bind))
    return
end

local ok_start, err_start = cron.start()
log.info("cron.start ok=%s err=%s next aligned 5min, now=%s",
    tostring(ok_start), tostring(err_start), tostring(info.times()))

-- 入口不再周期性 delay，避免自己把休眠打醒
rt.delay(-1)

-- 正常流程不执行到这里，这里只是为了防止cron挂了，导致无法睡眠。
while true do
    rt.delay(600*1000)
end

--[=[
  lowpower_cron demo — cron 五分钟对齐唤醒

  ============================================================================
  cron 是什么
  ============================================================================
    内置单例模块 require("cron")，按墙上时钟（年月日时分秒）对齐触发。

    和 rt.delay 的差别：
      rt.delay(300000)     从“现在”再等 5 分钟，和钟点无关
      cron "0 */5 * * * ?" 对齐到 xx:00 / xx:05 / xx:10 … 的 0 秒

    表达式（Quartz，空格分隔）：
      秒  分  时  日  月  星期  [年]
      日和星期必须有一个写 ?。

      0 */5 * * * ?     每 5 分钟整分 0 秒（本 demo）
      0 * * * * ?       每分钟 0 秒
      0 15 10 * * ?     每天 10:15:00
      0/10 * * * * ?    每 10 秒（高频请用 delay，不要用 cron）

    未授时时调度线程不会 1 秒轮询；NITZ/授时成功后才会按真实时钟算下一拍。
    等到点用 osDelay，系统可以进低功耗；到期 RTC 唤醒。

  ============================================================================
  接口（节选）
  ============================================================================
    id, err = cron.create_trigger(expr)
    ok, err = cron.bind_trigger(id, fn)   -- fn 要立刻返回
    ok, err = cron.start()
    cron.pause() / cron.resume()
    cron.pause_trigger(id) / cron.resume_trigger(id)
    cron.replace_trigger(id, expr)
    cron.remove_trigger(id)

  ============================================================================
  本 demo 流程
  ============================================================================
    1. lp.wait_link(-1)              等驻网
    2. 等到 info.time_ready()        确认时钟已同步（NITZ/NTP/应用授时均可）
    3. lp.set_mode(MODE_LOW_POWER_2)
    4. cron 5 分钟对齐；回调里只 rt.mbox_send
    5. task 里 mbox_recv 后打印当前时间

    理想波形：空闲睡在低功耗 2；每个整 5 分钟 WAKE（多为 RTC）+ task 打一行。

    回调跑在调度循环里，不要 rt.delay / 打太久的 log。
    测电流时请注释掉打印，串口会把休眠脉冲放大。

]=]
