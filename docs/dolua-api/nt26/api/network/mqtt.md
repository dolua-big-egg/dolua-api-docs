# mqtt

**文档版本** `2.0.1`

全托管 MQTT 3.1.1 客户端。协议能力、心跳、重发边界和云平台适配见 [概述](#概述)。`create` 建实例并拉起工作线程；`open` 只把目标设成「要连上」。之后连 broker、断线重连、收报文都由内部自动跑，消息和状态用回调回来。全系统最多 4 路。

```lua
local mqtt = require("mqtt")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [概述](#概述)
  - [MQTT 是什么](#mqtt-是什么)
  - [协议版本](#协议版本)
  - [支持的特性](#支持的特性)
  - [协议心跳](#协议心跳)
  - [确认与重发](#确认与重发)
  - [未实现的特性](#未实现的特性)
  - [实现机制](#实现机制)
  - [消息调度](#消息调度)
  - [云平台适配](#云平台适配)
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
  - [9.3 MQTTS](#9-3-mqtts)
- [10. 订阅：`sub` 与 `auto_sub`](#10-订阅sub-与-auto_sub)
- [11. 事件回调](#11-事件回调)
- [12. OneNET 平台](#12-onenet-平台)
- [13. 错误与返回约定](#13-错误与返回约定)
- [14. 资源上限与生命周期](#14-资源上限与生命周期)
- [15. 选型对照](#15-选型对照)
- [16. 完整示例](#16-完整示例)
- [修订记录](#修订记录)

---

## 概述

这一节讲协议本身，以及本模块实际做到哪一步。后面的章节才是脚本接口。连接托管、重连节奏见 [第 3 节](#3-目标态与自动重连)。

### MQTT 是什么

MQTT 是跑在 TCP 上的发布/订阅协议。设备不互相直连，只和一台 **broker**（服务器）保持一条连接。发出去的数据叫 **发布**（PUBLISH），想收哪类数据就 **订阅**（SUBSCRIBE）对应的 **主题**（topic）。主题是用 `/` 分段的字符串，例如 `/device/864000000000001`。broker 按主题把报文转给当前订了这个主题的客户端。

和 HTTP 的差别：没有「请求—响应」这一对。谁发、谁收，只由主题决定。连接要长期留着；空闲时靠心跳判断对端是否还活着。

一条 MQTT 会话里常见的角色：

| 概念 | 作用 |
| --- | --- |
| ClientId | broker 用来区分设备。相同 ClientId 后连上的会话会把先连上的踢掉 |
| 用户名 / 密码 | CONNECT 里的鉴权。有的云把密码换成算出来的 token |
| QoS | 这一条发布要不要等确认。0 不等，1 等 PUBACK，2 走四步握手 |
| Retain | 发布时带上后，broker 记下这条，后来订阅的客户端会立刻收到 |
| 遗嘱（Will） | 写在 CONNECT 里。设备异常掉线、没发 DISCONNECT 时，由 broker 代发一条 |
| Clean Session | CONNECT 的一个标志。`true` 时 broker 不保留这个 ClientId 的旧订阅和离线队列 |
| Keep Alive | 双方约定的空闲上限（秒）。超时无报文就该发心跳或认定连接已死 |

本模块是 **客户端**。它主动连 broker，不监听端口，也不做 broker。

### 协议版本

CONNECT 里的协议级别固定为 **4**，即 **MQTT 3.1.1**。没有版本参数，也不能改成 3.1 或 5.0。

| 版本 | 协议级别 | 本模块 |
| --- | --- | --- |
| MQTT 3.1 | 3 | 不发送 |
| MQTT 3.1.1 | 4 | 唯一使用的版本 |
| MQTT 5.0 | 5 | 不发送，也不解析 5.0 属性 |

broker 拒绝这个级别时，回调 `error` 的 `ev.code` 为 `1100`（CONNACK 返回码 1）。只开 MQTT 5.0 的服务器对不上。

### 支持的特性

线路上会收发的报文：

| 报文 | 方向 | 何时出现 |
| --- | --- | --- |
| CONNECT / CONNACK | 本机 → broker / 回 | 每次建连。CONNACK 成功才回调 `connected` |
| PUBLISH | 双向 | `pub` / `pub_async` 发出；订了的主题进来 |
| PUBACK | 双向 | QoS 1 的确认 |
| PUBREC / PUBREL / PUBCOMP | 双向 | QoS 2 的四步握手 |
| SUBSCRIBE / SUBACK | 本机 → broker / 回 | `sub`，以及每次 `connected` 后的 `auto_sub` |
| UNSUBSCRIBE / UNSUBACK | 本机 → broker / 回 | `unsub` |
| PINGREQ / PINGRESP | 本机 → broker / 回 | 协议心跳，见下一节 |
| DISCONNECT | 本机 → broker | `close`、离网或拆连接时主动发 |

CONNECT 里会带上：ClientId、用户名、密码（空则省略）、Clean Session、Keep Alive、遗嘱（主题、内容、QoS、retain）。遗嘱内容最长 4096 字节。

发布和订阅的 QoS 都可以是 `0` / `1` / `2`。发布可以带 retain。订阅主题可以使用单层通配符 `+` 和末尾的多层通配符 `#`。一次 `sub` 只订一个主题；`auto_sub` 也是逐条发 SUBSCRIBE。

传输默认是明文 TCP，端口默认 1883，范围 `1`～`65535`。整机最多 4 路，每路一条连接。`tls_enable = true` 后同一条连接改走 MQTTS，端口一般写成 `8883`。校验级别和证书见 [9.3](#9-3-mqtts)。证书从 ublob 读取时写成 `{ ublob = 短名 }`。AT 通道仍用 `ssl_level` / `ssl_id`，见 [AT · MQTT](../../at/manual/mqtt.md)。

连接断了会自动再连（目标仍是「要连上」时）。这是 **连接级** 重试，见 [第 3 节](#3-目标态与自动重连)。`auto_sub` 列表会在每次 `connected` 之后再订，每个主题最多再试 3 次（一共 4 次 SUBSCRIBE）。这是订阅命令的重试。

`clean_session = false` 时，这个标志会原样放进 CONNECT，broker **可以** 保留该 ClientId 的订阅和离线 QoS 1/2 队列。模组自己不把会话、订阅、未完成握手写进掉电存储。重连后只保证重放 `auto_sub`；只调用过 `sub` 的主题，要靠 broker 在 clean session 关闭时还记得。

### 协议心跳

有。这是 MQTT 的 **PINGREQ / PINGRESP**，由协议线程自己发，脚本不用周期 `pub`。

`keepalive_interval` 就是 CONNECT 里的 Keep Alive，单位 **秒**，默认 60，范围 10～65535。小于 10 会抬到 10，所以这条连接关不掉心跳。

判定方式：

1. 每成功发出或收到一帧，空闲计时重新算一个 Keep Alive。
2. 发送空闲或接收空闲任一到期，发一帧 PINGREQ。
3. 发出后再等 **整整一个** Keep Alive。这段时间里收到 PINGRESP（或任意入站帧会刷新接收计时）就继续。
4. 一个 Keep Alive 过后仍然没有 PINGRESP，认定连接已死：回调 `error`，`ev.code = 1206`，然后走自动重连。

链路完全发呆时，从最后一帧到判定死亡大约是 **两个 Keep Alive**（一个用来决定该 ping，一个用来等 PINGRESP）。链路上还有 PUBLISH 时，心跳会跟着被推迟，不会按墙钟每 60 秒硬 ping 一次。

本模块不会替脚本往某个业务主题打「应用层心跳」。要让云平台看到设备在线，仍是这条 TCP 上的 PING；平台若另外要求周期上报属性，由脚本自己 `pub_async`。

已连接后，读套接字的单次等待会随低功耗档变化，避免空转把模组叫醒：

| 配置 key | 默认 | 范围 | 对应档位 |
| --- | --- | --- | --- |
| `yield_timeout_normal_ms` | 70 | 50～300000 | 普通 |
| `yield_timeout_low_power_ms` | 5000 | 50～300000 | 低功耗 |
| `yield_timeout_ultra_low_power_ms` | 30000 | 50～300000 | 超低功耗 |
| `yield_timeout_psm_plus_ms` | 30000 | 50～300000 | PSM+ |

这四项 **立刻生效**，只影响「这一轮阻塞读多久」，不改变 Keep Alive 的死亡判定。读窗口比 Keep Alive 短时，也不会因为没在这一轮里读到 PINGRESP 就误断线。

### 确认与重发

**没有未确认报文的重发。** QoS 1/2 只表示「这一次调用里等不等确认」，不表示「超时后再把同一条 DUP 发出去」，也不表示「断线后续传」。

发出去的 PUBLISH，DUP 标志固定为 0。`command_timeout_ms`（默认 30000，范围 1000～300000）是这一次握手的上限，订阅、退订、断开也用它。

| QoS | 这次调用里做什么 | 超时或断线之后 |
| --- | --- | --- |
| 0 | 写入发送缓冲即成功 | 无确认、无重发 |
| 1 | 发一条 PUBLISH，等到 PUBACK 或 `command_timeout_ms` 用尽 | 这次失败。不会过一会儿再发 |
| 2 | 发一条 PUBLISH，在同一次超时里走完 PUBREC → PUBREL → PUBCOMP | 这次失败。未完成的四步握手不保存，重连后续不上 |

同一条连接上，QoS 1/2 的发布是 **串行握手**：前一条确认结束（或超时）才发下一条，没有「飞行中多条、按报文号定时重传」的窗口。

`pub_async` 只是先放进内存队列（每路上限 **40 KiB**），由协议线程逐条按上表发送。出现下面任一情况，队列里的内容直接丢掉，不补发：

- 调用时还没 `connected`（`pub_async` 当场失败）
- 这一条等到确认超时，或写出套接字失败
- 连接断开、离网、`close`

入站方向会立刻回确认，同样没有「确认没发出去就稍后再试」的队列：

| 收到 | 协议线程接着做 | 对脚本的含义 |
| --- | --- | --- |
| QoS 0 的 PUBLISH | 拷进下行队列 | 丢了就没了 |
| QoS 1 的 PUBLISH | 先尝试入队，然后回 PUBACK | 入队失败也会回 PUBACK。broker 认为已送达，脚本可能没看到 |
| QoS 2 的 PUBLISH | 入队并回 PUBREC；之后收到 PUBREL 再回 PUBCOMP | 模组不保存 QoS 2 事务。broker 重投时，`message` 会再来一次 |

回调里的 `message` 只有主题和 payload。入站 QoS、DUP、retain 都不会放进 `ev`。入站也不按报文号去重。

所以：业务上要「至少一次」，脚本自己要能认重复、自己决定要不要再 `pub_async`。把 QoS 设成 2 得不到跨断线的恰好一次。

### 未实现的特性

| 项 | 实际情况 |
| --- | --- |
| MQTT 5.0 | 无用户属性、主题别名、订阅标识、共享订阅 `$share`、会话过期、请求/响应、原因字符串、流量控制、遗嘱延迟、内容类型、消息过期 |
| MQTT 3.1 | 不发送协议级别 3 |
| WebSocket | 无 |
| 报文级重发 / 离线补发 | 见上一节。没有 DUP 重传，没有掉电或断线后的发布缓存 |
| 应用层心跳主题 | 只有 PINGREQ。不会周期发布某个业务主题 |
| 关闭心跳 | Keep Alive 最低 10 秒 |
| 本地会话库 | `clean_session = false` 只通知 broker。模组不保存订阅和未完成 QoS |
| 入站去重 | 无。重投会再次回调 |
| 回调里的 QoS / DUP / retain | `message` 不带这些字段 |
| SUBACK 实际授予的 QoS | `sub` 只返回成败。broker 把 QoS 降级时，脚本看不到新级别 |
| 一条 SUBSCRIBE 订多个主题 | 每次一个主题 |
| 订阅过滤器槽 | 同时按过滤器登记 15 条。`auto_sub` 列表仍可写 20 条；超出槽位时这次 `sub` 可能返回失败，但 broker 上已经订上的报文仍会从默认路径进 `message`。一条报文同时命中多个过滤器时，回调来多次 |
| 下行积压 | 接收队列 32 条、内存池 30 KiB。单条更大，或池子/队列已满，这条丢掉，只有日志，没有 `error` 回调。主题抄进回调时最长 255 字节，更长会截断 |
| 单包大小 | 一整帧必须放进发送/接收缓冲（默认 4096，可到 16384）。更大的 PUBLISH 会把连接拆掉（`ev.code = 1401`）再重连 |
| Broker / 桥接 | 只做客户端 |

### 实现机制

每路客户端一条协议线程，外加一条只负责把已收到的 PUBLISH 交出去的投递线程。脚本看到的回调在 Lua 调度循环里，不在这两条线程里。

```
脚本  create / open / pub / sub / close
        │
        ▼
对象层  目标态（要连 / 挂起）、鉴权缓存、平台 token、相同错误码只上报一次
        │
        ▼
协议线程（每路一条，独占这条 TCP）
  目标=挂起 → 断开并休眠
  目标=要连且未驻网 → 堵住等网
  目标=要连且已驻网 →
        pre_connect
        → TCP 或 TLS（connect_timeout_ms）
        → CONNECT（MQTT 3.1.1）
        → CONNACK
        → connected
        → 按 auto_sub 逐条 SUBSCRIBE（每条最多 4 次）
        → 循环：先把异步发布队列发完，再读套接字（心跳、入站、回 PUBACK/PUBREC/PUBREL/PUBCOMP）
        → 读失败 / 心跳失败 / 离网 → 清空未发队列 → disconnected → 回到「要连」
        │
        ▼  入站 PUBLISH 拷贝
投递线程 → 运行时事件队列 → 调度循环里的 cb(ev)
```

建连顺序固定。`pre_connect` 在 TCP / TLS 之前就进脚本队列，所以每次重试都会来一次。这次回调入队之前，模块已经做完两件事：MQTTS 若把证书写成 `{ ublob = 短名 }`，会按那个名字重读；OneNET 会按缓存算好 token。见 [9.3](#9-3-mqtts) 和 [第 12 节](#12-onenet-平台)。

`open` 的返回只表示目标已改成「要连」。TCP 和 CONNECT 都在协议线程里做，失败不会停掉托管，按 [第 3 节](#3-目标态与自动重连) 的节奏再试。`close` 把目标改成挂起：发 DISCONNECT、停重连、线程休眠。再连必须再 `open`。

低功耗切到不在网档时，协议线程会自己松开连接并等网，脚本不必先 `close`。见 `lp` 文档 3.5。

### 消息调度

三条路，互不等待对方把 Lua 跑完：

**1. 同步发布 `pub`**

调用方一直占着当前协程，直到这一条写完（QoS 0）或握手结束（QoS 1/2）。期间协议线程让出套接字，由这次调用自己读确认。所以回调里不要 `pub`：调度循环被堵住，别的回调和任务都停。

**2. 异步发布 `pub_async`**

只入队就返回。协议线程在「已经连接」的每一轮里，先把队列按先进先出逐条发完，再去读套接字。QoS 1/2 的等待算在协议线程上，所以队列里若堆了多条 QoS 1，后面的主题会等前面的 PUBACK。队列按字节算，上限 40 KiB；超限时 `pub_async` 返回 `false, "publish_async failed"`，不会另起一条 `error` 回调。

未连接时不能入队。连接一旦离开「已连接」，还没发出去的整队丢掉。

**3. 入站与状态事件**

协议线程收到 PUBLISH 后，把主题和 payload 拷进接收队列（32 条，内存池 30 KiB），随即按 QoS 回确认，然后继续读套接字。投递线程从这队取出，放进 Lua 运行时队列。`connected` / `disconnected` / `error` / `pre_connect` 由协议线程直接放进运行时队列，不经这 32 条。

用户函数 `cb(ev)` 在调度循环里执行。要求短：不要 `rt.delay`、`wait_connect`、同步 `pub`。回包用 `pub_async`。同一轮断线里，相同 `ev.code` 的 `error` 只入队一次，直到再次 `connected`。

因此可能出现：

- `pub_async` 已返回 `true`，随后断线，这条再也发不出去，也没有单独的「发布失败」回调
- broker 已收到 PUBACK，脚本的 `message` 却因为接收队列满了没出现
- `connected` 先到，`auto_sub` 的 SUBSCRIBE 还在逐条进行；紧接着的 `message` 取决于 broker 何时开始推

### 云平台适配

适配只发生在 **CONNECT 的三元组**。报文格式、QoS、心跳、主题字符串都不变。物模型 JSON、属性主题由脚本自己组。本模块没有阿里云、华为云、腾讯云、AWS IoT 的签名函数。

| 平台 | 怎么接 | 模块额外做的事 |
| --- | --- | --- |
| 普通 MQTT | 默认 `platform("normal")` | 用户名、密码原样放进 CONNECT |
| 中国移动 OneNET | `platform("onenet")` 后再 `open` | 每次建连前用产品 ID + access key 计算 token，当作密码。明文 key 不下发 |
| 度云物联（玄武） | 本模块没有 `"doiot"` | 不自动拼 ClientId，也不代发物模型。脚本按下方格式自己填，或改走 AT |
| 阿里云 / 华为云 / 腾讯云 / AWS 等 | `normal`，三元组在脚本里算好，再开 MQTTS | 无签名器。加密用 `tls_enable` 和证书，见 [9.3](#9-3-mqtts) |

测试服务器 `mqtts.doiot.cn:1883`（用户名 `doiot`，密码 `web`）是普通 MQTT，平台用 `"normal"`。它不是度云物联。度云物联的 broker 是 `5giot.cn:1883`。

**OneNET**（细节与调用顺序见 [第 12 节](#12-onenet-平台)）

| 脚本传入 | 放进 CONNECT 的值 |
| --- | --- |
| `client_id` | 设备名，原样 |
| `username` | 产品 ID，原样，同时作为 token 的资源 |
| `password` | access key（Base64）。只留在缓存里 |

token 按 OneNET 安全方案 `2018-10-31`、方法 `sha1` 计算：资源为 `products/{产品ID}`，过期时刻为当前 UTC 再加 365 天，签名是 access key 的 HMAC-SHA1。每次 TCP 之前重算，所以重连会换一张新 token。设备时间不对时，过期时刻会错，broker 会拒（常见 `1103` / `1104`）。先做 NTP 再 `open`。

**度云物联**

AT 通道把平台写成 `"doiot"` 后，固件用本机 IMEI 拼 ClientId，并处理 `io*` 物模型。说明在 [专栏 · MQTT 连接度云物联](../../at/topics/5giot.md)。

Lua 里要自己写成：

| 项 | 值 |
| --- | --- |
| 主机 | `5giot.cn` |
| 端口 | `1883` |
| ClientId | `S&<IMEI>&<产品编号>&<用户ID>` |
| 用户名 | 控制台认证账号 |
| 密码 | 控制台认证密码 |
| `platform` | `"normal"` |

主题一般是 `/<产品编号>/<IMEI>/function/post` 与 `/<产品编号>/<IMEI>/function/get`。本模块不会自动订、也不会自动报属性。

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

`keepalive_interval` 是 MQTT 协议心跳（秒）。判定死亡后仍走上面的自动重连，不改间隔。空闲多久才 ping、多久才认定没收到 PINGRESP，见 [协议心跳](#协议心跳)。

`poll_interval_ms` 和四档 `yield_timeout_*_ms` **改了马上用上**，不用等重连。其余多数项等下次建连才合并，见 [第 9 节](#9-配置表)。

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

模块表导出 `create`，以及 MQTTS 的三个校验级别。没有 `mqtt.CONNECTED` 这类连接状态符号。事件名是回调里的 **字符串**。

| 符号 | 值 | 用在 |
| --- | --- | --- |
| `mqtt.TLS_INSECURE` | `1` | `tls_seclevel`：加密，不校验证书 |
| `mqtt.TLS_SERVER_AUTH` | `2` | `tls_seclevel`：校验服务端证书，必须有 CA |
| `mqtt.TLS_MUTUAL_AUTH` | `3` | `tls_seclevel`：双向校验，必须有 CA、客户端证书和私钥 |

数字 `1` / `2` / `3` 与符号等价。`0` 不是合法的 `tls_seclevel`。关掉加密用 `tls_enable = false`，不要写 `0`。

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

**例外**：`poll_interval_ms` 和四档 `yield_timeout_*_ms` 立刻生效。

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
| `yield_timeout_normal_ms` | number | 70 | 50～300000 | **立刻生效**。普通功耗下单次读等待 |
| `yield_timeout_low_power_ms` | number | 5000 | 50～300000 | **立刻生效**。低功耗下单次读等待 |
| `yield_timeout_ultra_low_power_ms` | number | 30000 | 50～300000 | **立刻生效**。超低功耗下单次读等待 |
| `yield_timeout_psm_plus_ms` | number | 30000 | 50～300000 | **立刻生效**。PSM+ 下单次读等待 |
| `clean_session` | **boolean** | `true` | — | 下次 CONNECT 时带上 |
| `send_buffer_size` | number | 4096 | 2048～16384 | 下次重连时重新分配 |
| `recv_buffer_size` | number | 4096 | 2048～16384 | 下次重连时重新分配 |
| `will_enable` | **boolean** | `false` | — | 下次 CONNECT |
| `will_topic` | string | 空 | — | 下次 CONNECT |
| `will_message` | string | 空 | 最长 4096 字节 | 下次 CONNECT |
| `will_qos` | number | 0 | 0～2 | 下次 CONNECT |
| `will_retain` | **boolean** | `false` | — | 下次 CONNECT |
| `tls_enable` | **boolean** | `false` | 只能是 `true` / `false` | 下次建连。`true` 走 MQTTS |
| `tls_seclevel` | number | `1` | `1` / `2` / `3` | 下次建连。见 [9.3](#9-3-mqtts) |
| `tls_hostname` | string | 空，跟随 `host` | 最长 127 字节 | 下次建连。SNI 与证书校验用的主机名 |
| `tls_ciphersuite` | number | `65535` | `0`～`65535` | 下次建连。`0` 与 `65535` 都是默认套件 |
| `ca_cert` | string 或 `{ ublob = name }` | 无 | CA 最长 6144 字节 | 下次建连。见 [9.3](#9-3-mqtts) |
| `client_cert` | string 或 `{ ublob = name }` | 无 | 最长 4096 字节 | 下次建连 |
| `client_key` | string 或 `{ ublob = name }` | 无 | 最长 4096 字节 | 下次建连 |

未列出的字段忽略。布尔必须是 `true`/`false`。`open(host, port, client_id, ...)` 等价于先写入这几项再 `open`。

`recv_buffer_size` 与 TCP 不同：MQTT 可以在 `update` 里改，等下次重连重新分配。

### 9.2 已连接时改参

当前这条连接完全不热改（对端、鉴权、心跳、缓冲都不改）。等这条断了、内部重连（或你 `close` 再 `open`）才用上新值。

`poll_interval_ms` 立刻改空转 / 高频间隔。四档 `yield_timeout_*_ms` 立刻改已连接后的单次读等待。

TLS 各项也等下次建连。已经连着明文时要改走 MQTTS：`update` 写好 `tls_*` 和证书，再 `close` 然后 `open`。

### 9.3 MQTTS {#9-3-mqtts}

`tls_enable = false`（默认）时是明文 TCP。`true` 时这条连接在 TCP 之上做 TLS，再发 MQTT CONNECT。broker 端口要写成它实际监听的端口，常见是 `8883`，模块不会因为开了 TLS 就改端口。

```lua
c:update({
    tls_enable = true,
    tls_seclevel = mqtt.TLS_SERVER_AUTH,
    port = 8883,
    ca_cert = { ublob = "ca.pem" },
})
```

| `tls_seclevel` | 握手时检查 |
| --- | --- |
| `1` / `mqtt.TLS_INSECURE` | 只加密。不看证书。默认就是这一档 |
| `2` / `mqtt.TLS_SERVER_AUTH` | 用 CA 校验服务端证书。没有 CA 时 `create` / `update` 失败 |
| `3` / `mqtt.TLS_MUTUAL_AUTH` | 再带上客户端证书和私钥。三份缺一则失败 |

`tls_enable` 仍是 `false` 时，可以先把 `tls_seclevel` 和证书写上，这时不检查证书是否齐全。等 `tls_enable = true` 的那一次（或同一次表里已经是 `true`）才按上表检查。检查不通过时，这次表里的证书、开关、级别、主机名和套件都不会写进去。

SNI 在 MQTTS 上固定打开，没有关闭开关。没写过 `tls_hostname`，或写成空串时，SNI 用当前 `host`；之后只改 `host`，SNI 跟着改。写过非空 `tls_hostname` 之后，再改 `host` 不会改 SNI，要改就再写一次主机名，或写回空串恢复跟随。连的是 IP、证书上是域名时，把域名写进 `tls_hostname`。

`tls_ciphersuite` 不写、写 `0` 或写 `65535`，都用默认套件。

证书三份各自独立。字符串是 PEM 正文。要从 ublob 读，跟 `audio`、`http`、`lvgl` 一样写成 `{ ublob = 短名 }`。

| 写法 | 证书从哪来 |
| --- | --- |
| `ca_cert = pem` | 字符串就是 PEM 正文（可含二进制，按 Lua string 的长度，不在 `\0` 处截断） |
| `ca_cert = ""` | 清掉这一份，同时忘掉之前记的 ublob 短名 |
| `ca_cert = { ublob = "ca.pem" }` | ublob 短名。luapk 打进 ublob 的证书直接写这个名字 |

`client_cert` / `client_key` 规则相同。短名最长 95 字节，规则与 `ublob` 相同（不能含 `/`、`\`、`:`）。

`create` / `update` 当时就会按这个短名把证书读进来。名字不存在、是空文件、超长或读失败，调用直接失败，连接还按旧配置。长度上限：CA **6144** 字节，客户端证书 **4096** 字节，私钥 **4096** 字节。

TLS 开着、并且这份证书是用 `{ ublob = 短名 }` 配的，每次 `pre_connect` 会再读一次。luapk 换过包里的证书后，下一次重连用新内容，不必再 `update`。这一次重读失败时，沿用上一份已经读成功的内容，只打日志。内联 PEM 不会在 `pre_connect` 里重读。

```lua
local mqtt = require("mqtt")

c:update({
    host = "mqtt.example.com",
    port = 8883,
    tls_enable = true,
    tls_seclevel = mqtt.TLS_MUTUAL_AUTH,
    ca_cert = { ublob = "ca.pem" },
    client_cert = { ublob = "device.pem" },
    client_key = { ublob = "device.key" },
})
```

只加密、不校验：

```lua
c:update({
    port = 8883,
    tls_enable = true,
    tls_seclevel = mqtt.TLS_INSECURE,
})
```

[examples/nt26/network/mqtt/mqtts](../../../../../examples/nt26/network/mqtt/mqtts) 用 `mqtt.TLS_SERVER_AUTH` 连 EMQX 公共 broker `broker.emqx.io:8883`。CA 是 DigiCert Global Root G2（同目录 `ca.pem`，脚本里内联同一份）。匿名，主题带本机 IMEI。

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

先看返回形态，再拿 `err` 字符串或回调 `ev.code` 对下面两张表。类型错（缺回调、QoS 越界、`pub` 参数组合不对）走 **抛错**，不是 `nil, err`。

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

模块表没有导出这些数字常量。诊断时直接比对 `ev.code` 的整数。

### 13.1 接口返回的 `err` 文本

| `err` | 出现在 | 可能原因 |
| --- | --- | --- |
| `callback function required` | `create` | 第 1 参不是 function |
| `rt vm context missing` | `create` | 不在脚本虚拟机里调（几乎只会出现在错误嵌入） |
| `mutex init failed` | `create` | 系统资源不够，重启后再试 |
| `mqtt client limit reached (max 4)` | `create` | 整机已有 4 路未 `delete`；含其它脚本 |
| `net_mqtt_create failed` | `create` | 底层客户端没建起来，内存或协议栈未就绪 |
| `net_mqtt_init failed` | `create` | 初始化失败，看缓冲/内存 |
| `apply config failed` | `create` | `cfg` 里某项底层拒收（过长、非法），且没有更具体的 TLS 文案 |
| `tls_seclevel must be 1, 2 or 3` | `create` / `update` | `tls_seclevel` 不是数字 1、2、3 |
| `tls_enable must be boolean` | `create` / `update` | 写成了 `1` / `0` 或别的类型。只能 `true` / `false` |
| `tls_hostname must be string` | `create` / `update` | `tls_hostname` 不是字符串 |
| `tls_seclevel 2 requires ca_cert` | `create` / `update` | 已开 TLS 且级别为 2，但还没有 CA |
| `tls_seclevel 3 requires ca_cert, client_cert and client_key` | `create` / `update` | 级别为 3，CA / 客户端证书 / 私钥缺一份 |
| `tls_hostname too long` | `create` / `update` | 主机名达到或超过 128 字节 |
| `tls_ciphersuite out of range` | `create` / `update` | 不在 0～65535 |
| `tls_enable failed` | `create` / `update` | 加密开关没写进连接参数 |
| `ca_cert must be pem or {ublob=name}` | `create` / `update` | `ca_cert` 不是字符串也不是带 `ublob` 的表。`client_cert` / `client_key` 有同样句式 |
| `ca_cert ublob name required` | `create` / `update` | `{ ublob = name }` 里的短名是空的。`client_cert` / `client_key` 有同样句式 |
| `ca_cert ublob invalid` | `create` / `update` | 短名过长或含 ublob 不接受的字符。`client_cert` / `client_key` 把开头换成 `client_cert ublob` / `client_key ublob`，下面几行同样 |
| `ca_cert ublob not found` | `create` / `update` | 这个短名在 ublob 里没有 |
| `ca_cert ublob read failed` | `create` / `update` | 读 ublob 失败 |
| `ca_cert ublob empty` | `create` / `update` | 文件是空的 |
| `ca_cert ublob no mem` | `create` / `update` | 读证书时内存不够 |
| `ca_cert too large` | `create` / `update` | CA 超过 6144 字节。客户端证书 / 私钥对应 `client_cert too large` / `client_key too large`（上限 4096） |
| `mqtt create race` | `create` | 并发 `create` 抢同一槽，串行再建 |
| `invalid mqtt client` | 各方法 | 对象已 `delete`、被 GC、或不是本模块对象 |
| `open failed` | `open` | 目标没设成「要连」：句柄无效、已在拆、内部 open 失败 |
| `set_param failed` | `open` | host/port 没写进底层 |
| `close failed` | `close` | 句柄已无效 |
| `subscribe failed` | `sub` | 未连接、主题非法、内部订失败 |
| `unsubscribe failed` | `unsub` | 未订过或未连接 |
| `unsub_auto failed` | `unsub_auto` | 自动订阅表操作失败 |
| `auto_sub qos must be in [0..2]` | `auto_sub` | 表里某条 QoS 越界（返回值失败，不一定抛） |
| `auto_sub list too large` | `auto_sub` | 超过 20 条 |
| `auto_sub failed` | `auto_sub` | 内部登记失败 |
| `publish failed` | `pub` | 未连接、主题非法、内部发送失败 |
| `publish_async failed` | `pub_async` | 队列满或句柄无效 |
| `update failed` | `update` | 句柄无效或参数没吃进去 |
| `set_param failed (client_id)` | `auth` | client_id 没写下发 |
| `set_param failed (username)` | `auth` | username 没写下发 |
| `set_param failed (password)` | `auth` | password / access key 没写下发 |
| `platform must be 'onenet' or 'normal'` | `platform` | 拼写不是这两字 |

**抛错**（`pcall` 才能接到）：

| 摘要 | 可能原因 |
| --- | --- |
| `port must be in [1..65535]` | `open` 的端口 |
| `qos must be in [0..2]` | `sub` / `pub` / `pub_async` |
| `usage: pub(topic,payload,qos,retain) or pub(topic,qos,retain)` | `pub` 参数个数/类型对不上两种形态 |
| `mqtt mutex init failed` | 模块装载时系统互斥量没建起来（整模块不可用） |

`bad argument #n`：该 string/function/integer 的位置给了别的类型。

### 13.2 回调 `ev.event == "error"` 时的 `ev.code`

同一路连续相同 `code` 不会再投递（避免重连刷屏）。连上后计数清零，下次新码会再来。

| `ev.code` | 含义 | 可能原因 |
| --- | --- | --- |
| `0` | 无错（一般不会以 error 事件出现） | — |
| `1000` | TCP 连不上 | host/port 错、对端没开、防火墙、还没驻网 |
| `1001` | 建 socket 失败 | 资源耗尽、协议栈异常 |
| `1002` | DNS 失败 | 域名错、DNS 没配、未驻网 |
| `1003` | TCP 超时 | 链路差、IP 不可达 |
| `1004` | TCP 已断开 | 对端关连接、中间网络掉 |
| `1005` | TCP 发送失败 | 已断或发送缓冲 |
| `1006` | TCP 接收失败 | 已断或读失败 |
| `1100` | CONNACK：协议版本拒 | broker 不接受当前 MQTT 版本 |
| `1101` | CONNACK：client_id 拒 | ID 空、重复、格式不合 broker |
| `1102` | CONNACK：服务器不可用 | broker 过载或未就绪 |
| `1103` | CONNACK：用户名/密码错 | `auth` 三元组或测试站密码不对 |
| `1104` | CONNACK：未授权 | ACL / 证书 / OneNET token |
| `1105` | MQTT 连接失败（通用） | 握手没走完，看前后是否先有 100x |
| `1106` | MQTT 连接超时 | CONNACK 一直不来 |
| `1107` | 连接缓冲溢出 | client_id/用户信息过长或缓冲偏小 |
| `1200` | 订阅失败 | 主题/QoS 被拒，或当时未真正连上 |
| `1201` | 取消订阅失败 | 主题不存在于当前会话 |
| `1202` | 发布失败 | 未连接、主题非法、QoS |
| `1203` | 发布队列满（保留码） | 当前 `pub_async` 队列满时直接返回 `publish_async failed`，不投递这条 `error` |
| `1204` | 会话循环失败（通用） | 看是否伴随 1205～1207 |
| `1205` | 读/套接字超时或出错 | 链路闪断，随后会重连 |
| `1206` | 心跳无 PINGRESP | 中间设备吃包、keepalive 过短/过长 |
| `1207` | 发 PUBACK/PUBREL 失败 | 上行卡住 |
| `1208` | 主动断开失败 | 少见，句柄已坏 |
| `1300` | 参数无效 | 某次内部调用参数被拒 |
| `1301` | 句柄无效 | 对象已拆仍在用 |
| `1302` | 未初始化 | `create` 未成功就当已连用 |
| `1303` | 未连接 | 在 `connected` 之前 `pub`/`sub`（`pub_async` 可排队，同步 `pub` 常失败） |
| `1304` | 已连接 | 内部状态冲突，少见 |
| `1305` | 主题无效 | 空串、非法通配 |
| `1306` | QoS 无效 | 不是 0/1/2 |
| `1400` | 内存分配失败 | 减小 `rx_buf`/`tx_buf`，少开路数 |
| `1401` | 缓冲区太小 | 报文大于 create 时的缓冲；加大再 `create` |
| `1500` | 未知 | 对不上上面的码 |
| `1501` | 内部错误 | 协议栈异常，可 `close` 再 `open` |
| `1502` | 工作线程错误 | 线程没跑起来或已退出 |

诊断顺序：先看 `err` 文本（调用当场失败）→ 再看是否收到 `connected` → 再看 `error` 的 `ev.code`。`1002`/`1000` 先查 `lp.wait_link` 和 host；`1103`/`1104` 查三元组；`1401` 查包长和缓冲。

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
| 异步发布队列 | 40 KiB / 路 | 只在已连接时接受 `pub_async`；断线整队丢弃 |
| 下行接收队列 | 32 条，内存池 30 KiB | 满或单条超过池子则丢弃，无 `error` 回调 |
| 订阅过滤器槽 | 15 | 列表上限仍是 `auto_sub` 的 20 条；槽满时多出来的订阅调用可能失败，报文仍可能进 `message` |
| 回调中的主题 | 255 字节 | 更长截断 |
| CA 证书 | 6144 字节 | 内联 PEM 或 ublob 读入后都是这个上限 |
| 客户端证书 / 私钥 | 各 4096 字节 | 同上 |
| ublob 证书名 | 95 字节 | `{ ublob = name }` 里的短名 |

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
| MQTTS | `tls_enable = true`，`tls_seclevel` 用 `mqtt.TLS_*`；证书用 PEM，或 `{ ublob = 短名 }` |
| OneNET | `platform("onenet")` 后再 `open` |
| 销毁 | 一般不必；用 `close` 即可 |

---

## 16. 完整示例

与 [examples/nt26/network/mqtt/mqtt_client](../../../../../examples/nt26/network/mqtt/mqtt_client) 一致。`mqtts.doiot.cn` 是 **普通 MQTT 测试服务器**（不是度云物联云平台），用户名 `doiot`、密码 `web`，`client_id` 用设备 IMEI；网页往 `/server/<IMEI>` 发，模组就能收到。度云物联（玄武）是度云公司推出的云平台（与 OneNET 同类），Broker `5giot.cn`，请走 AT，见 [专栏 · MQTT 连接度云物联](../../at/topics/5giot.md)；脚本自己 `open` 时要手写 `S&` 三元组，不会自动按 `"doiot"` 平台拼。

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
| `obj:update(cfg)` | 改缓存；`poll_interval_ms` 与 `yield_timeout_*_ms` 立刻生效 | `true, "ok"` 或 `nil, err` |
| `obj:auth(...)` | 改三元组，`nil` 的项不改 | `true, "ok"` 或 `nil, err` |
| `obj:platform("normal"\|"onenet")` | 鉴权平台 | `true, "ok"` 或 `nil, err` |

## 附录 B. 枚举值一览

`mqtt.TLS_INSECURE = 1`，`mqtt.TLS_SERVER_AUTH = 2`，`mqtt.TLS_MUTUAL_AUTH = 3`。事件名为字符串，见第 5 节。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全接口 `err` 文案与回调 `ev.code` 全表，并写可能原因 |
| 1.1.1 | 2026-09-20 | 完整示例注明度云物联走 AT 专栏；脚本 `open` 不自动拼 `"doiot"` 三元组 |
| 1.1.2 | 2026-09-20 | 标明 `mqtts.doiot.cn` 是普通 MQTT 测试服务器，不是度云物联云平台 |
| 1.2.0 | 2026-10-13 | 文首增加概述：MQTT 3.1.1、协议心跳、无报文级重发、调度路径、OneNET / 度云物联适配；配置表补四档读等待；资源表补发布队列、接收队列与过滤器槽；`1203` 改为保留码，队列满只返回 `publish_async failed` |
| 1.2.1 | 2026-10-13 | 写明 MQTTS 在 AT 的 `ssl_level`；Lua `mqtt` 仍是明文 TCP |
| 1.3.0 | 2026-10-13 | Lua `mqtt` 增加 MQTTS：`tls_enable` / `tls_seclevel` / 主机名 / 套件；证书可内联 PEM，也可写 ublob 地址，建连前重读 |
| 2.0.0 | 2026-10-13 | 证书只认 PEM 字符串或 `{ ublob = 短名 }`。去掉 `ublob://`、`ublob:` 和 `ca_ublob` / `client_cert_ublob` / `client_key_ublob` |
| 2.0.1 | 2026-10-20 | 增加 MQTTS 例程 `examples/nt26/network/mqtt/mqtts`。单向认证，CA 为 DigiCert Global Root G2，连 `broker.emqx.io:8883` |
