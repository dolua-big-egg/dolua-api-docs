# NT26 短信转发器 — 使用与配置说明

本例程把模组收到的短信推到钉钉 / 飞书 / Bark / Telegram 等通道，也可再转发到指定手机号。  
**配置只来自 `config.lua`。** 改完后必须和 `sms_forward.lua` 一起重新烧录才会生效。运行时不能用短信改参数。

| 文件 | 作用 |
| --- | --- |
| `sms_forward.lua` | 主程序（监听短信、推送、转发）。一般不用改。 |
| `config.lua` | 唯一配置文件。用户 / AI 只改这个。 |
| `rtu_config.cfg` | 模组工程配置，与推送通道无关。 |

---

## 1. 它实际会做什么

开机后等待驻网，向 `adminPhone` 发一条「短信转发器已启动」（号码为空则不发）。

之后每收到一条新短信：

1. **60 秒内**同一发送者 + 相同内容前 48 字，视为重复，丢弃。
2. 发送者在 **黑名单** 里：不推送、不转发。
3. 按通道 **优先级**（数字越小越先发，0 最高）依次 HTTP/HTTPS 推送。`enabled` 不是 `true`、或类型为 `NONE` 的通道跳过。
4. 若配置了 **转发手机号**：再 `sms.send` 到这些号码。来自转发号自己的短信不再二次转发，避免回环。

HTTPS 使用 Lua `http` 模块，`TLS_INSECURE`（加密、不校验证书）。失败会重试 2 次。

---

## 2. 用户怎么改配置

直接改 `config.lua` 里 `DEFAULT_CFG = { ... }` 这一块，**不要动**文件上半部分的 `PUSH` 常量表和 `ch(...)` 函数。改完后勾选下载 `config.lua` 与 `sms_forward.lua`，重新烧录。

```lua
local DEFAULT_CFG = {
    adminPhone     = "13800138000",          -- 开机通知号码；不需要就 ""
    forwardPhones  = {"13900139000"},        -- 短信转发目标；不需要就 {}
    blacklist      = {"10086"},              -- 这些来信号码不处理；不需要就 {}
    email          = {},                     -- 当前未使用，保持空表
    pushChannels   = {
        -- 固定 11 条 ch(...)，类型与顺序见下文，不要增删、不要换序
        ch(true/false, PUSH.类型, "名称", "url", "key", "key2", "customBody", 优先级),
        ...
    },
}
return DEFAULT_CFG
```

`ch(...)` 参数顺序固定，少一个就不完整：

| 序号 | 参数 | 类型 | 含义 |
| --- | --- | --- | --- |
| 1 | enabled | `true` / `false` | 是否启用 |
| 2 | type | `PUSH.CUSTOM_POST` 等 | 通道种类，必须用符号，不要写数字 |
| 3 | name | 字符串 | 显示名（日志用） |
| 4 | url | 字符串 | Webhook / API 地址 |
| 5 | key | 字符串 | 主密钥或主参数 |
| 6 | key2 | 字符串 | 第二密钥；不用就 `""` |
| 7 | customBody | 字符串 | 仅 CUSTOM_POST 用；其它通道 `""` |
| 8 | priority | 整数 | 0 最高 |

字符串用双引号。URL、token 里的 `"` 要写成 `\"`。不要删 `return DEFAULT_CFG`。

不需要的通道写成 `ch(false, PUSH.XXX, ...)`，**不要删那一行**。`pushChannels` 必须始终是下面 11 种、且按此顺序：

`CUSTOM_POST` → `TELEGRAM` → `PUSHDEER` → `BARK` → `DINGTALK` → `FEISHU` → `WECOM` → `PUSHOVER` → `INOTIFY` → `NEXT_SMTP_PROXY` → `GOTIFY`

烧录后只改电脑上的文件，模组里不会自动变。

### 改完怎么确认生效

- 烧录后模组应给 `adminPhone` 发开机短信（该字段非空时）。
- 用非黑名单号码给模组发一条短信，看对应通道有没有到。
- 日志里会有 `已从 config.lua 载入配置`，以及 `HTTP POST ... -> 200`。

---

## 3. 十一种通道怎么填

未启用的通道 url/key 可以留空。

### 3.1 自定义 POST（`PUSH.CUSTOM_POST`）

任意 HTTP/HTTPS 的 POST（Server酱、自建接口等）。

- **url**：完整地址，例如 `https://sctapi.ftqq.com/<SENDKEY>.send`
- **key**：填 `form` 则按表单编码；其它值或空则按 JSON（`Content-Type: application/json`）
- **customBody**：请求体模板，运行时替换占位符：

| 占位符 | 替换内容 | 适用 |
| --- | --- | --- |
| `{sender}` `{message}` `{timestamp}` | JSON 转义后的发送者 / 正文 / 时间 | JSON 模式 |
| `{sender_u}` `{message_u}` `{timestamp_u}` | URL 编码后的同上 | **表单必须用这组**，否则短信里的 `&` `=` `%` 空格会拆坏表单 |

表单示例（Server酱一类）：

```lua
ch(true, PUSH.CUSTOM_POST, "Server酱",
    "https://sctapi.ftqq.com/<SENDKEY>.send",
    "form",
    "",
    "title=短信来自{sender_u}&desp={message_u}%0A时间:{timestamp_u}",
    0),
```

未填 `customBody` 的启用通道会被跳过。

### 3.2 Telegram（`PUSH.TELEGRAM`）

- **url**：默认 `https://api.telegram.org`；自建反代可改
- **key**：`chat_id`
- **key2**：`bot_token`（程序会拼 `/bot{token}/sendMessage`）

### 3.3 PushDeer（`PUSH.PUSHDEER`）

- **url**：默认 `https://api2.pushdeer.com/message/push`
- **key**：pushkey

### 3.4 Bark（`PUSH.BARK`）

- **url**：默认 `https://api.day.app`（自建服务器填自己的根地址，不要末尾 `/`）
- **key**：设备 Key。程序实际请求 `url/key`

也可把 key 已经写在 url 路径里，此时 **key 留空**。不要两边各写一份导致拼两次。

### 3.5 钉钉（`PUSH.DINGTALK`）

- **url**：机器人 Webhook，须含 `access_token=...`
- **key2**：加签 SEC（一般以 `SEC` 开头）。**留空 = 不加签**
- **key、customBody**：不用，留空

加签依赖模组时间，启动时会 NTP 校时。

### 3.6 飞书（`PUSH.FEISHU`）

- **url**：`https://open.feishu.cn/open-apis/bot/v2/hook/<uuid>`
- **key2**：签名密钥；留空不校验

### 3.7 企业微信（`PUSH.WECOM`）

- **url**：群机器人 Webhook。HTTP 200 但 JSON 里 `errcode != 0` 会当失败重试。

### 3.8 Pushover（`PUSH.PUSHOVER`）

- **url**：默认 `https://api.pushover.net/1/messages.json`
- **key**：API Token
- **key2**：User Key

### 3.9 inotify（`PUSH.INOTIFY`）

- **url**：**必须以 `.send` 结尾**
- 程序用 GET：`url/` + URL 编码后的短信正文

### 3.10 邮件代理 SMTP（`PUSH.NEXT_SMTP_PROXY`）

走 HTTP 代理接口，不是模组直接连 SMTP。

- **url**：代理服务地址
- **key**：六个字段用 `|` 拼接，不要多空格：  
  `user|password|smtp主机|端口|收件邮箱|主题`

### 3.11 Gotify（`PUSH.GOTIFY`）

- **url**：服务根地址（可 `http://`），程序会补成 `url/message?token=...`
- **key**：Gotify Token

---

## 4. 常见问题

**改了 config.lua 没变化**  
没有重新烧录，或工程里没勾选 `config.lua`。本程序不会从 UFS 读旧配置。

**钉钉/飞书收不到**  
Webhook 填错、加签 SEC 填错、或未驻网。看日志 HTTP 状态和 `errcode`。加签通道需要校时成功。

**Bark 的 key 填在 url 还是 key**  
二选一：`url=https://api.day.app` 且 `key=设备Key`；或 url 已含设备路径、key 留空。不要重复拼两次。
