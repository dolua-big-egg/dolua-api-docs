# HTTP / HTTPS 专栏

**文档版本** `1.2.1`

**固件版本** `1.4.3` 起支持 `HTTPFREE="chunk"` 连续上传，详见 [11.1](#11-1-chunk-upload)。自由请求从 UART 或 USB AT 发起时，响应回到同一发起端口。

**当前 SDK 新增** HTTP 连接保持与自由会话，连续请求流程见 [第 14 节](#14-长连接与复用)。

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
  - [11.1 连续 chunked 上传（固件 1.4.3）](#11-1-chunk-upload)
- [12. 常见失败](#12-常见失败)
- [13. 对照手册](#13-对照手册)
- [14. 长连接与复用](#14-长连接与复用)
- [修订记录](#修订记录)

---

## 1. 先建立图景

HTTP 按请求执行。旧接口默认需要时建连、做完关闭；开启通道 `keep_alive` 或创建 `HTTPSESS` 后，可以保留 TCP/TLS 连接供后续请求复用。应用 AT 入口仍串行执行，后发的命令等待前一个事务结束。Socket / MQTT 与 HTTP 分开管理通道号。

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
| 反复打同一个 API | `AT+HTTPURL` + `AT+HTTPREQ` | URL/方法/头落盘；开启 `keep_alive` 可复用连接 |
| 不写通道配置，连续请求同一服务 | `AT+HTTPSESS` | open 后多次 req，完成后 close |
| HTTPS 校不校验、用哪组证 | `AT+HTTPCFG` 的 `ssl_type` / `ssl_id` | 证书内容用 [AT+SSL](../manual/ssl.md) |
| 响应打到哪 | `AT+HTTPCFG` 的 `route` | 默认 `6[1]`（UART1），语法见 [route.md](../manual/route.md) |
| 串口数据触发 HTTP | `AT+DTUPSUP` 里带 `5[N]` | N 是 HTTP 通道 1～5，不是 SOCK 通道 |

**编号不要混：**

| 编号 | 范围 | 例子 |
| --- | --- | --- |
| HTTP 通道 | 1～5 | `AT+HTTPURL=1` / `AT+HTTPREQ=1` |
| HTTP 自由会话 | 1～5 | `AT+HTTPSESS=1`，与配置通道分开管理 |
| SOCK / MQTT / 任务 | 1～4 | `AT+SOCK=1`、`AT+DTUTASK=1` |
| SSL 证书组 | 1～3 | `AT+SSL=1`、`HTTPCFG "ssl_id"` |
| 路由串里的 `5[1]` | HTTP 通道 1 | 不是任务 5，也没有任务 5 |

下文 URL 请换成自己的服务器。`write` 或普通 FREE 的行内载荷是 **TAILRAW**：最后一个逗号之后到行结束之前的原始字节。`HTTPFREE="chunk"` 则在 `>` 提示后持续读取输入流。

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

不想先配通道时，一条 `HTTPFREE` 就能打。固件 **1.4.3** 从 UART 或 USB AT 发起时，响应回到同一个端口，带状态行、头和体，没有 `resp_*` / `resp_at_mode`。普通请求从其他入口调用时，响应数据回落到 UART1。

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

五路配置可以同时在盘上，开启连接保持后也可以各自保留连接。AT 入口的执行仍然串行：`HTTPREQ=1` 没结束时再发 `HTTPREQ=2`，后一条会等；保留多条连接不等于并行执行请求。

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

HTTP 没有 `DTUPSDN`。通道响应出口是 `HTTPCFG` 的 `route`。固件 **1.4.3** 的自由请求响应跟随发起的 UART / USB AT 口；`chunk` 上传也使用该端口接收数据。普通 FREE 从其他入口调用时，响应数据回落到 UART1。

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
| `AT+HTTPFREE="chunk",2,"<url>","","",<total>` | 本次 URL | 五字段结果行和 `OK`；失败 `ERROR` | 固件 1.4.3，看到 `>` 后持续上传二进制 |
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

普通 `HTTPREQ` 和 FREE `sync` / `async` 的 `error_code=0` 只表示请求流程走完，HTTP 状态仍可能是 404/500，需要同时检查 `<status>`。FREE `chunk` 以完整 2xx 响应为成功条件，HTTP 拒绝或网络失败会返回负数错误码和 `ERROR`。

---

## 10. 同步与异步

这里的 sync/async **不是** Socket 那套「等发送返回 / 入队」。HTTP 是**响应怎么吐出来**：

| | `"sync"` | `"async"` |
| --- | --- | --- |
| 响应 | 收完整段，再按 `resp_*` 一次写出 | 边收边分段写出（头、随后 chunk） |
| AT 口占用 | 等到收完或超时 | 接收期间分段直出，仍等到结束或超时（结果受 `resp_at_mode` 管） |
| 同步体上限 | 响应约 **64 KiB**，超了码 `2008` | 按段输出，不受这一条 64 KiB 收齐上限约束 |
| 结果行 | `+HTTPREQ: id,status,code,"msg"` | 同形，出现在结束/失败之后 |
| AT 执行 | 当前事务完成后再执行下一条命令 | 同样串行；连接保持不改变此规则 |

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
- 连续很多个小请求：开启 `keep_alive` 后逐次 `HTTPREQ`，或用 `HTTPSESS`。事务仍排队，完整响应后再发下一条请求。

Socket 的 `SOCKASYNC` 队列、MQTT 的发布队列和 HTTP **不是**同一套。

---

## 11. 请求体 write / stream

本节的 `write` / `stream` 用于 `HTTPREQ`。只有通道方法是 **POST（2）或 PUT（3）** 才能带体，否则 `"error method"`。GET 不要跟 `write`。持续推流上传使用固件 1.4.3 的 [11.1 chunk 模式](#11-1-chunk-upload)。

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

### 11.1 连续 chunked 上传（固件 1.4.3） {#11-1-chunk-upload}

`HTTPFREE="chunk"` 适合 MCU 持续推流：HTTP 连接和请求头准备完成后才给 `>`，每批数据由模组组装成 chunked 请求体。沿用 FREE 的 URL / path / header 参数，并输出服务器的状态行、响应头和正文。服务器需要支持 HTTP/1.1 chunked 请求体。

已知要上传 6 字节时：

~~~text
AT+HTTPFREE="chunk",2,"http://10.0.0.8/api/echo","","Content-Type: text/plain",6,30000
>
~~~

看到 `>` 后发送原始 `abcdef`，不带尾随 CRLF；收满 6 字节后自动结束并等待服务器响应。示例成功响应：

~~~text
HTTP/1.1 200 OK
Content-Type: text/plain
Content-Length: 2

ok
+HTTPFREE: 200,0,"ok",6,2

OK
~~~

结果行最后两项分别是已完整发送的 chunk 正文字节数、已接收的响应正文字节数。网络发送完成只代表数据交给本地传输层，最终完整 2xx 响应才表示整次调用成功。

未知长度时把长度设为 0：

~~~text
AT+HTTPFREE="chunk",2,"http://10.0.0.8/api/echo","","Content-Type: application/octet-stream",0,30000
>
~~~

输入数据中的每个 `10` 字节都编码为 `10 10`；结束时发送原始十六进制字节 `10 04`。例如正文 `61 10 04 62` 应发送 `61 10 10 04 62`，最后再发送 `10 04`。定长模式所有字节透明传输，不做这项转义。`Ctrl+Z`（`1A`）在两种方式中都是数据。

响应下载要限速时，模式可写 `"chunk:8192"`，表示响应正文平均接收速率 8192 字节/秒；它不控制主机推流速度。输入环形缓冲区 16 KiB，网络每次取最多 2048 字节，持续输入快于网络发送会明确报 `-35`。

失败结果行会给出负数错误码、已解析的 HTTP 状态和发送进度；已经拿到的响应信息仍输出。主机收到失败结果行应停止推流，等待最终 `ERROR` 后再发新 AT。断线后不自动重传，应用应根据服务端语义决定是否重试。

参数范围、16 KiB 响应正文上限、完整错误码和 `HTTPUPLOAD` 兼容入口见 [HTTP 指令手册 7.4～7.6](../manual/http.md#7-4-chunk-upload)。Lua 对应两种接口：手动 `http.upload(opts)`，或回调供数 `http.upload(opts, producer)`，见 [Lua HTTP API](../../api/network/http.md#6-9-upload)。

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
| 第二条 `HTTPREQ` 很久才动 | AT 处理串行，在等前一条事务结束 |
| chunk 结果 `-31` | 看已输出的 HTTP 状态和响应正文；确认接口支持 chunked 请求体，以及认证、Content-Type 是否符合服务端要求 |
| chunk 结果 `-34` | 输入空闲超时：定长未收满，或未知长度未发送结束序列 |
| chunk 结果 `-35` | 16 KiB 输入缓冲区满；降低主机推流速度，`max_recv_bps` 只限响应下载 |
| chunk 结果 `-36` | 未知长度的 DLE 转义非法，或结束后发送了多余数据；定长正文末尾不要追加 CRLF |
| chunk 结果 `-38` | 服务器在结束帧发送完成前提前返回成功状态，整次上传按失败处理 |

参数错误全表见 [http.md 第 8 节](../manual/http.md#8-错误一览)；普通请求数字码见 [第 6.4 节](../manual/http.md#64-请求错误码结果行不是-error-reason)，chunk 上传负数码见 [7.5](../manual/http.md#7-5-upload-errors)。

---

## 13. 对照手册

| 要查 | 去 |
| --- | --- |
| `HTTPURL` / `HTTPCFG` / `HTTPREQ` / `HTTPFREE` | [http.md](../manual/http.md) |
| 通道连接保持、自由会话 | [HTTPCONN](../manual/http.md#10-athttpconn)、[HTTPSESS](../manual/http.md#11-athttpsess) |
| chunk 上传参数、结束字节、响应格式、HTTPUPLOAD | [HTTP 手册 7.4～7.6](../manual/http.md#7-4-chunk-upload) |
| Lua 上传对象和取数回调 | [http.upload](../../api/network/http.md#6-9-upload) |
| 证书组读写 | [ssl.md](../manual/ssl.md) |
| `5[1]` / `6[1]` / `1[1:2]` | [route.md](../manual/route.md) |
| 行格式、三套编号 | [convention.md](../manual/convention.md#4-通道编号) |
| 串口上行带上 HTTP | [rtu.md](../manual/rtu.md) 的 `DTUPSUP` |
| 常驻 TCP/MQTT | [Socket 专栏](socket.md)、[MQTT 连接专栏](mqtt.md) |
| `[http.N]` 全部 key | [rtu_config.cfg](../../api/rtu_config/rtu_config.md#12-httpn) |

---

## 14. 长连接与复用

反复访问同一服务时，保留 TCP/TLS 连接可以减少重复建连和 HTTPS 握手。两种入口共用连接管理和响应解析规则，事务都需要等到完整响应后才可继续。

### 14.1 已有配置通道

```lua
AT+HTTPURL=1,1,1,"","http://10.0.0.8"
AT+HTTPCFG=1,"keep_alive",1
AT+HTTPCFG=1,"idle_timeout",60
AT+HTTPCONN=1,"open"
AT+HTTPREQ=1,"async","/api/info"
AT+HTTPREQ=1,"async","/api/status"
AT+HTTPCONN=1,"status"
AT+HTTPCONN=1,"close"
```

`open` 可以省略，让第一次 HTTPREQ 建连。`close` 只释放当前运行态会话，配置仍在，下次 HTTPREQ 可自动建立新会话。HTTPS 继续用 HTTPCFG 的 `ssl_type` / `ssl_id`；详细参数和状态字段见 [HTTPCONN](../manual/http.md#10-athttpconn)。

### 14.2 不写通道配置的自由会话

```lua
AT+HTTPSESS=1,"open","https://api.example.com",2,1,60
AT+HTTPSESS=1,"req","async",1,"/device/info"
AT+HTTPSESS=1,"req","sync",2,"/report","Content-Type: application/json","write",{"v":1}
AT+HTTPSESS=1,"status"
AT+HTTPSESS=1,"close"
```

示例使用单向认证和证书组 1，需先写入对应 CA。会话号与配置通道号分开；自由会话 close 后必须重新 open。模式、正文输入和 chunk 上传见 [HTTPSESS](../manual/http.md#11-athttpsess)。

### 14.3 确认是否复用

观察 `connection_seq` 和 `reused`：同一会话的连接序号保持不变且 reused 为 1，表示本次借用了已有连接。预连接成功后，第一次请求也可以 reused=1；销毁再创建会话会重新计数。最终验证可结合服务端连接数与 TLS 握手日志。

空闲超时默认 60 秒，只释放连接；服务器也可以先关闭连接。下一次新请求可按需重建，已经发出但失败的请求不会自动重放。收到 Connection: close、正文未收完整或解析错误时不继续复用。

当前默认共 8 个会话名额，由配置通道、自由会话和 Lua 客户端共用。空闲释放 TCP/TLS 不销毁会话对象，不用时显式 close 归还名额。

### 14.4 断线后怎么继续请求

自由会话 `open` 成功后，底层连接断开不会销毁该会话。继续发同一会话的 `req` 即可按需重连，不需要每次重新 `open`；空闲时不会在后台持续尝试重连。

| 发生时机 | 行为 |
| --- | --- |
| 新请求发送前已经发现旧连接失效 | 尝试新建连接，成功后继续本次请求；`connection_seq` 增加，`reused=0` |
| 请求已开始发送或正在等待响应时才发现断线 | 本次返回错误，不自动重发；下一次新请求再尝试建连 |
| 自由会话已经 `close` 或设备重启 | 必须先重新 `open` |
| 固定通道执行了 `HTTPCONN close` | 持久化配置仍在，通道保持启用且开启 keep_alive 时，下次 `HTTPREQ` 可自动创建新会话 |

**当前没有 HTTP 断线主动 URC。** 空闲断线、本地空闲超时不会主动输出 AT 通知；请求期间发生错误，通过本次请求的 `"done"` 结果和 `ERROR` 报告。

主机可执行 `AT+HTTPSESS=1,"status"` 查看本地已知状态。查询不发送探活请求、不触发重连；网络静默中断时不能保证立即发现。看 `connected` 判断是否仍保留连接，`last_error=0` 或 `reused=1` 不能单独证明连接仍在线。

完整生命周期和你可能看到的 `+HTTPSESS: 1,0,1,0,1,10,0,1` 字段解读，见 [手册 11.5：断线与重连](../manual/http.md#115-断线按需重连与-urc) 和 [11.6：状态判读示例](../manual/http.md#116-状态判读示例)。失败的 POST/PUT 是否重试，应由应用结合服务端的幂等、去重和处理状态决定。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-19 | 首版：自由请求与通道、HTTPS、单/多/混合、响应路由、主动发送、同步异步、write/stream |
| 1.1.0 | 2026-11-09 | 对应固件 1.4.3。增加 FREE chunk 定长/未知长度上传流程、完整响应输出和失败处理；更新 UART/USB AT 响应路由 |
| 1.2.0 | 2026-11-12 | 当前 SDK 新增配置通道连接保持和自由会话流程；区分连接保留与 AT 串行执行，补充复用验证和断线行为 |
| 1.2.1 | 2026-11-13 | 补充现有按需重连、失败不重发、无主动断线 URC、状态查询边界，以及自由会话与固定通道关闭后的区别 |
