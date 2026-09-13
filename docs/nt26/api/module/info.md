# info

**文档版本** `1.1.0`

纯函数查询模块：本机身份、驻网/信号/小区、默认 APN、本机时钟。没有对象、没有回调。授时写钟走 [`ntp`](../network/ntp.md) / [`sys`](sys.md)，本模块只读（APN 和 `cfun` 除外）。

```lua
local info = require("info")
```

平台预加载模块，无需额外 `.lua` 文件。没插卡、没驻网时，不少接口是 `nil`、`99` 或 `-1`。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 身份](#61-身份)
  - [6.2 射频、驻网、信号](#62-射频驻网信号)
    - [`info.cfun`](#info-cfun)
    - [`info.csq`](#info-csq)
    - [`info.cereg`](#info-cereg)
    - [`info.islink`](#info-islink)
    - [`info.signal`](#info-signal)
  - [6.3 小区](#63-小区)
  - [6.4 APN](#64-apn)
  - [6.5 时间](#65-时间)
- [7. 返回表](#7-返回表)
- [8. `times` 格式](#8-times-格式)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

按需点名查询，没有 `open`：

1. 身份：`imei` / `imsi` / `iccid`。
2. 驻网：`cfun`、`cereg`、`islink`、`csq` / `signal`。
3. 小区：`serv_cell`、`mult_cell`。
4. 默认承载 APN（CID=1，写入协议栈 NVM）：`getapn` / `setapn` / `apn_factory_reset`。
5. 本机时间：`time` / `times` / `timestamp`；是否已授时：`time_ready` / `nitz_ready`。开机单调时钟：`tick` / `tick_ms`（与墙钟无关）。

`islink()` 返回的是整数 `1` / `0` / `-1`，**不是**布尔。Lua 里 `0` 为真，不要写 `if info.islink()`，应判断 `== 1`。

`cfun` 的 MIN / RF_OFF 会关射频，demo 只演示 GET。`setapn` 会改设备配置并落盘。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("info") → 查询 / setapn / cfun                  │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  info 模块                                               │
│  · 问协议栈：身份、CEREG、信号、小区、PDP、APN、CFUN     │
│  · 问本机钟：本地拆分时间、UTC 时间戳、NITZ 标志         │
│  · tick：开机计数，不问网络                              │
└────────────────────────────┬────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   模组 / SIM            默认 CID=1 承载           本机 RTC
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `imei` / `csq` / `cereg` / 小区 / APN / `cfun` 等 | 问协议栈，等到结果 | **否** | 整台 Lua 调度 |
| `time` / `timestamp*` / `time_ready` | 读本机钟与授时标志 | **否** | 通常较短 |
| `tick` / `tick_ms` | 读开机计数 | **否** | 极短 |

同一时刻多路 `info.*` 会排队（内部互斥），第二路等到第一路返回。`tick` / `tick_ms` 不参与这套排队。

---

## 3. 阻塞语义

查询 **不是** `rt.delay` 那种让出。返回前当前协程停住，其它 Lua 任务和 IO 回调都要等。协议栈忙时可能明显变慢。不要在 UART / MQTT / TCP 短回调里扫 `mult_cell` 或改 `cfun`。

`cfun(CFUN_MIN)` / `CFUN_RF_OFF` 会掉网，后续 MQTT/TCP 都会受影响。

---

## 4. 常量与枚举

### 4.1 `cfun` 方法

用于 `info.cfun(method)`。这是本模块的方法号，**不是** AT `+CFUN=` 的 0/1/4。

| 符号 | 值 | 含义 | 返回 |
| --- | --- | --- | --- |
| `info.CFUN_GET` | `0` | 查询当前功能级 | 成功 `true, cfun`（第二值才是协议栈的 0/1/4）；失败只 `false` |
| `info.CFUN_MIN` | `1` | 设为最小功能（对应 AT CFUN=0） | `true` / `false` |
| `info.CFUN_FULL` | `2` | 全功能（CFUN=1） | `true` / `false` |
| `info.CFUN_RF_OFF` | `3` | 关射频（CFUN=4） | `true` / `false` |

其它整数 **抛** `"invalid cfun method"`。

GET 成功时的第二返回值是协议栈功能级，常见：`0` 最小、`1` 全功能、`4` 飞行/关射频。不要和 `CFUN_GET=0` 搞混：方法 0 表示「查询」，查到的 `cfun` 也可能是 0。

### 4.2 APN 鉴权 `auth`

用于 `setapn` 第四参，以及 `getapn().auth`。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `info.APN_AUTH_NONE` | `0` | 不鉴权 |
| `info.APN_AUTH_PAP` | `1` | PAP |
| `info.APN_AUTH_CHAP` | `2` | CHAP |
| `info.APN_AUTH_CHAP_PAP` | `3` | 先 CHAP，失败再 PAP |

范围外的 `auth`：`setapn` 返回 `false`，不抛。

### 4.3 未挂到模块的返回值

`cereg` / `islink` / `csq` 的整数含义没有符号常量，完整对照见 [6.2](#62-射频驻网信号)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `method` | integer | `CFUN_*` |
| `apn` / `user` / `pass` | string | 可空串；超长则 `setapn` 失败 |
| `auth` | integer | `APN_AUTH_*` |
| `fmt` | string | `times` 的格式，见第 8 节 |

没有按真假解释的入参。`time_ready` / `nitz_ready` 返回布尔；`islink` / `csq` / `cereg` 返回整数。

`mult_cell` 里 `is_serving`、`cell_info_valid` 是布尔（`true`/`false`）。

---

## 6. 模块函数

全部在模块表上。除 `setapn` / `cfun` / `times` 外均无参。

---

### 6.1 身份

#### `info.iccid()` / `info.imei()` / `info.imsi()`

```lua
info.iccid()
info.imei()
info.imsi()
```

三个都是模组/卡上报的数字字符串，失败或空串当 `nil`。

| 接口 | 是什么 | 从哪来 | 没卡 / 失败 |
| --- | --- | --- | --- |
| `imei` | 国际移动设备识别码，标识 **模组** | 模组出厂号 | `nil` |
| `imsi` | 国际移动用户识别码，标识 **SIM 签约** | SIM | 没插卡或未读到：`nil` |
| `iccid` | SIM 卡集成电路卡号，标识 **这张卡** | SIM，固定 20 位数字 | 同上 |

IMEI 换机不变、换卡不变；IMSI/ICCID 换卡就变。业务上常用 IMEI 当设备 ID，ICCID 当卡号。

---

### 6.2 射频、驻网、信号

上电后几件事是分开的，不要用其中一个代替全部：

```
射频开着 (cfun 全功能)
    → 搜网、附着小区 (cereg = 1 或 5)
        → 默认承载 PDP 激活 (islink == 1)  → 才能 TCP/MQTT/NTP
信号好坏 (csq / signal) 只说明无线质量，搜网中也可能有 CSQ。
```

| 接口 | 问的是 | 典型「好了」 | 常见「还没有」 |
| --- | --- | --- | --- |
| `cfun(GET)` | 射频/协议栈功能级 | 第二返回值 `1`（全功能） | `0` 最小、`4` 关射频 |
| `cereg` | 是否已向网络 **注册**（EPS/CEREG） | `1` 本地 / `5` 漫游 | `2` 还在搜；`0`/`3`/`4` 未注册或被拒 |
| `islink` | 默认 CID=1 的 **PDP 是否激活** | `== 1` | `0`：已注册也可能还没激活；`-1` 读失败 |
| `csq` / `signal` | 无线质量 | CSQ 约 ≥10 能用，≥20 较好 | `99` 未知；数值高不等于已经 `islink==1` |

等上网：先等 `cereg` 为 1 或 5，再等 `islink() == 1`。只看 CSQ 会误判。可用 [`lp`](lp.md) 的 `wait_link` 把这套等待收掉。

---

#### `info.cfun(method)` {#info-cfun}

**调用模式**

```lua
info.cfun(info.CFUN_GET)
info.cfun(info.CFUN_MIN)
info.cfun(info.CFUN_FULL)
info.cfun(info.CFUN_RF_OFF)
```

| `method` | 成功 | 失败 |
| --- | --- | --- |
| `CFUN_GET` | `true, cfun` | 只 `false`（没有第二值） |
| 其余三个 | `true` | `false` |

缺参或非整数：**抛**。非法方法号：**抛** `"invalid cfun method"`。锁失败：`false`。

```lua
local ok, val = info.cfun(info.CFUN_GET)
if ok then
    -- val 是协议栈功能级
end
```

#### `info.csq()` {#info-csq}

```lua
info.csq()
```

**CSQ**（Channel Signal Quality）是 AT `+CSQ` 那套 **RSSI 档位**，不是 dBm 原值。协议栈把接收电平压成 `0`～`31` 一个整数，方便日志和阈值判断。

返回 **一个整数**。读失败或当前不可用：**99**（不是 `nil`）。没驻网、飞行模式、刚上电，经常是 99。

| 返回值 | 含义 | 大约对应 RSSI |
| --- | --- | --- |
| `0` | 极弱 | ≤ −113 dBm |
| `1` | 很弱 | −111 dBm |
| `2`～`30` | 线性档 | −109 dBm 起，每加 1 大约强 2 dB，到 `30` ≈ −53 dBm |
| `31` | 满格档 | ≥ −51 dBm |
| `99` | 未知 / 读失败 | 不要当「满格」 |

经验（仅供界面，不是硬指标）：

| CSQ | 大致观感 |
| --- | --- |
| `99` / `0`～`9` | 不可用或很差，数据容易失败 |
| `10`～`14` | 能附着，吞吐一般 |
| `15`～`19` | 可用 |
| `20`～`31` | 较好 |

`csq()` 和 `signal().csq` 是同一套数。要 SNR/RSRP/RSRQ 用 `signal()`。

```lua
local n = info.csq()
if n == 99 then
    -- 还没测到
elseif n >= 15 then
    -- 无线质量尚可
end
```

---

#### `info.cereg()` {#info-cereg}

```lua
info.cereg()
```

**CEREG** 是 LTE/NB 的 **EPS 网络注册状态**（对应 AT `+CEREG?` 的 `stat`）。问的是「有没有在蜂窝网上挂上号」，**不是**「有没有 IP」。只返回这一个 `state` 整数，不含 TAC、小区 ID（那些看 `serv_cell`）。

读失败：**-1**（不是 `nil`）。未挂到模块表，按下表判断：

| 值 | 名称 | 说明 |
| --- | --- | --- |
| `-1` | 查询失败 | 协议栈没答上，稍后重试 |
| `0` | 未注册 | 射频可能关着，或还没开始搜；也不是正在搜 |
| `1` | 已注册（本地） | 附着在归属网，业务上最常见的「驻上了」 |
| `2` | 正在搜网 / 尝试注册 | 上电后常见过渡态，请等，不要此时开 TCP |
| `3` | 注册被拒绝 | SIM、PLMN、限制或鉴权问题，空等 CSQ 没用 |
| `4` | 未知 | 状态无效，当未注册处理 |
| `5` | 已注册（漫游） | 和 `1` 一样已经挂上号，只是漫游 |

`1` 和 `5` 都能继续等 PDP。`2` 属于正常等待。`3` 要查卡和 APN，不是信号问题。

```lua
local st = info.cereg()
if st == 1 or st == 5 then
    -- 已注册，再看 islink
elseif st == 2 then
    -- 还在搜
end
```

---

#### `info.islink()` {#info-islink}

```lua
info.islink()
```

看 **默认承载 CID=1 的 PDP 是否已激活**。PDP（Packet Data Protocol）激活后模组才有网口/IP，TCP、MQTT、HTTP、NTP 才走得通。

它 **不是**：

- 不是 CEREG：可能已经 `cereg==1` 但 PDP 还没起来（APN 错、核心网慢）。
- 不是「任意 CID」：只问默认 CID=1。
- 不是布尔：返回整数。Lua 里 `0` 为真，**禁止** `if info.islink()`。

| 返回值 | 含义 | 脚本怎么用 |
| --- | --- | --- |
| `1` | 默认承载已激活 | 可以发起网络业务 |
| `0` | 未激活 | 再等，或检查 APN / `cereg` |
| `-1` | 查询失败 | 稍后重试，不要当成已掉线或已在线 |

```lua
if info.islink() == 1 then
    -- 已有默认承载
end
```

---

#### `info.signal()` {#info-signal}

```lua
info.signal()
```

一次取出当前服务小区的一组无线测量。失败 `nil`（例如协议栈没交出质量）。成功表：

| 字段 | 类型 | 范围 / 特殊值 | 是什么 |
| --- | --- | --- | --- |
| `csq` | integer | `0`～`31`，未知 `99` | 与 `info.csq()` 相同的 RSSI 档 |
| `snr` | integer | 约 −20～40，单位 **dB** | 信噪比，越大越干净 |
| `rsrp` | integer | 有效约 −17～97；**127** 无效 | LTE 参考信号接收功率的 **协议栈档位**，不是直接 dBm。档位大约对应 −156 dBm～−44 dBm |
| `rsrq` | integer | 有效约 −30～46；**127** 无效 | 参考信号接收质量档，大约对应 −34 dB～2.5 dB |

CSQ 看「响不响」；RSRP 看「小区参考信号有多强」；RSRQ/SNR 看「干不干净、有没有邻区干扰」。室内弱覆盖常见 CSQ 尚可但 RSRQ 很差。

`mult_cell` 里的 `rsrp`/`rsrq` 是另一路测量（邻区列表），单位按 dBm / dB 上报，不要和 `signal()` 的档位混着比绝对值。

---

### 6.3 小区

#### `info.serv_cell()`

```lua
info.serv_cell()
```

当前正在提供服务的那一个小区。失败或还没服务小区：`nil`。成功字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `mcc` | integer | 移动国家码，中国移动/联通/电信均为 `460` |
| `mnc` | integer | 移动网号，如 `00`/`02`/`04`/`07` 等（按运营商，以卡为准） |
| `tac` | integer | 跟踪区码（Tracking Area Code） |
| `cell_id` | integer | 小区标识（ECI / Cell ID） |
| `snr` | integer | 该小区信噪比，单位 dB |

`mcc`+`mnc` 标识 PLMN（运营商网络）。做定位/运维上报时带上 `tac`+`cell_id`。这里 **没有** RSRP/RSRQ，质量看 `signal()` 或 `mult_cell`。

#### `info.mult_cell()`

```lua
info.mult_cell()
```

服务小区 **加** 邻区测量列表。成功是一张表：`count` 为条数，`cells[1]` … `cells[count]` 为每一小区。失败或一条都没有：`nil`。最多 **21** 条（1 个服务小区 + 最多 20 个邻区）。扫邻区比 `serv_cell` 慢，不要在短回调里高频打。

每一项：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `is_serving` | **boolean** | `true` 当前服务小区，`false` 邻区 |
| `cell_info_valid` | **boolean** | `true` 则 PLMN/TAC/小区 ID 有效；`false` 时可能只有 rsrp 等测量值 |
| `mcc` `mnc` `tac` `cell_id` | integer | 同 `serv_cell`；`cell_info_valid==false` 时不要当有效 ID |
| `snr` | integer | 信噪比，dB |
| `rsrp` | integer | 参考信号接收功率，**dBm** |
| `rsrq` | integer | 参考信号接收质量，**dB** |

```lua
local cells = info.mult_cell()
if cells then
    for i = 1, cells.count do
        local c = cells[i]
        -- c.is_serving, c.rsrp, ...
    end
end
```

---

### 6.4 APN

读写 **默认 CID=1**，写入协议栈 NVM，重启仍在。不是临时 RAM。

#### `info.getapn()`

```lua
info.getapn()
```

读默认 CID=1 上正在用的接入点。失败 `nil`。成功：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `apn` | string | 接入点名，空串表示未配 / 空 APN |
| `user` | string | 鉴权用户名，可空 |
| `pass` | string | 鉴权密码，可空 |
| `auth` | integer | `0` NONE / `1` PAP / `2` CHAP / `3` CHAP+PAP，见 4.2 |

#### `info.setapn(apn [, user, pass [, auth]])`

**调用模式**

```lua
info.setapn(apn)
info.setapn(apn, user, pass)
info.setapn(apn, user, pass, auth)
```

| 写法 | 行为 |
| --- | --- |
| 只传 `apn` | 只改接入点名；`""` 表示空 APN |
| `apn, user, pass` | 写完整鉴权。省略 `auth`：有用户名或密码则 PAP，否则 NONE |
| 再加上 `auth` | 显式鉴权类型 |

**不接受** `setapn(apn, user)`（两个参数）：**抛** `"setapn(apn [, user, pass [, auth]])"`。零个参数同样抛这句。

`user` / `pass` 可以是 `nil`（当空串）。超长（APN 约 99 字节、用户名/密码 64 字节）或 `auth` 越界：`false`。

成功 `true`，协议栈拒绝或锁失败 `false`。

```lua
info.setapn("cmnet")
info.setapn("iot.apn", "user", "pass", info.APN_AUTH_CHAP)
```

#### `info.apn_factory_reset()`

```lua
info.apn_factory_reset()
```

默认 CID 恢复出厂：空 APN、无用户名密码、`auth=NONE`。`true` / `false`。

---

### 6.5 时间

`time` / `times` 是 **已应用时区的本地墙钟**。`timestamp` / `timestamp_ms` 是 **UTC Unix**。写钟用 `ntp.get(..., auto_set)` 或 `sys.set_ts`，不是本模块。

#### `info.time()`

```lua
info.time()
```

拆分表或 `nil`。字段见第 7 节。`weekday`：`0` 周日 … `6` 周六。

#### `info.times([fmt])`

**调用模式**

```lua
info.times()
info.times(fmt)
```

把当前 **本地墙钟** 格式化成一根字符串。读钟失败返回 `nil`。

| 参数 | 类型 | 必填 | 默认 |
| --- | --- | --- | --- |
| `fmt` | string | 否 | `"%Y-%m-%d %H:%M:%S"` |

`fmt` 不是 C 的 `strftime`，也不是 Lua `os.date`：只认 `%` 后面 **恰好一个** 字母，大小写敏感。完整占位、示例和写错对照见 [第 8 节](#8-times-格式)。

输出最长约 **80** 字节，超了截断。末尾单独一个 `%` 会被丢掉。

```lua
info.times()                      -- 默认：2026-09-04 14:05:07
info.times("%Y%m%d-%H%M%S")       -- 20260904-140507
info.times("%Y年%m月%d日 %H:%M")  -- 2026年09月04日 14:05
```

#### `info.timezone()`

```lua
info.timezone()
```

网络/本机保存的时区偏移，单位是 **15 分钟一格**（和 AT `+CTZU` / NITZ 常见编码一致），**不是**小时。

| 返回值 | 含义 |
| --- | --- |
| `32` | UTC+8（8×60÷15） |
| `0` | UTC |
| 负数 | 西时区，例如 `-20` ≈ UTC−5 |
| `nil` | 读失败 |

换算：`偏移小时 = timezone / 4`。失败 `nil`。

#### `info.time_ready()` / `info.nitz_ready()`

```lua
info.time_ready()
info.nitz_ready()
```

布尔。`time_ready`：机身钟已同步（含 NITZ / CCLK / SNTP / 应用授时）。`nitz_ready`：已通过基站 NITZ。锁失败当 `false`。

回授 MCU 是否「基站已对时」用 `nitz_ready`。

#### `info.timestamp()` / `info.timestamp_ms()`

```lua
info.timestamp()
info.timestamp_ms()
```

UTC Unix 秒 / 毫秒，整数。失败 `nil`。

#### `info.tick()` / `info.tick_ms()`

```lua
info.tick()
info.tick_ms()
```

开机以来的 tick 计数 / 按 tick 频率换算的毫秒。总是返回整数，不失败。精度受 OS tick 限制，**不是**墙钟。

---

## 7. 返回表（速查）

字段的完整含义在对应接口节。这里只列结构，避免和 6.2 / 6.3 两套说法打架。

| 接口 | 结构 |
| --- | --- |
| `signal` | `{ csq, snr, rsrp, rsrq }`，见 [signal](#info-signal) |
| `serv_cell` | `{ mcc, mnc, tac, cell_id, snr }`，见 [6.3](#63-小区) |
| `mult_cell` | `{ count, [1]=项, … }`；项含 `is_serving` / `cell_info_valid` / 标识 / `snr` `rsrp` `rsrq` |
| `time` | 见下表 |
| `getapn` | `{ apn, user, pass, auth }` |

### `time`

| 字段 | 范围 | 含义 |
| --- | --- | --- |
| `year` | 四位年 | 本地墙钟 |
| `month` | 1–12 | |
| `day` | 1–31 | |
| `hour` | 0–23 | 24 小时制 |
| `minute` / `second` | 0–59 | |
| `millisecond` | 0–999 | |
| `weekday` | 0–6 | **0=周日**，1=周一 … 6=周六 |

---

## 8. `times` 格式

下面假设本机本地时间是 **2026-09-04 14:05:07.008，星期五**（`weekday=5`），用来对照每一列「本例输出」。

扫描规则：从左到右走 `fmt`。普通字符原样抄进结果。碰到 `%` 就看 **紧跟的那一个字符**，按表替换，然后继续。没有宽度、没有 `%-d`、没有 `%Y-%m` 这种「一个 `%` 管一串」的写法——每个字段都要自己带 `%`。

### 8.1 占位一览

| 占位 | 宽度 | 来源 | 本例输出 | 说明 |
| --- | --- | --- | --- | --- |
| `%Y` | 4 位，不足补零 | 年 | `2026` | 公元年 |
| `%y` | 2 位 | 年 `% 100` | `26` | 两位年 |
| `%m` | 2 位 | 月 1–12 | `09` | **月**。和 `%M` 不是一回事 |
| `%d` | 2 位 | 日 1–31 | `04` | 日 |
| `%H` | 2 位 | 时 0–23 | `14` | **24 小时制**。没有 `%I`、没有上午/下午 |
| `%M` | 2 位 | 分 0–59 | `05` | **分** |
| `%S` | 2 位 | 秒 0–59 | `07` | 秒 |
| `%s` | 3 位，不足补零 | 毫秒 0–999 | `008` | **毫秒**。不是 Unix 时间戳 |
| `%w` | 1 位，不补零 | 星期 | `5` | `0`=周日 … `6`=周六。本例星期五为 `5` |
| `%%` | 1 个字符 | — | `%` | 字面百分号 |

表里没有的 `%X`：吃掉 `%`，只输出后面那个字符 `X`。例如 `%F` → `F`，`%n` → `n`。

`fmt` 以孤立 `%` 结尾（后面没有字符）：这个 `%` **丢弃**，不出现在结果里。

### 8.2 常用拼法

| `fmt` | 本例结果 | 用途 |
| --- | --- | --- |
| （省略） | `2026-09-04 14:05:07` | 默认，含空格，**不含毫秒** |
| `"%Y-%m-%d %H:%M:%S"` | 同上 | 和默认相同 |
| `"%Y-%m-%d %H:%M:%S.%s"` | `2026-09-04 14:05:07.008` | 带毫秒 |
| `"%Y%m%d"` | `20260904` | 日期文件名 |
| `"%Y%m%d-%H%M%S"` | `20260904-140507` | 紧凑时间戳 |
| `"%y/%m/%d"` | `26/09/04` | 两位年 |
| `"%H:%M:%S"` | `14:05:07` | 只要时钟 |
| `"%Y年%m月%d日"` | `2026年09月04日` | 中文日期，汉字当普通字符 |
| `"week=%w"` | `week=5` | 星期数字 |
| `"100%%"` | `100%` | 百分号 |

```lua
info.times()
info.times("%Y-%m-%d %H:%M:%S")
info.times("%Y-%m-%d %H:%M:%S.%s")
info.times("%Y%m%d-%H%M%S")
info.times("%Y年%m月%d日 %H:%M:%S")
```

### 8.3 和 `strftime` / `os.date` 的差别（容易写错）

本模块 **没有** 实现下面这些常见占位，写了会按「未知 `%X` → 只剩 `X`」处理，结果会 silently 错：

| 你可能想写 | 别处的含义 | 这里实际得到（本例） |
| --- | --- | --- |
| `%s` | POSIX：Unix 秒 | **毫秒三位** `008`，要用 Unix 秒请 `info.timestamp()` |
| `%S` vs `%s` | 秒 vs 毫秒 | 大小写不同 |
| `%m` vs `%M` | 月 vs 分 | `"%H:%m"` 会变成 `14:09`（分钟位置填了月份） |
| `%F` | ISO 日期 | 字符 `F` |
| `%T` | 时分秒 | 字符 `T` |
| `%a` `%A` | 英文星期 | `a` / `A` |
| `%b` `%B` | 英文月份 | `b` / `B` |
| `%z` `%Z` | 时区 | `z` / `Z` |
| `%I` `%p` | 12 小时 / AM | `I` / `p` |
| `%j` | 年中第几天 | `j` |
| `%-d` `%#d` | 不补零 | `%` 后是 `-`，输出 `-`，`d` 再当普通字母……不要用修饰符 |

普通分隔符（`-` `:` 空格 `/` 汉字）都可以直接写在 `fmt` 里，不必转义。只有 `%` 自己要写成 `%%`。

Lua 普通字符串里 `%` 没有特殊含义，`"%Y-%m-%d"` 可以直接传。若先用 `string.format` 去拼格式串，要把占位写成 `%%Y`，否则 `string.format` 会先把 `%Y` 吃掉。

### 8.4 长度

结果缓冲大约 **80** 字节。默认格式远够用。把很长的说明文字塞进 `fmt` 会被截断，末尾可能不完整。

---

## 9. 错误与返回约定

多数查询失败**没有**第二返回值错误串，也**没有**统一 `err` 文本。用返回值本身判断。

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `iccid` / `imei` / `imsi` | string | 单独 `nil` |
| `csq` | 0–31 | **99** |
| `cereg` | 0–5 | **-1** |
| `islink` | 1 或 0 | **-1** |
| `serv_cell` / `mult_cell` / `signal` / `time` / `getapn` | table | 单独 `nil` |
| `times` / `timezone` / `timestamp*` | string / integer | 单独 `nil` |
| `time_ready` / `nitz_ready` | boolean | 锁失败当 `false` |
| `tick` / `tick_ms` | integer | 不失败 |
| `setapn` / `apn_factory_reset` | `true` | `false`（无 `err`）；`setapn` 参数个数不对则 **抛** |
| `cfun(GET)` | `true, cfun` | `false` |
| `cfun(其它)` | `true` | `false`；方法非法 **抛** |

**何时 `nil` / `false` / 特殊整数（无错误码）**

- `nil`：锁失败、协议栈读失败、SIM/身份未就绪、时间未授时
- `csq() == 99`：尚未测到或射频未就绪
- `cereg() == -1` / `islink() == -1`：锁失败或查询失败（`islink` 不要当布尔用）
- `setapn` 返回 `false`：APN 字符串过长/拷贝失败、鉴权值非法、锁失败、协议栈写失败
- `cfun` 返回 `false`：锁失败或协议栈拒绝

**抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `setapn(apn [, user, pass [, auth]])` | 一个参数都没给，或只给了 APN+用户、漏了密码（必须 1 个，或 ≥3 个） |
| `invalid cfun method` | `cfun` 第一参不是 `CFUN_GET` / `CFUN_MIN` / `CFUN_FULL` / `RF_OFF` |

缺参、类型错走 Lua 标准 `bad argument #n`。

---

## 10. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| ICCID | 20 位数字 |
| `times` 输出 | 约 80 字节 |
| `mult_cell` | 最多 21 条 |
| APN 名 | 约 99 字节 |
| APN 用户名/密码 | 各 64 字节 |
| 默认承载 | 固定 CID=1 |

没有 userdata、没有回调槽。APN 与部分射频状态在协议栈侧持久化，与 Lua VM 生命周期无关。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 读 IMEI/卡号 | `imei` / `imsi` / `iccid` |
| 是否已有默认 PDP（能上网） | `islink() == 1`（不要当布尔用） |
| 是否已注册到蜂窝网 | `cereg()` 为 `1` 或 `5` |
| 无线质量档位 | `csq()`：0–31，99=未知；对照见 [csq](#info-csq) |
| 质量一组打完 | `signal()`：CSQ + SNR + RSRP/RSRQ 档 |
| 改 APN | `setapn`；恢复出厂 `apn_factory_reset` |
| 读本地时间字符串 | `times` |
| 用 NTP 对时 | [`ntp`](../network/ntp.md)，可选 `auto_set` |
| 应用自己写 UTC 秒 | `sys.set_ts` |
| 关射频省电 | `cfun(CFUN_MIN)` / `RF_OFF`，须清楚会掉网 |

没有 `info.ntp()`。问 NTP 用 `ntp` 模块。

---

## 12. 完整示例

只读一遍身份、驻网、时间：[examples/NT26/module/info/info_api](../../../../examples/NT26/module/info/info_api)。

```lua
local info = require("info")

print(info.imei(), info.imsi(), info.iccid())

local ok, cfun = info.cfun(info.CFUN_GET)
print("cfun", ok, cfun)

print("csq", info.csq(), "cereg", info.cereg(), "pdp", info.islink())

if info.islink() == 1 then
    print("default bearer up")
end

local t = info.time()
print(info.times(), info.timezone(), info.time_ready(), info.nitz_ready())

local apn = info.getapn()
if apn then
    print(apn.apn, apn.auth)
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：抛错摘要、无错误码失败形态与可能原因 |
