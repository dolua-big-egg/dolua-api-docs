# dns

**文档版本** `1.0.1`

读/改当前生效的 DNS 服务器，并做同步域名解析。纯函数模块：没有对象、没有回调、没有后台解析任务。

```lua
local dns = require("dns")
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
  - [6.1 `dns.get`](#6-1-get)
  - [6.2 `dns.set`](#6-2-set)
  - [6.3 `dns.resolve`](#6-3-resolve)
  - [6.4 `dns.clear_cache`](#6-4-clear-cache)
  - [6.5 `dns.active_cid`](#6-5-active-cid)
  - [6.6 `dns.cids`](#6-6-cids)
- [7. 错误与返回约定](#7-错误与返回约定)
- [8. 资源上限与生命周期](#8-资源上限与生命周期)
- [9. 选型对照](#9-选型对照)
- [10. 完整示例](#10-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

开机默认用运营商下发的 DNS（PCO）。本模块用来查看这份列表、临时换成公共 DNS，以及自己解析一个主机名。

1. **解析、改服务器都要已经能上网。** 可先 `lp.wait_link`。
2. TCP / MQTT / HTTP 自己会解析主机名，一般不必先调 `dns.resolve`。本模块适合：看当前用哪台 DNS、改成 `223.5.5.5`、或只要一个 IPv4 字符串。
3. `dns.set` 是运行期覆盖：**掉电不保存**；重拨后仍优先于运营商下发。改完请 `clear_cache`，否则 `resolve` 可能还拿旧结果。
4. CID 一般就是 `1`。省略 `cid` 时用 `dns.DEFAULT_CID`。

不要在 UART / MQTT / TCP 回调里调用 `resolve`：会占住整条 Lua 引擎线程。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  get / set / resolve / clear_cache / active_cid / cids   │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  dns 模块                                                │
│  · 按 CID 读、写当前生效的服务器列表                      │
│  · resolve：同步问询，只取第一个 IPv4                     │
│  · 全系统同时一路，resolve 结束前其它 dns 调用要等         │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  数据承载（PDP / CID）                                    │
│  默认 CID=1。未驻网时 get/set/resolve 会失败              │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 要不要网 |
| --- | --- | --- | --- |
| `get` | 读当前 DNS 列表 | 否 | 通常要已激活的 CID |
| `set` | 覆盖列表 | 否 | 要已激活的 CID |
| `resolve` | 同步解析，阻塞到出结果或失败 | **否** | **必须**已驻网 |
| `clear_cache` | 清解析缓存 | 否 | 协议栈已起来即可 |
| `active_cid` / `cids` | 读承载状态 | 否 | 未联网多为 `nil` |

---

## 3. 阻塞语义

`resolve` **不是** `rt.delay` 那种让出：当前协程停住，其它 Lua 任务、定时器、IO 回调都要等它结束。超时由协议栈决定，站点慢时会卡住一整次调用。

全系统同时只能跑 **一路** DNS 操作。`resolve` 进行时，另一路 `get`/`set`/`resolve` 会等到这一路返回，而不是并行打两份包。

`get` / `set` / `clear_cache` / `cids` 本身很快，但仍不要放在短回调里。

---

## 4. 常量与枚举

模块表只导出一个整数常量：

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `dns.DEFAULT_CID` | `1` | 默认数据承载 | `get` / `set` / `resolve` 省略 `cid` 时 |

没有错误码符号。失败靠 `nil`/`false` 加英文短句。

`cids()` 里每项的 `state` 是整数，**未挂成模块常量**：

| 值 | 含义 |
| --- | --- |
| `0` | 未激活 |
| `1` | 已激活 |

其它 state 不要当可用档位。CID 编号常见 `0`～`15`；绑定允许 `0`～`255`，越界抛 `"invalid cid"`。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `cid` | integer | `0`～`255`；省略 / `nil` = `DEFAULT_CID` |
| `host` | string | 主机名；不能为空 |
| `server` | string | IPv4/IPv6 点分地址，不能是 `0.0.0.0` 这类 any |
| `servers` | table（数组） | 1 起下标的地址字符串，长度 1～4 |
| `all` | boolean | 仅 `true`/`false`。**不要传数字 `0`/`1`**：`clear_cache` 用 `lua_isboolean` 判断第一参 |

`cid` 走 **integer**。`clear_cache` 的「清全部」必须是真正的 boolean，数字会被当成主机名。

---

## 6. 模块函数

模块表：`get`、`set`、`resolve`、`clear_cache`、`active_cid`、`cids`。

---

### 6.1 `dns.get([cid])` {#6-1-get}

读指定 CID **当前生效** 的 DNS 列表（运营商下发，或被 `set` 覆盖后的）。成功返回 1 起下标的字符串数组，常见长度 2。

**调用模式**

```lua
dns.get()
```

```lua
dns.get(nil)
```

```lua
dns.get(cid)
```

**返回**

- 成功：`{ "x.x.x.x", ... }`，可能短于 4
- 失败：`nil, err`（`"get dns fail"` 或 `"mutex fail"`）

```lua
local servers, err = dns.get()
if servers then
    log.info("DNS1=%s DNS2=%s", servers[1], servers[2])
end
```

---

### 6.2 `dns.set(...)` {#6-2-set}

临时覆盖该 CID 的 DNS。至少 1 个地址，最多 **4** 个。末尾若是 integer，当作 `cid`。

掉电不保存。重拨后这份覆盖仍优先于运营商 PCO。非法地址（解析不成 IP、或 any 地址）**不抛错**，返回 `false, "set dns fail"`。不是字符串的项会抛类型错。一个参数都没有：抛 `"dns.set requires at least one server"`。

**调用模式**

```lua
dns.set(primary)
```

```lua
dns.set(primary, secondary)
```

```lua
dns.set(primary, secondary, cid)
```

```lua
dns.set({ primary, secondary })
```

```lua
dns.set({ primary, secondary }, cid)
```

位置参数还可以继续填到 4 个地址，再在末尾加 `cid`。超过 4 个的位置参数会被丢掉。表长度不是 1～4：抛 `"invalid dns table"`。

**返回**

- 成功：`true`
- 失败：`false, err`

```lua
local ok, serr = dns.set("223.5.5.5", "223.6.6.6")
dns.set({ "8.8.8.8", "8.8.4.4" })
dns.set("223.5.5.5", "223.6.6.6", 1)
```

改完后应 `dns.clear_cache(true)`，再 `resolve`。

---

### 6.3 `dns.resolve(host[, cid])` {#6-3-resolve}

同步解析，返回 **第一个 IPv4** 字符串。不返回 IPv6、不返回地址列表。

`host` 必填。空串会失败。占用当前协程直到结束。

**调用模式**

```lua
dns.resolve(host)
```

```lua
dns.resolve(host, nil)
```

```lua
dns.resolve(host, cid)
```

**返回**

- 成功：如 `"1.2.3.4"`
- 失败：`nil, err`（`"resolve fail"` 或 `"mutex fail"`）

```lua
local ip, rerr = dns.resolve("www.baidu.com")
local ip2 = dns.resolve("www.5giot.cn", 1)
```

---

### 6.4 `dns.clear_cache([all[, host]])` {#6-4-clear-cache}

清协议栈 DNS 缓存。`set` 之后、想强制重新问服务器时用。

**调用模式**

```lua
dns.clear_cache()
```

```lua
dns.clear_cache(true)
```

```lua
dns.clear_cache(false, host)
```

```lua
dns.clear_cache(host)
```

| 写法 | 行为 |
| --- | --- |
| 省略 | 清全部 |
| `true` | 清全部 |
| `false, host` | 只清该主机名 |
| 只传字符串 | 只清该主机名 |

`clear_cache(false)` 且不给 `host`：失败（`"clear cache fail"`）。

第一参若是数字，不会被当成「清全部」，会按主机名处理。请用 `true`/`false`。

**返回**

- 成功：`true`
- 失败：`false, err`

```lua
dns.clear_cache()
dns.clear_cache(true)
dns.clear_cache("www.baidu.com")
dns.clear_cache(false, "www.baidu.com")
```

---

### 6.5 `dns.active_cid()` {#6-5-active-cid}

当前应使用的 CID：优先 `DEFAULT_CID`（1），否则第一个已激活的。未联网或读失败：`nil`（没有第二返回值）。

**调用模式**

```lua
dns.active_cid()
```

```lua
local cid = dns.active_cid() or dns.DEFAULT_CID
```

---

### 6.6 `dns.cids()` {#6-6-cids}

各 CID 激活状态。成功返回数组；失败 `nil`（没有第二返回值）。最多 16 项。

**调用模式**

```lua
dns.cids()
```

每项：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `cid` | integer | 承载号 |
| `state` | integer | `0` 未激活，`1` 已激活 |

```lua
local list = dns.cids()
if list then
    for i, item in ipairs(list) do
        log.info("cid=%s state=%s", item.cid, item.state)
    end
end
```

---

## 7. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `get` | 地址数组 | `nil, err` |
| `set` | `true` | `false, err` |
| `resolve` | IPv4 字符串 | `nil, err` |
| `clear_cache` | `true` | `false, err` |
| `active_cid` | integer | `nil` |
| `cids` | 状态数组 | `nil` |

类型错、缺参、非法 `cid`、空 `set`、非法 DNS 表：抛 Lua 错，不是 `nil`/`false`。

常见 `err` 短句：`"get dns fail"`、`"set dns fail"`、`"resolve fail"`、`"clear cache fail"`、`"mutex fail"`。

---

## 8. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 一次 `set` 的服务器数 | 4 | 表长度也必须 1～4 |
| `get` 读回条数 | 最多 4 | |
| 主机名 | 256 字节量级 | 空串不可解析 |
| IP 字符串 | 最长约 63 个可见字符 | |
| CID 表 | 16 | `cids()` |
| 并发 DNS 操作 | 1 路 | 第二路等待 |
| `set` 持久化 | 运行期 + 重拨仍有效 | **掉电丢失** |

无对象、无回调。不必持有引用。

---

## 9. 选型对照

| 需求 | 做法 |
| --- | --- |
| 看运营商给了哪些 DNS | `dns.get()` |
| 改成公共 DNS | `dns.set("223.5.5.5", "223.6.6.6")` 再 `clear_cache(true)` |
| 只要一个 IPv4 | `dns.resolve(host)` |
| HTTP/MQTT 连域名 | 直接把主机名给它们，不必先 resolve |
| 未联网就解析 | 会失败；先 `lp.wait_link` |
| 在回调里 resolve | **不要** |

---

## 10. 完整示例

与仓库 [examples/NT26/network/dns/dns_api](../../../../examples/NT26/network/dns/dns_api) 一致：等网 → 读 CID → 读 PCO DNS 并解析 → 改成阿里 DNS、清缓存再解析。

```lua
local rt  = require("rt")
local log = require("log")
local lp  = require("lp")
local dns = require("dns")

if not lp.wait_link(60000) then
    log.warn("网络超时，没有网络无法测试 dns")
    while true do
        rt.delay(10000)
    end
end

local cid = dns.active_cid() or dns.DEFAULT_CID
log.info("active_cid=%s", cid)

local list = dns.cids()
if list then
    for i, item in ipairs(list) do
        log.info("cids[%d] cid=%s state=%s", i, item.cid, item.state)
    end
end

local servers, err = dns.get()
if servers then
    log.info("DNS1=%s DNS2=%s", servers[1], servers[2])
end

local ip, rerr = dns.resolve("www.5giot.cn", cid)
log.info("www.5giot.cn ip=%s err=%s", ip, rerr)

local ok, serr = dns.set("223.5.5.5", "223.6.6.6")
log.info("set ok=%s err=%s", ok, serr)
dns.clear_cache(true)

ip, rerr = dns.resolve("www.baidu.com", cid)
log.info("www.baidu.com ip=%s err=%s", ip, rerr)

while true do
    dns.clear_cache(true)
    ip, rerr = dns.resolve("www.baidu.com", cid)
    log.info("www.baidu.com ip=%s err=%s", ip, rerr)
    rt.delay(10000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `dns.get()` | 读默认 CID 的 DNS | 数组或 `nil, err` |
| `dns.get(cid)` | 读指定 CID | 同上 |
| `dns.set(primary[, secondary[, cid]])` | 覆盖 | `true` 或 `false, err` |
| `dns.set({ ... }[, cid])` | 表形式覆盖 | 同上 |
| `dns.resolve(host[, cid])` | 同步解析 IPv4 | 字符串或 `nil, err` |
| `dns.clear_cache()` / `true` | 清全部缓存 | `true` 或 `false, err` |
| `dns.clear_cache(host)` | 清一个主机 | 同上 |
| `dns.clear_cache(false, host)` | 同上 | 同上 |
| `dns.active_cid()` | 当前 CID | integer 或 `nil` |
| `dns.cids()` | 各 CID 状态 | 数组或 `nil` |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `dns.DEFAULT_CID` | 1 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
