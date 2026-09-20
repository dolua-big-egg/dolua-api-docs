-- ============================================================================
-- sms_forward.lua — 纯 NT26 Lua 短信转发器
--
-- 功能：
--   1. 监听新短信（sms.reg 回调，无需 AT 指令 / 串口解析）
--   2. 黑名单过滤
--   3. 多通道推送：
--      BARK / 钉钉 / 飞书 / Gotify / Telegram / custom_post /
--      pushdeer / wecom / pushover / inotify / next-smtp-proxy
--   4. 转发短信到指定手机号（sms.send）
--   5. 配置只来自 config.lua 模块；改完后与主脚本一同烧录生效
--      （可用上位机改 config.lua，不要改本文件结构）
--
-- 已知限制（NT26 Lua 环境）：
--   * HTTP / HTTPS 推送一律走 Lua http 模块（钉钉/飞书/Telegram/PushDeer/Bark/
--     企微/Pushover/inotify 及明文 http webhook）。https 使用 TLS_INSECURE：
--     加密但不校验证书（各通道证书链不同，demo 不内嵌 CA）。
--   * tls 提供 HMAC-SHA256 与 base64 → 钉钉/飞书"加签"机器人可在 Lua 层完成签名。
--   * 通道字段：url / key（主密钥）/ key2（可选第二值）/ customBody / priority；
--     next-smtp-proxy 等多字段通道在 key 内用 "|" 分隔承载（user|password|host|port|to|subject）。
-- ============================================================================

-- ---- 模块引入（均为 NT26 固件内置，非外部库）----
local rt    = require("rt")
local sms   = require("sms")
local tls   = require("tls")    -- 哈希 / HMAC / base64（钉钉加签用）
local info  = require("info")
local lp    = require("lp")
local http  = require("http")   -- Lua HTTP/HTTPS 客户端

-- NT26 固件在运行期注入的全局对象：log（日志模块，提供 log.info）。
-- 静态分析工具（如 lua-language-server）无法识别运行期注入的全局，会误报
-- "未定义的全局变量 log"。此处显式捕获为局部变量以消告警；若环境未注入则回落 print。
local log = _G.log

-- ---- 安全日志（log.info 不做 %d 格式化，统一在此拼接）----
local function logi(tag, ...)
    local args = { ... }
    local parts = {}
    for i = 1, #args do parts[#parts + 1] = tostring(args[i]) end
    local msg = table.concat(parts, " ")
    if type(log) == "table" and type(log.info) == "function" then
        log.info(tag, msg)
    else
        print("[" .. tag .. "] " .. msg)
    end
end

-- ---- 推送类型 ----
local PUSH = {
    NONE = 0, BARK = 2, DINGTALK = 4, FEISHU = 8,
    GOTIFY = 9, TELEGRAM = 10,
    CUSTOM_POST = 11, PUSHDEER = 12, WECOM = 13, PUSHOVER = 14,
    INOTIFY = 15, NEXT_SMTP_PROXY = 16,
}

-- 最多同时启用/配置的独立推送通道数
local MAX_PUSH_CHANNELS = 16

-- 单通道发送失败时的重试次数
local PUSH_RETRY = 2

-- 类型码 <-> 可读名称 映射（用于日志）
local PUSH_NAME = {
    [PUSH.NONE]      = "NONE",
    [PUSH.BARK]      = "BARK",
    [PUSH.DINGTALK]  = "DINGTALK",
    [PUSH.FEISHU]    = "FEISHU",
    [PUSH.GOTIFY]    = "GOTIFY",
    [PUSH.TELEGRAM]  = "TELEGRAM",
    [PUSH.CUSTOM_POST] = "CUSTOM_POST",
    [PUSH.PUSHDEER]  = "PUSHDEER",
    [PUSH.WECOM]     = "WECOM",
    [PUSH.PUSHOVER]  = "PUSHOVER",
    [PUSH.INOTIFY]   = "INOTIFY",
    [PUSH.NEXT_SMTP_PROXY] = "NEXT_SMTP_PROXY",
}

-- ============================================================================
-- 配置：只来自独立模块 config.lua（require），改完重新烧录生效。
-- ============================================================================

-- 通道归一化：强制 MAX_PUSH_CHANNELS 上限、补齐缺省字段。
local function normalize_channels(t)
    t = t or {}
    local list = t.pushChannels
    if type(list) ~= "table" then list = {} end
    if #list > MAX_PUSH_CHANNELS then
        local trimmed = {}
        for i = 1, MAX_PUSH_CHANNELS do trimmed[i] = list[i] end
        list = trimmed
        logi("cfg", "推送通道超过 " .. MAX_PUSH_CHANNELS .. " 个，已截断")
    end
    for i, c in ipairs(list) do
        list[i] = {
            enabled    = (c.enabled == true),
            type       = c.type or PUSH.NONE,
            name       = c.name or "",
            url        = c.url or "",
            key        = c.key or "",
            key2       = c.key2 or "",
            customBody = c.customBody or "",
            priority   = tonumber(c.priority) or 0,
        }
    end
    t.pushChannels = list
    return t
end

local function load_cfg()
    local ok, m = pcall(require, "config")
    if not (ok and type(m) == "table") then
        logi("cfg", "未找到 config.lua，使用空配置")
        m = {
            adminPhone    = "",
            forwardPhones = {},
            blacklist     = {},
            email         = {},
            pushChannels  = {},
        }
    else
        logi("cfg", "已从 config.lua 载入配置")
    end
    local phones, black, chs = {}, {}, {}
    for i, p in ipairs(m.forwardPhones or {}) do phones[i] = p end
    for i, p in ipairs(m.blacklist or {}) do black[i] = p end
    for i, c in ipairs(m.pushChannels or {}) do chs[i] = c end
    return normalize_channels({
        adminPhone    = m.adminPhone or "",
        forwardPhones = phones,
        blacklist     = black,
        email         = m.email or {},
        pushChannels  = chs,
    })
end

local cfg = load_cfg()

-- ============================================================================
-- 工具函数
-- ============================================================================
-- 去除 +86 / 86 前缀，便于号码比较（模块报上来的号码常带裸 86）
local function norm_num(s)
    s = tostring(s or "")
    if s:sub(1, 3) == "+86" then s = s:sub(4) end
    if s:sub(1, 2) == "86" and #s > 11 then s = s:sub(3) end
    return s
end

-- 判断号码是否在某张列表里（支持 +86 比对）
local function in_list(list, num)
    local n = norm_num(num)
    for _, v in ipairs(list or {}) do
        if norm_num(v) == n then return true end
    end
    return false
end

-- 按分隔符拆分一行字段（next-smtp-proxy 的 key 用 "|" 分隔）
local function split_fields(text, sep)
    sep = sep or " "
    local res, i, n = {}, 1, #text
    while i <= n do
        local j = text:find(sep, i, true)
        if j then
            res[#res + 1] = text:sub(i, j - 1)
            i = j + #sep
        else
            res[#res + 1] = text:sub(i)
            break
        end
    end
    return res
end

-- 当前时间戳 YYYY-MM-DD HH:MM:SS
local function get_timestamp()
    local t = info.time()
    if not t then return "" end
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
        t.year or 0, t.month or 0, t.day or 0,
        t.hour or 0, t.minute or 0, t.second or 0)
end

-- ============================================================================
-- 时间同步（NTP）
-- NT26 不会自动校时；钉钉/飞书加签、以及 60s 去重都依赖准确时间，
-- 故在启动及签名前确保已同步。
-- ============================================================================
local TIME_VALID_THRESHOLD_MS = 1714500000000  -- 2024-05-01 之前视为未同步
local time_synced = false

local function sync_time()
    local ok, t = pcall(function() return info.ntp("ntp1.aliyun.com") end)
    if ok and type(t) == "string" and #t > 0 then
        logi("time", "NTP 校时成功: " .. t)
        time_synced = true
        return true
    end
    logi("time", "NTP 校时失败: " .. tostring(t))
    return false
end

-- 需要准确时间前调用：若尚未同步或时间异常，则尝试 NTP 同步一次
local function ensure_time_synced()
    local ok, ts = pcall(info.timestamp_ms)
    if ok and type(ts) == "number" and ts > TIME_VALID_THRESHOLD_MS then
        time_synced = true
        return true
    end
    return sync_time()
end

-- URL 编码
local function url_encode(s)
    s = tostring(s or "")
    local r = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = c:byte()
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
            or c == "-" or c == "_" or c == "." or c == "~" then
            r[#r + 1] = c
        elseif c == " " then
            r[#r + 1] = "+"
        else
            r[#r + 1] = string.format("%%%02X", b)
        end
    end
    return table.concat(r)
end

-- JSON 字符串转义
local function json_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

-- ============================================================================
-- 日志脱敏（隐私/安全）：避免短信正文与 webhook token 落入持久日志
-- ============================================================================
-- 隐藏 URL 中的敏感查询参数（access_token/key/secret/token/sendkey/password）
-- 及路径中的长令牌段（如 /<SENDKEY>.send、/KEY）
local function redact_url(u)
    u = tostring(u or "")
    u = u:gsub("([?&])([%w_]+)=([^&#]*)", function(sep, key, val)
        if key:lower():find("token") or key:lower() == "key"
            or key:lower() == "secret" or key:lower() == "password"
            or key:lower() == "sendkey" then
            return sep .. key .. "=***"
        end
        return sep .. key .. "=" .. val
    end)
    u = u:gsub("/(%w%w%w%w%w%w%w%w%w%w%w%w%w%w+)", "/***")
    return u
end

-- 隐藏短信正文：仅保留首尾各 3 字与长度，避免隐私泄露到日志
local function mask_sms(s)
    s = tostring(s or "")
    if #s <= 6 then return s end
    return s:sub(1, 3) .. "***(" .. #s .. "字)***" .. s:sub(-3)
end

-- ============================================================================
-- HTTP/HTTPS 请求（Lua http 模块）
-- https:// 必须带 tls_mode；明文 http:// 也带 TLS_INSECURE（与官方 demo 一致）。
-- HTTPS 不校验证书（各通道证书链不同，demo 不内嵌 CA）。
-- 调用会占住当前协程及整条 Lua 引擎线程直到返回，必须在 worker 里发，不能在 sms 回调里发。
-- 返回 ok(bool), status(string), body(string|nil)
-- ============================================================================
local function http_request(method, url, content_type, body)
    method = method or "POST"
    body = body or ""
    local opts = {
        tls_mode = http.TLS_INSECURE,
        timeout_s = 30,
        timeout_r = 30,
        max_response_size = 8192,
        headers = { ["User-Agent"] = "NT26-SMS-Forward/1.0" },
    }
    if method ~= "GET" then
        opts.content_type = content_type or "application/json"
    end

    local resp, err, msg
    if method == "GET" then
        resp, err, msg = http.get(url, opts)
    else
        resp, err, msg = http.post(url, body, opts)
    end
    if not resp then
        logi("push", "HTTP " .. method .. " 失败 " .. redact_url(url)
            .. " err=" .. tostring(err) .. " msg=" .. tostring(msg))
        return false, tostring(msg or err or "http_fail"), nil
    end
    local code = tostring(resp.status_code or "")
    local n = tonumber(code)
    logi("push", "HTTP " .. method .. " " .. redact_url(url) .. " -> " .. code)
    if n and n >= 200 and n < 300 then
        return true, code, resp.body
    end
    logi("push", "HTTP 非 2xx status=" .. code
        .. " body=" .. tostring(resp.body))
    return false, code, resp.body
end

-- POST（默认 JSON；需表单编码时传 "application/x-www-form-urlencoded"）
local function http_post(url, body, content_type)
    return http_request("POST", url, content_type, body)
end

-- GET（inotify 等 GET 型 webhook 使用）
local function http_get(url)
    return http_request("GET", url, nil, "")
end

-- ============================================================================
-- HMAC-SHA256 二进制摘要（兼容不同固件 raw 参数语义）
-- 钉钉加签需要的是「原始 32 字节摘要」的 base64，而非 hex 文本。
-- 不同固件 raw=true/false 返回 hex 或 binary 不一致，这里统一归一成二进制串。
-- 返回 32 字节二进制串，失败返回 nil
-- ============================================================================
local function hmac_sha256_binary(key, data)
    -- 优先 raw=true（多数固件期望返回二进制）
    local r = tls.hmac_sha256(key, data, true)
    if type(r) == "string" and #r == 32 then
        return r
    end
    -- 回落：取默认（hex 文本），再在 Lua 层转成二进制字节
    r = tls.hmac_sha256(key, data)
    if type(r) ~= "string" or #r ~= 64 then
        return nil
    end
    local bin = {}
    for i = 1, #r, 2 do
        bin[#bin + 1] = string.char(tonumber(r:sub(i, i + 1), 16))
    end
    return table.concat(bin)
end

-- ============================================================================
-- 单通道推送（按类型构造请求）
-- ============================================================================
local function send_to_channel(ch0, sender, message, timestamp)
    if not ch0 or not ch0.enabled then return end
    if ch0.type == PUSH.NONE then return end

    local name = (#(ch0.name or "") > 0) and ch0.name or (PUSH_NAME[ch0.type] or "?")

    -- 仅部分类型必须提供 URL（其余有内置默认地址：TELEGRAM/PUSHOVER 等）
    local need_url = (ch0.type == PUSH.BARK
        or ch0.type == PUSH.DINGTALK
        or ch0.type == PUSH.FEISHU
        or ch0.type == PUSH.CUSTOM_POST or ch0.type == PUSH.PUSHDEER
        or ch0.type == PUSH.WECOM or ch0.type == PUSH.INOTIFY
        or ch0.type == PUSH.NEXT_SMTP_PROXY or ch0.type == PUSH.GOTIFY)
    if need_url and (#(ch0.url or "") == 0) then
        logi("push", "通道[" .. name .. "] 缺少 URL，跳过")
        return
    end
    -- 配置性错误：直接跳过，不做网络重试
    if (ch0.type == PUSH.CUSTOM_POST)
        and #(ch0.customBody or "") == 0 then
        logi("push", "通道[" .. name .. "] 自定义模板为空，跳过")
        return
    end
    if not PUSH_NAME[ch0.type] then
        logi("push", "通道[" .. name .. "] 未知类型，跳过")
        return
    end

    local se = json_escape(sender)
    local me = json_escape(message)
    local te = json_escape(timestamp)
    -- URL 编码版本：表单模式(form)下必须用它替换值，否则 &/=/%/空格 会破坏表单
    local su = url_encode(sender)
    local mu = url_encode(message)
    local tu = url_encode(timestamp)

    -- 单次发送（不含重试）。返回 ok(bool), status(string)
    local function attempt()
        if ch0.type == PUSH.BARK then
            -- key=Bark 设备 Key；url 默认为 https://api.day.app
            local base = (#ch0.url > 0) and ch0.url or "https://api.day.app"
            base = base:gsub("/$", "")
            local url = base .. "/" .. (ch0.key or "")
            local data = "title=" .. url_encode("短信来自: " .. sender)
                .. "&body=" .. url_encode(message)
            return http_post(url, data, "application/x-www-form-urlencoded")

        elseif ch0.type == PUSH.DINGTALK then
            -- 钉钉自定义机器人（HTTPS + 可选加签）
            --   url  = Webhook（含 access_token）
            --   key2 = 加签 SEC 密钥（为空则按"未开启加签"发送）
            local sec = ch0.key2 or ""
            ensure_time_synced()
            local ts = string.format("%d", math.floor(info.timestamp_ms() or 0))
            local send_url = ch0.url or ""
            if #sec > 0 then
                -- 加签：sign = base64(HMAC-SHA256(SEC, timestamp + "\n" + SEC))
                local string_to_sign = ts .. "\n" .. sec
                local hmac_bin = hmac_sha256_binary(sec, string_to_sign)
                if not hmac_bin then
                    logi("push", "通道[" .. name .. "] 钉钉加签失败")
                    return false, "sign_fail"
                end
                local sign = tls.base64_encode(hmac_bin)
                local sep = send_url:find("?", 1, true) and "&" or "?"
                send_url = send_url .. sep .. "timestamp=" .. ts .. "&sign=" .. url_encode(sign)
            end
            local content = "📱短信通知\n发送者: " .. sender
                .. "\n内容: " .. message .. "\n时间: " .. timestamp
            local data = '{"msgtype":"text","text":{"content":"'
                .. json_escape(content) .. '"}}'
            local ok, status, resp = http_post(send_url, data)
            if ok then
                -- 钉钉 200 仍可能业务失败（errcode!=0），限流/时间失效需重试
                local ec = resp and resp:match('"errcode"%s*:%s*(-?%d+)')
                if ec and ec ~= "0" then
                    logi("push", "通道[" .. name .. "] 钉钉返回 errcode=" .. ec)
                    return false, "errcode:" .. ec
                end
                return true, status
            end
            return false, status

        elseif ch0.type == PUSH.FEISHU then
            -- 飞书自定义机器人（HTTPS + 可选加签）
            --   url  = Webhook（https://open.feishu.cn/open-apis/bot/v2/hook/xxx）
            --   key2 = 加签密钥（飞书开启"签名校验"时填写；为空表示未开启）
            local content = "📱短信通知\n发送者: " .. sender
                .. "\n内容: " .. message .. "\n时间: " .. timestamp
            local secret = ch0.key2 or ""
            local data
            if #secret > 0 then
                -- 加签：sign = base64(HMAC-SHA256(SEC, timestamp(秒) + "\n" + SEC))
                -- 飞书签名用秒级时间戳，且 timestamp/sign 放在 JSON body（非 URL 参数）
                ensure_time_synced()
                local ts_sec = tostring(math.floor((info.timestamp_ms() or 0) / 1000))
                local hmac_bin = hmac_sha256_binary(secret, ts_sec .. "\n" .. secret)
                if not hmac_bin then
                    logi("push", "通道[" .. name .. "] 飞书加签失败")
                    return false, "sign_fail"
                end
                local sign = tls.base64_encode(hmac_bin)
                data = '{"timestamp":"' .. ts_sec .. '","sign":"' .. json_escape(sign)
                    .. '","msg_type":"text","content":{"text":"' .. json_escape(content) .. '"}}'
            else
                data = '{"msg_type":"text","content":{"text":"'
                    .. json_escape(content) .. '"}}'
            end
            return http_post(ch0.url, data)

        elseif ch0.type == PUSH.GOTIFY then
            local url = ch0.url
            if not url:find("/$", 1, true) then url = url .. "/" end
            url = url .. "message?token=" .. ch0.key
            local data = '{"title":"短信来自: ' .. se .. '","message":"' .. me
                .. '\\n\\n时间: ' .. te .. '","priority":5}'
            return http_post(url, data, "application/json")

        elseif ch0.type == PUSH.TELEGRAM then
            -- key=chat_id, key2=bot_token
            local base = (#ch0.url > 0) and ch0.url or "https://api.telegram.org"
            base = base:gsub("/$", "")
            local url = base .. "/bot" .. (ch0.key2 or "") .. "/sendMessage"
            local data = '{"chat_id":"' .. json_escape(ch0.key or "") .. '","text":"短信通知 发送者:'
                .. se .. ' 内容:' .. me .. ' 时间:' .. te .. '"}'
            return http_post(url, data)

        elseif ch0.type == PUSH.CUSTOM_POST then
            -- 通用自定义 POST：customBody 模板支持 {sender}/{message}/{timestamp}
            --   JSON 模式用 {sender}/{message}/{timestamp}（json_escape）
            --   表单(form)模式务必用 {sender_u}/{message_u}/{timestamp_u}（url_encode），
            --   否则短信内容里的 &/=/%/空格 会破坏表单提交
            -- key="form" → 表单编码，否则 JSON
            local data = ch0.customBody
            data = data:gsub("{sender}", function() return se end)
            data = data:gsub("{message}", function() return me end)
            data = data:gsub("{timestamp}", function() return te end)
            data = data:gsub("{sender_u}", function() return su end)
            data = data:gsub("{message_u}", function() return mu end)
            data = data:gsub("{timestamp_u}", function() return tu end)
            local ct = "application/json"
            if (ch0.key or ""):lower() == "form" then
                ct = "application/x-www-form-urlencoded"
            end
            return http_post(ch0.url, data, ct)

        elseif ch0.type == PUSH.PUSHDEER then
            -- key=pushkey；url 默认 https://api2.pushdeer.com/message/push
            local url = ch0.url
            if not url:find("/$", 1, true) then url = url .. "/" end
            local data = "pushkey=" .. url_encode(ch0.key)
                .. "&type=text&text=" .. url_encode(message)
            return http_post(url, data, "application/x-www-form-urlencoded")

        elseif ch0.type == PUSH.WECOM then
            -- 企业微信机器人（HTTPS）。url=webhook；返回 errcode!=0 视为失败需重试
            local data = '{"msgtype":"text","text":{"content":"' .. json_escape(message) .. '"}}'
            local ok, status, resp = http_post(ch0.url, data)
            if ok then
                local ec = resp and resp:match('"errcode"%s*:%s*(-?%d+)')
                if ec and ec ~= "0" then
                    logi("push", "通道[" .. name .. "] 企微返回 errcode=" .. ec)
                    return false, "errcode:" .. ec
                end
                return true, status
            end
            return false, status

        elseif ch0.type == PUSH.PUSHOVER then
            -- key=API Token, key2=User Key；url 默认 https://api.pushover.net/1/messages.json
            local url = (#ch0.url > 0) and ch0.url or "https://api.pushover.net/1/messages.json"
            local data = '{"token":"' .. json_escape(ch0.key or "") .. '","user":"'
                .. json_escape(ch0.key2) .. '","message":"' .. me .. '"}'
            return http_post(url, data)

        elseif ch0.type == PUSH.INOTIFY then
            -- GET 型 webhook：url 须以 .send 结尾，消息作为路径段拼接
            local url = ch0.url
            if not url:match("%.send$") then
                logi("push", "通道[" .. name .. "] INOTIFY_API 必须以 .send 结尾，跳过")
                return false, "bad_url"
            end
            local u = url .. "/" .. url_encode(message)
            return http_get(u)

        elseif ch0.type == PUSH.NEXT_SMTP_PROXY then
            -- 邮件代理：key 内以 "|" 分隔 6 字段：
            --   user|password|smtp_host|smtp_port|to_email|subject；text=短信内容
            local p = split_fields(ch0.key or "", "|")
            local data = "user=" .. url_encode(p[1] or "")
                .. "&password=" .. url_encode(p[2] or "")
                .. "&host=" .. url_encode(p[3] or "")
                .. "&port=" .. url_encode(p[4] or "")
                .. "&to_email=" .. url_encode(p[5] or "")
                .. "&subject=" .. url_encode(p[6] or "")
                .. "&text=" .. url_encode(message)
            return http_post(ch0.url, data, "application/x-www-form-urlencoded")

        else
            return false, "unknown_type"
        end
    end

    -- 重试：最多 PUSH_RETRY 次（共 PUSH_RETRY+1 次尝试）
    local last_status = ""
    for i = 1, PUSH_RETRY + 1 do
        local ok, status = attempt()
        last_status = tostring(status or "")
        if ok then
            logi("push", "通道[" .. name .. "] 推送成功 (HTTP " .. last_status .. ")")
            return
        end
        if i <= PUSH_RETRY then
            logi("push", "通道[" .. name .. "] 第" .. i .. "次失败(" .. last_status .. ")，重试")
            rt.delay(500)
        end
    end
    logi("push", "通道[" .. name .. "] 推送失败，重试" .. PUSH_RETRY .. "次后仍失败: " .. last_status)
end

-- 遍历所有启用通道推送（按优先级从小到大，0 为最高）
local function push_all_channels(sender, message, timestamp)
    if not cfg.pushChannels or #cfg.pushChannels == 0 then
        logi("push", "未配置任何推送通道")
        return
    end
    -- 复制并排序，避免改动原配置顺序（priority 越小越先发送，0 为最高优先级）
    local list = {}
    for _, c in ipairs(cfg.pushChannels) do
        if c.enabled and c.type ~= PUSH.NONE then
            list[#list + 1] = c
        end
    end
    table.sort(list, function(a, b) return (a.priority or 0) < (b.priority or 0) end)

    for _, c in ipairs(list) do
        local ok, err = pcall(send_to_channel, c, sender, message, timestamp)
        if not ok then logi("push", "通道异常: " .. tostring(err)) end
        rt.delay(100)   -- 短暂延迟，避免请求过快
    end
end

-- ============================================================================
-- 转发短信到目标手机号（直接用 sms.send，无需 AT+SMS 槽位配置）
-- ============================================================================
local function forward_sms_to_phones(sender, message)
    if not cfg.forwardPhones or #cfg.forwardPhones == 0 then
        logi("fwd", "未配置转发目标手机号")
        return
    end
    -- 防止回环：来自转发号本身的短信不再二次转发
    if in_list(cfg.forwardPhones, sender) then
        logi("fwd", "来自转发号，跳过以避免回环: " .. sender)
        return
    end
    local header = "【短信转发】\n来自号码：" .. tostring(sender) .. "\n"
    local body = tostring(message):gsub("\r", ""):gsub("\n", "")
    local forward_msg = header .. body
    if #forward_msg == 0 then return end

    local sent, fail = 0, 0
    for _, phone in ipairs(cfg.forwardPhones) do
        local ret = sms.send(tostring(phone), forward_msg, 30000)
        if ret == 0 or ret == sms.ERR_OK then
            logi("fwd", "转发成功 -> " .. tostring(phone))
            sent = sent + 1
        else
            logi("fwd", "转发失败 -> " .. tostring(phone) .. " code=" .. tostring(ret))
            fail = fail + 1
        end
    end
    logi("fwd", "短信转发完成: 成功 " .. sent .. "/" .. (sent + fail))
end

-- ============================================================================
-- 短信处理（去重 + 黑名单 + 推送 + 转发）
-- ============================================================================
local g_last_key = ""
local g_last_ts  = 0

local function process_sms_content(sender, text, timestamp)
    -- 去重：60 秒内相同 发送者+内容 不重复处理
    local key = sender .. "|" .. text:sub(1, 48)
    local now = 0
    local ok, v = pcall(info.timestamp_ms)
    if ok and type(v) == "number" then now = v end
    if key == g_last_key and (now - g_last_ts) < 60000 then
        logi("sms", "重复短信，跳过")
        return
    end
    g_last_key = key
    g_last_ts = now

    logi("sms", "处理短信 from=" .. sender .. " text=" .. mask_sms(text))

    if in_list(cfg.blacklist, sender) then
        logi("sms", "黑名单号码，忽略: " .. sender)
        return
    end

    push_all_channels(sender, text, timestamp)
    forward_sms_to_phones(sender, text)
end

-- ============================================================================
-- 队列 + 工作线程（保证 sms 回调轻量，不在回调里做阻塞/网络操作）
-- ============================================================================
local queue = {}

local function worker()
    while true do
        while #queue > 0 do
            local item = table.remove(queue, 1)
            local ok, err = pcall(process_sms_content, item.sender, item.text, item.timestamp)
            if not ok then logi("worker", "处理异常: " .. tostring(err)) end
        end
        rt.delay(300)
    end
end

-- ============================================================================
-- 启动
-- ============================================================================
logi("init", "=== NT26 短信转发器启动 ===")
if lp.wait_link(120000) then
    logi("init", "驻网成功")
else
    logi("init", "驻网超时，仍继续（网络恢复后自动生效）")
end

-- 启动即校时，保证后续加签/去重时间准确
sync_time()

sms.reg(function(ev)
    if ev and ev.event_id == sms.EVENT_NEW_SMS then
        queue[#queue + 1] = {
            sender    = ev.sender or "",
            text      = ev.text or "",
            timestamp = get_timestamp(),
        }
    elseif ev and ev.event_id == sms.EVENT_SEND_DONE then
        logi("sms", "发送完成 tag=" .. tostring(ev.user_tag))
    elseif ev and ev.event_id == sms.EVENT_SEND_FAILED then
        logi("sms", "发送失败 tag=" .. tostring(ev.user_tag))
    end
end)

rt.task_start(worker)

-- 启动通知：adminPhone 有号码则发一条开机短信（不是远程指令）
if cfg.adminPhone and #cfg.adminPhone > 0 then
    sms.send(cfg.adminPhone, "短信转发器已启动", 30000)
end

logi("init", "就绪。改配置请编辑 config.lua 后重新烧录")

-- 主循环（NT26 协程模型要求脚本必须含主循环）
while true do
    rt.delay(1000)
end
