# mqtt

**文档版本** `1.0.1`

全托管 MQTT 客户端。`create` 建实例并拉起工作线程；`open` 只把目标设成「要连上」。之后连 broker、断线重连、收报文都由内部自动跑，消息和状态用回调回来。全系统最多 4 路。

```lua
local mqtt = require("mqtt")
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
  - [`mqtt.create`](#7-create)
- [8. 对象方法](#8-对象方法)
  - [8.1 `obj:open`](#8-1-open)
  - [8.2 `obj:close`](#8-2-close)
  - [8.3 `obj:delete`](#8-3-delete)
  - [8.4 `obj:sub`](#8-4-sub)
  - [8.5 `obj:unsub`](#8-5-unsub)
  - [8.6 `obj:auto_sub`](#8-6-auto-sub)
  - [8.7 `obj:unsub_auto`](#8-7-unsub-auto)
  - [8.8 `obj:pub`](#8-8-pub)
  - [8.9 `obj:pub_async`](#8-9-pub-async)
  - [8.10 `obj:status`](#8-10-status)
  - [8.11 `obj:wait_connect`](#8-11-wait-connect)
  - [8.12 `obj:update`](#8-12-update)
  - [8.13 `obj:auth`](#8-13-auth)
  - [8.14 `obj:platform`](#8-14-platform)
- [9. 配置表](#9-配置表)
- [10. 订阅：`sub` 与 `auto_sub`](#10-订阅sub-与-auto_sub)
- [11. 事件回调](#11-事件回调)
- [12. OneNET 平台](#12-onenet-平台)
- [13. 错误与返回约定](#13-错误与返回约定)
- [14. 资源上限与生命周期](#14-资源上限与生命周期)
- [15. 选型对照](#15-选型对照)
- [16. 完整示例](#16-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`mqtt` 与 `tcp` 同一套托管模型，不是“每次自己 CONNECT / 掉线再 CONNECT”的手搓客户端：

1. `mqtt.create(cb[, cfg])` 得到客户端对象，同时拉起专属工作线程（先挂起，这时还不连网）。
2. `c:open(...)` 把目标设成 **要连上**，叫醒线程。成功返回只表示「交给内部了」，不等于已经连上。
3. 连上、断开、收到报文、出错、即将建连，都通过 `cb(ev)` 回来。
4. 只要目标仍是「要连上」，断线、连不上、掉网，内部自己重试。脚本 **不要** 在 `disconnected` 里再 `open`。

长期主题用 `auto_sub`：每次 `connected`（含重连）内部会按列表再订一遍。只调 `sub` 不会写入这份列表。

也可以不管驻网，直接 `create` + `open`：没网时内部会等网再连。demo 里先 `lp.wait_link` 只是为了演示时少等一会儿。

对象必须长期持有引用（模块级 `local` 或全局）。丢引用会被回收，连接和线程一起拆掉。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  create(cb) → auto_sub → open(目标=要连)                 │
│             → pub / update / close                       │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  mqtt 对象层                                             │
│  · 最多 4 路客户端                                       │
│  · open / close 只改目标态                               │
│  · auto_sub 列表：每次 connected 后内部再订              │
│  · 事件进运行时队列，调度循环里调 cb                     │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  托管工作线程（每路一条）                                 │
│  目标=要连：等网 → TCP → MQTT CONNECT → 收发 → 断了再连 │
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
| **要连上** | `open` / `open(host, port, ...)` | 线程醒来，自己去连 broker；断了继续连 |
| **挂起** | `close`，或尚未 `open` | 不连网；已连则主动断开 MQTT，停重连 |

`create` 之后默认是挂起。只 `create` 不 `open`，永远不会连。

`open` 的返回值 **不是** 连接结果。连上靠：

- 回调 `ev.event == "connected"`（MQTT CONNACK 成功）
- 或 `wait_connect`（同步等，少用）

### 3.2 掉线不要再 `open`

目标已经是「要连上」时，broker 关掉、收发出错、心跳失败、驻网丢失，内部会：

1. 回调 `disconnected` 或 `error`
2. 状态回到未连接，**目标不变**
3. 立刻再试，再失败则按重连节奏继续

此时再调 `open` **无效**（不会叠两路、不会把现有流程拆掉重建）。只有自己 `close` 过，才需要再 `open`。

`auto_sub` 列表会在再次 `connected` 后由内部订回，也不要在 `disconnected` 里自己 `sub`。

### 3.3 重复 `open` 分别做什么

| 当前状况 | `open()` 无参 | `open(新host, 新port, ...)` |
| --- | --- | --- |
| 已连接 | 空操作，当前连接不动 | 新对端/鉴权只进缓存；**当前这条还是旧 broker**。等断线内部重连，或先 `close` 再 `open`，新地址才用上 |
| 正在连 / 正在重连 | 再确认一次「继续连」，不叠两路 | 写入新对端到缓存，下次建连才用 |
| `close` 之后 | 第二次连接：线程从挂起醒来，重新托管 | 写入对端并开始托管 |
| 从未 `open` | 用 `create`/`update` 已写的 host/port 开始连 | 写入对端并开始连 |

想立刻换 broker：**先 `close`，再 `open(新host, 新port, ...)`**（或 `update` 后再无参 `open`）。

### 3.4 重连节奏（`open` 之后、`close` 之前一直有效）

1. **还没驻网**  
   先等网。等到或超时后回到主循环再判断，**不会自己停掉托管**。

2. **对端还没配好**（host 空或 port 为 0）  
   按 `poll_interval_ms` 空转，等你 `update` 或 `open(host, port, ...)`。

3. **正在连、连失败**（从 `close` 后的第一次 `open` 算起）  
   - 前 5 秒：高频，每隔 `poll_interval_ms`（默认 30，范围 20～10000）再试  
   - 满 5 秒还没连上：低频，每隔 `reconnect_interval_ms`（默认 5000，范围 1000～60000）再试  
   - 这 5 秒固定，改不了。连上后两档清掉；你 `close` 再 `open`，重新从高频开始。

4. **已经连上又断了**  
   上报事件后目标仍是「要连」，内部立刻再试。不要在回调里 `open`。

`keepalive_interval` 是 MQTT 协议心跳（秒），用来发现死连接。发现后仍走上面的自动重连，不改间隔。

`poll_interval_ms` **改了马上用上**，不用等重连。其余多数项等下次建连才合并，见 [第 9 节](#9-配置表)。

低功耗切到不在网档时，MQTT 会感应目标并自动挂起，不必先 `close`。见 `lp` 文档 3.5。

---

## 4. 对象模型

```lua
local c, err = mqtt.create(on_mqtt)
c:open("mqtts.doiot.cn", 1883, client_id, username, password)
```

`create` 返回带元表的 userdata。方法必须通过该对象调用：

```lua
c:open(host, port, id)      -- 推荐
c.open(c, host, port, id)   -- 等价
c.open(host, port, id)      -- 错误
mqtt.open(c, host, port, id) -- 错误：模块表上只有 create
```

必须一直持有 `c`。demo 把它放在模块级 `local c`，回调里才能 `c:pub_async`。

---

## 5. 常量与枚举

模块表 **只导出** `create`，没有整数常量，也没有 `mqtt.CONNECTED` 这类符号。事件名是回调里的 **字符串**。

整机同时存在的客户端上限是 **4**（满员时 `create` 失败，错误串里会写 `max 4`）。这个数字没有挂到模块表。

事件字符串（`ev.event`）：

| 值 | 含义 |
| --- | --- |
| `"pre_connect"` | 即将建 TCP / MQTT 连接前。每次重试都会来 |
| `"connected"` | MQTT CONNACK 成功 |
| `"disconnected"` | 已断开（目标仍可能是「要连」，内部会重连） |
| `"message"` | 收到订阅报文 |
| `"error"` | 出错，看 `ev.code` |

`ev.event` 只会是上表五种。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `MqttClient` | userdata | `mqtt.create` 成功返回值 |
| `host` | string | 非空；域名或 IP。配置里也可写 `server_host` / `ip` |
| `port` | integer | `1`～`65535`。配置里也可写 `server_port` |
| `client_id` | string | 可空串；缓存最长 127 字节 |
| `username` / `password` | string | 可空串；用户名缓存 127 字节，密码/key 255 字节 |
| `topic` | string | 非空 MQTT 主题 |
| `qos` | integer | 仅 `0` / `1` / `2` |
| `retain` | boolean 或 integer | `true`/`false`，或整数（`0` 不保留，非 0 保留） |
| `cfg` | table | 见 [第 9 节](#9-配置表) |
| `timeout_ms` | integer | `-1` 无限等 |
| `ev` | table | 见 [第 11 节](#11-事件回调) |

配置里的布尔项（`clean_session`、`will_enable`、`will_retain`）必须是 **Lua boolean**。数字 `0`/`1` 不会被当成开关（字段会被忽略）。

`pub` / `pub_async` 的 `retain` 可以是 boolean，也可以是整数：`0` 为不保留，其它整数为保留。

`qos` 一律走整数，必须是 `0`/`1`/`2`，否则抛错。

---

## 7. 模块函数

模块表上只有 `create`。工厂函数，不是对象方法。

---

### `mqtt.create(cb [, cfg])` {#7-create}

创建客户端：登记回调、拉起工作线程并挂起。此时 **还不连网**。可在任务 / 协程里调用，回调会挂到主虚拟机。

未写配置时的初始值：host 空、port `1883`、`client_id` 为 `"lua_mqtt"`，其余见 [第 9 节](#9-配置表)。

**调用模式**

```lua
mqtt.create(cb)
```

```lua
mqtt.create(cb, nil)
```

```lua
mqtt.create(cb, cfg)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cb` | function | 是 | `function(ev)`，见第 11 节 |
| `cfg` | table | 否 | 填了的 key 覆盖默认；未出现保持默认。见第 9 节 |

第二参不是 table（含 `nil`）时忽略，等同只传回调。

`cfg` 里可以带 `host`/`port`/`client_id` 等，之后 `c:open()` 无参即可开始连。也可以 create 时不写对端，第一次 `open(host, port, client_id, ...)` 再带上。

**返回**

- 成功：`MqttClient`
- 失败：`nil, err`

| `err` | 原因 |
| --- | --- |
| `callback function required` | 第一参不是函数 |
| `rt vm context missing` | 不在合法虚拟机上下文 |
| `mutex init failed` | 模块初始化失败 |
| `mqtt client limit reached (max 4)` | 已有 4 路 |
| `net_mqtt_create failed` / `net_mqtt_init failed` / `mqtt create race` | 工作线程拉起失败 |
| `apply config failed` | `cfg` 里某项写入失败 |

```lua
local c, err = mqtt.create(on_mqtt, {
    reconnect_interval_ms = 5000,
    keepalive_interval = 60,
    clean_session = true,
})
```

---

## 8. 对象方法

---

### 8.1 `obj:open([host, port, client_id[, username[, password]]])` {#8-1-open}

把目标设成 **要连上**，叫醒托管线程。成功 `true, "ok"` 只表示交出去了。

**调用模式**

```lua
obj:open()
```

```lua
obj:open(host, port, client_id)
```

```lua
obj:open(host, port, client_id, username)
```

```lua
obj:open(host, port, client_id, username, password)
```

| 形态 | 对端怎么处理 |
| --- | --- |
| 无参 | 不改 host/port/鉴权，用 `create` / `update` / 上次 `open` 已写入的值 |
| 有参 | 至少 `host, port, client_id`。`username` / `password` 省略时写成空串 |

`port` 必须在 `1`～`65535`，否则抛 `port must be in [1..65535]`。只写 `open(host, port)` 会因缺少 `client_id` 抛错。

**返回**

- 成功：`true, "ok"`
- 失败：`nil, err`（`invalid mqtt client` / `set_param failed` / `open failed`）

重复调用的语义见 [3.3](#33-重复-open-分别做什么)。`disconnected` 里不要调用。

```lua
c:open()
c:open("mqtts.doiot.cn", 1883, CLIENT_ID)
c:open("mqtts.doiot.cn", 1883, CLIENT_ID, "doiot", "web")
```

---

### 8.2 `obj:close()` {#8-2-close}

目标改成 **挂起**：主动断开 MQTT，**停止自动重连**，工作线程随后挂起。之后要再连必须再 `open`。

这是“暂停这条托管连接”，不是销毁。定时断开用 `close`，不要 `delete`。没有超时参数。

**调用模式**

```lua
obj:close()
```

**返回**

- 成功：`true`
- 失败：`false`，或 `false, "close failed"`
- 对象无效：`false`

---

### 8.3 `obj:delete()` {#8-3-delete}

销毁实例和线程，对象作废。正常长期连接 **不必** `delete`；对象被回收时也会走同样清理。

需要间歇断开：用 `close`，线程休眠；再连时 `open`，比反复 create/delete 快。

**调用模式**

```lua
obj:delete()
```

无参数。返回 `true`（对象已经无效时也返回 `true`）。之后再调其它方法会失败。

---

### 8.4 `obj:sub(topic, qos)` {#8-4-sub}

对 **当前已连接会话** 立刻发 SUBSCRIBE。未连接会失败。

**不会**写入 `auto_sub` 列表。断线重连后不会自动再订。长期主题请用 `auto_sub`，见 [第 10 节](#10-订阅sub-与-auto_sub)。

**调用模式**

```lua
obj:sub(topic, qos)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `topic` | string | 是 | 主题 |
| `qos` | integer | 是 | `0` / `1` / `2`，否则抛 `qos must be in [0..2]` |

**返回**

- 成功：`true`
- 失败：`false, "invalid mqtt client"` 或 `false, "subscribe failed"`（未连接等）

---

### 8.5 `obj:unsub(topic)` {#8-5-unsub}

对当前会话发 UNSUBSCRIBE。**不改** `auto_sub` 列表。列表里还有这项的话，下次 `connected` 仍会再订上。

**调用模式**

```lua
obj:unsub(topic)
```

**返回**

- 成功：`true`
- 失败：`false, "invalid mqtt client"` 或 `false, "unsubscribe failed"`

---

### 8.6 `obj:auto_sub(list)` {#8-6-auto-sub}

全量覆盖自动订阅列表，最多 20 条。每次 `connected`（含掉线重连）后内部按这份列表再订一遍。

只改列表、**不立刻**对当前会话发 SUBSCRIBE。当前已连接又要马上订，再调一次 `sub`。建议在第一次 `open` 之前设好。

**调用模式**（三种合法表形态）

```lua
obj:auto_sub({ { topic = "a/b", qos = 0 } })
```

```lua
obj:auto_sub({ { topic = "a/b", qos = 0 }, { topic = "c/d", qos = 1 } })
```

```lua
obj:auto_sub({ "a/b", "c/d" })
```

```lua
obj:auto_sub({ ["a/b"] = 0, ["c/d"] = 1 })
```

| 表元素 | 含义 |
| --- | --- |
| `{ topic = s, qos = n }` | 推荐。`qos` 缺省当 `0` |
| 字符串 | 主题，QoS 为 `0` |
| `["主题"] = qos` | 键是主题，值是 QoS |

空主题跳过。QoS 不在 `0`～`2`：`false, "auto_sub qos must be in [0..2]"`。超过 20 条：`false, "auto_sub list too large"`。`list` 必须是 table，否则抛类型错。

**返回**

- 成功：`true`
- 失败：`false[, err]`

```lua
c:auto_sub({ { topic = TOPIC_SUB, qos = 0 } })
```

---

### 8.7 `obj:unsub_auto()` {#8-7-unsub-auto}

清空自动订阅列表。已经订上的当前会话 **不会**自动退订；需要的话再 `unsub`。

**调用模式**

```lua
obj:unsub_auto()
```

**返回**

- 成功：`true`
- 失败：`false, "invalid mqtt client"` 或 `false, "unsub_auto failed"`

---

### 8.8 `obj:pub(...)` {#8-8-pub}

同步发布。必须已连接。调用返回前占用当前协程，**不要在回调里用**。

**调用模式**

```lua
obj:pub(topic, payload, qos, retain)
```

```lua
obj:pub(topic, qos, retain)
```

| 形态 | 含义 |
| --- | --- |
| 四参且第二参是 string | 带 payload 发布 |
| 三参且第二参是 number | payload 为空 |

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `topic` | string | 主题 |
| `payload` | string | 可含二进制 |
| `qos` | integer | `0` / `1` / `2`，否则抛错 |
| `retain` | boolean 或 integer | `true`/`false`，或 `0` / 非 0 |

其它参数组合抛 `usage: pub(topic,payload,qos,retain) or pub(topic,qos,retain)`。

**返回**

- 成功：`true`
- 失败：`false, "invalid mqtt client"` 或 `false, "publish failed"`

---

### 8.9 `obj:pub_async(...)` {#8-9-pub-async}

只入队，由工作线程发送。回调里回数据用这个。未连接或队列满会失败。

参数组合与 `pub` **完全相同**：

```lua
obj:pub_async(topic, payload, qos, retain)
```

```lua
obj:pub_async(topic, qos, retain)
```

**返回**

- 成功：`true`
- 失败：`false, "invalid mqtt client"` 或 `false, "publish_async failed"`
- 参数不合法：抛错（与 `pub` 相同）

```lua
c:pub_async(TOPIC_PUB, "ack " .. ev.data, 0, 0)
```

---

### 8.10 `obj:status()` {#8-10-status}

当前是否已完成 MQTT 连接（CONNACK 成功）。

**调用模式**

```lua
obj:status()
```

**返回** boolean：`true` 已连接；`false` 未连接或对象无效。

日常看回调即可。`status` 适合同步路径里决定要不要 `pub`。

---

### 8.11 `obj:wait_connect([timeout_ms])` {#8-11-wait-connect}

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
- 对象无效：`false, "invalid mqtt client"`

多条 task 可以同时等同一个 client。

---

### 8.12 `obj:update(cfg)` {#8-12-update}

动态改参。填了的 key 覆盖，没填的保持。多数项先写入 **待生效缓存**。

**例外**：`poll_interval_ms` 立刻生效。

**调用模式**

```lua
obj:update(cfg)
```

`cfg` 必须是 table，否则抛类型错。

**返回**

- 成功：`true, "ok"`
- 失败：`nil, "invalid mqtt client"` 或 `nil, "update failed"`

已连接时改对端 / 鉴权 / 心跳 / 缓冲 **不会热改当前这条**。立刻换 broker：先 `close`。

```lua
c:update({ reconnect_interval_ms = 10000 })
c:update({ host = "mqtts.doiot.cn", port = 1883 })
```

---

### 8.13 `obj:auth([client_id[, username[, password]]])` {#8-13-auth}

只改鉴权三项。`nil` 或不传的项不改；传字符串（含 `""`）就写入。下次 CONNECT 才用上（已连接不热改）。

`pre_connect` 里可以调：普通模式下这次建连会用上新值。不要在这里 `rt.delay` / `wait_connect` / 同步 `pub`。

**调用模式**

```lua
obj:auth()
```

```lua
obj:auth(client_id)
```

```lua
obj:auth(client_id, username)
```

```lua
obj:auth(client_id, username, password)
```

```lua
obj:auth(nil, nil, password)
```

```lua
obj:auth(nil, username)
```

```lua
obj:auth(nil, username, password)
```

省略与显式 `nil` 相同：该项保持原值。

**返回**

- 成功：`true, "ok"`
- 失败：`nil, err`（`invalid mqtt client` / `set_param failed (...)`）

OneNET 模式下第三参当作 access key **只进缓存**，不会当成明文 MQTT password 下发。见 [第 12 节](#12-onenet-平台)。

---

### 8.14 `obj:platform(mode)` {#8-14-platform}

选择鉴权平台。默认 `"normal"`。

**调用模式**

```lua
obj:platform("normal")
```

```lua
obj:platform("onenet")
```

| `mode` | 含义 |
| --- | --- |
| `"normal"` | 普通 MQTT：`username` / `password` 原样带上 CONNECT |
| `"onenet"` | 中国移动 OneNET：按产品 ID + access key 在每次建连前生成 token |

其它字符串：`nil, "platform must be 'onenet' or 'normal'"`。对象无效：`nil, "invalid mqtt client"`。

成功：`true, "ok"`。

`platfrom` 是同一方法的拼写别名，行为完全相同。新脚本请写 `platform`。

---

## 9. 配置表

`create` 的第二参和 `update` 的 `cfg` 认同一套 key。

### 9.1 字段

| key | 类型 | 默认 | 范围 | 何时生效 |
| --- | --- | --- | --- | --- |
| `server_host` / `host` / `ip` | string | 空 | 非空 | 下次建连前。三者按此优先序取第一个字符串 |
| `server_port` / `port` | number | 1883 | 1～65535 | 下次建连前。先看 `server_port` |
| `client_id` | string | `"lua_mqtt"` | 缓存最长 127 字节 | 下次 CONNECT 前 |
| `username` | string | 空 | 缓存最长 127 字节 | 下次 CONNECT 前 |
| `password` | string | 空 | 缓存最长 255 字节 | 下次 CONNECT 前。OneNET 下当 key，不下发明文 |
| `reconnect_interval_ms` | number | 5000 | 1000～60000 | 下次进入未连接、准备建连时 |
| `poll_interval_ms` | number | 30 | 20～10000 | **立刻生效**；也是高频重连 / 空转间隔 |
| `connect_timeout_ms` | number | 5000 | 1000～5000 | 下次建连前，单次建连超时 |
| `command_timeout_ms` | number | 30000 | 1000～300000 | 下次建连前，协议命令超时 |
| `keepalive_interval` | number | 60 | 10～65535 **秒** | 下次 CONNECT 时带上（协议心跳） |
| `clean_session` | **boolean** | `true` | — | 下次 CONNECT 时带上 |
| `send_buffer_size` | number | 4096 | 2048～16384 | 下次重连时重新分配 |
| `recv_buffer_size` | number | 4096 | 2048～16384 | 下次重连时重新分配 |
| `will_enable` | **boolean** | `false` | — | 下次 CONNECT |
| `will_topic` | string | 空 | — | 下次 CONNECT |
| `will_message` | string | 空 | 最长 4096 字节 | 下次 CONNECT |
| `will_qos` | number | 0 | 0～2 | 下次 CONNECT |
| `will_retain` | **boolean** | `false` | — | 下次 CONNECT |

未列出的字段忽略。布尔必须是 `true`/`false`。`open(host, port, client_id, ...)` 等价于先写入这几项再 `open`。

`recv_buffer_size` 与 TCP 不同：MQTT 可以在 `update` 里改，等下次重连重新分配。

### 9.2 已连接时改参

当前这条连接完全不热改（对端、鉴权、心跳、缓冲都不改）。等这条断了、内部重连（或你 `close` 再 `open`）才用上新值。

`poll_interval_ms` 除外，立刻改空转 / 高频间隔。

---

## 10. 订阅：`sub` 与 `auto_sub`

| | `auto_sub` | `sub` |
| --- | --- | --- |
| 作用对象 | 内部列表 | 当前这一次会话 |
| 何时真正 SUBSCRIBE | 每次 `connected` 之后由内部发 | 调用当场发 |
| 断线重连 | 自动再订 | **不会**再订 |
| 未连接时 | 只改列表，等连上再订 | 失败 |
| 条数 | 最多 20 | 当次一条 |

推荐：第一次 `open` 前 `auto_sub` 写好长期主题。已经连上又要马上订：`auto_sub` 之后再 `sub` 一次。

`unsub` 只退当前会话；列表里还有的话，下次上线仍会订回来。要永久去掉：`unsub_auto` 或用一份更短的列表再 `auto_sub`。

---

## 11. 事件回调

```lua
function cb(ev)
```

跑在 Lua **调度循环**里，不是 MQTT 工作线程：

- 立刻返回。不要 `rt.delay`、`wait_connect`、同步 `pub`。
- 回数据用 `pub_async`。
- 不要在 `disconnected` / `error` 里 `open`。
- `pre_connect` 里可以 `auth` / `update`，不要阻塞。连不上时每次重试都会来一次，不要在这里打刷屏日志。

| 字段 | 类型 | 何时有 |
| --- | --- | --- |
| `ev.event` | string | 每次：见第 5 节 |
| `ev.mqtt_topic` | string | 仅 `message`：收到的主题 |
| `ev.data` | string | 仅 `message`：payload 原文（空 payload 时可能没有此字段） |
| `ev.code` | integer | `error` 时有意义 |
| `ev.client` | userdata | 这个客户端对象 |

业务按 `event` 分支即可。

同一次断线过程里，相同 `code` 的 `error` **只报一次**，直到再次 `connected` 才清掉。所以重连失败不会把回调打爆。

`connected` 之后，内部才会按 `auto_sub` 列表订阅。

回调里抛错会被吞掉并记日志。

---

## 12. OneNET 平台

连中国移动 OneNET 时：

```lua
c:platform("onenet")
c:open(host, port, device_name, product_id, access_key)
```

| 你传入的项 | 含义 |
| --- | --- |
| `client_id` | 设备名 |
| `username` | 产品 ID |
| `password` | access key（Base64）。只缓存，不当明文密码下发 |

每次即将 CONNECT 前，内部用产品 ID + key 算出 token，再作为 MQTT password 带上。脚本不用自己算。

`pre_connect` 里再 `auth`：普通模式这次建连用上新三元组；OneNET 的 token 在回调投递前已按缓存算好，在回调里才改 key 的话，**这次**仍用刚算的 token，下次重连才用新 key。

默认 `"normal"`，三元组原义使用。OneNET 的 access key 请用 `open` / `auth` / `update` 写入（会进缓存）。只写在 `create` 的 `cfg` 里再切 `platform("onenet")`：create 当时按普通模式把 `password` 下发，**不会**进 OneNET 的 key 缓存，token 也算不出来。

---

## 13. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `create` | userdata | `nil, err` |
| `open` / `update` / `auth` / `platform` | `true, "ok"` | `nil, err` |
| `close` | `true` | `false` 或 `false, err` |
| `delete` | `true` | — |
| `sub` / `unsub` / `auto_sub` / `unsub_auto` | `true` | `false[, err]`；QoS/类型不合法会抛错 |
| `pub` / `pub_async` | `true` | `false[, err]`；参数组合/QoS 不合法会抛错 |
| `status` | boolean | 无效对象也是 `false` |
| `wait_connect` | `true` | `false` 或 `false, err` |

---

## 14. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 客户端路数 | 4 | 整机，跨脚本共享；模块表无此常量 |
| 自动订阅 | 20 条 | `auto_sub` 全量覆盖 |
| 发送 / 接收缓冲 | 2048～16384 | 默认 4096；下次重连分配 |
| 遗嘱消息 | 4096 字节 | — |
| 高频重连窗 | 固定 5 秒 | 改不了 |
| `client_id` / `username` 缓存 | 127 字节 | 超出截断 |
| `password` / access key 缓存 | 255 字节 | 超出截断 |

`__gc` 与虚拟机退出会 `delete` 本 VM 的路。脚本必须持有对象。

---

## 15. 选型对照

| 需求 | 做法 |
| --- | --- |
| 长期连一台 broker | `create` + `auto_sub` + `open`，只看回调 |
| 掉线 | 什么都不用做，内部重连；`auto_sub` 会再订 |
| 主动暂停 | `close`；再连再 `open` |
| 立刻换 broker | `close` 后 `open(新host, 新port, ...)` |
| 已连接时改重连间隔 | `update`；下一次断线重连才用 |
| 马上改空转间隔 | `update({ poll_interval_ms = n })` |
| 长期主题 | `auto_sub`，最好在第一次 `open` 前 |
| 当前会话临时订 | `sub`（重连后不会自动再订） |
| 回调里回包 | `pub_async` |
| 任务里组完再发 | 已连接时 `pub` |
| 必须同步等到连上 | `wait_connect`（少用） |
| 动态改三元组 | `auth` 或 `pre_connect` 里 `auth` |
| OneNET | `platform("onenet")` 后再 `open` |
| 销毁 | 一般不必；用 `close` 即可 |

---

## 16. 完整示例

与 [examples/NT26/network/mqtt/mqtt_client](../../../../examples/NT26/network/mqtt/mqtt_client) 一致。测试站见 [mqtts.doiot.cn](http://mqtts.doiot.cn/)，用户名 `doiot`、密码 `web`。`client_id` 用设备 IMEI；网页往 `/server/<IMEI>` 发，模组就能收到。

```lua
local rt   = require("rt")
local log  = require("log")
local lp   = require("lp")
local mqtt = require("mqtt")
local info = require("info")

local HOST = "mqtts.doiot.cn"
local PORT = 1883
local USERNAME = "doiot"
local PASSWORD = "web"
local c
local TOPIC_PUB, TOPIC_SUB, CLIENT_ID

local function on_mqtt(ev)
    if ev.event == "pre_connect" then
        -- 每次重试前都会来；连不上时不要在这里打日志
        -- c:auth(CLIENT_ID, USERNAME, PASSWORD)
    elseif ev.event == "connected" then
        log.info("event connected")
    elseif ev.event == "disconnected" then
        log.info("event disconnected")   -- 不要在这里 open
    elseif ev.event == "error" then
        log.warn("event error code=%s", ev.code)
    elseif ev.event == "message" then
        log.info("event message topic=%s n=%d",
                 ev.mqtt_topic, ev.data and #ev.data or 0)
        if c and TOPIC_PUB then
            c:pub_async(TOPIC_PUB, "ack " .. tostring(ev.data), 0, 0)
        end
    end
end

if not lp.wait_link(60000) then
    log.warn("网络超时")
    while true do rt.delay(10000) end
end

CLIENT_ID = info.imei()
TOPIC_PUB = "/device/" .. CLIENT_ID
TOPIC_SUB = "/server/" .. CLIENT_ID

c, err = mqtt.create(on_mqtt, {
    reconnect_interval_ms = 5000,
    poll_interval_ms = 30,
    connect_timeout_ms = 5000,
    keepalive_interval = 60,
    clean_session = true,
    send_buffer_size = 4096,
    recv_buffer_size = 4096,
})
if not c then
    log.error("create fail %s", err)
    return
end

c:auto_sub({ { topic = TOPIC_SUB, qos = 0 } })

local ok, oerr = c:open(HOST, PORT, CLIENT_ID, USERNAME, PASSWORD)
log.info("open %s:%d ok=%s err=%s", HOST, PORT, ok, oerr)

-- 演示同步等连；正式业务靠回调即可
local ready = c:wait_connect(20000)
if c:status() then
    c:pub(TOPIC_PUB, "hello mqtt", 0, 0)
end

c:update({ reconnect_interval_ms = 10000 })

while true do
    log.info("status connected=%s", c:status())
    rt.delay(10000)
end
```

broker 关掉连接后日志会看到 `disconnected`，然后内部自己再连，脚本不用再 `open`；`auto_sub` 会在再次 `connected` 后自动订回。

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `mqtt.create(cb)` | 建实例，线程挂起 | userdata 或 `nil, err` |
| `mqtt.create(cb, cfg)` | 同上并写入初始配置 | 同上 |
| `obj:open()` | 目标=要连，不改对端 | `true, "ok"` 或 `nil, err` |
| `obj:open(host, port, id[, user[, pass]])` | 写入对端和鉴权，目标=要连 | 同上 |
| `obj:close()` | 目标=挂起，停重连 | `true` / `false[, err]` |
| `obj:delete()` | 销毁 | `true` |
| `obj:auto_sub(list)` | 覆盖自动订阅列表（最多 20） | `true` / `false[, err]` |
| `obj:unsub_auto()` | 清空自动订阅列表 | `true` / `false[, err]` |
| `obj:sub(topic, qos)` | 当前会话立刻订 | `true` / `false[, err]` |
| `obj:unsub(topic)` | 当前会话退订 | `true` / `false[, err]` |
| `obj:pub(topic, payload, qos, retain)` | 同步发布 | `true` / `false[, err]` |
| `obj:pub(topic, qos, retain)` | 同步发布空 payload | 同上 |
| `obj:pub_async(...)` | 入队发布（参数同 `pub`） | 同上 |
| `obj:status()` | 是否已 MQTT 连接 | boolean |
| `obj:wait_connect([ms])` | 协程等到连上 | boolean |
| `obj:update(cfg)` | 改缓存；`poll_interval_ms` 立刻生效 | `true, "ok"` 或 `nil, err` |
| `obj:auth(...)` | 改三元组，`nil` 的项不改 | `true, "ok"` 或 `nil, err` |
| `obj:platform("normal"\|"onenet")` | 鉴权平台 | `true, "ok"` 或 `nil, err` |

## 附录 B. 枚举值一览

模块表没有整数常量。事件名为字符串，见第 5 节。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
