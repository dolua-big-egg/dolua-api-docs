#  Socket（SOCK）

**文档版本** `1.0.2`

配置并收发模组上的 **4 路 Socket 通道**（TCP 或 UDP）。指令走应用 AT 口（主串口 / USB AT 等），与 [`rtu_config.cfg` 的 `[sock.N]`](../api/rtu_config/rtu_config.md#9-sockn--socketn) 读写**同一份持久化配置**。通道号一律 **1～4**，与配置段 `[sock.1]`～`[sock.4]` 对应。

本篇按常用模组 AT 手册体例写：先约定，再逐条给出测试命令、查询、设置、参数表、应答、错误码和可抄示例。行格式与两种失败风格亦见 [convention.md](convention.md)。其它业务指令按类分篇，索引在 [README.md](README.md)。

---

## 目录

- [1. 约定](#1-约定)
- [2. 指令一览](#2-指令一览)
- [3. 通道与生效时机](#3-通道与生效时机)
- [4. AT+SOCK](#4-atsock)
- [5. AT+SOCKCFG](#5-atsockcfg)
- [6. AT+SOCKKEEP](#6-atsockkeep)
- [7. AT+SOCKSYNC](#7-atsocksync)
- [8. AT+SOCKASYNC](#8-atsockasync)
- [9. 错误一览](#9-错误一览)
- [10. 联调顺序](#10-联调顺序)
- [修订记录](#修订记录)

---

## 1. 约定

### 1.1 行格式

| 项 | 约定 |
| --- | --- |
| 命令结束 | 每条命令以 `<CR><LF>`（`\r\n`）结束。下文示例省略行结束符 |
| 大小写 | 命令名大小写不敏感；参数里的 `key`、主机名按原文保存 |
| 字符串 | 主机、key 建议加双引号，例如 `"tcp_host"`、`"10.0.0.8"` |
| 数值 | 十进制整数，不要带符号、不要带小数 |
| 尾部裸数据 | `<payload>` 为 **TAILRAW**：最后一个逗号之后到行结束之前的**原始字节**，不做 HEX 文本解码。可含 `0x00`，也可是普通 ASCII |

测试命令（`AT+XXX=?`）返回该指令的取值范围与写法，以 `OK` 结束。

### 1.2 命令形态

| 形态 | 写法 | 本篇是否支持 |
| --- | --- | --- |
| 测试 | `AT+XXX=?` | 五条都支持 |
| 按通道查询 | `AT+XXX=<id>?` | `SOCK` / `SOCKCFG` / `SOCKKEEP` |
| 按 key 查询 | `AT+SOCKCFG=<id>,"<key>"`（无第三参） | 仅 `SOCKCFG` |
| 设置 | `AT+XXX=<id>,…` | 五条都支持 |
| 无参查询 `AT+XXX?` | — | **不支持**。不要写 `AT+SOCK?` |

没有「执行命令」（无参 `AT+SOCK`）。

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

`<reason>` 是短英文词，见 [第 9 节](#9-错误一览)。**不是** `+CME ERROR: <err>`。

`SOCKSYNC` / `SOCKASYNC` 在 `rsp=0` 时：**成功、失败都不回** `+CMD` / `OK` / `ERROR`。主机只能靠超时或其它通道判断。

### 1.4 与 Lua / 配置文件

| 入口 | 做什么 |
| --- | --- |
| 本篇 AT | 改 Socket 持久化配置；按通道同步/异步发数据 |
| `[sock.N]` | 同一套 key，开机/加载配置时写入 |
| Lua `require("rtu")` / `tcp` | 读的是落盘后的通道，不是另一套编号 |

`AT+SOCK` 只改 **当前协议栈** 的主机和端口（TCP 或 UDP 二选一），并顺带把该通道 `enable` 置 1。细项（缓冲、超时、keepalive 开关等）用 `AT+SOCKCFG`。`host`/`port` 那种「同时写 TCP+UDP」的别名只存在于 `rtu_config.cfg`，AT 没有。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+SOCK` | `=?` | `<id>?` | `<id>,<ip>,<port>,<proto>` | 设/查通道协议与对端，并打开 `enable` |
| `AT+SOCKCFG` | `=?` | `<id>?` 全量；`<id>,"key"` 单项 | `<id>,"key",<value>` | 按 key 读写全部 Socket 项 |
| `AT+SOCKKEEP` | `=?` | `<id>?` | `<id>,<idle>,<intvl>,<cnt>` | 只写 TCP keepalive 三个时间参数 |
| `AT+SOCKSYNC` | `=?` | 无 | `<id>,<rsp>,<payload>` | **同步**发送（阻塞到发送返回） |
| `AT+SOCKASYNC` | `=?` | 无 | `<id>,<rsp>,<payload>` | **异步**入队（当前仅 TCP） |

---

## 3. 通道与生效时机

- 通道数 **4**。`<id>` = 1、2、3、4。越界回 `"error id"`。
- 每通道同时只跑一种协议：`proto=0` TCP，`proto=1` UDP。两套参数都存在配置里，连线只用当前 `protocol`。
- **本篇设置类指令写入持久化配置，不改已经建立的那条连接。** 正在跑的通道仍用启动时读到的值。要让新主机/端口/保活生效：停通道再启、或按产品流程重新加载配置 / 复位。
- 仅写 `AT+SOCK` 而 RTU 任务没开（`[task.N] en=0` 或 `task_id` 不是 Socket）时，配置在、业务通道可能仍不起。发送会失败。
- 出厂未配时：`enable=0`，`protocol=0`（TCP），TCP/UDP 端口为 0，主机为空。此时 `AT+SOCK=<id>?` 可能看到空主机和端口 0。

TCP 出厂常用默认（未改过细项时）：

| 项 | 默认 |
| --- | --- |
| 重连间隔 | 5000 ms |
| 连接超时 | 10000 ms |
| 接收超时 | 1000 ms |
| 收缓冲 | 4096 |
| 发缓冲 | 2048 |
| keepalive 开关 | 0（关） |
| keepalive idle / interval / count | 60 s / 10 s / 3 |
| 轮询间隔 | 50 ms |
| 等链路 | 60000 ms |
| TCP_NODELAY | 0 |

UDP 出厂常用默认：重试 5000 ms，收/发缓冲 2048，轮询 50 ms，等链路 60000 ms。

主机最长 **127** 字节（不含结尾 NUL）。

---

## 4. AT+SOCK {#4-atsock}

设置或查询一路通道的 **协议 + 对端地址**。设置成功时该通道 `enable` 变为 1，并只改对应协议的 `host`/`port`（TCP 不改 UDP 主机，反之亦然）。其它超时、缓冲保持原值。

### 4.1 测试命令

**命令**

```lua
AT+SOCK=?
```

**应答**

```lua
+SOCK: (id,"ip",port,proto)
id:1-4, proto:0-tcp,1-udp
query: AT+SOCK=<id>?

OK
```

### 4.2 查询命令

**命令**

```lua
AT+SOCK=<id>?
```

返回**当前 `protocol` 那一套**主机和端口，不是两套都打。

**应答（成功）**

```lua
+SOCK: <id>,"<ip>",<port>,<proto>

OK
```

| 字段 | 含义 |
| --- | --- |
| `<id>` | 1～4 |
| `<ip>` | 当前协议的主机。未配置时可能为空串 `""` |
| `<port>` | 当前协议端口，0～65535 |
| `<proto>` | `0` TCP，`1` UDP |

**失败** `+SOCK: "error <reason>"` 后 `ERROR`。常见 `param`（缺 id / 不是数字）、`id`、`read`。

### 4.3 设置命令

**命令**

```lua
AT+SOCK=<id>,<ip>,<port>,<proto>
```

**参数**

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<ip>` | 字符串 | 1～127 字符，非空 | 域名或点分 IPv4。必须是字符串类型 |
| `<port>` | 整数 | 1～65535 | **0 非法** |
| `<proto>` | 整数 | 0 或 1 | `0` 写入 TCP 主机/端口并切到 TCP；`1` 写入 UDP 并切到 UDP |

参数个数不是 4、`<ip>` 不是字符串、`<port>`/`<proto>` 不是非负整数 → `"error param"`。

**应答（成功）** 回显刚写入的值：

```lua
+SOCK: <id>,"<ip>",<port>,<proto>

OK
```

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 形态不对或负数 |
| `id` | 不是 1～4 |
| `ip` | 空串或长度 ≥ 128 |
| `port` | 0 或大于 65535 |
| `proto` | 不是 0/1 |
| `read` | 读持久化配置失败 |
| `save` | 写入失败 |

### 4.4 示例

```lua
AT+SOCK=1,"10.0.0.8",9001,0
+SOCK: 1,"10.0.0.8",9001,0

OK

AT+SOCK=1?
+SOCK: 1,"10.0.0.8",9001,0

OK

AT+SOCK=2,"udp.example.com",5000,1
+SOCK: 2,"udp.example.com",5000,1

OK
```

### 4.5 说明

- 设置 **不会** 立刻断开旧连接再连新地址，见 [第 3 节](#3-通道与生效时机)。
- 查询读的是持久化配置，不是瞬时 TCP 状态（已连接/未连接本指令不报）。
- 不要用本指令当「connect」。连上由 RTU 任务 / 通道启动流程负责。

---

## 5. AT+SOCKCFG {#5-atsockcfg}

按 **key** 读写单通道全部 Socket 项。能改的名字与 `[sock.N]` 里除 `host`/`port` 别名以外的 key **相同**。

### 5.1 测试命令

```lua
AT+SOCKCFG=?
```

```lua
+SOCKCFG: (id,"key",value)
query: AT+SOCKCFG=<id>,"<key>"
query all: AT+SOCKCFG=<id>?
set:   AT+SOCKCFG=<id>,"<key>",<RAW>

OK
```

### 5.2 查询全部

```lua
AT+SOCKCFG=<id>?
```

成功时连续输出该通道每一项，最后一行带 `OK`。顺序固定如下（字段均为 `+SOCKCFG: <id>,"<key>",<value>`；主机类 value 带引号）：

`enable` → `protocol` → 全部 `tcp_*` → 全部 `udp_*`。

缓冲区不够回 `"error overflow"`；申请失败回 `"error malloc"`。

### 5.3 查询单项

第三参不出现或长度为 0 时，当作查询，不是设置：

```lua
AT+SOCKCFG=<id>,"<key>"
```

未知 key → `"error key"`。

**应答（数值 key）**

```lua
+SOCKCFG: <id>,"<key>",<number>

OK
```

**应答（主机 key）**

```lua
+SOCKCFG: <id>,"tcp_host","10.0.0.8"

OK
```

`protocol` 查询值为 **0/1**（对外），与设置时相同。

### 5.4 设置

```lua
AT+SOCKCFG=<id>,"<key>",<value>
```

| key | value 形态 | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `enable` | 整数 | 0 或 1 | 通道协议使能。任务侧还要 `[task.N]` |
| `protocol` | 整数 | 0=TCP，1=UDP | 只改当前用哪套参数 |
| `tcp_host` | 字符串 | 1～127，非空 | 只改 TCP 主机 |
| `tcp_port` | 整数 | 1～65535 | 0 会 `save` 失败 |
| `tcp_reconnect_interval` | 整数 ms | 0～4294967295 | 断线重连间隔 |
| `tcp_connect_timeout` | 整数 ms | 同上 | 连接超时 |
| `tcp_recv_timeout` | 整数 ms | 同上 | 接收超时 |
| `tcp_recv_buffer_size` | 整数 | 同上 | 收缓冲 |
| `tcp_send_buffer_size` | 整数 | 同上 | 发缓冲 |
| `tcp_keepalive_enable` | 整数 | 0 或 1 | TCP keepalive **总开关** |
| `tcp_keepalive_idle` | 整数 秒 | 0～4294967295 | 空闲多久开始探活 |
| `tcp_keepalive_interval` | 整数 秒 | 同上 | 探活间隔 |
| `tcp_keepalive_count` | 整数 | 同上 | 探活次数 |
| `tcp_poll_interval` | 整数 ms | 0～4294967295 | 轮询 |
| `tcp_nodelay` | 整数 | 0 或 1 | TCP_NODELAY |
| `tcp_link_wait_timeout` | 整数 ms | 0～4294967295 | 等蜂窝链路 |
| `udp_host` | 字符串 | 1～127，非空 | 只改 UDP 主机 |
| `udp_port` | 整数 | 1～65535 | 0 会失败 |
| `udp_retry_interval` | 整数 ms | 0～4294967295 | UDP 重试 |
| `udp_recv_buffer_size` | 整数 | 同上 | |
| `udp_send_buffer_size` | 整数 | 同上 | |
| `udp_poll_interval` | 整数 ms | 同上 | |
| `udp_link_wait_timeout` | 整数 ms | 同上 | |

没有 `host` / `port` 别名。要两套地址一起改，分别写 `tcp_host` 与 `udp_host`。

`<value>` 可以是十进制数，或带/不带引号的文本。主机类必须能解析成非空字符串。数值类解析失败 → `"error value"`。`enable` / `protocol` / `tcp_nodelay` / `tcp_keepalive_enable` 超出 0/1 → `"error value"` 或 `"error save"`。

**应答（成功）** 与单项查询同形，回显写入后的值。

**失败 reason**：`param`、`id`、`key`、`value`、`read`、`save`、`overflow`、`malloc`。

### 5.5 示例

```lua
AT+SOCKCFG=1,"tcp_host","10.0.0.8"
+SOCKCFG: 1,"tcp_host","10.0.0.8"

OK

AT+SOCKCFG=1,"tcp_port",9001
+SOCKCFG: 1,"tcp_port",9001

OK

AT+SOCKCFG=1,"protocol",0
+SOCKCFG: 1,"protocol",0

OK

AT+SOCKCFG=1,"tcp_keepalive_enable",1
+SOCKCFG: 1,"tcp_keepalive_enable",1

OK

AT+SOCKCFG=1,"enable"
+SOCKCFG: 1,"enable",1

OK
```

---

## 6. AT+SOCKKEEP {#6-atsockkeep}

一次写入该通道 TCP keepalive 的 **idle / interval / count**。只动这三个数，**不改** `tcp_keepalive_enable`。开关仍为 0 时，三个数存着也不会探活。要探活须再：

```lua
AT+SOCKCFG=<id>,"tcp_keepalive_enable",1
```

UDP 通道查得到这三项（存在 TCP 参数块里），但连 UDP 时不会用。

### 6.1 测试命令

```lua
AT+SOCKKEEP=?
```

```lua
+SOCKKEEP: (id,keep_idle,keep_intvl,keep_cnt)
id:1-4
keep_idle:1-7200(s)
keep_intvl:1-300(s)
keep_cnt:1-10
set:   AT+SOCKKEEP=<id>,<keep_idle>,<keep_intvl>,<keep_cnt>
query: AT+SOCKKEEP=<id>?

OK
```

测试命令里的 1～7200 / 1～300 / 1～10 是**推荐工作范围**。写入时按 32 位无符号整数落盘；超出推荐范围只要能写成整数，仍可能 `OK`。产品侧请按测试命令范围配。

### 6.2 查询

```lua
AT+SOCKKEEP=<id>?
```

```lua
+SOCKKEEP: <id>,<keep_idle>,<keep_intvl>,<keep_cnt>

OK
```

单位：秒、秒、次。

### 6.3 设置

```lua
AT+SOCKKEEP=<id>,<keep_idle>,<keep_intvl>,<keep_cnt>
```

四个参数都必须是非负整数。任一写入失败 → `"error save"`（可能已写入前面几个，重发整条）。

**应答（成功）** 回显四个数，与查询同形。

**失败**：`param`、`id`、`read`、`save`。

### 6.4 示例

```lua
AT+SOCKKEEP=1,60,10,3
+SOCKKEEP: 1,60,10,3

OK

AT+SOCKCFG=1,"tcp_keepalive_enable",1
+SOCKCFG: 1,"tcp_keepalive_enable",1

OK
```

---

## 7. AT+SOCKSYNC {#7-atsocksync}

在指定通道上 **同步发送** 一段载荷：调用一直等到发送接口返回。发送前按映射规则尝试展开占位符（与 `[maping]` 的 sock 路由同类）；展开失败则发送**原始**载荷，不因此报错。

**仅设置，无查询。** 通道必须已经启动且当前协议允许发送，否则失败。

### 7.1 测试命令

```lua
AT+SOCKSYNC=?
```

```lua
+SOCKSYNC: (id,rsp,<TAILRAW>)
id:1-4 rsp:0/1
set only: AT+SOCKSYNC=<id>,<rsp>,<TAILRAW>
rsp=1: 返回最终发送结果；rsp=0: 同步发送但不返回指令响应

OK
```

### 7.2 设置

```lua
AT+SOCKSYNC=<id>,<rsp>,<payload>
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<id>` | 整数 | 1～4 | 通道 |
| `<rsp>` | 整数 | 0 或 1 | `1`：成功/失败都有 AT 应答；`0`：**完全静默**（无 `OK`/`ERROR`） |
| `<payload>` | TAILRAW | 长度 ≥ 1 | 第二个逗号之后的原始字节，直到行结束。空载荷非法 |

载荷长度在映射之后若超过内部 16 位上限，按截断长度做映射；映射缓冲申请失败则发原文。

**应答（`rsp=1` 且成功）**

```lua
+SOCKSYNC: <id>,1,<len>

OK
```

`<len>` 为**实际交给发送接口的字节数**（映射成功则是展开后的长度）。

**应答（`rsp=1` 且失败）**

```lua
+SOCKSYNC: "error <reason>"

ERROR
```

| reason | 可能原因 |
| --- | --- |
| `param` | 少参或 id 不是数字 |
| `id` | 不是 1～4 |
| `rsp` | 不是 0/1 |
| `data` | 没有 TAILRAW 或长度为 0 |
| `send` | 通道未起、未连接、协议/状态不允许、底层发送失败 |

**`rsp=0`**：无论成败，本条都没有 `+SOCKSYNC` / `OK` / `ERROR`。

### 7.3 示例

ASCII（注意第三个逗号后就是要发出去的字节，含空格）：

```lua
AT+SOCKSYNC=1,1,hello
+SOCKSYNC: 1,1,5

OK
```

静默发送（主机看不到 OK）：

```lua
AT+SOCKSYNC=1,0,hello
```

二进制：在 `AT+SOCKSYNC=1,1,` 之后直接跟原始字节再 `\r\n`，不要先编成 HEX 文本（除非你就是要发 ASCII 的 `A` `B` `C`）。

### 7.4 说明

- 同步发送会占住这条 AT 处理，大包或对端堵塞时 AT 口会停一阵。
- 本指令**不**把对端回包当 AT 应答吐出来。下行数据走 RTU / Lua 通道回调，不在 `+SOCKSYNC` 里。
- UDP、TCP 只要通道已 start，都可以走同步发送。

---

## 8. AT+SOCKASYNC {#8-atsockasync}

把载荷 **排进发送队列后返回**，不在 AT 调用里等发完。映射规则与 `SOCKSYNC` 相同。

**当前仅 TCP 通道支持异步入队。** UDP 或未连接时，`rsp=1` 得到 `"error enqueue"`；`rsp=0` 静默失败。

### 8.1 测试命令

```lua
AT+SOCKASYNC=?
```

```lua
+SOCKASYNC: (id,rsp,<TAILRAW>)
id:1-4 rsp:0/1
set only: AT+SOCKASYNC=<id>,<rsp>,<TAILRAW>
rsp=1: 仅返回是否成功推送队列（且需当前已连接）；rsp=0: 不返回指令响应

OK
```

### 8.2 设置

```lua
AT+SOCKASYNC=<id>,<rsp>,<payload>
```

参数表与 `AT+SOCKSYNC` 相同。`rsp=1` 成功：

```lua
+SOCKASYNC: <id>,1,<len>

OK
```

`<len>` 同样是入队前（映射后）的长度，**不是**对端已收到的长度。

失败 reason：`param` / `id` / `rsp` / `data` / **`enqueue`**（未连接、非 TCP、队列满、底层拒绝）。

`rsp=0`：无任何 AT 应答。

### 8.3 示例

```lua
AT+SOCKASYNC=1,1,hello
+SOCKASYNC: 1,1,5

OK
```

通道是 UDP 或 TCP 未连上：

```lua
AT+SOCKASYNC=1,1,hello
+SOCKASYNC: "error enqueue"

ERROR
```

### 8.4 对照

| | `SOCKSYNC` | `SOCKASYNC` |
| --- | --- | --- |
| 等待 | 等到发送调用返回 | 入队成功即返回 |
| TCP | 可以 | 可以（须已连接） |
| UDP | 可以 | **不可以**（enqueue） |
| `rsp=0` | 无应答 | 无应答 |
| 回包 | 都不从本指令返回 | 同左 |

---

## 9. 错误一览

统一形态：`+<CMD>: "error <reason>"` + `ERROR`（`rsp=0` 的发送指令除外）。

| reason | 出现指令 | 含义 |
| --- | --- | --- |
| `param` | 全部 | 参数个数、类型不对，或出现负数 |
| `id` | 全部 | 通道不是 1～4 |
| `ip` | SOCK | 主机空或过长 |
| `port` | SOCK | 端口不是 1～65535 |
| `proto` | SOCK | 不是 0/1 |
| `key` | SOCKCFG | key 空或不是已公布名字 |
| `value` | SOCKCFG | 值解析失败或 0/1 类越界 |
| `read` | SOCK / SOCKCFG / SOCKKEEP | 读持久化失败 |
| `save` | SOCK / SOCKCFG / SOCKKEEP | 写入失败或数值校验失败（如端口 0） |
| `overflow` | SOCKCFG 全量查询 | 回包拼爆缓冲 |
| `malloc` | SOCKCFG 全量查询 | 内存不足 |
| `rsp` | SOCKSYNC / SOCKASYNC | 不是 0/1 |
| `data` | SOCKSYNC / SOCKASYNC | 无载荷 |
| `send` | SOCKSYNC | 同步发送失败 |
| `enqueue` | SOCKASYNC | 异步入队失败 |

---

## 10. 联调顺序

1. 驻网完成（CSQ / CEREG 正常）。
2. `AT+SOCK=1,"<服务器>",<端口>,0` 配 TCP 对端并 `enable=1`。
3. 需要探活：`AT+SOCKKEEP=1,60,10,3`，再 `AT+SOCKCFG=1,"tcp_keepalive_enable",1`。
4. 确认 RTU 任务该路已使能且 `task_id` 指向 Socket（见 `rtu_config`）。等通道起来。
5. `AT+SOCKSYNC=1,1,ping` 看是否 `OK` 且 `<len>` 合理。
6. 改地址后若仍连旧服务器：先按产品流程重启该通道或复位，再发。

完整细项也可用 `AT+SOCKCFG=1?` 与 `rtu_config.cfg` 的 `[sock.1]` 对照，key 名应一致。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：SOCK / SOCKCFG / SOCKKEEP / SOCKSYNC / SOCKASYNC 的测试、查询、设置、错误与示例 |
| 1.0.1 | 2026-09-05 | 全部 AT 演示代码块标注为 lua |
| 1.0.2 | 2026-09-05 | 交叉链接通用约定与 AT 分类索引 |
