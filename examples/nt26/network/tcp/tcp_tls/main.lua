--[=[
  tcp tls demo — 长连接测试服务器，TLS 握手后发一行 hello
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 tcp tls」后空转
    2) create：tls_enable = true。TLS_AUTH = 1 单向认证，= 0 只加密不校验证书
    3) open 后 wait_connect。连上只表示 TCP 和 TLS 都完成了
    4) 每次 connected 用 send_async 发一行 hello。回调里不要用同步 send
    5) data 回调打印解密后的数据。不要 close：目标保持「要连上」，对端断开后内部自己重连

    换服务器时改 HOST / PORT，单向认证还要换成那台服务器自己的证书。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local tcp = require("tcp")

-- 如果要测试证书，把 SERVER_CA 改成证书内容，TLS_AUTH 改成 1。
local SERVER_CA = [[-----BEGIN CERTIFICATE-----
..............................
-----END CERTIFICATE-----
]]

-- 改这一处。1 = 单向认证（带下面的 CA），0 = 只加密、不校验证书。
local TLS_AUTH = 1
local HOST = "xxx.xxx.xxx.xxx" -- 服务器地址
local PORT = 123 -- 服务器端口
local LINK_WAIT_MS = 60 * 1000
local REQ = "hello tls\r\n"

local c
local sent = false

local function preview(data)
    if not data then
        return ""
    end
    if #data > 256 then
        return string.sub(data, 1, 256) .. "..."
    end
    return data
end

local function on_tcp(ev)
    if ev.event == "connected" then
        log.info("event connected ip=%s port=%s", ev.ip, ev.port)
        if c and not sent then
            local ok, err = c:send_async(REQ)
            log.info("send_async ok=%s err=%s", ok, err)
            if ok then
                sent = true
            end
        end
    elseif ev.event == "disconnected" then
        log.info("event disconnected")
        sent = false
    elseif ev.event == "error" then
        log.warn("event error code=%s", ev.code)
    elseif ev.event == "data" then
        log.info("event data n=%d", ev.data and #ev.data or 0)
        log.info("event data=\n%s", preview(ev.data))
    end
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 tcp tls")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start tcp tls auth=%d", TLS_AUTH)

local cfg = {
    reconnect_interval_ms = 5000,
    connect_timeout_ms = 5000,
    recv_buffer_size = 4096,
    tls_enable = true,
    tls_ignore_time = true,
}
if TLS_AUTH == 1 then
    cfg.tls_seclevel = tcp.TLS_SERVER_AUTH
    cfg.ca_cert = SERVER_CA
else
    cfg.tls_seclevel = tcp.TLS_INSECURE
end

log.info("---- create ----")
local err
c, err = tcp.create(on_tcp, cfg)
if not c then
    log.error("create fail err=%s", err)
    while true do
        rt.delay(10000)
    end
end
log.info("create ok seclevel=%s", cfg.tls_seclevel)

log.info("---- open ----")
local ok, oerr = c:open(HOST, PORT)
log.info("open %s:%d ok=%s err=%s", HOST, PORT, ok, oerr)
if not ok then
    while true do
        rt.delay(10000)
    end
end

log.info("---- wait_connect ----")
local ready = c:wait_connect(30000)
log.info("wait_connect ready=%s status=%s", ready, c:status())

while true do
    log.info("status connected=%s", c:status())
    rt.delay(10000)
end
