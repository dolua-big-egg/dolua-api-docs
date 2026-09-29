--[=[
  smtp_starttls — STARTTLS 发纯文本邮件
  ============================================================================
  tls = smtp.TLS_STARTTLS：TCP 先明文读 220、EHLO，再发 STARTTLS 升级成 TLS。
  不传 port 时默认 587（不要填 465，那是隐式 TLS）。

  【QQ 邮箱】本方式可以发给 QQ，也是 QQ SMTP 的推荐写法。
  服务器填 smtp.qq.com，用邮箱生成的 16 位授权码，不要用 QQ 登录密码。
  发件人必须是开通了 SMTP 的那个 QQ 邮箱；收件人可以是 QQ，也可以是其它邮箱。

  下面 HOST / FROM / TO / AUTH_CODE 先空着，填好再烧录。
  发完一封后等 60 秒，再重复。
]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local smtp = require("smtp")

-- SMTP 主机名。QQ 邮箱填 "smtp.qq.com"（STARTTLS 目前可以发给 QQ）。
-- 其它常见：smtp.163.com、smtp.exmail.qq.com。不要带 http:// 或端口号。
local HOST = ""

-- 发件邮箱，必须写完整地址（如 xxx@qq.com），且与下面授权码是同一个账号。
-- QQ：设置 → 账号与安全 → 先开启 SMTP 服务，再用这个邮箱发。
local FROM = ""

-- 收件邮箱，完整地址。可以发给自己的 QQ，也可以发给其它邮箱。
local TO = ""

local SUBJECT = "NT26 SMTP STARTTLS 测试"
local BODY = "这是一封由 NT26 设备通过 STARTTLS 发出的测试邮件。"

-- SMTP 授权码，不是网页登录密码。
-- QQ：设置 → 账号与安全 → 开启 SMTP 服务 → 生成授权码（一般 16 位）。
-- 163：设置 → POP3/SMTP/IMAP → 客户端授权码。
local AUTH_CODE = ""

local CONNECT_TIMEOUT_S = 8
local CMD_TIMEOUT_S = 5
local RETRY = 2
local LOOP_MS = 60 * 1000

local LINK_WAIT_MS = 60 * 1000

local function send_once()
    log.info("smtp starttls send from=%s to=%s", FROM, TO)
    local ok, err, msg = smtp.send({
        host = HOST,
        tls = smtp.TLS_STARTTLS,
        auth_plain = true,
        user = FROM,
        password = AUTH_CODE,
        from = FROM,
        to = TO,
        subject = SUBJECT,
        body = BODY,
        connect_timeout_s = CONNECT_TIMEOUT_S,
        cmd_timeout_s = CMD_TIMEOUT_S,
        retry = RETRY,
    })
    if not ok then
        log.error("send fail err=%s msg=%s", tostring(err), tostring(msg))
    else
        log.info("send ok")
    end
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法发信")
    while true do
        rt.delay(10000)
    end
end

if HOST == "" or FROM == "" or TO == "" or AUTH_CODE == "" then
    log.error("请先在 main.lua 填写 HOST / FROM / TO / AUTH_CODE（QQ 用 smtp.qq.com + SMTP 授权码）")
    while true do
        rt.delay(10000)
    end
end

while true do
    send_once()
    log.info("next round in %d ms", LOOP_MS)
    rt.delay(LOOP_MS)
end
