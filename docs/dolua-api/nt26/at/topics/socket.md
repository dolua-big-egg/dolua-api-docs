# Socket 专栏

**文档版本** `1.0.1`

场景专题：用应用 AT 把一路或多路 **TCP/UDP Socket** 跑起来，再走串口透传或指令主动发送。指令逐条的测试/查询/设置、参数表、错误码见 [Socket 指令手册](../manual/sock.md)、[透传任务](../manual/rtu.md)、[路由串](../manual/route.md)。本篇不重复那些表格。

这不是 Lua `require("tcp")`。通道号与 `[sock.N]` / `AT+DTUTASK=<N>` **同一路 1～4**。

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
- [9. 保活、心跳、注册包](#9-保活心跳注册包)
- [10. 常见失败](#10-常见失败)
- [11. 对照手册](#11-对照手册)
- [修订记录](#修订记录)

---

## 1. 先建立图景

四路常驻网络任务，每路在某一时刻只能是 **SOCK** 或 **MQTT**，不能同一路两边都开。Socket 这一路再在 TCP / UDP 里二选一。

```lua
UART 数据口 ──AT+DTUPSUP──► 任务 N（SOCK）──► 远端 TCP/UDP
远端回包     ──AT+DTUPSDN──► UART / 其它出口
AT 口主动发  ──AT+SOCKSYNC / SOCKASYNC / RTUWRITE──► 同一路任务
```

| 角色 | 谁来配 | 说明 |
| --- | --- | --- |
| 对端主机/端口/协议 | `AT+SOCK` / `AT+SOCKCFG` | 只写持久化；正在跑的连接仍用启动时的值 |
| 这一路是不是 SOCK | `AT+DTUTASK=<id>,1,"SOCK"` | 没开任务，光写 `AT+SOCK` 也发不出去 |
| 串口 → 网络 | `AT+DTUPSUP` | 上行透传总闸，路由串见 [route.md](../manual/route.md) |
| 网络 → 串口 | `AT+DTUPSDN` | 该路下行出口 |
| AT 口立刻发一包 | `AT+SOCKSYNC` / `AT+SOCKASYNC` / `AT+RTUWRITE` | 不经过串口透传路径 |

**AT 口和透传数据口尽量分开。** 配置走主串口 / USB AT；MCU 业务数据走另一路 UART（常见 UART2）。同一口既当 AT 又当透传时，模组会把以 `AT` 开头的行当指令解析，业务二进制很容易被吃掉。若必须共用一口，配完后用 [AT+RTUPSD](../manual/rtu.md#8-atrtuctl--atrtupsd--atdtumsghead) 把 AT 口锁成透传，解锁才重新进指令。

下文 Socket 对端一律用公开演示 TCP：

| | 值 |
| --- | --- |
| 主机 | `socket.doiot.cn` |
| 端口 | `5000` |
| 协议 | TCP（`AT+SOCK` 的 `proto=0`） |

行为：**发啥回啥**。你发出去的载荷，对端原样从同一条 TCP 连接打回来。特例：发 ASCII `doiot`（5 字节），回的是 `测试成功`，不是再回 `doiot`。回包**不会**夹在 `+SOCKSYNC` 里，要配好 `DTUPSDN` 才能在串口看到。

载荷是 **TAILRAW**：最后一个逗号之后到行结束之前的原始字节，不要先编成 HEX 文本（除非你就是要发 ASCII 的 `41` `42`）。联调自己的服务器时，把主机端口换掉即可，指令形态不变。

---

## 2. 联调前：驻网与生效

```lua
AT
OK

ATI
doiot
NT26-PRO-RTU-E1.1.6
2026-07-09 13:41:00

OK

AT+CSQ
+CSQ: <rssi>,<ber>

OK

AT+ISLINK
+ISLINK: 1

OK
```

`+ISLINK: 1` 再配 Socket。写完 `AT+SOCK` / `AT+DTUTASK` / 路由后，**默认不拆已经建立的连接**。第一次把任务从关改到开、或改了对端，按产品流程 `AT+RESET`（或停通道再启）。复位后等驻网，再查任务是否在跑：

```lua
AT+RESET

AT+ISLINK
+ISLINK: 1

OK

AT+DTUSTATE=1
+DTUSTATE: 1,<state>

OK
```

本次开机临时暂停/恢复这一路（不写盘）用 `AT+RTUCTL=1,0` / `AT+RTUCTL=1,1`，见 [rtu.md](../manual/rtu.md#8-atrtuctl--atrtupsd--atdtumsghead)。

---

## 3. 单通道

目标：通道 1 连一台 TCP 服务器；UART1 与该通道双向透传；AT 口还能主动发。

### 3.1 配 SOCK 并拉起任务

```lua
AT+SOCK=1,"socket.doiot.cn",5000,0
+SOCK: 1,"socket.doiot.cn",5000,0

OK

AT+DTUTASK=1,1,"SOCK"
+DTUTASK: 1,1,"SOCK"

OK

AT+SOCK=1?
+SOCK: 1,"socket.doiot.cn",5000,0

OK
```

`proto=0` 是 TCP，`1` 是 UDP。UDP 通道「上线」只表示实例创建成功，没有 TCP 那种三次握手。`socket.doiot.cn:5000` 是 **TCP 回显口**，必须 `proto=0` 才能「发啥回啥」。UDP 只换协议位，主机端口写法相同，但对着这个演示口没有回显：

```lua
AT+SOCK=1,"socket.doiot.cn",5000,1
+SOCK: 1,"socket.doiot.cn",5000,1

OK
```

### 3.2 透传：UART1 ↔ 通道 1

```lua
AT+DTUPSUP=1,"1"
+DTUPSUP: 1,"1"

OK

AT+DTUPSDN=1,"6[1]"
+DTUPSDN: 1,"6[1]"

OK
```

| 指令 | 含义 |
| --- | --- |
| `DTUPSUP=1,"1"` | UART1 收到的业务数据发到网络通道 1 |
| `DTUPSDN=1,"6[1]"` | 通道 1 从网络收到的数据送到 UART1 |

`6` 是路由串里的 UART 类，`[1]` 是 UART1；不写括号时 `6` 默认也是 UART1。MCU 接 UART2 时改成：

```lua
AT+DTUPSUP=2,"1"
+DTUPSUP: 2,"1"

OK

AT+DTUPSDN=1,"6[2]"
+DTUPSDN: 1,"6[2]"

OK
```

然后 `AT+RESET`，等 `ISLINK=1`。UART 数据口上直接写字节即可，模组按 `UARTQUE` 分包后异步送进 Socket；对端回包从 `DTUPSDN` 指定的口吐出。对着演示口：数据口发 `doiot` 会收回 `测试成功`，发其它内容则原样回来。透传底层走的就是异步发送队列。

### 3.3 指令主动发送（单通道）

通道已经起来之后，在 **AT 口**发（不必经过透传 UART）：

```lua
AT+SOCKSYNC=1,1,doiot
+SOCKSYNC: 1,1,5

OK
```

`+SOCKSYNC` 的 `5` 只是发出去的长度。对端回 `测试成功`，从 `DTUPSDN` 指定的口出来（上面配了 UART1）。发其它内容则原样回显，例如发 `hello` 会在串口收到 `hello`：

```lua
AT+SOCKSYNC=1,1,hello
+SOCKSYNC: 1,1,5

OK

AT+SOCKASYNC=1,1,doiot
+SOCKASYNC: 1,1,5

OK
```

按路由写（SOCK 路忽略 MQTT 槽号，整包仍只发到这一路 Socket）：

```lua
AT+RTUWRITE="1",doiot
OK
```

成功不回 `OK` 的静默写法（方便嵌进透传流）用 `AT+RTUWRITEQ`，见 [第 7 节](#7-指令主动发送)。

### 3.4 单通道联调顺序（可抄）

```lua
AT+ISLINK
AT+SOCK=1,"socket.doiot.cn",5000,0
AT+DTUTASK=1,1,"SOCK"
AT+DTUPSUP=1,"1"
AT+DTUPSDN=1,"6[1]"
AT+RESET
```

复位、驻网后：

```lua
AT+ISLINK
AT+DTUSTATE=1
AT+SOCKSYNC=1,1,doiot
```

---

## 4. 多通道

目标：通道 1、通道 2 各建一条 TCP，可并行。演示口允许两路同时连 `socket.doiot.cn:5000`（两条独立连接，各自回显）。每路独立的 `AT+SOCK`、`AT+DTUTASK`、下行路由。

```lua
AT+SOCK=1,"socket.doiot.cn",5000,0
+SOCK: 1,"socket.doiot.cn",5000,0

OK

AT+SOCK=2,"socket.doiot.cn",5000,0
+SOCK: 2,"socket.doiot.cn",5000,0

OK

AT+DTUTASK=1,1,"SOCK"
+DTUTASK: 1,1,"SOCK"

OK

AT+DTUTASK=2,1,"SOCK"
+DTUTASK: 2,1,"SOCK"

OK
```

UART1 同时上行到两路（同一份数据各发一份）：

```lua
AT+DTUPSUP=1,"1|2"
+DTUPSUP: 1,"1|2"

OK
```

两路下行都回到 UART1：

```lua
AT+DTUPSDN=1,"6[1]"
+DTUPSDN: 1,"6[1]"

OK

AT+DTUPSDN=2,"6[1]"
+DTUPSDN: 2,"6[1]"

OK
```

或拆开：通道 1 → UART1，通道 2 → UART2：

```lua
AT+DTUPSDN=1,"6[1]"
AT+DTUPSDN=2,"6[2]"
AT+DTUPSUP=1,"1"
AT+DTUPSUP=2,"2"
```

AT 口分别主动发：

```lua
AT+SOCKSYNC=1,1,doiot
+SOCKSYNC: 1,1,5

OK

AT+SOCKASYNC=2,1,doiot
+SOCKASYNC: 2,1,5

OK
```

两路都会各自收到 `测试成功`（走各自的 `DTUPSDN`）。

一路 TCP、一路 UDP（UDP 对着演示口没有回显，只示范写法）：

```lua
AT+SOCK=3,"socket.doiot.cn",5000,1
AT+DTUTASK=3,1,"SOCK"
```

UDP 只能用 `SOCKSYNC` / 透传，不能 `SOCKASYNC`（会 `"error enqueue"`），见 [第 8 节](#8-同步与异步)。

四路上限就是 1～4。不需要的路保持 `AT+DTUTASK=<id>,0,"SOCK"`（`enable=0` 时 taskid 不必合法）。

---

## 5. 混合通道

目标：通道 1 跑 Socket，通道 2 跑 MQTT。编号不能冲突——**同一 `<id>` 不能既是 SOCK 又是 MQTT**。

MQTT 侧逐步说明见 [MQTT 连接专栏](mqtt.md)。这里给出一份可一起烧进去的最小混合配置。

```lua
AT+SOCK=1,"socket.doiot.cn",5000,0
+SOCK: 1,"socket.doiot.cn",5000,0

OK

AT+DTUTASK=1,1,"SOCK"
+DTUTASK: 1,1,"SOCK"

OK

AT+MQTT=2,"mqtts.doiot.cn",1883
+MQTT: 2,"mqtts.doiot.cn",1883

OK

AT+MQTTPLATFORM=2,"normal"
+MQTTPLATFORM: 2,"normal"

OK

AT+MQTTAUTH=2,"my-client","","",""
+MQTTAUTH: 2,"my-client","","",""

OK

AT+MQTTSUB=2,1,"/server/demo",0
+MQTTSUB: 2,1,"/server/demo",0

OK

AT+MQTTPUB=2,1,"/device/demo",0,0
+MQTTPUB: 2,1,"/device/demo",0,0

OK

AT+DTUTASK=2,1,"MQTT"
+DTUTASK: 2,1,"MQTT"

OK
```

UART1 上行：Socket 整包进通道 1；MQTT 走到通道 2 的**发布槽 1**（路由串 `2` 默认子通道 1）：

```lua
AT+DTUPSUP=1,"1|2"
+DTUPSUP: 1,"1|2"

OK

AT+DTUPSDN=1,"6[1]"
+DTUPSDN: 1,"6[1]"

OK

AT+DTUPSDN=2,"6[1]"
+DTUPSDN: 2,"6[1]"

OK
```

若 MQTT 要同时发到发布槽 1 和 2：

```lua
AT+DTUPSUP=1,"1|2[1:2]"
```

复位后分别主动发：

```lua
AT+SOCKSYNC=1,1,doiot
+SOCKSYNC: 1,1,5

OK

AT+MQTTSYNC=2,"/device/demo",0,0,1,hello-mqtt
+MQTTSYNC: 2,"/device/demo",0,0,1,10

OK
```

Socket 异步队列和 MQTT 异步队列相互独立，一路堵了不会占另一路的队列额度。

---

## 6. 透传配置

透传 = 任务已使能 + 上下行路由指向你真正接线的口。路由串语法、子通道上限见 [route.md](../manual/route.md)，不要把 `AT+SOCK=1` 的 `1` 和路由里的 `6[1]` 当成同一种编号。

### 6.1 常用组合

| 需求 | 上行 | 下行 |
| --- | --- | --- |
| UART1 ↔ 通道 1 | `AT+DTUPSUP=1,"1"` | `AT+DTUPSDN=1,"6[1]"` |
| UART2 ↔ 通道 1（AT 仍在 UART1） | `AT+DTUPSUP=2,"1"` | `AT+DTUPSDN=1,"6[2]"` |
| UART1 同时上到通道 1、2 | `AT+DTUPSUP=1,"1\|2"` | 每路各自 `DTUPSDN` |
| 通道 1 下行到 UART1 和 UART2 | 不变 | `AT+DTUPSDN=1,"6[1:2]"` |
| 关掉某路 UART 上行 | `AT+DTUPSUP=1,""` | — |

查询：

```lua
AT+DTUPSUP=1?
+DTUPSUP: 1,"1"

OK

AT+DTUPSDN=1?
+DTUPSDN: 1,"6[1]"

OK
```

### 6.2 和 AT 口的关系

- 正在当 AT 口的那一路，默认仍解析 `AT+…`。业务 MCU 不要和 AT 工具抢同一条 UART。
- 配完参数、复位跑起来之后，若要把 **当前 AT 口**改成纯透传：`AT+RTUPSD=1,"<密码>"`，之后该口字节按上行路由走网络；需要再下指令时 `AT+RTULOCK="<密码>"`。细则见 [rtu.md](../manual/rtu.md)。
- 调试阶段可 `AT+DTUMSGHEAD=1`，透传数据带上来源标识；量产再关上，少几个头字节。

### 6.3 分包

串口侧按 [AT+UARTQUE](../manual/uart.md) 的包数 / 长度 / 等待时间切包，再交给上行路由。包太大时对照 `AT+SOCKCFG` 的收发缓冲（默认常见 2048～4096），需要再加大再改，不要盲目拉到上限。

---

## 7. 指令主动发送

三种入口，载荷都是最后一个逗号后的裸数据（`RTUWRITE` 也是）。

| 指令 | 目标怎么写 | 成功时 | 适合 |
| --- | --- | --- | --- |
| `AT+SOCKSYNC=<id>,<rsp>,<payload>` | 通道号 | `rsp=1` 回实际交给发送接口的长度 | 要确认发出去 |
| `AT+SOCKASYNC=<id>,<rsp>,<payload>` | 通道号 | `rsp=1` 只表示入队 | 高频、不堵 AT 口 |
| `AT+RTUWRITE="<路由>",<payload>` | 路由串 | 回 `OK` | 一包打到多路 / 指定 UART |
| `AT+RTUWRITEQ="<路由>",<payload>` | 路由串 | **成功完全静默** | 嵌在透传流里 |

`rsp=0` 时 `SOCKSYNC` / `SOCKASYNC` 成功失败都不回 `+CMD` / `OK` / `ERROR`，主机只能靠超时或其它通道判断。

```lua
AT+SOCKSYNC=1,0,doiot

AT+SOCKASYNC=1,0,hello

AT+RTUWRITE="1|2",doiot
OK

AT+RTUWRITEQ="1",hello
```

通道未配成 SOCK、未连接、UDP 走异步，会在 `rsp=1` 时看到：

```lua
AT+SOCKSYNC=1,1,doiot
+SOCKSYNC: "error send"

ERROR

AT+SOCKASYNC=1,1,doiot
+SOCKASYNC: "error enqueue"

ERROR
```

主动发送**不会**把对端回包夹在 `+SOCKSYNC` 里返回。连 `socket.doiot.cn:5000` 时：发 `doiot` 下行是 `测试成功`，发其它内容则原样回显。都走 `DTUPSDN` / Lua 回调。

主题、载荷里的 `<#IMEI>` 一类占位符按 `[maping]` 展开；Socket 映射失败时同步/异步发送改发原文，不因此报错。细则见指令手册。

---

## 8. 同步与异步

| | `SOCKSYNC` | `SOCKASYNC` | 串口透传 |
| --- | --- | --- | --- |
| 等待 | 等到发送调用返回 | 入队成功即返回 | 入队（与异步同一套队列） |
| TCP | 可以 | 可以（须已连接） | 可以 |
| UDP | 可以 | **不可以** | 可以（不走这条异步入队） |
| `rsp=1` 的含义 | 真实交给发送接口的结果 | 是否进队列 | 无此参数 |
| AT 口占用 | 大包或对端堵塞时会停一阵 | 短 | 不经过 AT 解析（数据口） |
| 队列 | 无 | 每路独立，溢出丢弃 | 同左 |

公开演示口径：Socket 异步队列大约 **32 KB** / 路，与 MQTT 异步队列分开。队列满 → `"error enqueue"`。

选法：

- 要知道这包有没有交给协议栈：`SOCKSYNC` 且 `rsp=1`。
- 连续上报、不能堵 AT：`SOCKASYNC` 且 `rsp=1`（只确认入队）或 `rsp=0`。
- 串口 MCU 一直推流：透传，不要每包套一层 `AT+SOCK*`。
- UDP：同步或透传，不要异步。

---

## 9. 保活、心跳、注册包

三重手段不要一次全改到极限。

**协议层 TCP keepalive**（只改时间不够，还要打开开关）：

```lua
AT+SOCKKEEP=1,60,10,3
+SOCKKEEP: 1,60,10,3

OK

AT+SOCKCFG=1,"tcp_keepalive_enable",1
+SOCKCFG: 1,"tcp_keepalive_enable",1

OK
```

不清楚含义不要改 `tcp_poll_interval`、缓冲、重连间隔。单项见 [AT+SOCKCFG](../manual/sock.md#5-atsockcfg)。

**应用层心跳 / 注册包**（SOCK 模式下最后一段通道列表**无效**，填空串）：

```lua
AT+DTUHEART=1,1,10,"4845415254",""
+DTUHEART: 1,1,10,"4845415254",""

OK

AT+DTUREG=1,1,"3C23494D45493E",""
+DTUREG: 1,1,"3C23494D45493E",""

OK
```

`4845415254` 是 ASCII `HEART` 的十六进制文本；`3C23494D45493E` 是 `<#IMEI>`。注册包在连接建立后发一次，心跳按间隔重复。

---

## 10. 常见失败

| 现象 | 先查 |
| --- | --- |
| `"error send"` / `"error enqueue"` | `DTUTASK` 是否 SOCK、是否已复位生效、`ISLINK`、TCP 是否已连上；UDP 误走了 `SOCKASYNC` |
| 改了主机仍连旧地址 | 写配置不拆旧连接，需要复位或 `RTUCTL` 停再启 |
| 串口有数据但服务器没有 | `DTUPSUP` 是否指向该通道；是否把数据打到了 AT 口 |
| 发了 `doiot` 看不到 `测试成功` | `DTUPSDN` 是否指向你看的那路 UART；回包不在 `+SOCKSYNC` 里 |
| 服务器有回包但 MCU 没有 | `DTUPSDN` 是否指向实际接线的 UART |
| AT 口突然不再认指令 | 是否开了 `RTUPSD`，用 `RTULOCK` 解锁 |
| 通道号搞混 | `AT+SOCK=1` 的 1 是业务通道；`6[1]` 才是 UART1 |

错误短 reason 全表见 [sock.md 第 9 节](../manual/sock.md#9-错误一览) 与 [rtu.md](../manual/rtu.md)。

---

## 11. 对照手册

| 要查 | 去 |
| --- | --- |
| `SOCK` / `SOCKCFG` / `SOCKKEEP` / `SOCKSYNC` / `SOCKASYNC` | [sock.md](../manual/sock.md) |
| `DTUTASK` / `DTUPSUP` / `DTUPSDN` / `RTUWRITE` / `RTUPSD` | [rtu.md](../manual/rtu.md) |
| `1\|6[1]` 怎么写 | [route.md](../manual/route.md) |
| 行格式、失败风格、通道编号 | [convention.md](../manual/convention.md) |
| 同一路改成 MQTT | [MQTT 连接专栏](mqtt.md) |
| `[sock.N]` 全部 key | [rtu_config.cfg](../../api/rtu_config/rtu_config.md#9-sockn--socketn) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-19 | 首版：单通道 / 多通道 / 混合通道、透传、指令主动发送、同步与异步 |
| 1.0.1 | 2026-09-19 | 对端统一为 `socket.doiot.cn:5000`；写明发啥回啥，发 `doiot` 回 `测试成功` |
