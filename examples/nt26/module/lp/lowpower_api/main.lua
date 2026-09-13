--[=[
  lowpower_api demo — 三种低功耗模式轮换（不含 PSM）
  ============================================================================
  本 demo
  ============================================================================
    注册网络/模式/唤醒回调后，主循环每 2 分钟在
    MODE_NORMAL → MODE_LOW_POWER → MODE_LOW_POWER_2 之间切换，周而复始。
    不含 MODE_PSM_PLUS。从 Sleep 唤醒时回调里会打 WAKE。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")

local INTERVAL_MS = 2 * 60 * 1000

-- 不含 PSM。顺序：正常 → 低功耗1 → 低功耗2 → 再回到正常
local MODES = {
    lp.MODE_LOW_POWER_2,
    lp.MODE_NORMAL,
    lp.MODE_LOW_POWER,
    lp.MODE_LOW_POWER_2,
}

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

-- 回调必须立刻返回：只打日志。
-- MODE_CHANGE 第二参数是切换后的模式；WAKE 是 Sleep1/2/Hibernate 唤醒恢复。
lp.reg_netcb(function(state, mode)
    if state == lp.MODE_CHANGE then
        local m = mode or -1
        log.info("[lp.netcb] %s new_mode=%s (%d)",
            lp_state_name(state), lp_mode_name(m), m)
    elseif state == lp.WAKE then 
        local src = mode or -1
        local src_name = "UNKNOWN"
        if src == lp.WAKE_POR then
            src_name = "POR"
        elseif src == lp.WAKE_RTC then
            src_name = "RTC"
        elseif src == lp.WAKE_PAD then
            src_name = "PAD"
        elseif src == lp.WAKE_UART then
            src_name = "UART"
        elseif src == lp.WAKE_USB then
            src_name = "USB"
        elseif src == lp.WAKE_PWRKEY then
            src_name = "PWRKEY"
        elseif src == lp.WAKE_CHARG then
            src_name = "CHARG"
        end
        log.info("[lp.netcb] WAKE src=%s (%d)", src_name, src)
    else
        log.info("[lp.netcb] %s (%d)", lp_state_name(state), state)
    end
end)

log.info("lp demo start, cycle every %d ms, current=%s (%d) pdp=%d",
    INTERVAL_MS, lp_mode_name(lp.get_mode()), lp.get_mode(), lp.islink())

local idx = 1
while true do
    local mode = MODES[idx]
    log.info("set_mode %s (%d)", lp_mode_name(mode), mode)
    lp.set_mode(mode)
    log.info("get_mode %s (%d)", lp_mode_name(lp.get_mode()), lp.get_mode())

    -- delay 让出协程，到期后切下一个模式；空闲时模组可按当前模式休眠
    rt.delay(INTERVAL_MS)
    idx = idx % #MODES + 1
end

--[=[
  lowpower_api demo — 三种低功耗模式轮换（不含 PSM）

  ============================================================================
  低功耗模式
  ============================================================================
    lp.MODE_NORMAL       常电，不主动进休眠
    lp.MODE_LOW_POWER    低功耗 1（空闲后 Sleep1 一类）
    lp.MODE_LOW_POWER_2  低功耗 2
    lp.MODE_PSM_PLUS     PSM+，本 demo 不用

  切模式：
    lp.set_mode(mode)     立即请求切换
    lp.get_mode()         读当前模式
    lp.islink()           0/1，PDP 是否已驻网

  真正入睡发生在「当前模式允许休眠 + 空闲」之后，不是 set_mode 当下立刻断电。
  串口有数据、定时 delay 到期，都会把模组拉起来，然后再按当时模式决定能不能睡回去。

  ============================================================================
  网络回调
  ============================================================================
    lp.reg_netcb(function(state [, extra]) ... end)

    state:
      lp.NET_ATTACHED / NET_DETACHED
      lp.SIM_READY / SIM_REMOVED
      lp.MODE_CHANGE   此时第二参数 extra 为切换后的模式
      lp.WAKE   【E1.2.18版本新增】       从 Sleep1 / Sleep2 / Hibernate 唤醒恢复
                   第二参数 extra 为唤醒源（见下方）

    回调跑在调度循环里，必须立刻返回，不要 rt.delay / uart.block。

  ============================================================================
  唤醒源（lp.WAKE 的第二参数 extra）
  ============================================================================
    lp.WAKE_POR      上电/复位
    lp.WAKE_RTC      RTC（含 Sleep1 周期醒） 有些系统内部调度也会时不时的触发他，一般都是一瞬间就结束，不必过分纠结这个
    lp.WAKE_PAD      引脚
    lp.WAKE_UART     串口
    lp.WAKE_USB      USB
    lp.WAKE_PWRKEY   电源键
    lp.WAKE_CHARG    充电

    例：
      if state == lp.WAKE then
          -- extra 为 lp.WAKE_* 之一
      end

  ============================================================================
  本 demo
  ============================================================================
    每 2 分钟：NORMAL → LOW_POWER → LOW_POWER_2 → NORMAL …
    回调打印驻网、模式变化和 WAKE（含唤醒源），便于对照电流波形。
    测电流时请注释掉 WAKE 日志，串口打印会把休眠电流脉冲放大。

]=]
