# ntp

**文档版本** `1.0.1`

同步问询 NTP 的纯函数模块。没有对象、没有回调、没有自动重连。`ntp.get` 当场 UDP 问一次，返回时间字符串或 `nil`。

```lua
local ntp = require("ntp")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [`ntp.get`](#6-get)
- [7. 返回字符串](#7-返回字符串)
- [8. 写本机钟（`auto_set`）](#8-写本机钟auto_set)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`ntp` 只做一件事：向 NTP 服务器要当前 UTC 时间。

1. 必须已经能上网（有 PDP）。没网会 `nil`。也可以先 `lp.wait_link`，再 `get`。
2. `ntp.get(...)` 同步问询。成功返回时间字符串，失败返回 `nil`。
3. 可选第五参 `auto_set`：把这次问到的 UTC 秒写入本机钟，效果与 `sys.set_ts` 相同。
4. 参数都可以省略；中间想跳过某项就传 `nil`。

这不是托管连接：不会后台对时、不会断线重连、没有事件回调。要周期性对时，自己用 `rt.delay` 隔一段时间再 `get`。

不要在 UART / MQTT / TCP 等回调里调用：问询会占住整条 Lua 引擎线程。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("ntp") → get([server, port, timeout, tz, set]) │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  ntp 模块                                                │
│  · 缺省参数用模块常量 / 系统时区                         │
│  · 同步 UDP 问询（含 DNS、有限次重试）                    │
│  · 可选：把 UTC 秒写入本机钟                             │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  网络                                                    │
│  需已驻网。一次调用占住 Lua 引擎线程，直到成功或超时     │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `ntp.get` | DNS + UDP 问 NTP，组时间字符串 | **否** | 整条 Lua 引擎线程 |
| `auto_set=true` 且问询成功 | 再写本机 UTC 秒 | 仍在同一次调用里 | 同上 |

全系统同时只能跑 **一路** 问询。第二路会等到第一路返回，不会并行打两份包。

---

## 3. 阻塞语义

`get` **不是** `rt.delay` 那种让出。返回前：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 看门狗仍可能被喂到，但超时开得太大（比如几十秒）会把整机业务卡住

`timeout_ms` 是 **这一整次** 的上限：含解析主机名、最多 3 次 UDP、两次失败之间约 500 ms 间隔。默认 6000。正式业务不要开到十几秒以上。

需要网络。没 SIM / 没驻网会一直 `nil`，不会自己等网。

---

## 4. 常量与枚举

模块表导出三个常量，对应 `get` 省略该项时的默认值。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `ntp.DEFAULT_SERVER` | `"ntp1.aliyun.com"` | 内置 NTP 主机 | `get` 的 `server` 省略 / `nil` |
| `ntp.DEFAULT_PORT` | `123` | 标准 NTP 端口 | `get` 的 `port` 省略 / `nil` |
| `ntp.DEFAULT_TIMEOUT` | `6000` | 整次问询超时（毫秒） | `get` 的 `timeout_ms` 省略 / `nil` |

没有事件枚举。没有未导出却能当 API 用的第五个常量。

传空字符串当 `server` **不会**回落到 `DEFAULT_SERVER`，会改走协议层另一台内置主机。要默认服务器就省略或传 `nil`。

`port` 传 `0` 时，协议层按 123 处理（与省略不同：省略用模块常量，`0` 也落到 123）。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `server` | string | 主机名或 IP；省略 / `nil` = `DEFAULT_SERVER` |
| `port` | integer | `0`～`65535`；省略 / `nil` = `DEFAULT_PORT` |
| `timeout_ms` | integer | 必须 `> 0`；省略 / `nil` = `DEFAULT_TIMEOUT` |
| `tz_min` | integer | 时区偏移，**分钟**。省略 / `nil` = 系统当前时区（内部按「时区格 × 15」换算成分钟；读不到则当 `0`） |
| `auto_set` | boolean 或 integer | 见下 |
| 返回值 | string 或 `nil` | 成功为时间串，失败为 `nil` |

`auto_set`：

- 传 **boolean**：`true` 写钟，`false` 不写。
- 传 **integer**：`0` 不写，非 `0` 写。
- 推荐 `true` / `false`。

`tz_min` 举例：`480` = UTC+8，`0` = UTC（返回串不带时区后缀），负数西区。

---

## 6. 模块函数

模块表上只有 `get`。

---

### `ntp.get([server [, port [, timeout_ms [, tz_min [, auto_set]]]]])` {#6-get}

向 NTP 服务器同步要时间。成功返回时间字符串；失败返回 `nil`，不抛错（参数不合法除外）。

中间参数用 `nil` 跳过，后面的仍可传。

**调用模式**

```lua
ntp.get()
```

```lua
ntp.get(nil)
```

```lua
ntp.get(server)
```

```lua
ntp.get(server, nil)
```

```lua
ntp.get(server, port)
```

```lua
ntp.get(server, port, nil)
```

```lua
ntp.get(server, port, timeout_ms)
```

```lua
ntp.get(server, port, timeout_ms, nil)
```

```lua
ntp.get(server, port, timeout_ms, tz_min)
```

```lua
ntp.get(server, port, timeout_ms, tz_min, nil)
```

```lua
ntp.get(server, port, timeout_ms, tz_min, true)
```

```lua
ntp.get(server, port, timeout_ms, tz_min, false)
```

```lua
ntp.get(server, port, timeout_ms, tz_min, 1)
```

```lua
ntp.get(server, port, timeout_ms, tz_min, 0)
```

```lua
ntp.get(nil, nil, nil, nil, true)
```

```lua
ntp.get(nil, nil, timeout_ms)
```

```lua
ntp.get(nil, nil, nil, tz_min)
```

| 参数 | 类型 | 省略时 | 说明 |
| --- | --- | --- | --- |
| `server` | string | `DEFAULT_SERVER` | 非 `nil` 必须是字符串 |
| `port` | integer | `DEFAULT_PORT` | 超出 `0`～`65535` 抛 `invalid port` |
| `timeout_ms` | integer | `DEFAULT_TIMEOUT` | `<= 0` 抛 `invalid timeout` |
| `tz_min` | integer | 系统时区（分钟） | 只影响返回串后缀，不改写入本机的 UTC 秒 |
| `auto_set` | boolean / integer | 不写钟 | `true` / 非 0 则写本机钟 |

**返回**

- 成功：string，见 [第 7 节](#7-返回字符串)
- 失败：`nil`（没网、DNS/UDP 失败、超时、问到了但写钟失败、模块忙不过来）

参数类型不对或端口/超时非法：**抛错**，不是 `nil`。

```lua
local t = ntp.get()
local t = ntp.get("cn.ntp.org.cn")
local t = ntp.get("ntp.ntsc.ac.cn", 123, 8000)
local t = ntp.get("pool.ntp.org", 123, 8000, 480)
local t = ntp.get(nil, nil, nil, nil, true)
```

---

## 7. 返回字符串

成功时数字部分 **始终是 UTC**：

```
YYYY-MM-DD HH:MM:SS
```

`tz_min ~= 0` 时再追加时区后缀（按小时，由分钟整除 60）：

```
YYYY-MM-DD HH:MM:SS +08
YYYY-MM-DD HH:MM:SS -05
```

后缀只作说明，**不会**把前面的时分秒改成本地时间。`tz_min = 480` 得到的仍是 UTC 钟点，后面跟 `+08`。

`tz_min = 0`（含读不到系统时区时的默认）不追加后缀。

写本机钟用的是 UTC Unix 秒，与这串展示是否带后缀无关。

---

## 8. 写本机钟（`auto_set`）

第五参为真时，问询成功且 UTC 秒 `> 0`，会把这次结果写入本机 RAM 时钟，语义与 `sys.set_ts` 相同：

- 置本机时间就绪
- **不**冒充基站 NITZ（`info.nitz_ready()` 不会因此变真）
- **不**触发 `sys.nitz_reg` 的回调

问询成功但写钟失败：整次 `get` 仍返回 `nil`（分不清是没问到还是没写成）。

只想看时间、不改钟：省略第五参或传 `false` / `0`。

---

## 9. 错误与返回约定

| 情况 | 行为 |
| --- | --- |
| 问询成功 | 返回时间字符串 |
| 没网 / DNS 失败 / UDP 失败 / 超时 | `nil` |
| 问询成功但 `auto_set` 写钟失败 | `nil` |
| `port` 不在 `0`～`65535` | 抛 `invalid port` |
| `timeout_ms <= 0` | 抛 `invalid timeout` |
| `server` / `port` / `timeout_ms` / `tz_min` 类型不对 | 抛 Lua 类型错 |
| `auto_set` 既不是 boolean 也不是整数 | 抛类型错 |

没有第二返回值错误串。失败就是 `nil`。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 并发问询 | 1 路 | 第二路等到第一路结束 |
| 单次 UDP 重试 | 最多 3 次 | 失败间隔约 500 ms |
| 默认超时 | 6000 ms | 整次（含 DNS） |
| 单次 recv 下限 | 约 1000 ms | 剩余时间过短时仍按这个量级等 |

无对象、无 `__gc`、无回调槽。不需要持有引用。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 看一眼网络时间 | `ntp.get()` |
| 指定服务器 | `ntp.get("cn.ntp.org.cn")` |
| 拉长超时 | `ntp.get(server, 123, 8000)` |
| 返回串带 +08 后缀 | `ntp.get(server, 123, 6000, 480)` |
| 对时并写入本机 | `ntp.get(nil, nil, nil, nil, true)` |
| 只要 UTC 秒、自己写钟 | `get` 成功后再用其它手段；本模块成功时不单独返回秒 |
| 等基站 NITZ | 用 `sys.nitz_reg`，不是本模块 |
| 周期性对时 | 自己 `rt.delay` 后再 `get` |
| 在回调里对时 | **不要**；丢到独立任务再调 |

---

## 12. 完整示例

与 [examples/NT26/network/ntp/ntp_api](../../../../examples/NT26/network/ntp/ntp_api) 一致。先等驻网，再问内置服务器和若干公网 NTP，最后一次写入本机钟。

```lua
local rt  = require("rt")
local log = require("log")
local ntp = require("ntp")
local lp  = require("lp")

local function ntp_one(tag, ...)
    local t = ntp.get(...)
    if t then
        log.info("%s ok %s", tag, t)
        return true
    end
    log.warn("%s fail", tag)
    return false
end

if not lp.wait_link(60000) then
    log.warn("网络超时，没有网络无法测试 ntp")
    while true do rt.delay(10000) end
end

ntp_one("builtin")
ntp_one("aliyun", "ntp.aliyun.com")
ntp_one("ntsc", "ntp.ntsc.ac.cn", 123, 8000)
ntp_one("cn.ntp.org.cn", "cn.ntp.org.cn", 123, 8000)
ntp_one("pool.ntp.org", "pool.ntp.org", 123, 8000, 480)

ntp_one("auto_set", nil, nil, nil, nil, true)

while true do
    rt.delay(10000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `ntp.get()` | 内置服务器、默认端口/超时/时区 | 时间串或 `nil` |
| `ntp.get(server)` | 指定主机 | 同上 |
| `ntp.get(server, port)` | 指定主机和端口 | 同上 |
| `ntp.get(server, port, timeout_ms)` | 再指定整次超时 | 同上 |
| `ntp.get(server, port, timeout_ms, tz_min)` | 再指定返回串时区后缀 | 同上 |
| `ntp.get(..., auto_set)` | 第五参为真则写本机钟 | 同上；写钟失败也是 `nil` |
| `ntp.get(nil, nil, nil, nil, true)` | 内置服务器并写钟 | 同上 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `ntp.DEFAULT_SERVER` | `"ntp1.aliyun.com"` |
| `ntp.DEFAULT_PORT` | `123` |
| `ntp.DEFAULT_TIMEOUT` | `6000` |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
