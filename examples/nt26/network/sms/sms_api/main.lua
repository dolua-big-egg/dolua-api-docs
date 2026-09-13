--[=[
  sms demo — 收短信，可选异步发送
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印后空转
    2) sms.reg 收 NEW_SMS / SEND_DONE / SEND_FAILED
    3) 顶部 DA 填了手机号才 send_async 一条；空串只收不发
    回调必须马上返回，不要 send / delay。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local sms = require("sms")

--[[ 改成你的手机号才发测试短信，例如 "13800138000"。空串 = 只收不发。
    对了必须是手机卡哈，物联网卡不行的，测试该功能时可以用自己的手机卡。
    特别注意：千万不要用自己的手机卡时写 while(1) send 这种循环一直发送的代码，等你反应过来的时候可能已经因为
    发了太多，短信耗尽，或者因为连续发送被运营商当成垃圾号临时ban掉了。]]

local DA = ""
local LINK_WAIT_MS = 60 * 1000

local function ev_name(id)
    if id == sms.EVENT_NEW_SMS then
        return "NEW_SMS"
    elseif id == sms.EVENT_SEND_DONE then
        return "SEND_DONE"
    elseif id == sms.EVENT_SEND_FAILED then
        return "SEND_FAILED"
    end
    return tostring(id)
end

local function ret_name(ret)
    if ret == sms.ERR_OK then
        return "OK"
    elseif ret == sms.ERR_NET_NOT_ATTACHED then
        return "NET_NOT_ATTACHED"
    end
    return tostring(ret)
end

local function on_sms(ev)
    if not ev then
        return
    end
    log.info("sms %s sms_id=%s ip=%s sender=%s tag=%s text=%s",
             ev_name(ev.event_id), ev.sms_id, ev.is_sms_over_ip,
             tostring(ev.sender), ev.user_tag, tostring(ev.text))
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 sms")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start sms")

sms.reg(on_sms)
log.info("sms.reg ok, waiting NEW_SMS")

if DA ~= nil and DA ~= "" then
    local ret = sms.send_async(DA, "hello from lua", 30, 1001)
    log.info("send_async da=%s ret=%s", DA, ret_name(ret))
else
    log.info("DA empty, skip send; fill DA at top of file to test send_async")
end

while true do
    rt.delay(10000)
end

--[=[
  sms demo — 收短信，可选异步发送

  require("sms")。要 SIM、要驻网。事件走 sms.reg，不是公开 mbox。
  回调跑在调度循环里，必须马上返回。

  ----------------------------------------------------------------------------
  sms.reg(callback) -> true
  ----------------------------------------------------------------------------
    callback(ev)，重复调用覆盖；sms.reg(nil) 取消。
    ev 表：
      event_id         sms.EVENT_NEW_SMS / EVENT_SEND_DONE / EVENT_SEND_FAILED
      sms_id           新短信：存储 index（长短信合并后可能为 0）
                       SEND_DONE：TP-MR；SEND_FAILED：0xFF
      is_sms_over_ip   AT 路径一般为 0
      sender           新短信=发件人；发送结果=目标号码
      text             新短信=正文；发送结果当前为空串
      user_tag         异步发送时原样带回；新短信恒为 0

  ----------------------------------------------------------------------------
  sms.send(da, text [, guard_s]) -> ret
  sms.send_async(da, text [, guard_s, user_tag]) -> ret
  ----------------------------------------------------------------------------
    da        号码，如 "13800138000" 或 "+8613800138000"
    text      文本（7bit 可打印）
    guard_s   超时秒，默认 30
    user_tag  仅 async，结果事件里带回
    send      同步，占住当前协程；不要在回调里用
    send_async 入队即返回，结果靠 EVENT_SEND_DONE / SEND_FAILED

    成功 sms.ERR_OK(0)；未驻网 sms.ERR_NET_NOT_ATTACHED(-100)。
    其它失败为负数（参数、队列满等）。

  ============================================================================
  本 demo
  ============================================================================
    等驻网后注册回调。DA 非空则异步发一条并等结果；之后一直等收信。

]=]
