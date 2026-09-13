#  OTA / MCUOTA

**文档版本** `1.0.0`

两条升级入口：

| 指令 | 升什么 |
| --- | --- |
| `AT+OTA` | **模组**差分包：按包名校验当前版本，或直接给 URL；同步等到流程结束（约 60 s） |
| `AT+MCUOTA` | **外挂 MCU** 槽位：向平台查版本 / 按 Range 拉分片到 RAM，再按 `raw` / `at` / `pkt` 吐给主机 |

行格式见 [convention.md](convention.md)。`OTA` 走短 reason。`MCUOTA` 失败是另一套：`+MCUOTA: <index>,"<action>","error",<code>,"<msg>"` + `ERROR`。

脚本包 AB 槽升级走 [script.md](script.md)，不是本篇。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+OTA](#3-atota)
- [4. AT+MCUOTA](#4-atmcuota)
- [5. 错误一览](#5-错误一览)
- [6. 联调顺序](#6-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| `OTA` 失败 | `+OTA: "error <reason>"` + `ERROR` |
| `MCUOTA` 失败 | 见 [4.5](#45-失败格式)；三种成功输出形态都走同一套失败 |
| `MCUOTA` 槽位 | `<index>` ≥ 1（解析侧 1～99） |
| `MCUOTA` 分片 | 单次 `length` **1～32768** 字节 |
| 阻塞 | `OTA` 会占住本条 AT 直到成功、失败或约 60 s 超时 |
| 成功后 | 模组 OTA 成功后设备会按升级流程复位应用差分 |

本篇只有 `OTA` / `MCUOTA`。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+OTA` | `=?` | 无 | `<1\|2>,"<arg>"` | 模组差分升级 |
| `AT+MCUOTA` | `=?` | 无 | `index,"getinfo"[,ver]` 或 `index,"download",…` | MCU 查信息 / 拉分片 |

没有无参查询。不要写 `AT+OTA?`。

---

## 3. AT+OTA {#3-atota}

同步启动一次模组 OTA：下载差分、写入、校验。成功回 `OK` 后设备会继续复位应用。同一时刻只能跑一轮。

### 3.1 测试命令

```lua
AT+OTA=?
```

```lua
+OTA: (mode,"arg")
mode=1: AT+OTA=1,"edit_name" (parse+check version, use default URL by IMEI)
mode=2: AT+OTA=2,"url"  (use custom URL directly)

OK
```

### 3.2 设置

```lua
AT+OTA=<mode>,"<arg>"
```

| `<mode>` | `<arg>` | 行为 |
| --- | --- | --- |
| `1` | 差分包文件名 | 解析包名，**包名里的当前版本必须等于本机正在跑的版本**，再按本机 IMEI 拼默认下载地址 |
| `2` | 完整 URL | 不再解析包名，直接拉该地址。URL 最长 **127** 字节 |

`<arg>` 不能空。`mode` 只能是 1 或 2。

**mode=1 包名**

去可选后缀 `.bin` 之后，必须能拆成：

```lua
<型号>-<当前版本>_<目标版本>-diff-<YYYYMMDD>
```

| 段 | 规则 |
| --- | --- |
| 型号 | 非空，最后一段版本前用 `-` 切开 |
| 当前版本 / 目标版本 | 带点的版本串（例如 `1.0.0`），不能以点开头或结尾 |
| `-diff-` | 固定分隔 |
| 日期 | 正好 8 位数字 |

例：`NT26-PRO-RTU-1.0.0_1.0.1-diff-20260424` 或同名加 `.bin`。当前版本段必须与模组 `AT+CGMR` / 应用版本一致，否则 `"error version"`。解析失败 → `"error name"`。

mode=1 使用的默认地址形态：

```lua
http://5giot.cn/prod-api/otaDownload/range?imei=<本机IMEI>
```

**应答（成功）**

```lua
+OTA: <mode>,0

OK
```

第二字段为 `0` 表示启动并等到流程结束为成功。随后设备会复位。

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 少于 2 参，或 mode 不是数字、arg 不是字符串 |
| `mode` | 不是 1 或 2 |
| `arg` | 字符串为空 |
| `name` | mode=1 包名拆不开 |
| `version` | 包名里的当前版本与本机不一致 |
| `url_len` | mode=2 的 URL ≥ 128 字节 |
| `start` | 已有一轮在跑、下载/写入/校验失败、或等待超时 |

### 3.3 示例

```lua
AT+OTA=1,"NT26-PRO-RTU-1.0.0_1.0.1-diff-20260424"
+OTA: 1,0

OK
```

自定义地址：

```lua
AT+OTA=2,"http://192.168.1.8/delta.par"
+OTA: 2,0

OK
```

包名版本对不上：

```lua
AT+OTA=1,"NT26-PRO-RTU-9.9.9_1.0.1-diff-20260424"
+OTA: "error version"

ERROR
```

---

## 4. AT+MCUOTA {#4-atmcuota}

按槽位向内置 range 服务查 MCU 固件，或拉一段到 RAM 后从**本条 AT 口**输出。数据不写模组内部 Flash，由主机 MCU 自己编程。

`<action>` 大小写不敏感：`getinfo` / `download`。`<index>` 从 1 起。

### 4.1 测试命令

```lua
AT+MCUOTA=?
```

```lua
+MCUOTA: <index>,"getinfo"[,"<version>"]
+MCUOTA: <index>,"download",<start>,<length>,"<resp_mode>"

getinfo:
  AT+MCUOTA=1,"getinfo"
    +MCUOTA: 1,"getinfo",<size>,"<version>"  then OK
  AT+MCUOTA=1,"getinfo","1.0.0"
    +MCUOTA: 1,"getinfo",<size>,"<version>",<0|1>  then OK (1=need update)

download resp_mode (string key, success only; fail always AT error):
  "raw"  : payload bytes only, no AT header/OK; length=actual got
  "at"   : \r\n+MCUOTA: i,"download","at",start,req,got\r\n<got bytes>\r\nOK\r\n  (read exactly got after header line)
  "pkt"  : binary frame only: magic MCU1(4D435531) + u16le N + N data + CRC16-Modbus(LE, over magic+len+data)

fail (all actions/modes):
  +MCUOTA: <index>,"<action>","error",<code>,"<msg>"  then ERROR

OK
```

### 4.2 查大小和版本

```lua
AT+MCUOTA=<index>,"getinfo"
```

**应答（成功）**

```lua
+MCUOTA: <index>,"getinfo",<size>,"<version>"

OK
```

| 字段 | 含义 |
| --- | --- |
| `<size>` | 远端固件总字节数 |
| `<version>` | 响应头里的 MCU 版本 |

该槽无文件或 HTTP 失败：走 [4.5](#45-失败格式)，不回这段 OK。

### 4.3 查是否需要升级

第三个参数为当前 MCU 版本（带引号）：

```lua
AT+MCUOTA=<index>,"getinfo","<local_ver>"
```

版本串最长 **31** 字节，不能空。后面不能再跟多余字段。

**应答（成功）**

```lua
+MCUOTA: <index>,"getinfo",<size>,"<version>",<need>

OK
```

`<need>`：`1` 本地版本与远端不同（要更新），`0` 相同。`<size>` / `<version>` 仍是**远端**固件。

该槽无固件（或平台报版本一致 / 无槽）：仍回 **OK**，且固定为：

```lua
+MCUOTA: <index>,"getinfo",0,"",0

OK
```

HTTP / 参数失败仍走失败格式。

### 4.4 下载分片

```lua
AT+MCUOTA=<index>,"download",<start>,<length>,"<resp_mode>"
```

| 参数 | 类型 | 范围 | 说明 |
| --- | --- | --- | --- |
| `<start>` | 整数 | ≥ 0 | 起始偏移 |
| `<length>` | 整数 | 1～32768 | 请求长度 |
| `<resp_mode>` | 字符串 | `raw` / `at` / `pkt`（大小写不敏感） | **仅成功时**的通道输出形态 |

`got` 以实际拉取为准，可能小于 `length`（末包或服务器少给）。`got==0` 当失败，不会走成功输出。

失败时**忽略** `resp_mode`，三种模式都只出 AT 错误行，不夹带二进制、不输出半帧。

#### 4.4.1 `raw` — 纯固件字节

成功：通道上**只有** `got` 字节固件，没有任何 `+MCUOTA` / `OK` / 换行前缀后缀。

主机应先 `getinfo` 拿总长，用 `start + got` 判断是否结束。

#### 4.4.2 `at` — AT 头 + 二进制 + OK

成功时严格三段，主机必须按 `got` 读二进制，**不要**靠扫描 `OK` 切包（固件里可能出现 `OK` 字节）：

1. ASCII 头行：

```lua
+MCUOTA: <index>,"download","at",<start>,<req>,<got>
```

`<req>` 即请求的 `length`。

2. 头行结束的 `\r\n` 之后，**正好** `got` 字节固件（可含 `0x00`）。
3. 再输出 `\r\nOK\r\n`。

解析：读到头行 → 取出 `got` → 再读 `got` 字节 → 再读 `\r\nOK\r\n`。

#### 4.4.3 `pkt` — 自描述二进制帧

成功：通道上**只有**下面整帧，无 AT 头、无 `OK`。

| 偏移 | 长度 | 说明 |
| --- | --- | --- |
| 0 | 4 | 魔数 `MCU1`（字节 `4D 43 55 31`） |
| 4 | 2 | 载荷长度 N，小端 uint16（只含固件，不含魔数/长度/CRC） |
| 6 | N | 固件数据 |
| 6+N | 2 | CRC16-Modbus（初值 `FFFF`、多项式 `A001`），范围是 `[0 .. 6+N-1]`（魔数+长度+数据），低字节在前 |

帧总长 = N + 8。先认魔数，再按长度读 N，再校验 CRC。

### 4.5 失败格式

所有 action、所有 `resp_mode` 共用：

```lua
+MCUOTA: <index>,"<action>","error",<code>,"<msg>"

ERROR
```

缺参时 `<index>` 可能为 `0`，`<action>` 可能为空串。`<code>` 为负整数；`<msg>` 为固定英文或参数说明。

| code | msg（默认） | 可能原因 |
| --- | --- | --- |
| -1 | `invalid param` | 槽位/动作/长度非法；或参数说明见下表 |
| -2 | `imei failed` | 读本机 IMEI 失败，拼不了默认 URL |
| -3 | `url failed` | URL 拼接失败 |
| -4 | `http failed` | DNS / 连接 / 超时等传输失败 |
| -5 | `http status` | HTTP 状态不是 200/206 |
| -6 | `no firmware` | 无固件版本信息；下载空包时 msg 可能为 `empty` |
| -7 | `size unknown` | 有固件但拿不到总大小 |
| -8 | `out of memory` | RAM 不够（含组 `pkt` 帧） |
| -9 | `no mcu file at slot` | 该 index 没有 MCU 文件 |
| -10 | `version same` | 平台认为版本一致、不提供下载（无本地版本的 `getinfo` 会当失败；带本地版本的 `getinfo` 则改走空结果 OK） |

`-1` 时 `<msg>` 还可能是参数说明（不是上表默认句）：

| msg | 可能原因 |
| --- | --- |
| `index,action` | 缺 index/action，或 index 小于 1，或 action 空 |
| `unknown action` | 不是 `getinfo` / `download` |
| `version` | 带版本的 getinfo：引号版本空或解析失败 |
| `extra` | 合法字段后面还有多余字节 |
| `missing start,length,resp_mode` | download 少了后半段 |
| `start,length,resp_mode` | 三段解析失败 |
| `resp_mode` | 不是 `raw`/`at`/`pkt` |
| `length` | 请求长度为 0 或大于 32768 |

### 4.6 示例

```lua
AT+MCUOTA=1,"getinfo"
+MCUOTA: 1,"getinfo",262144,"1.2.0"

OK

AT+MCUOTA=1,"getinfo","1.0.0"
+MCUOTA: 1,"getinfo",262144,"1.2.0",1

OK
```

`at` 模式（头行之后是 1024 字节二进制，文档里用注释标明）：

```lua
AT+MCUOTA=1,"download",0,1024,"at"
+MCUOTA: 1,"download","at",0,1024,1024
（此处正好 1024 字节固件）
OK
```

`raw` 成功时主机只收到固件字节。槽位无文件（不带本地版本）：

```lua
AT+MCUOTA=3,"getinfo"
+MCUOTA: 3,"getinfo","error",-9,"no mcu file at slot"

ERROR
```

---

## 5. 错误一览

### 5.1 OTA（短 reason）

`+OTA: "error <reason>"` + `ERROR`。

| reason | 含义 |
| --- | --- |
| `param` | 参数个数或类型不对 |
| `mode` | 不是 1/2 |
| `arg` | 第二参空串 |
| `name` | 包名无法解析 |
| `version` | 包名当前版本与本机不一致 |
| `url_len` | 自定义 URL 过长 |
| `start` | 启动或同步等待失败（忙、下载、校验、超时） |

自定义 CME 码里的 129（版本无变化）、132（MCU 下载失败）、133（禁止跨越大版本）供其它入口 / `AT+CMEERR` 对照，**本两条指令的失败行不走 `+CME ERROR`**。

### 5.2 MCUOTA

见 [4.5](#45-失败格式) 的 code / msg 全表。不要把 MCUOTA 失败理解成 `+MCUOTA: "error start"` 那种短 reason。

---

## 6. 联调顺序

1. 驻网完成，能出网。
2. 模组升级：`AT+CGMR` 记下当前版本 → `AT+OTA=1,"<与当前版本匹配的包名>"` → 等到 `OK` 后等复位。或 `mode=2` 指向已放好的差分 URL。
3. MCU 升级：`AT+MCUOTA=1,"getinfo"` 拿 `size` / `version` → 可选再带本地版本看 `need` → 按 `size` 循环 `download`。
4. 主机协议栈弱、怕和 AT 行搅在一起：用 `pkt`（CRC）或先 `getinfo` 再 `raw` 按长度读。能可靠解析头行时用 `at`，且必须按 `got` 读满。
5. 脚本包不要走本篇，用 [script.md](script.md)。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：OTA 两种 mode 与包名规则；MCUOTA getinfo/download 与 raw\|at\|pkt 三种成功输出；失败码与 msg 全表 |
