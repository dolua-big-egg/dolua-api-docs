#  HTTP

**文档版本** `1.2.1`

**固件版本** `1.4.3` 起新增 `HTTPFREE="chunk"` 连续上传，保留自由请求的状态行、响应头和正文输出；支持定长自动结束及未知长度结束序列。详见 [7.4 Chunked 上传](#7-4-chunk-upload)。同版本修正自由请求在 USB AT 口的响应输出。

**当前 SDK 新增** 通道连接保持和 `HTTPSESS` 自由会话，见 [HTTPCONN](#10-athttpconn) 与 [HTTPSESS](#11-athttpsess)。这些能力需使用包含长连接实现的固件。

配置并执行模组上的 **5 路 HTTP 通道**，以及**不占配置通道**的自由请求或自由会话。指令走应用 AT 口，与 [`rtu_config.cfg` 的 `[http.N]`](../../api/rtu_config/rtu_config.md#12-httpn) 读写**同一份持久化配置**（自由请求除外）。通道号一律 **1～5**，与 `[http.1]`～`[http.5]` 对应。

HTTP 的 N **不是** Socket / MQTT 的 N，也不是 SSL 证书组号。`ssl_id` 才引用 [SSL 组 1～3](ssl.md)。见 [convention.md 第 4 节](convention.md#4-通道编号)。

明文 / HTTPS、单通道 / 多通道 / 与 SOCK·MQTT 混合、响应路由、同步异步的场景流程见 [专栏 · HTTP / HTTPS](../topics/http.md)。行格式与失败风格见 [convention.md](convention.md)。Lua `require("http")` 见 [http API](../../api/network/http.md)，其 `http.upload` 同样自固件 1.4.3 支持 chunked 上传。

---

## 目录

- [1. 约定](#1-约定)
- [2. 指令一览](#2-指令一览)
- [3. 通道与生效时机](#3-通道与生效时机)
- [4. AT+HTTPURL](#4-athttpurl)
- [5. AT+HTTPCFG](#5-athttpcfg)
- [6. AT+HTTPREQ](#6-athttpreq)
- [7. AT+HTTPFREE](#7-athttpfree)
  - [7.4 Chunked 上传（固件 1.4.3）](#7-4-chunk-upload)
  - [7.5 上传错误码](#7-5-upload-errors)
  - [7.6 AT+HTTPUPLOAD 兼容入口](#7-6-httpupload)
- [8. 错误一览](#8-错误一览)
- [9. 联调顺序](#9-联调顺序)
- [10. AT+HTTPCONN 与通道连接保持](#10-athttpconn)
- [11. AT+HTTPSESS 自由会话](#11-athttpsess)
  - [11.5 断线、按需重连与 URC](#115-断线按需重连与-urc)
  - [11.6 状态判读示例](#116-状态判读示例)
- [修订记录](#修订记录)

---

## 1. 约定

### 1.1 行格式

| 项 | 约定 |
| --- | --- |
| 命令结束 | 每条命令以 `<CR><LF>`（`\r\n`）结束。下文示例省略行结束符 |
| 大小写 | 命令名大小写不敏感；`key`、URL、`sync`/`async`/`chunk` 按原文 |
| 字符串 | URL、header、path、key 建议加双引号 |
| 数值 | 十进制整数 |
| 尾部裸数据 | `<payload>` 为 **TAILRAW**：最后一个逗号之后到行结束之前的**原始字节**，不做 HEX 文本解码 |

测试命令（`AT+XXX=?`）返回取值范围与写法，以 `OK` 结束。

### 1.2 命令形态

| 形态 | 写法 | 本篇是否支持 |
| --- | --- | --- |
| 测试 | `AT+XXX=?` | 本页指令均支持 |
| 按通道查询 | `AT+XXX=<id>?` | `HTTPURL` / `HTTPCFG` |
| 按 key 查询 | — | **不支持**。`AT+HTTPCFG=<id>,"key"` 缺第三参会 `param`（测试文案里写了 query，实现没有单项查询） |
| 设置 | `AT+XXX=…` | 本页指令均支持 |
| 无参查询 `AT+XXX?` | — | **不支持** |

### 1.3 成功与失败

配置类（`HTTPURL` / `HTTPCFG`）以及 `HTTPREQ` / `HTTPFREE` 的**参数错误**：

```lua
<CR><LF>+<CMD>: "error <reason>"<CR><LF>
<CR><LF>ERROR<CR><LF>
```

`HTTPREQ` 和 `HTTPFREE` 的 `sync` / `async` 模式在参数合法之后，**请求本身失败仍可能回 `OK`**，需要检查结果行的状态和错误码。

固件 **1.4.3** 新增的 `HTTPFREE="chunk"` / `HTTPUPLOAD` 以完整最终响应为准：收到完整 2xx 响应才回 `OK`；断线、超时、HTTP 拒绝等回错误结果行及 `ERROR`，见 [7.4](#7-4-chunk-upload)。

`HTTPCONN` / `HTTPSESS` 管理操作的非零 `ret` 以 `ERROR` 结束；`HTTPSESS` 请求的非零错误码也以 `ERROR` 结束，不能沿用普通 FREE 的“只看最终 OK”判断方式。

`HTTPREQ` 还受 `resp_at_mode` 控制：成功/失败结果行可以不打，只留 `OK`。

`HTTPREQ` 的 `stream` 与 `SSL` 的 `stream` 一样：先打 `>` 再阻塞读后续裸字节。

### 1.4 与 Lua / 配置文件

| 入口 | 做什么 |
| --- | --- |
| `HTTPURL` / `HTTPCFG` | 改 HTTP 通道持久化 |
| `HTTPREQ` | 用已落盘的通道立刻发请求 |
| `HTTPFREE` | 本次临时 URL/方法/头/体，**不读不写**通道配置 |
| `HTTPCONN` | 管理配置通道的运行态连接，不改 URL、方法等持久化配置 |
| `HTTPSESS` | 独立的运行态自由会话，不读写 HTTPURL 通道配置 |
| `[http.N]` | 同一套通道 key（另有 `url_encode`，本篇 AT **没有**对应指令） |
| Lua `require("http")` | 脚本请求或 chunked 上传，不占用 AT 通道号 |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+HTTPURL` | `=?` | `<id>?` | `<id>,<enable>,<method>,<header>,<url>` | 通道使能、方法、头、URL |
| `AT+HTTPCFG` | `=?` | `<id>?` 全量 | `<id>,"key",<value>` | TLS、超时、连接保持、回包策略、输出路由 |
| `AT+HTTPREQ` | `=?` | 无 | `<id>,"sync\|async"[,path[,action[,payload]]]` | 按通道发请求 |
| `AT+HTTPFREE` | `=?` | 无 | `"sync\|async[:max_recv_bps]",<method>,<url>[,path[,header[,payload]]]` | 自由请求；同样支持 `sync:速率` |
| `AT+HTTPFREE`（chunk） | `=?` | 无 | `"chunk[:max_recv_bps]",<method>,<url>[,path[,header[,total_bytes[,input_timeout_ms]]]]` | 固件 1.4.3，看到 `>` 后持续输入上传数据 |
| `AT+HTTPUPLOAD` | `=?` | 无 | `<method>,<url>[,total_bytes[,header[,input_timeout_ms]]]` | 固件 1.4.3，chunk 上传兼容入口 |
| `AT+HTTPCONN` | `=?` | `"status"` 操作 | `<id>,"open\|status\|close"` | 管理配置通道连接 |
| `AT+HTTPSESS` | `=?` | `"status"` 操作 | `<sid>,"open\|req\|status\|close"[,参数]` | 自由会话和连接复用 |

---

## 3. 通道与生效时机

- 通道数 **5**。`<id>` = 1～5。越界回 `"error id"`。
- `HTTPURL` / `HTTPCFG` 更新持久化配置，下一次 `HTTPREQ` 读取新值。修改 `keep_alive` / `idle_timeout` 后会释放该通道现有会话；URL 或 TLS 配置变化时，下次请求更换会话。正在执行的请求不会被配置更新直接改写。
- `HTTPREQ` / `HTTPFREE` / `HTTPSESS` 请求会占住 AT 处理直到事务完成；`async` 表示接收期间分段输出，不表示立即返回。
- `HTTPREQ` 要求该通道 `enable=1`。`enable=0` 时不回 `"error …"`，而是结果行 `status=-1`、错误码 `1002`、文案 `"channel_disabled"`（再按 `resp_at_mode` 决定是否打印），最后仍可能是 `OK`。
- URL / header 各最长 **511** 字节（不含结尾 NUL）。超时 AT 可写 **1～60** 秒（配置文件里 `timeout_s` 范围更宽，本指令按 1～60 校验）。
- HTTPS：`ssl_type` 为 1～3，`ssl_id` 为 1～3。本篇 **不能** 把 `ssl_id` / `ssl_type` 写成 0。证书内容见 [ssl.md](ssl.md)。
- `Host`、`Content-Length`、`Transfer-Encoding`、`Connection`、`Expect` 由 HTTP 实现管理，自定义这些请求头会返回参数错误。
- 出厂未改过时常见默认：

| 项 | 默认 |
| --- | --- |
| `enable` | 0 |
| `method` | 1（GET） |
| `url` / `header` | 空 |
| `timeout` | 5 s |
| `keep_alive` | 0（单次连接） |
| `idle_timeout` | 60 s |
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
+HTTPCFG: (id,"ssl_type|ssl_id|route|timeout|keep_alive|idle_timeout|resp_status_line|resp_header|resp_content|resp_at_mode",value)
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

`ssl_id` → `ssl_type` → `route` → `resp_status_line` → `resp_header` → `resp_content` → `resp_at_mode` → `keep_alive` → `idle_timeout` → `timeout`。

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
| `keep_alive` | 整数 | 0 或 1 | 默认 0；1 为按通道保留连接。非法回 `"error keep_alive"` |
| `idle_timeout` | 整数 秒 | 1～3600 | 默认 60；事务完成后的连接空闲时长。非法回 `"error idle_timeout"` |
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

**失败 reason**：`param`、`id`、`key`、`ssl_type`、`ssl_id`、`timeout`、`keep_alive`、`idle_timeout`、`route`、`resp_status_line`、`resp_header`、`resp_content`、`resp_at_mode`、`nomem`、`read`、`save`、`overflow`。

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
+HTTPCFG: 1,"keep_alive",0
+HTTPCFG: 1,"idle_timeout",60
+HTTPCFG: 1,"timeout",10

OK
```

---

## 6. AT+HTTPREQ {#6-athttpreq}

用已配置通道 **立刻发请求**。`sync` 收完再把响应写到该通道 `route`；`async` 在接收期间分段直出，最终结果在本次事务结束后给出。

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

一次给出方法、URL、可选 path/header/body，**不读 `HTTPURL`/`HTTPCFG`，也不写盘**。没有通道号。固件 **1.4.3** 中，从 UART 或 USB AT 发起时，状态行、响应头、正文和结果均回到发起请求的同一个 AT 口。普通 `sync` / `async` 从其他入口调用时，响应数据仍回落到 UART1。总是输出状态行 + 头 + 体（没有 `resp_*` 开关，也没有 `resp_at_mode`）。

TLS 按 URL 是否 `https` 走；证书组/模式用本次参数里的默认（未指定时按不校验处理）。要指定证书组请走通道 `HTTPREQ`。

**仅设置，无查询。**

### 7.1 测试命令

```lua
AT+HTTPFREE=?
```

```lua
+HTTPFREE: ("sync|async|chunk[:max_recv_bps]",method,"url"[,"path"[,"header"[,<TAILRAW>]]])
method:1-GET,2-POST,3-PUT,4-DELETE,5-HEAD
example: AT+HTTPFREE="async:8192",1,"http://example.com/file.bin"
max_recv_bps: body bytes/s, omitted or 0 means unlimited
path/header optional, use "" to skip; content is optional TAILRAW (raw bytes to EOL)
POST/PUT with body only: AT+HTTPFREE="sync",2,"<url>","","",<TAILRAW>
chunk POST/PUT: AT+HTTPFREE="chunk",2,"<url>","","",total_bytes[,input_timeout_ms]
chunk total=0/omitted uses DLE EOT(10 04), escape DLE as 10 10; wait for > before input
chunk response includes HTTP status line, headers and body
chunk result: +HTTPFREE: status,error_code,"error_msg",sent_bytes,response_bytes; OK/ERROR
result: +HTTPFREE: status,error_code,"error_msg"

OK
```

### 7.2 设置

本节为 `sync` / `async` 的一次性请求体；连续上传见 [7.4](#7-4-chunk-upload)。

```lua
AT+HTTPFREE=<mode>,<method>,<url>[,<path>[,<header>[,<payload>]]]
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<mode>` | 字符串 | `sync` / `async`，可追加 `:max_recv_bps` | 如 `async:8192`，响应正文平均接收限速为 8192 字节/秒；0 或省略不限速 |
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

### 7.4 Chunked 上传（固件 1.4.3） {#7-4-chunk-upload}

在 `HTTPFREE` 的基础上选择 `chunk` 模式，连接成功、请求头发出且完成 `100 Continue` 等待后输出 `>`，此后主机可以持续推送二进制数据。模组自动生成 HTTP/1.1 `Transfer-Encoding: chunked` 请求体，结束时发送终止 chunk，接收最终响应并输出完整状态行、响应头和正文。

~~~text
AT+HTTPFREE="chunk[:max_recv_bps]",<method>,"<url>"[,"<path>"[,"<header>"[,<total_bytes>[,<input_timeout_ms>]]]]
~~~

| 参数 | 范围与含义 |
| --- | --- |
| `method` | 仅 `2` POST 或 `3` PUT |
| `url` / `path` / `header` | 延续 FREE 的位置和规则，各最多 511 字节；`path`、`header` 不用时写 `""` |
| `header` | 可附加一对 `Key: Value`，如 `Content-Type: application/octet-stream`；省略时使用默认正文类型 |
| `total_bytes` | 省略或 0：未知长度，使用结束序列；1～2147483647：定长，收满后自动结束。按解码后的上传正文计数 |
| `input_timeout_ms` | 输入空闲超时，默认 30000 ms；范围 100～3600000 ms。定长未收满、未知长度未结束且持续无输入时失败 |
| `max_recv_bps` | 可选模式后缀，响应正文接收限速，0 或省略不限速。例如 `chunk:8192`；不限制主机向模组输入的速度 |

第六参及其后的超时是裸十进制参数，例如 `...,6,30000`，不要把它们合成带引号的字符串。`Host`、`Content-Length`、`Transfer-Encoding`、`Connection`、`Expect` 由模组管理，不能通过 `header` 覆盖。与普通 FREE 一样，HTTPS 默认不校验服务端证书；本指令没有证书组选择参数。

仅支持从 **物理 UART 或 USB AT** 发起，输入和响应均使用发起端口。等待提示符后再发正文；提示符前发生 DNS、TLS、连接失败或服务器提前拒绝时直接返回错误。客户端会发送 `Expect: 100-continue`，默认等待 1000 ms，服务器未答复 100 时继续上传。

**定长输入**

~~~text
AT+HTTPFREE="chunk",2,"http://10.0.0.8/api/echo","","Content-Type: text/plain",6,30000
>
~~~

看到 `>` 后发送恰好 6 字节 `abcdef`，模组自动结束上传。**正文后不追加 CRLF**；所有二进制值（包括 `10 04`、`1A`）都按数据处理，无需转义。此时长度负责划分上传数据，主机要等最终 `OK` / `ERROR` 后再发下一条 AT。

**未知长度输入**

~~~text
AT+HTTPFREE="chunk",2,"http://10.0.0.8/api/echo","","Content-Type: application/octet-stream",0
>
~~~

看到 `>` 后持续发送数据，并按下表编码。表中是十六进制**原始字节**，串口工具应使用 HEX 发送，不能输入文本 `"10 04"` 代替。

| 意图 | 主机发送字节 | 上传正文 |
| --- | --- | --- |
| 普通字节 | 原样 | 原样 |
| 一个 DLE 字节 `10` | `10 10` | `10` |
| 数据中包含 `10 04` | `10 10 04` | `10 04` |
| 结束上传 | `10 04` | 不计入正文；模组发送终止 chunk |

转义序列可跨串口接收批次。DLE 后接非 `10` / `04` 的字节为 framing 错误；单独 DLE 后不再发送会触发输入超时。`Ctrl+Z`（`1A`）是普通数据。若数据集包含任意二进制值，推荐已知长度方式，或在主机发送端统一完成上述 DLE 转义。

**响应与结束**

仍支持 FREE 的响应头输出，示意如下；状态码、头字段和正文由服务器决定：

~~~text
HTTP/1.1 200 OK
Content-Type: text/plain
Content-Length: 2

ok
+HTTPFREE: 200,0,"ok",6,2

OK
~~~

| 结果字段 | 含义 |
| --- | --- |
| `status` | 已解析的 HTTP 状态码；未获得最终状态时为 0 |
| `error_code` / `error_msg` | 原生负数错误码及文案，见 [7.5](#7-5-upload-errors)；成功为 `0,"ok"` |
| `sent_bytes` | 已完整交给本地传输层的 chunk 正文累计字节数；不含 chunk 帧和串口转义字节 |
| `response_bytes` | 已接收、解码的响应正文长度；输出失败时不代表主机已收到这些字节 |

成功要求上传正常结束并收到完整 **2xx** 最终响应。非 2xx 返回 `-31`，结束帧发完前收到 2xx 返回 `-38`；已经获得的响应信息仍输出。上传中途断线也返回错误，不自动重试。发送失败的当前 chunk 可能已有部分正文到达服务器，`sent_bytes` 只累计完整发送的 chunk。

串口输入环形缓冲区为 **16 KiB**，网络发送按最多 **2048 字节**一块取数；主机输入持续快于网络时，缓冲区满返回 `-35`。响应正文在内存中收齐，上限 **16 KiB**，超过返回 `-15`。`max_recv_bps` 只控制响应接收，主机推流速度应结合网络发送能力控制。

失败时先输出五字段结果行，主机收到后应立即停止推流。模组继续吸收输入，等待约 300 ms 安静期，最长等待 `input_timeout_ms` 后恢复 AT 解析并输出 `ERROR`。**等待最终 `OK` / `ERROR` 后再发下一条指令**。

### 7.5 上传错误码 {#7-5-upload-errors}

以下用于固件 **1.4.3** 的 `HTTPFREE="chunk"` / `HTTPUPLOAD`。普通 `sync` / `async` 继续使用 [6.4](#64-请求错误码结果行不是-error-reason) 的 2000 / 3000 系列码。

| 码 | 文案 | 含义 |
| --- | --- | --- |
| 0 | `ok` | 上传结束且完整最终响应为 2xx |
| -1 / -2 | `invalid param` / `invalid url` | 请求参数、header 或 URL 非法 |
| -3 | `out of memory` | 缓冲区或连接内存不足 |
| -4 / -5 / -6 | `dns resolve failed` / `socket failed` / `connect failed` | DNS、建 socket 或连接失败 |
| -7 | `tls failed` | TLS 连接失败 |
| -8 | `timeout` | 网络发送或响应接收超时 |
| -9 / -10 / -11 | `send failed` / `recv failed` / `connection closed` | 发送、接收失败或连接提前关闭 |
| -12 / -13 | `parse header failed` / `parse chunked failed` | 响应解析失败 |
| -15 | `response too large` | 响应正文超过 16 KiB |
| -16 | `response output failed` | 状态行、响应头或正文输出失败 |
| -30 | `upload state` | 上传状态无效，或输入端口无法进入流接收状态 |
| -31 | `http rejected` | 最终 HTTP 状态非 2xx，如 401、413、417、500 |
| -32 | `upload length mismatch` | 正文与约定长度不符 |
| -34 | `upload input timeout` | 主机输入空闲超过设定时间 |
| -35 | `upload input overflow` | 输入缓冲区满或底层接收溢出 |
| -36 | `upload input framing` | 未知长度模式转义非法，或结束后继续输入多余数据 |
| -38 | `early final response` | 上传结束帧发送完成前收到 2xx 最终响应 |

参数阶段错误仍使用 `+HTTPFREE: "error <reason>"` 加 `ERROR`，例如长度/超时格式错误为 `upload length/timeout`，非物理 AT 入口为 `UART/USB required`。Lua 供数回调相关的 `-33` / `-37` 见 [Lua HTTP 文档](../../api/network/http.md#6-10-upload-methods)。

### 7.6 AT+HTTPUPLOAD 兼容入口 {#7-6-httpupload}

固件 **1.4.3** 同时保留以下入口，推荐新接入统一使用上述 `HTTPFREE="chunk"`：

~~~text
AT+HTTPUPLOAD=<method>,"<url>"[,<total_bytes>[,"<header>"[,<input_timeout_ms>]]]
AT+HTTPUPLOAD=?
~~~

此入口无 `path`、接收限速参数，其余输入、结束序列、响应状态行/头/正文及错误处理与 [7.4](#7-4-chunk-upload) 相同。结果前缀为 `+HTTPUPLOAD`，使用同样的五字段格式：

~~~text
+HTTPUPLOAD: <status>,<error_code>,"<error_msg>",<sent_bytes>,<response_bytes>

OK
~~~

请求失败时最后一行为 `ERROR`。

---

## 8. 错误一览

配置类与参数错误：`+<CMD>: "error <reason>"` + `ERROR`。

| reason | 出现指令 | 含义 |
| --- | --- | --- |
| `param` | 全部 | 参数个数、类型不对；chunk 方法须为 POST/PUT |
| `id` | HTTPURL / HTTPCFG / HTTPREQ | 不是 1～5 |
| `enable` | HTTPURL | 不是 0/1 |
| `method` | HTTPURL / HTTPREQ / HTTPFREE | 方法非法，或 HTTPREQ 对非 POST/PUT 带体 |
| `length` | HTTPURL | header/url 过长 |
| `nomem` | HTTPURL / HTTPCFG | 内存不足 |
| `read` | HTTPURL / HTTPCFG / HTTPREQ | 读持久化失败 |
| `save` | HTTPURL / HTTPCFG | 写入失败 |
| `overflow` | HTTPCFG 全量查询 | 回包拼爆 |
| `key` | HTTPCFG | 未知 key |
| `ssl_type` / `ssl_id` / `timeout` / `keep_alive` / `idle_timeout` / `route` | HTTPCFG | 对应值非法 |
| `resp_status_line` / `resp_header` / `resp_content` / `resp_at_mode` | HTTPCFG | 对应值非法 |
| `mode` | HTTPREQ / HTTPFREE | HTTPREQ 须为 `sync`/`async`；HTTPFREE 另支持 `chunk` 和可选限速后缀 |
| `path` | HTTPREQ / HTTPFREE | path 类型不对或过长 |
| `action` | HTTPREQ | action 非法 |
| `write_payload` | HTTPREQ | `write` 无载荷 |
| `stream_param` | HTTPREQ | `stream` 带了 TAILRAW |
| `stream_read` | HTTPREQ | `>` 后读超时或空 |
| `maping` | HTTPREQ / HTTPFREE | 体映射失败 |
| `url` | HTTPFREE | URL 空或过长 |
| `header` | HTTPFREE | header 过长 |
| `max_recv_bps` | HTTPFREE | 模式后缀速率不是 0～4294967295 的十进制整数 |
| `upload length/timeout` | HTTPFREE chunk | 第六参的长度或超时格式/范围错误 |
| `UART/USB required` | HTTPFREE chunk / HTTPUPLOAD | 发起端不是物理 UART 或 USB AT |

普通请求阶段数字码见 [第 6.4 节](#64-请求错误码结果行不是-error-reason)，chunk 上传见 [7.5](#7-5-upload-errors)。

---

## 9. 联调顺序

1. 驻网完成。
2. `AT+HTTPURL=1,1,1,"","http://<主机>/path"` 打开通道并给 URL。
3. 需要超时/TLS/回包策略：`AT+HTTPCFG=1,"timeout",10` 等。HTTPS 先按 [ssl.md](ssl.md) 写证书，再设 `ssl_id` / `ssl_type`。
4. `AT+HTTPREQ=1,"sync"` 看结果行 `status` 与 `"ok"`。
5. 不想占通道：`AT+HTTPFREE="sync",1,"http://<主机>/path"`。
6. 改 URL 后下一次 `HTTPREQ` 才会用新值；正在飞的请求不会被改配置打断。
7. 连续上传：按 [7.4](#7-4-chunk-upload) 选择定长或未知长度，等待 `>` 再输入数据，并检查最终五字段结果和 `OK` / `ERROR`。

---

## 10. AT+HTTPCONN 与通道连接保持 {#10-athttpconn}

沿用已有 `HTTPURL` 设置 URL、方法和请求头；通道号仍是 1～5。旧通道默认 `keep_alive=0`，仍是一请求一连接。

### 10.1 测试和设置

```lua
AT+HTTPCONN=?
AT+HTTPCONN=<id>,"open"
AT+HTTPCONN=<id>,"status"
AT+HTTPCONN=<id>,"close"
```

没有 `AT+HTTPCONN?` 或 `<id>?` 查询形态；查询状态使用 `"status"` 操作。

```lua
AT+HTTPURL=1,1,1,"","http://10.0.0.8"
AT+HTTPCFG=1,"keep_alive",1
AT+HTTPCFG=1,"idle_timeout",60
AT+HTTPCONN=1,"open"
AT+HTTPREQ=1,"async","/device/info"
AT+HTTPREQ=1,"async","/device/status"
AT+HTTPCONN=1,"status"
AT+HTTPCONN=1,"close"
```

`keep_alive` 默认 0；`idle_timeout` 默认 60，范围 1～3600 秒。
无需显式 `open`，第一次 `HTTPREQ` 也可建立连接；`open` 要求通道已启用并开启 keep_alive。
`close` 释放当前运行态会话，保留配置，下一次 `HTTPREQ` 可自动建立新会话。
配置的 origin、PDP、TLS 或证书内容变化时，下次请求更换会话。
`sync` 仍是收完再输出，`async` 仍是阻塞执行期间分段输出，原结果格式保持兼容。
`HTTPCFG=<id>?` 查询会包含两个新增字段；配置导入支持 `keep_alive`、`idle_timeout_s`。
持久化配置升级为版本 5，版本 4 的 URL、请求头、TLS、路由和超时会迁移，长连接默认关闭。

### 10.2 应答和字段

连接管理结果格式为：

```lua
+HTTPCONN: <id>,<ret>,<connected>,<busy>,<connection_seq>,<completed_requests>,<last_error>,<reused>
```

随后返回 `OK` 或 `ERROR`。`ret=0` 成功，非零表示当前管理操作失败。连接未创建时状态字段为 0。

| 字段 | 说明 |
| --- | --- |
| `connected` | 本地已知连接状态，不保证远端此刻仍在线 |
| `busy` | 正被请求或上传占用；忙时只保证该字段，统计字段在事务完成后查询 |
| `connection_seq` | 当前会话内每次新建 TCP/TLS 后递增；销毁并创建会话后重新计数 |
| `completed_requests` | 本会话已完整完成的事务数 |
| `last_error` | 最近一次连接/传输阶段错误码 |
| `reused` | 最近一次事务是否借用了已有连接 |

### 10.3 连接生命周期

同一连接串行完成请求，定长正文收满、chunked 结束块及 trailers 收完，或明确无正文后才可复用。`Content-Length: 0`、HEAD、204、304 不等待远端关闭；100/103 等临时响应继续等待最终响应。

收到 `Connection: close`、HTTP/1.0 未声明 keep-alive、正文依靠 EOF 定界，或发生截断、解析错误、超限、输出中断时不复用。空闲超时只释放 TCP/TLS，下一次请求可重建。断网或 SIM 移除会使旧连接失效；不会发送 HTTP 心跳，也不会自动重放发送或等待响应时失败的请求。

配置通道、自由会话和 Lua 客户端共用会话额度，当前默认 8 个。不足返回 `-3`；空闲超时只释放连接，不归还会话名额，不用的会话应显式 `close`。

配置通道的连接同样按新请求需要重建，不在后台持续重连，也没有独立的 HTTP 断线 URC。发送前发现旧连接失效与请求进行中失败的处理边界，见 [11.5](#115-断线按需重连与-urc)。

## 11. AT+HTTPSESS 自由会话 {#11-athttpsess}

自由会话号为 1～5，与 HTTPURL 配置通道号分开管理；同一数字不会共用连接。已有 `HTTPFREE` / `HTTPUPLOAD` 保留单次连接行为。

### 11.1 测试和操作

```lua
AT+HTTPSESS=?
```

```lua
AT+HTTPSESS=<sid>,"open","<origin>"[,<tls_mode>[,<ssl_id>[,<idle_timeout>]]]
AT+HTTPSESS=<sid>,"req","<mode>",<method>,"<path>"[,"<header>"[,"<action>"[,<TAILRAW>]]]
AT+HTTPSESS=<sid>,"status"
AT+HTTPSESS=<sid>,"close"
```

### 11.2 参数

| 参数 | 取值 / 行为 |
| --- | --- |
| `sid` | 自由会话号 1～5 |
| `origin` | HTTP/HTTPS 服务地址，固定 scheme、host 和有效端口；即使带路径，也不作为后续路径前缀 |
| `tls_mode` | 1 不校验、2 单向、3 双向，默认 1；含义与 `ssl_type` 一致 |
| `ssl_id` | 已有 [SSL 证书组](ssl.md) 1～3，默认 1 |
| `idle_timeout` | 默认 60 秒，范围 1～3600；上次完整事务结束后计时 |
| `mode` | `sync` / `async` / `chunk`，可带 `:max_recv_bps`；仍为阻塞执行 |
| `method` | 1 GET、2 POST、3 PUT、4 DELETE、5 HEAD |
| `path` | 必须以 `/` 开头；不能在这里改主机 |
| `header` | 沿用 HTTPFREE 的 `Key: Value` 格式，可用空字符串跳过 |

- `tls_mode` 和 `ssl_id` 的默认值均为 1。
- `idle_timeout` 默认 60，范围 1～3600 秒。自由会话请求收发超时为 30 秒。
- `path` 必须以 `/` 开头；方法编号沿用 1 GET、2 POST、3 PUT、4 DELETE、5 HEAD。
- `mode` 沿用 `sync`、`async`、`chunk` 和可选的 `:max_recv_bps`。
- 普通正文使用 `"write",<TAILRAW>`；`"stream"` 沿用现有 AT 阻塞收数入口。
- `chunk` 模式仅限 POST/PUT，其 header 后直接接 `total_bytes[,input_timeout_ms]`，不传 action；输入参数范围见 [7.4](#7-4-chunk-upload)。
- chunk 输入的长度规则、提示符、16 KiB 接收缓冲和 DLE 转义与已有 HTTPFREE chunk 模式一致，仅支持物理 UART / USB AT。
- `open` 成功后保存运行态连接；重复 open 成功后替换原会话，打开失败时保留原会话。
- `close` 销毁该自由会话，之后必须重新 open。重启不会恢复运行态连接。

chunk 模式的独立写法如下，header 后直接接长度和输入超时：

```lua
AT+HTTPSESS=<sid>,"req","chunk[:max_recv_bps]",<method>,"<path>"[,"<header>"[,<total_bytes>[,<input_timeout_ms>]]]
```

### 11.3 示例

```lua
AT+HTTPSESS=1,"open","https://api.example.com",2,1,60
AT+HTTPSESS=1,"req","async",1,"/device/info"
AT+HTTPSESS=1,"req","sync",2,"/report","Content-Type: application/json","write",{"v":1}
AT+HTTPSESS=1,"req","chunk",2,"/upload","Content-Type: application/octet-stream",6,30000
```

### 11.4 应答和错误

普通请求和上传沿用 HTTPFREE 的完整 HTTP 响应输出逻辑。响应体为解码后的正文，原有正文输出方式保持一致。
管理操作返回与 [HTTPCONN](#102-应答和字段) 相同的字段，前缀为 `+HTTPSESS`。未打开会话不能直接请求；`close` 后需重新 `open`。
普通请求最终结果为：

```lua
+HTTPSESS: <sid>,"done",<http_status>,<error>,"<message>",<connection_seq>,<reused>,<connected>
```

chunk 上传在以上字段后追加 `<sent_bytes>,<response_bytes>`。
请求完成返回 `OK`，传输、输入或状态错误返回 `ERROR`。
普通请求 HTTP 4xx/5xx 与旧接口一样保留为正常 HTTP 响应；上传仍要求最终 HTTP 2xx。

自由会话使用底层负数错误码，连接/收发/解析等见 [7.5](#7-5-upload-errors)，另外：

| 码 | 含义 |
| --- | --- |
| `-3` | 内存或会话额度不足，关闭不用的会话再试 |
| `-17` | 会话正被请求或上传占用 |
| `-18` | 底层请求 origin 与会话不一致；HTTPSESS 的 path 参数本身不允许更换主机 |

管理行第二字段是数字 `ret`，请求完成行第二字段是 `"done"`，两种布局需分开解析。预连接后第一次请求也可以 `reused=1`。参数错误仍按 [1.3](#13-成功与失败) 的 reason 格式返回。

Lua 的客户端对象见 [http.client](../../api/network/http.md#6-11-client)。

### 11.5 断线、按需重连与 URC {#115-断线按需重连与-urc}

自由会话对象与底层 TCP/TLS 连接分别管理。`open` 成功后，远端关闭、空闲超时或网络变化会使底层连接失效，但自由会话对象仍保留。只要没有执行 `close` 或重启，后续可以继续对同一 `sid` 发 `req`，无需重新 `open`。

重连由**新请求触发**，空闲时不在后台持续尝试连接：

| 情况 | 本次处理 | 后续请求 |
| --- | --- | --- |
| 新请求发送前已发现旧连接失效，或连接已因空闲超时释放 | 尝试新建 TCP/TLS，建连成功后继续本次请求；建连失败则返回错误 | 会话保留，下次 `req` 可再次尝试建连 |
| 发送或接收过程中才发生/发现断线，或请求超时、解析失败 | 当前请求失败，返回非零错误码；不会自动重新发送这次请求 | 下一次新 `req` 尝试重新建连 |
| 完整收到响应，但服务器声明 `Connection: close` | 保留本次 HTTP 响应结果，释放连接；请求可以正常完成 | 下一次新 `req` 重新建连 |
| 执行 `HTTPSESS=<sid>,"close"` 或设备重启 | 自由会话对象销毁 | 必须重新 `open`，再发 `req` |

失败请求不会自动重放，GET、POST、PUT 及 chunk 上传都遵循这一规则。发送失败或未收到完整响应时，服务器可能已经处理过部分或全部正文，应用需按服务端的幂等、去重或状态查询机制决定是否重试。

**当前没有独立的 HTTP 断线 URC。** 空闲期间远端关闭、本地空闲超时或网络失效，不会主动输出一条 `+HTTPSESS` / `+HTTPCONN` 断线通知。请求进行中检测到断线时，会在该请求的 `"done"` 结果行给出非零错误码并返回 `ERROR`；该结果是命令应答，不是主动 URC。

主机可主动查询：

```lua
AT+HTTPSESS=1,"status"
```

查询会检查本地超时、网络失效标记及 socket 已可检测的关闭状态，但**不会发送 HTTP 心跳或探活请求，也不会自动建连**。`connected=1` 只代表本地已知连接状态；网络静默中断且未收到 FIN/RST 等可检测信号时，状态查询不能立即判断远端是否可达。最终仍以实际请求的发送和响应结果为准。

`last_error` 和 `reused` 描述最近一次连接/事务记录。空闲释放或状态查询发现连接关闭时，这两个字段可能保留原值；`connected=0` 可以同时出现 `last_error=0`、`reused=1`，不能据此判为仍连接。

固定配置通道与自由会话的 `close` 后续行为不同：`HTTPCONN=<id>,"close"` 保留持久化通道配置，通道仍启用且 `keep_alive=1` 时，下一次 `HTTPREQ` 可自动创建新会话；自由会话 `HTTPSESS=<sid>,"close"` 后则必须重新 `open`。两类会话编号相同也不共用连接。

### 11.6 状态判读示例 {#116-状态判读示例}

`HTTPSESS` 管理操作和状态查询的完整字段为：

```lua
+HTTPSESS: <sid>,<ret>,<connected>,<busy>,<connection_seq>,<completed_requests>,<last_error>,<reused>
```

例如：

```lua
+HTTPSESS: 1,0,1,0,1,10,0,1

OK
```

表示自由会话 1，查询成功（`ret=0`），本地连接仍保留（`connected=1`），当前空闲（`busy=0`）；该会话只成功建立过一次 TCP/TLS 连接（`connection_seq=1`），已完整完成 10 次事务，最近一次连接/事务无错误且借用了已有连接。统计只在当前会话对象内有效，重新 `open` 或销毁再创建后会重新计数。

若之后连接因空闲超时释放，查询可能变为 `+HTTPSESS: 1,0,0,0,1,10,0,1`；这里 `connected=0` 表示当前没有保留连接，历史完成次数和最近一次复用记录仍在。

若下一次 GET 成功重建连接并收到 HTTP 200，请求结果示例为：

```lua
+HTTPSESS: 1,"done",200,0,"ok",2,0,1

OK
```

此时 `connection_seq=2` 表示当前会话第二次成功建连，`reused=0` 表示本次使用新连接，`connected=1` 表示完成后连接可保留。随后继续复用成功时序号保持 2、`reused=1`。预连接 `open` 成功后，第一次请求也可直接为 `reused=1`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：HTTPURL / HTTPCFG / HTTPREQ / HTTPFREE 的测试、查询、设置、`resp_at_mode` 静默、请求错误码与示例 |
| 1.0.1 | 2026-09-07 | `route` 改链到 [route.md](route.md) |
| 1.0.2 | 2026-09-19 | 相对链接随目录迁到 `at/manual/` |
| 1.0.3 | 2026-09-19 | 文首链到 [专栏 · HTTP / HTTPS](../topics/http.md) |
| 1.1.0 | 2026-11-09 | 对应固件 1.4.3。新增 FREE chunk 上传、定长/转义结束、响应头与正文、五字段进度结果、负数错误码和 HTTPUPLOAD 兼容入口；同步 UART/USB 响应路由与接收限速写法 |
| 1.2.0 | 2026-11-12 | 当前 SDK 新增 keep_alive、idle_timeout、HTTPCONN 与 HTTPSESS；补齐连接保持、上传复用、状态应答和旧配置迁移 |
| 1.2.1 | 2026-11-13 | 补充现有长连接机制：新请求触发重连、失败请求不重放、无主动断线 URC、状态查询与静默断网边界，以及会话关闭/重启差异和状态报文示例 |
