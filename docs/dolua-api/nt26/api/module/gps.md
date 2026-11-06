# gps

**文档版本** `2.2.0`

UART GPS 快照。NMEA 在固件里解析，**一包串口数据只进一次 Lua 回调**。回调和 `gps.fix()` 都是同一张表：一份坐标，加上海拔、精度、卫星、天线这些各句不重复的字段。`keep_raw` 打开时，这张表才多一个 `raw`。

脚本不按句子名取数，也不要自己挑 RMC 还是 GGA 的经纬度。模块按下面第 7 节的优先级合成。要自己拆某一句，用 [`nmea`](nmea.md)。

```lua
local gps = require("gps")
```

平台预加载模块，无需额外 `.lua` 文件。工程里若自带 `gps.lua`，会盖掉本模块（`package.preload` 后写）。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `gps.open`](#6-1-open)
  - [6.2 `gps.close`](#6-2-close)
  - [6.3 `gps.datain`](#6-3-datain)
  - [6.4 `gps.on` / `gps.reg`](#6-4-on)
  - [6.5 `gps.fix`](#6-5-fix)
  - [6.6 `gps.heard`](#6-6-heard)
  - [6.7 `gps.keep_raw`](#6-7-keep_raw)
  - [6.8 `gps.send`](#6-8-send)
  - [6.9 `gps.set_rate`](#6-9-set_rate)
  - [6.10 `gps.set_sentences`](#6-10-set_sentences)
- [7. 快照 `ev`](#7-快照-ev)
  - [7.1 字段一览](#7-1-字段一览)
  - [7.2 坐标与 `valid`](#7-2-坐标与-valid)
  - [7.3 `quality`](#7-3-quality)
  - [7.4 时间、日期、速度、航向](#7-4-时间日期速度航向)
  - [7.5 海拔与精度](#7-5-海拔与精度)
  - [7.6 卫星 `sats` 与 `sats_used`](#7-6-卫星-sats-与-sats_used)
  - [7.7 天线与 `raw`](#7-7-天线与-raw)
  - [7.8 不写入快照的内容](#7-8-不写入快照的内容)
  - [7.9 现场怎么读](#7-9-现场怎么读)
- [8. 回调](#8-回调)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

典型顺序：`gps.on` / `gps.reg` 登记回调，再 `gps.open` 打开串口。默认 `auto_reg=true`：该口每一包先交给 gps 解析，**不占** `uart.reg` 槽。脚本仍可对同一口 `uart.reg`，两边都会进；gps 先更新快照并调用自己的回调，再调脚本串口回调。

一包里校验通过的句子先合成**同一张表**，再按登记种类调用回调，每种登记在这一包里最多一次。`gps.fix()` 读的是这张表的最新缓存，不会再去读串口。

`quality` 原样放在表里，模块**不会**因为估算点把坐标丢掉。用不用 `quality == 6` 由脚本判断。

默认 `proto="none"` 只收、不向 GPS 芯片发配置句。真要让模组少吐某一类句子，再用 `set_sentences`。它同时是本地更新开关：写成 `0` 的句子不再刷新快照里对应的项。

---

## 2. 框架结构

```
GPS 模组 ──UART──► 分包（rtu_config [uart.N]）
                      │
                      ▼
                 串口分发（Lua 调度循环，不是硬件中断）
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
   gps 解析（默认监听时）      uart.reg（若脚本登记了）
          │
          ▼
   更新快照 → gps.on / gps.reg
```

`auto_reg=false` 时左边那条关掉，自己在 `uart.reg` 里把收到的字符串交给 `gps.datain`。不要默认监听再 `datain`，同一包会解析两次。

以换行结束的一行才解析。一行被拆进相邻两包时，会先拼上再解析。拼行缓冲 1024 字节，超长的半行丢掉。校验和不对的行丢掉，不更新快照，也不算 `gps.heard()` 收到过。

| 路径 | 谁在跑 | 是否让出 |
| --- | --- | --- |
| 解析与合成快照 | 串口事件进调度后、脚本 `uart.reg` 之前 | 否 |
| `gps.on` / `gps.reg` | 同上，必须短 | 否：禁止 `rt.delay` / `mbox_recv` / 同步 `uart.write` |
| 脚本 `uart.reg` | gps 回调之后 | 否，约束同 [`uart`](../peripherals/uart.md) |
| `gps.fix` / `gps.heard` | 调用方当前协程 | 否，只读缓存 |

---

## 3. 阻塞语义

`open` / `close` / `datain` / `fix` / `heard` / `keep_raw` 同步返回。`open` 会按给定波特率调用 `uart.config`（8 数据位、1 停止位、无校验、无流控），配置完才返回。

`set_rate` / `send` / `set_sentences`（`proto` 不是 `none` 时）只把命令丢进 UART 发送队列，不等 GPS 模组 ACK。

---

## 4. 常量与枚举

### 默认串口

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `gps.UART` | `2` | 默认口 UART2 | `open` 省略 `uart` 时 |

口编号与 [`uart`](../peripherals/uart.md) 相同，业务口 1～3。`0` 和大于 3 的编号会让 `open` 抛错。

### 芯片协议 `opts.proto`

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `gps.PROTO_NONE` | `"none"` | 不发配置句 | `open` 的 `proto` |
| `gps.PROTO_PMTK` | `"pmtk"` | 配置句只发 PMTK | 同上 |
| `gps.PROTO_PCAS` | `"pcas"` | 配置句只发 PCAS | 同上 |
| `gps.PROTO_AUTO` | `"auto"` | PMTK 和 PCAS 都发 | 同上 |

未识别的字符串按 `"none"` 处理。这些值只决定 `set_rate` / `set_sentences` 发不发、发哪一套，不改变解析。

### 输出周期

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `gps.RATE_MS.HZ_10` | `100` | 10 Hz，周期 100 ms | `set_rate` |
| `gps.RATE_MS.HZ_5` | `200` | 5 Hz | 同上 |
| `gps.RATE_MS.HZ_2` | `500` | 2 Hz | 同上 |
| `gps.RATE_MS.HZ_1` | `1000` | 1 Hz | 同上 |

也可以直接传毫秒整数。模块把参数夹到 100～10000。

### 回调种类

`gps.on` 的种类是字符串，不是上面的整数常量。

| 字符串 | 何时调用 |
| --- | --- |
| `"all"` | 本包至少解析出一条允许更新的句子 |
| `"fix"` | 本包解析出定位句 RMC、GGA 或 GNS |

省略种类、`gps.on(cb)`、`gps.reg(cb)` 都是 `"all"`。其它字符串抛错 `gps.on: unknown kind`。

---

## 5. 类型约定

| 名 | 类型 | 说明 |
| --- | --- | --- |
| 快照 `ev` | table | 每次回调、每次 `gps.fix()` 新建。字段还没收到时**没有这个键**，读出来是 `nil` |
| `opts.keep_raw` | boolean 或整数 | 见下。这里的整数 `0` 是关 |
| `opts.auto_reg` | boolean 语义 | 走 Lua 真假。数字 `0` 为真，**关不掉监听** |
| `gps.keep_raw` 的参数 | boolean，或整数 | 布尔走真假；整数里 `0` 为关，省略等于 `0` |
| `set_sentences` 的值 | 整数 `0`/`1` 或 boolean | `0` 和 `false` 为关，其它真值为开 |
| `time` / `date` / `sats` | table | 随快照一起新建 |

`open` 里两个开关不要混用：

```lua
gps.open({ keep_raw = false, auto_reg = false })  -- 关原文、关自动监听
gps.open({ keep_raw = 0 })                        -- 整数 0：关原文
gps.open({ auto_reg = 0 })                        -- 数字 0 仍是真：监听还开着
```

快照里的 `valid`、`quality` 是两件独立的事。`valid` 表示定位句自己的状态位；`quality` 只来自 GGA，用来让脚本分辨单点、差分、RTK 和估算。

---

## 6. 模块函数

### 6.1 `gps.open`

```lua
gps.open({ uart = uart.UART3, baud = 9600 })
```

```lua
gps.open({
    uart = 3,
    baud = 9600,
    proto = gps.PROTO_NONE,
    keep_raw = false,
    auto_reg = true,
})
```

省略整张表时，用默认口 UART2、9600、`proto="none"`、不保留原文、自动监听。

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `uart` | integer | `gps.UART`（2） | 1～3 |
| `baud` | integer | 9600 | 立刻 `uart.config`，不写盘 |
| `proto` | string | `"none"` | 第 4 节。未识别的值当成 `"none"` |
| `keep_raw` | boolean 或 number | `false` | `true` 或非 0 才把本包挂到 `ev.raw`。布尔和整数都认，整数 `0` 为关 |
| `auto_reg` | boolean 语义 | `true` | 只有 `false` 关掉监听。数字 `0` 仍为开 |

成功返回 `true`。

`open` 会做这些事：

- 清掉上一份快照、卫星列表、天线文本和 `heard` 记录
- `rtu.option("pass_up", false)` 与 `rtu.option("pass_down", false)`，避免这条口被当成 AT 透传吃掉
- 按 `baud` 配置 8N1、无流控
- `auto_reg=true` 时开始听这个口。不调用、不覆盖脚本已有的 `uart.reg`

再次 `open` 会换口、换波特率，并清空缓存。已经 `gps.on` 的回调还在，不用重新登记。

`pin_map`、分包 `max_wait_ms` 只能写 `rtu_config.cfg` 的 `[uart.N]`。GPS 建议 `max_wait_ms` ≥ 200，让同一秒的坐标、海拔、卫星更可能进同一包。同一包只触发一次回调；拆成多包就会多次回调，每次看到的是当时的缓存。

非法口抛错 `gps.open: invalid uart`。工作缓冲分配失败抛错 `gps.open: no mem`。

### 6.2 `gps.close`

```lua
gps.close()
```

停止监听，并清掉 `heard`。返回 `true`。

`close` **不**调用 `uart.unreg`，脚本自己的串口回调还在。也**不**拆掉 `gps.on` 登记，**不**清空 `gps.fix()` 里已经合成的坐标和卫星。要丢掉旧点，再 `open` 一次。

### 6.3 `gps.datain`

```lua
gps.datain(data)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `data` | string | 是 | 一包串口字节，可以含多行 NMEA |

在 `auto_reg=false` 时，从 `uart.reg` 回调里把收到的数据交进来。返回 `true`。本包没有任何校验通过的句子时也返回 `true`，只是不调 gps 回调、不刷新 `heard`。

`auto_reg=true` 时不要再调，同一包会解析两次。`data` 不是字符串时抛 `bad argument #1`。

### 6.4 `gps.on` / `gps.reg`

```lua
gps.reg(cb)
gps.on(cb)
gps.on("all", cb)
gps.on("fix", cb)
```

| 调用 | 种类 |
| --- | --- |
| `gps.reg(cb)` | `"all"` |
| `gps.on(cb)` | `"all"` |
| `gps.on("all", cb)` | `"all"` |
| `gps.on("fix", cb)` | `"fix"` |

`cb` 只有一个参数，就是第 7 节的快照：

```lua
function on_gps(ev)
end
```

`"all"`：本包解析出至少一条允许更新的句子就调用。`"fix"`：本包里出现了 RMC、GGA 或 GNS 才调用。`valid` 为 `false`（尚未定位）也会进 `"fix"`。同一包、同一个登记槽只调用一次。先登记的先调用。`"all"` 和 `"fix"` 可以同时登记，有定位句时两个都会进。

句子名（`rmc`、`gga`、`gsv` 等）不能当第一个参数，传入抛错 `gps.on: unknown kind`。登记满 8 个抛错 `gps.on: too many callbacks`。第二个参数不是函数时抛 `bad argument`。

无返回值。回调被模块持有，脚本不必再把函数存进全局；换一份新函数要再 `on` 一次，旧的不会被替换。

### 6.5 `gps.fix`

```lua
local ev = gps.fix()
```

返回当前缓存，字段与回调参数相同。这是读最近一次合成结果，不是向 UART 要一包新数据。

还没收到的字段是 `nil`。已经收到的字段会留着，直到更新的句子覆盖那一项，或再次 `gps.open` 清空。`gps.close` 不清这份缓存。

没有登记回调时也可以轮询 `gps.fix()`。缓存仍只在串口包被解析之后变化。

### 6.6 `gps.heard`

```lua
local ok, ms = gps.heard()
```

| 返回值 | 类型 | 说明 |
| --- | --- | --- |
| `ok` | boolean | 本次 `open` 之后，有没有解析出过一条校验通过、且允许更新的 NMEA |
| `ms` | integer 或 `nil` | 最近一次这种解析的开机毫秒，与 [`info.tick_ms`](info.md) 同一时钟。还没有则是 `nil` |

`ms` 是本机开机毫秒，不是报文里的卫星时间。没定位时卫星时间经常停在出厂日期，不能用来判断模块有没有往外吐。

多久以前收到：`info.tick_ms() - ms`。一直是 `false`：这口没有完整 NMEA，先查接线、波特率和 `uart` 号。`true` 但快照里 `valid` 仍是 `false`：报文到了，模块还没定位。

校验失败的乱码不算。`close` 或再次 `open` 会把 `ok` 清回 `false`。`auto_reg=false` 时，只有 `datain` 喂进去并解析成功的数据才会计数。

### 6.7 `gps.keep_raw`

```lua
gps.keep_raw(true)
gps.keep_raw(false)
```

```lua
gps.keep_raw(1)
gps.keep_raw(0)
gps.keep_raw()
```

| 调用 | 结果 |
| --- | --- |
| `true` / 非 0 整数 | 打开。之后的快照带 `raw` |
| `false` | 关闭，并丢掉已保留的原文 |
| `0`、省略、`nil` | 关闭。这一支走整数，`0` 是关 |

返回关闭或打开之后的状态，boolean。打开时若分配 1024 字节缓冲失败，保持关闭并返回 `false`。

`open` 的 `keep_raw` 与这个函数同一开关。回调里的 `ev.raw` 是**这一包 UART 原文**（可含多行），不是单独某一句，最长 1024 字节，超出截断。

### 6.8 `gps.send`

```lua
gps.send("PMTK605")
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| 正文 | string | 是 | 命令正文。不要带 `$`、`*` 和校验，模块会补 |

发到 `open` 时选定的那一口。返回 `uart.write` 的布尔。正文无法组成一帧时返回 `false`。`proto` 不影响 `send`，需要发什么就发什么。

### 6.9 `gps.set_rate`

```lua
gps.set_rate(1000)
gps.set_rate(gps.RATE_MS.HZ_1)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| 周期 | integer | 是 | 毫秒。小于 100 按 100，大于 10000 按 10000 |

| `proto` | 行为 | 返回值 |
| --- | --- | --- |
| `"none"` | 不发送 | `false` |
| `"pmtk"` | 发送 `PMTK220,<ms>` | `true` |
| `"pcas"` | 发送 `PCAS02,<ms>` | 该次 `uart.write` 的布尔 |
| `"auto"` | 两条都发 | PCAS 那次 `uart.write` 的布尔 |

不等待模组应答。芯片不认识对应命令时，返回值仍只表示有没有写入发送队列。

### 6.10 `gps.set_sentences`

```lua
gps.set_sentences({ rmc = 1, gga = 1, gsv = 0 })
```

```lua
gps.set_sentences({ gsv = false, txt = 0 })
```

这是输出开关，不是回调过滤。回调种类仍然只有 `"all"` 和 `"fix"`。

本地更新：表里出现的键会改「这类句子还刷不刷新快照」。`0` 和 `false` 为停，其它真值为开。没写到的键保持原样。`open` 之后默认全部开启。键名大小写都可以：`rmc` 与 `RMC` 相同。

| 键 | 停掉之后，快照里不再被它刷新的内容 |
| --- | --- |
| `rmc` | 坐标、`valid`、速度、航向、时间、日期的第一优先来源 |
| `gga` | 坐标与 `valid` 的第二来源；`quality`、`sats_used`、`hdop`、海拔 |
| `gns` | 坐标与 `valid` 的第三来源；没有 GGA 时的 `sats_used`、`hdop`、海拔 |
| `gsa` | `fix_type`、`pdop`、`vdop` |
| `gsv` | `sats`。已有的列表会留着，直到再次允许并收到新的卫星句 |
| `vtg` | 没有 RMC 速度/航向时的速度、航向 |
| `zda` | 没有 RMC 时的时间、日期 |
| `gll` | 无。GLL 本来就不写入快照 |
| `gst` | 无。GST 的误差项不进快照 |
| `txt` | `antenna` |

不认识的键忽略。

`proto` 为 `"none"` 时只改本地开关，不发芯片命令，返回 `true`。

`proto` 不是 `"none"` 时，还会按整句命令重写芯片输出。命令里**没在这次表里出现的项用下面的默认值**，可能把芯片上的 GSA、GSV 关掉。本地开关则只改表里写出的键。

PMTK314 各项默认：`gll=0`，`rmc=1`，`vtg=0`，`gga=1`，`gsa=0`，`gsv=0`，`zda=0`。

PCAS03 各项默认：`gga=1`，`gll=0`，`gsa=0`，`gsv=0`，`rmc=1`，`vtg=0`，`zda=0`，`gst=0`。

`gns` 和 `txt` 只影响本地，不会出现在这两条芯片命令里。

`"pmtk"` 返回 `true`。`"pcas"` 和 `"auto"` 返回这次写串口的布尔。参数不是表时抛 `bad argument #1`。

---

## 7. 快照 `ev`

每次回调和每次 `gps.fix()` 都是一张新表。没有按 RMC、GGA、GSV 拆开的子表。还没收到的字段不出现，读到的是 `nil`，不要把它当成 `0`。`quality` 是例外：GGA 一旦到过，`0` 会真的写在表里，表示未定位。

字段会留在缓存里。后面的包只更新它带来的那几项。例如先收到了海拔，下一包只有 RMC，`alt` 仍是上一次的值。`gps.open` 整表清空。

经纬度已经换成十进制度。南纬、西经为负。

### 7.1 字段一览

```lua
ev = {
  valid,             -- boolean。定位句状态有效才是 true
  lat, lon,          -- 十进制度
  speed_kmh, course, -- 公里/小时、航向角（度）
  time = { hour, min, sec },
  date = { day, month, year },
  alt,               -- 海拔，米
  quality,           -- 只来自 GGA。0 未定位，6 为估算
  sats_used,         -- 参与解算的卫星个数
  hdop,              -- 水平精度因子
  fix_type,          -- 1 未定位，2 为 2D，3 为 3D
  pdop, vdop,        -- 综合精度因子、垂直精度因子
  sats = { { sys, prn, elev, az, snr }, ... },
  antenna,           -- 天线文本，例如 "ANTENNA OK"
  raw,               -- 本包 UART 原文；keep_raw 关闭则没有这个字段
}
```

| 字段 | 类型 | 从哪来 | 没有时 |
| --- | --- | --- | --- |
| `valid` | boolean | RMC，否则 GGA，再否则 GNS | 键不存在 |
| `lat` / `lon` | number | 同上，纬、经各自按这个顺序 | 键不存在 |
| `speed_kmh` | number | RMC（节换算成公里/小时），否则 VTG | 键不存在 |
| `course` | number | RMC，否则 VTG。单位度 | 键不存在 |
| `time` | table | RMC，否则 ZDA，否则 GGA，否则 GNS | 键不存在 |
| `date` | table | RMC，否则 ZDA。`year` 为四位年 | 键不存在 |
| `alt` | number | GGA，否则 GNS。米 | 键不存在 |
| `quality` | integer | 只来自 GGA | 还没有 GGA 时键不存在 |
| `sats_used` | integer | GGA，否则 GNS | 键不存在 |
| `hdop` | number | GGA 且大于 0，否则 GNS 且大于 0 | 键不存在 |
| `fix_type` | integer | GSA，且大于 0 | 键不存在 |
| `pdop` / `vdop` | number | GSA，且大于 0 | 键不存在 |
| `sats` | table | GSV 拼成的可见星，最多 32 颗 | 一颗都没有时键不存在 |
| `antenna` | string | 文本里含 `ANTENNA` 的那条 TXT，最长 47 字符 | 键不存在 |
| `raw` | string | 本包 UART 原文，最长 1024 字节 | `keep_raw` 关闭，或本包没有可解析句子 |

`time.hour`、`time.min` 为整数，`time.sec` 为 number，可以带小数。`date` 的三项都是整数。

### 7.2 坐标与 `valid`

坐标只有一份。`GN` 开头的是多系统合解（常见是 GPS 加北斗解出来的一个点），不是把 GP 和 BD 的经纬度相加。`GP` 是 GPS，`BD` / `GB` 是北斗。不同 talker 的句子可能同时出现，快照不按系统拆成多份坐标。

优先级：

| 项 | 第一 | 第二 | 第三 |
| --- | --- | --- | --- |
| `lat` | RMC 里有纬度 | GGA | GNS |
| `lon` | RMC 里有经度 | GGA | GNS |
| `valid` | 有 RMC | 没有 RMC 时看 GGA | 前两者都没有时看 GNS |

纬和经分开取。RMC 只有纬度、没有经度时，经度可以落到 GGA。

`valid` 的含义：

| 实际用到的句子 | `true` 的条件 |
| --- | --- |
| RMC | 状态为 `A`。`V` 为 `false`。此时不再看 GGA 的 `quality` |
| GGA | `quality > 0`。因此 `6`（估算）也是 `true` |
| GNS | 模式字符有值，并且不是 `N` |

有 RMC 且状态为 `V` 时，即使同包 GGA 的 `quality` 为 1，`valid` 仍是 `false`。要看定位质量，读 `quality`，不要只看 `valid`。

### 7.3 `quality`

只来自 GGA，原样保留整数。模块不用它过滤坐标：`quality` 为 6 时，只要对应定位句让 `valid` 为 `true`，`lat` / `lon` 仍会更新。

| 值 | 含义 |
| --- | --- |
| `0` | 未定位。键存在，值就是 0 |
| `1` | 单点 |
| `2` | 差分 |
| `4` | RTK 固定解 |
| `5` | RTK 浮点解 |
| `6` | 估算（推算）。精度通常差于实测点 |
| 其它正整数 | 按芯片原文保留，模块不另作解释 |

脚本若不接受估算点，自己丢弃 `quality == 6` 的坐标。RMC 里的模式字符（含表示估算的 `E`）不在这张表里。

还没有任何 GGA 时，没有 `quality` 键。这和「GGA 来了且质量为 0」不同。

### 7.4 时间、日期、速度、航向

| 字段 | 顺序 | 单位与形状 |
| --- | --- | --- |
| `speed_kmh` | RMC，否则 VTG | 公里/小时。RMC 的节会乘 1.852 |
| `course` | RMC，否则 VTG | 度 |
| `time` | RMC，否则 ZDA，否则 GGA，否则 GNS | `{ hour, min, sec }` |
| `date` | RMC，否则 ZDA | `{ day, month, year }`，年为四位 |

这是卫星报文里的时间，不是 `gps.heard()` 的开机毫秒。未定位时它可能停在芯片出厂日期。

### 7.5 海拔与精度

| 字段 | 来源 | 出现条件 |
| --- | --- | --- |
| `alt` | GGA，否则 GNS | 该句带了海拔 |
| `hdop` | GGA，否则 GNS | 值大于 0。GSA 里的水平精度不写入 `hdop` |
| `fix_type` | GSA | 大于 0。`1` 未定位，`2` 为 2D，`3` 为 3D |
| `pdop` | GSA | 大于 0 |
| `vdop` | GSA | 大于 0 |

GSA 的选用：已经收到过 talker 为 `GN` 的 GSA 之后，后面的 `GP` / `BD` GSA 不再覆盖 `fix_type`、`pdop`、`vdop`。还没有 `GN` 时，用最近一条 GSA。

### 7.6 卫星 `sats` 与 `sats_used`

`sats` 不是一种句子名，是 GSV 拼出来的可见星列表。`sats_used` 是另一个字段，表示参与解算的颗数，来自 GGA（没有 GGA 时来自 GNS）。两者不相等：看得见的星可以比参与解算的多，`#ev.sats` 也不是 `sats_used`。

每颗星：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `sys` | string | 这一条 GSV 的 talker，两字母。常见 `GP`、`BD`、`GB`、`GL`、`GA`、`GN` |
| `prn` | integer | 星号。不同 `sys` 下的星号会重复，必须连 `sys` 一起看 |
| `elev` | integer | 仰角，度 |
| `az` | integer | 方位角，度 |
| `snr` | integer | 信噪比。该星这一项为空时可能是 0 |

同一 talker 的多条 GSV 拼在一起。该 talker 新一轮的第 1 条到来时，只清掉这个 `sys` 的旧星，其它系统留着。列表最多 32 颗，再多的丢掉。`set_sentences` 把 `gsv` 关掉之后，已有列表保留，直到重新打开并收到新的 GSV。

### 7.7 天线与 `raw`

`antenna` 只收文本中含有 `ANTENNA` 的 TXT，例如 `ANTENNA OK`。其它 TXT 不进快照。最长 47 个字符。

`raw` 仅在 `keep_raw` 打开、且本包解析出至少一条句子时出现。内容是这一包串口数据，可以包含多行，最长 1024 字节。`"fix"` 回调里的 `raw` 仍是整包，不是单独的 RMC 或 GGA 那一行。

### 7.8 不写入快照的内容

这些句子可以被解析、可以触发 `"all"` 回调、也可以被 `set_sentences` 关掉，但没有自己的子表：

| 句子 | 快照里能看到的部分 |
| --- | --- |
| GLL | 无。其中的经纬度、状态不参与 `lat` / `lon` / `valid` |
| GST | 无。误差椭圆不进表 |
| VTG | 只在没有 RMC 速度或航向时，提供 `speed_kmh`、`course` |
| ZDA | 只在相应项还没有 RMC 时，提供 `time`、`date` |
| TXT | 只在含 `ANTENNA` 时写入 `antenna` |
| RMC 模式字符 | 无。估算与否看 GGA 的 `quality` |

### 7.9 现场怎么读

| 现象 | 含义 |
| --- | --- |
| `gps.heard()` 为 `false` | 这次 `open` 之后还没有完整 NMEA。先查口、波特率、接线 |
| `heard` 为 `true`，`valid` 为 `false` 或没有 `lat` | 模块在吐数，还没有可用定位 |
| `valid` 为 `true`，`quality` 为 1 | 单点定位 |
| `valid` 为 `true`，`quality` 为 6 | 估算点。坐标在表里，用不用由脚本决定 |
| `valid` 为 `true`，没有 `quality` | 定位状态来自 RMC 或 GNS，这包缓存里还没有 GGA |
| `antenna` 为 `ANTENNA OK` 但 `valid` 为 `false` | 天线状态正常，不等于已经定位 |

---

## 8. 回调

签名：`function(ev) ... end`。在 Lua 调度循环执行，与 `uart.reg` 同一约束：短、只投递或打日志，不要 `rt.delay`，不要在回调里同步写大段串口。

`gps.on` 和 `uart.reg` 是两套槽。同一口可以同时登记：先走完 gps 的回调，再走脚本串口回调。`uart.reg` 同一口仍是后写覆盖，与 gps 无关。

一个回调出错时，同包里其余已登记的 gps 回调仍会调用。出错信息走模块日志，不把错误返回给 `open` 或 `datain`。

`uart.block` 把这一包消费掉之后，gps 收不到该包。

---

## 9. 错误与返回约定

| 摘要或返回值 | 原因 |
| --- | --- |
| `gps.open: invalid uart` | `uart` 不是 1～3 |
| `gps.open: no mem` | 1024 字节拼行缓冲，或打开 `keep_raw` 时的原文缓冲分配失败 |
| `gps.on: unknown kind` | 种类不是 `"all"` / `"fix"`。句子名属于这种 |
| `gps.on: too many callbacks` | 已有 8 个回调 |
| `bad argument #n` | 该参数走了类型检查：`datain` 要字符串，`on` 的回调要函数，`send` 要字符串，`set_rate` 要整数，`set_sentences` 要表 |
| `open` / `datain` / `close` 返回 `true` | 调用完成。`datain` 即使本包没有合法句子也是 `true` |
| `set_rate` 在 `proto=="none"` 时返回 `false` | 按设计不发送 |
| `keep_raw` 返回 `false` | 已经关掉，或打开时缓冲分配失败 |
| `send` 返回 `false` | 组帧失败，或 `uart.write` 失败 |

回调内部的 Lua 错误不抛回给登记函数，见第 8 节。

---

## 10. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 同时 GPS 实例 | **1**（整机一份快照、一个监听口） |
| 回调槽 | 8。重复 `on` 会再占一槽，不会替换旧回调 |
| `sats` | 32 颗 |
| `antenna` | 47 字符 |
| `ev.raw` 与拼行缓冲 | 各 1024 字节。原文超长截断；拼不下的半行丢掉 |
| `set_rate` | 100～10000 ms |
| VM 退出 | 释放回调引用和缓冲，监听停止 |

脚本在生命周期内 `require("gps")` 即可。回调函数由模块保存。再次 `open` 清空快照和 `heard`，保留回调。`close` 只停监听并清 `heard`。

---

## 11. 选型对照

| 需求 | 用 |
| --- | --- |
| 产品里要坐标、精度、卫星 | 本模块，读第 7 节这一张表 |
| 确认模块有没有往外吐 NMEA | `gps.heard()` |
| 只要最新缓存、不要回调 | `gps.fix()` |
| 估算点自己丢弃 | 看 `ev.quality == 6` |
| UART3 接线、全字段打印 | [gps_uart2](../../../../../examples/nt26/apps/uart_collect/gps_uart2) |
| 短示例 | [gps_api](../../../../../examples/nt26/module/gps/gps_api) |
| 只拆一句、不接 UART | [`nmea`](nmea.md) |

---

## 12. 完整示例

下面说明回调、`quality` 和 `heard` 怎么一起用。可运行的短例子在 [gps_api](../../../../../examples/nt26/module/gps/gps_api)，把每个字段都打出来的例子在 [gps_uart2](../../../../../examples/nt26/apps/uart_collect/gps_uart2)。

```lua
local rt = require("rt")
local info = require("info")
local uart = require("uart")
local gps = require("gps")

local function on_gps(ev)
    if not (ev.valid and ev.lat) then
        return
    end
    if ev.quality == 6 then
        return
    end
    print(ev.lat, ev.lon, ev.alt, ev.speed_kmh, ev.sats_used, ev.hdop)
end

gps.on("fix", on_gps)
gps.open({
    uart = uart.UART3,
    baud = 9600,
    proto = gps.PROTO_NONE,
    keep_raw = false,
    auto_reg = true,
})

while true do
    local ok, ms = gps.heard()
    if ok then
        print("nmea age", info.tick_ms() - ms)
    end
    rt.delay(10000)
end
```

接线（NT26-PRO UART3 出厂 `pin_map=0`）：GPS TX → PIN 53，GPS RX → PIN 52（只收数可不接 RX）。日志走 UART1。

示例里 `quality == 6` 直接返回，是脚本自己的取舍。去掉这段判断后，估算点的 `lat` / `lon` 会和其他点一样被打印。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-16 | 首版 |
| 1.1.0 | 2026-09-16 | 收包改成分发层注入：不占 `uart.reg`；`close` 不再 `unreg` 脚本回调 |
| 1.1.1 | 2026-09-16 | 修一包超过原 256 字节窗口时丢掉包头 GGA：`ev.gga` 的 alt/sats/hdop 会是 nil |
| 1.2.0 | 2026-09-16 | `ev.raw` 与解析工作缓冲改为 1024 字节 |
| 2.0.0 | 2026-11-04 | 回调改为单表：坐标加海拔、精度、卫星、天线；`raw` 仍可选。`gps.on` 只接受 `all` / `fix`，不再按句子名登记 |
| 2.1.0 | 2026-11-04 | 增加 `gps.heard()`：是否收到过完整 NMEA，以及最近一次的开机毫秒 |
| 2.1.1 | 2026-11-04 | `gps_uart2` 改为固件 `gps` 例程，不再自带 Lua 解析器 |
| 2.2.0 | 2026-11-04 | 写全快照字段来源与优先级；`quality` 含 6（估算）且由脚本取舍；区分 `valid`、`sats` 与 `sats_used`；补上 `open`/`keep_raw`/`set_sentences` 的布尔和整数语义，以及 `close` 不清缓存 |
