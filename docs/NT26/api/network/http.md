# http

**文档版本** `1.0.1`

同步 HTTP/HTTPS 客户端。纯函数模块：一次 `request` 从发到收完，没有对象、没有托管线程、没有自动重连。响应体可以进 Lua 字符串，也可以落到 **ublob**、已挂载的 **LittleFS**，或已挂载的 FlashDB。

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

`http` 只做一件事：按配置发一次 HTTP(S)，把结果带回来。

1. **必须已经能上网。** 没网会 DNS/连接失败。demo 都是先 `lp.wait_link`。
2. `http.request(opts)` 是通用入口。`http.sync` 与它是同一个函数。
3. `http.get` / `http.post` 只是帮你填 `url`、`method`（post 再填 body），其余仍走 `request`。
4. 不带 `save`：整份 body 变成 Lua 字符串。带 `save`：body 写入指定存储，`resp.body` 为空串，`body_len` 仍有效。

这不是 TCP/MQTT 那种托管连接：没有后台任务、不会断线重连、失败不会自己再试。要再发就再调一次。

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

和 TCP/MQTT 不同：没有独立工作线程替你收包。整次调用占着当前协程。

---

## 3. 阻塞语义

`request` / `get` / `post` **不是** `rt.delay` 那种让出：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 默认发送/接收超时各 30 秒；再加大文件，整机业务会卡住

失败不会自动重试。HTTPS 握手、大 body、慢站点（如 httpbin）都会把这次调用拉长。

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
| `tls_sni` / `tls_ignore_time` / `require_content_length` | boolean | **走 `toboolean`：数字 `0` 为真**。请用 `true`/`false` |
| `resp` | table | 成功响应，见第 11 节 |

超时、长度、PDP 走 **integer**。负的无符号项收成 `0`；`u8` 超过 255 收成 `255`。

---

## 6. 模块函数

模块表：`request`、`sync`、`get`、`post`，以及嵌套表 `http.save`。

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
| `timeout_r` | integer | `30` | 接收超时（秒） |
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

示例见 [examples/NT26/network/http/https](../../../../examples/NT26/network/http/https)。

---

## 10. 下载到文件

这一节单独讲：HTTP 不只是把 JSON 收进 `resp.body`。加上 `save` 后，响应体写入存储，**整包不进 Lua 字符串**，适合固件、资源包、大页面。

对应 demo：

| 路径 | demo |
| --- | --- |
| 内存字符串 | [examples/NT26/network/http/http_request](../../../../examples/NT26/network/http/http_request)、[examples/NT26/network/http/https](../../../../examples/NT26/network/http/https) |
| 内部 ublob | [examples/NT26/network/http/http_file_ublob](../../../../examples/NT26/network/http/http_file_ublob) |
| 外挂 LittleFS | [examples/NT26/network/http/http_file_lfs](../../../../examples/NT26/network/http/http_file_lfs) |

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

HTTP 状态不是 2xx 时，只要收包和写盘成功，仍返回这张表。业务上请自己看 `status_code`。

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

有 `save` 时见 [10.6](#106-落盘后的响应表)。

---

## 12. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `request` / `sync` / `get` / `post` | 响应表 | `nil, err_code, err_msg` |
| `http.save.ublob` | 描述表 | 缺参抛错 |
| `http.save.lfs` / `kv` / `ts` | 描述表 | 对象未挂载等：**抛错** |

类型错（opts 不是 table、url 不是字符串等）走 Lua 抛错，不是三返回值。

协议层错误（未导出符号）：

| 值 | `err_msg` | 含义 |
| --- | --- | --- |
| `-1` | `invalid param` | 入参非法；非法 headers 也是 `-1`（文案 `invalid headers`） |
| `-2` | `invalid url` | URL 非法 |
| `-3` | `out of memory` | 内存不足 |
| `-4` | `dns resolve failed` | DNS 失败（含未驻网） |
| `-5` | `socket failed` | socket |
| `-6` | `connect failed` | TCP 连不上 |
| `-7` | `tls failed` | TLS 握手 |
| `-8` | `timeout` | 超时 |
| `-9` | `send failed` | 发送 |
| `-10` | `recv failed` | 接收 |
| `-11` | `connection closed` | 对端关闭 |
| `-12` | `parse header failed` | 头解析 |
| `-13` | `parse chunked failed` | chunked |
| `-14` | `content-length required` | 要求 CL 但没有 |
| `-15` | `response too large` | 超过 `max_response_size` |

落盘错误从 **-20** 起（请求阶段或写盘阶段）：

| 值 | `err_msg` | 含义 |
| --- | --- | --- |
| `-20` | `save invalid param` | 文件名/路径/key 空或过长；`save` 不是 string/table |
| `-21` | `save quota exceeded` | ublob 配额或 LittleFS 无空间 |
| `-22` | `save io error` | 写盘 IO |
| `-23` | `save out of memory` | 写盘内存 |
| `-24` | `save failed` | 其它写盘失败 |
| `-25` | `save payload too large` | 超过 KV/TS 容量 |
| `-26` | `save target type invalid` | 对象类型不对或未挂载；固件未开 LFS |

TLS 配置失败：`err_msg` 为 `"tls configure failed"`，码可能是 `-1`～`-4`，用文案区分。

---

## 13. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 自定义头 | 32 对 | |
| `save` 名/路径/key | 95 字节 | 不含结尾 0 |
| 默认超时 | 30 s / 30 s | 发送 / 接收 |
| ublob | 与 ufs 共用 `usage().limit` | 只适合小文件 |
| 并发 view（ublob） | 1 | 与 HTTP 无关，读回时注意 |
| 对象 | 无 | 无 userdata 客户端 |

无回调槽。不必长期持有 `http` 模块以外的引用；但 `save.lfs` / `kv` / `ts` 用到的 `fs`/`db` 在这次调用期间必须仍有效（调用方本来就该持有挂载对象）。

---

## 14. 选型对照

| 需求 | 做法 |
| --- | --- |
| 小 JSON / 调试 | `http.get` / `request`，看 `resp.body` |
| HTTPS 不验证书 | `tls_mode = http.TLS_INSECURE` |
| HTTPS 验服务端 | `TLS_SERVER_AUTH` + `ca_cert` |
| 内部小二进制 | `save` → ublob |
| 内部 Lua 配置值 | **不要** HTTP save；下完再 `ufs.write` |
| 大文件 / 资源包 | 先挂 LittleFS，再 `http.save.lfs` |
| FlashDB 一条记录 | `save.kv` / `save.ts` |
| MCU OTA 小包 | ublob + `ublob.open` 按块读；再大走外挂盘 |
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
| `http.request(opts)` / `http.sync(opts)` | 通用一次请求 |
| `http.get(url)` | GET |
| `http.get(url, opts)` | GET + 选项 |
| `http.get(url, filename)` | GET 并写入 ublob |
| `http.get(url, filename, opts)` | 同上，可加 TLS 等 |
| `http.post(url, body)` | POST |
| `http.post(url, body, opts)` | POST + 选项（可含 `save`） |
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

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
