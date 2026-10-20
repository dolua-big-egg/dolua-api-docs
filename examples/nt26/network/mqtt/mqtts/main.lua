--[=[
  mqtts — 连 EMQX 公共 MQTTS
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印后空转
    2) create：MQTTS，TLS_AUTH = 1 用下面的 CA 做单向认证
    3) 服务器是 EMQX 公共 broker：broker.emqx.io:8883，匿名。不要在上面发隐私数据
    4) 证书是 DigiCert Global Root G2，和同目录 ca.pem 是同一份。叶子 *.emqx.io 由 RapidSSL TLS RSA CA G1 签发，链到这张根
    5) client_id 和主题都带本机 IMEI，避免和别人撞在同一个主题
    6) open 前 auto_sub。connected 里用 pub_async 发一行 hello mqtts。回调里不要用同步 pub
    7) 不要 close：目标保持「要连上」，断开后内部自己重连，auto_sub 会再订

    只加密、不校验证书时把 TLS_AUTH 改成 0。

]=]

-- DigiCert Global Root G2，自签根，有效期到 2038-01-15。与 ca.pem 相同。
local CA_PEM = [=[-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
MrY=
-----END CERTIFICATE-----
]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local mqtt = require("mqtt")
local info = require("info")

-- 1 = 单向认证（用 CA_PEM），0 = 只加密不校验证书
local TLS_AUTH = 1
local HOST = "broker.emqx.io"
local PORT = 8883

local c
local topic
local sent = false

local function on_mqtt(ev)
    if ev.event == "connected" then
        log.info("mqtts up")
        if not sent and topic then
            sent = true
            ev.client:pub_async(topic, "hello mqtts", 0, 0)
        end
    elseif ev.event == "message" then
        log.info("mqtts msg topic=%s data=%s", ev.mqtt_topic or "", ev.data or "")
    elseif ev.event == "disconnected" then
        sent = false
        log.warn("mqtts down")
    elseif ev.event == "error" then
        log.warn("mqtts err code=%d", ev.code)
    end
end

if not lp.wait_link(60000) then
    print("网络超时，没有网络无法测试 mqtts")
    while true do
        rt.delay(10000)
    end
end

local imei = info.imei() or "unknown"
local client_id = "nt26-" .. imei
topic = "nt26/" .. imei .. "/echo"

local client, err = mqtt.create(on_mqtt, {
    host = HOST,
    port = PORT,
    client_id = client_id,
    tls_enable = true,
    tls_seclevel = (TLS_AUTH == 1) and mqtt.TLS_SERVER_AUTH or mqtt.TLS_INSECURE,
    ca_cert = (TLS_AUTH == 1) and CA_PEM or nil,
    keepalive_interval = 60,
    clean_session = true,
    reconnect_interval_ms = 5000,
    connect_timeout_ms = 10000,
})
if not client then
    log.error("mqtts create fail %s", err or "create failed")
    while true do
        rt.delay(10000)
    end
end
c = client

c:auto_sub({ { topic = topic, qos = 0 } })

local ok, why = c:open()
log.info("mqtts open ok=%s err=%s host=%s port=%d", tostring(ok), tostring(why), HOST, PORT)

while true do
    rt.delay(10000)
end
