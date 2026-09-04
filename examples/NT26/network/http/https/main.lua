--[=[
  https 单向认证 demo — 先等网络，再用 TLS_SERVER_AUTH 访问 httpbin
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 https」后空转
    2) http.get https://httpbin.org/get
       tls_mode = TLS_SERVER_AUTH，ca_cert = Amazon Root CA 1
    3) 打印 status 和 body；然后空转

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local http = require("http")

-- Amazon Root CA 1，用来校验 httpbin.org 当前这条 Amazon 证书链。
-- 来源：https://www.amazontrust.com/repository/AmazonRootCA1.pem
local AMAZON_ROOT_CA1 = [[-----BEGIN CERTIFICATE-----
MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmljZbyjANBgkqhkiG9w0BAQsF
ADA5MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6
b24gUm9vdCBDQSAxMB4XDTE1MDUyNjAwMDAwMFoXDTM4MDExNzAwMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJ4gHHKeNXj
ca9HgFB0fW7Y14h29Jlo91ghYPl0hAEvrAIthtOgQ3pOsqTQNroBvo3bSMgHFzZM
9O6II8c+6zf1tRn4SWiw3te5djgdYZ6k/oI2peVKVuRF4fn9tBb6dNqcmzU5L/qw
IFAGbHrQgLKm+a/sRxmPUDgH3KKHOVj4utWp+UhnMJbulHheb4mjUcAwhmahRWa6
VOujw5H5SNz/0egwLX0tdHA114gk957EWW67c4cX8jJGKLhD+rcdqsq08p8kDi1L
93FcXmn/6pUCyziKrlA4b9v7LWIbxcceVOF34GfID5yHI9Y/QCB/IIDEgEw+OyQm
jgSubJrIqg0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0OBBYEFIQYzIU07LwMlJQuCFmcx7IQTgoIMA0GCSqGSIb3DQEBCwUA
A4IBAQCY8jdaQZChGsV2USggNiMOruYou6r4lK5IpDB/G/wkjUu0yKGX9rbxenDI
U5PMCCjjmCXPI6T53iHTfIUJrU6adTrCC2qJeHZERxhlbI1Bjjt/msv0tadQ1wUs
N+gDS63pYaACbvXy8MWy7Vu33PqUXHeeE6V/Uq2V8viTO96LXFvKWlJbYK8U90vv
o/ufQJVtMVT8QtPHRh8jrdkPSHCa2XV4cdFyQzR1bldZwgJcJmApzyMZFo6IQ6XU
5MsI+yMRQ+hDKXJioaldXgjUkK642M4UwtBV8ob2xJNDd2ZhwLnoQdeXeGADbkpy
rqXRfboQnoZsG4q5WTP468SQvvG5
-----END CERTIFICATE-----
]]

local URL = "https://httpbin.org/get"
local LINK_WAIT_MS = 60 * 1000

local function dump_resp(tag, resp)
    local body = resp.body or ""
    local preview = body
    if #preview > 256 then
        preview = string.sub(preview, 1, 256) .. "..."
    end
    log.info("%s protocol=%s status=%s %s",
             tag, resp.protocol_version, resp.status_code, resp.status_desc)
    log.info("%s header_len=%s body_len=%s", tag, resp.header_len, resp.body_len)
    log.info("%s body=\n%s", tag, preview)
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 https")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start https server-auth")

log.info("---- GET TLS_SERVER_AUTH ----")
-- 单向认证：校验服务端是不是 Amazon 这条链签出来的。不带 ca_cert 会直接失败。
-- 和 TLS_INSECURE 一样走 https，差别只是会验证书。
local resp, err, msg = http.get(URL, {
    tls_mode = http.TLS_SERVER_AUTH,
    ca_cert = AMAZON_ROOT_CA1,
})
if not resp then
    log.error("GET fail err=%s msg=%s", err, msg)
else
    dump_resp("GET", resp)
end

log.info("---- done ----")
while true do
    rt.delay(10000)
end

--[=[
  https 单向认证 demo — 先等网络，再用 TLS_SERVER_AUTH 访问 httpbin

  http 是独立模块：require("http")。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停。

  和 http_request 那个 demo 的差别：
    TLS_INSECURE     加密，不校验服务端证书，不用 CA
    TLS_SERVER_AUTH  加密，并且用 ca_cert 校验服务端（单向认证）
    TLS_MUTUAL_AUTH  还要再带客户端证书和私钥，本 demo 不用

  单向认证必须带 ca_cert，否则 request 会直接失败（tls configure failed）。
  ca_cert 填 PEM 文本。要校验哪家站点，就放那条证书链对应的根 CA（或中间 CA）。
  换 URL 通常就要换 CA，不能拿 Amazon 的根去验别的品牌站点。

  本 demo 访问 https://httpbin.org/get。
  当前证书链：httpbin.org ← Amazon RSA 2048 M01 ← Amazon Root CA 1
  所以嵌入 Amazon Root CA 1（官方：https://www.amazontrust.com/repository/AmazonRootCA1.pem）。
  有效期到 2038-01-17。站点以后换链的话，要把 CA 换成新链的根。

  httpbin 响应比较慢是正常的。

  ----------------------------------------------------------------------------
  https 相关 opts（叠在 http.request / http.get 上）
  ----------------------------------------------------------------------------
    tls_mode     http.TLS_SERVER_AUTH   单向认证，必须再带 ca_cert
    ca_cert      PEM 字符串。ca_cert_len 可不写，底层按字符串长度处理
    tls_sni      默认 true。多域名证书站点（httpbin 就是）必须开
    tls_ignore_time  默认 true，忽略证书有效期（设备没校时也能连）
                     校过时以后若要连有效期一起验，再改成 false

    成功 / 失败返回值和 http.request 相同，见 http_request demo。
    调用返回前当前协程被占住。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 https」后空转
    2) http.get https://httpbin.org/get
       tls_mode = TLS_SERVER_AUTH，ca_cert = Amazon Root CA 1
    3) 打印 status 和 body；然后空转

  ----------------------------------------------------------------------------
  预期结果
  ----------------------------------------------------------------------------
  注意这个测试网站响应特别慢，因为服务器在国外，所以慢是正常的，你可以换成自己的服务器。

  [2026-08-21 15:13:57.358]# RECV ASCII>
  [Lua][INFO][main][(main):89] wait_link 60000 ms
  [Lua][INFO][main][(main):97] network ok, start https server-auth
  [Lua][INFO][main][(main):99] ---- GET TLS_SERVER_AUTH ----

  [2026-08-21 15:14:27.499]# RECV ASCII>
  [Lua][INFO][dump_resp][(main):83] GET protocol=HTTP/1.1 status=200 OK
  [Lua][INFO][dump_resp][(main):85] GET header_len=211 body_len=227
  [Lua][INFO][dump_resp][(main):86] GET body=
  {
    "args": {},
    "headers": {
      "Content-Length": "0",
      "Host": "httpbin.org",
      "X-Amzn-Trace-Id": "Root=1-6a87fab7-2717ce52740e77a4745f569e"
    },
    "origin": "39.144.144.35",
    "url": "https://httpbin.org/get"
  }

  [Lua][INFO][main][(main):112] ---- done ----

]=]
