#  HTTP

**文档版本** `1.0.1`

配置并执行模组上的 **5 路 HTTP 通道**，以及一条**不占通道**的自由请求。指令走应用 AT 口，与 [`rtu_config.cfg` 的 `[http.N]`](../api/rtu_config/rtu_config.md#12-httpn) 读写**同一份持久化配置**（自由请求除外）。通道号一律 **1～5**，与 `[http.1]`～`[http.5]` 对应。

HTTP 的 N **不是** Socket / MQTT 的 N，也不是 SSL 证书组号。`ssl_id` 才引用 [SSL 组 1～3](ssl.md)。见 [convention.md 第 4 节](convention.md#4-通道编号)。

行格式与失败风格见 [convention.md](convention.md)。Lua `require("http")` 见 [http API](../api/network/http.md)（脚本侧是一次性 `request`，与本篇通道配置不是同一条调用栈，但证书组 / URL 规则可对照）。

---

## 目录

- [1. 约定](#1-约定)
- [2. 指令一览](#2-指令一览)
- [3. 通道与生效时机](#3-通道与生效时机)
- [4. AT+HTTPURL](#4-athttpurl)
- [5. AT+HTTPCFG](#5-athttpcfg)
- [6. AT+HTTPREQ](#6-athttpreq)
- [7. AT+HTTPFREE](#7-athttpfree)
- [8. 错误一览](#8-错误一览)
- [9. 联调顺序](#9-联调顺序)
- [修订记录](#修订记录)

---

## 1. 约定

### 1.1 行格式

| 项 | 约定 |
| --- | --- |
| 命令结束 | 每条命令以 `<CR><LF>`（`\r\n`）结束。下文示例省略行结束符 |
| 大小写 | 命令名大小写不敏感；`key`、URL、`sync`/`async` 按原文 |
| 字符串 | URL、header、path、key 建议加双引号 |
| 数值 | 十进制整数 |
| 尾部裸数据 | `<payload>` 为 **TAILRAW**：最后一个逗号之后到行结束之前的**原始字节**，不做 HEX 文本解码 |

测试命令（`AT+XXX=?`）返回取值范围与写法，以 `OK` 结束。

### 1.2 命令形态

| 形态 | 写法 | 本篇是否支持 |
| --- | --- | --- |
| 测试 | `AT+XXX=?` | 四条都支持 |
| 按通道查询 | `AT+XXX=<id>?` | `HTTPURL` / `HTTPCFG` |
| 按 key 查询 | — | **不支持**。`AT+HTTPCFG=<id>,"key"` 缺第三参会 `param`（测试文案里写了 query，实现没有单项查询） |
| 设置 | `AT+XXX=…` | 四条都支持 |
| 无参查询 `AT+XXX?` | — | **不支持** |

### 1.3 成功与失败

配置类（`HTTPURL` / `HTTPCFG`）以及 `HTTPREQ` / `HTTPFREE` 的**参数错误**：

```lua
<CR><LF>+<CMD>: "error <reason>"<CR><LF>
<CR><LF>ERROR<CR><LF>
```

`HTTPREQ` / `HTTPFREE` 在参数合法之后，**请求本身失败仍可能回 `OK`**，结果行里带负状态和错误码，见各条。这与 Socket / MQTT 发送失败回 `ERROR` 不同。

`HTTPREQ` 还受 `resp_at_mode` 控制：成功/失败结果行可以不打，只留 `OK`。

`HTTPREQ` 的 `stream` 与 `SSL` 的 `stream` 一样：先打 `>` 再阻塞读后续裸字节。

### 1.4 与 Lua / 配置文件

| 入口 | 做什么 |
| --- | --- |
| `HTTPURL` / `HTTPCFG` | 改 HTTP 通道持久化 |
| `HTTPREQ` | 用已落盘的通道立刻发请求 |
| `HTTPFREE` | 本次临时 URL/方法/头/体，**不读不写**通道配置 |
| `[http.N]` | 同一套通道 key（另有 `url_encode`，本篇 AT **没有**对应指令） |
| Lua `require("http")` | 脚本一次性请求，不占用 AT 通道号 |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+HTTPURL` | `=?` | `<id>?` | `<id>,<enable>,<method>,<header>,<url>` | 通道使能、方法、头、URL |
| `AT+HTTPCFG` | `=?` | `<id>?` 全量 | `<id>,"key",<value>` | TLS、超时、回包策略、输出路由 |
| `AT+HTTPREQ` | `=?` | 无 | `<id>,"sync\|async"[,path[,action[,payload]]]` | 按通道发请求 |
| `AT+HTTPFREE` | `=?` | 无 | `"sync\|async",<method>,<url>[,path[,header[,payload]]]` | 自由请求 |

---

## 3. 通道与生效时机

- 通道数 **5**。`<id>` = 1～5。越界回 `"error id"`。
- **`HTTPURL` / `HTTPCFG` 只落盘，不拆已经建立的连接，也不改正在飞的那次请求。** 下次 `HTTPREQ` 才读新配置。
- **`HTTPREQ` / `HTTPFREE` 立刻执行**，会占住这条 AT 处理直到同步收完或异步启动返回。
- `HTTPREQ` 要求该通道 `enable=1`。`enable=0` 时不回 `"error …"`，而是结果行 `status=-1`、错误码 `1002`、文案 `"channel_disabled"`（再按 `resp_at_mode` 决定是否打印），最后仍可能是 `OK`。
- URL / header 各最长 **511** 字节（不含结尾 NUL）。超时 AT 可写 **1～60** 秒（配置文件里 `timeout_s` 范围更宽，本指令按 1～60 校验）。
- HTTPS：`ssl_type` 为 1～3，`ssl_id` 为 1～3。本篇 **不能** 把 `ssl_id` / `ssl_type` 写成 0。证书内容见 [ssl.md](ssl.md)。
- 出厂未改过时常见默认：

| 项 | 默认 |
| --- | --- |
| `enable` | 0 |
| `method` | 1（GET） |
| `url` / `header` | 空 |
| `timeout` | 5 s |
| `ssl_id` | 1 |
| `ssl_type` | 1（HTTPS 不校验证书） |
| `url_encode` | 0（仅配置文件，AT 改不了） |
| `resp_status_line` / `resp_header` / `resp_content` | 1 / 1 / 1 |
| `resp_at_mode` | 0（结果行都回） |
| 输出路由 | `6[1]`（UART1），见 [路由串](route.md) |

`method`：`0` NONE，`1` GET，`2` POST，`3` PUT，`4` DELETE，`5` HEAD。

`ssl_type`：`1` 不校验，`2` 校验服务端（要 CA），`3` 双向。

`resp_at_mode`：`0` 成功失败都打 `+HTTPREQ` 结果行；`1` **仅失败**打结果行，成功只 `OK`；`2` 都不打结果行，只 `OK`。

---

## 4. AT+HTTPURL {#4-athttpurl}

设置或查询一路通道的 **使能 + 方法 + 额外头 + URL**。不改超时、TLS、回包策略。

### 4.1 测试命令

```lua
AT+HTTPURL=?
```

```lua
+HTTPURL: (id,enable,method,"header","url")
id:1-5, enable:0|1 (per-channel), method:0-NONE,1-GET,2-POST,3-PUT,4-DELETE,5-HEAD

OK
```

### 4.2 查询命令

```lua
AT+HTTPURL=<id>?
```

```lua
+HTTPURL: <id>,<enable>,<method>,"<header>","<url>"

OK
```

未配置时 header / url 可能是 `""`，`enable` 为 0，`method` 常见 1。

**失败**：`param`、`id`、`nomem`、`read`。

### 4.3 设置命令

```lua
AT+HTTPURL=<id>,<enable>,<method>,<header>,<url>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～5 | 通道 |
| `<enable>` | 整数 | 0 或 1 | 通道使能 |
| `<method>` | 整数 | 0～5 | 见上表 |
| `<header>` | 字符串 | 0～511 | 额外头，可空 |
| `<url>` | 字符串 | 0～511 | URL，可空；可含占位符 |

五个参数都必须在，且 header / url 必须是字符串类型。过长 → `"error length"`。

**应答（成功）** 回显写入后的值，与查询同形。

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或类型不对 |
| `id` | 不是 1～5 |
| `enable` | 不是 0/1 |
| `method` | 大于 5 |
| `length` | header 或 url ≥ 512 |
| `nomem` | 申请配置缓冲失败 |
| `read` | 读持久化失败 |
| `save` | 写入失败 |

### 4.4 示例

```lua
AT+HTTPURL=1,1,1,"Accept: application/json","http://10.0.0.8/api/status"
+HTTPURL: 1,1,1,"Accept: application/json","http://10.0.0.8/api/status"

OK

AT+HTTPURL=1?
+HTTPURL: 1,1,1,"Accept: application/json","http://10.0.0.8/api/status"

OK
```

POST 带体时方法写 `2`，体在 `HTTPREQ` 的 `write` / `stream` 里给，不写在本指令。

---

## 5. AT+HTTPCFG {#5-athttpcfg}

按 **key** 写单通道细项，或全量查询。能改的名字是测试命令列出的那一组，**不是** `[http.N]` 的全部 key（没有 `enable` / `method` / `url` / `header` / `url_encode`）。

### 5.1 测试命令

```lua
AT+HTTPCFG=?
```

```lua
+HTTPCFG: (id,"ssl_type|ssl_id|route|timeout|resp_status_line|resp_header|resp_content|resp_at_mode",value)
id:1-5, ssl_type:1-3, ssl_id:1-3, timeout:1-60(second), resp_status_line/resp_header/resp_content:0|1, resp_at_mode:0-2
value uses RAW: number for ssl_type/ssl_id/timeout, string for route
query: AT+HTTPCFG=<id>,"<key>"
query all: AT+HTTPCFG=<id>?

OK
```

测试文案里的「按 key 查询」**没有实现**。请只用 `AT+HTTPCFG=<id>?`。

### 5.2 查询全部

```lua
AT+HTTPCFG=<id>?
```

成功时按固定顺序连续输出，最后 `OK`：

`ssl_id` → `ssl_type` → `route` → `resp_status_line` → `resp_header` → `resp_content` → `resp_at_mode` → `timeout`。

`route` 的 value 带引号。路由转字符串失败时打空串 `""`。

拼爆缓冲 → `"error overflow"`；申请失败 → `"error nomem"`。

### 5.3 设置

```lua
AT+HTTPCFG=<id>,"<key>",<value>
```

第三参必须有，按裸文本解析（数字或路由串，可带引号）。

| key | value 形态 | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `ssl_type` | 整数 | 1～3 | TLS 模式。非法回 `"error ssl_type"` |
| `ssl_id` | 整数 | 1～3 | 证书组。非法回 `"error ssl_id"` |
| `timeout` | 整数 秒 | 1～60 | 非法回 `"error timeout"` |
| `route` | 路由串 | 须能解析 | 例如 `6[1]`。非法回 `"error route"` |
| `resp_status_line` | 整数 | 0 或 1 | 是否把状态行写到输出路由 |
| `resp_header` | 整数 | 0 或 1 | 是否把头写到输出路由 |
| `resp_content` | 整数 | 0 或 1 | 是否把体写到输出路由 |
| `resp_at_mode` | 整数 | 0～2 | AT 结果行策略 |

`resp_*` 解析失败或越界时，reason **就是 key 名**（`resp_status_line` / `resp_header` / `resp_content` / `resp_at_mode`）。未知 key → `"error key"`。

**应答（成功）**

数值：

```lua
+HTTPCFG: <id>,"<key>",<number>

OK
```

路由：

```lua
+HTTPCFG: <id>,"route","6[1]"

OK
```

**失败 reason**：`param`、`id`、`key`、`ssl_type`、`ssl_id`、`timeout`、`route`、`resp_status_line`、`resp_header`、`resp_content`、`resp_at_mode`、`nomem`、`read`、`save`、`overflow`。

### 5.4 示例

```lua
AT+HTTPCFG=1,"timeout",10
+HTTPCFG: 1,"timeout",10

OK

AT+HTTPCFG=1,"ssl_type",2
+HTTPCFG: 1,"ssl_type",2

OK

AT+HTTPCFG=1,"route","6[1]"
+HTTPCFG: 1,"route","6[1]"

OK

AT+HTTPCFG=1?
+HTTPCFG: 1,"ssl_id",1
+HTTPCFG: 1,"ssl_type",2
+HTTPCFG: 1,"route","6[1]"
+HTTPCFG: 1,"resp_status_line",1
+HTTPCFG: 1,"resp_header",1
+HTTPCFG: 1,"resp_content",1
+HTTPCFG: 1,"resp_at_mode",0
+HTTPCFG: 1,"timeout",10

OK
```

---

## 6. AT+HTTPREQ {#6-athttpreq}

用已配置通道 **立刻发请求**。`sync` 收完再把响应写到该通道 `route`；`async` 分段直出（结果行里的 HTTP 状态在启动/首段完成后给出）。

**仅设置，无查询。**

无 body：

```lua
AT+HTTPREQ=<id>,"sync"
AT+HTTPREQ=<id>,"async"
AT+HTTPREQ=<id>,"sync","/dynamic/path"
AT+HTTPREQ=<id>,"sync",""
```

`write`（TAILRAW）：

```lua
AT+HTTPREQ=<id>,"sync","/p","write",<TAILRAW>
AT+HTTPREQ=<id>,"sync","","write",<TAILRAW>
```

`stream`（先 `>` 再阻塞读，超时 10 s）：

```lua
AT+HTTPREQ=<id>,"sync","/p","stream"
AT+HTTPREQ=<id>,"sync","","stream"
```

第三参若正好是 `write` 或 `stream`，当作 **action**（path 省略）。

### 6.1 测试命令

```lua
AT+HTTPREQ=?
```

```lua
+HTTPREQ: (id,"sync|async"[,"path"[,"write|stream"[,<TAILRAW>]]])
id:1-5, path可选可为空；async为分段直出，sync为收完再输出
result: +HTTPREQ: id,status,error_code,"error_msg"

OK
```

### 6.2 设置

```lua
AT+HTTPREQ=<id>,<mode>[,<path>[,<action>[,<payload>]]]
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～5 | 通道 |
| `<mode>` | 字符串 | `sync` / `async` | 其它拼写 → `"error mode"` |
| `<path>` | 字符串 | 可空 | 拼在已配 URL 后面的路径；可省略 |
| `<action>` | 字符串 | `write` / `stream` 或省略 | 只有 POST/PUT 才能带体，否则 `"error method"` |
| `<payload>` | TAILRAW | `write` 时长度 ≥ 1 | `stream` **禁止**再跟 TAILRAW（→ `"error stream_param"`） |

`write` 缺载荷 → `"error write_payload"`。`stream` 先打：

```lua
>
```

然后等主机再发一截原始字节（以行结束或阻塞读超时为准）。读不到 → `"error stream_read"`。

body 会按 AT HTTP 映射规则展开；展开失败 → `"error maping"`。展开后同步请求体上限按 **64 KiB** 收响应。

通道 `enable=0`：不走 `"error enable"`，见 [第 3 节](#3-通道与生效时机)。

### 6.3 应答

参数错误：`+HTTPREQ: "error <reason>"` + `ERROR`。

参数合法后（`resp_at_mode=0` 或失败且 `resp_at_mode=1`）：

```lua
+HTTPREQ: <id>,<status>,<error_code>,"<error_msg>"

OK
```

| 字段 | 含义 |
| --- | --- |
| `<status>` | HTTP 状态码；没拿到响应时为 `-1` |
| `<error_code>` | `0` 成功；非 0 见下表 |
| `<error_msg>` | 成功为 `"ok"`；通道未开为 `"channel_disabled"`；其它为下表短词 |

`resp_at_mode=2`，或 `resp_at_mode=1` 且成功：只有

```lua
OK
```

没有 `+HTTPREQ` 行。响应正文是否出现在 AT 口，还取决于 `route` 以及 `resp_status_line` / `resp_header` / `resp_content`。状态行形如 `HTTP/1.1 200 OK`。

同步成功时，状态行 / 头 / 体按三个开关写到 `route`；头与体之间会插一空行。

### 6.4 请求错误码（结果行，不是 `"error reason"`）

这些码出现在 `+HTTPREQ: id,status,code,"msg"` 里，**后面仍是 `OK`**（除非被 `resp_at_mode` 吃掉结果行）。

| 码 | 文案 | 可能原因 |
| --- | --- | --- |
| 0 | `ok` | 请求流程成功（HTTP 状态仍可能是 4xx/5xx） |
| 1001 | `rtu_precheck_param` | 通道参数不齐 |
| 1002 | `rtu_disabled` | 预检判定通道不可用（AT 未使能时文案固定为 `channel_disabled`） |
| 1101 | `rtu_build_request` | 拼请求失败（URL/头不合法等） |
| 1201 | `rtu_load_tls` | 证书组读不出 |
| 1301 | `rtu_config_tls` | TLS 模式与证书不匹配 |
| 2001 | `sync_param` | 同步参数非法 |
| 2002 | `sync_connect` | 同步连接失败 |
| 2003 | `sync_socket_invalid` | 套接字无效 |
| 2004 | `sync_send` | 同步发送失败 |
| 2005 | `sync_recv_first` | 首包接收失败 |
| 2006 | `sync_parse_header` | 响应头解析失败 |
| 2007 | `sync_require_cl` | 需要 Content-Length 但没有 |
| 2008 | `sync_size_limit` | 响应超过 64 KiB 上限 |
| 2009 | `sync_no_mem` | 同步内存不足 |
| 2010 | `sync_recv_loop` | 后续接收失败 |
| 2011 | `sync_dns` | 域名解析失败 |
| 2012 | `sync_tls` | TLS 握手/校验失败 |
| 2013 | `sync_timeout` | 同步超时 |
| 2014 | `sync_closed` | 对端关闭 |
| 2015 | `sync_parse_chunked` | chunked 解析失败 |
| 2016 | `sync_url` | URL 非法 |
| 3001 | `async_param` | 异步参数非法 |
| 3002 | `async_no_mem_header` | 异步头内存不足 |
| 3003 | `async_no_mem_post_copy` | 异步拷贝 POST 体失败 |
| 3004 | `async_connect` | 异步连接失败 |
| 3005 | `async_send` | 异步发送失败 |
| 3006 | `async_no_mem_recv` | 异步收包内存不足 |
| 3007 | `async_recv_first` | 异步首包失败 |
| 3008 | `async_parse_header` | 异步头解析失败 |
| 3009 | `async_chunk_parse` | 异步 chunk 解析失败 |
| 3010 | `async_no_mem_temp` | 异步临时缓冲不足 |
| 3011 | `async_recv_loop` | 异步后续接收失败 |
| 3012 | `async_dns` | 异步 DNS 失败 |
| 3013 | `async_tls` | 异步 TLS 失败 |
| 3014 | `async_timeout` | 异步超时 |
| 3015 | `async_closed` | 异步对端关闭 |
| 3016 | `async_url` | 异步 URL 非法 |

未列入的码文案为 `unknown`。

### 6.5 参数失败 reason

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或 id/mode 类型不对 |
| `id` | 不是 1～5 |
| `read` | 读通道配置失败 |
| `mode` | 不是 `sync` / `async` |
| `path` | 第三参不是字符串 |
| `action` | 第四参不是字符串，或不是 `write`/`stream` |
| `method` | 带了 body 但通道方法不是 POST/PUT |
| `write_payload` | `write` 没有 TAILRAW |
| `stream_param` | `stream` 后又跟了 TAILRAW |
| `stream_read` | `>` 之后 10 s 内没读到数据 |
| `maping` | 载荷占位符展开失败（过长或内存不足） |

### 6.6 示例

```lua
AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,200,0,"ok"

OK
```

POST 写体：

```lua
AT+HTTPURL=1,1,2,"Content-Type: text/plain","http://10.0.0.8/api/echo"
+HTTPURL: 1,1,2,"Content-Type: text/plain","http://10.0.0.8/api/echo"

OK

AT+HTTPREQ=1,"sync","","write",hello
+HTTPREQ: 1,200,0,"ok"

OK
```

通道未开（`resp_at_mode=0`）：

```lua
AT+HTTPREQ=1,"sync"
+HTTPREQ: 1,-1,1002,"channel_disabled"

OK
```

`stream`：发完命令后先看到 `>`，再贴原始字节。

---

## 7. AT+HTTPFREE {#7-athttpfree}

一次给出方法、URL、可选 path/header/body，**不读 `HTTPURL`/`HTTPCFG`，也不写盘**。没有通道号。响应默认打到 UART1（路由 `6[1]`）。总是打状态行 + 头 + 体（没有 `resp_*` 开关，也没有 `resp_at_mode`）。

TLS 按 URL 是否 `https` 走；证书组/模式用本次参数里的默认（未指定时按不校验处理）。要指定证书组请走通道 `HTTPREQ`。

**仅设置，无查询。**

### 7.1 测试命令

```lua
AT+HTTPFREE=?
```

```lua
+HTTPFREE: ("sync|async",method,"url"[,"path"[,"header"[,<TAILRAW>]]])
method:1-GET,2-POST,3-PUT,4-DELETE,5-HEAD
path/header optional, use "" to skip; content is optional TAILRAW (raw bytes to EOL)
POST/PUT with body only: AT+HTTPFREE="sync",2,"<url>","","",<TAILRAW>
result: +HTTPFREE: status,error_code,"error_msg"

OK
```

### 7.2 设置

```lua
AT+HTTPFREE=<mode>,<method>,<url>[,<path>[,<header>[,<payload>]]]
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<mode>` | 字符串 | `sync` / `async` | |
| `<method>` | 整数 | **1～5** | 没有 `0` NONE |
| `<url>` | 字符串 | 1～511，非空 | |
| `<path>` | 字符串 | 0～511 | `""` 表示不用 |
| `<header>` | 字符串 | 0～511 | `""` 表示不用 |
| `<payload>` | TAILRAW | 可省略 | 仅 POST/PUT 会发送；其它方法有体也**忽略**，不报错 |

**应答（参数合法后，含请求失败）**

```lua
+HTTPFREE: <status>,<error_code>,"<error_msg>"

OK
```

没有通道号。错误码与文案同 [第 6.4 节](#64-请求错误码结果行不是-error-reason)（没有 `channel_disabled` 这条预检）。请求失败仍然是 `OK`，不是 `ERROR`。

**参数失败** 才 `"error <reason>"` + `ERROR`：`param`、`mode`、`method`、`url`、`path`、`header`、`maping`。

### 7.3 示例

```lua
AT+HTTPFREE="sync",1,"http://10.0.0.8/api/status"
+HTTPFREE: 200,0,"ok"

OK
```

只带 body（path/header 用空串占位）：

```lua
AT+HTTPFREE="sync",2,"http://10.0.0.8/api/echo","","",hello
+HTTPFREE: 200,0,"ok"

OK
```

---

## 8. 错误一览

配置类与参数错误：`+<CMD>: "error <reason>"` + `ERROR`。

| reason | 出现指令 | 含义 |
| --- | --- | --- |
| `param` | 全部 | 参数个数、类型不对 |
| `id` | HTTPURL / HTTPCFG / HTTPREQ | 不是 1～5 |
| `enable` | HTTPURL | 不是 0/1 |
| `method` | HTTPURL / HTTPREQ / HTTPFREE | 方法非法，或 HTTPREQ 对非 POST/PUT 带体 |
| `length` | HTTPURL | header/url 过长 |
| `nomem` | HTTPURL / HTTPCFG | 内存不足 |
| `read` | HTTPURL / HTTPCFG / HTTPREQ | 读持久化失败 |
| `save` | HTTPURL / HTTPCFG | 写入失败 |
| `overflow` | HTTPCFG 全量查询 | 回包拼爆 |
| `key` | HTTPCFG | 未知 key |
| `ssl_type` / `ssl_id` / `timeout` / `route` | HTTPCFG | 对应值非法 |
| `resp_status_line` / `resp_header` / `resp_content` / `resp_at_mode` | HTTPCFG | 对应值非法 |
| `mode` | HTTPREQ / HTTPFREE | 不是 `sync`/`async` |
| `path` | HTTPREQ / HTTPFREE | path 类型不对或过长 |
| `action` | HTTPREQ | action 非法 |
| `write_payload` | HTTPREQ | `write` 无载荷 |
| `stream_param` | HTTPREQ | `stream` 带了 TAILRAW |
| `stream_read` | HTTPREQ | `>` 后读超时或空 |
| `maping` | HTTPREQ / HTTPFREE | 体映射失败 |
| `url` | HTTPFREE | URL 空或过长 |
| `header` | HTTPFREE | header 过长 |

请求阶段数字码见 [第 6.4 节](#64-请求错误码结果行不是-error-reason)。

---

## 9. 联调顺序

1. 驻网完成。
2. `AT+HTTPURL=1,1,1,"","http://<主机>/path"` 打开通道并给 URL。
3. 需要超时/TLS/回包策略：`AT+HTTPCFG=1,"timeout",10` 等。HTTPS 先按 [ssl.md](ssl.md) 写证书，再设 `ssl_id` / `ssl_type`。
4. `AT+HTTPREQ=1,"sync"` 看结果行 `status` 与 `"ok"`。
5. 不想占通道：`AT+HTTPFREE="sync",1,"http://<主机>/path"`。
6. 改 URL 后下一次 `HTTPREQ` 才会用新值；正在飞的请求不会被改配置打断。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：HTTPURL / HTTPCFG / HTTPREQ / HTTPFREE 的测试、查询、设置、`resp_at_mode` 静默、请求错误码与示例 |
| 1.0.1 | 2026-09-07 | `route` 改链到 [route.md](route.md) |
