# sms

**文档版本** `1.1.0`

短信收发模块。纯函数：`send` / `send_async` 发，`reg` 收事件。没有对象、没有 `open`。

```lua
local sms = require("sms")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 运营商与固件](#2-运营商与固件)
- [3. 框架结构](#3-框架结构)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `sms.reg`](#6-1-reg)
  - [6.2 `sms.send`](#6-2-send)
  - [6.3 `sms.send_async`](#6-3-send-async)
- [7. 事件回调](#7-事件回调)
- [8. 发送返回值](#8-发送返回值)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`sms` 做两件事：发一条文本短信，以及用回调收「新短信 / 发送完成 / 发送失败」。

1. 必须插 **手机卡**，并已驻网（可用 `lp.wait_link`）。物联网卡一般发不了、也收不到业务短信。
2. `sms.reg(cb)` 登记事件回调。重复调用覆盖；`sms.reg(nil)` 取消。
3. 日常发送用 `send_async`：入队即返回，结果靠 `EVENT_SEND_DONE` / `EVENT_SEND_FAILED`。
4. `send` 同步等到发出或失败，占住整条 Lua 引擎线程。**不要在回调里用。**

这不是 TCP/MQTT 那种托管连接：没有「目标态」、没有自动重连。每条短信都是一次独立投递。

不要写 `while true do sms.send(...) end` 这类循环狂发。运营商会当垃圾号临时封停，短信费也会很快耗尽。

---

## 2. 运营商与固件

**目前标准固件仅支持中国联通和中国移动。**

需要电信、或三家都能用（全网通）时，必须换成独立发布的 **isms** 版本固件。标准包打上去，电信卡上短信不可用。

| 固件 | 短信可用运营商 |
| --- | --- |
| 标准固件 | 联通、移动 |
| **isms** 固件（独立发布） | 全网通，含电信 |

Lua API（`require("sms")`、`send` / `send_async` / `reg`）两边相同。差别在协议栈是否带电信短信，不在脚本写法。下单或刷机时认准固件型号里的 `isms`。

其余限制两边都有：要手机卡、要驻网、不要循环狂发。

---

## 3. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  reg(cb) → send_async / send                             │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  sms 模块                                                │
│  · send：当场阻塞发完                                    │
│  · send_async：入发送队列，立刻返回                      │
│  · 事件进运行时队列，调度循环里调 cb                     │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  短信协议                                                │
│  驻网检查 → 组 PDU（7bit / UCS2，超长自动分片）          │
│  收信解码合并后上报 NEW_SMS                              │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否已经发出 | 谁在跑 |
| --- | --- | --- | --- |
| `reg` | 登记 / 取消回调 | — | 之后事件在调度循环里调 |
| `send` | 阻塞直到发出或失败 | 返回时已有结果 | 当前 Lua 引擎线程 |
| `send_async` | 入队 | 否（只表示入队） | 内部发送线程；结果走回调 |
| 回调 `cb(ev)` | 调度循环里通知 | 看 `ev.event_id` | 不是短信工作线程 |

若设备还部署了快捷回调脚本 `cb_sms`，同一事件会再进那条独立快捷虚拟机（六个位置参数）。主业务脚本仍用 `sms.reg`；快捷脚本必须立刻返回，不能 `send` / `rt.delay`。

---

## 4. 常量与枚举

### 4.1 事件 `event_id`

用于回调 `ev.event_id`。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `sms.EVENT_NEW_SMS` | `0` | 收到新短信 |
| `sms.EVENT_SEND_DONE` | `1` | 异步发送成功 |
| `sms.EVENT_SEND_FAILED` | `2` | 异步发送失败 |

没有未导出却能当事件用的第四种 id。比较时用符号。

### 4.2 发送返回值（已导出）

用于 `send` / `send_async` 的返回整数。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `sms.ERR_OK` | `0` | 成功。`send` 表示已发出；`send_async` 表示已入队 | 返回值比较 |
| `sms.ERR_NET_NOT_ATTACHED` | `-100` | 未驻网 / PDP 未激活，不能发也不能入队 | 返回值比较 |

其它失败也是负数，**没有挂到模块表**，不要发明 `sms.ERR_QUEUE_FULL` 这类符号。见 [第 8 节](#8-发送返回值)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `da` | string | 目标号码，如 `"13800138000"` 或 `"+8613800138000"`。最长 20 字符 |
| `text` | string | 短信正文。纯 ASCII 走 7bit；含中文等走 UCS2。超长自动分片 |
| `guard_s` | integer | 发送超时，**秒**。省略 / `nil` = 30；传 `0` 也按 30；同步路径上限 60 |
| `user_tag` | integer | 仅 `send_async`。原样出现在完成/失败事件里。省略 / `nil` = `0` |
| `event_id` | integer | `EVENT_*` |
| `ret` | integer | `ERR_OK` / `ERR_NET_NOT_ATTACHED` / 其它负数 |
| `ev` | table | 见 [第 7 节](#7-事件回调) |

`guard_s` / `user_tag` 走整数，不是 boolean。不要传 `true`/`false` 当超时。

---

## 6. 模块函数

模块表上只有 `reg`、`send`、`send_async`。

---

### 6.1 `sms.reg(cb)` {#6-1-reg}

登记主脚本虚拟机的短信事件回调。全模块一条，重复调用 **覆盖** 旧回调。

**调用模式**

```lua
sms.reg(cb)
```

```lua
sms.reg(nil)
```

```lua
sms.reg()
```

| 形态 | 含义 |
| --- | --- |
| 函数 | 登记；`function(ev)`，见第 7 节 |
| `nil` / 省略 | 取消登记 |

第一参既不是函数也不是 `nil`：抛类型错。

**返回** 始终 `true`。

事件不是公开邮箱主题，不要用 `rt.mbox_reg("SMS", ...)` 去收。

---

### 6.2 `sms.send(da, text [, guard_s])` {#6-2-send}

同步发送。返回前占住整条 Lua 引擎线程（与 `ntp.get` 同类，**不是** `rt.delay` 那种让出）。其它 Lua 任务、定时器、IO 回调都要等它结束。

**不要在 `sms.reg` 回调、UART 回调、快捷 `cb_sms` 里调用。** 回调里发信用 `send_async`。

**调用模式**

```lua
sms.send(da, text)
```

```lua
sms.send(da, text, nil)
```

```lua
sms.send(da, text, guard_s)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `da` | string | 是 | 号码 |
| `text` | string | 是 | 正文 |
| `guard_s` | integer | 否 | 超时秒；省略 / `nil` = 30 |

**返回** integer，见 [第 8 节](#8-发送返回值)。`ERR_OK` 表示已经发出（不是「对方已读」）。

未驻网立刻 `ERR_NET_NOT_ATTACHED`，不会自己等网。

```lua
local ret = sms.send("13800138000", "hello")
if ret ~= sms.ERR_OK then
    log.warn("send fail %s", ret)
end
```

---

### 6.3 `sms.send_async(da, text [, guard_s[, user_tag]])` {#6-3-send-async}

入发送队列后立刻返回。真正发出去以后才会来 `EVENT_SEND_DONE` 或 `EVENT_SEND_FAILED`。回调里发信请用这个。

**调用模式**

```lua
sms.send_async(da, text)
```

```lua
sms.send_async(da, text, nil)
```

```lua
sms.send_async(da, text, guard_s)
```

```lua
sms.send_async(da, text, guard_s, nil)
```

```lua
sms.send_async(da, text, guard_s, user_tag)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `da` | string | 是 | 号码 |
| `text` | string | 是 | 正文；入队时拷贝，最长约 1000 字节，超出截断 |
| `guard_s` | integer | 否 | 超时秒；省略 / `nil` / `0` = 30 |
| `user_tag` | integer | 否 | 完成/失败事件里原样带回，用来对上是哪一条 |

**返回** integer：`ERR_OK` 只表示 **已入队**。队列满、未驻网、号码过长等当场失败，不会再有完成事件。

```lua
local ret = sms.send_async(DA, "hello from lua", 30, 1001)
```

---

## 7. 事件回调

```lua
function cb(ev)
```

跑在 Lua **调度循环**里：

- 立刻返回。不要 `rt.delay`、同步 `send`、`lp.wait_link`。
- 回短信用 `send_async`。
- 回调里抛错会被吞掉并记日志。

| 字段 | 类型 | `NEW_SMS` | `SEND_DONE` | `SEND_FAILED` |
| --- | --- | --- | --- | --- |
| `ev.event_id` | integer | `EVENT_NEW_SMS` | `EVENT_SEND_DONE` | `EVENT_SEND_FAILED` |
| `ev.sms_id` | integer | 存储 index；长短信合并后可能为 `0` | TP-MR（0～255） | `255` |
| `ev.is_sms_over_ip` | integer | 一般 `0` | 一般 `0` | 一般 `0` |
| `ev.sender` | string | 发件人号码 | 目标号码 | 目标号码，失败时可能空 |
| `ev.text` | string | 正文 | 当前为空串 | 当前为空串 |
| `ev.user_tag` | integer | 恒为 `0` | 入队时的 `user_tag` | 入队时的 `user_tag` |

号码、正文在投递进 Lua 时会截断：发件人约 31 字节，正文约 1199 字节。

---

## 8. 发送返回值

`send` / `send_async` 永远返回一个整数，不抛业务错（参数类型不对除外）。

| 值 | 是否模块常量 | 含义 |
| --- | --- | --- |
| `0`（`sms.ERR_OK`） | 是 | `send` 已发出；`send_async` 已入队 |
| `-100`（`sms.ERR_NET_NOT_ATTACHED`） | 是 | 未驻网 |
| `-1` | 否 | 参数无效 |
| `-2` | 否 | 号码过长（≥ 21 字节） |
| `-3` | 否 | 内存不足，或短信子系统未就绪 |
| `-4` | 否 | 异步队列满（仅 `send_async`） |
| `-5` | 否 | 组 PDU 失败（仅同步） |
| `-6` | 否 | 单条发送失败（仅同步；异步则表现为 `SEND_FAILED`） |
| `-7` | 否 | 长短信某一片发送失败（仅同步） |

未导出的负数不要写成 `sms.ERR_xxx`。判断时：先比 `ERR_OK` 和 `ERR_NET_NOT_ATTACHED`，其余当失败即可。

`send_async` 返回 `ERR_OK` 之后，真正发出失败只会走 `EVENT_SEND_FAILED`，不会再给这次调用返回 `-6`。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `reg` | `true` | 非函数且非 `nil` 时抛类型错 |
| `send` | `ERR_OK`（`0`） | 其它整数；`da`/`text` 不是字符串则抛 |
| `send_async` | `ERR_OK`（已入队） | 其它整数；类型错则抛 |

没有返回文本 `err`。业务失败就是整数码。缺参走 Lua 标准 `bad argument #n`。

**发送返回码（`send` / `send_async`）**

| 值 | 模块常量 | 可能原因 |
| --- | --- | --- |
| `0` | `sms.ERR_OK` | `send` 已发出；`send_async` 已入队 |
| `-100` | `sms.ERR_NET_NOT_ATTACHED` | 未驻网 / PDP 未激活。先 `lp.wait_link` |
| `-1` | 否 | `da`/`text` 为空指针级无效（脚本侧少见；类型错会先抛） |
| `-2` | 否 | 号码过长（≥ 21 字节，含 `+`） |
| `-3` | 否 | 内存不足，或短信子系统未就绪 |
| `-4` | 否 | 异步队列满（仅 `send_async`，队列约 12 条） |
| `-5` | 否 | 组 PDU 失败（仅同步） |
| `-6` | 否 | 单条发送失败（仅同步；异步则表现为 `EVENT_SEND_FAILED`） |
| `-7` | 否 | 长短信某一片发送失败（仅同步） |

未导出的负数不要写成 `sms.ERR_xxx`。`send_async` 返回 `0` 之后，真正发出失败只走 `EVENT_SEND_FAILED`。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 号码 `da` | 20 字符 | 含 `+`；再长返回 `-2` |
| 异步正文拷贝 | 约 950 字节 | 超出截断后再发 |
| 单条 7bit | 160 字符 | 更长自动分片（带头约 153 / 片） |
| 单条 UCS2（中文等） | 70 字符 | 更长自动分片（带头约 67 / 片） |
| 异步发送队列 | 12 条 | 满则 `-4` |
| `guard_s` | 同步最大 60 秒 | 默认 30 |
| 回调 `sender` | 约 31 字节 | 投递进 Lua 时截断 |
| 回调 `text` | 约 1199 字节 | 长短信合并后的上限量级 |
| `sms.reg` | 每虚拟机 1 个 | 覆盖，不是叠加 |

无 userdata。`reg` 的函数引用挂在当前虚拟机上，脚本退出会拆掉。

编码由正文自动选：能进 7bit GSM 默认表就 7bit，否则 UCS2。脚本不用自己选编码。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 收短信 | `sms.reg(cb)`，看 `EVENT_NEW_SMS` |
| 任务里发一条并立刻知道成败 | `send`（不要在回调里） |
| 回调里回信、或不等待 | `send_async`，用 `user_tag` 对结果 |
| 未驻网 | 先 `lp.wait_link`；否则 `-100` |
| 电信卡 | 刷 **isms** 固件，标准固件不行 |
| 物联网卡 | 不要测短信，换手机卡 |
| 取消收信 | `sms.reg(nil)` |
| 周期性狂发 | 特别是文本完全一样的短信**【别这么干👈，被运营商ban了，受伤的只会是自己】** |

---

## 12. 完整示例

与 [examples/NT26/network/sms/sms_api](../../../../examples/NT26/network/sms/sms_api) 一致。把 `DA` 换成你的手机号才发测试短信；空串只收不发。必须用手机卡。

```lua
local rt  = require("rt")
local log = require("log")
local lp  = require("lp")
local sms = require("sms")

local DA = ""   -- 例如 "13800138000"；空 = 只收不发
local LINK_WAIT_MS = 60 * 1000

local function ev_name(id)
    if id == sms.EVENT_NEW_SMS then
        return "NEW_SMS"
    elseif id == sms.EVENT_SEND_DONE then
        return "SEND_DONE"
    elseif id == sms.EVENT_SEND_FAILED then
        return "SEND_FAILED"
    end
    return tostring(id)
end

local function on_sms(ev)
    if not ev then
        return
    end
    log.info("sms %s sms_id=%s sender=%s tag=%s text=%s",
             ev_name(ev.event_id), ev.sms_id,
             tostring(ev.sender), ev.user_tag, tostring(ev.text))
    -- 不要在这里 sms.send；回信用 send_async
end

if not lp.wait_link(LINK_WAIT_MS) then
    log.warn("网络超时，没有网络无法测试 sms")
    while true do rt.delay(10000) end
end

sms.reg(on_sms)

if DA ~= "" then
    local ret = sms.send_async(DA, "hello from lua", 30, 1001)
    log.info("send_async ret=%s", ret)
end

while true do
    rt.delay(10000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `sms.reg(cb)` | 登记回调，覆盖旧的 | `true` |
| `sms.reg(nil)` / `sms.reg()` | 取消回调 | `true` |
| `sms.send(da, text)` | 同步发，默认超时 30 s | 整数 |
| `sms.send(da, text, guard_s)` | 同步发，自定义超时 | 整数 |
| `sms.send_async(da, text)` | 入队，tag=0 | 整数（0=已入队） |
| `sms.send_async(da, text, guard_s)` | 入队 | 同上 |
| `sms.send_async(da, text, guard_s, user_tag)` | 入队并带标记 | 同上 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `sms.EVENT_NEW_SMS` | 0 |
| `sms.EVENT_SEND_DONE` | 1 |
| `sms.EVENT_SEND_FAILED` | 2 |
| `sms.ERR_OK` | 0 |
| `sms.ERR_NET_NOT_ATTACHED` | -100 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部发送返回码与可能原因 |
