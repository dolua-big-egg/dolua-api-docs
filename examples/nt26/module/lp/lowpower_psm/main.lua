
--[=[

  lowpower_psm demo — PSM+ 对应内部 Hibernate
  ============================================================================
  开头读上次实际睡眠档和这次唤醒源。Hibernate 睡成后从头再跑，
  不会回到睡前的回调。

  WAKEUP0（wkpad 0）上下沿都开、内部下拉。脚闲低，拉高或松开都会产生沿。
  定时用 ID2。0/1 和 2～6 都能在 PSM（Hibernate）里走时并唤醒。
  0/1 在 AON，不写 Flash，最长约 2.5 小时。2～6 写入 Flash，最长约 740 小时。

  入口每 60 秒打一次剩余时间。进了 Hibernate 这行不会再出现，
  下一次开头的 wake_src 才是唤醒结果。若一直能看到 still up，
  说明没进 Hibernate。

  如果连着USB，需要拔掉USB哦，核心是VBUS，VBUS如果连着，设备不会进入休眠。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")

local DSTMR_ID = 1
local DSTMR_MS = 3 * 60 * 1000

local function slp_name(slp)
    if slp == lp.SLP_ACTIVE then
        return "SLP_ACTIVE"
    elseif slp == lp.SLP_IDLE then
        return "SLP_IDLE"
    elseif slp == lp.SLP_SLEEP1 then
        return "SLP_SLEEP1"
    elseif slp == lp.SLP_SLEEP2 then
        return "SLP_SLEEP2"
    elseif slp == lp.SLP_HIB then
        return "SLP_HIB"
    end
    return "UNKNOWN_SLP(" .. tostring(slp) .. ")"
end

local function wake_name(src)
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
    return "UNKNOWN(" .. tostring(src) .. ")"
end

local last_slp = lp.last_slp()
local wake_src = lp.wake_src()
log.info("[psm] boot last_slp=%s (%d) wake_src=%s (%d)",
    slp_name(last_slp), last_slp, wake_name(wake_src), wake_src)
print(string.format("[psm] boot last_slp=%s (%d) wake_src=%s (%d)",
    slp_name(last_slp), last_slp, wake_name(wake_src), wake_src))

-- WAKEUP0：上升沿和下降沿都开，内部下拉。0~2 不能关掉唤醒。
lp.wkpad(0, true, true, true, false, true)
local pad = lp.wkpad(0)
log.info("[psm] wkpad0 en=%s pos=%s neg=%s up=%s dn=%s",
    tostring(pad.enable), tostring(pad.pos), tostring(pad.neg),
    tostring(pad.pull_up), tostring(pad.pull_down))

-- ID2 会写 Flash。3 分钟在 0/1 和 2～6 的长度里都放得下。
lp.dstmr(DSTMR_ID, DSTMR_MS)
log.info("[psm] dstmr id=%d on=%s left_ms=%d",
    DSTMR_ID, tostring(lp.dstmr_on(DSTMR_ID)), lp.dstmr_left(DSTMR_ID))

lp.set_mode(lp.MODE_PSM_PLUS)
log.info("[psm] target MODE_PSM_PLUS, idle until pad or 10min RTC")

while true do
    rt.delay(60 * 1000)
    log.info("[psm] still up mode=%d dstmr_on=%s left_ms=%d last_slp=%s",
        lp.get_mode(), tostring(lp.dstmr_on(DSTMR_ID)), lp.dstmr_left(DSTMR_ID),
        slp_name(lp.last_slp()))
    print(string.format("[psm] still up mode=%d dstmr_on=%s left_ms=%d",
        lp.get_mode(), tostring(lp.dstmr_on(DSTMR_ID)), lp.dstmr_left(DSTMR_ID)))
end
