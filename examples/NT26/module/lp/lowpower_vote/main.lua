--[=[
  lowpower_vote demo — lp 模块内的低功耗投票
  ============================================================================
  本 demo
  ============================================================================
    投票在 lp 里：lp.vote_create 得到实例，不是独立 vote 模块。
    开机直接切 MODE_LOW_POWER_2，再开 A/B 两条任务错开投票：
    干活前 acquire 保活，delay 模拟耗时，干完 release 允许睡。
    WAKE 在回调里打印，并带上唤醒源。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")

-- 全票允许睡眠后，延迟这么久再切回低功耗 2（毫秒）
local SLEEP_DELAY_MS = 3000

local function lp_state_name(state)
    if state == lp.NET_ATTACHED then
        return "NET_ATTACHED"
    elseif state == lp.NET_DETACHED then
        return "NET_DETACHED"
    elseif state == lp.SIM_READY then
        return "SIM_READY"
    elseif state == lp.SIM_REMOVED then
        return "SIM_REMOVED"
    elseif state == lp.MODE_CHANGE then
        return "MODE_CHANGE"
    elseif state == lp.WAKE then
        return "WAKE"
    end
    return "UNKNOWN(" .. tostring(state) .. ")"
end

local function lp_mode_name(mode)
    if mode == lp.MODE_NORMAL then
        return "MODE_NORMAL"
    elseif mode == lp.MODE_LOW_POWER then
        return "MODE_LOW_POWER"
    elseif mode == lp.MODE_LOW_POWER_2 then
        return "MODE_LOW_POWER_2"
    elseif mode == lp.MODE_PSM_PLUS then
        return "MODE_PSM_PLUS"
    end
    return "UNKNOWN_MODE(" .. tostring(mode) .. ")"
end

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

-- 回调必须立刻返回。WAKE 一定打；MODE_CHANGE 能看到投票把模式拉到常电/低功耗 2。
lp.reg_netcb(function(state, extra)
    if state == lp.WAKE then
        local src = extra or -1
        log.info("[lp.netcb] WAKE src=%s (%d)", lp_wake_src_name(src), src)
    elseif state == lp.MODE_CHANGE then
        local m = extra or -1
        log.info("[lp.netcb] MODE_CHANGE new_mode=%s (%d)", lp_mode_name(m), m)
    else
        log.info("[lp.netcb] %s (%d)", lp_state_name(state), state)
    end
end)

-- 1. 系统直接进低功耗模式 2
lp.set_mode(lp.MODE_LOW_POWER_2)
log.info("set MODE_LOW_POWER_2, current=%s (%d)",
    lp_mode_name(lp.get_mode()), lp.get_mode())

-- 2. 投票实例挂在 lp 上：无人保活后 delay，再切回低功耗 2
local vote, err_vote = lp.vote_create({
    sleep_mode = lp.MODE_LOW_POWER_2,
    max_keys = 8,
    sleep_delay_ms = SLEEP_DELAY_MS,
})
if not vote then
    log.info("vote_create fail: %s", tostring(err_vote))
    return
end
log.info("vote_create ok, sleep_delay_ms=%d", SLEEP_DELAY_MS)

local function dump_status(tag)
    local st = vote:status()
    local keys = st.keys or {}
    log.info("[%s] active_count=%d keys=%s mode=%s",
        tag, st.active_count or -1, table.concat(keys, ","),
        lp_mode_name(lp.get_mode()))
end

-- 干活前投票保活；delay 只模拟耗时；干完投票允许睡
local function run_worker(name, key, first_delay_ms, work_ms, rest_ms)
    if first_delay_ms > 0 then
        log.info("[%s] 错开启动，先等 %d ms", name, first_delay_ms)
        rt.delay(first_delay_ms)
    end

    while true do
        local ok_acq, err_acq = vote:acquire(key)
        log.info("[%s] acquire %s err=%s", name, tostring(ok_acq), tostring(err_acq))
        dump_status(name)
        log.info("[%s] 正在执行业务，不能休眠（模拟 %d ms）", name, work_ms)
        rt.delay(work_ms)

        local ok_rel, err_rel = vote:release(key)
        log.info("[%s] 业务结束，投票允许睡眠 ok=%s err=%s",
            name, tostring(ok_rel), tostring(err_rel))
        dump_status(name)

        -- 休息这段时间让系统有机会真正入睡；到期后 RTC 会再把本任务拉起来
        rt.delay(rest_ms)
    end
end

-- 3. 两条任务轮流/交错投票：A 立刻开工 8s，B 晚 5s 再干 10s，休息周期不同
rt.task_start(function()
    run_worker("A", "task_a", 0, 8 * 1000, 22 * 1000)
end)

rt.task_start(function()
    run_worker("B", "task_b", 5 * 1000, 10 * 1000, 20 * 1000)
end)

-- 入口协程不再周期性 delay，避免自己把休眠打醒；WAKE 来自任务到期或外部唤醒
rt.delay(-1)

--[=[
  lowpower_vote demo — lp 模块内的低功耗投票

  ============================================================================
  投票在哪
  ============================================================================
    投票不是独立模块，接口都在 lp 里：

      local vote = lp.vote_create({
          sleep_mode = lp.MODE_LOW_POWER_2,  -- 全部允许睡眠后要回到的模式
          max_keys = 8,                      -- 最多几个 key 同时投票
          sleep_delay_ms = 3000,             -- 全释放后延迟再睡，默认 10000
      })

      vote:acquire(key)   -- 投票：有业务，切 MODE_NORMAL，不能睡
      vote:release(key)   -- 投票：本 key 允许睡；全部释放后才启动入睡倒计时
      vote:status()       -- {active_count, sleep_mode, sleep_delay_ms, max_keys, keys}

    只要还有一个 key 处于 acquire，系统就保持常电。
    全部 release 后等 sleep_delay_ms，再 set_mode(sleep_mode)。

  ============================================================================
  本 demo 时序（约 30s 一个来回）
  ============================================================================
    t=0    A acquire，打印「正在执行业务，不能休眠」，delay 8s
    t=5    B acquire（与 A 重叠，active_count=2）
    t=8    A release，B 还在干活，不会睡
    t=15   B release，active_count=0，3s 后切回 MODE_LOW_POWER_2
    t=18   空闲入睡
    t=30   A 休息到期 → WAKE（多为 RTC）→ A 再次 acquire
    t=35   B 休息到期，再次 acquire

  ============================================================================
  网络回调 / 唤醒源
  ============================================================================
    lp.reg_netcb(function(state [, extra]) ... end)
    回调必须立刻返回，不要 rt.delay。

    lp.WAKE 第二参数 extra 为唤醒源：
      lp.WAKE_POR / WAKE_RTC / WAKE_PAD / WAKE_UART
      lp.WAKE_USB / WAKE_PWRKEY / WAKE_CHARG

    任务 rt.delay 到期把模组拉起来时，通常是 WAKE_RTC。

  ============================================================================
  注意
  ============================================================================
    入口用 rt.delay(-1)，避免主循环自己每几秒醒一次。
    测电流时请注释掉回调和业务 log，串口打印会把休眠脉冲放大。

]=]
