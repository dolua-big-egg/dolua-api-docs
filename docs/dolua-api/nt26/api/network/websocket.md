# websocket

**文档版本** `1.0.0`

全托管 WebSocket 客户端。`open` 把目标设成「要连上」之后，TCP、可选 TLS、HTTP 升级和断线重连都在内部完成。`connected` 只在升级成功之后出现。全系统最多 `websocket.MAX_CLIENTS` 路（当前 4）。

```lua
local websocket = require("websocket")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 目标态与自动重连](#3-目标态与自动重连)
- [4. 对象模型](#4-对象模型)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [`websocket.create`](#websocketcreate)
- [8. 对象方法](#8-对象方法)
  - [8.1 `obj:open`](#8-1-open)
  - [8.2 `obj:close`](#8-2-close)
  - [8.3 `obj:delete`](#8-3-delete)
  - [8.4 `obj:send`](#8-4-send)
  - [8.5 `obj:send_async`](#8-5-send-async)
  - [8.6 `obj:status`](#8-6-status)
  - [8.7 `obj:wait_connect`](#8-7-wait-connect)
  - [8.8 `obj:update`](#8-8-update)
- [9. 配置表](#9-配置表)
- [10. 事件回调](#10-事件回调)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`ws` 是 **WebSocket 客户端**。它去连一台已经在听的服务器，先完成 TCP（需要加密时再完成 TLS），再发 HTTP Upgrade，升级成功后按消息收发文本或二进制。

脚本不自己拼掩码帧，也不在断线后再次 `open`。`open` 成功只表示目标已经是「要连上」。对端断开、升级失败或握手失败时，只要没有 `close`，内部会按重连间隔再走一遍 TCP、TLS 和升级。

明文用 `tls_enable = false`（默认）。`wss` 把 `tls_enable` 设为 `true`，校验级别与 [`tcp`](tcp.md) 相同。本模块不做服务端，也不做压缩扩展。

---

## 2. 框架结构

```
脚本  create / open / send / send_async / close
        │
        ▼
对象层  路径、升级状态、文本/二进制消息
        │
        ▼
连接层  目标态、TCP、可选 TLS、自动重连、发送队列
        │
        ▼
回调    connected / disconnected / data / error
        在 Lua 调度循环里执行，不在连接线程里
```

| 路径 | 谁在跑 | 是否占用 Lua 调度 | 用途 |
| --- | --- | --- | --- |
| `create` / `open` / `close` / `update` | 调用方协程 | 调用期间占用 | 建实例、改目标、改参数 |
| `wait_connect` | 调用方协程 | 让出，直到连上或超时 | 等升级成功 |
| 收包、升级、重连、自动应答 ping | 每路连接自己的线程 | 否 | 保持目标态 |
| `cb(ev)` | Lua 调度循环 | 回调返回前占用 | 业务 |

升级请求使用路径 `path`（默认 `/`）、`Sec-WebSocket-Version: 13`。发出的数据帧带掩码。收到的服务端帧不得带掩码。ping 由内部回 pong，不进回调。对端 close、非法帧或单条消息超过上限时，这次连接拆掉并按目标态重连。

---

## 3. 目标态与自动重连

| 调用 | 目标 | 之后 |
| --- | --- | --- |
| `open` | 要连上 | 未连上就重试；已连上保持 |
| `close` | 挂起 | 拆掉当前连接，停止重连 |
| 对端断开、升级失败、帧错误 | 不变 | 仍是「要连上」则整段重来，包括升级 |

`connected` 的含义是 **升级已经成功**，不是 TCP 刚连上。下一次 `connected` 表示又升级成功了，可以再发业务数据。不要在 `data` 里 `close`，否则目标变成挂起，后面不会重连。

---

## 4. 对象模型

`websocket.create` 返回 userdata。方法用冒号调用。

```lua
local c = websocket.create(cb, cfg)
c:open()
c:send("hello")
```

`c.open(c)` 与 `c:open()` 相同。`c.open()` 少了对象，会报错。

`tls_enable`、`tls_ignore_time` 必须是布尔。`0` / `1` 不能代替 `false` / `true`。

回调和返回的对象都要留在脚本能引用到的地方。局部变量在函数返回后被收掉时，对象会被回收，连接跟着销毁。

---

## 5. 常量与枚举

### 路数

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `websocket.MAX_CLIENTS` | 4 | 全系统同时存在的客户端上限 | 只读 |

### 数据帧类型

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `websocket.TEXT` | 1 | 文本帧 | `send` / `send_async` 的 opcode；`data` 事件的 `ev.opcode` |
| `websocket.BINARY` | 2 | 二进制帧 | 同上 |

不传 opcode 时按文本发送。其它数值会返回 `nil, "opcode must be text or binary"`。

### TLS 校验级别

写入配置表字段 `tls_seclevel`。数值与 [`tcp`](tcp.md) 相同。

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `websocket.TLS_INSECURE` | 1 | 加密，不校验证书 | `tls_seclevel` |
| `websocket.TLS_SERVER_AUTH` | 2 | 用 `ca_cert` 校验服务端 | `tls_seclevel` |
| `websocket.TLS_MUTUAL_AUTH` | 3 | 在单向之上再送客户端证书 | `tls_seclevel` |

### 事件名

回调表字段 `ev.event`，字符串。

| 值 | 含义 |
| --- | --- |
| `"connected"` | 升级成功，可以发送 |
| `"disconnected"` | 曾经升级成功的连接拆掉了。目标仍是「要连上」时会再连 |
| `"data"` | 一条完整消息。`ev.data` 是字符串，`ev.opcode` 是 `websocket.TEXT` 或 `websocket.BINARY` |
| `"error"` | 还没升级成功就失败。`ev.code` 是连接层错误码。升级被拒绝时日志里有原因，随后也会走重连 |

---

## 6. 类型约定

| 文档用名 | Lua 类型 | 合法取值 |
| --- | --- | --- |
| 主机 | string | 非空。域名或 IP。字段名 `host`，没有 `host` 时用 `ip` |
| 端口 | number | 1～65535 |
| 路径 | string | 非空。不以 `/` 开头时内部补上。默认 `/` |
| 载荷 | string | `send` 不允许空串。可含 `\0` |
| opcode | number | `websocket.TEXT` 或 `websocket.BINARY` |
| 超时 | number | `wait_connect` 省略或负数表示一直等；`close` 省略时内部等待 30000 毫秒 |
| PEM | string | `ca_cert` / `client_cert` / `client_key`，整段证书或私钥文本 |

---

## 7. 模块函数

### `websocket.create(callback, config)`

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `callback` | function | 必填。事件回调，签名 `function(ev)` |
| `config` | table | 必填。至少含 `host`（或 `ip`）和 `port`。其余见 [第 9 节](#9-配置表) |

| 结果 | 含义 |
| --- | --- |
| userdata | 已建好，工作线程已拉起，目标仍是挂起，还没去连 |
| `nil, err` | 主机或端口缺失、路数已满、配置不合法、底层创建失败 |

`callback` 不是函数，或 `config` 不是表，直接报错。

创建成功不会自动 `open`。

---

## 8. 对象方法

### 8.1 `obj:open([host, port])` {#8-1-open}

无参：不改已写入的主机和端口，只把目标设成「要连上」。

两参：先写入主机和端口，再设目标。端口为 0 时报错。

| 结果 | 含义 |
| --- | --- |
| `true, "ok"` | 目标已是要连上 |
| `nil, err` | 对象无效，或写入对端失败，或 open 失败 |

### 8.2 `obj:close([timeout_ms])` {#8-2-close}

目标改为挂起，停止重连，并等待当前连接退出。

| 参数 | 说明 |
| --- | --- |
| `timeout_ms` | 可选。等待毫秒。省略为 30000 |

| 结果 | 含义 |
| --- | --- |
| `true` | 已挂起 |
| `false, err` | 对象无效或等待失败 |

### 8.3 `obj:delete()` {#8-3-delete}

销毁这一路，归还名额。返回 `true`。对象被回收时也会销毁。不要在回调里 `delete` 正在回调的这一路。

### 8.4 `obj:send(data[, opcode])` {#8-4-send}

把一条消息入队。`opcode` 省略时为 `websocket.TEXT`。

必须在 `connected` 之后调用。回调里要发送时用 `send_async`，不要用本方法做长阻塞；本方法同样只入队，失败立刻返回。

| 结果 | 含义 |
| --- | --- |
| `true` | 已入队 |
| `nil, err` | 未升级成功、opcode 不对、载荷超过 65535 字节，或发送队列满 |

`data` 为空串直接报错。

### 8.5 `obj:send_async(data[, opcode])` {#8-5-send-async}

与 `send` 相同：入队后返回。回调里发送用这个名字，避免和同步发送混用。

### 8.6 `obj:status()` {#8-6-status}

返回布尔。`true` 表示升级已成功且回调已经发出 `connected`。TCP 刚连上、升级还没完成时是 `false`。

### 8.7 `obj:wait_connect([timeout_ms])` {#8-7-wait-connect}

当前协程等到 `connected`，或超时。已经连着则立刻返回 `true`。

| 参数 | 说明 |
| --- | --- |
| `timeout_ms` | 省略或负数：一直等。`0`：不等待 |

返回布尔。超时或对象无效为 `false`。只在协程里调用。

### 8.8 `obj:update(config)` {#8-8-update}

按 [第 9 节](#9-配置表) 改参数。主机、端口、TLS 在下一轮建连时生效。`path` 在下一轮升级时生效。已升级成功的这一次连接不热切换。

| 结果 | 含义 |
| --- | --- |
| `true, "ok"` | 已写入 |
| `nil, err` | 对象无效或某项不合法 |

`config` 不是表直接报错。

---

## 9. 配置表

`create` 的第二个参数和 `update` 使用同一组字段。没出现的字段保持原值。

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `host` | string | 无 | 对端。`create` 必填（可用 `ip` 代替） |
| `ip` | string | 无 | `host` 不是字符串时采用 |
| `port` | number | 无 | `create` 必填 |
| `path` | string | `"/"` | URL 路径，含查询串时可写在这里，例如 `"/mqtt"` |
| `reconnect_interval_ms` | number | 5000 | 失败后隔多久再连 |
| `tls_enable` | boolean | `false` | `true` 时先做 TLS，再升级。这就是 `wss` |
| `tls_seclevel` | number | 1 | `1` / `2` / `3`，见第 5 节 |
| `tls_ignore_time` | boolean | `true` | `true` 时不因证书过期或未生效而失败 |
| `ca_cert` | string | 无 | PEM。`tls_enable = true` 且级别 ≥ 2 时，这一张表里必须带非空证书 |
| `client_cert` | string | 无 | PEM。级别 3 时与 `client_key` 一起必填 |
| `client_key` | string | 无 | PEM 私钥。级别 3 必填 |

同一张表里 `tls_enable = true` 且 `tls_seclevel >= 2`，但没有非空 `ca_cert`，`create` / `update` 返回 `nil, "tls_seclevel 2 requires ca_cert"`。级别 3 还要求非空 `client_cert` 与 `client_key`。

证书只接受 PEM 字符串。主机名校验沿用连接层：不因证书名字和 `host` 不一致而失败。

80 和 443 的升级请求里，Host 不带端口。其它端口写成 `主机:端口`。

---

## 10. 事件回调

```lua
local function cb(ev)
    if ev.event == "connected" then
        ev.client:send_async("hello")
    elseif ev.event == "data" then
        log.info("ws echo opcode=%d data=%s", ev.opcode, ev.data)
    elseif ev.event == "disconnected" then
        -- 不要在这里 open。目标仍是要连上时会自己重连
    elseif ev.event == "error" then
        log.warn("ws err code=%d", ev.code)
    end
end
```

| 字段 | 出现在 | 说明 |
| --- | --- | --- |
| `event` | 全部 | 第 5 节的事件名 |
| `client` | 全部 | 这一路对象 |
| `data` | `data` | 一条拼完整的消息 |
| `opcode` | `data` | `websocket.TEXT` 或 `websocket.BINARY` |
| `code` | `error` | 连接层错误码 |

分片会被拼成一条再回调。一条消息最长 8192 字节，超出则拆连接并重连。单帧载荷最长 65535 字节。不支持 64 位长度，也不支持 permessage-deflate。

回调里可以 `send_async`。不要在回调里 `wait_connect` 或 `close` 死等。

---

## 11. 错误与返回约定

| 情况 | 行为 |
| --- | --- |
| 参数类型不对（回调、配置表、空载荷、端口 0） | 报错 |
| 路数满、对端缺失、TLS 材料不齐、发送失败 | `nil, err` 或 `false, err` |
| 升级被拒绝、对端 close、帧不合法 | 打日志，拆掉这次连接。若尚未 `connected`，再来一次 `error`；若已经 `connected`，来一次 `disconnected`。目标不变则重连 |
| `wait_connect` 超时 | `false` |

---

## 12. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 同时存在的客户端 | 4 |
| 主机名 | 127 字节 |
| 路径 | 159 字节 |
| 升级响应缓冲 | 4096 字节 |
| 拼好的一条消息 | 8192 字节 |
| 单帧载荷 | 65535 字节 |

每路占用一条连接和它自己的线程，与 `tcp` 的路数分开计数。`delete` 或回收之后名额立即释放。

`close` 之后对象还在，可以再 `open`。`delete` 之后不要再调用方法。

---

## 13. 选型对照

| 需求 | 用 |
| --- | --- |
| 原始字节流、自己组帧 | [`tcp`](tcp.md) |
| WebSocket 文本或二进制 | 本模块 |
| MQTT | [`mqtt`](mqtt.md) |
| 一次 HTTP 请求 | [`http`](http.md) |

---

## 14. 完整示例

长连接公共回声 `ws.postman-echo.com:443`，路径 `/raw`。证书是 RSA。默认只加密、不校验证书，方便在没有根证书时先看通升级和回声。不要在收到数据后 `close`。

工程：[examples/nt26/network/websocket/websocket](../../../../examples/nt26/network/websocket/websocket)。

```lua
local rt = require("rt")
local log = require("log")
local lp = require("lp")
local websocket = require("websocket")

local HOST = "ws.postman-echo.com"
local PORT = 443
local sent = false

local function cb(ev)
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
    log.warn("ws no network")
    while true do
        rt.delay(10000)
    end
end
local c, err = websocket.create(cb, {
    host = HOST,
    port = PORT,
    path = "/raw",
    tls_enable = true,
    tls_seclevel = websocket.TLS_INSECURE,
    tls_ignore_time = true,
})
if not c then
    log.error("ws create fail %s", err)
    while true do
        rt.delay(10000)
    end
end
local ok, why = c:open()
log.info("ws open ok=%s err=%s", ok, why)
while true do
    rt.delay(10000)
end
```

单向认证时把 `tls_seclevel` 改成 `websocket.TLS_SERVER_AUTH`，并在同一张表里放入该服务器的 PEM `ca_cert`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-10-19 | 首版。模块名 `websocket`。升级成功才 `connected`，断线重做升级；`wss` 复用 TLS 级别与 PEM 证书。例程 `examples/nt26/network/websocket/websocket` |
