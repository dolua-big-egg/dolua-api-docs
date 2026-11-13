# http

**文档版本** `1.4.0`

同步 HTTP/HTTPS 客户端。`request` / `get` / `post` 完成一次请求并返回响应，响应体可以进 Lua 字符串，也可以落到 **ublob**、已挂载的 **LittleFS**，或已挂载的 FlashDB。固件 `1.4.3` 起增加 `http.upload`，支持上传对象和取数回调两种 chunked 上传方式。

**上传接口对应固件版本** `1.4.3`。上传参数、返回值、错误处理见 [6.9 Chunked 上传](#6-9-upload)。

**当前 SDK 新增** `http.client()`：保留同一 TCP/TLS 连接，串行执行多次请求或上传。旧的单次接口仍默认关闭连接。见 [6.11 客户端](#6-11-client)。

```lua
local http = require("http")
```

平台预加载模块，无需额外 `.lua` 文件。必须已经能上网（可先 `lp.wait_link`）。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `http.request` / `http.sync`](#6-1-request)
  - [6.2 `http.get`](#6-2-get)
  - [6.3 `http.post`](#6-3-post)
  - [6.4 `http.save.ublob`](#6-4-save-ublob)
  - [6.5 `http.save.lfs`](#6-5-save-lfs)
  - [6.6 `http.save.kv`](#6-6-save-kv)
  - [6.7 `http.save.ts`](#6-7-save-ts)
  - [6.8 `http.encode`](#6-8-encode)
  - [6.9 `http.upload`（固件 1.4.3）](#6-9-upload)
  - [6.10 上传对象方法](#6-10-upload-methods)
  - [6.11 `http.client` 长连接客户端](#6-11-client)
  - [6.12 客户端方法](#6-12-client-methods)
- [7. 请求配置](#7-请求配置)
- [8. 自定义头](#8-自定义头)
- [9. HTTPS](#9-https)
- [10. 下载到文件](#10-下载到文件)
  - [10.1 为什么要落盘](#101-为什么要落盘)
  - [10.2 选哪块盘](#102-选哪块盘)
  - [10.3 落到 ublob（内部）](#103-落到-ublob内部)
  - [10.4 落到 LittleFS（外挂 Flash）](#104-落到-littlefs外挂-flash)
  - [10.5 落到 FlashDB](#105-落到-flashdb)
  - [10.6 落盘后的响应表](#106-落盘后的响应表)
- [11. 返回表](#11-返回表)
- [12. 错误与返回约定](#12-错误与返回约定)
- [13. 资源上限与生命周期](#13-资源上限与生命周期)
- [14. 选型对照](#14-选型对照)
- [15. 完整示例](#15-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`http` 提供同步 HTTP(S) 请求和上传；单次接口用完关闭连接，客户端对象可以保留连接供下一次请求复用。

1. **必须已经能上网。** 没网会 DNS/连接失败。demo 都是先 `lp.wait_link`。
2. `http.request(opts)` 是通用入口。`http.sync` 与它是同一个函数。
3. `http.get` / `http.post` 只是帮你填 `url`、`method`（post 再填 body），其余仍走 `request`。
4. 不带 `save`：整份 body 变成 Lua 字符串。带 `save`：body 写入指定存储，`resp.body` 为空串，`body_len` 仍有效。
5. `http.encode` 只做百分号编码，不联网、不改你正在发的请求。查询值里的方括号要自己编完再拼进 `url`。
6. 固件 `1.4.3` 起，`http.upload(opts)` 返回上传对象；`http.upload(opts, producer)` 按需取数并完成上传，支持 POST/PUT。
7. `http.client(opts)` 建立固定服务地址的客户端，`c:get/post/request/upload` 共用它的连接。

请求不会在后台自动执行，失败的请求也不会自动重放。客户端保留的是 TCP/TLS 连接；空闲超时会释放连接，下一次新请求按需重建。没有 HTTP 心跳或自动补发业务数据。

不要在 UART / MQTT / TCP 回调里调用：一次请求会占住整条 Lua 引擎线程。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  request / get / post  （可选 save）                     │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  http 模块                                                │
│  · 填方法、头、超时、TLS                                  │
│  · 同步等到收完                                          │
│  · 有 save：把 body 写入目标后再返回                      │
└────────────┬───────────────┬───────────────┬────────────┘
             │               │               │
             ▼               ▼               ▼
        Lua 字符串        内部 ublob     已挂载 LittleFS /
        （默认）          （小文件）     已挂载 FlashDB
```

| 路径 | 调用当场做什么 | 是否让出协程 | body 去哪 |
| --- | --- | --- | --- |
| 无 `save` | 发请求、收完整响应 | **否** | `resp.body` 字符串 |
| `save` → ublob | 同上，再覆盖写入 ublob | **否** | 内部二进制文件；`body=""` |
| `save` → lfs | 同上，再写入已挂载分区 | **否** | 外挂 Flash 上的路径 |
| `save` → kv / ts | 同上，再写入已挂载库 | **否** | FlashDB 键 / 一条时序 |
| `upload(opts)` | 建连接、发请求头，随后用对象写入并结束 | **否**，每个网络操作同步执行 | `finish()` 返回响应表 |
| `upload(opts, producer)` | 回调取数、发送 chunk、结束并读取响应 | **否** | 调用返回响应表 |
| `client(opts)` | 建立 TCP/TLS 连接，返回客户端 | **否** | 暂无正文 |
| `c:request/get/post/upload` | 借用客户端连接，完成本次请求或上传 | **否** | 响应表或上传对象 |

和 TCP/MQTT 不同：没有独立工作线程替你收包。整次调用占着当前协程。

---

## 3. 阻塞语义

`request` / `get` / `post` **不是** `rt.delay` 那种让出：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 默认发送/接收超时各 30 秒；再加大文件，整机业务会卡住

失败不会自动重试。HTTPS 握手、大 body、慢站点（如 httpbin）都会把这次调用拉长。

固件 `1.4.3` 的 `upload`、`write`、`poll`、`finish`、`send` 同样同步执行，占用当前 Lua VM 线程。取数回调需要及时返回。需要事件供数时，可以保存上传对象，由任务协程消费事件数据并逐次 `write()`，数据结束时 `finish()`；串口、MQTT 等快捷回调先转交数据。

---

## 4. 常量与枚举

### 4.1 方法字符串

| 符号 | 值 | 用在 |
| --- | --- | --- |
| `http.METHOD_GET` | `"GET"` | `opts.method` |
| `http.METHOD_POST` | `"POST"` | 同上 |
| `http.METHOD_PUT` | `"PUT"` | 同上 |
| `http.METHOD_DELETE` | `"DELETE"` | 同上 |
| `http.METHOD_HEAD` | `"HEAD"` | 同上 |

也可以直接写 `"GET"` 这类字符串。未导出的方法名不要当可用档位。

不写 `method`、也没有 body：按 GET。不写 `method`、但带了 `body` / `data` / `post_data`：按 POST。

### 4.2 TLS 模式（`opts.tls_mode`）

| 符号 | 值 | 含义 | 还要带什么 |
| --- | --- | --- | --- |
| `http.TLS_INSECURE` | `1` | 加密，不校验证书 | 不用 CA |
| `http.TLS_SERVER_AUTH` | `2` | 单向认证 | 必须 `ca_cert` |
| `http.TLS_MUTUAL_AUTH` | `3` | 双向认证 | `ca_cert` + `client_cert` + `client_key` |

其它整数未导出。`https://` 必须设 `tls_mode`，否则握手按「不校验」以外的路径可能直接失败。demo 明文站点也一律带上 `TLS_INSECURE`。

### 4.3 URL 编码等级

`http.encode` 的第二参。省略时是 `ENCODE_COMPONENT`。

| 符号 | 值 | 原样保留 | 空格 | `[` `]` |
| --- | --- | --- | --- | --- |
| `http.ENCODE_COMPONENT` | `0` | `A-Z` `a-z` `0-9` `-` `.` `_` `~` | `%20` | `%5B` `%5D` |
| `http.ENCODE_FORM` | `1` | 与 `ENCODE_COMPONENT` 相同 | `+` | `%5B` `%5D` |
| `http.ENCODE_PATH` | `2` | `ENCODE_COMPONENT` 的集合，再加 `/` | `%20` | `%5B` `%5D` |
| `http.ENCODE_URI` | `3` | `ENCODE_COMPONENT` 的集合，再加 `:` `/` `?` `#` `@` `!` `$` `&` `'` `(` `)` `*` `+` `,` `;` `=` | `%20` | `%5B` `%5D` |

其余字节一律写成 `%` 加大写十六进制。四个等级都会编码方括号。

| 等级 | 用在 |
| --- | --- |
| `ENCODE_COMPONENT` | 查询参数的一个值，或路径里的一段 |
| `ENCODE_FORM` | `application/x-www-form-urlencoded` 的一个值 |
| `ENCODE_PATH` | 已经带 `/` 的路径，斜杠要留下来当分隔符 |
| `ENCODE_URI` | 已经拼好的整段地址，方案和 `?` `&` `=` 不要被编掉 |

其它整数没有导出。传进去会抛错，见 [6.8](#6-8-encode)。

错误码 **没有** 挂到模块表。失败时用第二返回值的整数和第三返回值的英文短句，见 [第 12 节](#12-错误与返回约定)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `opts` | table | 请求配置；`url` 必填 |
| `url` | string | 完整 `http://` 或 `https://` |
| `method` | string | `METHOD_*` 或同等字面量 |
| `body` / `data` / `post_data` | string | 请求体，三选一 |
| `headers` | table | 见第 8 节 |
| `save` | string 或 table | 落盘目标，见第 10 节 |
| `tls_mode` | integer | `1` / `2` / `3` |
| `level` | integer | `http.encode` 的第二参：`0`～`3`，见 [4.3](#43-url-编码等级) |
| `tls_sni` / `tls_ignore_time` / `require_content_length` | boolean | **走 `toboolean`：数字 `0` 为真**。请用 `true`/`false` |
| `resp` | table | 成功响应，见第 11 节 |

超时、长度、PDP 走 **integer**。负的无符号项收成 `0`；`u8` 超过 255 收成 `255`。

---

## 6. 模块函数

模块表：`request`、`sync`、`get`、`post`、`upload`、`client`、`encode`，以及嵌套表 `http.save`。

---

### 6.1 `http.request(opts)` / `http.sync(opts)` {#6-1-request}

通用入口。`sync` 与 `request` 行为完全相同。

第一参必须是 table，且含 `url`。成功返回响应表；失败 `nil, err_code, err_msg`。

**调用模式**

```lua
http.request({ url = url })
```

```lua
http.sync({ url = url })
```

```lua
http.request({
    url = url,
    method = http.METHOD_GET,
    tls_mode = http.TLS_INSECURE,
})
```

```lua
http.request({
    url = url,
    method = http.METHOD_POST,
    body = body,
    content_type = "text/plain",
    tls_mode = http.TLS_INSECURE,
})
```

```lua
http.request({
    url = url,
    save = "demo.bin",
    tls_mode = http.TLS_INSECURE,
})
```

`url` 缺失或不是能转成字符串的值：抛类型错。`opts` 不是 table：抛类型错。

---

### 6.2 `http.get(url [, arg2 [, arg3]])` {#6-2-get}

强制 `method=GET`。`url` 用位置参数。其余 opts 与 `request` 相同。

**调用模式**

```lua
http.get(url)
```

```lua
http.get(url, opts)
```

```lua
http.get(url, filename)
```

```lua
http.get(url, filename, opts)
```

- 第二参是 **table**：当作 `opts`（可含 `save`、`tls_mode` 等）。
- 第二参是 **非空字符串**：当作 ublob 文件名（内部写成 `opts.save`）。若 `opts` 里已经有 `save`，**不覆盖**。
- 第二参既不是字符串也不是 table 也不是 `nil`：抛 `"expected filename string or options table"`。

空字符串文件名不会开启落盘。

---

### 6.3 `http.post(url, body [, opts])` {#6-3-post}

强制 `method=POST`。`url`、`body` 用位置参数；位置上的 body 会盖掉 `opts.body`。

**调用模式**

```lua
http.post(url, body)
```

```lua
http.post(url, body, opts)
```

`opts` 若出现必须是 table。`content_type`、`tls_mode`、`save` 都放 opts 里。`content_type` 不写则底层 **不会**自动补。

---

### 6.4 `http.save.ublob(name)` {#6-4-save-ublob}

构造落盘描述表 `{ ublob = name }`，本身不下载。给 `opts.save` 用。

```lua
http.save.ublob("demo.bin")
```

---

### 6.5 `http.save.lfs(fs, path)` {#6-5-save-lfs}

构造 `{ lfs = fs, path = path }`。`fs` 必须是 **已经 `lfs.mount` 成功** 的对象，否则 **抛错**（`"expected lfs.fs userdata"`）。固件未开 LittleFS 时调用会抛 `"lfs save unsupported"`。

```lua
http.save.lfs(fs, "/demo.bin")
```

---

### 6.6 `http.save.kv(db, key)` {#6-6-save-kv}

构造 `{ kv = db, key = key }`。`db` 必须是已挂载的 FlashDB KV 对象，否则抛错。

```lua
http.save.kv(kv, "fw.bin")
```

---

### 6.7 `http.save.ts(db)` {#6-7-save-ts}

构造 `{ ts = db }`。`db` 必须是已挂载的 FlashDB 时序对象。写入一条记录，没有文件名。

```lua
http.save.ts(ts)
```

---

### 6.8 `http.encode(text [, level])` {#6-8-encode}

百分号编码。不联网，也不改 `request` / `get` / `post` 里的 `url`。成功返回一个新字符串。

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `text` | string | 是 | | 按字节编码，可以含 `0` 字节。空串得到空串 |
| `level` | integer | 否 | `http.ENCODE_COMPONENT`（`0`） | 只能是 [4.3](#43-url-编码等级) 的四个值。`nil` 用默认 |

**调用模式**

```lua
http.encode(text)
```

```lua
http.encode(text, http.ENCODE_COMPONENT)
```

```lua
http.encode(text, http.ENCODE_FORM)
```

```lua
http.encode(text, http.ENCODE_PATH)
```

```lua
http.encode(text, http.ENCODE_URI)
```

```lua
local ver = "NT26-PRO-RTU-D1.3.7[A]"
local url = "https://5giot.cn/prod-api/openDtuConfig/getConfigParams?ware_version=" .. http.encode(ver)
```

```lua
http.encode("a b", http.ENCODE_FORM)
-- "a+b"
```

```lua
http.encode("/a b/c", http.ENCODE_PATH)
-- "/a%20b/c"
```

`http.encode("NT26-PRO-RTU-D1.3.7[A]")` 得到 `NT26-PRO-RTU-D1.3.7%5BA%5D`。

失败 **抛错**，没有 `nil, err`：

| 文案 | 可能原因 |
| --- | --- |
| `bad argument #1 ...` | `text` 不是字符串 |
| `invalid encode level, expect ENCODE_COMPONENT/ENCODE_FORM/ENCODE_PATH/ENCODE_URI` | 第二参不是 `0`～`3`，也不是 `nil` |
| `encode input too large` | 原文长到编码结果无法放进一个字符串 |
| `encode failed` | 编码缓冲不足 |

---

### 6.9 `http.upload(opts [, producer])`（固件 1.4.3） {#6-9-upload}

固件 **1.4.3** 新增。使用 HTTP/1.1 `Transfer-Encoding: chunked` 上传，方法支持 `POST` 和 `PUT`，默认 `POST`。适用于文件逐块读取、持续生成数据以及开始时未知总长度的上传。服务器需支持 chunked 请求体。

`http.upload(opts)` 建立连接并发送请求头，成功返回上传对象。传入第二参 `producer` 时，会循环取数并完成整个上传，成功返回响应表。两种形式失败都返回 `nil, err_code, err_msg, info`。

SDK 为非空写入生成 chunk 帧，结束时发送 `0\r\n\r\n`。指定总长度也使用 chunked 请求体。完成前会等待完整的最终 HTTP 响应，最终状态为 **2xx** 才返回成功。遇到断线、错误或提前拒绝时关闭连接，返回错误及已获得的 HTTP 状态和发送进度。

| `opts` 字段 | 约定 |
| --- | --- |
| `url` | 必填，完整 HTTP/HTTPS URL |
| `method` | `"POST"` 或 `"PUT"`，默认 `"POST"` |
| `total_bytes` | 省略表示未知长度；显式 0 表示空上传；范围 0～4294967295 |
| `content_type` | 默认 `application/octet-stream` |
| `headers` | 沿用 [自定义头](#8-自定义头) 的格式，最多 32 对 |
| `timeout_s` / `timeout_r` | 发送/响应接收超时，单位秒；0 或省略使用 30，最大 3600 |
| `connect_timeout_s` | 0 或省略沿用底层连接默认值 |
| `max_response_size` | 响应正文内存上限；0 或省略使用 16 KiB，最大 1 MiB |
| `expect_wait_ms` | 等待 `100 Continue` 的时间；0 或省略使用 1000 ms，最大 30000 ms |
| `max_recv_bps` | 响应正文接收限速，单位字节/秒；0 不限速 |
| Basic Auth、`pdp_id`、TLS 字段 | 沿用请求配置中的同名字段 |

`Host`、`Content-Length`、`Transfer-Encoding`、`Connection`、`Expect` 由上传实现管理，自定义这些头会返回参数错误。请求头中带 `Expect: 100-continue`；服务器在等待窗口内未回复 100 时，客户端继续上传。

#### 手动写入

在已联网的任务中执行下面代码。手动模式通过 `finish()` 完成事务，指定长度时，写入超量或不足量就结束均返回 `-32`。

~~~lua
local http = require("http")

local u, code, message, info = http.upload({
    url = "https://httpbin.org/post",
    method = "POST",
    content_type = "text/plain",
    total_bytes = 6,
    tls_mode = http.TLS_INSECURE,
})
if not u then
    return nil, code, message, info
end

for _, data in ipairs({"abc", "def"}) do
    local written
    written, code, message, info = u:write(data)
    if not written then
        u:close()
        return nil, code, message, info
    end
end

local response
response, code, message, info = u:finish()
u:close()
return response, code, message, info
~~~

#### 取数回调

`http.upload(opts, producer)` 或 `u:send(producer)` 在当前 Lua VM 中同步调用 `producer(event)`。回调每次填充一块数据后返回，网络发送完成后再请求下一块。

| 回调参数 | 含义 |
| --- | --- |
| `event.max_bytes` | 本次最多可返回的字节数，最大 2048 |
| `event.sent_bytes` | 已完整发送的 chunk 正文累计字节数 |
| `event.remaining` | 仅指定 `total_bytes` 时有，表示剩余字节数 |

回调返回 1～`max_bytes` 字节的字符串。返回 `nil` 表示数据结束，返回 `false` 表示取消。空字符串、超长字符串、其他类型或回调抛错返回 `-33`。指定总长度时，达到长度自动结束；提前返回 `nil` 会触发长度不足错误。未知长度通过回调返回 `nil` 结束。

~~~lua
local http = require("http")
local bytes = "abc\0def"
local offset = 1

local response, code, message, info = http.upload({
    url = "https://httpbin.org/post",
    content_type = "application/octet-stream",
    total_bytes = #bytes,
    tls_mode = http.TLS_INSECURE,
}, function(event)
    if offset > #bytes then
        return nil
    end
    local data = bytes:sub(offset, offset + event.max_bytes - 1)
    offset = offset + #data
    return data
end)

return response, code, message, info
~~~

删除上述示例的 `total_bytes` 即为未知长度上传，数据耗尽时返回 `nil` 结束。取数回调需要及时返回，可执行同步读取来填充数据，不能在回调中执行需要 yield 的等待。回调运行期间，该上传对象的写入、轮询、发送、结束和关闭操作会返回 `-30`。回调异常会作为整个 `upload` / `send` 的错误返回，回调模式在结束、失败或取消时释放连接。

### 6.10 上传对象方法 {#6-10-upload-methods}

**对应固件版本 1.4.3。**

| 调用 | 成功返回值 | 用途 |
| --- | --- | --- |
| `u:write(data)` | `本次字节数, 累计发送字节数` | 发送二进制字符串，空字符串返回 0 字节 |
| `u:poll([wait_ms])` | `true, info` | 检查断线和服务器提前响应；等待 0～1000 ms，默认 0 |
| `u:status()` | `info` | 查询本地状态 |
| `u:finish()` | 响应表 | 发送结束 chunk，等待完整最终响应；单次上传关闭连接，客户端上传归还可复用连接 |
| `u:send(producer)` | 响应表 | 按回调供数并完成上传，连接处理与 `finish()` 相同 |
| `u:close()` | `true` | 清理上传对象；上传未完成时丢弃连接，可重复调用，支持 GC 与 Lua `<close>` |

`write` / `poll` / `finish` / `send` 失败返回 `nil, err_code, err_msg, info`。参数类型错误遵循 Lua 参数异常约定。`write` 成功说明完整 chunk 已交给本地传输层；业务成功以 `finish` 收到完整 2xx 响应为准。

返回的 `info` 包含 `sent_bytes`、可选的 `total_bytes`、`error_code` 和 `state`（`open` / `finished` / `closed` / `error`）。已经解析到响应时还包含响应表字段，例如 `status_code`、`header`、`body`。错误发生在 chunk 中途时，服务器可能已经收到该块的部分数据，`sent_bytes` 仅累计完整发送的块。

`finish()` 的成功返回表包含响应内容和发送进度。连接释放后，`status()` 保留本地状态和发送计数。手动模式发生错误时调用 `close()`；有空闲供数间隔时可调用 `poll()` 检查连接。

上传新增错误码如下。连接、DNS、TLS、内存和解析错误沿用 [第 12 节](#12-错误与返回约定)。

| 码 | `err_msg` | 含义 |
| --- | --- | --- |
| `-30` | `upload state` | 对象已关闭、已结束或在取数回调中重入 |
| `-31` | `http rejected` | 最终 HTTP 状态非 2xx，状态码在 `info.status_code` |
| `-32` | `upload length mismatch` | 指定的上传长度与实际数据不符 |
| `-33` | `upload producer failed` | 取数回调返回值不符合约定或抛错；抛错时返回信息带异常文本 |
| `-37` | `upload cancelled` | 取数回调返回 `false` |
| `-38` | `early final response` | 结束帧发送完成前收到 2xx 响应 |

AT 的连续串口输入使用 `HTTPFREE="chunk"`，参数和结束序列见 [AT HTTP 手册](../../at/manual/http.md#7-4-chunk-upload)。

---

### 6.11 `http.client(opts)` 长连接客户端 {#6-11-client}

保留同一 TCP 连接和完整 TLS 上下文，减少重复建连与握手。`http.client(opts)` 会立即连接，成功返回客户端，失败返回 `nil, err_code, err_msg`。

```lua
local http = require("http")
local c, err, msg = http.client {
    origin = "https://api.example.com",
    idle_timeout = 60,
    timeout_s = 30,
    timeout_r = 30,
    tls_mode = http.TLS_SERVER_AUTH,
    ca_cert = CA_PEM,
}
if not c then return nil, err, msg end

local first = assert(c:get("/device/info"))
local second = assert(c:post("/report", '{"v":1}', {
    content_type = "application/json",
}))
print(second.connection_seq, second.reused, second.reusable)
c:close()
```

| opts 字段 | 默认 / 范围 | 说明 |
| --- | --- | --- |
| `origin` | 必填；`url` 为别名 | HTTP/HTTPS 服务地址，只取 scheme、host、port；即使含路径，也不会作为后续请求的路径前缀 |
| `idle_timeout` | 省略或 0 使用 60 秒，最大 86400 | 上次事务结束后的连接空闲时长；超时释放 TCP/TLS，客户端对象仍可使用 |
| `timeout_s` / `timeout_r` | 省略或 0 使用 30 秒，最大 3600 | 后续请求的默认发送 / 接收超时，可按次覆盖 |
| `connect_timeout_s` | 省略或 0 沿用底层默认值，最大 3600 秒 | 建立连接时使用；连接超时由客户端配置持有 |
| `pdp_id` | 0～255，默认 0 | 固定 PDP 上下文 |
| `tls_mode`、证书、SNI、套件等 | 沿用 [HTTPS](#9-https) 字段 | 固定连接身份；客户端复制持有证书内容 |
| 请求头、Basic Auth、限速、响应上限、保存选项 | 沿用各自请求字段 | 作为后续请求的默认值，按次 opts 可以覆盖 |

构造参数会保存为默认值，之后修改原配置表中的字符串字段不会改变客户端的连接身份。按次 opts 不允许修改 `origin`、`pdp_id` 或任何 TLS/证书字段；需要更换时创建新客户端。请求头等嵌套表仍是普通 Lua 表，业务上按需管理。

同一客户端固定 origin（协议、主机、有效端口）；可以请求不同路径。同一时间只能有一个请求或上传租用它，重入返回 `-17`。这里是串行复用，不使用 HTTP pipelining。

### 6.12 客户端方法 {#6-12-client-methods}

| 方法 | 成功 | 说明 |
| --- | --- | --- |
| `c:request(opts)` | 响应表 | 使用 `path` 或相同 origin 的完整 `url`，默认 `/`；支持现有请求、保存选项 |
| `c:get(path [, opts])` | 响应表 | GET；保存文件请在 opts 中设置 `save` / `save_file` 等 |
| `c:post(path, body [, opts])` | 响应表 | POST；body 为二进制字符串 |
| `c:upload(opts [, producer])` | 上传对象或响应表 | 使用 `path`，其余上传选项和返回值沿用 [6.9](#6-9-upload) |
| `c:status()` | 本地状态表 | 字段见下表；不发送 HTTP 探活请求 |
| `c:close()` | `true` | 销毁客户端，可重复调用；支持 GC 与 Lua `<close>` |

请求失败返回 `nil, err_code, err_msg`；上传失败沿用第四返回值 `info`。不同 origin 返回 `-18`，原连接仍可继续使用。类型错误、修改固定连接选项、使用已关闭客户端时按 Lua 参数异常处理。

```lua
local c <close> = assert(http.client { origin = "http://example.com" })
local resp = assert(c:request { path = "/info", headers = { Accept = "application/json" } })
local u = assert(c:upload { path = "/upload", total_bytes = 6 })
assert(u:write("ab\0def"))
local result = assert(u:finish())
u:close()
-- 上传结束后，c 仍可继续请求。
assert(c:get("/status"))
```

`c:upload` 从创建到 `finish()` / `close()` 期间独占客户端。此时再发请求、创建另一上传或调用 `c:close()`，返回 `-17`。上传对象持有父客户端，父变量置 nil 或触发 GC 不会提前释放连接。成功 `finish()` 归还满足复用条件的连接；取消、长度不足、提前响应或中途网络错误会丢弃连接，下一次新请求可重建。

普通请求和上传的成功响应增加 [第 11 节](#11-返回表) 的连接字段。`c:status()` 返回：

| 字段 | 含义 |
| --- | --- |
| `closed` | 客户端已被 `close()` 销毁 |
| `connected` | 本地已知连接状态，不能保证远端此刻仍在线 |
| `busy` | 连接正在被请求或上传占用；忙时只保证该字段，统计字段请在事务完成后查询 |
| `reused` | 最近一次事务是否借用了已有连接 |
| `connection_seq` | 当前客户端内每次新建 TCP/TLS 后递增，创建新客户端重新计数 |
| `completed_requests` | 已完整完成的请求数，含完成的上传 |
| `last_error` | 最近一次连接/传输阶段错误码 |

空闲超时只释放连接，不销毁客户端。服务器空闲关闭后，发送前检测到关闭时会先重建；发送或等待响应期间失败的请求不自动重放。普通请求的完整 HTTP 4xx/5xx 仍返回响应表，上传仍要求最终 HTTP 2xx。

AT 侧连接保持与自由会话见 [HTTPCONN](../../at/manual/http.md#10-athttpconn) 和 [HTTPSESS](../../at/manual/http.md#11-athttpsess)。

---

## 7. 请求配置

`opts` 必填只有 `url`。没写的项走协议层默认。

| key | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `url` | string | 必填 | 完整 URL |
| `method` | string | 无 body→GET；有 body→POST | 见第 4.1 节 |
| `body` / `data` / `post_data` | string | 无 | 请求体，三选一，先认 `body` |
| `content_type` | string | 不自动补 | POST/PUT 的 Content-Type |
| `headers` | table | 无 | 最多 32 对，见第 8 节 |
| `basic_auth_user` + `basic_auth_password` | string | 无 | **成对**才生效 |
| `timeout_s` | integer | `30`（写 `0` 也由协议层补默认） | 发送超时（秒） |
| `timeout_r` | integer | `30` | 接收超时（秒）；`timeout_s` / `timeout_r` 最大 3600 秒 |
| `pdp_id` | integer | `0` | PDP 上下文 |
| `max_response_size` | integer | `0` = 不限制 | 响应体上限（字节），超出 `-15` |
| `require_content_length` | boolean | `false` | `true` 时没有 Content-Length 则 `-14`。数字 `0` 会被当成真 |
| `save` / `save_file` / `filename` | 见第 10 节 | 无 | 落盘。优先 `save` |
| `tls_mode` 等 | 见第 9 节 | | HTTPS |

`ca_cert_len` / `client_cert_len` / `client_key_len` 可不写：`<=0` 时按 PEM 字符串处理。

也可用 `tls_seclevel`（`0` 不校验 / `1` 单向 / `2` 双向）代替 `tls_mode`。写了 `tls_mode` 则以它为准，并按模式检查证书是否齐全。

---

## 8. 自定义头

`opts.headers` 三种写法等价，最多 **32** 对。空 key 非法。值可以是 string 或 number（会转成字符串）。

```lua
{ ["User-Agent"] = "doiot", ["Accept"] = "*/*" }
```

```lua
{ "User-Agent", "doiot", "Accept", "*/*" }
```

```lua
{ { "User-Agent", "doiot" }, { "Accept", "*/*" } }
```

`Host`、`Content-Length`、`Transfer-Encoding`、`Connection`、`Expect` 由 HTTP 实现管理，自定义这些头返回 `-1`；普通头仍可按次设置。

扁平数组长度必须为偶数。非法头：`nil, -1, "invalid headers"`。内存不够：`nil, -3, "out of memory"`。

---

## 9. HTTPS

`https://` 必须配 TLS。常用：

```lua
http.get(url, { tls_mode = http.TLS_INSECURE })
```

```lua
http.get(url, {
    tls_mode = http.TLS_SERVER_AUTH,
    ca_cert = pem_text,
})
```

```lua
http.get(url, {
    tls_mode = http.TLS_MUTUAL_AUTH,
    ca_cert = ca_pem,
    client_cert = cert_pem,
    client_key = key_pem,
})
```

| 项 | 默认 | 说明 |
| --- | --- | --- |
| `tls_sni` | `true` | 多域名证书站点需要开。数字 `0` 为真，要关请传 `false` |
| `tls_ignore_time` | `true` | 忽略证书有效期（设备没校时也能连）。要连有效期一起验：`false` |
| `tls_ciphersuite` | `0xFFFF` | 默认套件 |

单向/双向缺证书：失败，`err_msg` 为 `"tls configure failed"`。换站点通常要换根 CA，不能拿 A 站点的根去验 B 站点。

示例见 [examples/nt26/network/http/https](../../../../../examples/nt26/network/http/https)。

---

## 10. 下载到文件

这一节单独讲：HTTP 不只是把 JSON 收进 `resp.body`。加上 `save` 后，响应体写入存储，**整包不进 Lua 字符串**，适合固件、资源包、大页面。

对应 demo：

| 路径 | demo |
| --- | --- |
| 内存字符串 | [examples/nt26/network/http/http_request](../../../../../examples/nt26/network/http/http_request)、[examples/nt26/network/http/https](../../../../../examples/nt26/network/http/https) |
| 内部 ublob | [examples/nt26/network/http/http_file_ublob](../../../../../examples/nt26/network/http/http_file_ublob) |
| 外挂 LittleFS | [examples/nt26/network/http/http_file_lfs](../../../../../examples/nt26/network/http/http_file_lfs) |

### 10.1 为什么要落盘

| | 不带 `save` | 带 `save` |
| --- | --- | --- |
| `resp.body` | 完整正文 | 空串 `""` |
| `resp.body_len` | 长度 | 仍是实际长度 |
| Lua 堆 | 文件有多大就占多大 | 只留下状态码、头、`saved` 小表 |
| 读回数据 | 直接用 `body` | 按目标用 `ublob.open` / `fs:open` 等 **按块读** |

落盘是 **覆盖写**。HTTP 仍会先把整份 body 收到 RAM，再一次性写入目标——不是边收边刷 Flash。`max_response_size` 仍然要够用。外挂盘适合「Lua 堆装不下当字符串、但 RAM 瞬时还能扛这次下载」的包；更大请自己用 Range 分片下。

解析 `save` 失败时 **不会发起下载**。

### 10.2 选哪块盘

内部有两套小文件系统，**共用同一块配额**（`ublob.usage()` / `ufs.usage()` 的 `used`/`limit`，可写上限大约几十 KB 量级，以设备读到的 `limit` 为准）：

| 模块 | HTTP 能否直接 `save` | 存什么 |
| --- | --- | --- |
| `ublob` | **能**。这是内部落盘的正路 | 原始二进制 |
| `ufs` | **不能**。没有 `http.save.ufs` | 可序列化 Lua 值（配置表等） |

要把 HTTP 正文当成 `ufs` 里的配置，只能先下到内存或 ublob，再 `ufs.write`。不要把几百 KB、数 MB 往内部盘塞。

外挂 SPI Flash：

| 目标 | 前提 | 容量 |
| --- | --- | --- |
| LittleFS | **必须先 `lfs.mount` 成功**，把返回的 `fs` 交给 `save` | 分区大小（demo 常用整片） |
| FlashDB KV / TS | **必须先挂载**对应库 | 分区大小 |

未挂载就 `http.save.lfs(fs, path)`：**抛错**。未挂载却把坏对象塞进 `opts.save`：请求失败 `-26`（`"save target type invalid"`），不会下载。

先用 SPI / sfud demo 把 Flash 通讯跑通，再测 HTTP 落盘。SPI0 默认脚常和 UART2 冲突，外挂盘工程通常要改 `rtu_config.cfg` 的 UART2 `pin_map`。

### 10.3 落到 ublob（内部）

适合证书、小配置、一小段固件。和 `ufs` 抢配额。超配额失败，码 **-21**（`"save quota exceeded"`）。

文件名最长 **95** 字节（不含结尾 0），不能为空。body 长度为 0 时：删掉同名旧文件（没有也算成功）——内部不允许 0 长 ublob。

**调用模式**（四条等价，都是覆盖写）

```lua
http.get(url, "demo.bin", opts)
```

```lua
http.request({ url = url, save = "demo.bin" })
```

```lua
http.request({ url = url, save = http.save.ublob("demo.bin") })
```

```lua
http.request({ url = url, save = { ublob = "demo.bin" } })
```

兼容旧键（仍映射 ublob；仅当没有 `save` 时生效）：

```lua
http.request({ url = url, save_file = "demo.bin" })
```

```lua
http.request({ url = url, filename = "demo.bin" })
```

读回不要整包解进 Lua。`ublob.open` 开 view，按块 `read`，用完 `close`。同时只能开 1 个 view。示例：`http_file_ublob`。

下载前可 `ublob.remove(name)` 清同名旧文件。

### 10.4 落到 LittleFS（外挂 Flash）

适合几百 KB～数 MB。路径是 LittleFS 上的 POSIX 风格路径，如 `"/demo.bin"`。

**`fs` 必须是已经挂载好的对象。** HTTP 不会替你 `mount`、不会格式化、不会绑 SPI。典型顺序：

1. SPI + CS GPIO + `sfud.bind`
2. `lfs.mount(sfud, { offset, size, ... })` 得到 `fs`
3. 再 `http.get(..., { save = http.save.lfs(fs, path) })`

**调用模式**

```lua
http.get(url, { save = http.save.lfs(fs, "/demo.bin"), tls_mode = http.TLS_INSECURE })
```

```lua
http.request({
    url = url,
    save = http.save.lfs(fs, "/demo.bin"),
    max_response_size = 512 * 1024,
})
```

```lua
http.request({
    url = url,
    save = { lfs = fs, path = "/demo.bin" },
})
```

缺 `path`、path 为空、过长：`-20`（`"save invalid param"`）。

LittleFS **不会**按分区容量自动收紧 `max_response_size`，请自己设上限。写盘失败：无空间 `-21`，IO `-22`，内存 `-23`，其它 `-24`。

读：`fs:open(path, "r")` → `f:read(n)` → `f:close()`。每次从 Flash 抽一片，不要 `load` 整文件进字符串。示例：`http_file_lfs`（`flash.init` 挂整片，再 `download.run(flash.fs())`）。

### 10.5 落到 FlashDB

同一套 `save`，目标换成已挂载的 KV / 时序库。会按库的最大记录长度收紧 `max_response_size`；超限在有 Content-Length 时头阶段就 `-15`，收下后写前仍可能 `-25`。

```lua
http.request({ url = url, save = http.save.kv(kv, "ota") })
```

```lua
http.request({ url = url, save = { kv = kv, key = "ota" } })
```

```lua
http.request({ url = url, save = http.save.ts(ts) })
```

```lua
http.request({ url = url, save = { ts = ts } })
```

KV 必须有非空 `key`。TS 没有文件名。`max_len` 为 0 的 TS：直接 `-25`，不下载体。

### 10.6 落盘后的响应表

成功时除第 11 节公共字段外：

| 字段 | 说明 |
| --- | --- |
| `body` | 恒为空串 |
| `body_len` | 写入的字节数 |
| `saved` | `{ kind, body_len, ... }` |
| `saved.kind` | `"ublob"` / `"lfs"` / `"kv"` / `"ts"` |
| `saved.name` | 仅 ublob |
| `saved.path` | 仅 lfs |
| `saved.key` | 仅 kv |
| `saved_file` | **仅 ublob**，等于文件名（兼容旧脚本） |

`request` / `get` / `post` 的 HTTP 状态不是 2xx 时，只要收包和写盘成功，仍返回这张表，业务上请自己看 `status_code`。固件 1.4.3 新增的 `upload` 只接受完整 2xx 响应，其他状态返回 `-31`，并在错误第四返回值 `info` 中提供响应内容。

`save` 表里同时写多个目标时，识别顺序是 **ublob → lfs → kv → ts**，只用第一个认到的。

---

## 11. 返回表

无 `save` 时：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `protocol_version` | string | 如 `"HTTP/1.1"` |
| `status_code` | integer | 如 `200` |
| `status_desc` | string | 如 `"OK"` |
| `header` | string | 响应头原文（不含状态行） |
| `header_len` | integer | |
| `body` | string | 响应体，可能含 0 字节 |
| `body_len` | integer | |
| `connection_seq` | integer | 当前客户端内的连接序号；单次连接接口为 0 |
| `reused` | boolean | 本次借用了已有连接；构造时已预连接，第一次客户端请求也可为 true |
| `reusable` | boolean | 完整响应后满足继续使用条件，不保证远端存活；单次接口为 false |

有 `save` 时见 [10.6](#106-落盘后的响应表)。

---

## 12. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `request` / `sync` / `get` / `post` 及 `c:request/get/post` | 响应表 | `nil, err_code, err_msg` |
| `http.client(opts)` | 客户端 | `nil, err_code, err_msg` |
| `c:close()` | `true` | 租用期间 `nil, -17, "session busy"` |
| `upload(opts)` | 上传对象 | `nil, err_code, err_msg, info` |
| `upload(opts, producer)` / `u:send(producer)` / `u:finish()` | 响应表 | `nil, err_code, err_msg, info` |
| `u:write(data)` | `本次字节数, 累计发送字节数` | `nil, err_code, err_msg, info` |
| `u:poll([wait_ms])` | `true, info` | `nil, err_code, err_msg, info` |
| `http.encode` | 编码后的字符串 | **抛错**，见 [6.8](#6-8-encode) |
| `http.save.ublob` | 描述表 | 缺参抛错 |
| `http.save.lfs` / `kv` / `ts` | 描述表 | 对象未挂载等：**抛错** |

类型错（opts 不是 table、url 不是字符串等）走 Lua 抛错，不是三返回值。

协议层错误（模块表 **没有** 导出这些数字）：

| 值 | `err_msg` | 可能原因 |
| --- | --- | --- |
| `-1` | `invalid param` | URL/opts 非法。非法 headers 也是 `-1`，文案改为 `invalid headers` |
| `-2` | `invalid url` | 不是 `http://`/`https://`、缺 host、规范化失败 |
| `-3` | `out of memory` | 响应体或内部缓冲分配失败；减小 `max_response_size` 或改 `save` |
| `-4` | `dns resolve failed` | 域名错、未驻网、DNS 没配。先 `lp.wait_link` |
| `-5` | `socket failed` | 建/绑 socket 失败，协议栈忙或句柄无效 |
| `-6` | `connect failed` | 对端没开、端口错、防火墙、仅 IPv6 等 |
| `-7` | `tls failed` | HTTPS 握手失败、证书模式与 `tls_mode`/`ca_cert` 不匹配、固件未开 TLS |
| `-8` | `timeout` | 连/发/收超时；加大 opts 超时或查链路 |
| `-9` | `send failed` | 请求发出去一半连接断了 |
| `-10` | `recv failed` | 收响应失败，对端或链路 |
| `-11` | `connection closed` | 对端先关；短连接正常结束有时也会走到这，看是否已有部分头 |
| `-12` | `parse header failed` | 对端不是合法 HTTP 头 |
| `-13` | `parse chunked failed` | chunked 不完整或格式坏 |
| `-14` | `content-length required` | 这次请求要求 Content-Length，响应没给 |
| `-15` | `response too large` | 超过 `max_response_size`；改上限或改 `save` 落盘 |
| `-16` | `response output failed` | 响应输出失败 |
| `-17` | `session busy` | 客户端被请求或上传占用 |
| `-18` | `origin mismatch` | 请求与客户端的协议、主机或有效端口不同 |
| 其它负值 | `http request failed` | 未单独翻译的底层码 |

落盘错误从 **-20** 起（组 save 描述或写盘时）：

| 值 | `err_msg` | 可能原因 |
| --- | --- | --- |
| `-20` | `save invalid param` | 文件名/路径/key 空或过长；`save` 不是 string/table |
| `-21` | `save quota exceeded` | ublob 与脚本区共用配额满；或 LittleFS 没空间 |
| `-22` | `save io error` | 写盘 IO，介质或挂载异常 |
| `-23` | `save out of memory` | 写盘时分配失败 |
| `-24` | `save failed` | 其它写盘失败 |
| `-25` | `save payload too large` | 超过 KV/TS 单条容量 |
| `-26` | `save target type invalid` | `save.lfs`/`kv`/`ts` 对象类型不对、未挂载；或固件未开 LFS |

TLS 配置失败：`err_msg` 为 `"tls configure failed"`，码可能是 `-1`～`-4`，**以文案为准**。`http.save.lfs` 在固件关掉 LittleFS 时 **抛** `lfs save unsupported (APP_LFS_ENABLE=0)`。

诊断：`-4`/`-6`/`-8` 先查驻网和 URL；`-7` 查证书与 `tls_mode`；`-15`/`-21`/`-25` 查体积和配额；`-26` 查挂载对象是否还活着。

---

## 13. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 自定义头 | 32 对 | |
| `save` 名/路径/key | 95 字节 | 不含结尾 0 |
| 默认超时 | 30 s / 30 s | 发送 / 接收 |
| ublob | 与 ufs 共用 `usage().limit` | 只适合小文件 |
| 并发 view（ublob） | 1 | 与 HTTP 无关，读回时注意 |
| 上传对象 | 每次上传一个 | 单次上传完成关闭连接；客户端上传成功归还连接，未完成关闭则丢弃连接 |
| 长连接会话 | 默认共 8 个 | Lua 客户端、AT 配置通道和 AT 自由会话共用；超出返回 `-3` |
| 客户端空闲时长 | 默认 60 秒，最大 86400 秒 | 释放 TCP/TLS；仍需 `close()` 或 GC 销毁不用的客户端以归还会话名额 |
| 上传取数回调 | 每次最多 2048 字节 | 使用回调参数中的 `max_bytes` |
| 上传响应正文 | 默认 16 KiB，最大 1 MiB | `upload` 的 `max_response_size`；0 使用默认值 |

`request` / `get` / `post` 的文件和数据库对象在调用期间必须有效。手动上传期间持有上传对象，出错或取消后调用 `close()`。取数回调只在 `upload(opts, producer)` 或 `u:send(producer)` 执行期间调用。

### 13.1 连接复用条件

只有完整消费本次响应后才能继续使用连接：定长正文收满、chunked 结束块与 trailers 收完，或明确无正文。`Content-Length: 0`、HEAD、204、304 不等待远端断开；100/103 等临时响应继续等待最终响应。

`Connection: close`、HTTP/1.0 未声明 keep-alive、依赖 EOF 定界的正文，以及截断、解析错误、超限、输出中断都不复用。断网或 SIM 移除会使旧连接失效；空闲连接由周期清理处理，正在执行的事务负责结束并释放租用。不会发送 HTTP 心跳，也不会自动重放已经发出的失败请求。

---

## 14. 选型对照

| 需求 | 做法 |
| --- | --- |
| 小 JSON / 调试 | `http.get` / `request`，看 `resp.body` |
| 同一服务连续请求或上传 | `http.client` + `c:request/get/post/upload`，复用 TCP/TLS |
| 查询值里有 `[` `]`、空格 | 先 `http.encode`，再拼进 `url` |
| HTTPS 不验证书 | `tls_mode = http.TLS_INSECURE` |
| HTTPS 验服务端 | `TLS_SERVER_AUTH` + `ca_cert` |
| 内部小二进制 | `save` → ublob |
| 内部 Lua 配置值 | **不要** HTTP save；下完再 `ufs.write` |
| 大文件 / 资源包 | 先挂 LittleFS，再 `http.save.lfs` |
| FlashDB 一条记录 | `save.kv` / `save.ts` |
| MCU OTA 小包 | ublob + `ublob.open` 按块读；再大走外挂盘 |
| 上传持续生成的数据 | 固件 1.4.3，`http.upload` 的取数回调或上传对象 |
| 回调里发 HTTP | **不要** |

---

## 15. 完整示例

### 15.1 GET / POST（`http_request`）

```lua
local rt   = require("rt")
local log  = require("log")
local lp   = require("lp")
local http = require("http")

if not lp.wait_link(60000) then
    log.warn("网络超时")
    while true do rt.delay(10000) end
end

local resp, err, msg = http.request({
    url = "https://httpbin.org/get",
    method = http.METHOD_GET,
    tls_mode = http.TLS_INSECURE,
})
if not resp then
    log.error("GET fail %s %s", err, msg)
else
    log.info("status=%s body_len=%s", resp.status_code, resp.body_len)
end

resp, err, msg = http.post("https://httpbin.org/post", "hello doiot~", {
    content_type = "text/plain",
    tls_mode = http.TLS_INSECURE,
})
```

### 15.2 下载到 ublob（`http_file_ublob`）

```lua
local http  = require("http")
local ublob = require("ublob")

ublob.remove("demo.bin")
local resp, err, msg = http.get("https://httpbin.org/html", "demo.bin", {
    tls_mode = http.TLS_INSECURE,
    max_response_size = 32 * 1024,
})
if not resp then
    log.error("%s %s", err, msg)
    return
end
-- resp.body == "" ，resp.body_len 与 ublob.size("demo.bin") 应一致
local v = ublob.open("demo.bin")
local off = 0
while off < v:size() do
    local chunk, n = v:read(off, 100)
    if n == 0 then break end
    log.info("[%s]", chunk)
    off = off + n
end
v:close()
```

### 15.3 下载到已挂载 LittleFS（`http_file_lfs`）

挂盘本身见该 demo 的 `flash.lua`（SPI + sfud + `lfs.mount`）。HTTP 只接收 **已经挂好的** `fs`：

```lua
local http = require("http")

-- fs 来自 lfs.mount(...)，未挂载不要往下走
local resp, err, msg = http.get("https://www.baidu.com/", {
    tls_mode = http.TLS_INSECURE,
    save = http.save.lfs(fs, "/demo.bin"),
    max_response_size = 512 * 1024,
})
if not resp then
    log.error("%s %s", err, msg)
    return
end
log.info("saved %s %s", resp.saved.kind, resp.saved.path)

local f = fs:open("/demo.bin", "r")
while true do
    local chunk = f:read(100)
    if chunk == nil or chunk == "" then break end
    log.info("[%s]", chunk)
end
f:close()
```

---

## 附录 A. 方法速查

| 调用 | 动作 |
| --- | --- |
| `http.client(opts)` | 建立可复用连接的客户端 |
| `c:request(opts)` / `c:get(path, opts)` / `c:post(path, body, opts)` | 在客户端连接上请求 |
| `c:upload(opts [, producer])` | 在客户端连接上上传 |
| `c:status()` / `c:close()` | 查询状态 / 销毁客户端 |
| `http.request(opts)` / `http.sync(opts)` | 通用一次请求 |
| `http.get(url)` | GET |
| `http.get(url, opts)` | GET + 选项 |
| `http.get(url, filename)` | GET 并写入 ublob |
| `http.get(url, filename, opts)` | 同上，可加 TLS 等 |
| `http.post(url, body)` | POST |
| `http.post(url, body, opts)` | POST + 选项（可含 `save`） |
| `http.upload(opts)` | 固件 1.4.3，建立 chunked 上传，返回对象 |
| `http.upload(opts, producer)` | 固件 1.4.3，按回调取数并完成上传 |
| `u:write(data)` / `u:finish()` / `u:close()` | 写入、结束并读响应、释放上传连接 |
| `u:poll([wait_ms])` / `u:status()` / `u:send(producer)` | 检查连接、本地状态、回调供数 |
| `http.encode(text)` | 按 `ENCODE_COMPONENT` 百分号编码 |
| `http.encode(text, level)` | 按 `ENCODE_COMPONENT` / `ENCODE_FORM` / `ENCODE_PATH` / `ENCODE_URI` 编码 |
| `http.save.ublob(name)` | ublob 描述表 |
| `http.save.lfs(fs, path)` | LittleFS 描述表（fs 已挂载） |
| `http.save.kv(db, key)` | KV 描述表 |
| `http.save.ts(db)` | TS 描述表 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `http.METHOD_GET` | `"GET"` |
| `http.METHOD_POST` | `"POST"` |
| `http.METHOD_PUT` | `"PUT"` |
| `http.METHOD_DELETE` | `"DELETE"` |
| `http.METHOD_HEAD` | `"HEAD"` |
| `http.TLS_INSECURE` | `1` |
| `http.TLS_SERVER_AUTH` | `2` |
| `http.TLS_MUTUAL_AUTH` | `3` |
| `http.ENCODE_COMPONENT` | `0` |
| `http.ENCODE_FORM` | `1` |
| `http.ENCODE_PATH` | `2` |
| `http.ENCODE_URI` | `3` |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 协议/落盘错误码补全可能原因，并写未翻译码与 LFS 关闭时的抛错 |
| 1.2.0 | 2026-10-16 | 新增 `http.encode` 与 `ENCODE_COMPONENT` / `ENCODE_FORM` / `ENCODE_PATH` / `ENCODE_URI`。查询值默认把方括号编成 `%5B` `%5D` |
| 1.2.1 | 2026-10-16 | 补全 `http.encode` 的参数、四个调用等级和抛错文案 |
| 1.3.0 | 2026-11-09 | 对应固件 1.4.3。新增 `http.upload` 的 POST/PUT chunked 上传、上传对象、取数回调、四返回值错误约定及资源上限 |
| 1.4.0 | 2026-11-12 | 当前 SDK 新增长连接客户端、连接复用状态、上传租用、资源上限、断线与错误语义；AT 接口说明移至 AT 手册 |
