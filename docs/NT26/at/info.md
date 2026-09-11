#  标识与版本

**文档版本** `1.0.0`

握手、读版本、读模组/SIM 标识。行格式、两种失败风格见 [convention.md](convention.md)。本篇多数是无参查询；`CHIPID` / `ATMODE` 带参数。

`IMEI` / `ICCID` / `IMSI` / `SIMINFO` / `CHIPID` 失败走 `+CME ERROR`。`ATMODE` 走短 reason。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT / ATI](#3-at--ati)
- [4. AT+VERSION](#4-atversion)
- [5. AT+CGMR](#5-atcgmr)
- [6. AT+IMEI](#6-atimei)
- [7. AT+ICCID](#7-aticcid)
- [8. AT+IMSI](#8-atimsi)
- [9. AT+SIMINFO](#9-atsiminfo)
- [10. AT+CHIPID](#10-atchipid)
- [11. AT+CMEERR](#11-atcmeerr)
- [12. AT+ATMODE](#12-atatmode)
- [13. 错误一览](#13-错误一览)
- [14. 联调顺序](#14-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 无参查询 | `AT+XXX` 与 `AT+XXX?` 等价（本篇标识类） |
| `ATI` | 没有 `+`，出厂三行：厂商、应用版本名、编译时间，再 `OK` |
| `SIMINFO` | 会向平台拉卡信息，最长约 5 s；失败仍可能回 `OK`（`+CME ERROR` 在前） |
| `ATMODE` | **只在 UART AT 口**有效；切到 1 后，本口后续字节交给原厂引擎，应用 `AT+` 不再解析 |

Lua 对照：`require("info")` 读的是同一套标识，不是另一套编号。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT` | 无 | `AT` / `AT?` | 无 | 握手，只回 `OK` |
| `ATI` | 无 | `ATI` / `ATI?` | 无 | 厂商标识三行 |
| `AT+VERSION` | 无 | `AT+VERSION` / `?` | 无 | SDK / 硬件 / 应用版本多行 |
| `AT+CGMR` | 无 | `AT+CGMR` / `?` | 无 | 一行应用版本名 |
| `AT+IMEI` | 无 | `AT+IMEI` / `?` | 无 | IMEI |
| `AT+ICCID` | 无 | `AT+ICCID` / `?` | 无 | SIM ICCID |
| `AT+IMSI` | 无 | `AT+IMSI` / `?` | 无 | IMSI |
| `AT+SIMINFO` | 无 | `AT+SIMINFO` / `?` | 无 | 平台卡套餐信息 |
| `AT+CHIPID` | `=?` | 无无参查询 | `<sel>` | 芯片 ID / 修订 / 全 ID |
| `AT+CMEERR` | `=?` | `AT+CMEERR` / `?` | 无 | 列出自定义 CME 码 |
| `AT+ATMODE` | `=?` | `AT+ATMODE?` | `<0\|1>` | 本 UART 口切应用/原厂引擎 |

没有「执行命令」形态的空 `AT+VERSION=`。

---

## 3. AT / ATI {#3-at--ati}

### 3.1 AT

**命令**

```lua
AT
```

或 `AT?`。

**应答**

```lua
OK
```

不回 `+` 前缀。用来确认口通、回显与行结束是否配对。

### 3.2 ATI

**命令**

```lua
ATI
```

出厂未改厂商串时：

```lua
doiot
<应用版本名>
<编译时间>

OK
```

厂商串可被产线/整机配置改写；改过之后三行内容以机内保存的为准。读失败只回 `ERROR`（无 `+CME ERROR`）。

---

## 4. AT+VERSION {#4-atversion}

**命令**

```lua
AT+VERSION
```

或 `AT+VERSION?`。

**应答**

```lua
+VERSION: 
SDK Version:<sdk>
EVB Version:<evb>
Compiled:<编译时间戳>
APP Version:<应用版本名>
Build Number:<构建号>
Build Time:<应用构建时间>

OK
```

字段均为文本，长度随镜像变。`APP Version` 与 `AT+CGMR`、出厂 `ATI` 第二行是同一套应用版本名。

无失败分支：查询总会 `OK`。

---

## 5. AT+CGMR {#5-atcgmr}

**命令**

```lua
AT+CGMR
```

**应答**

```lua
+CGMR: <应用版本名>

OK
```

只要一行，适合脚本抠版本。无失败分支。

---

## 6. AT+IMEI {#6-atimei}

**命令**

```lua
AT+IMEI
```

**应答（成功）**

```lua
+IMEI: "<15位数字>"

OK
```

**失败** `+CME ERROR: <n>`，常见：

| 码 | 可能原因 |
| --- | --- |
| 150 | 读 IMEI 失败（未归到更细码） |
| 143 | SIM 未插入（底层把未插卡映射过来时） |
| 144 | 协议栈未上电（例如 `CFUN=0`） |
| 145 | SIM 忙 |
| 146 | 查询超时 |
| 147 | SIM 响应异常 |
| 148 | 操作不支持 |
| 105 | 无效参数 |

本指令不写 IMEI。产测写号不在本手册。

---

## 7. AT+ICCID {#7-aticcid}

**命令**

```lua
AT+ICCID
```

**应答（成功）**

```lua
+ICCID: "<20位左右数字>"

OK
```

失败 `+CME ERROR: <n>`：未插卡 **143**，未上电 **144**，通用读失败 **131**，其余同 IMEI 的忙/超时/异常码。

必须已插卡且射频侧允许读 SIM。`CFUN=0` 时常见 144。

---

## 8. AT+IMSI {#8-atimsi}

**命令**

```lua
AT+IMSI
```

**应答（成功）**

```lua
+IMSI: "<15位左右数字>"

OK
```

失败风格同 ICCID。通用读失败码是 **149**。

---

## 9. AT+SIMINFO {#9-atsiminfo}

向平台拉该卡的套餐/状态（需要驻网）。超时约 **5 s**。

**命令**

```lua
AT+SIMINFO
```

**应答（成功）** 多行，字段名固定：

```lua
+SIMINFO: 
code: <整数>
iccid: "<…>"
imsi: "<…>"
imei: "<…>"
card_status: "<…>"
card_phone: "<…>"
carrier: "<…>"
start_date: "<…>"
expire_date: "<…>"
silence_date: "<…>"
flow_specification: "<…>"
remaining_volume: "<…>"
use_data_volume: "<…>"
testing_expire_date: "<…>"

OK
```

空字符串表示平台没给该字段。`code` 是平台业务码，不是 CME。

**失败**（注意末尾仍是 `OK`）：

```lua
+CME ERROR: <n>

OK
```

| 码 | 可能原因 |
| --- | --- |
| 105 | 参数无效 |
| 113 | HTTP 失败（未驻网、DNS、平台不可达） |
| 114 | 平台 JSON 无法解析 |
| 115 | 请求超时 |
| 116 | 本地 ICCID 都读不到，无法组请求 |

不要在没网时当「读 ICCID」用；只读卡号用 `AT+ICCID`。

---

## 10. AT+CHIPID {#10-atchipid}

### 10.1 测试

```lua
AT+CHIPID=?
```

```lua
+CHIPID: sel(0:chipid,1:revid,2:fullid)

OK
```

### 10.2 设置（兼查询）

没有 `AT+CHIPID?`。必须带选择子：

```lua
AT+CHIPID=<sel>
```

| `<sel>` | 含义 |
| --- | --- |
| 0 | 芯片 ID |
| 1 | 修订 ID |
| 2 | 全 ID |

**应答（成功）**

```lua
+CHIPID: <sel>,0x<8位十六进制>

OK
```

参数不是 0～2、或读取失败：`+CME ERROR: 131`（与 ICCID 通用失败码相同，不要按「没卡」理解）。

---

## 11. AT+CMEERR {#11-atcmeerr}

### 11.1 测试

```lua
AT+CMEERR=?
```

```lua
+CMEERR: query all custom +CME ERROR codes (id,"comment" per line)

OK
```

### 11.2 查询

```lua
AT+CMEERR
```

或 `AT+CMEERR?`。

```lua
+CMEERR:
101,"NTP请求超时"
102,"NTP失败"
…
156,"DNS CID状态查询失败"

OK
```

完整表见 [convention.md 第 6 节](convention.md#6-自定义-cme-error)。机内表以本指令为准。

---

## 12. AT+ATMODE {#12-atatmode}

把**当前这条 UART AT 口**在「应用引擎」和「原厂内置引擎」之间切换。USB AT、Socket/MQTT 虚拟口会回 `"error need uart channel"`。

切到 `1` 之后，本口不再走应用 `AT+SOCK` 等；要回来必须在原厂引擎里再发切回，或复位（出厂默认应用引擎）。

### 12.1 测试

```lua
AT+ATMODE=?
```

```lua
+ATMODE: (0:app AT engine, 1:SDK built-in AT engine)

OK
```

### 12.2 查询

只支持 `AT+ATMODE?`，不支持无参 `AT+ATMODE`。

```lua
AT+ATMODE?
```

```lua
+ATMODE: <0或1>

OK
```

### 12.3 设置

```lua
AT+ATMODE=<mode>
```

| `<mode>` | 含义 |
| --- | --- |
| 0 | 应用 AT 引擎（本手册全部指令） |
| 1 | 原厂内置 AT 引擎 |

**应答（成功）** 回显刚设置的值，立刻生效。

```lua
+ATMODE: 1

OK
```

**失败** `+ATMODE: "error <reason>"` + `ERROR`。

| reason | 可能原因 |
| --- | --- |
| `need uart channel` | 不是物理 UART AT 口 |
| `param` | 缺参数或不是整数 |
| `use 0 or 1` | 不是 0/1 |
| `FEATURE_AT_ENABLE off` | 本镜像未打开原厂引擎 |
| `bridge not ready` | 桥接未就绪 |

`virat.exec` 走的是应用已注册指令；`virat.ril_exec` 才是原厂通道。不要用本指令代替脚本里的 `virat`。

---

## 13. 错误一览

| 风格 | 指令 |
| --- | --- |
| 只 `OK` / 只 `ERROR` | `AT`、`ATI`、`VERSION`、`CGMR`、`CMEERR` |
| `+CME ERROR: n` | `IMEI`、`ICCID`、`IMSI`、`CHIPID` |
| `+CME ERROR` 后仍 `OK` | `SIMINFO` |
| `"error <reason>"` + `ERROR` | `ATMODE` |

SIM 未插 / 未上电优先看 143 / 144。完整 CME 表见 convention。

---

## 14. 联调顺序

```lua
AT
OK

ATI
doiot
<版本>
<时间>

OK

AT+VERSION
+VERSION: 
…

OK

AT+IMEI
+IMEI: "86…………"

OK

AT+ICCID
+ICCID: "8986…………"

OK
```

先 `AT` 确认口，再 `VERSION`/`CGMR` 对镜像，再读卡号。`SIMINFO` 放到已驻网之后。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：握手、版本、IMEI/ICCID/IMSI/SIMINFO/CHIPID、CMEERR、ATMODE |
