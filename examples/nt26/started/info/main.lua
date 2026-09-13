--[=[
  info demo — 读本机身份、驻网和信号
  ============================================================================
  本 demo
  ============================================================================
    1) 打印 imei / imsi / iccid / cfun
    2) 每 10 秒打印 signal / ntp / csq / cereg / islink

]=]

local rt = require("rt")
local log = require("log")
local info = require("info")

log.info("imei=%s", info.imei())
log.info("imsi=%s", info.imsi())
log.info("iccid=%s", info.iccid())

local ok, cfun = info.cfun(info.CFUN_GET)
log.info("cfun ok=%s value=%s", ok, cfun)



while true do
    -- 获取信号
    local sig = info.signal()
    if sig ~= nil then
        log.info("signal csq=%d snr=%d rsrp=%d rsrq=%d",
                 sig.csq or 99, sig.snr or 0, sig.rsrp or 0, sig.rsrq or 0)
    else
        log.info("signal=nil")
    end

    -- 获取时间
    log.info("ntp=%s", info.ntp())

    -- 获取驻网等信息
    log.info("csq=%d cereg=%d islink=%d",
             info.csq() or 99, info.cereg() or -1, info.islink() or -1)

    rt.delay(10 * 1000)
end

--[=[
  info demo — 读本机身份、驻网和信号

  info 是平台扩展模块，require("info") 后即可用。
  字符串类失败返回 nil；csq 失败为 99，cereg/islink 失败为 -1。

    身份    info.imei() / imsi() / iccid()     string | nil
    射频    info.cfun(info.CFUN_GET)           true, cfun  或  false
    信号    info.signal()                      { csq, snr, rsrp, rsrq } | nil
            info.csq()                         number（失败 99）
    驻网    info.cereg()                       CEREG 状态（失败 -1）
            info.islink()                      1 已激活 / 0 未激活 / -1
                                               （默认 CID=1 的 PDP）

  本 demo：先打身份 / CFUN，再每 10 秒打信号和驻网。
  授时见独立模块 ntp（network/ntp 工程）。
  注：如果设备没有SIM卡，则很多参数会是 nil 或 99 或 -1
  注：本 demo 不是完整的 info 模块使用示例，仅演示基本用法

  ============================================================================
  本 demo
  ============================================================================
    1) 打印 imei / imsi / iccid / cfun
    2) 每 10 秒打印 signal / ntp / csq / cereg / islink

]=]
