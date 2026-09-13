#  MQTT

**文档版本** `1.0.0`

配置并收发模组上的 **4 路 MQTT 通道**。指令走应用 AT 口（主串口 / USB AT 等），与 [`rtu_config.cfg` 的 `[mqtt.N]`](../api/rtu_config/rtu_config.md#10-mqttn) 以及主题槽 [`[mqtt.N.subscribe.M]` / `[mqtt.N.publish.M]`](../api/rtu_config/rtu_config.md#11-mqttnsubscribem--mqttnpublishm) 读写**同一份持久化配置**。通道号一律 **1～4**，与配置段 `[mqtt.1]`～`[mqtt.4]` 对应。

MQTT 的 N 与 Socket / RTU 任务是**同一路**；HTTP 是另一套 1～5。换入口不换编号，见 [convention.md 第 4 节](convention.md#4-通道编号)。

本篇按常用模组 AT 手册体例写：先约定，再逐条给出测试命令、查询、设置、参数表、应答、错误码和可抄示例。行格式与失败风格见 [convention.md](convention.md)。Lua `require("mqtt")` 见 [mqtt API](../api/network/mqtt.md)。

---

## 目录

- [1. 约定](#1-约定)
- [2. 指令一览](#2-指令一览)
- [3. 通道与生效时机](#3-通道与生效时机)
- [4. AT+MQTT](#4-atmqtt)
- [5. AT+MQTTCFG](#5-atmqttcfg)
- [6. AT+MQTTAUTH](#6-atmqttauth)
- [7. AT+MQTTPLATFORM](#7-atmqttplatform)
- [8. AT+MQTTSUB](#8-atmqttsub)
- [9. AT+MQTTPUB](#9-atmqttpub)
- [10. AT+MQTTSYNC](#10-atmqttsync)
- [11. AT+MQTTASYNC](#11-atmqttasync)
- [12. AT+MQTTCLRRET](#12-atmqttclrret)
- [13. AT+MQTTWILL](#13-atmqttwill)
- [14. 错误一览](#14-错误一览)
- [15. 联调顺序](#15-联调顺序)
- [修订记录](#修订记录)

---

## 1. 约定

### 1.1 行格式

| 项 | 约定 |
| --- | --- |
| 命令结束 | 每条命令以 `<CR><LF>`（`\r\n`）结束。下文示例省略行结束符 |
| 大小写 | 命令名大小写不敏感；参数里的 `key`、主机名按原文保存 |
| 字符串 | 主机、key、主题建议加双引号，例如 `"server_host"`、`"broker.example.com"` |
| 数值 | 十进制整数，不要带符号、不要带小数 |
| 尾部裸数据 | `<payload>` 为 **TAILRAW**：最后一个逗号之后到行结束之前的**原始字节**，不做 HEX 文本解码。可含 `0x00`，也可是普通 ASCII |

测试命令（`AT+XXX=?`）返回该指令的取值范围与写法，以 `OK` 结束。

### 1.2 命令形态

| 形态 | 写法 | 本篇是否支持 |
| --- | --- | --- |
| 测试 | `AT+XXX=?` | 十条都支持 |
| 按通道查询 | `AT+XXX=<id>?` | `MQTT` / `MQTTCFG` / `MQTTAUTH` / `MQTTPLATFORM` / `MQTTSUB` / `MQTTPUB` / `MQTTWILL` |
| 无参查询 `AT+XXX?` | — | **仅** `MQTTSUB` / `MQTTPUB`（打出全部通道全部槽）。其它指令**不支持**，不要写 `AT+MQTT?` |
| 按 key 查询 | `AT+MQTTCFG=<id>,"<key>"`（无第三参） | 仅 `MQTTCFG` |
| 设置 | `AT+XXX=<id>,…` | 十条都支持 |

没有「执行命令」（无参 `AT+MQTT`）。

### 1.3 成功与失败

成功（需要回结果的命令）：

```lua
<CR><LF>+<CMD>: <字段…><CR><LF>
<CR><LF>OK<CR><LF>
```

失败（需要回报错的命令）：

```lua
<CR><LF>+<CMD>: "error <reason>"<CR><LF>
<CR><LF>ERROR<CR><LF>
```

`<reason>` 是短英文词，见 [第 14 节](#14-错误一览)。**不是** `+CME ERROR: <err>`。

`MQTTSYNC` / `MQTTASYNC` 在参数已解析且 `rsp=0` 时：发送成败**都不回** `+CMD` / `OK` / `ERROR`。解析阶段的 `param` / `id` / `topic` / `qos` / `retain` / `rsp` / `data` **仍会**回 `"error <reason>"` + `ERROR`（此时还没走到静默分支）。

### 1.4 与 Lua / 配置文件

| 入口 | 做什么 |
| --- | --- |
| 本篇 AT | 改 MQTT 持久化配置；按通道立刻发布 / 清 retain |
| `[mqtt.N]` / `[mqtt.N.subscribe.M]` / `[mqtt.N.publish.M]` | 同一套 key，开机/加载配置时写入 |
| Lua `require("mqtt")` | 独立客户端对象，最多也是 4 路；**不是**另一套通道号 |

`AT+MQTT` 只改 broker 主机和端口，并顺带把该通道 `enable` 置 1。鉴权、平台、遗嘱、超时、TLS、主题槽用其它指令或 `AT+MQTTCFG`。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+MQTT` | `=?` | `<id>?` | `<id>,<ip>,<port>` | 设/查 broker 主机与端口，并打开 `enable` |
| `AT+MQTTCFG` | `=?` | `<id>?` 全量；`<id>,"key"` 单项 | `<id>,"key",<value>` | 按 key 读写通道项与主题槽 |
| `AT+MQTTAUTH` | `=?` | `<id>?` | `<id>,<auth1>[,<auth2>[,<auth3>[,<auth4>]]]` | 写 `auth1`～`auth4` |
| `AT+MQTTPLATFORM` | `=?` | `<id>?` | `<id>,"<platform>"` | 写平台（`normal` / `onenet` / `doiot`） |
| `AT+MQTTSUB` | `=?` | `?` 全通道；`<id>?` 单通道 | `<id>,<topic_id>,<topic>,<qos>` | 订阅槽 |
| `AT+MQTTPUB` | `=?` | `?` 全通道；`<id>?` 单通道 | `<id>,<topic_id>,<topic>,<qos>,<retain>` | 发布槽 |
| `AT+MQTTSYNC` | `=?` | 无 | `<id>,<topic>,<qos>,<retain>,<rsp>[,<payload>]` | **同步**自由发布 |
| `AT+MQTTASYNC` | `=?` | 无 | 同上 | **异步**入队自由发布 |
| `AT+MQTTCLRRET` | `=?` | 无 | `<id>,<topic_id>` | 向该发布槽发空包，清 broker retain |
| `AT+MQTTWILL` | `=?` | `<id>?` | `<id>,<enable>,<topic>,<qos>,<retain>,<message>` | 遗嘱 |

---

## 3. 通道与生效时机

- 通道数 **4**。`<id>` = 1、2、3、4。越界回 `"error id"`。
- 每通道 **10** 个订阅槽、**10** 个发布槽。槽号 `<topic_id>` = 1～10（`MQTTCLRRET` 除外，见该条）。
- **写配置的指令只落盘，不拆已经建立的连接，也不立刻改正在跑的 runtime。** 正在连的通道仍用启动时读到的值。要让新主机/端口/鉴权/遗嘱/主题表生效：停通道再启、或按产品流程重新加载配置 / 复位。
- **立刻执行、改 runtime 的指令**：`MQTTSYNC` / `MQTTASYNC`（当场发布）、`MQTTCLRRET`（当场发空包清 retain）。通道必须已经起来且允许发布，否则失败。
- 仅写 `AT+MQTT` 而 RTU 任务没开（`[task.N] en=0` 或 `task_id` 不是 MQTT）时，配置在、业务通道可能仍不起。发布会失败。
- TLS：`ssl_level=0` 不走 TLS；`1` 不校验；`2` 校验服务端；`3` 双向。`ssl_id` 引用 [SSL 证书组 1～3](ssl.md)，与 HTTP 的证书组是同一套 1～3，**不是** MQTT 通道号。
- 出厂未改过时常见默认：

| 项 | 默认 |
| --- | --- |
| `enable` | 0 |
| `server_port` | 1883 |
| `platform` | 0（普通） |
| `clean_session` | 1 |
| `keepalive_interval` | 60 s |
| `connect_timeout_ms` | 5000 |
| `command_timeout_ms` | 30000 |
| `reconnect_interval_ms` | 5000 |
| `send_buffer_size` / `recv_buffer_size` | 4096 / 4096 |
| `callback_queue_mem_max` | 30720 |
| `poll_interval_ms` | 30（可写范围 20～10000） |
| `yield_timeout_*` | 70 / 5000 / 30000 / 30000 ms（均不可为 0） |
| `ssl_id` | 1 |
| `ssl_level` | 0（关 TLS） |
| 遗嘱 | 关，主题/消息空，QoS 0，retain 0 |

主机最长 **127** 字节（不含结尾 NUL）。`auth1`～`auth4` 各最长 **127**。主题最长 **127**。遗嘱消息最长 **255**。

`platform` × `auth*` 怎么拼三元组，见 [rtu_config 第 10.2 节](../api/rtu_config/rtu_config.md#102-platform--auth联合)。AT 只负责把字符串入库；连上时才按平台解释。

---

## 4. AT+MQTT {#4-atmqtt}

设置或查询一路通道的 **broker 主机 + 端口**。设置成功时该通道 `enable` 变为 1。其它鉴权、超时、主题保持原值。

### 4.1 测试命令

**命令**

```lua
AT+MQTT=?
```

**应答**

```lua
+MQTT: (id,"ip",port)
id:1-4
query: AT+MQTT=<id>?

OK
```

### 4.2 查询命令

**命令**

```lua
AT+MQTT=<id>?
```

**应答（成功）**

```lua
+MQTT: <id>,"<ip>",<port>

OK
```

| 字段 | 含义 |
| --- | --- |
| `<id>` | 1～4 |
| `<ip>` | `server_host`。未配置时可能为空串 `""` |
| `<port>` | `server_port`，出厂常见 1883 |

**失败** `+MQTT: "error <reason>"` 后 `ERROR`。常见 `param`（缺 id / 不是数字）、`id`、`read`。

### 4.3 设置命令

**命令**

```lua
AT+MQTT=<id>,<ip>,<port>
```

**参数**

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<ip>` | 字符串 | 1～127 字符，非空 | 域名或点分 IPv4。必须是字符串类型 |
| `<port>` | 整数 | 1～65535 | **0 非法** |

参数个数不是 3、`<ip>` 不是字符串 → `"error param"`。

**应答（成功）** 回显刚写入的值：

```lua
+MQTT: <id>,"<ip>",<port>

OK
```

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 形态不对或少参 |
| `id` | 不是 1～4 |
| `ip` | 空串或长度 ≥ 128 |
| `port` | 0、大于 65535、或不是非负整数 |
| `read` | 读持久化配置失败 |
| `save` | 写入失败 |

### 4.4 示例

```lua
AT+MQTT=1,"broker.example.com",1883
+MQTT: 1,"broker.example.com",1883

OK

AT+MQTT=1?
+MQTT: 1,"broker.example.com",1883

OK
```

### 4.5 说明

- 设置 **不会** 立刻断开旧连接再连新地址，见 [第 3 节](#3-通道与生效时机)。
- 查询读的是持久化配置，不是瞬时在线状态。
- 不要用本指令当「connect」。连上由 RTU 任务 / 通道启动流程负责。

---

## 5. AT+MQTTCFG {#5-atmqttcfg}

按 **key** 读写单通道 MQTT 项。能改的名字与 `[mqtt.N]` 以及主题槽 key **相同**（AT 另提供 `host` / `port` 别名，以及 `subscribe_M_*` / `publish_M_*` 扁平名）。

### 5.1 测试命令

```lua
AT+MQTTCFG=?
```

```lua
+MQTTCFG: (id,"key",value)
query: AT+MQTTCFG=<id>,"<key>"
query all: AT+MQTTCFG=<id>?
set:   AT+MQTTCFG=<id>,"<key>",<RAW>

OK
```

### 5.2 查询全部

```lua
AT+MQTTCFG=<id>?
```

成功时连续输出该通道每一项，最后一行带 `OK`。顺序固定：

`enable` → `server_host` → `server_port` → `platform` → `auth1`～`auth4` → 超时/缓冲/yield → 遗嘱五项 → `ssl_id` / `ssl_level` → `subscribe_1_topic` / `subscribe_1_qos` … `subscribe_10_*` → `publish_1_topic` / `publish_1_qos` / `publish_1_retain` … `publish_10_*`。

全量查询**不**额外打 `host` / `port` 别名行（与 `server_host` / `server_port` 同值）。订阅槽不打 `retain`。

缓冲区不够回 `"error overflow"`；申请失败回 `"error malloc"`。

### 5.3 查询单项

第三参不出现或长度为 0 时，当作查询，不是设置：

```lua
AT+MQTTCFG=<id>,"<key>"
```

未知 key → `"error key"`。`subscribe_M_retain` **不是**合法查询 key（订阅槽没有对外 retain）。

**应答（数值 key）**

```lua
+MQTTCFG: <id>,"<key>",<number>

OK
```

**应答（字符串 key）**

```lua
+MQTTCFG: <id>,"server_host","broker.example.com"

OK
```

`platform` 查询值为 **0/1/2**（对外数字），与设置时相同。字符串平台名只存在于 `AT+MQTTPLATFORM`。

### 5.4 设置

```lua
AT+MQTTCFG=<id>,"<key>",<value>
```

| key | value 形态 | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `enable` | 整数 | 0 或 1 | 通道使能。任务侧还要 `[task.N]` |
| `server_host` / `host` | 字符串 | 1～127，非空 | 别名写入同一主机 |
| `server_port` / `port` | 整数 | 1～65535 | 0 会 `value` 失败 |
| `platform` | 整数 | 0=普通，1=OneNET，2=DoIoT | 也可用 `AT+MQTTPLATFORM` 写字符串 |
| `auth1`～`auth4` | 字符串 | 0～127 | 可空；含义见配置文件第 10.2 节 |
| `keepalive_interval` | 整数 秒 | 0～4294967295 | MQTT keepalive |
| `clean_session` | 整数 | 0 或 1 | 清会话。OneNET 连上时会强制按 1 用 |
| `connect_timeout_ms` | 整数 ms | 0～4294967295 | 连接超时 |
| `command_timeout_ms` | 整数 ms | 同上 | 命令超时 |
| `reconnect_interval_ms` | 整数 ms | 同上 | 重连间隔 |
| `send_buffer_size` | 整数 | 同上 | 发缓冲 |
| `recv_buffer_size` | 整数 | 同上 | 收缓冲 |
| `callback_queue_mem_max` | 整数 | 4096～262144 | 回调队列内存上限 |
| `poll_interval_ms` | 整数 ms | 20～10000 | 轮询 |
| `yield_timeout_normal_ms` | 整数 ms | ≥ 1 | 正常 yield，**0 非法** |
| `yield_timeout_low_power_ms` | 整数 ms | ≥ 1 | 低功耗 yield |
| `yield_timeout_ultra_low_power_ms` | 整数 ms | ≥ 1 | 超低功耗 yield |
| `yield_timeout_psm_plus_ms` | 整数 ms | ≥ 1 | PSM+ yield |
| `will_enable` | 整数 | 0 或 1 | 是否带遗嘱 |
| `will_topic` | 字符串 | 0～127 | 遗嘱主题 |
| `will_message` | 字符串 | 0～255 | 遗嘱消息 |
| `will_qos` | 整数 | 0～2 | 遗嘱 QoS |
| `will_retain` | 整数 | 0 或 1 | 遗嘱 retain |
| `ssl_id` | 整数 | **1～3** | 引用 SSL 证书组。本指令**不能**写成 0 |
| `ssl_level` | 整数 | 0～3 | `0` 关 TLS；`1` 不校验；`2` 校验服务端；`3` 双向 |
| `subscribe_<M>_topic` | 字符串 | 0～127 | M = 1～10 |
| `subscribe_<M>_qos` | 整数 | 0～2 | |
| `publish_<M>_topic` | 字符串 | 0～127 | |
| `publish_<M>_qos` | 整数 | 0～2 | |
| `publish_<M>_retain` | 整数 | 0 或 1 | 订阅槽没有这项 |

`<value>` 可以是十进制数，或带/不带引号的文本。主机类必须能解析成非空字符串。数值类解析失败 → `"error value"`。越界（端口 0、`ssl_id` 不是 1～3、yield 为 0 等）→ `"error value"`。未知 key → `"error key"`。

**应答（成功）** 与单项查询同形，回显写入后的值。

**失败 reason**：`param`、`id`、`key`、`value`、`read`、`save`、`overflow`、`malloc`。

### 5.5 示例

```lua
AT+MQTTCFG=1,"server_host","broker.example.com"
+MQTTCFG: 1,"server_host","broker.example.com"

OK

AT+MQTTCFG=1,"server_port",1883
+MQTTCFG: 1,"server_port",1883

OK

AT+MQTTCFG=1,"ssl_level",2
+MQTTCFG: 1,"ssl_level",2

OK

AT+MQTTCFG=1,"enable"
+MQTTCFG: 1,"enable",1

OK

AT+MQTTCFG=1,"publish_1_topic","up/data"
+MQTTCFG: 1,"publish_1_topic","up/data"

OK
```

---

## 6. AT+MQTTAUTH {#6-atmqttauth}

一次写入该通道 `auth1`～`auth4`。`auth1` **必填且非空**。后面三项可省略；省略的项写成**空串**（会清掉原来的值）。

### 6.1 测试命令

```lua
AT+MQTTAUTH=?
```

```lua
+MQTTAUTH: (id,auth1,[auth2],[auth3],[auth4])
id:1-4
query: AT+MQTTAUTH=<id>?

OK
```

### 6.2 查询

```lua
AT+MQTTAUTH=<id>?
```

```lua
+MQTTAUTH: <id>,"<auth1>","<auth2>","<auth3>","<auth4>"

OK
```

未配置时四段都可能是 `""`。

### 6.3 设置

```lua
AT+MQTTAUTH=<id>,<auth1>[,<auth2>[,<auth3>[,<auth4>]]]
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<auth1>` | 字符串 | 1～127，非空 | 普通平台 = ClientId |
| `<auth2>` | 字符串 | 0～127 | 可省略；省略则清空 |
| `<auth3>` | 字符串 | 0～127 | 可省略；省略则清空 |
| `<auth4>` | 字符串 | 0～127 | 可省略；省略则清空。仅 DoIoT 参与 ClientId |

只想改 `auth2` 而保留其它：先查再四段一起写。只发 `auth1` 会把 2～4 清掉。

**应答（成功）** 回显四段，与查询同形。

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或 id 不是数字 |
| `id` | 不是 1～4 |
| `auth1` | 空、过长、或解析失败 |
| `auth2` / `auth3` / `auth4` | 对应段解析失败或过长 |
| `read` | 读持久化失败 |
| `save` | 写入失败 |

### 6.4 示例

```lua
AT+MQTTAUTH=1,"device001","user","pass"
+MQTTAUTH: 1,"device001","user","pass",""

OK

AT+MQTTAUTH=1?
+MQTTAUTH: 1,"device001","user","pass",""

OK
```

---

## 7. AT+MQTTPLATFORM {#7-atmqttplatform}

写/查平台类型。设置只接受字符串；查询也回字符串。数字 0/1/2 请用 `AT+MQTTCFG` 的 `platform`。

### 7.1 测试命令

```lua
AT+MQTTPLATFORM=?
```

```lua
+MQTTPLATFORM: (id,"platform")
platform: normal/onenet/doiot
query: AT+MQTTPLATFORM=<id>?

OK
```

### 7.2 查询

```lua
AT+MQTTPLATFORM=<id>?
```

```lua
+MQTTPLATFORM: <id>,"<platform>"

OK
```

`<platform>` 为 `normal` / `onenet` / `doiot`。无法识别的存量值按 `normal` 打出。

### 7.3 设置

```lua
AT+MQTTPLATFORM=<id>,"<platform>"
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<platform>` | 字符串 | `normal` / `onenet` / `doiot` | **大小写不敏感** |

其它拼写 → `"error platform"`。必须是字符串类型，写 `0` 当数字会 `param`。

**应答（成功）** 回显规范化小写名，与查询同形。

**失败**：`param`、`id`、`platform`、`read`、`save`。

### 7.4 示例

```lua
AT+MQTTPLATFORM=1,"onenet"
+MQTTPLATFORM: 1,"onenet"

OK

AT+MQTTPLATFORM=1?
+MQTTPLATFORM: 1,"onenet"

OK
```

---

## 8. AT+MQTTSUB {#8-atmqttsub}

配置订阅槽。设置只改该槽的 `topic` / `qos`，并把该槽 `retain` **写成 0**。空主题表示该槽不用。

### 8.1 测试命令

```lua
AT+MQTTSUB=?
```

```lua
+MQTTSUB: (id,topic_id,"topic",qos)
id:1-4 topic_id:1-10 qos:0-2
query all:     AT+MQTTSUB?
query by id:   AT+MQTTSUB=<id>?

OK
```

### 8.2 查询全部通道

```lua
AT+MQTTSUB?
```

按通道 1→4、槽 1→10 连续输出。**每一行带 retain**（订阅槽业务上不用，但存量会打出来）：

```lua
+MQTTSUB: <id>,<topic_id>,"<topic>",<qos>,<retain>
```

最后 `OK`。读失败 → `"error read"`。

### 8.3 按通道查询

```lua
AT+MQTTSUB=<id>?
```

只打该通道 10 个槽，**没有 retain 字段**：

```lua
+MQTTSUB: <id>,<topic_id>,"<topic>",<qos>
```

### 8.4 设置

```lua
AT+MQTTSUB=<id>,<topic_id>,<topic>,<qos>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<topic_id>` | 整数 | 1～10 | 订阅槽 |
| `<topic>` | 字符串 | 0～127 | 必须是字符串类型；空串表示清空该槽 |
| `<qos>` | 整数 | 0～2 | |

通道号或槽号越界都回 `"error id"`。主题过长或 QoS 不是 0～2 → `"error value"`。

**应答（成功）**

```lua
+MQTTSUB: <id>,<topic_id>,"<topic>",<qos>

OK
```

**失败**：`param`、`id`、`value`、`read`、`save`。

### 8.5 示例

```lua
AT+MQTTSUB=1,1,"down/cmd",1
+MQTTSUB: 1,1,"down/cmd",1

OK

AT+MQTTSUB=1?
+MQTTSUB: 1,1,"down/cmd",1
+MQTTSUB: 1,2,"",0
...
OK
```

---

## 9. AT+MQTTPUB {#9-atmqttpub}

配置发布槽。`MQTTCLRRET` / 按槽发送走的就是这些主题。

### 9.1 测试命令

```lua
AT+MQTTPUB=?
```

```lua
+MQTTPUB: (id,topic_id,"topic",qos,retain)
id:1-4 topic_id:1-10 qos:0-2 retain:0-1
query all:     AT+MQTTPUB?
query by id:   AT+MQTTPUB=<id>?

OK
```

### 9.2 查询

`AT+MQTTPUB?` 打全部通道全部槽；`AT+MQTTPUB=<id>?` 打单通道 10 槽。行格式相同，都带 retain：

```lua
+MQTTPUB: <id>,<topic_id>,"<topic>",<qos>,<retain>
```

### 9.3 设置

```lua
AT+MQTTPUB=<id>,<topic_id>,<topic>,<qos>,<retain>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<topic_id>` | 整数 | 1～10 | 发布槽 |
| `<topic>` | 字符串 | 0～127 | 必须是字符串 |
| `<qos>` | 整数 | 0～2 | |
| `<retain>` | 整数 | 0 或 1 | |

越界 id / topic_id → `"error id"`。主题过长或 qos/retain 非法 → `"error value"`。

**应答（成功）** 与查询行同形，再 `OK`。

**失败**：`param`、`id`、`value`、`read`、`save`。

### 9.4 示例

```lua
AT+MQTTPUB=1,1,"up/data",1,0
+MQTTPUB: 1,1,"up/data",1,0

OK
```

---

## 10. AT+MQTTSYNC {#10-atmqttsync}

在指定通道上 **同步自由发布**：不改发布槽表，用本次给出的主题 / QoS / retain 立刻发。调用一直等到发布接口返回。

**仅设置，无查询。** 载荷可省略或为空，表示发空包。

### 10.1 测试命令

```lua
AT+MQTTSYNC=?
```

```lua
+MQTTSYNC: (id,"topic",qos,retain,rsp,<TAILRAW>?)
id:1-4 qos:0-2 retain:0-1 rsp:0/1
set only: AT+MQTTSYNC=<id>,"<topic>",<qos>,<retain>,<rsp>[,<TAILRAW>]
payload omitted/empty means send empty packet

OK
```

### 10.2 设置

```lua
AT+MQTTSYNC=<id>,<topic>,<qos>,<retain>,<rsp>[,<payload>]
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<topic>` | 字符串 | 1～127，非空 | 本次主题，不写进配置 |
| `<qos>` | 整数 | 0～2 | |
| `<retain>` | 整数 | 0 或 1 | |
| `<rsp>` | 整数 | 0 或 1 | `1`：成功/失败都有 AT 应答；`0`：发布成败**完全静默** |
| `<payload>` | TAILRAW | 可省略 | 第五个逗号之后的原始字节。省略或长度为 0 = 空包 |

第五参之后若出现但不是 TAILRAW → `"error data"`。

**应答（`rsp=1` 且成功）**

```lua
+MQTTSYNC: <id>,"<topic>",<qos>,<retain>,1,<len>

OK
```

`<len>` 为**交给发布接口的原始载荷字节数**（省略则为 0）。不是对端已收到的长度。

**应答（`rsp=1` 且发布失败）**

```lua
+MQTTSYNC: "error send"

ERROR
```

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或 id 不是数字 |
| `id` | 不是 1～4 |
| `topic` | 空或过长、解析失败 |
| `qos` | 不是 0～2 |
| `retain` | 不是 0/1 |
| `rsp` | 不是 0/1 |
| `data` | 第六参存在但不是裸数据 |
| `send` | 通道未起、未连接、底层发布失败 |

**`rsp=0`**：发布成功或 `send` 失败都没有 `+MQTTSYNC` / `OK` / `ERROR`。解析错误仍会回 ERROR。

### 10.3 示例

```lua
AT+MQTTSYNC=1,"up/data",0,0,1,hello
+MQTTSYNC: 1,"up/data",0,0,1,5

OK
```

静默发送（主机看不到 OK）：

```lua
AT+MQTTSYNC=1,"up/data",0,0,0,hello
```

空包：

```lua
AT+MQTTSYNC=1,"up/data",0,1,1
+MQTTSYNC: 1,"up/data",0,1,1,0

OK
```

### 10.4 说明

- 同步发布会占住这条 AT 处理，对端堵塞时 AT 口会停一阵。
- 本指令**不**把订阅下行当 AT 应答吐出来。下行走 RTU / Lua 回调。
- 主题和载荷会按 `[maping]` 的 MQTT 主题 / 发布规则展开。主题展开失败、载荷展开失败或映射缓冲申请失败，都会变成 `"error send"`，**不会**改发原文。成功应答里的 `<len>` 仍是 AT 行上的原始字节数，不是展开后的长度。

---

## 11. AT+MQTTASYNC {#11-atmqttasync}

把一次自由发布 **排进发送队列后返回**，不在 AT 调用里等发完。参数与 `MQTTSYNC` 相同。

**当前须通道已连接。** 未连接或入队失败时，`rsp=1` 得到 `"error enqueue"`；`rsp=0` 静默失败。

### 11.1 测试命令

```lua
AT+MQTTASYNC=?
```

```lua
+MQTTASYNC: (id,"topic",qos,retain,rsp,<TAILRAW>?)
id:1-4 qos:0-2 retain:0-1 rsp:0/1
set only: AT+MQTTASYNC=<id>,"<topic>",<qos>,<retain>,<rsp>[,<TAILRAW>]
rsp=1 时仅表示是否成功入队（且当前需已连接）

OK
```

### 11.2 设置

```lua
AT+MQTTASYNC=<id>,<topic>,<qos>,<retain>,<rsp>[,<payload>]
```

`rsp=1` 成功：

```lua
+MQTTASYNC: <id>,"<topic>",<qos>,<retain>,1,<len>

OK
```

`<len>` 是入队前的原始长度，**不是**对端已收到的长度。

失败 reason：`param` / `id` / `topic` / `qos` / `retain` / `rsp` / `data` / **`enqueue`**。

`rsp=0`：发布成败无任何 AT 应答；解析错误仍回 ERROR。

### 11.3 示例

```lua
AT+MQTTASYNC=1,"up/data",0,0,1,hello
+MQTTASYNC: 1,"up/data",0,0,1,5

OK
```

未连上：

```lua
AT+MQTTASYNC=1,"up/data",0,0,1,hello
+MQTTASYNC: "error enqueue"

ERROR
```

### 11.4 对照

| | `MQTTSYNC` | `MQTTASYNC` |
| --- | --- | --- |
| 等待 | 等到发布调用返回 | 入队成功即返回 |
| 须已连接 | 通常要（否则 `send`） | **必须**已连接（否则 `enqueue`） |
| `rsp=0` | 无应答 | 无应答 |
| 回包 | 都不从本指令返回 | 同左 |

---

## 12. AT+MQTTCLRRET {#12-atmqttclrret}

向该通道**已配置的发布槽**发一包 **空载荷**，用来清 broker 上该主题的 retain。立刻执行，不改配置。

**仅设置，无查询。**

测试应答与解析规则里的槽号是 **1～8**（不是 1～10）。槽 9、10 请用 `MQTTSYNC` 对同一主题发空包 + retain=1。

### 12.1 测试命令

```lua
AT+MQTTCLRRET=?
```

```lua
+MQTTCLRRET: (id,topic_id)
id:1-4 topic_id:1-8
send empty payload to clear retained publish message

OK
```

### 12.2 设置

```lua
AT+MQTTCLRRET=<id>,<topic_id>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<topic_id>` | 整数 | 1～8 | 发布槽。该槽主题为空或通道未连都会 `send` |

**应答（成功）**

```lua
+MQTTCLRRET: <id>,<topic_id>

OK
```

**失败**

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或不是数字 |
| `id` | 通道不是 1～4，或槽号不是 1～10（解析层若先拦 1～8，可能根本进不了回调） |
| `send` | 未连接、槽主题空、底层发送失败 |

没有 `rsp` 参数：成败都会回 `+MQTTCLRRET` 或 `"error …"`。

### 12.3 示例

```lua
AT+MQTTCLRRET=1,1
+MQTTCLRRET: 1,1

OK
```

---

## 13. AT+MQTTWILL {#13-atmqttwill}

一次写入该通道遗嘱五项。只落盘，不拆当前连接；下次连上才带新遗嘱。

### 13.1 测试命令

```lua
AT+MQTTWILL=?
```

```lua
+MQTTWILL: (id,enable,"topic",qos,retain,"message")
id:1-4 enable:0/1 qos:0-2 retain:0/1
query: AT+MQTTWILL=<id>?

OK
```

### 13.2 查询

```lua
AT+MQTTWILL=<id>?
```

```lua
+MQTTWILL: <id>,<enable>,"<topic>",<qos>,<retain>,"<message>"

OK
```

### 13.3 设置

```lua
AT+MQTTWILL=<id>,<enable>,<topic>,<qos>,<retain>,<message>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<enable>` | 整数 | 0 或 1 | 总开关。0 时后四项仍入库 |
| `<topic>` | 字符串 | 0～127 | 必须是字符串 |
| `<qos>` | 整数 | 0～2 | |
| `<retain>` | 整数 | 0 或 1 | |
| `<message>` | 字符串 | 0～255 | 必须是字符串 |

越界或主题/消息过长 → `"error value"`。

**应答（成功）** 与查询同形。

**失败**：`param`、`id`、`value`、`read`、`save`。

### 13.4 示例

```lua
AT+MQTTWILL=1,1,"will/offline",0,1,"offline"
+MQTTWILL: 1,1,"will/offline",0,1,"offline"

OK
```

---

## 14. 错误一览

统一形态：`+<CMD>: "error <reason>"` + `ERROR`（`rsp=0` 且已通过解析的发送指令除外）。

| reason | 出现指令 | 含义 |
| --- | --- | --- |
| `param` | 全部 | 参数个数、类型不对 |
| `id` | 全部 | 通道不是 1～4，或主题槽越界 |
| `ip` | MQTT | 主机空或过长 |
| `port` | MQTT | 端口不是 1～65535 |
| `key` | MQTTCFG | key 空或不是已公布名字 |
| `value` | MQTTCFG / MQTTSUB / MQTTPUB / MQTTWILL | 值解析失败或越界 |
| `read` | 配置类 | 读持久化失败 |
| `save` | 配置类 | 写入失败 |
| `overflow` | MQTTCFG 全量查询 | 回包拼爆缓冲 |
| `malloc` | MQTTCFG 全量查询 | 内存不足 |
| `auth1`～`auth4` | MQTTAUTH | 对应段空/过长/解析失败 |
| `platform` | MQTTPLATFORM | 不是 `normal` / `onenet` / `doiot` |
| `topic` | MQTTSYNC / MQTTASYNC | 主题空或过长 |
| `qos` | MQTTSYNC / MQTTASYNC | 不是 0～2 |
| `retain` | MQTTSYNC / MQTTASYNC | 不是 0/1 |
| `rsp` | MQTTSYNC / MQTTASYNC | 不是 0/1 |
| `data` | MQTTSYNC / MQTTASYNC | 第六参不是 TAILRAW |
| `send` | MQTTSYNC / MQTTCLRRET | 同步发布或清 retain 失败 |
| `enqueue` | MQTTASYNC | 异步入队失败（未连接、队列满等） |

---

## 15. 联调顺序

1. 驻网完成（CSQ / CEREG 正常）。
2. `AT+MQTT=1,"<broker>",1883` 配主机端口并 `enable=1`。
3. `AT+MQTTPLATFORM=1,"normal"`，再 `AT+MQTTAUTH=1,"<clientId>","<user>","<pass>"`。
4. 需要 TLS：先按 [ssl.md](ssl.md) 写入证书组，再 `AT+MQTTCFG=1,"ssl_id",1` 与 `AT+MQTTCFG=1,"ssl_level",2`。
5. `AT+MQTTSUB=1,1,"down/cmd",1`，`AT+MQTTPUB=1,1,"up/data",1,0`。需要遗嘱则 `AT+MQTTWILL`。
6. 确认 RTU 任务该路已使能且 `task_id` 指向 MQTT。等通道起来。
7. `AT+MQTTSYNC=1,"up/data",0,0,1,ping` 看是否 `OK` 且 `<len>` 合理。
8. 改地址后若仍连旧 broker：先按产品流程重启该通道或复位，再发。

完整细项用 `AT+MQTTCFG=1?` 与 `rtu_config.cfg` 的 `[mqtt.1]` 对照。主题槽也可用 `AT+MQTTSUB=1?` / `AT+MQTTPUB=1?`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：MQTT / MQTTCFG / MQTTAUTH / MQTTPLATFORM / MQTTSUB / MQTTPUB / MQTTSYNC / MQTTASYNC / MQTTCLRRET / MQTTWILL 的测试、查询、设置、错误与示例 |
