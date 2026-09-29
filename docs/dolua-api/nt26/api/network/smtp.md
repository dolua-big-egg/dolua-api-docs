# smtp

**文档版本** `1.0.0`

**起始固件** `NT26-PRO-RTU-D1.3.2`（此前版本没有 `smtp` 模块）

同步提交一封 UTF-8 纯文本邮件。没有对象、没有回调、没有后台发信任务。`smtp.send(opts)` 当场连上 SMTP 服务器、认证、发完再关掉连接。

```lua
local smtp = require("smtp")
```

平台预加载模块，无需额外 `.lua` 文件。

必须已经能上网。建议先 `lp.wait_link`，再 `send`。必须走 TLS：要么连上即加密（隐式 TLS），要么明文问候后再 `STARTTLS`。没有明文 25 端口这条路径。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 两种 TLS（怎么选）](#4-两种-tls怎么选)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [`smtp.send`](#7-send)
- [8. 配置表字段](#8-配置表字段)
- [9. 邮箱、授权码与 QQ](#9-邮箱授权码与-qq)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [附录 A. 方法速查](#附录-a-方法速查)
- [附录 B. 枚举值一览](#附录-b-枚举值一览)
- [修订记录](#修订记录)

---

## 1. 模块定位

本模块从固件 **`NT26-PRO-RTU-D1.3.2`** 起支持。更早的包里 `require("smtp")` 不存在。

只做一件事：按配置表发一封 `text/plain; charset=UTF-8` 邮件。

1. 填主机、发件人、收件人、授权码，选 `tls` 模式。
2. `smtp.send(opts)` 同步完成：解析主机 → TCP → TLS → `EHLO` / 认证 → `MAIL`/`RCPT`/`DATA` → `QUIT` → 关连接。
3. 成功返回 `true`；失败返回 `nil, err, msg`。
4. 每次调用自建连接，返回后连接已关闭。要再发一封，再调一次。

这不是托管通道：不会后台排队、不会自动重连保活、没有事件回调。周期性上报自己用 `rt.delay` 隔一段时间再 `send`。

不要在 UART / MQTT / TCP 等回调里调用：发信会占住整条 Lua 引擎线程。

证书不做校验。脚本仍须持有正确的授权码；被中间人连上假服务器时，内容可能被看到。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  lp.wait_link → smtp.send({ host, tls, user, ... })      │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  smtp 模块                                                │
│  · 解析配置表，缺省端口随 tls 模式走 465 或 587            │
│  · 同步 TCP + TLS，发完即关                               │
│  · 全系统同时一路，返回前其它 smtp.send 进不来              │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  网络（需已驻网）                                          │
│  隐式 TLS：连上即握手                                      │
│  STARTTLS：先读 220 / EHLO，再升级                         │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 要不要网 |
| --- | --- | --- | --- |
| `smtp.send` | DNS + TCP + TLS + SMTP 命令，发完关连接 | **否** | **必须**已驻网 |

握手协议为 TLS 1.2。解析出多个地址时会依次尝试；某一地址握手超时会换下一个。

---

## 3. 阻塞语义

`send` **不是** `rt.delay` 那种让出。返回前：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 看门狗仍可能被喂到，但超时开得太大（比如几十秒再叠加重试）会把整机业务卡住

默认握手读超时 8 秒、每条 SMTP 命令读超时 5 秒；另有最多 2 次额外重试（只覆盖连接/TLS/超时/断开/发送失败，认证失败不重试）。正式业务不要把超时拉到十几秒以上再叠加很高的 `retry`。

需要网络。没 SIM / 没驻网会失败，不会自己等网。

---

## 4. 两种 TLS（怎么选）

`tls` 管握手怎么走，`port` 只管连哪。两者可以一起写，但 **不要混用**：465 配 `TLS_STARTTLS`、587 配 `TLS_IMPLICIT` 都会和服务器对不上。

| `tls` | 连上之后 | 省略 `port` 时 | 典型场景 |
| --- | --- | --- | --- |
| `smtp.TLS_IMPLICIT`（默认，也可不写） | 立刻 TLS，再读 SMTP 220 | **465** | 163、企业邮 SMTPS |
| `smtp.TLS_STARTTLS` | 先明文读 220、`EHLO`，再 `STARTTLS` 升级 | **587** | **QQ 邮箱推荐**；也适用于其它开了 STARTTLS 的服务器 |

推荐写法：只写 `tls`，不写 `port`，让默认口跟模式走。

```lua
-- 隐式 TLS，默认 465
smtp.send({ host = "smtp.163.com", tls = smtp.TLS_IMPLICIT, ... })
```

```lua
-- STARTTLS，默认 587。QQ 邮箱请用这一条。
smtp.send({ host = "smtp.qq.com", tls = smtp.TLS_STARTTLS, ... })
```

```lua
-- 服务器把 STARTTLS 开在非标准口时才需要自己填 port
smtp.send({ host = "...", tls = smtp.TLS_STARTTLS, port = 2525, ... })
```

旧字段 `starttls = true/false` **已经废除**。再写会抛错，提示改用 `tls = smtp.TLS_IMPLICIT` 或 `smtp.TLS_STARTTLS`。

---

## 5. 常量与枚举

模块表导出下列常量。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `smtp.TLS_IMPLICIT` | `0` | 连上即 TLS | `opts.tls` |
| `smtp.TLS_STARTTLS` | `1` | 明文问候后再 STARTTLS | `opts.tls` |
| `smtp.DEFAULT_PORT` | `465` | 隐式 TLS 的惯用端口 | 对照用。省略 `port` 且 `tls` 为 STARTTLS 时实际走的是 **587**，不是这个常量 |

没有未导出却能当 API 用的其它 TLS 模式。`tls` 只能是上面两个整数；传 `2`、字符串、布尔都会失败或抛错。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `opts` | table | `send` 的唯一参数 |
| `host` | string | 主机名或 IP，不要带 `http://`、不要带端口、不要含 `/` |
| `port` | integer | `1`～`65535`；省略则按 `tls` 填 465 或 587 |
| `tls` | integer | `smtp.TLS_IMPLICIT` / `smtp.TLS_STARTTLS`；省略 = 隐式 TLS |
| `user` / `password` | string | 同时有则登录；同时省略则不认证。只填一个会失败 |
| `from` | string | 完整邮箱，必须含 `@` |
| `to` | string 或字符串数组 | 1～4 个完整邮箱 |
| `subject` | string | 可省略；含中文会按 UTF-8 编码进邮件头 |
| `body` | string | 可省略；UTF-8 纯文本，最长 8192 字节 |
| `auth_plain` | boolean 或 integer | 见下 |
| `timeout_s` | integer | `> 0` 时作为下面两段的后备 |
| `connect_timeout_s` | integer | TLS 握手读超时（秒） |
| `cmd_timeout_s` | integer | 每条 SMTP 命令读超时（秒） |
| `retry` | integer | 额外重试次数；`< 0` 当默认 2；`0` = 不重试；上限 3 |
| `pdp_id` | integer | `0`～`255`；省略绑当前默认上网网卡 |
| 成功返回 | boolean `true` | 只有一个返回值 |
| 失败返回 | `nil, err, msg` | `err` 为负整数，`msg` 为英文摘要 |

`auth_plain`：

- 传 **boolean**：`true` 走 `AUTH PLAIN`，`false` 走 `AUTH LOGIN`。
- 传 **integer**：走布尔语义，**数字 `0` 为真**（会变成 PLAIN）。推荐只写 `true` / `false`。
- 省略：`AUTH LOGIN`。

`tls` 必须是整数枚举，不要传 `true`/`false`。

---

## 7. 模块函数

模块表上只有 `send`。

---

### `smtp.send(opts)` {#7-send}

按配置表发一封邮件。成功 `true`；失败 `nil, err, msg`。参数类型不对或仍写了 `starttls` 时 **抛错**。

**调用模式**

```lua
smtp.send(opts)
```

```lua
local ok, err, msg = smtp.send({
    host = "smtp.qq.com",
    tls = smtp.TLS_STARTTLS,
    user = "xxx@qq.com",
    password = "授权码",
    from = "xxx@qq.com",
    to = "yyy@qq.com",
    subject = "设备通知",
    body = "内容",
})
```

```lua
smtp.send({
    host = "smtp.163.com",
    tls = smtp.TLS_IMPLICIT,
    user = "xxx@163.com",
    password = "授权码",
    from = "xxx@163.com",
    to = "xxx@163.com",
    subject = "设备通知",
    body = "内容",
})
```

```lua
smtp.send({
    host = "smtp.qq.com",
    tls = smtp.TLS_STARTTLS,
    auth_plain = true,
    user = FROM,
    password = AUTH_CODE,
    from = FROM,
    to = { "a@qq.com", "b@163.com" },
    subject = SUBJECT,
    body = BODY,
    connect_timeout_s = 8,
    cmd_timeout_s = 5,
    retry = 2,
})
```

```lua
-- 省略 tls：与 TLS_IMPLICIT 相同，默认 465
smtp.send({
    host = "smtp.163.com",
    user = FROM,
    password = AUTH_CODE,
    from = FROM,
    to = TO,
    body = "hi",
})
```

`opts` 必须是 table，不能把字段拆成位置参数。

**返回**

- 成功：`true`
- 失败：`nil, err, msg`。`msg` 在服务器给了回复时可能带上码，例如 `authentication failed (535 ...)`
- 类型不对 / 仍传 `starttls`：**抛错**

成功没有第二、第三返回值。

---

## 8. 配置表字段

| 字段 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `host` | 是 | — | SMTP 主机。最长 119 字节，不能含 `/`、回车换行 |
| `from` | 是 | — | 发件地址，必须含 `@`，最长 127 字节，不能含回车换行 |
| `to` | 是 | — | 一个字符串，或 1～4 个字符串的数组 |
| `user` | 与 `password` 成对 | 不登录 | 登录名，通常与 `from` 相同 |
| `password` | 与 `user` 成对 | 不登录 | 客户端授权码或服务商规定的 SMTP 密码，**不是**网页登录密码 |
| `tls` | 否 | `TLS_IMPLICIT` | 见 [第 4 节](#4-两种-tls怎么选) |
| `port` | 否 | 随 `tls`：465 或 587 | `1`～`65535`。Lua 里不能传 `0` 表示默认（省略该键即可） |
| `subject` | 否 | 空主题 | 最长 200 字节，不能含回车换行 |
| `body` | 否 | 空正文 | UTF-8，最长 **8192** 字节 |
| `auth_plain` | 否 | `false`（LOGIN） | 企业邮常用 PLAIN；QQ / 163 两种都可以 |
| `timeout_s` | 否 | 不用 | `> 0` 时，未单独写的握手/命令超时都用它 |
| `connect_timeout_s` | 否 | 8 | TLS 握手读超时（秒） |
| `cmd_timeout_s` | 否 | 5 | 每条命令读超时（秒） |
| `retry` | 否 | 2 | 额外重试次数，最大 3 |
| `pdp_id` | 否 | 当前默认网卡 | `0`～`254` 为指定 CID；省略不要填 |

`to` 超过 4 个、`body` 超过 8192、地址没有 `@`、`user`/`password` 只填一侧：失败 `err = -1`（`invalid param`），不抛错。

`port` 不是整数、越界、`tls` 不是合法枚举、`pdp_id` 越界：同样 `invalid param`。`tls` 类型不是整数：Lua 标准类型错。

---

## 9. 邮箱、授权码与 QQ

公共邮箱几乎都要求先在网页里打开 SMTP，再用 **授权码**（或应用专用密码），不能拿网页登录密码去 `password`。

| 服务商 | 主机 | 推荐 `tls` | `password` |
| --- | --- | --- | --- |
| QQ 邮箱 | `smtp.qq.com` | **`TLS_STARTTLS`（默认 587）** | 设置 → 账号与安全 → 开启 SMTP → 生成授权码（一般 16 位） |
| 163 | `smtp.163.com` | `TLS_IMPLICIT`（默认 465）也可 STARTTLS | 设置 → POP3/SMTP/IMAP → 客户端授权码 |
| 腾讯企业邮 | `smtp.exmail.qq.com` | 两种都可以 | 按企业邮说明，常见是邮箱密码；认证可用 `auth_plain = true` |

发件人必须是开通了 SMTP 的那个账号，且与 `user` 一致。收件人可以是自己，也可以是其它邮箱。

**QQ 邮箱请走 STARTTLS。** `smtp.TLS_STARTTLS` + `smtp.qq.com`、不传 `port`（默认 587）可以发给 QQ，也是本模块的推荐写法。QQ 的 465 隐式 TLS 在蜂窝链路上握手不稳定，不要用 `smtp_implicit` 那条例程去发 QQ。

对应示例：

- [smtp_starttls](../../../../../examples/nt26/network/smtp/smtp_starttls) — STARTTLS，适合 QQ
- [smtp_implicit](../../../../../examples/nt26/network/smtp/smtp_implicit) — 隐式 TLS，适合 163 等

例程里的 `HOST` / `FROM` / `TO` / `AUTH_CODE` 是空的，填好再烧。

---

## 10. 错误与返回约定

| 结果 | 返回 |
| --- | --- |
| 成功 | `true` |
| 业务失败 | `nil, err, msg` |
| 参数类型错 / 仍写 `starttls` | 抛错 |

**`err` / `msg`（业务失败）**

| `err` | `msg` 基文 | 可能原因 |
| --- | --- | --- |
| `-1` | `invalid param` | 缺 `host`/`from`/`to`；地址无 `@` 或含回车；`to` 超过 4 个；`body` 超过 8192；`user`/`password` 只填一个；`tls` 不是 0/1；`port`/`pdp_id` 越界 |
| `-2` | `out of memory` | 内存不够 |
| `-3` | `connect failed` | 未驻网、DNS 失败、TCP 连不上 |
| `-4` | `tls failed` | TLS 握手失败（对端不回、协议不匹配、把 465/587 和 `tls` 写反） |
| `-5` | `smtp protocol error` | 服务器回复码不是当前步骤期望的（例如拒绝 MAIL/RCPT/DATA） |
| `-6` | `authentication failed` | 授权码错、账号未开 SMTP、用户名不是完整邮箱 |
| `-7` | `send failed` | 命令或正文发送失败 |
| `-8` | `timeout` | 握手或命令读超时 |
| `-9` | `connection closed` | 对端关掉连接 |
| `-10` | `busy` | 内部互斥未拿到（极少见；同线程上一次 `send` 返回前不会并发进来） |

服务器若返回了 SMTP 码，`msg` 会拼在基文后面，例如 `authentication failed (535 ...)`。

**抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `smtp: use tls = smtp.TLS_IMPLICIT or smtp.TLS_STARTTLS` | 配置表里还有 `starttls` |
| `smtp: host must be a string` 等 | `host` / `user` / `password` / `from` / `subject` / `body` 不是字符串 |
| `smtp: to must be a string or array` | `to` 既不是字符串也不是表 |
| `smtp: to[N] must be a string` | 收件人数组第 N 项不是字符串 |

`opts` 不是 table、`port`/`tls`/`retry` 等类型不对：Lua 标准 `bad argument`。

---

## 11. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 并发发信 | 1 路 | `send` 返回前占住整条 Lua 引擎线程 |
| 收件人 | 4 | `to` 数组 |
| 正文 | 8192 字节 | UTF-8 字节数，不是字符数 |
| 主题 | 200 字节 | 不能含 `\r` / `\n` |
| 主机名 | 119 字节 | 不能含 `/` |
| 地址 / 用户名 / 密码 | 127 字节 | 地址必须含 `@` |
| 默认额外重试 | 2（最多 3） | 只覆盖连接、TLS、超时、断开、发送失败 |
| 默认握手超时 | 8 秒 | `connect_timeout_s` |
| 默认命令超时 | 5 秒 | `cmd_timeout_s` |

无对象、无 `__gc`、无回调槽。不需要持有引用。每次 `send` 结束即断开。

认证失败、协议错误、参数错误 **不会** 按 `retry` 再试。

---

## 12. 选型对照

| 需求 | 做法 |
| --- | --- |
| 发给 QQ | `tls = smtp.TLS_STARTTLS`，`host = "smtp.qq.com"`，不写 `port` |
| 163 隐式 TLS | `tls = smtp.TLS_IMPLICIT`，`host = "smtp.163.com"` |
| 企业邮 | 主机用企业邮 SMTP；认证可试 `auth_plain = true` |
| 多个收件人 | `to = { "a@x.com", "b@y.com" }`，最多 4 个 |
| 周期上报 | 自己 `rt.delay` 后再 `send` |
| 在回调里发信 | **不要**；丢到独立任务再调 |
| 附件 / HTML | 本模块不支持，只发 UTF-8 纯文本 |
| 明文 25 端口 | 不支持 |
| 自己用 `tcp` 手搓 SMTP | 不要；`tcp` 没有 STARTTLS 升级 |

---

## 13. 完整示例

与 [examples/nt26/network/smtp/smtp_starttls](../../../../../examples/nt26/network/smtp/smtp_starttls) 同一条路径：等网 → 检查参数 → STARTTLS 发一封。把空字符串换成你的主机、邮箱和授权码。QQ 用这一份。

隐式 TLS、打满 8 KB 正文见 [smtp_implicit](../../../../../examples/nt26/network/smtp/smtp_implicit)。

```lua
local rt = require("rt")
local log = require("log")
local lp = require("lp")
local smtp = require("smtp")

-- QQ：smtp.qq.com + TLS_STARTTLS（默认 587）
local HOST = ""
local FROM = ""
local TO = ""
local AUTH_CODE = ""
local SUBJECT = "NT26 SMTP STARTTLS 测试"
local BODY = "这是一封由 NT26 设备通过 STARTTLS 发出的测试邮件。"

if not lp.wait_link(60000) then
    log.warn("网络超时，没有网络无法发信")
    while true do
        rt.delay(10000)
    end
end

if HOST == "" or FROM == "" or TO == "" or AUTH_CODE == "" then
    log.error("请先填写 HOST / FROM / TO / AUTH_CODE")
    while true do
        rt.delay(10000)
    end
end

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
    connect_timeout_s = 8,
    cmd_timeout_s = 5,
    retry = 2,
})
if not ok then
    log.error("send fail err=%s msg=%s", tostring(err), tostring(msg))
else
    log.info("send ok")
end

while true do
    rt.delay(10000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `smtp.send(opts)` | 发一封 UTF-8 纯文本并关连接 | 成功 `true`；失败 `nil, err, msg` |
| `opts.tls = smtp.TLS_IMPLICIT`，省略 `port` | 隐式 TLS，465 | 同上 |
| `opts.tls = smtp.TLS_STARTTLS`，省略 `port` | STARTTLS，587（QQ 用这条） | 同上 |
| `opts.to = { ... }` | 最多 4 个收件人 | 同上 |
| `opts.auth_plain = true` | `AUTH PLAIN` | 同上 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `smtp.TLS_IMPLICIT` | `0` |
| `smtp.TLS_STARTTLS` | `1` |
| `smtp.DEFAULT_PORT` | `465` |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-29 | 首版。模块从固件 `NT26-PRO-RTU-D1.3.2` 起支持；`smtp.send`、`TLS_IMPLICIT` / `TLS_STARTTLS`、端口缺省与 QQ STARTTLS 推荐写法 |
