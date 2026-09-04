--[=[
  script demo — AB bundle 查询 / trial 确认
  ============================================================================
  本 demo
  ============================================================================
    1) script.info() 读当前启动副本
    2) script.info("A") / info("B") 读两个槽的 manifest
    3) 仅当 mode=trial 时 script.confirm()
    不演示 switch / rollback。

    -- A/B槽系统，因为内部flash空间不足，暂时未正式开放，但是属于底层设计。
    但是这个模块暂时可以用来读取lua工程的版本号。

]=]

local rt = require("rt")
local log = require("log")
local script = require("script")

local function dump_info(tag, info)
    log.info("%s slot=%s version=%s build=%s bundle_id=%s mode=%s first_run=%s",
             tag,
             tostring(info.slot),
             tostring(info.version),
             tostring(info.build),
             tostring(info.bundle_id),
             tostring(info.mode),
             tostring(info.first_run))
end

local function try_info(slot)
    local ok, info
    if slot then
        ok, info = pcall(script.info, slot)
    else
        ok, info = pcall(script.info)
    end
    if ok then
        dump_info(slot and ("info(" .. slot .. ")") or "info()", info)
        return info
    end
    log.warn("%s fail %s", slot and ("info(" .. slot .. ")") or "info()", tostring(info))
    return nil
end

log.info("---- current bundle ----")
local cur = try_info()

log.info("---- slot A / B ----")
try_info("A")
try_info("B")

log.info("---- confirm ----")
if cur and cur.mode == "trial" then
    local ok, ret = pcall(script.confirm)
    if ok then
        log.info("confirm ok")
        try_info()
    else
        log.warn("confirm fail %s", tostring(ret))
    end
else
    log.info("skip confirm, mode=%s (only trial needs confirm)",
             cur and tostring(cur.mode) or "nil")
end

while true do
    rt.delay(10000)
end

--[=[
  script demo — AB bundle 查询 / trial 确认

  require("script")。脚本以 A/B 两槽存放，当前启动的那份叫 boot bundle。

  ----------------------------------------------------------------------------
  script.info([slot]) -> table
  ----------------------------------------------------------------------------
    无参     当前 boot bundle
    slot     "A" 或 "B"，读该槽 manifest
    失败抛错（槽无效、manifest 读不到、bundle 未就绪）

    返回表
      slot        "A" / "B"
      version     版本字符串
      build       构建号
      bundle_id   副本 ID
      mode        "normal" 或 "trial"
      first_run   本次启动后脚本首次运行的本地时间 "YYYY-MM-DD HH:MM:SS"
                  未记录或时钟不可用时为空串

  ----------------------------------------------------------------------------
  script.confirm() -> true
  ----------------------------------------------------------------------------
    确认当前 trial 副本运行成功，mode 回到 normal。
    不在 trial、或 trial 槽与当前 boot 不一致时抛错。
    本 demo 只在 mode=trial 时调用。

  script.switch / script.rollback 尚未完善，本 demo 不调用。

  ============================================================================
  本 demo
  ============================================================================
    打印当前副本和 A/B 两槽；trial 时 confirm，否则跳过。

]=]
