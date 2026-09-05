# rtu

**文档版本** `1.1.2`

纯函数模块。用来和模组上 **传统 RTU / DTU 业务** 打交道：AT 或 [`rtu_config.cfg`](../rtu_config/rtu_config.md) 配好的透传通道、串口上下行路由、挂起恢复、以及在这些通道上直接发 TCP/UDP/MQTT。

没有对象。通道 **1～4** 不是 [`tcp.create`](../network/tcp.md) / [`mqtt.create`](../network/mqtt.md) 拉起来的连接，而是固件里已经在跑的四路 RTU 任务。没配通道时 `is_connect` 为 `false`，发送会失败，属正常。

```lua
local rtu = require("rtu")
```

平台预加载模块，无需额外 `.lua` 文件。

Lua 脚本若要自己收 UART / 自己组协议，上电先关本次透传，避免 DTU 把串口数据抢走：

```lua
rtu.option("pass_up", false)
rtu.option("pass_down", false)
```

这两项只改运行时，**不落盘**。重启后回到配置值。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞与回调语义](#3-阻塞与回调语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `rtu.option`](#6-1-option)
  - [6.2 `rtu.write`](#6-2-write)
  - [6.3 `rtu.update_write`](#6-3-update-write)
  - [6.4 `rtu.down_write`](#6-4-down-write)
  - [6.5 `rtu.is_connect`](#6-5-is-connect)
  - [6.6 `rtu.state`](#6-6-state)
  - [6.7 `rtu.control`](#6-7-control)
  - [6.8 `rtu.wait_connect`](#6-8-wait-connect)
  - [6.9 `rtu.socket_sync`](#6-9-socket-sync)
  - [6.10 `rtu.socket_async`](#6-10-socket-async)
  - [6.11 `rtu.mqtt_sync`](#6-11-mqtt-sync)
  - [6.12 `rtu.mqtt_async`](#6-12-mqtt-async)
  - [6.13 `rtu.mqtt_sub`](#6-13-mqtt-sub)
  - [6.14 `rtu.mqtt_unsub`](#6-14-mqtt-unsub)
  - [6.15 `rtu.reg_chcb`](#6-15-reg-chcb)
  - [6.16 `rtu.unreg_chcb`](#6-16-unreg-chcb)
- [7. `option` 键](#7-option-键)
- [8. 路由字符串](#8-路由字符串)
- [9. 通道回调](#9-通道回调)
- [10. 和 `uart` / `tcp` / `mqtt` 的边界](#10-和-uart--tcp--mqtt-的边界)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

传统 RTU 模式里，模组自己完成「串口 ↔ 云通道」透传：UART 上报走各口配置的上行路由，通道下行走该任务的下行路由。通道类型（TCP / UDP / MQTT）、对端、心跳、注册包都由 AT 或配置文件决定，本模块 **不负责建连参数**。

脚本侧做三件事：

1. **开关与查询**：读/写透传使能、扫连接、等上线、挂起/恢复通道。
2. **借用 DTU 路由发数**：`write` 按路由字符串转发（等价 AT `RTUWRITE` 那一类）；`update_write` / `down_write` 分别假装「某路 UART 上报」「某通道下行」，走对应配置路由。后两条 **不看** `pass_up` / `pass_down`。
3. **直连该通道协议栈**：TCP/UDP 用 `socket_*`，MQTT 用 `mqtt_*`；下行和上下线用 `reg_chcb`。

id 一律 **从 1 起**：通道 `1..4`，UART `1..3`。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  option / write / socket_* / mqtt_* / reg_chcb           │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  rtu 模块                                                │
│  · 读运行时或落盘开关                                    │
│  · 解析路由字符串，交给 DTU 输出                         │
│  · 在已配置的通道 1..4 上发 / 订 / 等连接                │
│  · 通道事件进运行时队列，调度循环里调 chcb               │
└──────────────┬───────────────────────────┬──────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────┐       ┌──────────────────────┐
│ 传统 RTU 任务         │       │ 串口 / HTTP / 短信    │
│ 通道 1..4             │       │ 路由号 6 / 5 / 7      │
│ TCP · UDP · MQTT      │       │ 由配置决定实际出口    │
└──────────────────────┘       └──────────────────────┘
```

| 路径 | 当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `option` 读/写 | 改运行时或写配置 | 否 |
| `write` / `update_write` / `down_write` | 入 DTU 输出 | 否（不保证对端已收到） |
| `is_connect` / `state` / `control` | 查或改通道 | 否 |
| `wait_connect` | 已连立刻返回；否则当前协程让出 | **是**（未连时） |
| `socket_sync` / `mqtt_sync` | 等到发出或失败 | **可能较久**，不要在短回调里调 |
| `socket_async` / `mqtt_async` | 入队 | 否（适合回调里回包） |
| `reg_chcb` 回调 | 调度循环里执行 | 必须马上返回 |

同一时刻只有一条 Lua 协程在跑。通道事件和 UART 回调共用 [`rt`](rt.md) 调度循环。

---

## 3. 阻塞与回调语义

**必须在任务协程里调用的**：`wait_connect`（通道未连时会让出）。入口 `main.lua` 顶层算任务协程。禁止在 `uart.reg`、`reg_chcb`、定时器回调里调用。

**不要在短回调里调用的**：`socket_sync`、`mqtt_sync`。回包用 `socket_async` / `mqtt_async`，或 `mbox_send` 到工作协程再发。

**必须马上返回的**：`reg_chcb` 的回调。不要 `delay`、`wait_connect`、`mbox_recv`。

`wait_connect` 的 `timeout_ms` 默认 `-1`（一直等）；`< -1` 按 `-1`。超时返回 `false`。没配通道时不要用无限等，demo 用有限毫秒。

---

## 4. 常量与枚举

模块表 **没有** 整数枚举常量。通道类型、事件名只出现在回调 `meta` 的字符串字段里，见 [第 9 节](#9-通道回调)。

`control` 的 `cmd`、MQTT 的 `qos` / `retain` 用 **整数** `0`/`1`/`2`，不是布尔。`option` 的开关必须是 **真正的 boolean**（`true`/`false`），数字 `0`/`1` 会抛 `bool expected`。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `key` | string | `option` 键，见第 7 节 |
| `bool` | boolean | 仅 `true`/`false` |
| `channel_id` / `id` | integer | 通道 `1..4` |
| `uart_id` | integer | UART `1..3` |
| `route` | string | 路由串，见第 8 节 |
| `data` | string | 可含 `0x00`；部分接口禁止空串 |
| `timeout_ms` | integer | 毫秒；默认 `-1` |
| `cmd` | integer | `0` 挂起 / `1` 恢复 |
| `topic` | string | MQTT 主题 |
| `qos` | integer | `0..2` |
| `retain` | integer | `0` 或 `1` |
| `cb` | function | `cb(channel_id, data, meta)` |

---

## 6. 模块函数

---

### 6.1 `rtu.option(key)` / `rtu.option(key, bool)` {#6-1-option}

读或写透传与 UART 使能。键表见 [第 7 节](#7-option-键)。

**调用模式**

```lua
rtu.option(key)
rtu.option(key, bool)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `key` | 是 | 见第 7 节 |
| `bool` | 写时必填 | 必须是 boolean，不要传 `0`/`1` |

读：成功返回 boolean；失败 `nil, err`（`err` 是整数状态码，常见 `0` 成功、非 0 失败）。

写：返回整数状态码，**`0` 表示成功**。不抛业务错（非法 key / 参数个数 / 第二参不是 boolean 除外）。

失败抛错：

| 文案 | 原因 |
| --- | --- |
| `rtu.option: usage rtu.option(key) or rtu.option(key, bool)` | 参数个数不是 1 或 2 |
| `bool expected` | 第二参不是 boolean |
| `rtu.option: unsupported key` | 未知 key |

```lua
local up = rtu.option("pass_up")
local rc = rtu.option("pass_up", false)   -- rc == 0 才算写成功
```

---

### 6.2 `rtu.write(route, data)` {#6-2-write}

按路由字符串把 `data` 交给 DTU 输出，类似 AT 侧按 `route_str` 写一包。

**调用模式**

```lua
rtu.write(route, data)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `route` | 是 | 路由串；空串表示不选任何出口（仍算解析成功） |
| `data` | 是 | string，允许空 |

解析成功：`true`。不保证对端已收到。非法 `route` **抛** `rtu.write: invalid route_str`。缺参/类型不对也抛。

```lua
rtu.write("1", "hello")
rtu.write("1|2", "hello")
rtu.write("6[1]", "to uart1")
```

---

### 6.3 `rtu.update_write(uart_id, data)` {#6-3-update-write}

假装这包来自 UART1～3 的上报，走该口配置的 **上行路由**。

**调用模式**

```lua
rtu.update_write(uart_id, data)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `uart_id` | 是 | `1..3` |
| `data` | 是 | 长度必须 `> 0` |

成功：`true`。不检查 `pass_up`。越界或空数据抛 `uart_id must be in [1..3]` / `data len must be > 0`。

---

### 6.4 `rtu.down_write(channel_id, data)` {#6-4-down-write}

假装这包来自通道 1～4 的下行，走该任务配置的 **下行路由**（常见是写到某路 UART）。

**调用模式**

```lua
rtu.down_write(channel_id, data)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `channel_id` | 是 | `1..4` |
| `data` | 是 | 长度必须 `> 0` |

成功：`true`。不检查 `pass_down`。越界或空数据抛错。

---

### 6.5 `rtu.is_connect(id)` {#6-5-is-connect}

当前这路 RTU 通道是否已连上。不问「配置里有没有启用」。

**调用模式**

```lua
rtu.is_connect(id)
```

成功：boolean。`id` 必须 `1..4`，否则抛 `id must be in [1..4]`。

---

### 6.6 `rtu.state(id)` {#6-6-state}

`is_connect` 的别名，参数与返回完全相同。

**调用模式**

```lua
rtu.state(id)
```

---

### 6.7 `rtu.control(channel_id, cmd)` {#6-7-control}

挂起或恢复一路 RTU 通道，语义对齐 AT `RTUCTL`。

**调用模式**

```lua
rtu.control(channel_id, 0)
rtu.control(channel_id, 1)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `channel_id` | 是 | `1..4` |
| `cmd` | 是 | 整数：`0` 挂起，`1` 恢复。不要传 boolean |

返回整数：`0` 成功；`-2` 参数；`-3` 通道未启用或类型无效；其它负值为失败。

`cmd` 不是 `0`/`1` 抛 `cmd must be 0(suspend) or 1(resume)`。

---

### 6.8 `rtu.wait_connect(id[, timeout_ms])` {#6-8-wait-connect}

等到该通道上线。已连接则立刻 `true`。

**调用模式**

```lua
rtu.wait_connect(id)
rtu.wait_connect(id, timeout_ms)
```

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 |  | `1..4` |
| `timeout_ms` | 否 | `-1` | `-1` 一直等；超时 `false` |

成功上线：`true`。超时：`false`。必须在任务协程。不判断通道是否启用。

```lua
if rtu.wait_connect(1, 15000) then
    rtu.socket_async(1, "hello")
end
```

---

### 6.9 `rtu.socket_sync(id, data)` {#6-9-socket-sync}

在通道 `id` 的 TCP/UDP 上同步发送。通道必须是套接字类型且已可用。

**调用模式**

```lua
rtu.socket_sync(id, data)
```

`data` 长度必须 `> 0`。返回整数：`>= 0` 为发出字节数；`< 0` 失败（未初始化、参数、状态、未连接等，常见 `-1`～`-8`）。不要在 `reg_chcb` 里调用。

---

### 6.10 `rtu.socket_async(id, data)` {#6-10-socket-async}

异步入队发送。TCP 走发送队列；当前 UDP 仍走同步发出路径。参数与 `socket_sync` 相同。

**调用模式**

```lua
rtu.socket_async(id, data)
```

返回整数：成功常见 `0`（已入队）或 `>= 0`；`< 0` 失败。适合在短回调里回包。

---

### 6.11 `rtu.mqtt_sync(id, topic, data, qos, retain)` {#6-11-mqtt-sync}

在通道 `id` 上同步 PUBLISH。该通道必须是 MQTT 任务。

**调用模式**

```lua
rtu.mqtt_sync(id, topic, data, qos, retain)
rtu.mqtt_sync(id, topic, nil, qos, retain)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | `1..4` |
| `topic` | 是 | 非空 string |
| `data` | 是（可用 `nil`） | string 或 `nil`（空 payload）；空串也当空 payload |
| `qos` | 是 | 整数 `0..2` |
| `retain` | 是 | 整数 `0` 或 `1`，不是 boolean |

`qos` / `retain` **没有默认值**，必须传。返回 `0` 成功，负值为失败。不要在短回调里调用。没有 Lua 侧 `auto_sub`：CONNECT 后的自动订阅由传统 RTU 自己维护。

---

### 6.12 `rtu.mqtt_async(id, topic, data, qos, retain)` {#6-12-mqtt-async}

异步 PUBLISH。参数与 `mqtt_sync` 相同。

**调用模式**

```lua
rtu.mqtt_async(id, topic, data, qos, retain)
rtu.mqtt_async(id, topic, nil, qos, retain)
```

返回整数，`0` 成功。适合回调里回包。

---

### 6.13 `rtu.mqtt_sub(id, topic, qos)` {#6-13-mqtt-sub}

**调用模式**

```lua
rtu.mqtt_sub(id, topic, qos)
```

`qos` 为 `0..2`。返回整数，`0` 成功。只订这一次，不写入 RTU 自动订阅列表。

---

### 6.14 `rtu.mqtt_unsub(id, topic)` {#6-14-mqtt-unsub}

**调用模式**

```lua
rtu.mqtt_unsub(id, topic)
```

返回整数，`0` 成功。

---

### 6.15 `rtu.reg_chcb(channel_id, cb)` {#6-15-reg-chcb}

登记该通道的上下线与下行回调。同一通道再次登记会换掉旧回调。协议见 [第 9 节](#9-通道回调)。

**调用模式**

```lua
rtu.reg_chcb(channel_id, cb)
```

成功：`true`。失败 **抛**：`channel_id must be in [1..4]`、`rtu reg_chcb init fail`、`rt vm context missing`、`rtu reg_chcb full`（最多 16 个登记槽），或 `cb` 不是 function。

登记时若已经连着，会立刻补一次 `event = "online"`（这次可能没有 `host`/`port`）。

---

### 6.16 `rtu.unreg_chcb(channel_id)` {#6-16-unreg-chcb}

**调用模式**

```lua
rtu.unreg_chcb(channel_id)
```

卸掉本脚本在该通道上的回调。成功 `true`；id 非法、上下文没有、或本来没登记：`false`（不抛）。

虚拟机退出时会清掉本 VM 的全部登记。

---

## 7. `option` 键

| 键 | 读/写 | 落盘 | 立刻改运行时 | 含义 |
| --- | --- | --- | --- | --- |
| `pass_up` | 是 | 否 | 是 | 串口数据是否按上行路由透传到通道 |
| `pass_down` | 是 | 否 | 是 | 通道下行是否按下发路由透传出去（常见到串口） |
| `pass_up_cfg` | 是 | **是** | 否 | 配置里的上报透传开关；下次按配置生效 |
| `pass_down_cfg` | 是 | **是** | 否 | 配置里的下发透传开关 |
| `uart2_en_cfg` | 是 | **是** | 否 | UART2 使能，**重启后**生效 |
| `uart3_en_cfg` | 是 | **是** | 否 | UART3 使能，**重启后**生效 |

Lua 自己收 UART 时，把 `pass_up` / `pass_down` 设 `false`。不要随手写 `*_cfg`：那会改 NVM。

`update_write` / `down_write` / `write` / `socket_*` / `mqtt_*` **不受** 这两个运行时开关拦截。

---

## 8. 路由字符串

`rtu.write` 的第一参。通道号 **1～7**，用 `|` 并选多路；`[a:b:c]` 为该通道的子通道（从 1 计）。不写 `[]` 时默认子通道 1。

| 写法 | 含义 |
| --- | --- |
| `"1"` / `"2"` / `"3"` / `"4"` | RTU 任务通道 1～4 |
| 用竖线并选，例如 `"1\|2"` | 同时发到通道 1 和 2 |
| `"1[1:2]"` | 通道 1 的子通道 1 和 2（MQTT 主题槽等） |
| `"6[1]"` `"6[2]"` `"6[3]"` | UART1 / UART2 / UART3 |
| `"5"` | HTTP |
| `"7"` | 短信 |
| `""` | 不选任何出口 |

括号必须成对。通道号重复时后出现的忽略。子通道超出该通道上限则整串非法，抛 `invalid route_str`。

AT 文档里同类例子：`"1|2|3"`、`"1[1:2]|2"`。

---

## 9. 通道回调

```lua
function cb(channel_id, data, meta)
end
```

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `channel_id` | integer | `1..4` |
| `data` | string 或 `nil` | `event == "data"` 时为下行字节；上下线为 `nil` |
| `meta` | table | 见下表 |

| `meta` 字段 | 何时有 | 取值 |
| --- | --- | --- |
| `event` | 总有 | `"online"` / `"offline"` / `"data"` |
| `type` | 总有 | `"tcp"` / `"udp"` / `"mqtt"`；未知为 `"unknown"` |
| `topic` | MQTT 下行 | 订阅主题 |
| `host` | 上下线且带了地址 | 对端主机 |
| `port` | 与 `host` 一起 | 对端端口 |

内部完成事件 **不会** 进 `rt.mbox_recv`。要在协程里处理：回调里 `mbox_send`，工作协程 `mbox_recv`。

空下行不会回调。回调里出错只记日志，不会把异常抛回脚本。

---

## 10. 和 `uart` / `tcp` / `mqtt` 的边界

| | `rtu` | `uart` / `tcp` / `mqtt` |
| --- | --- | --- |
| 连接从哪来 | AT / `rtu_config.cfg` 的四路 RTU 任务 | 脚本 `create`/`open` |
| 串口数据默认去向 | `pass_up` 开着就进 DTU 上行路由 | `uart.reg` / `uart.block` |
| 通道下行默认去向 | `pass_down` 开着就走任务下行路由 | 脚本自己 `write` 串口 |
| 适用 | 传统 DTU 透传上再插一段 Lua | 脚本完全接管链路 |

两套网络客户端不要当成「同一个 id」。Lua `mqtt` 对象的 1～4 路和 RTU 通道 1～4 **不是** 同一张表。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `option` 读 | boolean | `nil, 整数码`；非法 key **抛** |
| `option` 写 | 整数，`0` 成功 | 非 0 整数；非法参数 **抛** |
| `write` / `update_write` / `down_write` | `true` | **抛** |
| `is_connect` / `state` | boolean | id 非法 **抛** |
| `control` / `socket_*` / `mqtt_*` | 整数（`0` 或 `>=0` 视接口） | 负整数；缺参 **抛** |
| `wait_connect` | `true` | 超时 `false`；不在协程 **抛**（与 `rt.delay` 同类） |
| `reg_chcb` | `true` | **抛** |
| `unreg_chcb` | `true` | `false`（无 `err`：未登记或已取消） |

`socket_sync` 成功时返回的是 **发出字节数**（可能大于 0），不要只用 `== 0` 判断。缺参、类型错走 Lua 标准 `bad argument #n`。

**抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `rtu.option: usage rtu.option(key) or rtu.option(key, bool)` | 参数个数不是 1 或 2 |
| `rtu.option: unsupported key` | 键不是 `pass_up` / `pass_down` / `pass_up_cfg` / `pass_down_cfg` / `uart2_en_cfg` / `uart3_en_cfg` |
| `bool expected` | `option` 写值不是 boolean（数字 `0` 在这里**不能**当 false） |
| `rtu.write: invalid route_str` | 路由串解析失败（格式/通道号不对） |
| `rtu reg_chcb init fail` | 通道回调子系统初始化失败 |
| `rt vm context missing` | 不在脚本主虚拟机 / 快捷回调里登记 |
| `rtu reg_chcb full` | 全机登记槽满（16） |
| `channel_id must be in [1..4]` | 通道 id 不是 1～4 |
| `id must be in [1..4]` | 同上（`is_connect` / `socket_*` / `mqtt_*` / `wait_connect`） |
| `uart_id must be in [1..3]` | `update_write` 串口号不是 1～3 |
| `data len must be > 0` | 写出数据长度为 0 |
| `cmd must be 0(suspend) or 1(resume)` | `control` 第二参不是 0/1 |
| `qos must be in [0..2]` | MQTT QoS 越界 |
| `retain must be 0/1` | MQTT retain 不是 0/1 |

**返回的整数码**（不挂在模块表上，不要写成 `rtu.ERR_xxx`）

| 值 | 可能原因 |
| --- | --- |
| `0` | `option` 写 / `control` / MQTT 成功 |
| `-1` | 一般失败（读配置、通道操作被拒） |
| `-2` | 参数不合法 |
| `-3` | 配置缺失 / 未启用（`control`）；MQTT 侧也可能表示 KV 等问题 |
| `-5` | 功能未启用 |
| `-6` | 状态不对：未连接、通道类型不是 socket 等 |
| `-7` | 协议栈未初始化 |
| `-8` | 内存不足 |

`option` 读失败是 `nil, 整数码`（上表）。诊断：先看有没有抛；通道类再看负数；`wait_connect` 只看 `true`/`false`。

---

## 12. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| RTU 任务通道 | **4**（id `1..4`） |
| 业务 UART | **3**（`1..3`） |
| 路由通道号 | **1～7** |
| `reg_chcb` 登记槽 | **16**（全机，按通道+VM） |
| MQTT 主题长 | **128** 字节量级 |
| MQTT payload | 最长 **65535** 字节 |
| `qos` | `0..2` |

通道建连、心跳、注册包、自动订阅列表由传统 RTU 维护，脚本退出不会拆掉这些连接。脚本退出只拆本 VM 的 `reg_chcb`。

`wait_connect` 占用一条 [`rt`](rt.md) 任务协程槽（让出期间）。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| Lua 收串口、不要 DTU 抢走 | `option("pass_up"/"pass_down", false)` + [`uart`](../peripherals/uart.md) |
| 等传统通道上线再发 | `wait_connect` + `socket_async` / `mqtt_async` |
| 按配置路由转发（含 UART/HTTP/短信） | `write(route, data)` |
| 注入「像串口上报 / 像通道下行」 | `update_write` / `down_write` |
| 脚本自己拉 TCP/MQTT | [`tcp`](../network/tcp.md) / [`mqtt`](../network/mqtt.md)，不要用本模块的通道 id |
| 查询 / 等连接 / 回调（不发数） | [examples/NT26/module/rtu/rtu_api](../../../../examples/NT26/module/rtu/rtu_api) |
| UART 指令驱动全部 API | [examples/NT26/module/rtu/rtu_cmd](../../../../examples/NT26/module/rtu/rtu_cmd) |
| 通道 1 下行组帧出 UART1 | [examples/NT26/apps/protocol_pack/rtu_ch1_uart_frame](../../../../examples/NT26/apps/protocol_pack/rtu_ch1_uart_frame) |

---

## 14. 完整示例

关本次透传、等通道 1、异步发一包（通道须已在模组里配成 TCP/UDP）：

```lua
local rt = require("rt")
local rtu = require("rtu")

rtu.option("pass_up", false)
rtu.option("pass_down", false)

rtu.reg_chcb(1, function(id, data, meta)
    meta = meta or {}
    if meta.event == "data" then
        rtu.socket_async(id, data)   -- 短回调里用 async
    end
end)

if rtu.wait_connect(1, 15000) then
    rtu.socket_async(1, "hello")
end

while true do
    rt.delay(10000)
end
```

只查开关和连接、登记日志回调：见 [examples/NT26/module/rtu/rtu_api](../../../../examples/NT26/module/rtu/rtu_api)。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部抛错摘要、整数码与可能原因 |
| 1.1.1 | 2026-09-05 | 定位段链到 `rtu_config.cfg` 语法文档 |
| 1.1.2 | 2026-09-05 | 选型增加通道下行组帧出串口的应用例程 |
