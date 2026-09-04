--[=[
  info demo — 设备身份、驻网、小区、时间、APN
  ============================================================================
  本 demo
  ============================================================================
    1) 身份：imei / imsi / iccid / cfun GET
    2) 驻网与信号：csq / cereg / islink / signal
    3) 小区：serv_cell / mult_cell
    4) APN：只 getapn，不 set / factory_reset（会改 NVM）
    5) 时间：time / times / timezone / time_ready / nitz_ready / timestamp / tick
    6) 每 10 秒再打一遍信号和时间

]=]

local rt = require("rt")
local log = require("log")
local info = require("info")

local function dump_signal()
    local sig = info.signal()
    if sig then
        log.info("signal csq=%s snr=%s rsrp=%s rsrq=%s", sig.csq, sig.snr, sig.rsrp, sig.rsrq)
    else
        log.info("signal=nil")
    end
end

log.info("---- identity ----")
log.info("imei=%s", info.imei())
log.info("imsi=%s", info.imsi())
log.info("iccid=%s", info.iccid())

local ok, cfun = info.cfun(info.CFUN_GET)
log.info("cfun GET ok=%s value=%s", ok, cfun)

log.info("---- network ----")
log.info("csq=%s cereg=%s islink=%s", info.csq(), info.cereg(), info.islink())
dump_signal()

log.info("---- cell ----")
local cell = info.serv_cell()
if cell then
    log.info("serv_cell mcc=%s mnc=%s tac=%s cell_id=%s snr=%s",
             cell.mcc, cell.mnc, cell.tac, cell.cell_id, cell.snr)
else
    log.info("serv_cell=nil")
end

local cells = info.mult_cell()
if cells then
    log.info("mult_cell count=%s", cells.count)
    for i = 1, cells.count do
        local c = cells[i]
        log.info("  [%d] serving=%s valid=%s mcc=%s mnc=%s tac=%s cell_id=%s snr=%s rsrp=%s rsrq=%s",
                 i, c.is_serving, c.cell_info_valid, c.mcc, c.mnc, c.tac, c.cell_id,
                 c.snr, c.rsrp, c.rsrq)
    end
else
    log.info("mult_cell=nil")
end

log.info("---- apn ----")
local apn = info.getapn()
if apn then
    log.info("apn=%s user=%s pass=%s auth=%s", apn.apn, apn.user, apn.pass, apn.auth)
else
    log.info("getapn=nil")
end

log.info("---- time ----")
local t = info.time()
if t then
    log.info("time %04d-%02d-%02d %02d:%02d:%02d.%03d w=%d",
             t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond, t.weekday)
else
    log.info("time=nil")
end
log.info("times=%s", info.times())
log.info("times custom=%s", info.times("%Y%m%d-%H%M%S"))
log.info("timezone=%s (unit=15min) time_ready=%s nitz_ready=%s",
         info.timezone(), info.time_ready(), info.nitz_ready())
log.info("timestamp=%s timestamp_ms=%s", info.timestamp(), info.timestamp_ms())
log.info("tick=%s tick_ms=%s", info.tick(), info.tick_ms())

log.info("---- loop ----")
while true do
    dump_signal()
    log.info("csq=%s cereg=%s islink=%s times=%s",
             info.csq(), info.cereg(), info.islink(), info.times())
    rt.delay(10 * 1000)
end

--[=[
  info demo — 设备身份、驻网、小区、时间、APN

  require("info")。没插 SIM 时不少字段是 nil / 99 / -1。
  授时写时钟见独立模块 ntp；本模块只读本机时间。

  ----------------------------------------------------------------------------
  身份
  ----------------------------------------------------------------------------
    info.imei() / imsi() / iccid()     string | nil

  ----------------------------------------------------------------------------
  射频 / 驻网 / 信号
  ----------------------------------------------------------------------------
    info.cfun(method)
      method = info.CFUN_GET / CFUN_MIN / CFUN_FULL / CFUN_RF_OFF
      GET：true, cfun  或  false
      其余：true/false。本 demo 只 GET，不关射频。

    info.csq()       number（失败 99）
    info.cereg()     CEREG state（失败 -1）
    info.islink()    默认 CID=1 的 PDP：1 已激活 / 0 未激活 / -1
    info.signal()    { csq, snr, rsrp, rsrq } | nil

  ----------------------------------------------------------------------------
  小区
  ----------------------------------------------------------------------------
    info.serv_cell()   { mcc, mnc, tac, cell_id, snr } | nil
    info.mult_cell()   { count, [1]= { is_serving, cell_info_valid,
                         mcc, mnc, tac, cell_id, snr, rsrp, rsrq }, ... } | nil

  ----------------------------------------------------------------------------
  APN（默认 CID=1，协议栈 NVM 持久化）
  ----------------------------------------------------------------------------
    info.getapn()     { apn, user, pass, auth } | nil
                      auth: 0=NONE 1=PAP 2=CHAP 3=CHAP+PAP
    info.setapn(apn [, user, pass [, auth]])
                      例：info.setapn("cmnet")
                          info.setapn("iot.apn", "u", "p", info.APN_AUTH_CHAP)
    info.apn_factory_reset()   恢复空 APN / 无鉴权
    本 demo 不调用 set / factory_reset，避免改设备配置。

  ----------------------------------------------------------------------------
  时间
  ----------------------------------------------------------------------------
    info.time()            { year, month, day, hour, minute, second,
                             millisecond, weekday } | nil   本地时间
    info.times([fmt])      默认 "%Y-%m-%d %H:%M:%S"
                           占位：%Y %y %m %d %H %M %S %s(毫秒) %w %%
    info.timezone()        时区，单位 15 分钟（例如 32 = UTC+8）
    info.time_ready()      机身时钟已同步（NITZ/CCLK/SNTP/应用授时）
    info.nitz_ready()      已通过基站 NITZ 授时
    info.timestamp()       UTC Unix 秒 | nil
    info.timestamp_ms()    UTC Unix 毫秒 | nil
    info.tick() / tick_ms()  开机 tick / 毫秒，与墙钟无关

  ============================================================================
  本 demo
  ============================================================================
    先把只读接口打一遍；setapn / cfun 关射频不演示。
    然后每 10 秒打印信号、驻网和时间。

]=]
