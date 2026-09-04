--[=[
  wifiscan demo — 先扫周围 AP，有网再做 WiFi 定位
  ============================================================================
  本 demo
  ============================================================================
    1) wifiscan.scan() 默认参数
    2) scan 带 max_bssid_num / round
    3) lp.wait_link 最多 60 秒；超时则不测 location
    4) wifiscan.location() 默认
    5) location 带嵌套 scan 和超时
    扫描不需要上网；定位要扫到 AP 并且 PDP 已激活。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local wifiscan = require("wifiscan")

local LINK_WAIT_MS = 60 * 1000

log.info("ERR_OK=%s TIMEOUT=%s INVALID=%s SCAN=%s NET=%s IMEI=%s PARSE=%s",
         wifiscan.ERR_OK, wifiscan.ERR_TIMEOUT, wifiscan.ERR_INVALID_PARAM,
         wifiscan.ERR_GET_WIFI_SCAN, wifiscan.ERR_NETWORK_NOT_READY,
         wifiscan.ERR_GET_IMEI, wifiscan.ERR_PARSE_RESPONSE)

log.info("---- scan default ----")
local list, err, msg = wifiscan.scan()
if list then
    log.info("scan n=%d", #list)
    for i = 1, #list do
        local ap = list[i]
        log.info("  [%d] ssid=%s rssi=%s ch=%s bssid=%s",
                 i, tostring(ap.ssid), tostring(ap.rssi),
                 tostring(ap.channel), tostring(ap.bssid))
    end
else
    log.warn("scan fail code=%s msg=%s", tostring(err), tostring(msg))
end

log.info("---- scan max_bssid_num=8 ----")
list, err, msg = wifiscan.scan({
    max_bssid_num = 8,
    round = 1,
    max_time_out_ms = 12000,
})
if list then
    log.info("scan8 n=%d", #list)
    for i = 1, #list do
        log.info("  [%d] %s rssi=%s", i, tostring(list[i].ssid), tostring(list[i].rssi))
    end
else
    log.warn("scan8 fail code=%s msg=%s", tostring(err), tostring(msg))
end

log.info("wait_link %d ms (location needs PDP)", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 wifiscan.location")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start location")

log.info("---- location default ----")
local resp, lerr, lmsg = wifiscan.location()
if resp then
    log.info("loc lon=%s lat=%s addr=%s prec=%s srv=%s %s",
             tostring(resp.longitude), tostring(resp.latitude),
             tostring(resp.address), tostring(resp.precision),
             tostring(resp.server_err_code), tostring(resp.server_err_msg))
else
    log.warn("location fail code=%s msg=%s", tostring(lerr), tostring(lmsg))
end

log.info("---- location with nested scan ----")
resp, lerr, lmsg = wifiscan.location({
    timeout_s = 8,
    timeout_r = 10,
    retry_count = 1,
    min_ap_count = 3,
    scan = {
        max_bssid_num = 8,
        round = 1,
        max_time_out_ms = 12000,
    },
})
if resp then
    log.info("loc2 lon=%s lat=%s addr=%s prec=%s",
             tostring(resp.longitude), tostring(resp.latitude),
             tostring(resp.address), tostring(resp.precision))
else
    log.warn("location2 fail code=%s msg=%s", tostring(lerr), tostring(lmsg))
end

log.info("wifiscan demo done")
while true do
    rt.delay(10000)
end

--[=[
  wifiscan demo — WiFi 扫描与 DoIoT WiFi 定位

  require("wifiscan")。scan 走模组射频扫周围 AP，不需要上网。
  location 先扫 AP，再 POST 到 DoIoT 云（要 IMEI + PDP）。
  调用返回前当前协程被占住（不是 rt.delay 那种让出），超时别开过大。
  室内要能扫到 AP；AP 太少或没网，location 会失败。

  ----------------------------------------------------------------------------
  wifiscan.scan([config]) -> list | nil, err_code, err_msg
  ----------------------------------------------------------------------------
    省略 config 则用 HAL 默认：
      max_time_out_ms = 12000     整次扫描总超时（毫秒）
      round = 1                   扫描轮数
      max_bssid_num = 5           最多上报几个 AP
      scan_timeout_s = 5          每轮 RRC 超时（秒）
      wifi_priority = 0           0=数据优先，1=WiFi 扫描优先
      channel_rec_len_ms = 280    每信道停留
      channel_count = 1
      channel_id = {0}            count=1 且 id[0]=0 表示全信道
    指定信道：channel_count=2, channel_id={1,6}（最多 14 个）。

    成功 list 数组，每项：
      ssid     字符串，隐藏网络可能是空串
      rssi     dBm
      bssid    "AA:BB:CC:DD:EE:FF"
      channel  1~13/14

    失败 nil, err_code, err_msg。扫描失败常见：
      wifiscan.ERR_TIMEOUT / ERR_INVALID_PARAM / ERR_GET_WIFI_SCAN

    例  wifiscan.scan()
        wifiscan.scan({ max_bssid_num = 8, round = 1 })
        wifiscan.scan({ channel_count = 2, channel_id = { 1, 6 } })

  ----------------------------------------------------------------------------
  wifiscan.location([config]) -> resp | nil, err_code, err_msg
  ----------------------------------------------------------------------------
    内部：扫 AP → 带 IMEI/MAC/RSSI 请求 DoIoT → 解析经纬度和地址。
    必须已驻网。config 可选：

      timeout_s / timeout_r   HTTP 发/收超时（秒），0=模块默认
      pdp_id                  PDP 上下文，0=默认
      retry_count             HTTP 重试，0=默认
      precision               坐标小数位 1~8，0=NVRAM/默认
      min_ap_count            最少 AP 数，0=默认 5
      scan                    表，字段同 wifiscan.scan 的 config

    成功 resp：
      longitude / latitude / address   字符串
      precision                        小数位数
      server_err_code / server_err_msg 平台侧，0 表示成功

    经纬度空串会当成失败：ERR_PARSE_RESPONSE, "wifi location empty result"。

    失败 err_code 还可能是：
      ERR_NETWORK_NOT_READY / ERR_GET_IMEI / ERR_GET_WIFI_SCAN
      ERR_TIMEOUT / ERR_INVALID_PARAM

    例  wifiscan.location()
        wifiscan.location({
            timeout_s = 8, timeout_r = 10, min_ap_count = 3,
            scan = { max_bssid_num = 8 },
        })

  ----------------------------------------------------------------------------
  常量（与 lbs_client 错误码同一套数字）
  ----------------------------------------------------------------------------
    wifiscan.ERR_OK                  0
    ERR_INVALID_PARAM               -1
    ERR_NETWORK_NOT_READY           -3
    ERR_GET_IMEI                    -5
    ERR_PARSE_RESPONSE             -10
    ERR_TIMEOUT                    -12
    ERR_GET_WIFI_SCAN              -13

  ============================================================================
  本 demo
  ============================================================================
    先默认扫、再 max_bssid_num=8；有网才 location 两次（默认 / 嵌套 scan）。
    没网只停在扫描结果上，不测定位。

]=]
