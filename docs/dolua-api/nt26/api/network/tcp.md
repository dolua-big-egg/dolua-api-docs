# tcp

**文档版本** `1.3.1`

全托管 TCP 客户端。字节流、两条线程、阻塞位置和每个参数在哪一步生效见 [概述](#概述)。`create` 建实例并拉起工作线程；`open` 只把目标设成「要连上」。之后连网、断线重连、收包都由内部自动跑，消息和状态用回调回来。全系统最多 `tcp.MAX_CLIENTS` 路（当前 4）。

```lua
local tcp = require("tcp")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [概述](#概述)
  - [这条连接是什么](#这条连接是什么)
  - [两条线程](#两条线程)
  - [阻塞在哪](#阻塞在哪)
  - [轮询间隔](#轮询间隔)
  - [参数在哪一步参与](#参数在哪一步参与)
  - [发送与接收](#发送与接收)
  - [TCP 保活](#tcp-保活)
  - [本模块不做的事](#本模块不做的事)
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
  - [9.3 TLS](#9-3-tls)
- [10. 事件回调](#10-事件回调)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [15. TLS 示例](#15-tls-示例)
- [修订记录](#修订记录)

---

## 概述

这一节讲这条连接实际怎么跑：谁在等、等多久、配置写进去之后在哪一步被读到。脚本接口从 [第 1 节](#1-模块定位) 开始。重连的使用约定见 [第 3 节](#3-目标态与自动重连)。

### 这条连接是什么

本模块是 **TCP 客户端**。它主动去连一台已经在听的服务器，维护一条字节流。整机最多 4 路，每路一条连接。

收到的内容没有「一条消息」这种边界。一次 `data` 回调里的 `ev.data` 是这一轮从套接字里读出来、拼进接收缓冲的字节。对端一次 `send` 多大，和脚本一次看到多长，可以不一致：对端拆开发，这边可能并成一次；对端一次发很多，这边可能按接收缓冲拆成几次。

默认是明文 TCP。`tls_enable = true` 时，TCP 连上之后先做 TLS 握手，`send` / `data` 仍是业务明文。不监听端口，也不做 UDP。要 MQTT 报文、心跳和主题，用 [`mqtt`](mqtt.md)。

### 两条线程

每路客户端两条线程。用户函数 `cb(ev)` 在 Lua 调度循环里，不在这两条线程里。

```
脚本  create / open / send / send_async / close
        │
        ▼
对象层  目标态（要连 / 挂起）、对端和套接字选项的待生效缓存
        │
        ├─ 工作线程（每路一条）
        │    目标=挂起 → 关掉套接字，再堵在「被 open 叫醒」
        │    目标=要连、对端还没写 → 按 poll_interval_ms 空转
        │    目标=要连、未驻网 → 堵在驻网上线事件
        │    目标=要连、已驻网 →
        │         并入待生效参数 → 建套接字 → 解析域名 → connect
        │         → connected
        │         → 循环：select 等可读 → 读进接收缓冲 → 拷进运行时队列
        │         → 读失败 / 对端关闭 / 离网 → 清空未发队列 → disconnected → 再连
        │
        └─ 发送线程（每路一条）
             堵在「有数据要发」
             → 按块写套接字；发送缓冲满了就过 10 ms 再试
             → 写出失败则拆掉这条连接，交给工作线程重连
        │
        ▼
运行时队列 → 调度循环里的 cb(ev)
```

工作线程在投递事件时只把字节 **拷进** 运行时队列，然后继续读套接字。它不等 Lua 把 `cb` 跑完。队列放不下时，这一次事件丢掉，没有另外的 `error`。

`open` 的返回只表示目标已改成「要连」。域名解析、connect、收数据都在工作线程里。`close` 把目标改成挂起，并对套接字做 shutdown，用来打断正在进行的 `select`；同时打一拍事件，用来打断驻网等待和挂起等待。

### 阻塞在哪

下面这些等待都会把对应线程停住。停住期间这条线程不空转，模组可以进低功耗。时间到了就回到主循环再看一次目标态和驻网，不会因此停掉托管。

| 谁在等 | 等什么 | 最长多久 | 什么能提前叫醒 |
| --- | --- | --- | --- |
| 工作线程，目标仍是挂起（`create` 之后，或 `close` 完成之后） | 「要连」或退出 | 10 分钟，到点再看一次目标 | `open` |
| 工作线程，目标是要连、还没驻网 | 驻网上线。离网通知 **不** 叫醒这次等待 | 10 分钟，到点再读一次驻网 | 驻网上线；`close` / `delete` |
| 工作线程，正在 connect | 套接字变为可写 | `connect_timeout_ms`（默认 5000，范围 1000～5000） | 连上、失败或到点 |
| 工作线程，已经连上 | 套接字可读 | **固定 4 秒**。改不了，也不读 `recv_timeout_ms` | 有数据、对端关闭、出错、`close` 的 shutdown |
| 发送线程 | 「队列里有数据」或退出 | 10 分钟。到点若队列里还有数据，照样发出去 | `send_async` 入队 |
| 调用 `send` 的协程 | 这一包按块写完 | 发送缓冲满时每 10 ms 再试，直到写完或连接没了 | 写完或断开 |
| 调用 `close` 的协程 | 工作线程回到挂起并且自己堵在事件上 | 省略时 30000 ms；传入 `<= 0` 时内部用 15000 ms。每 5 ms 看一次 | 线程挂起 |
| 调用 `wait_connect` 的协程 | 调度循环里出现这一路的 `connected` | 省略或 `-1` 一直等 | `connected`，或到点 |

域名解析发生在 connect 之前，锁已经放开。这段时间算在「正在连」里，**不** 计入 `connect_timeout_ms`。`connect_timeout_ms` 只包住非阻塞 connect 发出去之后、等套接字可写的那一次 `select`。

`close` 若正赶上域名解析，要等解析返回，工作线程才会看到「目标已改成挂起」。所以 `close` 的等待偶尔会盖过一次解析，而不只是那 4 秒的可读等待。

### 轮询间隔

`poll_interval_ms` 默认 30，范围 20～10000。它是工作线程 **醒着干活之后的空转**，不是「已连接时多久看一次套接字」。

已连接、没有数据时，节奏是：

1. `select` 堵住，最多 4 秒。
2. 到点且仍驻网：再空转一个 `poll_interval_ms`，回到第 1 步。
3. 这一轮读到了数据：把缓冲读到空（或读满），投递 `data`，**跳过** 这一轮空转，马上再 `select`。

所以空闲连接大约每 4 秒醒一次，外加默认 30 ms。把 `poll_interval_ms` 改成 10 秒，空闲时仍是约 4 秒看一次套接字；变长的是两次 `select` 之间多出来的那一截，以及下面这些未连接时的等待。

`poll_interval_ms` 还用在：

| 场合 | 怎么等 |
| --- | --- |
| 目标是要连，但 host 空或 port 为 0 | 每轮空转 `poll_interval_ms`，等 `update` 或 `open(ip, port)` |
| 连失败后的前 5 秒（高频） | 每次失败空转 `poll_interval_ms` 再试。这 5 秒从离开挂起、开始这一轮连接时算起，固定，改不了 |
| 满 5 秒仍没连上（低频） | 距上次尝试已满 `reconnect_interval_ms`：只再空转一个 `poll_interval_ms` 就重试。还没满：整段睡一个 `reconnect_interval_ms`（不是剩下的零头） |
| 套接字创建失败 | 固定睡 1 秒，与上面两个间隔无关 |
| 已连接且本轮没读到数据 | `select` 返回之后再空转 `poll_interval_ms` |

连上之后，高频/低频都清掉。`close` 再 `open`，重新从高频的 5 秒算起。已经连上又断了，回到「要连」后按同一套节奏再试。

待生效缓存只在 **还没处于已连接** 时并入。已连接期间改 `poll_interval_ms`，当前这条上的空转仍用并入时的旧值，断线后的下一轮才换成新的。

### 参数在哪一步参与

`create` 的第二参和 `update` 写入同一套待生效缓存（`recv_buffer_size` 除外，它在 `create` 时分配，之后改不了）。缓存并入发生在工作线程准备建连、且当前不是已连接的那一步。已连接的这条套接字不热改。

| 配置 | 默认 | 实际参与的位置 |
| --- | --- | --- |
| `host` / `ip`、`port` | 空 / `0` | 并入后用于域名解析和 connect。`ip` 只在没有合法 `host` 时顶上。空 host 或 port 为 0 时不建连，按 `poll_interval_ms` 空转。已连接时 `open(新地址)` 只改缓存，当前这条仍是旧服务器 |
| `connect_timeout_ms` | 5000，钳制在 1000～5000 | 只作为 connect 之后那一次「等可写」的上限。不含域名解析 |
| `reconnect_interval_ms` | 5000，钳制在 1000～60000 | 只在高频 5 秒过去之后的失败间隔里读，见上一节 |
| `poll_interval_ms` | 30，钳制在 20～10000 | 未连接空转、高频重试、低频到点后的短空转、已连接且本轮无数据时 `select` 之后的空转 |
| `link_wait_timeout_ms` | 60000，钳制在 1000～600000 | **会收下并钳制，当前等待不读它。** 没驻网时工作线程堵在上线事件上，上限固定 10 分钟 |
| `recv_buffer_size` | 2048，范围 2048～16384 | 仅 `create`。这一轮 `recv` 的拼包上限。读满就先投递一次 `data`，然后立刻再读 |
| `recv_timeout_ms` | 1000，钳制在 100～30000 | 下次建套接字时写成该套接字的接收超时。已连接后「有没有数据」的等待是固定 4 秒的 `select`，不读这个值。套接字是非阻塞的，读循环遇到「现在没有更多数据」就停 |
| `send_buffer_size` | `0` | `0`：不改系统发送缓冲，单次写出按 2048 字节切块。写成正数：钳制到 2048～16384，下次建套接字时既作为发送缓冲，也作为单次写出的块大小 |
| `tcp_nodelay` | `false` | 下次建套接字。`true` 关掉 Nagle，小包尽快发出；`false` 允许合并小包 |
| `keepalive_enable` 及 `keepalive_idle` / `keepalive_interval` / `keepalive_count` | 开；60 秒 / 10 秒 / 3 次 | 下次建套接字时交给 TCP 保活，见下一节。不改变重连间隔 |

布尔项必须是 `true` / `false`。数字 `0` / `1` 会被忽略，该项保持原值。越界的整数在写入缓存时就钳进上表范围。

### 发送与接收

**同步 `send`**

必须已经连接。调用方占着当前协程，按块写套接字，直到这一包写完，或中途断开。发送缓冲暂满时，放开锁，过 10 ms 再写剩下的。返回值是这次实际写出的字节数；一个字节都没写出去则 `nil, "send failed"`。回调里不要用：调度循环被堵住，别的回调和任务都停。

**异步 `send_async`**

只拷进发送队列就返回。队列按「每条的数据加上条目本身」计字节，上限 **48 KiB**。超限、未连接、未驻网，都是当场 `false, "send_async failed"`，没有单独的失败回调。

发送线程被入队叫醒后，按先进先出逐条、按块写出。某一条写出失败：拆掉套接字、清空整队，工作线程走断开和重连。连接一旦离开「已连接」，队列里还没发出去的直接丢掉，不补发。

因此可能出现：`send_async` 已返回 `true`，随后断线，这条再也发不出去。

**接收**

已连接时工作线程用 4 秒的 `select` 等可读。可读之后，在同一次里连续 `recv`，直到下面任一情况：

- 暂时没有更多数据
- 接收缓冲读满（`recv_buffer_size`）
- 对端关闭或读出错

读到的字节先投递 `data`（此时若对端已关闭，紧接着还有 `disconnected`）。缓冲读满时，投递之后不空转，马上再进下一轮 `select` / `recv`，所以一包比缓冲大时会连续多次 `data`。

`error` 只在仍认为驻网、但读或 `select` 报错时出现，`ev.code` 是当时的套接字错误码。离网导致的读失败上报 `disconnected`，`ev.code` 为 0。`select` 这 4 秒到点时会再看一次驻网；已经不在网就主动拆连接并 `disconnected`，避免套接字还活着、脚本却在离网后继续发。

### TCP 保活

有，而且是套接字上的 **TCP keepalive**，由协议栈发探测，脚本不用周期 `send`。

`keepalive_enable = true`（默认）时，下次建套接字会打开保活，并带上三个数（单位是秒，不是毫秒）：

| key | 默认 | 范围 | 含义 |
| --- | --- | --- | --- |
| `keepalive_idle` | 60 | 1～7200 | 链路上没有任何数据之后，再过多久开始探测 |
| `keepalive_interval` | 10 | 1～300 | 两次探测的间隔 |
| `keepalive_count` | 3 | 1～10 | 连续多少次探测没有回应，协议栈认定这条连接已死 |

默认大约是：静默 60 秒后开始探测，每 10 秒一次，3 次都没有回应则失败。失败之后本模块看到的是读或 `select` 出错，然后按 [第 3 节](#3-目标态与自动重连) 重连。保活不改 `poll_interval_ms`，也不改 `reconnect_interval_ms`。

`keepalive_enable = false` 时，下次建的套接字不打开保活。对端静默断开时，要等本机下一次读或写失败才能发现。已连接期间改这三个数，要等这条断了、下一轮建套接字才生效。

本模块不会替脚本周期发送一段业务数据。平台若要求应用层心跳，由脚本自己 `send_async`。

### 本模块不做的事

| 项 | 实际情况 |
| --- | --- |
| 监听端口 / UDP | 只做 TCP 客户端。加密用 `tls_enable`，见 [9.3](#9-3-tls) |
| 消息边界、粘包拆包 | 只交字节。组帧在脚本里做 |
| 应用层心跳 | 只有 TCP keepalive |
| 断线补发 | 发送队列在离开「已连接」时清空 |
| 用 `link_wait_timeout_ms` 控制等网时长 | 该值会收下。等网堵住的是固定 10 分钟的上线事件 |
| 用 `recv_timeout_ms` 控制已连接时的读等待 | 该值写成套接字接收超时。已连接的读等待是固定 4 秒 |
| 已连接热改地址、保活、Nagle | 都等下一轮建套接字 |

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
   工作线程堵在驻网上线事件上，最长固定 10 分钟，到点再看一次驻网。细节和 `link_wait_timeout_ms` 的实际位置见 [概述 · 阻塞在哪](#阻塞在哪)。不会自己停掉托管。

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

模块表导出客户端上限，以及 TLS 校验级别。事件名是回调里的 **字符串**，不是 `tcp.CONNECTED` 这类符号。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `tcp.MAX_CLIENTS` | `4` | 全系统同时存在的客户端上限 | 对照自己已 `create` 的路数；满员时 `create` 失败 |
| `tcp.TLS_INSECURE` | `1` | 只加密，不校验证书 | `tls_seclevel` |
| `tcp.TLS_SERVER_AUTH` | `2` | 用 CA 校验服务端 | `tls_seclevel`，必须有 `ca_cert` |
| `tcp.TLS_MUTUAL_AUTH` | `3` | 双向校验 | `tls_seclevel`，CA、客户端证书、私钥都要 |

数字 `1` / `2` / `3` 与符号等价。关掉加密用 `tls_enable = false`，不要写 `0`。

事件字符串（`ev.event`）：

| 值 | 含义 |
| --- | --- |
| `"connected"` | 已连上。开了 TLS 时表示握手也完成 |
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
| `poll_interval_ms` | number | 30 | 20～10000 | 未连接空转，以及已连接时 4 秒 `select` 之后的空转。见 [概述](#轮询间隔) |
| `connect_timeout_ms` | number | 5000 | 1000～5000 | 下次 connect 里「等可写」的上限，不含域名解析 |
| `link_wait_timeout_ms` | number | 60000 | 1000～600000 | 收下并钳制。等网堵住的是固定 10 分钟，不读这个值 |
| `recv_timeout_ms` | number | 1000 | 100～30000 | 下次建套接字时写成接收超时。已连接的读等待是固定 4 秒 |
| `send_buffer_size` | number | 0=系统默认，单次按 2048 切块 | 正数则钳到 2048～16384 | 下次建套接字，同时作为单次写出的块大小 |
| `recv_buffer_size` | number | 2048 | 2048～16384 | **仅 create**；一包超长会拆成多次 `data` |
| `keepalive_enable` | **boolean** | `true` | — | 下次创建 socket |
| `keepalive_idle` | number | 60 | 1～7200 秒 | 下次创建 socket |
| `keepalive_interval` | number | 10 | 1～300 秒 | 下次创建 socket |
| `keepalive_count` | number | 3 | 1～10 | 下次创建 socket |
| `tcp_nodelay` | **boolean** | `false` | — | 下次创建 socket（`true`=关 Nagle） |
| `tls_enable` | **boolean** | `false` | 只能是 `true` / `false` | 下次建连。`true` 时 TCP 连上后做 TLS |
| `tls_seclevel` | number | `1` | `1` / `2` / `3` | 下次建连。见 [9.3](#9-3-tls) |
| `tls_hostname` | string | 空，跟随 `host` | 最长 127 字节 | 下次建连。SNI 与证书主机名 |
| `tls_ciphersuite` | number | `65535` | `0`～`65535` | 下次建连。`0` 与 `65535` 都是默认套件 |
| `tls_ignore_time` | **boolean** | `true` | — | 下次建连。`true` 不查证书有效期 |
| `ca_cert` | string 或 `{ ublob = name }` | 无 | CA 最长 6144 字节 | 下次建连 |
| `client_cert` | string 或 `{ ublob = name }` | 无 | 最长 4096 字节 | 下次建连 |
| `client_key` | string 或 `{ ublob = name }` | 无 | 最长 4096 字节 | 下次建连 |

未列出的字段忽略。布尔必须是 `true`/`false`。

### 9.2 已连接时改参

当前这条连接完全不热改。等这条断了、内部重连（或你 `close` 再 `open`）才用上新值。

`open(ip, port)` 等价于先把 host/port 写入缓存再 `open`。

TLS 各项也等下次建连。已经连着明文时要改走 TLS：`update` 写好 `tls_*` 和证书，再 `close` 然后 `open`。

### 9.3 TLS {#9-3-tls}

`tls_enable = false`（默认）时是明文 TCP。`true` 时这条连接在 TCP 三次握手之后做 TLS 握手，通过之后才回调 `connected`。端口不会因为开了 TLS 而改写，对方听 443 就自己写 443。

`send` / `send_async` 写的是业务明文，`data` 回调里的 `ev.data` 是解密后的业务字节。

```lua
local c = tcp.create(on_tcp, {
    host = "tcp.example.com",
    port = 443,
    tls_enable = true,
    tls_seclevel = tcp.TLS_SERVER_AUTH,
    ca_cert = { ublob = "ca.pem" },
})
c:open()
```

证书也可以直接写 PEM 字符串，不经过 ublob：

```lua
c:update({
    tls_enable = true,
    tls_seclevel = tcp.TLS_SERVER_AUTH,
    ca_cert = [[
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
]],
})
```

| `tls_seclevel` | 握手时检查 |
| --- | --- |
| `1` / `tcp.TLS_INSECURE` | 只加密。不看证书。默认就是这一档 |
| `2` / `tcp.TLS_SERVER_AUTH` | 用 CA 校验服务端证书。没有 CA 时 `create` / `update` 失败 |
| `3` / `tcp.TLS_MUTUAL_AUTH` | 再带上客户端证书和私钥。三份缺一则失败 |

`tls_enable` 仍是 `false` 时，可以先把级别和证书写上，这时不检查证书是否齐全。等 `tls_enable = true` 的那一次才检查。检查不通过时，这次表里的证书、开关、级别、主机名、套件和 `tls_ignore_time` 都不会写进去。

SNI 固定打开。没写 `tls_hostname` 或写成空串时，用当前 `host`。连的是 IP、证书上是域名时，把域名写进 `tls_hostname`。

`tls_ciphersuite` 不写、写 `0` 或写 `65535`，都用默认套件。

`tls_ignore_time` 默认 `true`：不查证书有效期，设备没校时也能握上手。要连有效期一起验，写成 `false`。

字符串是 PEM 正文，长度按 Lua string 计算，不在 `\0` 处截断。空串清掉这一份。要从 ublob 读，写成 `{ ublob = 短名 }`。短名最长 95 字节，不能含 `/`、`\`、`:`。`create` / `update` 当时就按短名把证书读进来。名字不存在、是空文件、超长或读失败，调用直接失败。

TLS 开着、并且这份证书是用 `{ ublob = 短名 }` 配的，每次重连握手前会再读一次。换过 ublob 后，下一次重连用新内容。这一次重读失败时，沿用上一份已经读成功的内容，只打日志。内联 PEM 不会在重连时重读。

只加密、不校验：

```lua
c:update({
    port = 443,
    tls_enable = true,
    tls_seclevel = tcp.TLS_INSECURE,
})
```

双向：

```lua
c:update({
    tls_enable = true,
    tls_seclevel = tcp.TLS_MUTUAL_AUTH,
    ca_cert = { ublob = "ca.pem" },
    client_cert = { ublob = "device.pem" },
    client_key = { ublob = "device.key" },
})
```

握手失败走原来的重连，不新增事件。`connected` 表示 TCP 和 TLS 都完成了。

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
| `ev.data` | string | 仅 `data`：业务字节。开了 TLS 时已解密 |
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

### 11.1 接口返回的 `err` 文本

| `err` | 出现在 | 可能原因 |
| --- | --- | --- |
| `callback function required` | `create` | 第 1 参不是 function |
| `rt vm context missing` | `create` | 不在脚本 VM |
| `mutex init failed` | `create` | 系统互斥量没建起来 |
| `tcp client limit reached (max N)` | `create` | 整机已满 4 路（N 为当时上限） |
| `net_tcp_create failed` | `create` | 底层客户端没建起来 |
| `tcp create race` | `create` | 并发抢槽 |
| `invalid tcp client` | 各方法 | 已 `delete` / 被 GC / 不是本对象 |
| `set_param host failed` | `open` | host 没写下发 |
| `set_param port failed` | `open` | port 没写下发 |
| `open failed` | `open` | 没进入「要连」：句柄坏或内部失败 |
| `send failed` | `send` | 未连接或发送失败 |
| `send_async failed` | `send_async` | 未连接或异步排队失败 |
| `tls_enable must be boolean` | `create` / `update` | `tls_enable` 不是 `true` / `false` |
| `tls_seclevel must be 1, 2 or 3` | `create` / `update` | 级别不是 1、2、3 |
| `tls_seclevel 2 requires ca_cert` | `create` / `update` | 开了 TLS 且级别 2，没有 CA |
| `tls_seclevel 3 requires ca_cert, client_cert and client_key` | `create` / `update` | 开了 TLS 且级别 3，三份不齐 |
| `tls_hostname must be string` / `tls_hostname too long` | `create` / `update` | 主机名类型不对或超过 127 字节 |
| `tls_ciphersuite out of range` | `create` / `update` | 不在 `0`～`65535` |
| `tls_ignore_time must be boolean` | `create` / `update` | 不是 `true` / `false` |
| `ca_cert must be pem or {ublob=name}` | `create` / `update` | `client_cert` / `client_key` 同样有对应文案 |
| `ca_cert too large` / `ca_cert ublob not found` | `create` / `update` | 超长，或 ublob 短名不存在。另外两份证书文案相同，只是前缀不同 |

**抛错**：`port required`（`open` 没给端口）、`data required`（`send`/`send_async` 空数据）、`tcp mutex init failed`（模块装载失败）。`wait_connect` 内部还可能抛 `invalid internal wait topic` / `wait must run in coroutine/task` / `wait no task slot`。

### 11.2 回调 `ev.event == "error"` 的 `ev.code`

TCP 的 `ev.code` **不是** 一套稳定的 Lua 枚举，而是套接字层当时的 **errno**（连上/断开/收数据时为 `0`）。非 0 表示协议栈报了错：对端拒绝、重置、超时、未驻网导致连不上等。

诊断：调用当场看 `err` 文本；已经 `open` 却总进 `error`/`disconnected`，先 `lp.wait_link`，再查 host/port。不要把某次看到的 errno 数字写成跨版本契约。

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
| 下行组帧出 UART1 | [examples/nt26/apps/protocol_pack/tcp_uart_frame](../../../../../examples/nt26/apps/protocol_pack/tcp_uart_frame) |
| 加密连一台 TLS 服务器 | [15. TLS 示例](#15-tls-示例) |

---

## 14. 完整示例

与 [examples/nt26/network/tcp/tcp_api](../../../../../examples/nt26/network/tcp/tcp_api) 一致。把 `HOST` / `PORT` 换成你的服务器；测试站见 [tcp.doiot.cn](http://tcp.doiot.cn/)，网页刷新端口会变。

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

## 15. TLS 示例

与 [examples/nt26/network/tcp/tcp_tls](../../../../../examples/nt26/network/tcp/tcp_tls) 一致。连例程里的测试服务器，单向认证用那台服务器自己的自签名证书 `SERVER_CA`。握手成功后发一行 `hello tls`，`data` 里是解密后的业务字节。

`connected` 出现时，TCP 和 TLS 都已经完成。`send` / `send_async` 写业务明文。

```lua
local c = tcp.create(on_tcp, {
    tls_enable = true,
    tls_seclevel = tcp.TLS_SERVER_AUTH,
    tls_ignore_time = true,
    ca_cert = SERVER_CA, -- 服务器自己的证书，完整内容见该例程 main.lua
})
c:open(HOST, PORT)
```

只加密、不校验证书时，把例程开头的 `TLS_AUTH` 改成 `0`，等价于：

```lua
c:update({
    tls_enable = true,
    tls_seclevel = tcp.TLS_INSECURE,
})
```

证书换站就要换根 CA。设备没校时时保持 `tls_ignore_time = true`。例程 `open` 之后不再 `close`，目标保持「要连上」，对端断开后内部自己重连。

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
| `tcp.TLS_INSECURE` | 1 |
| `tcp.TLS_SERVER_AUTH` | 2 |
| `tcp.TLS_MUTUAL_AUTH` | 3 |

事件名为字符串，见第 5 节。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全 `err` 文案；说明回调 `ev.code` 为套接字 errno 及可能原因 |
| 1.1.1 | 2026-09-05 | 选型增加下行组帧出串口的应用例程 |
| 1.2.0 | 2026-10-14 | 增加概述：阻塞位置、轮询与 4 秒读等待、各参数的生效步骤。更正等网为固定 10 分钟，`link_wait_timeout_ms` 当前不参与这次等待 |
| 1.3.0 | 2026-10-16 | TCP 连接可开 TLS：`tls_enable`、校验级别、证书（PEM 字符串或 ublob）、SNI、套件、忽略证书有效期。`connected` 在握手成功之后 |
| 1.3.1 | 2026-10-19 | 增加 TLS 例程 `examples/nt26/network/tcp/tcp_tls`。`TLS_AUTH = 1` 用该服务器自签名证书 `SERVER_CA` 做单向认证，`0` 只加密不校验证书。握手后发 `hello tls`，不断开，断线后按「要连上」自动重连 |
