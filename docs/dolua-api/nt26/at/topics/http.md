# HTTP / HTTPS 专栏

**文档版本** `1.0.0`

场景专题：用应用 AT 发 **明文 HTTP** 或 **HTTPS** 请求。指令逐条的测试/查询/设置、参数表、错误码见 [HTTP 指令手册](../manual/http.md)、[SSL](../manual/ssl.md)、[路由串](../manual/route.md)。本篇不重复那些表格。

这不是 Lua `require("http")`。通道号与 `[http.N]` **同一套 1～5**，和 Socket / MQTT 的 1～4 **不是一路**，也和证书组 1～3 不是一路。

---

## 目录

- [1. 先建立图景](#1-先建立图景)
- [2. 联调前：驻网](#2-联调前驻网)
- [3. 最快路径：自由请求](#3-最快路径自由请求)
- [4. 单通道](#4-单通道)
- [5. HTTPS](#5-https)
- [6. 多通道](#6-多通道)
- [7. 混合通道](#7-混合通道)
- [8. 响应往哪走](#8-响应往哪走)
- [9. 指令主动发送](#9-指令主动发送)
- [10. 同步与异步](#10-同步与异步)
- [11. 请求体 write / stream](#11-请求体-write--stream)
- [12. 常见失败](#12-常见失败)
- [13. 对照手册](#13-对照手册)
- [修订记录](#修订记录)

---

## 1. 先建立图景

HTTP **不是** `AT+DTUTASK` 那种常驻任务。需要时才建连接、做完就拆，省常驻资源。代价是：**同一时刻只跑一个 HTTP 请求**，后发的会堵住等前一个结束。Socket / MQTT 四路可以一直挂着，和 HTTP 互不顶通道号。

```lua
AT 口 ──AT+HTTPFREE──────────────► 本次临时 URL（不占通道、不写盘）
AT 口 ──AT+HTTPURL / HTTPCFG ──► 通道 1～5 配置
       ──AT+HTTPREQ────────────► 用该通道立刻请求
UART / RTUWRITE ──路由 5[N]──► 同一套通道（载荷当请求体）
响应 ──该通道 route（默认 UART1）──► 串口 / SOCK / MQTT / …
HTTPS ──ssl_type + ssl_id 1～3──► [ssl.K] 证书组
```

| 角色 | 谁来配 | 说明 |
| --- | --- | --- |
| 试一次、不想占通道 | `AT+HTTPFREE` | 当场给方法/URL/头/体，**不读不写**通道 |
| 反复打同一个 API | `AT+HTTPURL` + `AT+HTTPREQ` | URL/方法/头落盘；下次 `HTTPREQ` 才用新值 |
| HTTPS 校不校验、用哪组证 | `AT+HTTPCFG` 的 `ssl_type` / `ssl_id` | 证书内容用 [AT+SSL](../manual/ssl.md) |
| 响应打到哪 | `AT+HTTPCFG` 的 `route` | 默认 `6[1]`（UART1），语法见 [route.md](../manual/route.md) |
| 串口数据触发 HTTP | `AT+DTUPSUP` 里带 `5[N]` | N 是 HTTP 通道 1～5，不是 SOCK 通道 |

**三套编号不要混：**

| 编号 | 范围 | 例子 |
| --- | --- | --- |
| HTTP 通道 | 1～5 | `AT+HTTPURL=1` / `AT+HTTPREQ=1` |
| SOCK / MQTT / 任务 | 1～4 | `AT+SOCK=1`、`AT+DTUTASK=1` |
| SSL 证书组 | 1～3 | `AT+SSL=1`、`HTTPCFG "ssl_id"` |
| 路由串里的 `5[1]` | HTTP 通道 1 | 不是任务 5，也没有任务 5 |

下文 URL 请换成自己的服务器。载荷是 **TAILRAW**：最后一个逗号之后到行结束之前的原始字节。

---

## 2. 联调前：驻网

```lua
AT
OK

AT+ISLINK
+ISLINK: 1

OK
```

`+ISLINK: 1` 再发请求。HTTP **一般不必**为改 URL 去 `AT+RESET`：`HTTPURL` / `HTTPCFG` 只落盘，**下一次** `HTTPREQ` 就读新值；正在飞的那次不会被改配置打断。

---

## 3. 最快路径：自由请求

不想先配通道时，一条 `HTTPFREE` 就能打。响应默认出 UART1（`6[1]`），总是带头和体，没有 `resp_*` / `resp_at_mode`。

明文 GET：

```lua
AT+HTTPFREE="sync",1,"http://10.0.0.8/api/status"
HTTP/1.1 200 OK
Content-Type: application/json
…

+HTTPFREE: 200,0,"ok"

OK
```

HTTPS GET（URL 是 `https://` 才走 TLS；自由请求未指定证书组时按**不校验**处理）：

```lua
AT+HTTPFREE="sync",1,"https://api.example.com/v1/ping"
+HTTPFREE: 200,0,"ok"

OK
```

POST 只带体时，path / header 用空串占位：

```lua
AT+HTTPFREE="sync",2,"http://10.0.0.8/api/echo","","",hello
+HTTPFREE: 200,0,"ok"

OK
```

方法：`1` GET，`2` POST，`3` PUT，`4` DELETE，`5` HEAD。自由请求没有 `0` NONE。

要指定证书组、超时、响应打到哪，不要用 `HTTPFREE`，改走下面的通道。

---

## 4. 单通道

目标：通道 1 固定打一个 HTTP API；响应回到 UART1；AT 口随时 `HTTPREQ`。

### 4.1 配 URL 并发 GET

```lua
AT+HTTPURL=1,1,1,"","http://10.0.0.8/api/status"
+HTTPURL: 1,1,1,"","http://10.0.0.8/api/status"

OK

AT+HTTPREQ=1,"sync"
HTTP/1.1 200 OK
…

+HTTPREQ: 1,200,0,"ok"

OK
```

`enable=1` 必须写。`enable=0` 时参数仍算合法，结果行是 `status=-1`、码 `1002`、文案 `"channel_disabled"`，**后面仍可能是 `OK`**，和 Socket 发送失败回 `ERROR` 不同。

额外头（多行用占位符 `<#ENTER>`，不要自己嵌真实 CRLF 进这一条 AT）：

```lua
AT+HTTPURL=1,1,1,"Accept: application/json<#ENTER>Authorization: Bearer token","http://10.0.0.8/api/status"
```

`Content-Length` 不用自己填，模组会按体长度补。

### 4.2 拼一段 path

通道 URL 是前缀，本次再接 path：

```lua
AT+HTTPURL=1,1,1,"","http://10.0.0.8/api"
AT+HTTPREQ=1,"sync","/device/<#IMEI>"
```

实际请求打到 `http://10.0.0.8/api` 再加上 `/device/…`（占位符按 `[maping]` 展开）。不接 path 就 `AT+HTTPREQ=1,"sync"`，或第三参写 `""`。

### 4.3 超时与回包策略

```lua
AT+HTTPCFG=1,"timeout",10
+HTTPCFG: 1,"timeout",10

OK

AT+HTTPCFG=1,"route","6[1]"
AT+HTTPCFG=1,"resp_status_line",1
AT+HTTPCFG=1,"resp_header",1
AT+HTTPCFG=1,"resp_content",1
AT+HTTPCFG=1,"resp_at_mode",0
```

| `resp_at_mode` | AT 口上的 `+HTTPREQ` 结果行 |
| --- | --- |
| `0`（默认） | 成功失败都打 |
| `1` | 只失败打；成功只 `OK` |
| `2` | 都不打，只 `OK` |

状态行 / 头 / 体是否出现在 **route 指向的口**，由三个 `resp_*` 开关决定，和 `resp_at_mode` 不是同一件事。

### 4.4 单通道联调顺序（可抄）

```lua
AT+ISLINK
AT+HTTPURL=1,1,1,"","http://10.0.0.8/api/status"
AT+HTTPCFG=1,"timeout",10
AT+HTTPREQ=1,"sync"
```

---

## 5. HTTPS

HTTPS = URL 用 `https://` + 通道上的 `ssl_type` / `ssl_id`。证书组是 **1～3**，用 [AT+SSL](../manual/ssl.md) 写入，**不是** HTTP 通道号。

| `ssl_type` | 含义 | 证书组里要有 |
| --- | --- | --- |
| `1` | 不校验（出厂默认） | 可以没有 CA |
| `2` | 校验服务端 | `ca_cert` |
| `3` | 双向 | `ca_cert` + `client_cert` + `client_key` |

本篇 AT **不能**把 `ssl_type` / `ssl_id` 写成 0。明文 `http://` 也可以保持 `ssl_type=1`。

### 5.1 不校验（先打通）

```lua
AT+HTTPURL=1,1,1,"","https://api.example.com/v1/ping"
+HTTPURL: 1,1,1,"","https://api.example.com/v1/ping"

OK

AT+HTTPCFG=1,"ssl_id",1
AT+HTTPCFG=1,"ssl_type",1
AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,200,0,"ok"

OK
```

### 5.2 校验服务端（CA）

先把 CA 写入证书组 1（多行 PEM 用 `stream`，看到 `>` 再贴原文）：

```lua
AT+SSL=1,"stream","ca_cert"
>
+SSL: 1,"stream","ca_cert",<len>

OK

AT+HTTPCFG=1,"ssl_id",1
AT+HTTPCFG=1,"ssl_type",2
AT+HTTPURL=1,1,1,"","https://api.example.com/v1/ping"
AT+HTTPREQ=1,"sync"
```

双向再写入 `client_cert` / `client_key`，并把 `ssl_type` 设为 `3`。

改证书或 `ssl_type` **不会**拆掉已经在飞的请求；下次 `HTTPREQ` 才用新材料。TLS 对不上时，结果行常见 `1201` / `1301` / `2012` / `3013`，后面仍是 `OK`。

自由请求要指定证书组：当前没有参数可写 `ssl_id`，请改用通道 `HTTPREQ`。

---

## 6. 多通道

五路配置可以同时在盘上，但**执行仍是单实例**：`HTTPREQ=1` 没结束时再发 `HTTPREQ=2`，后一条会等。这不是五路 HTTP 并行长连接。

```lua
AT+HTTPURL=1,1,1,"","http://10.0.0.8/api/a"
AT+HTTPURL=2,1,2,"Content-Type: text/plain","http://10.0.0.8/api/b"
AT+HTTPCFG=1,"route","6[1]"
AT+HTTPCFG=2,"route","6[2]"
```

分别打：

```lua
AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,200,0,"ok"

OK

AT+HTTPREQ=2,"sync","","write",hello
+HTTPREQ: 2,200,0,"ok"

OK
```

一路 HTTP、一路 HTTPS：

```lua
AT+HTTPURL=3,1,1,"","https://api.example.com/v1/ping"
AT+HTTPCFG=3,"ssl_type",1
AT+HTTPREQ=3,"sync"
```

不需要的路 `AT+HTTPURL=<id>,0,1,"",""` 关掉 `enable`。第 5 路用 `AT+HTTPREQ=5,…` 即可；路由串写出 HTTP 时，当前只会真正发出 **1～4** 路（`5[5]` 能存但不发），见 [route.md](../manual/route.md#42-通道-5http)。

---

## 7. 混合通道

HTTP 不占 `DTUTASK` 的 SOCK/MQTT 名额。常见混法：任务 1 跑 Socket 或 MQTT，HTTP 通道另外打 REST。

```lua
AT+SOCK=1,"socket.doiot.cn",5000,0
AT+DTUTASK=1,1,"SOCK"

AT+HTTPURL=1,1,1,"","http://10.0.0.8/api/status"
```

这里两个 `1` **不是一路**：`SOCK=1` 是业务通道 1，`HTTPURL=1` 是 HTTP 通道 1。

UART1 上行：一份数据既进 Socket，又当 HTTP 通道 1 的请求体（该通道须已是 POST/PUT，且 `enable=1`）：

```lua
AT+HTTPURL=1,1,2,"","http://10.0.0.8/api/echo"
AT+DTUPSUP=1,"1|5[1]"
```

HTTP 响应回到 UART1，Socket 下行仍走 `DTUPSDN`：

```lua
AT+HTTPCFG=1,"route","6[1]"
AT+DTUPSDN=1,"6[1]"
```

HTTP 响应转发到 MQTT 通道 2 的发布槽 1（任务 2 须已是 MQTT 且槽有主题）：

```lua
AT+HTTPCFG=1,"route","2"
```

AT 口分别主动发：

```lua
AT+SOCKSYNC=1,1,hello-tcp
+SOCKSYNC: 1,1,9

OK

AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,200,0,"ok"

OK
```

MQTT + HTTP 同理：`DTUTASK=2,1,"MQTT"` 与 `HTTPURL=1` 并存，路由里 `2` 是 MQTT，`5[1]` 才是 HTTP。

---

## 8. 响应往哪走

HTTP 没有 `DTUPSDN`。通道响应出口是 `HTTPCFG` 的 `route`；自由请求固定 UART1。

| 需求 | 配置 |
| --- | --- |
| 响应出 UART1（默认） | `AT+HTTPCFG=1,"route","6[1]"`（查询常回 `"6"`，同义） |
| 响应出 UART2（AT 仍在 UART1） | `AT+HTTPCFG=1,"route","6[2]"` |
| 响应进 SOCK 通道 1 | `AT+HTTPCFG=1,"route","1"` |
| 响应进 MQTT 通道 1 发布槽 1 和 2 | `AT+HTTPCFG=1,"route","1[1:2]"` |
| 只要 AT 结果行、不要把体打到串口 | `resp_content=0`，或 `route` 留空 |

只关体、仍看状态行：

```lua
AT+HTTPCFG=1,"resp_status_line",1
AT+HTTPCFG=1,"resp_header",0
AT+HTTPCFG=1,"resp_content",0
```

串口透传 MCU 数据去触发 HTTP，用 `DTUPSUP` 的 `5[N]`，不是改 `HTTPCFG route`。`route` 只管**响应**出口。

---

## 9. 指令主动发送

| 指令 | 目标 | 成功时 | 适合 |
| --- | --- | --- | --- |
| `AT+HTTPFREE="sync\|async",<method>,"<url>"…` | 本次 URL | 结果行无通道号，失败也常是 `OK` | 试一次、脚本里临时打 |
| `AT+HTTPREQ=<id>,"sync\|async"…` | 已配通道 | `+HTTPREQ: id,status,code,"msg"` | 反复打同一 API、要 TLS 组 |
| `AT+RTUWRITE="5[N]",<payload>` | HTTP 通道 N | `OK` | 把体打进已配好的 POST/PUT 通道 |
| `AT+RTUWRITEQ="5[N]",<payload>` | 同上 | **成功完全静默** | 嵌在透传流里 |

```lua
AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,200,0,"ok"

OK

AT+RTUWRITE="5[1]",hello
OK
```

`error_code=0` 只表示请求流程走完，HTTP 状态仍可能是 404/500。真正的协议失败看 `<status>` 和 `"error_msg"`。参数写错才会 `ERROR`。

---

## 10. 同步与异步

这里的 sync/async **不是** Socket 那套「等发送返回 / 入队」。HTTP 是**响应怎么吐出来**：

| | `"sync"` | `"async"` |
| --- | --- | --- |
| 响应 | 收完整段，再按 `resp_*` 一次写出 | 边收边分段写出（头、随后 chunk） |
| AT 口占用 | 等到收完或超时 | 启动后分段直出，最后仍给结果行（受 `resp_at_mode` 管） |
| 同步体上限 | 响应约 **64 KiB**，超了码 `2008` | 按段输出，不受这一条 64 KiB 收齐上限约束 |
| 结果行 | `+HTTPREQ: id,status,code,"msg"` | 同形，出现在结束/失败之后 |
| 单实例 | 这一发占着 HTTP 引擎 | 同样占着，别指望两路并行 |

```lua
AT+HTTPREQ=1,"async"
HTTP/1.1 200 OK
…
+HTTPREQ: 1,200,0,"ok"

OK
```

选法：

- 要完整 JSON 再给 MCU：`sync`，注意 64 KiB。
- 大文件 / 想边下边出串口：`async`。
- 连续很多个小请求：仍然排队，一个接一个 `HTTPREQ`，或穿插 `HTTPFREE`。

Socket 的 `SOCKASYNC` 队列、MQTT 的发布队列和 HTTP **不是**同一套。

---

## 11. 请求体 write / stream

只有通道方法是 **POST（2）或 PUT（3）** 才能带体，否则 `"error method"`。GET 不要跟 `write`。

`write`：最后一个逗号后直接跟原始字节。

```lua
AT+HTTPURL=1,1,2,"Content-Type: text/plain","http://10.0.0.8/api/echo"
AT+HTTPREQ=1,"sync","","write",hello
+HTTPREQ: 1,200,0,"ok"

OK
```

第三参若正好是 `write` / `stream`，会当成 action（path 省略）：

```lua
AT+HTTPREQ=1,"sync","write",hello
```

`stream`：先看到 `>`，10 秒内再贴体（不要在同一条命令后面再跟 TAILRAW）：

```lua
AT+HTTPREQ=1,"sync","","stream"
>
hello
+HTTPREQ: 1,200,0,"ok"

OK
```

体里的 `<#IMEI>` 一类按 HTTP 映射规则展开；展开失败 → `"error maping"`（这条是参数阶段，会 `ERROR`）。

---

## 12. 常见失败

| 现象 | 先查 |
| --- | --- |
| `+HTTPREQ: 1,-1,1002,"channel_disabled"` 却是 `OK` | `HTTPURL` 的 `enable` 不是 1 |
| `"error method"` | GET/HEAD 带了 `write`/`stream`，或通道方法不是 2/3 |
| `2012` / `3013` / `1201` / `1301` | HTTPS：`ssl_type`、证书组、CA 是否写进对应 `ssl_id` |
| `2011` / `3012` | DNS；先 `ISLINK`、URL 主机是否写对 |
| `2013` / `3014` | `timeout` 太短或对端不回 |
| `2008` | `sync` 响应超过约 64 KiB，改 `async` 或缩小资源 |
| 改了 URL 仍打旧地址 | 看是不是还在飞旧请求；下次 `HTTPREQ` 才用新配置 |
| 响应在 AT 口看不到体 | `route` 指到了别的 UART；或 `resp_content=0`；或 `resp_at_mode=2` 只藏了结果行 |
| 把 `AT+HTTPURL=1` 当成 `AT+SOCK=1` | 两套 1～4 / 1～5；路由要用 `5[1]` 才进 HTTP |
| `HTTPFREE` HTTPS 校验失败 | 自由请求默认不校验；要 CA 请走通道 + `ssl_type=2` |
| 第二条 `HTTPREQ` 很久才动 | 单实例，在等前一条结束 |

参数错误全表见 [http.md 第 8 节](../manual/http.md#8-错误一览)；请求阶段数字码见 [第 6.4 节](../manual/http.md#64-请求错误码结果行不是-error-reason)。

---

## 13. 对照手册

| 要查 | 去 |
| --- | --- |
| `HTTPURL` / `HTTPCFG` / `HTTPREQ` / `HTTPFREE` | [http.md](../manual/http.md) |
| 证书组读写 | [ssl.md](../manual/ssl.md) |
| `5[1]` / `6[1]` / `1[1:2]` | [route.md](../manual/route.md) |
| 行格式、三套编号 | [convention.md](../manual/convention.md#4-通道编号) |
| 串口上行带上 HTTP | [rtu.md](../manual/rtu.md) 的 `DTUPSUP` |
| 常驻 TCP/MQTT | [Socket 专栏](socket.md)、[MQTT 连接专栏](mqtt.md) |
| `[http.N]` 全部 key | [rtu_config.cfg](../../api/rtu_config/rtu_config.md#12-httpn) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-19 | 首版：自由请求与通道、HTTPS、单/多/混合、响应路由、主动发送、同步异步、write/stream |
