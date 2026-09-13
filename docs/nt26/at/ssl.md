#  SSL

**文档版本** `1.0.0`

维护 **3 组** TLS 证书（CA / 客户端证书 / 客户端私钥），供 MQTT / HTTP 的 `ssl_id` 引用。指令走应用 AT 口，与 [`rtu_config.cfg` 的 `[ssl.N]`](../api/rtu_config/rtu_config.md#13-ssln) 是**同一套证书组编号**：`<id>` = **1～3**，对应 `[ssl.1]`～`[ssl.3]`。

SSL 组号 **不是** Socket / MQTT 通道 1～4，也不是 HTTP 通道 1～5。MQTT 写 `ssl_id` / `ssl_level`，HTTP 写 `ssl_id` / `ssl_type`，两边都可以指向本组。见 [convention.md 第 4 节](convention.md#4-通道编号)。

行格式见 [convention.md](convention.md)。Lua 侧证书用法见 [mqtt API](../api/network/mqtt.md) 与 [http API](../api/network/http.md) 的 TLS 字段；本篇只写 AT 读写证书文件。

`[ssl.N]` 的 `mode`（1 不校验 / 2 校验服务端 / 3 双向）走配置文件，**本指令改不了 mode**，只改三份证书内容。

---

## 目录

- [1. 约定](#1-约定)
- [2. 指令一览](#2-指令一览)
- [3. 证书组与生效时机](#3-证书组与生效时机)
- [4. AT+SSL](#4-atssl)
- [5. 错误一览](#5-错误一览)
- [6. 联调顺序](#6-联调顺序)
- [修订记录](#修订记录)

---

## 1. 约定

### 1.1 行格式

| 项 | 约定 |
| --- | --- |
| 命令结束 | 每条命令以 `<CR><LF>`（`\r\n`）结束。下文示例省略行结束符 |
| 大小写 | 命令名大小写不敏感；`action`、`cert_name` **按原文**（须小写名） |
| 字符串 | `action`、`cert_name` 建议加双引号 |
| 尾部裸数据 | `write` 的证书内容为 **TAILRAW**：第三个逗号之后到行结束之前的**原始字节**。PEM 就按 PEM 原文贴，不要先编成 HEX 文本（除非你就是要存 ASCII 的 `hex:` 前缀内容） |

测试命令（`AT+SSL=?`）返回取值范围与写法，以 `OK` 结束。

### 1.2 命令形态

| 形态 | 写法 | 本篇是否支持 |
| --- | --- | --- |
| 测试 | `AT+SSL=?` | 支持 |
| 按组查询 `AT+SSL=<id>?` | — | **不支持**。读证书用 `action=read` |
| 无参查询 `AT+SSL?` | — | **不支持** |
| 设置 | `AT+SSL=<id>,<action>,<cert_name>[,<payload>]` | 支持 |

没有「只改 mode」的 AT。mode 写 [`[ssl.N]`](../api/rtu_config/rtu_config.md#13-ssln)。

### 1.3 成功与失败

成功：

```lua
<CR><LF>+SSL: <字段…><CR><LF>
<CR><LF>OK<CR><LF>
```

失败：

```lua
<CR><LF>+SSL: "error <reason>"<CR><LF>
<CR><LF>ERROR<CR><LF>
```

`<reason>` 见 [第 5 节](#5-错误一览)。**不是** `+CME ERROR`。

`stream` 先打 `>`，再阻塞读后续裸字节（超时 10 s），与 [HTTP `stream`](http.md#6-athttpreq) 同类。

### 1.4 与 Lua / 配置文件

| 入口 | 做什么 |
| --- | --- |
| 本篇 AT | 立刻读写/删除一组里的一份证书 |
| `[ssl.N]` | 同一组号；`mode` 与 `hex:` / PEM 文本也可在配置文件里写 |
| MQTT / HTTP AT | 用 `ssl_id` 引用本组，不在本指令里选通道 |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+SSL` | `=?` | 无（读用 `read`） | `<id>,"write\|stream\|read\|delete","<cert_name>"[,<TAILRAW>]` | 写 / 流写 / 读 / 删一份证书 |

---

## 3. 证书组与生效时机

- 组数 **3**。`<id>` = 1、2、3。越界回 `"error id"`。
- 每组三份名字（必须完全一致）：

| `cert_name` | 最长 | 用途 |
| --- | --- | --- |
| `ca_cert` | 6144 字节 | CA |
| `client_cert` | 4096 字节 | 客户端证书 |
| `client_key` | 4096 字节 | 客户端私钥 |

- **`write` / `stream` / `delete` 立刻改机内证书文件**，不是「只改一份待加载的草稿」。已经建立的 MQTT/HTTP 连接**不会**因此被本指令拆掉；下次握手 / 下次请求才会用到新证书。
- `read` 时文件不存在或内容为空：按 **成功、长度为 0** 处理，不回 `"error read"`。
- 超长、空内容 `write`、证书子系统未就绪等，统一落到 `"error write"` / `"error stream_write"`（见各 action）。
- PEM 可以含换行：`write` 用 TAILRAW 时，整段必须仍在**同一条 AT 行**里（到行结束为止），多行 PEM 更适合 `stream`。
- 配置文件里以 `hex:` 开头的写法是 `[ssl.N]` 的解析规则；本指令 `write` **不会**再剥一层 `hex:`，你贴什么就存什么。

---

## 4. AT+SSL {#4-atssl}

### 4.1 测试命令

**命令**

```lua
AT+SSL=?
```

**应答**

```lua
+SSL: (id,"write|stream|read|delete","cert_name",<TAILRAW>?)
id:1-3, cert_name: ca_cert|client_cert|client_key
size_limit: ca_cert<=6144, client_cert<=4096, client_key<=4096(bytes)

OK
```

### 4.2 查询命令

本指令没有 `AT+SSL=<id>?`。读内容用 `read`，见 [4.3](#43-设置命令)。

### 4.3 设置命令

```lua
AT+SSL=<id>,<action>,<cert_name>[,<payload>]
```

前三个参数必须是：整数 id、字符串 action、字符串 cert_name。少参或类型不对 → `"error param"`。

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～3 | 证书组 |
| `<action>` | 字符串 | `write` / `stream` / `read` / `delete` | 其它拼写 → `"error action"` |
| `<cert_name>` | 字符串 | 上表三个名字 | 其它名字 → `"error key name"`（中间有空格） |
| `<payload>` | TAILRAW | `write` 必填且长度 ≥ 1 | `stream` / `read` / `delete` 不要跟载荷 |

#### write

第三个逗号之后必须是长度 ≥ 1 的 TAILRAW，否则 `"error write_param"`。写入失败（超长、空、存储失败等）→ `"error write"`。

**应答（成功）**

```lua
+SSL: <id>,"write","<cert_name>",<len>

OK
```

`<len>` 为本次 TAILRAW 字节数。

#### stream

先回：

```lua
>
```

然后阻塞最多 **10 s** 读后续原始字节。读不到或长度为 0 → `"error stream_read"`。写入失败 → `"error stream_write"`。

**应答（成功）**

```lua
+SSL: <id>,"stream","<cert_name>",<len>

OK
```

`<len>` 为阻塞读到的字节数。

#### read

**应答（成功）**

```lua
+SSL: <id>,"read","<cert_name>",<len>
<证书原始字节，仅当 len>0>
<CR><LF>
OK
```

先打一行长度，再原样吐证书字节（**不是** HEX 文本），再空行和 `OK`。`len=0` 时没有证书体。读失败（不是「文件空」）→ `"error read"`。

#### delete

删除该组这份证书。失败 → `"error delete"`。

**应答（成功）**

```lua
+SSL: <id>,"delete","<cert_name>"

OK
```

没有长度字段。

### 4.4 示例

短 PEM（同一行 TAILRAW，示例把换行收成空格，现场应贴真实 PEM）：

```lua
AT+SSL=1,"write","ca_cert",-----BEGIN CERTIFICATE-----...-----END CERTIFICATE-----
+SSL: 1,"write","ca_cert",128

OK
```

多行证书用 stream：先发命令，看到 `>` 后再贴 PEM 原文。

```lua
AT+SSL=1,"stream","ca_cert"
>
+SSL: 1,"stream","ca_cert",512

OK
```

读回：

```lua
AT+SSL=1,"read","ca_cert"
+SSL: 1,"read","ca_cert",512
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----

OK
```

空组：

```lua
AT+SSL=2,"read","client_key"
+SSL: 2,"read","client_key",0

OK
```

删除：

```lua
AT+SSL=1,"delete","ca_cert"
+SSL: 1,"delete","ca_cert"

OK
```

未知名字：

```lua
AT+SSL=1,"read","server_cert"
+SSL: "error key name"

ERROR
```

### 4.5 说明

- `write` / `stream` 成功后，MQTT `ssl_level=2|3` 或 HTTP `ssl_type=2|3` 的**下一次**握手才会用到新文件。
- 只删证书不改 MQTT/HTTP 的 `ssl_id`：下次校验服务端时会变成「证书组在、文件空」。
- 不要把本组号和 `AT+MQTT=1` / `AT+HTTPURL=1` 当成一路。

---

## 5. 错误一览

统一形态：`+SSL: "error <reason>"` + `ERROR`。

| reason | 含义 |
| --- | --- |
| `param` | 少参，或 id 不是数字、action/cert_name 不是字符串 |
| `id` | 不是 1～3 |
| `key name` | `cert_name` 不是 `ca_cert` / `client_cert` / `client_key` |
| `action` | 不是 `write` / `stream` / `read` / `delete` |
| `write_param` | `write` 没有 TAILRAW 或长度为 0 |
| `write` | 写入失败（超长、存储失败、证书子系统未就绪等） |
| `stream_read` | `>` 之后 10 s 内没读到数据 |
| `stream_write` | 流写入失败（超长、存储失败等） |
| `read` | 读取失败（不是空文件那种成功） |
| `delete` | 删除失败 |

没有 `+CME ERROR`。

---

## 6. 联调顺序

1. 决定用哪一组：MQTT/HTTP 的 `ssl_id` 写成 1、2 或 3。
2. `mode` / `ssl_level` / `ssl_type` 按校验深度选 1～3；要校验服务端则必须有 `ca_cert`。
3. `AT+SSL=<id>,"write","ca_cert",<PEM>` 或 `stream` 写入 CA；双向再写 `client_cert` / `client_key`。
4. `AT+SSL=<id>,"read","ca_cert"` 核对长度。
5. MQTT：`AT+MQTTCFG=<N>,"ssl_id",<id>` 与 `ssl_level`。HTTP：`AT+HTTPCFG=<N>,"ssl_id",<id>` 与 `ssl_type`。然后重启对应通道或等下次请求。
6. 换证书后旧连接仍用旧会话，直到断线重连 / 下次 HTTP。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：SSL write/stream/read/delete、证书名与长度上限、空文件读成功、错误 reason |
