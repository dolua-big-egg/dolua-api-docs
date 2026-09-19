# MQTT 连接专栏

**文档版本** `1.0.0`

场景专题：用应用 AT 把一路或多路 **MQTT** 连上 broker，再走串口透传或指令主动发布。指令逐条的测试/查询/设置、参数表、错误码见 [MQTT 指令手册](../manual/mqtt.md)、[透传任务](../manual/rtu.md)、[路由串](../manual/route.md)、[SSL](../manual/ssl.md)。本篇不重复那些表格。

这不是 Lua `require("mqtt")` 里另开的客户端对象。通道号与 `[mqtt.N]` / `AT+DTUTASK=<N>` **同一路 1～4**，和 Socket 任务抢同一组编号。

---

## 目录

- [1. 先建立图景](#1-先建立图景)
- [2. 联调前：驻网与生效](#2-联调前驻网与生效)
- [3. 单通道](#3-单通道)
- [4. 多通道](#4-多通道)
- [5. 混合通道](#5-混合通道)
- [6. 透传配置](#6-透传配置)
- [7. 指令主动发送](#7-指令主动发送)
- [8. 同步与异步](#8-同步与异步)
- [9. 平台、鉴权、TLS、遗嘱](#9-平台鉴权tls遗嘱)
- [10. 心跳、注册包](#10-心跳注册包)
- [11. 常见失败](#11-常见失败)
- [12. 对照手册](#12-对照手册)
- [修订记录](#修订记录)

---

## 1. 先建立图景

四路常驻网络任务，每路在某一时刻只能是 **MQTT** 或 **SOCK**。MQTT 这一路再配 broker、鉴权、最多 10 个订阅槽 + 10 个发布槽。透传上行走到的是**发布槽**；路由串只能写到槽 1～8，槽 9、10 留给 `MQTTSYNC` / `MQTTASYNC` 自由主题。

```lua
UART 数据口 ──AT+DTUPSUP──► 任务 N（MQTT）发布槽 ──► broker
broker 下行（已订阅）──AT+DTUPSDN──► UART / 其它出口
AT 口主动发 ──AT+MQTTSYNC / MQTTASYNC / RTUWRITE──► 同一路任务
```

| 角色 | 谁来配 | 说明 |
| --- | --- | --- |
| broker 主机/端口 | `AT+MQTT` | 顺带 `enable=1`；不立刻断开旧连接 |
| 平台 / 三元组 | `AT+MQTTPLATFORM` + `AT+MQTTAUTH` | `normal` / `onenet` / `doiot` 对 `auth1`～`auth4` 含义不同 |
| 订阅 / 发布槽 | `AT+MQTTSUB` / `AT+MQTTPUB` | 透传和 `RTUWRITE` 走发布槽 |
| 这一路是不是 MQTT | `AT+DTUTASK=<id>,1,"MQTT"` | 没开任务，光写 `AT+MQTT` 也发不出去 |
| 串口 → 网络 | `AT+DTUPSUP` | 路由里的子通道 = 发布槽号 |
| 网络 → 串口 | `AT+DTUPSDN` | 订阅到的载荷按该路下行出口走 |
| AT 口立刻发一包 | `AT+MQTTSYNC` / `AT+MQTTASYNC` | 主题当场指定，**不写进**发布槽 |

**AT 口和透传数据口尽量分开。** 配置走主串口 / USB AT；MCU 业务数据走另一路 UART。同一口既当 AT 又当透传时，以 `AT` 开头的行会被当指令。共用一口时配完用 [AT+RTUPSD](../manual/rtu.md#8-atrtuctl--atrtupsd--atdtumsghead) 锁成透传。

下文 `mqtts.doiot.cn:1883` 是公开演示 broker，可换成自己的。载荷是 **TAILRAW**。主题、载荷里的 `<#IMEI>` 按 `[maping]` 展开。

---

## 2. 联调前：驻网与生效

```lua
AT
OK

AT+ISLINK
+ISLINK: 1

OK
```

写完 broker / 鉴权 / 主题 / `DTUTASK` 后，**默认不拆已经建立的连接**。第一次使能或改了地址，按产品流程 `AT+RESET`。复位后：

```lua
AT+ISLINK
+ISLINK: 1

OK

AT+DTUSTATE=1
+DTUSTATE: 1,<state>

OK
```

本次开机临时断开/恢复：`AT+RTUCTL=1,0` / `AT+RTUCTL=1,1`。暂停时常会看到类似 `+MQTT-DISCONNECTED:1,"…"` 的上报，恢复后再连。

---

## 3. 单通道

目标：通道 1 连一台普通 MQTT 服务器；订阅下行主题；发布槽 1 给透传；AT 口还能自由发布。

### 3.1 配 broker、平台、鉴权、主题

```lua
AT+MQTT=1,"mqtts.doiot.cn",1883
+MQTT: 1,"mqtts.doiot.cn",1883

OK

AT+MQTTPLATFORM=1,"normal"
+MQTTPLATFORM: 1,"normal"

OK

AT+MQTTAUTH=1,"my-client","user","pass",""
+MQTTAUTH: 1,"my-client","user","pass",""

OK

AT+MQTTSUB=1,1,"/server/<#IMEI>",0
+MQTTSUB: 1,1,"/server/<#IMEI>",0

OK

AT+MQTTPUB=1,1,"/device/<#IMEI>",0,0
+MQTTPUB: 1,1,"/device/<#IMEI>",0,0

OK

AT+DTUTASK=1,1,"MQTT"
+DTUTASK: 1,1,"MQTT"

OK
```

无用户名密码时 `auth2` / `auth3` 留空串。`AT+MQTTAUTH` 四个字符串都会入库；`normal` 下第四段无意义。

查询本路发布槽：

```lua
AT+MQTTPUB=1?
+MQTTPUB: 1,1,"/device/<#IMEI>",0,0
+MQTTPUB: 1,2,"",0,0
…

OK
```

### 3.2 透传：UART1 ↔ 通道 1 发布槽 1

```lua
AT+DTUPSUP=1,"1"
+DTUPSUP: 1,"1"

OK

AT+DTUPSDN=1,"6[1]"
+DTUPSDN: 1,"6[1]"

OK
```

路由 `1` 默认子通道 1，等于 `1[1]`：UART1 的每一包发到 **通道 1 的发布槽 1**（主题即上面配的 `/device/<#IMEI>`）。下行：broker 推到已订阅主题的消息，送到 UART1。

MCU 接 UART2：

```lua
AT+DTUPSUP=2,"1"
AT+DTUPSDN=1,"6[2]"
```

同一路 UART 要把数据发到本通道两个发布槽：

```lua
AT+MQTTPUB=1,2,"/device/<#IMEI>/alarm",0,0
AT+DTUPSUP=1,"1[1:2]"
```

然后 `AT+RESET`，等驻网。UART 数据口写字节即可；透传底层走 MQTT 异步发送队列。

### 3.3 指令主动发送（单通道）

自由主题（不必事先写进 `MQTTPUB` 槽）：

```lua
AT+MQTTSYNC=1,"/device/<#IMEI>",0,0,1,hello
+MQTTSYNC: 1,"/device/<#IMEI>",0,0,1,5

OK

AT+MQTTASYNC=1,"/device/<#IMEI>",0,0,1,hello
+MQTTASYNC: 1,"/device/<#IMEI>",0,0,1,5

OK
```

按发布槽写（走路由，主题用槽里已配的）：

```lua
AT+RTUWRITE="1",hello
OK
```

清 broker 上某主题的 retain：空包 + `retain=1`，或对已配槽用 `AT+MQTTCLRRET`。

```lua
AT+MQTTSYNC=1,"/device/<#IMEI>",0,1,1
+MQTTSYNC: 1,"/device/<#IMEI>",0,1,1,0

OK

AT+MQTTCLRRET=1,1
+MQTTCLRRET: 1,1

OK
```

### 3.4 单通道联调顺序（可抄）

```lua
AT+ISLINK
AT+MQTT=1,"mqtts.doiot.cn",1883
AT+MQTTPLATFORM=1,"normal"
AT+MQTTAUTH=1,"my-client","","",""
AT+MQTTSUB=1,1,"/server/<#IMEI>",0
AT+MQTTPUB=1,1,"/device/<#IMEI>",0,0
AT+DTUTASK=1,1,"MQTT"
AT+DTUPSUP=1,"1"
AT+DTUPSDN=1,"6[1]"
AT+RESET
```

复位、驻网后：

```lua
AT+ISLINK
AT+DTUSTATE=1
AT+MQTTSYNC=1,"/device/<#IMEI>",0,0,1,ping
```

---

## 4. 多通道

目标：两路 MQTT 各连一台 broker（或同一台不同 clientId），主题互不干扰。

```lua
AT+MQTT=1,"mqtts.doiot.cn",1883
AT+MQTTPLATFORM=1,"normal"
AT+MQTTAUTH=1,"client-a","","",""
AT+MQTTSUB=1,1,"/server/a",0
AT+MQTTPUB=1,1,"/device/a",0,0
AT+DTUTASK=1,1,"MQTT"

AT+MQTT=2,"broker.example.com",1883
AT+MQTTPLATFORM=2,"normal"
AT+MQTTAUTH=2,"client-b","","",""
AT+MQTTSUB=2,1,"/server/b",0
AT+MQTTPUB=2,1,"/device/b",0,0
AT+DTUTASK=2,1,"MQTT"
```

UART1 同时上行到两路的发布槽 1：

```lua
AT+DTUPSUP=1,"1|2"
AT+DTUPSDN=1,"6[1]"
AT+DTUPSDN=2,"6[1]"
```

拆开：通道 1 ↔ UART1，通道 2 ↔ UART2：

```lua
AT+DTUPSUP=1,"1"
AT+DTUPSUP=2,"2"
AT+DTUPSDN=1,"6[1]"
AT+DTUPSDN=2,"6[2]"
```

AT 口分别发布：

```lua
AT+MQTTSYNC=1,"/device/a",0,0,1,from-ch1
+MQTTSYNC: 1,"/device/a",0,0,1,8

OK

AT+MQTTASYNC=2,"/device/b",0,0,1,from-ch2
+MQTTASYNC: 2,"/device/b",0,0,1,8

OK
```

查询全部通道全部发布槽：`AT+MQTTPUB?`。四路上限 1～4，不需要的路 `AT+DTUTASK=<id>,0,"MQTT"`。

---

## 5. 混合通道

目标：通道 1 MQTT，通道 2 Socket。**同一 `<id>` 不能两边都开。** Socket 侧逐步说明见 [Socket 专栏](socket.md)。

```lua
AT+MQTT=1,"mqtts.doiot.cn",1883
+MQTT: 1,"mqtts.doiot.cn",1883

OK

AT+MQTTPLATFORM=1,"normal"
AT+MQTTAUTH=1,"my-client","","",""
AT+MQTTSUB=1,1,"/server/demo",0
AT+MQTTPUB=1,1,"/device/demo",0,0
AT+DTUTASK=1,1,"MQTT"
+DTUTASK: 1,1,"MQTT"

OK

AT+SOCK=2,"socket.doiot.cn",5000,0
+SOCK: 2,"socket.doiot.cn",5000,0

OK

AT+DTUTASK=2,1,"SOCK"
+DTUTASK: 2,1,"SOCK"

OK
```

UART1 上行：MQTT 走通道 1 发布槽 1，Socket 走通道 2 整包：

```lua
AT+DTUPSUP=1,"1|2"
+DTUPSUP: 1,"1|2"

OK

AT+DTUPSDN=1,"6[1]"
AT+DTUPSDN=2,"6[1]"
```

MQTT 若还要槽 2：

```lua
AT+MQTTPUB=1,2,"/device/demo/alarm",0,0
AT+DTUPSUP=1,"1[1:2]|2"
```

复位后分别主动发：

```lua
AT+MQTTSYNC=1,"/device/demo",0,0,1,hello-mqtt
+MQTTSYNC: 1,"/device/demo",0,0,1,10

OK

AT+SOCKSYNC=2,1,hello-tcp
+SOCKSYNC: 2,1,9

OK
```

两路异步队列相互独立。

---

## 6. 透传配置

透传 = 任务已使能 + 上行点到**非空发布槽** + 下行点到实际接线的 UART。

### 6.1 常用组合

| 需求 | 上行 | 下行 |
| --- | --- | --- |
| UART1 → 通道 1 发布槽 1 | `AT+DTUPSUP=1,"1"` | `AT+DTUPSDN=1,"6[1]"` |
| UART2 → 通道 1（AT 仍在 UART1） | `AT+DTUPSUP=2,"1"` | `AT+DTUPSDN=1,"6[2]"` |
| UART1 → 通道 1 的槽 1 和槽 2 | `AT+DTUPSUP=1,"1[1:2]"` | 不变 |
| UART1 同时上到 MQTT 1 和 SOCK 2 | `AT+DTUPSUP=1,"1\|2"` | 每路各自 `DTUPSDN` |
| 关掉某路 UART 上行 | `AT+DTUPSUP=1,""` | — |

选中的 MQTT 槽若主题为空，该槽本次不发；槽全空等于没发出去。路由写 `1[9]` 非法（路由串最多槽 8）。

查询：

```lua
AT+DTUPSUP=1?
AT+DTUPSDN=1?
AT+MQTTSUB=1?
AT+MQTTPUB=1?
```

### 6.2 和 AT 口的关系

与 Socket 相同：业务 MCU 不要和 AT 工具抢一口；共用时再 `RTUPSD`。调试可 `AT+DTUMSGHEAD=1`。

### 6.3 分包与队列

串口按 [AT+UARTQUE](../manual/uart.md) 切包后入 MQTT 异步队列。公开演示口径：每路大约 **48 KB**，溢出丢弃；与 Socket 异步队列分开。

---

## 7. 指令主动发送

| 指令 | 主题从哪来 | 成功时 | 适合 |
| --- | --- | --- | --- |
| `AT+MQTTSYNC=<id>,<topic>,<qos>,<retain>,<rsp>[,<payload>]` | 本条当场指定 | `rsp=1` 回交给发布接口的原始长度 | 要确认发布调用返回 |
| `AT+MQTTASYNC=…`（参数相同） | 本条当场指定 | `rsp=1` 只表示入队且当前已连接 | 高频、不堵 AT 口 |
| `AT+RTUWRITE="<路由>",<payload>` | 路由选中的发布槽 | 回 `OK` | 走已配槽、一包多槽 |
| `AT+RTUWRITEQ=…` | 同上 | **成功完全静默** | 嵌在透传流里 |
| `AT+MQTTCLRRET=<id>,<topic_id>` | 该发布槽 | 空包清 retain | 槽 1～8 |

`rsp=0` 时发布成败都不回 `+CMD` / `OK` / `ERROR`；**解析错误仍回 ERROR**。

```lua
AT+MQTTSYNC=1,"/device/demo",0,0,0,hello

AT+MQTTASYNC=1,"/device/demo",1,0,1,hello
+MQTTASYNC: 1,"/device/demo",1,0,1,5

OK

AT+RTUWRITE="1[1:2]",hello
OK
```

通道未起、未连接：

```lua
AT+MQTTSYNC=1,"/device/demo",0,0,1,hello
+MQTTSYNC: "error send"

ERROR

AT+MQTTASYNC=1,"/device/demo",0,0,1,hello
+MQTTASYNC: "error enqueue"

ERROR
```

主动发布**不会**把订阅下行夹在 `+MQTTSYNC` 里返回。下行走 `DTUPSDN` / Lua 回调。

QoS 非 0 时同步发布会在 AT 口上多等一会儿（对端堵塞或低功耗时更明显）。透传不要指望 QoS 2 还保持低延迟。

---

## 8. 同步与异步

| | `MQTTSYNC` | `MQTTASYNC` | 串口透传 |
| --- | --- | --- | --- |
| 等待 | 等到发布调用返回 | 入队成功即返回 | 入队 |
| 须已连接 | 通常要（否则 `send`） | **必须**（否则 `enqueue`） | 通道须已起来 |
| `rsp=1` 的含义 | 发布调用结果 | 是否进队列 | 无此参数 |
| 空包 | 可省略 payload | 同左 | 取决于串口是否真的给出了 0 长度包 |
| 队列 | 无 | 每路独立，溢出丢弃 | 同左 |

选法：

- 要知道这次发布调用有没有返回成功：`MQTTSYNC` 且 `rsp=1`。严格投递再靠 QoS 或业务应答，不要只信这一条 `OK`。
- 连续上报、不能堵 AT：`MQTTASYNC`。
- 串口 MCU 一直推流：透传 + 配好发布槽，不要每包套 `AT+MQTT*`。
- 主题每次不同：必须 `MQTTSYNC` / `MQTTASYNC`，透传只会打到槽里写死的主题。

---

## 9. 平台、鉴权、TLS、遗嘱

### 9.1 平台 × auth

`AT+MQTTPLATFORM` 写字符串；`AT+MQTTCFG` 的 `platform` 是数字 0/1/2。连上时才按平台解释 `auth1`～`auth4`，入库阶段不校验三元组能不能连。

| 平台 | `auth1` | `auth2` | `auth3` | `auth4` |
| --- | --- | --- | --- | --- |
| `"normal"` | ClientId | 用户名 | 密码 | 忽略 |
| `"onenet"` | ClientId | 用户名 | 密码 | 忽略 |
| `"doiot"` | ClientId | 用户名 | 密码 | user_id |

度云演示常用（ClientId 用 IMEI 占位符，连上时展开）：

```lua
AT+MQTTPLATFORM=1,"doiot"
+MQTTPLATFORM: 1,"doiot"

OK

AT+MQTTAUTH=1,"<#IMEI>","doiot","doiot",""
+MQTTAUTH: 1,"<#IMEI>","doiot","doiot",""

OK
```

OneNET 连上时会按平台规则强制 `clean_session=1`。更细的拼法见 [rtu_config 第 10.2 节](../../api/rtu_config/rtu_config.md#102-platform--auth联合)。

### 9.2 TLS

`ssl_level`：`0` 关；`1` 不校验；`2` 校验服务端；`3` 双向。`ssl_id` 引用证书组 **1～3**（不是 MQTT 通道号）。先按 [ssl.md](../manual/ssl.md) 写入证书，再：

```lua
AT+MQTTCFG=1,"ssl_id",1
AT+MQTTCFG=1,"ssl_level",2
```

明文 1883 保持 `ssl_level=0`。改 TLS 后同样要复位才作用于新连接。

### 9.3 遗嘱

只落盘，下次 CONNECT 才带上：

```lua
AT+MQTTWILL=1,1,"will/offline",0,1,"offline"
+MQTTWILL: 1,1,"will/offline",0,1,"offline"

OK
```

---

## 10. 心跳、注册包

MQTT 协议层已有 keepalive（默认常见 60 s，`AT+MQTTCFG` 的 `keepalive_interval`）。应用层心跳/注册包是额外的业务包，发到**本路发布槽**列表，语法不是路由串。

```lua
AT+DTUHEART=1,1,300,"3C23494D45493E","1"
+DTUHEART: 1,1,300,"3C23494D45493E","1"

OK

AT+DTUREG=1,1,"3C2349434349443E","1"
+DTUREG: 1,1,"3C2349434349443E","1"

OK
```

`"1"` 表示发布槽 1；多槽写成 `"1|2"`。不要写成 `"6[1]"`，那不会出 UART。hex 包是十六进制文本：`3C23494D45493E` = `<#IMEI>`，`3C2349434349443E` = `<#ICCID>`。

---

## 11. 常见失败

| 现象 | 先查 |
| --- | --- |
| `"error send"` / `"error enqueue"` | `DTUTASK` 是否 MQTT、是否已复位生效、是否已 CONNECT；`rsp=0` 时失败也静默 |
| 改了 broker 仍连旧地址 | 写配置不拆旧连接 |
| 透传有串口数据但 broker 没有 | 发布槽主题是否为空；`DTUPSUP` 子通道是否指向有主题的槽 |
| 订阅能在其它客户端看到，MCU 没有 | `MQTTSUB` 是否写入并已重连；`DTUPSDN` 是否指向接线 UART |
| `1[9]` 配不上 | 路由串最多槽 8；槽 9、10 用 `MQTTSYNC` |
| TLS 失败 | `ssl_id` 1～3、证书组、`ssl_level`，改完要重连 |
| AT 口不再认指令 | `RTUPSD` 后需 `RTULOCK` |

错误短 reason 全表见 [mqtt.md 第 14 节](../manual/mqtt.md#14-错误一览)。

---

## 12. 对照手册

| 要查 | 去 |
| --- | --- |
| `MQTT` / `MQTTCFG` / `MQTTAUTH` / `MQTTPLATFORM` / `MQTTSUB` / `MQTTPUB` / `MQTTSYNC` / `MQTTASYNC` / `MQTTCLRRET` / `MQTTWILL` | [mqtt.md](../manual/mqtt.md) |
| `DTUTASK` / `DTUPSUP` / `DTUPSDN` / `RTUWRITE` / 心跳注册 | [rtu.md](../manual/rtu.md) |
| `1[1:2]\|6[1]` 怎么写 | [route.md](../manual/route.md) |
| 证书组 | [ssl.md](../manual/ssl.md) |
| 行格式、通道编号 | [convention.md](../manual/convention.md) |
| 同一路改成 Socket | [Socket 专栏](socket.md) |
| `[mqtt.N]` 全部 key | [rtu_config.cfg](../../api/rtu_config/rtu_config.md#10-mqttn) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-19 | 首版：单通道 / 多通道 / 混合通道、透传、指令主动发送、同步与异步、平台与 TLS |
