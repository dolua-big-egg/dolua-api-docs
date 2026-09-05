# AT 短信（SMS）

**文档版本** `1.0.0`

配 10 路短信通道号码、读写删除 **SIM 卡存储**、按通道或按号码发短信，以及收信转发到 RTU。与 [`rtu_config.cfg` 的 `[sms]` / `[sms.N]`](../api/rtu_config/rtu_config.md#27-sms--smsn) 读写**同一份持久化**。行格式见 [convention.md](convention.md)。

本篇失败风格 **混用**：通道号码 / SIM 存储 / 多数发送走短 reason；`SMSTMPH` 设置与 `SMSCFG` 单项写走 `+CME ERROR`。发送成功时 `+CMD` 里的数字是 **发送结果码**（`0` 成功），不是 CME。

Lua `require("sms")` 用模组短信能力收发，**不读** 这 10 路转发号码。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. 通道、SIM 存储与发送码](#3-通道sim-存储与发送码)
- [4. AT+SMS](#4-atsms)
- [5. AT+SMSR](#5-atsmsr)
- [6. AT+SMSL](#6-atsmsl)
- [7. AT+SMSD](#7-atsmsd)
- [8. AT+SMSWRITE](#8-atsmswrite)
- [9. AT+SMSSYNC](#9-atsmssync)
- [10. AT+SMSASYNC](#10-atsmsasync)
- [11. AT+SMSTMPH](#11-atsmstmph)
- [12. AT+SMSCFG](#12-atsmscfg)
- [13. 错误一览](#13-错误一览)
- [14. 联调顺序](#14-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 通道 `<id>` | **1～10** = `[sms.1]`～`[sms.10]`。**99** = 全体通道（查全部 / 清空全部） |
| SIM `index` | **1～255** 是卡上一条记录的槽号。**不要**和通道 99 混用 |
| `SMSD=0` | 删 SIM **全部**。用 0 而不是 99，避免和真实槽号冲突 |
| 正文 | `SMSWRITE` / `SMSSYNC` / `SMSASYNC` 的载荷是 **TAILRAW**（第一个逗号之后到行结束的原始字节） |
| 可空包 | 这三条发送允许正文长度为 0 |
| 正文上限 | **950** 字节（超单条由发送层分片） |
| 号码上限 | 通道号码 **31** 字符；`SMSSYNC`/`SMSASYNC` 目标号码 **20** 字符 |
| 发送守卫 | 约 **5 s**（同步等结果 / 异步入队前的附着检查窗口） |
| 失败 | 见各条。`SMSCFG` / `SMSTMPH` 设置会打 CME |

没有无参 `AT+SMS?` 查通道（那是 `AT+SMS=99`）。`AT+SMSTMPH` / `AT+SMSTMPH?`、`AT+SMSCFG?` 才是无参查询。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+SMS` | `=?` | `<id>` / `<id>?`；`99` 列全部 | `<id>,"<num>"` | 读写 10 路号码 |
| `AT+SMSR` | `=?` | 无 | `<index>` | 按 SIM 槽号读一条 |
| `AT+SMSL` | `=?` | 无 | `<type>` | 列 SIM：全部 / 已读 / 未读 |
| `AT+SMSD` | `=?` | 无 | `<index>` | `0` 删全部；`1～255` 删一条 |
| `AT+SMSWRITE` | `=?` | 无 | `<id>,<payload>` | 按通道号码 **异步** 发 |
| `AT+SMSSYNC` | `=?` | 无 | `"<da>",<payload>` | 指定号码 **同步** 发 |
| `AT+SMSASYNC` | `=?` | 无 | `"<da>",<payload>` | 指定号码 **异步** 入队 |
| `AT+SMSTMPH` | `=?` | `AT+SMSTMPH` / `?` | `"<hex>"` | 转发模板（hex，解码后最长 255） |
| `AT+SMSCFG` | `=?` | `?` 全量；`"key"` 单项 | `"key",<value>` | `forward_en` / `forward_route` / `forward_msg_mode` |

---

## 3. 通道、SIM 存储与发送码

### 3.1 通道 1～10 与 99

| AT `<id>` | 含义 |
| --- | --- |
| 1～10 | `[sms.N]` 的 `number`。内部下标 0～9 |
| 99 | **全体**：查询列出 10 行；设置只允许号码为空串（一次清空 10 路） |
| 其它 | `"error id"` |

`AT+SMSWRITE` 的 id **只能 1～10**（解析规则不含 99）。空号码通道发送会得到发送码 **-1**。

`forward_en=1` 但十路号码都空：没有可转发目标。mode=3 还要模板，且 `[maping] all=1` 占位符才会展开。见 [rtu_config 第 27 节](../api/rtu_config/rtu_config.md#27-sms--smsn)。

### 3.2 SIM 存储 index

`SMSR` / `SMSL` / `SMSD` 操作的是 **SIM 上的 SM 存储**，不是 10 路通道，也不是模组本地 ME。

| 值 | 指令 | 含义 |
| --- | --- | --- |
| `1`～`255` | `SMSR` | 读该槽。`<1` 或 `>255` → `"error index"`。槽空 / 读失败 → `"error read"` |
| `1`～`255` | `SMSD` | 删该槽。失败 `"error del"` |
| `0` | `SMSD` | **删全部**。失败 `"error del_all"` |
| `SMSL` 列出的 `<index>` | — | 就是上面这套槽号，拿去 `SMSR` / `SMSD` |

`SMSL` 一次最多列出 **64** 条。已读/未读过滤 **只对 SIM** 有效。

应答里的 `<status>` 与卡记录状态对齐：

| `<status>` | 含义 |
| --- | --- |
| `0` | 已收未读 |
| `1` | 已收已读 |
| `2` | 已存未发 |
| `3` | 已存已发 |
| `255`（`0xFF`） | 未知 |

号码、正文里的 `"`、`CR`、`LF` 在 AT 回显里会被换成空格，避免拆行。

### 3.3 发送结果码

`SMSWRITE` / `SMSSYNC` / `SMSASYNC` 成功或失败时，`+CMD` 后的整数是发送层结果（不是 CME）：

| 码 | 含义 |
| --- | --- |
| `0` | 成功（同步已发出；异步已入队） |
| `-1` | 参数：通道非法、该路号码空、正文指针异常 |
| `-2` | 目标号码过长 |
| `-3` | 内存不足，或发送队列未就绪 |
| `-4` | 异步队列满（仅异步） |
| `-5` | 组 PDU 失败（同步） |
| `-6` | 单条发送失败 |
| `-7` | 长短信某一分片发送失败 |
| `-10` / `-11` | 预留（当前路径一般用不到） |
| `-100` | 网络未附着 / PDP 未激活，不能发也不能入队 |

`0` 跟 `OK`；非 0 跟 `ERROR`（`SMSSYNC` 失败行格式见 [第 9 节](#9-atsmssync)）。最终投递结果还可能由短信回调异步上报（`SEND_DONE` / `SEND_FAILED`），本指令不把对端回执当 AT 应答。

---

## 4. AT+SMS {#4-atsms}

读写十路通道号码。只改持久化，不立刻发短信。

### 4.1 测试

```lua
AT+SMS=?
```

```lua
+SMS: (id,"phone_number")
id: 1-10 -> cfg index 0..9; 99 = all channels (only with "")
set: AT+SMS=<id>,"<num>"
clear one: AT+SMS=<id>,""
clear all: AT+SMS=99,""
query one: AT+SMS=<id> or AT+SMS=<id>?
query all: AT+SMS=99 or AT+SMS=99?

OK
```

### 4.2 查询一路

```lua
AT+SMS=<id>
```

或 `AT+SMS=<id>?`。`<id>` 为 1～10。

```lua
+SMS: <id>,"<number>"

OK
```

未配置时号码可能是空串 `""`。

### 4.3 查询全部

```lua
AT+SMS=99
```

或 `AT+SMS=99?`。连续最多 10 行，再 `OK`：

```lua
+SMS: 1,"13800138000"
+SMS: 2,""
…

OK
```

回包拼爆（内部约 896 字节）→ `"error rsp"`。

### 4.4 设置一路 / 清空

```lua
AT+SMS=<id>,"<number>"
```

| 参数 | 说明 |
| --- | --- |
| `<id>` | 1～10 写一路；99 只能配空串 |
| `<number>` | 字符串。空串清空该路。长度 ≥ 32 → `"error phone_len"` |

`AT+SMS=99,"138…"` → `"error all_need_empty"`。读盘失败 `"error read"`，写盘 `"error save"`。形态不对 `"error param"`。

**成功（一路）**

```lua
+SMS: <id>,"<number>"

OK
```

**成功（清空全部）**

```lua
+SMS: 99,""

OK
```

### 4.5 示例

```lua
AT+SMS=1,"13800138000"
+SMS: 1,"13800138000"

OK

AT+SMS=1?
+SMS: 1,"13800138000"

OK

AT+SMS=1,""
+SMS: 1,""

OK
```

---

## 5. AT+SMSR {#5-atsmsr}

按 **SIM 槽号** 读一条。无查询形态。

### 5.1 测试

```lua
AT+SMSR=?
```

```lua
+SMSR: (index)
SIM storage: read one record by index (1..N)
AT+SMSR=<index>

OK
```

### 5.2 设置（兼读取）

```lua
AT+SMSR=<index>
```

`<index>` 必须是 1～255 的整数。

**成功**

```lua
+SMSR: <index>,<status>,"<addr>","<msg>"

OK
```

| 字段 | 说明 |
| --- | --- |
| `<index>` | 卡上回的槽号（通常等于你请求的） |
| `<status>` | 见 [3.2](#32-sim-存储-index) |
| `<addr>` | 对端号码，最长约 20 |
| `<msg>` | 正文，最长约 280 |

**失败 reason**：`param`（缺参 / 不是数字）、`index`（0 或大于 255）、`read`（无此槽、卡忙、未插卡等）。

### 5.3 示例

```lua
AT+SMSR=1
+SMSR: 1,0,"13800138000","hello"

OK
```

---

## 6. AT+SMSL {#6-atsmsl}

列 SIM 存储。`<type>` 决定过滤。

### 6.1 测试

```lua
AT+SMSL=?
```

```lua
+SMSL: (type)
SIM storage list: 0=all, 1=read, 2=unread
AT+SMSL=<type>
note: read/unread filter only for SIM

OK
```

### 6.2 设置（兼列举）

```lua
AT+SMSL=<type>
```

| `<type>` | 过滤 |
| --- | --- |
| `0` | 全部 |
| `1` | 已读（status=1） |
| `2` | 未读（status=0） |
| 其它 | `"error type"` |

**成功** 零行或多行，最后 `OK`。空存储也是只有 `OK`（没有 `+SMSL` 行也算成功）：

```lua
+SMSL: <index>,<status>,"<addr>","<msg>"
+SMSL: …

OK
```

最多 64 条。内存不够 `"error mem"`，列举失败 `"error list"`，拼包失败 `"error rsp"`。

### 6.3 示例

```lua
AT+SMSL=2
+SMSL: 1,0,"13800138000","hello"

OK
```

---

## 7. AT+SMSD {#7-atsmsd}

删 SIM 存储。

### 7.1 测试

```lua
AT+SMSD=?
```

```lua
+SMSD: (index)
SIM storage: 0=delete all; 1..255=delete one slot
AT+SMSD=<index>

OK
```

### 7.2 设置

```lua
AT+SMSD=<index>
```

| `<index>` | 动作 | 失败 reason |
| --- | --- | --- |
| `0` | 删全部 | `del_all` |
| `1`～`255` | 删一条 | `del`（无此槽等） |
| 其它 | — | `index` |

**成功**

```lua
+SMSD: <index>

OK
```

```lua
AT+SMSD=1
+SMSD: 1

OK

AT+SMSD=0
+SMSD: 0

OK
```

不要写 `AT+SMSD=99`：99 既不是 0 也不是合法单槽语义，会 `"error index"`（若解析成 99）。

---

## 8. AT+SMSWRITE {#8-atsmswrite}

用通道 `<id>` 里已保存的号码 **异步** 发短信。正文为 TAILRAW，**允许空**。本条只表示是否成功推给发送层；送达看回调。

### 8.1 测试

```lua
AT+SMSWRITE=?
```

```lua
+SMSWRITE: (id,<TAILRAW>)
id: 1-10 -> channel[0..]，异步发送
set only: AT+SMSWRITE=<id>,<payload>
<TAILRAW>: 第一个逗号之后的原始字节流，最长 950 字节
发送结果由短信回调异步上报

OK
```

### 8.2 设置

```lua
AT+SMSWRITE=<id>,<payload>
```

| 参数 | 范围 | 说明 |
| --- | --- | --- |
| `<id>` | 1～10 | 通道。解析层就限制在此，99 进不来 |
| `<payload>` | 0～950 字节 | 第一个逗号之后到行结束。超过 `"error text_len"` |

**成功（入队）**

```lua
+SMSWRITE: 0

OK
```

**失败（发送码）**

```lua
+SMSWRITE: -100

ERROR
```

缺参 `"error param"`。通道号码为空常见 `-1`。未驻网 `-100`。

### 8.3 示例

```lua
AT+SMS=1,"13800138000"
+SMS: 1,"13800138000"

OK

AT+SMSWRITE=1,hello
+SMSWRITE: 0

OK
```

---

## 9. AT+SMSSYNC {#9-atsmssync}

指定号码 **同步** 发送：等到发送接口返回。号码不是通道表里的 id。

### 9.1 测试

```lua
AT+SMSSYNC=?
```

```lua
+SMSSYNC: ("number",<TAILRAW>)
set only: AT+SMSSYNC="<number>",<payload>
<TAILRAW>: 第一个逗号之后的原始字节流，最长 950 字节

OK
```

### 9.2 设置

```lua
AT+SMSSYNC="<da>",<payload>
```

| 参数 | 说明 |
| --- | --- |
| `<da>` | 目标号码，非空。空串 `"error da"`。长度 ≥ 21 → `"error da_len"` |
| `<payload>` | TAILRAW，0～950 字节。超长 `"error text_len"` |

**成功**

```lua
+SMSSYNC: 0,<mr>

OK
```

`<mr>` 为本次短信参考号（0～255）。发送码非 0 时：

```lua
+: <code>

ERROR
```

注意：同步失败时前缀是 **`+:`**（命令名为空），不是 `+SMSSYNC:`。以机内回文为准。入参错误仍是 `+SMSSYNC: "error …"`。

同步会占住这条 AT 处理，长短信或多分片时口会停一阵。

### 9.3 示例

```lua
AT+SMSSYNC="13800138000",hello
+SMSSYNC: 0,3

OK
```

---

## 10. AT+SMSASYNC {#10-atsmsasync}

指定号码 **异步** 入队。结果通过短信回调上报（`SEND_DONE` / `SEND_FAILED`）。

### 10.1 测试

```lua
AT+SMSASYNC=?
```

```lua
+SMSASYNC: ("number",<TAILRAW>)
set only: AT+SMSASYNC="<number>",<payload>
<TAILRAW> 最长 950 字节；结果通过短信回调异步上报

OK
```

### 10.2 设置

```lua
AT+SMSASYNC="<da>",<payload>
```

号码规则与 `SMSSYNC` 相同（`da` / `da_len`）。

**成功（已入队）**

```lua
+SMSASYNC: 0

OK
```

**失败（发送码）**

```lua
+SMSASYNC: -4

ERROR
```

未附着时入队前就会 `-100`，不会先 OK 再失败。

### 10.3 对照

| | `SMSWRITE` | `SMSSYNC` | `SMSASYNC` |
| --- | --- | --- | --- |
| 对端 | 通道 1～10 的号码 | 本条指定 | 本条指定 |
| 等待 | 入队即返回 | 等到发送返回 | 入队即返回 |
| 成功行 | `+SMSWRITE: 0` | `+SMSSYNC: 0,<mr>` | `+SMSASYNC: 0` |
| 空正文 | 可以 | 可以 | 可以 |

---

## 11. AT+SMSTMPH {#11-atsmstmph}

读写 `[sms] forward_msg_template`。载荷规则与 [`AT+IOTMPLH` 第三段](io.md#11-atiotmplh) 相同： **引号内 hex**，解码后写入。解码后最长 **255** 字节（比 IO 模板的 256 少 1，留给结尾空字符）。

仅 `forward_msg_mode=3` 时转发才用这份模板。占位符：`<#SENDER>`、`<#SMS_MSG>`。**没有 `<#TEXT>`。** 映射只受 `[maping] all` 约束。

### 11.1 测试

```lua
AT+SMSTMPH=?
```

```lua
+SMSTMPH: "<hex_str>"
hex 须双引号包裹，解码后最长 255 字节写入 forward_msg_template
查询: AT+SMSTMPH 或 AT+SMSTMPH?
设置: AT+SMSTMPH="AABB..."

OK
```

### 11.2 查询

```lua
AT+SMSTMPH
```

或 `AT+SMSTMPH?`。把已存模板按字节再编成大写 hex：

```lua
+SMSTMPH: "3C2353454E4445523E"

OK
```

读盘失败 `"error read"`。

### 11.3 设置

```lua
AT+SMSTMPH="<hex>"
```

不是 hex 段 → **105**。解码后超过 255 → **108**。读盘 `"error read"`，写盘 `"error write"`。空 hex 表示清空模板。

**成功** 回显 **解码后字节数**：

```lua
+SMSTMPH: <decoded_len>

OK
```

### 11.4 示例

模板明文 `<#SENDER>` 的 ASCII hex：

```lua
AT+SMSTMPH="3C2353454E4445523E"
+SMSTMPH: 9

OK

AT+SMSTMPH?
+SMSTMPH: "3C2353454E4445523E"

OK
```

---

## 12. AT+SMSCFG {#12-atsmscfg}

按 key 读写短信转发三项。对应 `[sms]` 的 `forward_en` / 转发路由 / `forward_msg_mode`。**没有** 在本指令里改 `forward_msg_template`（用 `SMSTMPH`）。

### 12.1 测试

```lua
AT+SMSCFG=?
```

```lua
+SMSCFG: ("key"[,<TAILRAW>])
key: forward_en | forward_route | forward_msg_mode
query all: AT+SMSCFG?
query: AT+SMSCFG="key" or AT+SMSCFG="key"?
set: AT+SMSCFG="key",<TAILRAW>

OK
```

### 12.2 查询全部

```lua
AT+SMSCFG?
```

或无参 `AT+SMSCFG`（与 `?` 等价）。

```lua
+SMSCFG: "forward_en",0
+SMSCFG: "forward_route","6[1]"
+SMSCFG: "forward_msg_mode",1

OK
```

读盘 `"error read"`，申请缓冲失败 `"error malloc"`，格式化失败 `"error format"`，拼爆 `"error overflow"`。

### 12.3 查询单项

第二段省略或长度为 0：

```lua
AT+SMSCFG="forward_en"
```

```lua
+SMSCFG: "forward_en",1

OK
```

未知 key → **104**。缺 key / 不是字符串 → **105**。

### 12.4 设置

```lua
AT+SMSCFG="<key>",<value>
```

| key | value 形态 | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `forward_en` | 十进制文本 | 只认 `0` / `1`（可带空白） | 收到短信是否转到 RTU 输出 |
| `forward_route` | **必须带双引号** 的路由串 | 与 [rtu 路由](../api/module/rtu.md#8-路由字符串) 相同；`""` 清空 | 例如 `,"1\|2"` 或 `,"6[1]"`。无引号 → **105**。非法串 → **109** |
| `forward_msg_mode` | 十进制文本 | **1～3**（写 0 失败） | `1` JSON；`2` AT 行；`3` 模板 + 占位符 |

`forward_route` 的 TAILRAW 整体须是 `"…"`：第一个字符和最后一个字符都是 `"`，中间才交给路由解析。不要写成不带引号的 `6[1]`。

写盘失败 `"error write"`。

**成功** 与单项查询同形（路由回显已规范化的路由串）。

### 12.5 示例

```lua
AT+SMSCFG="forward_en",1
+SMSCFG: "forward_en",1

OK

AT+SMSCFG="forward_msg_mode",3
+SMSCFG: "forward_msg_mode",3

OK

AT+SMSCFG="forward_route","6[1]"
+SMSCFG: "forward_route","6[1]"

OK
```

---

## 13. 错误一览

### 13.1 短 reason（`+CMD: "error <reason>"` + `ERROR`）

| reason | 出现指令 | 含义 |
| --- | --- | --- |
| `param` | SMS / SMSR / SMSL / SMSD / SMSWRITE / SMSSYNC / SMSASYNC | 个数或类型不对 |
| `id` | SMS | 不是 1～10 也不是 99 |
| `all_need_empty` | SMS | `id=99` 却给了非空号码 |
| `phone_len` | SMS | 号码 ≥ 32 |
| `read` | SMS / SMSR / SMSTMPH 查询 / SMSCFG | 读配置或读 SIM 槽失败 |
| `save` | SMS | 写通道号码失败 |
| `write` | SMSTMPH / SMSCFG | 写配置失败 |
| `rsp` | SMS 全查 / SMSL | 回包缓冲不够 |
| `index` | SMSR / SMSD | 槽号不在约定范围 |
| `type` | SMSL | 不是 0/1/2 |
| `mem` | SMSL | 申请列举缓冲失败 |
| `list` | SMSL | SIM 列举失败 |
| `del` | SMSD | 删一条失败 |
| `del_all` | SMSD | 删全部失败 |
| `text_len` | 三条发送 | 正文超过 950 或拷贝失败 |
| `da` | SMSSYNC / SMSASYNC | 号码空 |
| `da_len` | SMSSYNC / SMSASYNC | 号码 ≥ 21 |
| `malloc` / `format` / `overflow` | SMSCFG 全查 | 组回包失败 |

### 13.2 `+CME ERROR`

| 码 | 出现指令 | 可能原因 |
| --- | --- | --- |
| 104 | SMSCFG | key 不是三名字之一 |
| 105 | SMSTMPH 设置 / SMSCFG | 不是 hex、`forward_en` 不是 0/1、`forward_msg_mode` 不是 1～3、路由 TAILRAW 没包引号 |
| 108 | SMSTMPH | 解码后超过 255 字节 |
| 109 | SMSCFG | `forward_route` 路由串非法 |

### 13.3 发送码

见 [3.3](#33-发送结果码)。出现在 `+SMSWRITE` / `+SMSASYNC` / `+SMSSYNC`（失败时可能是 `+:`）。

---

## 14. 联调顺序

先插卡、射频允许（`CFUN=1`）、驻网后再发。未附着时发送码 **-100**。

```lua
AT+SMS=1,"13800138000"
+SMS: 1,"13800138000"

OK

AT+SMSWRITE=1,ping
+SMSWRITE: 0

OK

AT+SMSSYNC="13800138000",ping
+SMSSYNC: 0,1

OK

AT+SMSL=0

OK
```

收信转发：`AT+SMSCFG="forward_en",1`，配 `forward_route` 与 `forward_msg_mode`；mode=3 再 `AT+SMSTMPH="…"`。十路里至少一路有号码。改完转发项后按产品流程加载配置 / 复位再测收信。

SIM 维护：`AT+SMSL=2` 看未读 → `AT+SMSR=<index>` → `AT+SMSD=<index>`。清空卡用 `AT+SMSD=0`，不要用 99。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：SMS/SMSR/SMSL/SMSD/SMSWRITE/SMSSYNC/SMSASYNC/SMSTMPH/SMSCFG；通道 1～10 与 99；SIM index 0/1～255；发送码与 CME/reason |
