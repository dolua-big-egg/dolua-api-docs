# tcp

**文档版本** `1.0.1`

全托管 TCP 客户端。`create` 建实例并拉起工作线程；`open` 只把目标设成「要连上」。之后连网、断线重连、收包都由内部自动跑，消息和状态用回调回来。全系统最多 `tcp.MAX_CLIENTS` 路（当前 4）。

```lua
local tcp = require("tcp")
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
  - [`tcp.create`](#7-create)
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

`tcp` 不是“每次自己 `connect` / 掉线再 `connect`”的手搓套接字。它是一条 **托管连接**：

1. `tcp.create(cb[, cfg])` 得到客户端对象，同时拉起专属工作线程（先挂起，这时还不连网）。
2. `c:open(...)` 把目标设成 **要连上**，叫醒线程。成功返回只表示「交给内部了」，不等于已经连上。
3. 连上、断开、收到数据、出错，都通过 `cb(ev)` 回来。
4. 只要目标仍是「要连上」，断线、连不上、掉网，内部自己重试。脚本 **不要** 在 `disconnected` 里再 `open`。

也可以不管驻网，直接 `create` + `open`：没网时内部会等网再连。demo 里先 `lp.wait_link` 只是为了演示时少等一会儿。

对象必须长期持有引用（模块级 `local` 或全局）。丢引用会被回收，连接和线程一起拆掉。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  create(cb) → open(目标=要连) → send / update / close    │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  tcp 对象层                                              │
│  · 最多 4 路客户端                                       │
│  · open / close 只改目标态，不手搓 socket                │
│  · 事件进运行时队列，调度循环里调 cb                     │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  托管工作线程（每路一条）                                 │
│  目标=要连：等网 → 建连 → 收发 → 断了再连               │
│  目标=挂起：主动断开，线程再挂起，停止重连               │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否已经连上 | 谁在跑连接 |
| --- | --- | --- | --- |
| `create` | 建对象 + 拉起线程并挂起 | 否 | 线程在等 `open` |
| `open` | 目标=要连，叫醒线程 | 否（只交托管） | 内部自动连、自动重连 |
| `close` | 目标=挂起，断开并停重连 | 随后断开 | 线程再挂起 |
| `delete` | 销毁对象和线程 | 作废 | — |
| 回调 `cb(ev)` | 调度循环里通知 | 看 `ev.event` | 不在工作线程里跑 Lua |

---

## 3. 目标态与自动重连

### 3.1 两档目标

| 目标 | 谁设定 | 内部行为 |
| --- | --- | --- |
| **要连上** | `open` / `open(ip, port)` | 线程醒来，自己去连；断了继续连 |
| **挂起** | `close`，或尚未 `open` | 不连网；已连则主动断开，停重连 |

`create` 之后默认是挂起。只 `create` 不 `open`，永远不会连。

`open` 的返回值 **不是** 连接结果。连上靠：

- 回调 `ev.event == "connected"`
- 或 `wait_connect`（同步等，少用）

### 3.2 掉线不要再 `open`

目标已经是「要连上」时，对端关掉、收发出错、驻网丢失，内部会：

1. 回调 `disconnected` 或 `error`
2. 状态回到未连接，**目标不变**
3. 立刻再试，再失败则按重连节奏继续

此时再调 `open` **无效**（不会叠两路、不会把现有流程拆掉重建），也容易把业务写成“掉线风暴里反复 open”。只有自己 `close` 过，才需要再 `open`。

### 3.3 重复 `open` 分别做什么

| 当前状况 | `open()` 无参 | `open(新ip, 新port)` |
| --- | --- | --- |
| 已连接 | 空操作，当前连接不动 | 新对端只进缓存；**当前这条还是旧服务器**。等断线内部重连，或先 `close` 再 `open`，新地址才用上 |
| 正在连 / 正在重连 | 再确认一次「继续连」，不叠两路 | 写入新对端到缓存，下次建连才用 |
| `close` 之后 | 第二次连接：线程从挂起醒来，重新托管 | 写入对端并开始托管 |
| 从未 `open` | 用 `create`/`update` 已写的 host/port 开始连 | 写入对端并开始连 |

想立刻换服务器：**先 `close`，再 `open(新ip, 新port)`**（或 `update` 后再无参 `open`）。

### 3.4 重连节奏（`open` 之后、`close` 之前一直有效）

1. **还没驻网**  
   先等网，最长 `link_wait_timeout_ms`（默认 60000，范围 1000～600000）。等到或超时后回到主循环再判断，**不会自己停掉托管**。

2. **对端还没配好**（host 空或 port 为 0）  
   按 `poll_interval_ms` 空转，等你 `update` 或 `open(ip, port)`。

3. **正在连、连失败**（从 `close` 后的第一次 `open` 算起）  
   - 前 5 秒：高频，每隔 `poll_interval_ms`（默认 30，范围 20～10000）再试  
   - 满 5 秒还没连上：低频，每隔 `reconnect_interval_ms`（默认 5000，范围 1000～60000）再试  
   - 这 5 秒固定，改不了。连上后两档清掉；你 `close` 再 `open`，重新从高频开始。

4. **已经连上又断了**  
   上报事件后目标仍是「要连」，内部立刻再试。不要在回调里 `open`。

5. **建 socket 失败**  
   固定等 1 秒再试，与 `reconnect_interval_ms` 无关。

`keepalive_*` 用来发现死连接，发现后仍走上面的自动重连，不改间隔。

低功耗切到不在网档时，TCP 会感应目标并自动挂起，不必先 `close`。见 `lp` 文档 3.5。

---

## 4. 对象模型

```lua
local c, err = tcp.create(on_tcp)
c:open("tcp.doiot.cn", 26429)
```

`create` 返回带元表的 userdata。方法必须通过该对象调用：

```lua
c:open(host, port)      -- 推荐
c.open(c, host, port)   -- 等价
c.open(host, port)      -- 错误
tcp.open(c, host, port) -- 错误：模块表上只有 create
```

必须一直持有 `c`。demo 把它放在模块级 `local c`，回调里才能 `c:send_async`。

---

## 5. 常量与枚举

模块表只导出一个整数常量。事件名是回调里的 **字符串**，不是 `tcp.CONNECTED` 这类符号。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `tcp.MAX_CLIENTS` | `4` | 全系统同时存在的客户端上限 | 对照自己已 `create` 的路数；满员时 `create` 失败 |

事件字符串（`ev.event`）：

| 值 | 含义 |
| --- | --- |
| `"connected"` | 已连上 |
| `"disconnected"` | 已断开（目标仍可能是「要连」，内部会重连） |
| `"data"` | 收到数据 |
| `"error"` | 出错，看 `ev.code` |

`ev.event` 只会是上表四种。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `TcpClient` | userdata | `tcp.create` 成功返回值 |
| `host` / `ip` | string | 非空；域名或 IP，最长 127 字节（超出截断） |
| `port` | integer | 不能为 `0` |
| `cfg` | table | 见 [第 9 节](#9-配置表) |
| `timeout_ms` | integer | `-1` 无限等；`close` 里 `<=0` 表示用内部默认 |
| `ev` | table | 见 [第 10 节](#10-事件回调) |

配置里的布尔项（`keepalive_enable`、`tcp_nodelay`）必须是 **Lua boolean**。数字 `0`/`1` 不会被当成开关（字段会被忽略）。

整数项用 number。`host` / `ip` 必须是非空字符串才写入。

---

## 7. 模块函数

模块表上只有 `create`。工厂函数，不是对象方法。

---

### `tcp.create(cb [, cfg])` {#7-create}

创建客户端：登记回调、拉起工作线程并挂起。此时 **还不连网**。可在任务 / 协程里调用，回调会挂到主虚拟机。

**调用模式**

```lua
tcp.create(cb)
```

```lua
tcp.create(cb, nil)
```

```lua
tcp.create(cb, cfg)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cb` | function | 是 | `function(ev)`，见第 10 节 |
| `cfg` | table | 否 | 填了的 key 覆盖默认；未出现保持默认。见第 9 节 |

`recv_buffer_size` **只能**写在这里（创建时分配接收缓冲）。`update` 传入会被忽略。

`cfg` 里可以带 `host`/`ip` 和 `port`，之后 `c:open()` 无参即可开始连。也可以 create 时不写对端，第一次 `open(host, port)` 再带上。第二参不是 table（含 `nil`）时忽略，等同只传回调。

**返回**

- 成功：`TcpClient`
- 失败：`nil, err`

| `err` | 原因 |
| --- | --- |
| `callback function required` | 第一参不是函数 |
| `rt vm context missing` | 不在合法虚拟机上下文 |
| `mutex init failed` | 模块初始化失败 |
| `tcp client limit reached (max 4)` | 已有 4 路 |
| `net_tcp_create failed` / `tcp create race` | 工作线程拉起失败 |

```lua
local c, err = tcp.create(on_tcp, {
    reconnect_interval_ms = 5000,
    recv_buffer_size = 2048,
})
```

---

## 8. 对象方法

---

### 8.1 `obj:open([ip, port])` {#8-1-open}

把目标设成 **要连上**，叫醒托管线程。成功 `true, "ok"` 只表示交出去了。

**调用模式**

```lua
obj:open()
```

```lua
obj:open(ip, port)
```

| 形态 | 对端怎么处理 |
| --- | --- |
| 无参 | 不改 host/port，用 `create` / `update` / 上次 `open` 已写入的值 |
| `ip, port` | 先写入对端再开始托管。`port` 不能为 `0`（抛 `port required`） |

有参形态必须两个都给：只写 `open(ip)` 会因缺少 `port` 抛错；`port` 为 `0` 抛 `port required`。

**返回**

- 成功：`true, "ok"`
- 失败：`nil, err`（`invalid tcp client` / `set_param host failed` / `set_param port failed` / `open failed`）

重复调用的语义见 [3.3](#33-重复-open-分别做什么)。`disconnected` 里不要调用。

```lua
c:open()                          -- create/update 里已有对端
c:open("tcp.doiot.cn", 26429)
```

---

### 8.2 `obj:close([timeout_ms])` {#8-2-close}

目标改成 **挂起**：主动断开，**停止自动重连**，等工作线程挂起。之后要再连必须再 `open`。

这是“暂停这条托管连接”，不是销毁。定时断开用 `close`，不要 `delete`。

**调用模式**

```lua
obj:close()
```

```lua
obj:close(timeout_ms)
```

```lua
obj:close(nil)
```

```lua
obj:close(0)
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| 省略 / `nil` | 最多等 30000 ms | 等线程挂起 |
| `> 0` | 该毫秒数 | 同上 |
| `<= 0`（含 `0`） | 内部默认约 15 s | — |

回调被业务堵住时，这个等待会变长。正常很快返回。

**返回**

- 成功：`true`
- 失败：`false`，或 `false, "close timeout (thread not suspended)"` / `"close failed"`
- 对象无效：`false`

---

### 8.3 `obj:delete()` {#8-3-delete}

销毁实例和线程，对象作废。正常长期连接 **不必** `delete`；对象被回收时也会走同样清理。

需要间歇断开：用 `close`，线程休眠；再连时 `open`，比反复 create/delete 快。

**调用模式**

```lua
obj:delete()
```

无参数。返回 `true`。之后再调其它方法会失败。

---

### 8.4 `obj:send(data)` {#8-4-send}

同步发送。必须已连接。调用返回前占用当前协程，**不要在回调里用**。

**调用模式**

```lua
obj:send(data)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `data` | string | 是 | 非空；空串抛 `data required` |

**返回**

- 成功：已发送字节数（integer）
- 失败：`nil, "invalid tcp client"` 或 `nil, "send failed"`（未连接等）

---

### 8.5 `obj:send_async(data)` {#8-5-send-async}

只入队，由工作线程发送。回调里回数据用这个。未连接或队列满会失败。

**调用模式**

```lua
obj:send_async(data)
```

`data` 必须非空，否则抛 `data required`。

**返回**

- 成功：`true`
- 失败：`false`，或 `false, "send_async failed"`
- 对象无效：`false`

---

### 8.6 `obj:status()` {#8-6-status}

当前是否已连接。

**调用模式**

```lua
obj:status()
```

**返回** boolean：`true` 已连接；`false` 未连接或对象无效。

日常看回调即可。`status` 适合同步路径里决定要不要 `send`。

---

### 8.7 `obj:wait_connect([timeout_ms])` {#8-7-wait-connect}

阻塞当前协程，直到连上或超时。已连接则立刻 `true`。

会让出当前协程（与 `rt.delay` 同类），必须在任务/协程里调用。正常业务应靠回调推，少用这个。

**调用模式**

```lua
obj:wait_connect()
```

```lua
obj:wait_connect(nil)
```

```lua
obj:wait_connect(-1)
```

```lua
obj:wait_connect(0)
```

```lua
obj:wait_connect(timeout_ms)
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| 省略 / `nil` / `-1` | 无限等 | `< -1` 也按无限等 |
| `>= 0` | 该毫秒数 | 超时返回 `false` |

**返回**

- `true`：已连接或等到 `connected`
- `false`：超时
- 对象无效：`false, "invalid tcp client"`

多条 task 可以同时等同一个 client。

---

### 8.8 `obj:update(cfg)` {#8-8-update}

动态改参。填了的 key 覆盖，没填的保持。除 `recv_buffer_size` 外，都先写入 **待生效缓存**。

**调用模式**

```lua
obj:update(cfg)
```

`cfg` 必须是 table，否则抛类型错。

**返回**

- 成功：`true, "ok"`
- 失败：`nil, "invalid tcp client"`

生效时机见 [第 9 节](#9-配置表)。已连接时改对端/keepalive **不会热改当前这条**。

```lua
c:update({ reconnect_interval_ms = 10000 })
c:update({ host = "tcp.doiot.cn", port = 26429 })
```

---

## 9. 配置表

`create` 的第二参和 `update` 的 `cfg` 认同一套 key（`recv_buffer_size` 仅 create 生效）。

### 9.1 字段

| key | 类型 | 默认 | 范围 | 何时生效 |
| --- | --- | --- | --- | --- |
| `host` | string | 空 | 非空，最长 127 字节 | 下次建连前。优先于 `ip` |
| `ip` | string | 空 | 非空，最长 127 字节 | 没有合法 `host` 时用它 |
| `port` | number | 0 | `!= 0` 才写入 | 下次建连前 |
| `reconnect_interval_ms` | number | 5000 | 1000～60000 | 下次进入未连接、准备建连时 |
| `poll_interval_ms` | number | 30 | 20～10000 | 同上；也是线程空转间隔 |
| `connect_timeout_ms` | number | 5000 | 1000～5000 | 同上，单次 connect 超时 |
| `link_wait_timeout_ms` | number | 60000 | 1000～600000 | 等驻网上限 |
| `recv_timeout_ms` | number | 1000 | 100～30000 | 下次创建 socket |
| `send_buffer_size` | number | 0=系统默认 | — | 下次创建 socket |
| `recv_buffer_size` | number | 2048 | 2048～16384 | **仅 create**；一包超长会拆成多次 `data` |
| `keepalive_enable` | **boolean** | `true` | — | 下次创建 socket |
| `keepalive_idle` | number | 60 | 1～7200 秒 | 下次创建 socket |
| `keepalive_interval` | number | 10 | 1～300 秒 | 下次创建 socket |
| `keepalive_count` | number | 3 | 1～10 | 下次创建 socket |
| `tcp_nodelay` | **boolean** | `false` | — | 下次创建 socket（`true`=关 Nagle） |

未列出的字段忽略。布尔必须是 `true`/`false`。

### 9.2 已连接时改参

当前这条连接完全不热改。等这条断了、内部重连（或你 `close` 再 `open`）才用上新值。

`open(ip, port)` 等价于先把 host/port 写入缓存再 `open`。

---

## 10. 事件回调

```lua
function cb(ev)
```

跑在 Lua **调度循环**里，不是 TCP 工作线程：

- 立刻返回。不要 `rt.delay`、`wait_connect`、同步 `send`。
- 回数据用 `send_async`。
- 不要在 `disconnected` / `error` 里 `open`。

| 字段 | 类型 | 何时有 |
| --- | --- | --- |
| `ev.event` | string | 每次：`connected` / `disconnected` / `data` / `error` |
| `ev.data` | string | 仅 `data`：二进制原文 |
| `ev.code` | integer | `error` 时有意义 |
| `ev.ip` | string | 当前已生效对端（不含尚未合并的 update） |
| `ev.port` | integer | 同上 |
| `ev.client` | userdata | 这个客户端对象 |

业务按 `event` 分支即可。

回调里抛错会被吞掉并记日志。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `create` | userdata | `nil, err` |
| `open` / `update` | `true, "ok"` | `nil, err` |
| `close` | `true` | `false` 或 `false, err` |
| `delete` | `true` | — |
| `send` | integer 字节数 | `nil, err`；空数据抛错 |
| `send_async` | `true` | `false` 或 `false, err`；空数据抛错 |
| `status` | boolean | 无效对象也是 `false` |
| `wait_connect` | `true` | `false` 或 `false, err` |

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 客户端路数 | 4（`tcp.MAX_CLIENTS`） | 整机，跨脚本共享 |
| 接收缓冲 | 2048～16384 | 仅 create |
| `close` 默认等待 | 30000 ms | `0` 则内部约 15 s |
| 高频重连窗 | 固定 5 秒 | 改不了 |

`__gc` 与虚拟机退出会 `delete` 本 VM 的路。脚本必须持有对象。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| 长期连一台服务器 | `create` + `open`，只看回调 |
| 掉线 | 什么都不用做，内部重连 |
| 主动暂停 | `close`；再连再 `open` |
| 立刻换服务器 | `close` 后 `open(新ip, 新port)` |
| 已连接时改重连间隔 | `update`；下一次断线重连才用 |
| 回调里回包 | `send_async` |
| 任务里组完再发 | 已连接时 `send` |
| 必须同步等到连上 | `wait_connect`（少用） |
| 销毁 | 一般不必；用 `close` 即可 |

---

## 14. 完整示例

与 [examples/NT26/network/tcp/tcp_api](../../../../examples/NT26/network/tcp/tcp_api) 一致。把 `HOST` / `PORT` 换成你的服务器；测试站见 [tcp.doiot.cn](http://tcp.doiot.cn/)，网页刷新端口会变。

```lua
local rt  = require("rt")
local log = require("log")
local lp  = require("lp")
local tcp = require("tcp")

local HOST = "tcp.doiot.cn"
local PORT = 26429
local c

local function on_tcp(ev)
    if ev.event == "connected" then
        log.info("event connected ip=%s port=%s", ev.ip, ev.port)
    elseif ev.event == "disconnected" then
        log.info("event disconnected")   -- 不要在这里 open
    elseif ev.event == "error" then
        log.warn("event error code=%s", ev.code)
    elseif ev.event == "data" then
        if ev.data and c then
            c:send_async(ev.data)
        end
    end
end

if not lp.wait_link(60000) then
    log.warn("网络超时")
    while true do rt.delay(10000) end
end

c, err = tcp.create(on_tcp, {
    reconnect_interval_ms = 5000,
    poll_interval_ms = 30,
    connect_timeout_ms = 5000,
    link_wait_timeout_ms = 60000,
    recv_buffer_size = 2048,
    keepalive_enable = true,
    keepalive_idle = 60,
    keepalive_interval = 10,
    keepalive_count = 3,
})
if not c then
    log.error("create fail %s", err)
    return
end

local ok, oerr = c:open(HOST, PORT)
log.info("open %s:%d ok=%s err=%s", HOST, PORT, ok, oerr)

-- 演示同步等连；正式业务靠回调即可
local ready = c:wait_connect(20000)
if c:status() then
    c:send("hello tcp\r\n")
end

c:update({ reconnect_interval_ms = 10000 })

while true do
    log.info("status connected=%s", c:status())
    rt.delay(10000)
end
```

对端关掉连接后日志会看到 `disconnected`，然后内部自己再连，脚本不用再 `open`。

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `tcp.create(cb)` | 建实例，线程挂起 | userdata 或 `nil, err` |
| `tcp.create(cb, cfg)` | 同上并写入初始配置 | 同上 |
| `obj:open()` | 目标=要连，不改对端 | `true, "ok"` 或 `nil, err` |
| `obj:open(ip, port)` | 写入对端，目标=要连 | 同上 |
| `obj:close()` | 目标=挂起，停重连 | `true` / `false[, err]` |
| `obj:close(ms)` / `close(0)` | 同上，自定义/内部等待 | 同上 |
| `obj:delete()` | 销毁 | `true` |
| `obj:send(data)` | 同步发 | 字节数或 `nil, err` |
| `obj:send_async(data)` | 入队发 | `true` / `false[, err]` |
| `obj:status()` | 是否已连接 | boolean |
| `obj:wait_connect([ms])` | 协程等到连上 | boolean |
| `obj:update(cfg)` | 改缓存，下次建连生效 | `true, "ok"` 或 `nil, err` |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `tcp.MAX_CLIENTS` | 4 |

事件名为字符串，见第 5 节。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
