--[=[
  smtp_implicit — 隐式 TLS 发纯文本邮件
  ============================================================================
  tls = smtp.TLS_IMPLICIT：TCP 连上即 TLS（SMTPS）。不传 port 时默认 465。
  发完一封后等 60 秒，再重复。

  下面 HOST / FROM / TO / AUTH_CODE 先空着，填好再烧录。
  授权码是邮箱客户端授权码，不是网页登录密码。

  若发件是 QQ 邮箱：请改用 smtp_starttls 工程（tls = smtp.TLS_STARTTLS）。
  STARTTLS（默认 587）可以发给 QQ，也是 QQ SMTP 的推荐写法；本例是 465 隐式 TLS。

  正文按底层限制打到 8192 字节（含中文 UTF-8）。
]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local smtp = require("smtp")

-- SMTP 主机名。隐式 TLS 常见：smtp.163.com、等。
-- 不要带 http:// 或端口号。不传 port 时默认 465。
-- QQ 邮箱请用 smtp_starttls（smtp.qq.com + TLS_STARTTLS），不要走本例。
local HOST = ""

-- 发件邮箱，必须写完整地址（如 xxx@163.com），且与下面授权码是同一个账号。
local FROM = ""

-- 收件邮箱，完整地址。可与发件相同，也可发给其它邮箱。
local TO = ""

local SUBJECT = "【设备通知】NT26 SMTP 8KB 正文测试"
local BODY_MAX = 8 * 1024

local function make_body(target)
    local head = table.concat({
        "您好：",
        "",
        "这是一封由 NT26 设备自动发出的长正文测试邮件。",
        "底层限制 body 不超过 8192 字节（UTF-8），本信按该上限填满。",
        "",
        "发件账号：" .. FROM,
        "收件账号：" .. TO,
        "发送通道：" .. HOST .. "（TLS_IMPLICIT，默认 465）",
        "",
        "若您并未发起本次测试，请忽略本邮件。",
        "",
        "---- 以下为长度填充 ----",
        "",
    }, "\n")
    local parts = { head }
    local n = #head
    local i = 1
    local line_fmt = "第%04d行 NT26 SMTP 长正文测试 中文填充 ABCDEFG 0123456789\n"
    while true do
        local line = string.format(line_fmt, i)
        if n + #line > target then
            break
        end
        parts[#parts + 1] = line
        n = n + #line
        i = i + 1
    end
    if n < target then
        parts[#parts + 1] = string.rep("X", target - n)
    end
    return table.concat(parts)
end

-- 客户端授权码，不是网页登录密码。
-- 163：设置 → POP3/SMTP/IMAP → 开启并生成授权码。
-- 企业邮：一般用邮箱登录密码（以服务商说明为准）。
local AUTH_CODE = ""

local CONNECT_TIMEOUT_S = 8
local CMD_TIMEOUT_S = 5
local RETRY = 2
local LOOP_MS = 60 * 1000

local LINK_WAIT_MS = 60 * 1000

local function send_once()
    local body = make_body(BODY_MAX)
    log.info("smtp implicit send from=%s to=%s body=%d", FROM, TO, #body)
    local ok, err, msg = smtp.send({
        host = HOST,
        tls = smtp.TLS_IMPLICIT,
        auth_plain = true,
        user = FROM,
        password = AUTH_CODE,
        from = FROM,
        to = TO,
        subject = SUBJECT,
        body = body,
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
    log.error("请先在 main.lua 填写 HOST / FROM / TO / AUTH_CODE")
    while true do
        rt.delay(10000)
    end
end

while true do
    send_once()
    log.info("next round in %d ms", LOOP_MS)
    rt.delay(LOOP_MS)
end
