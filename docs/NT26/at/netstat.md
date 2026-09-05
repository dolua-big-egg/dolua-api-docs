# AT 网络状态与时间

**文档版本** `1.0.0`

读驻网、小区、链路是否可用，以及本地时钟 / 时区 / 是否已对过网时。复位与射频开关也在本篇。一次 NTP 对时见 [ntp.md](ntp.md)。行格式见 [convention.md](convention.md)。

本篇几乎都是查询。失败有的走 `+CME ERROR`，有的用「未知值 + OK」（`CSQ` / `CEREG` / `ISLINK`）。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+CSQ](#3-atcsq)
- [4. AT+MCC / AT+MNC](#4-atmcc--atmnc)
- [5. AT+CEREG](#5-atcereg)
- [6. AT+CGACT](#6-atcgact)
- [7. AT+CGI](#7-atcgi)
- [8. AT+ISLINK](#8-atislink)
- [9. AT+UTC / AT+TIMEZONE / AT+TIME](#9-atutc--attimezone--attime)
- [10. AT+NTS](#10-atnts)
- [11. AT+RESET](#11-atreset)
- [12. AT+CFUN](#12-atcfun)
- [13. 错误一览](#13-错误一览)
- [14. 联调顺序](#14-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 无参查询 | `AT+CSQ` 与 `AT+CSQ?` 等价（本篇查询类） |
| 未驻网 | `CSQ` 回 `99,99` 仍 `OK`；`MCC`/`MNC`/`CGI` 回 CME **140** |
| `RESET` | 先回 `+RESET`/`OK`，按入口延时后再复位，主机不会再收到后续字节 |

Lua：`require("info")` / `lp` 读的是同一套驻网与时间，不是另一套编号。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+CSQ` | 无 | `AT+CSQ` / `?` | 无 | 信号质量 |
| `AT+MCC` | 无 | 无参 | 无 | 服务小区 MCC（十进制） |
| `AT+MNC` | 无 | 无参 | 无 | 服务小区 MNC（十进制） |
| `AT+CEREG` | 无 | 无参 | 无 | EPS 注册状态 |
| `AT+CGACT` | 无 | 无参 | 无 | CID=1 的 PDP 是否激活 |
| `AT+CGI` | `=?` | 无参=服务小区 | `=1` 多小区 | Cell / TAC / 邻区 |
| `AT+ISLINK` | 无 | 无参 | 无 | 数据链路是否可用 |
| `AT+UTC` | 无 | 无参 | 无 | UTC 秒时间戳 |
| `AT+TIMEZONE` | `=?` | 无参=小时 | `=1` 分钟 | 时区 |
| `AT+TIME` | `=?` | 无参或 `=0` | 无真正设置 | 本地墙钟 |
| `AT+NTS` | `=?` | 无参 | 无 | 网时是否已同步 |
| `AT+RESET` | 无 | `AT+RESET` / `?` | 无 | 软复位 |
| `AT+CFUN` | `=?` | 无参 | `<0\|1>` | 射频/功能级 |

---

## 3. AT+CSQ {#3-atcsq}

```lua
AT+CSQ
```

```lua
+CSQ: <rssi>,99

OK
```

`<rssi>` 为平台信号质量整数。第二字段本平台**恒为 99**（误码未知）。读失败仍 `OK`，值为 `99,99`。

---

## 4. AT+MCC / AT+MNC {#4-atmcc--atmnc}

```lua
AT+MCC
+MCC: 460

OK

AT+MNC
+MNC: 0

OK
```

MCC 输出十进制（例如中国 460）。小区未就绪：`+CME ERROR: 140`。

---

## 5. AT+CEREG {#5-atcereg}

```lua
AT+CEREG
+CEREG: <state>

OK
```

`<state>` 为 EPS 注册状态整数（与常见 `+CEREG` 状态码同族）。读失败回 `0` 仍 `OK`，不要把它当成「一定未注册」的唯一依据，请同时看 `ISLINK` / `CGACT`。

本指令**不能**设置 URC 上报级别（没有 `AT+CEREG=2`）。

---

## 6. AT+CGACT {#6-atcgact}

只报 **CID 1**：

```lua
AT+CGACT
+CGACT: 1,<state>

OK
```

`<state>`：`1` 已激活，`0` 未激活或读失败。本指令不能激活/去激活 PDP。

---

## 7. AT+CGI {#7-atcgi}

### 7.1 测试

```lua
AT+CGI=?
```

```lua
+CGI: mode(0:serving,1:multi-cell)
AT+CGI / AT+CGI?
AT+CGI=1 : query multi-cell list

OK
```

### 7.2 服务小区（无参）

```lua
AT+CGI
```

或 `AT+CGI?`。

```lua
+CGI: "<cell_id_hex>","<tac_hex>"

OK
```

两个字段是十六进制文本（无 `0x` 前缀）。未就绪 CME **140**。

### 7.3 多小区

只有 `=1` 合法（`=0` 当非法参数，CME **105**）。

```lua
AT+CGI=1
```

第一行是条数，随后每小区一行：

```lua
+CGI: <count>
+CGI: <idx>,<is_serving>,<cell_info_valid>,"<cell_id_hex>","<tac_hex>",<mcc>,<mnc>,<snr>,<rsrp>,<rsrq>
…

OK
```

| 字段 | 含义 |
| --- | --- |
| `<idx>` | 从 0 起 |
| `<is_serving>` | 1 服务小区，0 邻区 |
| `<cell_info_valid>` | 1 该行小区信息有效 |
| `<snr>` / `<rsrp>` / `<rsrq>` | 有符号整数 |

---

## 8. AT+ISLINK {#8-atislink}

```lua
AT+ISLINK
+ISLINK: <0或1>

OK
```

`1`：数据链路可用（可以发 Socket/HTTP 等）。`0`：不可用或查询失败。总是 `OK`。

---

## 9. AT+UTC / AT+TIMEZONE / AT+TIME {#9-atutc--attimezone--attime}

未对时前这些数可能是开机默认，先看 `AT+NTS`。

### 9.1 UTC

```lua
AT+UTC
+UTC: "<秒>"

OK
```

无符号秒时间戳，带引号。总会 `OK`。

### 9.2 TIMEZONE

```lua
AT+TIMEZONE
+TIMEZONE: "<小时>"

OK

AT+TIMEZONE=1
+TIMEZONE: "<分钟>"

OK
```

无参 / `?`：整点小时（例如东八区 `8`）。`=1`：分钟（`480`）。其它设置值无输出。帮助 `AT+TIMEZONE=?`。

### 9.3 TIME

```lua
AT+TIME
+TIME: "YY-MM-DD HH:MM:SS"

OK
```

`AT+TIME?`、`AT+TIME=0` 与无参相同。`AT+TIME=<非0>`：

```lua
+TIME: 0

ERROR
```

年字段是两位年。

---

## 10. AT+NTS {#10-atnts}

```lua
AT+NTS
+NTS: <0或1>

OK
```

`1` 网络时间已同步，`0` 未同步。测试 `AT+NTS=?`。

---

## 11. AT+RESET {#11-atreset}

```lua
AT+RESET
```

或 `AT+RESET?`。

```lua
+RESET

OK
```

回完之后按入口等待再复位：UART 约 300 ms，Socket 约 1 s，MQTT 约 2 s（给应答发出去）。之后模组重启，会话断开。

---

## 12. AT+CFUN {#12-atcfun}

```lua
AT+CFUN=?
```

```lua
AT+CFUN
+CFUN: <0或1>

OK

AT+CFUN=0
+CFUN: 0

OK

AT+CFUN=1
+CFUN: 1

OK
```

`0` 关射频/最低功能，`1` 全功能。设置立刻下发。`CFUN=0` 后读 ICCID/IMSI 常见 CME **144**。注册表只接受 0/1；不要发 4 等其它值。

---

## 13. 错误一览

| 风格 | 指令 |
| --- | --- |
| 未知值仍 `OK` | `CSQ`（99,99）、`CEREG`（0）、`CGACT`/`ISLINK`（0） |
| CME 140 | `MCC`、`MNC`、`CGI` 小区未就绪 |
| CME 105 | `CGI` 参数不是 `1` |
| `+TIME: 0` + `ERROR` | `TIME` 非法格式选择 |
| 先 `OK` 再复位 | `RESET` |

---

## 14. 联调顺序

```lua
AT+CFUN?
+CFUN: 1

OK

AT+CSQ
+CSQ: 20,99

OK

AT+CEREG
+CEREG: 1

OK

AT+ISLINK
+ISLINK: 1

OK

AT+NTS
+NTS: 1

OK

AT+TIME
+TIME: "26-09-05 17:00:00"

OK
```

`ISLINK=1` 再发 Socket / HTTP / `SIMINFO` / `NTP`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：驻网状态、小区、时间、复位、CFUN |
