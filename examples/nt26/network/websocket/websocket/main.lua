--[[
Author: BURIBURI ZAEMON 59598825+liam-so-sad@users.noreply.github.com
Date: 2026-10-19 10:11:50
LastEditors: BURIBURI ZAEMON 59598825+liam-so-sad@users.noreply.github.com
LastEditTime: 2026-10-19 17:16:08
FilePath: \PLAT\dolua\examples\nt26\network\websocket\websocket\main.lua
Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
--]]
--[=[
  websocket — 长连接 WebSocket 回声
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印后空转
    2) create：wss，TLS_AUTH = 0 只加密不校验证书
    3) open 后由内部完成 TCP、TLS 和 HTTP 升级。connected 才表示可以发数据
    4) 每次 connected 用 send_async 发一行 hello ws。回调里不要用同步 send
    5) data 打印回声。不要 close：目标保持「要连上」，断开后内部自己重连并重新升级

    换服务器时改 HOST / PORT / PATH。这台公共回声的证书是 RSA。
    单向认证把 TLS_AUTH 改成 1，并填那台服务器的 CA。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local websocket = require("websocket")

-- 1 = 单向认证，0 = 只加密不校验证书
local TLS_AUTH = 0
local HOST = "echo.websocket.org"
local PORT = 443
local PATH = "/"

local sent = false

local function on_ws(ev)
    if ev.event == "connected" then
        log.info("ws up")
        if not sent then
            sent = true
            ev.client:send_async("hello ws")
        end
    elseif ev.event == "data" then
        log.info("ws echo opcode=%d data=%s", ev.opcode, ev.data)
    elseif ev.event == "disconnected" then
        sent = false
        log.warn("ws down")
    elseif ev.event == "error" then
        log.warn("ws err code=%d", ev.code)
    end
end

if not lp.wait_link(60000) then
    print("网络超时，没有网络无法测试 websocket")
    while true do
        rt.delay(10000)
    end
end

local cfg = {
    host = HOST,
    port = PORT,
    path = PATH,
    tls_enable = true,
    tls_seclevel = (TLS_AUTH == 1) and websocket.TLS_SERVER_AUTH or websocket.TLS_INSECURE,
    tls_ignore_time = true,
}
local c, err = websocket.create(on_ws, cfg)
if not c then
    log.error("ws create fail %s", err or "create failed")
    while true do
        rt.delay(10000)
    end
end
local ok, why = c:open()
log.info("ws open ok=%s err=%s", ok, why)

while true do
    rt.delay(10000)
end
