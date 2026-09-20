-- ============================================================================
-- config.lua — NT26 短信转发器 用户配置文件（独立文件，由上位机 exe 自动改写）
-- ----------------------------------------------------------------------------
-- 本文件 ONLY 包含用户需要修改的配置：管理员号码、转发号码、黑名单、推送通道。
--
-- 运行时规则（重要）：
--   * 运行时配置就是本文件 return 的表，由 sms_forward.lua require("config") 载入。
--   * 改完本文件后（可用上位机），与 sms_forward.lua 一同重新烧录即可生效。
--
-- 推送类型常量（值与 sms_forward.lua 必须保持一致）：
--   仅支持以下 11 种：BARK=2 DINGTALK=4 FEISHU=8 GOTIFY=9 TELEGRAM=10
--   CUSTOM_POST=11 PUSHDEER=12 WECOM=13 PUSHOVER=14 INOTIFY=15 NEXT_SMTP_PROXY=16
-- ============================================================================

local PUSH = {
    NONE = 0,
    BARK = 2, DINGTALK = 4, FEISHU = 8, GOTIFY = 9, TELEGRAM = 10,
    CUSTOM_POST = 11, PUSHDEER = 12, WECOM = 13, PUSHOVER = 14,
    INOTIFY = 15, NEXT_SMTP_PROXY = 16,
}

-- 构造单条推送通道的便捷函数（字段含义见下方逐条说明）
--   enabled    : 是否启用（true/false）
--   typeCode   : PUSH.* 类型常量
--   name       : 通道显示名（任意字符串）
--   url        : Webhook / API 地址
--                （钉钉/飞书/Telegram/PushDeer/Bark/企微/Pushover/inotify/
--                 next-smtp-proxy 等；Gotify 自托管多为 http）
--   key        : 主密钥/主参数（多数通道只需填这个）：
--                BARK=设备Key  PUSHDEER=pushkey  GOTIFY=Token
--                TELEGRAM=chat_id  PUSHOVER=API Token  CUSTOM_POST=填 "form" 走表单(留空为JSON)
--                NEXT_SMTP_PROXY=user|password|smtp_host|smtp_port|to_email|subject
--   key2       : 可选第二值（仅部分通道用）：
--                钉钉=加签 SEC 密钥；飞书=签名密钥(留空不校验)
--                TELEGRAM=bot_token  PUSHOVER=用户Key
--   customBody : 自定义模板（CUSTOM_POST 使用）。
--                JSON 模式用 {sender}/{message}/{timestamp}；
--                表单(form)模式务必用 {sender_u}/{message_u}/{timestamp_u}（URL 编码），
--                否则短信内容里的 &/=/%/空格 会破坏表单提交。
--   priority   : 优先级，0 为最高，数值越小越先发送（建议 0~10）
local function ch(enabled, typeCode, name, url, key, key2, customBody, priority)
    return {
        enabled    = enabled,
        type       = typeCode,
        name       = name or "",
        url        = url or "",
        key        = key or "",
        key2       = key2 or "",
        customBody = customBody or "",
        priority   = priority or 0,
    }
end

-- ============================================================================
-- ↓↓↓ 用户通常只需修改下面这一块 ↓↓↓
-- ============================================================================
local DEFAULT_CFG = {
    -- 管理员号码（可带 +86 也可不带）。开机成功后会向此号码发一条启动通知。
    adminPhone     = "",

    -- 转发目标手机号列表（收到短信后也会转发到这些号码）。
    forwardPhones  = {},

    -- 黑名单号码列表（这些号码的短信不转发、不推送）。
    blacklist      = {},

    -- 邮件配置（当前版本未使用，留空）。
    email          = {},

    -- 推送通道：固定 11 种，每种一个条目；enabled 控制是否启用（用户自行决定）。
    pushChannels   = {
        -- 推送通道（固定 11 种，每种一个 ch(...)）
        ch(false, PUSH.CUSTOM_POST, "Server酱",
            "https://sctapi.ftqq.com/<SENDKEY>.send",
            "form",
            "",
            "title=短信来自{sender_u}&desp={message_u}%0A时间:{timestamp_u}",
            0),
        ch(false, PUSH.TELEGRAM, "Telegram",
            "https://api.telegram.org",
            "",
            "",
            "",
            0),
        ch(false, PUSH.PUSHDEER, "PushDeer",
            "https://api2.pushdeer.com/message/push",
            "",
            "",
            "",
            0),
        ch(false, PUSH.BARK, "Bark（iOS推送）",
            "https://api.day.app",
            "",
            "",
            "",
            0),
        ch(false, PUSH.DINGTALK, "钉钉机器人",
            "https://oapi.dingtalk.com/robot/send?access_token=<TOKEN>",
            "",
            "",
            "",
            0),
        ch(false, PUSH.FEISHU, "飞书机器人",
            "",
            "",
            "",
            "",
            0),
        ch(false, PUSH.WECOM, "企业微信机器人",
            "",
            "",
            "",
            "",
            0),
        ch(false, PUSH.PUSHOVER, "Pushover",
            "https://api.pushover.net/1/messages.json",
            "",
            "",
            "",
            0),
        ch(false, PUSH.INOTIFY, "inotify",
            "",
            "",
            "",
            "",
            0),
        ch(false, PUSH.NEXT_SMTP_PROXY, "邮件代理(SMTP)",
            "",
            "",
            "",
            "",
            0),
        ch(false, PUSH.GOTIFY, "Gotify",
            "",
            "",
            "",
            "",
            0),
    },
}

return DEFAULT_CFG
