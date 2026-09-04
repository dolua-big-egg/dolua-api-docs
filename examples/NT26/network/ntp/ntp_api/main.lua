--[=[
  ntp demo — 先等网络，再问 NTP
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 ntp」后空转
    2) 先测内置服务器 ntp.get()
    3) 再测其它服务器
    4) 最后一次 auto_set=true，把内置服务器时间写入本机

]=]

local rt = require("rt")
local log = require("log")
local ntp = require("ntp")
local lp = require("lp")

local LINK_WAIT_MS = 60 * 1000

local function ntp_one(tag, ...)
    local t = ntp.get(...)
    if t then
        log.info("%s ok %s", tag, t)
        return true
    end
    log.warn("%s fail", tag)
    return false
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 ntp")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start ntp")

log.info("---- builtin server ----")
ntp_one("builtin")

log.info("---- other servers ----")
ntp_one("aliyun", "ntp.aliyun.com")
ntp_one("ntsc", "ntp.ntsc.ac.cn", 123, 8000)
ntp_one("cn.ntp.org.cn", "cn.ntp.org.cn", 123, 8000)
ntp_one("pool.ntp.org", "pool.ntp.org", 123, 8000, 480)

log.info("---- write local clock ----")
ntp_one("auto_set", nil, nil, nil, nil, true)

while true do
    rt.delay(10000)
end

--[=[
  ntp demo — 先等网络，再问 NTP

  NTP 是独立模块：require("ntp")。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停，不测 NTP。

  ----------------------------------------------------------------------------
  lp.wait_link([timeout_ms]) -> boolean     别名 wait_attach
  ----------------------------------------------------------------------------
    timeout_ms  可选，毫秒；省略或 -1 表示一直等
    返回        true 已驻网/PDP 激活；false 超时仍没网
    会让出当前协程。已驻网则立刻 true。

  ----------------------------------------------------------------------------
  ntp.get(server, port, timeout_ms, tz_min, auto_set) -> string | nil
  ----------------------------------------------------------------------------
    同步向 NTP 服务器要时间。底层 UDP 问询，调用返回前当前协程被占住
    （不是 uart.block 那种让出，timeout 别开得过大）。

    参数都可以省略，中间想跳过某项就传 nil。

    server     字符串，NTP 主机名或 IP。省略/nil = ntp.DEFAULT_SERVER（ntp1.aliyun.com）
    port       0~65535，默认 ntp.DEFAULT_PORT（123）；非法会抛错
    timeout_ms >0，默认 ntp.DEFAULT_TIMEOUT（6000）；<=0 会抛错
    tz_min     时区偏移，单位分钟。省略/nil = 用系统当前时区（timezone*15）
               480 = UTC+8；0 = UTC；负数西区
    auto_set   true/1 时把这次 NTP 的 UTC 秒写入本机时钟（同 sys.set_ts）
               只置 time_ready，不置 nitz_ready，不走 nitz 回调
               false/省略 = 只读时间，不改本机钟

    返回  成功：时间字符串（一般 "YYYY-MM-DD HH:MM:SS"，非 0 时区可能带 +08 这类后缀）
          失败：nil（没网、DNS/UDP 失败、超时、auto_set 写钟失败）

    常量
      ntp.DEFAULT_SERVER / DEFAULT_PORT / DEFAULT_TIMEOUT

    例
      ntp.get()
      ntp.get("cn.ntp.org.cn")
      ntp.get("ntp.ntsc.ac.cn", 123, 8000)
      ntp.get("ntp1.aliyun.com", 123, 6000, 480)
      ntp.get(nil, nil, nil, nil, true)    -- 内置服务器，并写入本机钟

  需要网络。没 SIM / 没驻网会一直 nil。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 ntp」后空转
    2) 先测内置服务器 ntp.get()
    3) 再测其它服务器
    4) 最后一次 auto_set=true，把内置服务器时间写入本机

]=]
