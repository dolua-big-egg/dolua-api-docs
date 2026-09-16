# gps

**文档版本** `1.2.0`

UART GPS 快照。NMEA 在 C 层解析，**一包串口数据只进一次 Lua 回调**。句表挂在 `ev.rmc` / `ev.gga` / … 上，`ev.lat` `ev.lon` `ev.valid` 给地图。纯拆句见 [`nmea`](nmea.md)。

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
  - [6.6 `gps.keep_raw`](#6-6-keep_raw)
  - [6.7 `gps.send`](#6-7-send)
  - [6.8 `gps.set_rate`](#6-8-set_rate)
  - [6.9 `gps.set_sentences`](#6-9-set_sentences)
- [7. 快照 `ev`](#7-快照-ev)
- [8. 回调](#8-回调)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`open` 配 UART。默认 `auto_reg=true`：串口分发把该口每一包先送给 gps 解析，**不占** `uart.reg` 槽。脚本仍可对同一口 `uart.reg`，两边都会进；gps 先更新快照，再调脚本串口回调。一包里的 GGA+RMC 先全部写入快照，再 `gps.on` 一次。不要用「改芯片输出」当过滤器；默认 `proto="none"` 只收。真要关 GSV，再 `set_sentences`（本地屏蔽；`proto` 不是 `none` 时才发 PMTK/PCAS）。

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
   gps 解析（C，默认）        uart.reg（若脚本登记了）
          │
          ▼
   gps.reg / gps.on
```

`auto_reg=false` 时左边那条关掉，自己在 `uart.reg` 里 `gps.datain`。不要默认监听再 `datain`，会解两遍。

| 路径 | 谁在跑 | 是否让出 |
| --- | --- | --- |
| 解析 | 串口事件进调度后、脚本 `uart.reg` 之前 | 否 |
| 用户 `gps.reg` | 同上，必须短 | 否：禁止 `rt.delay` / `mbox_recv` / 同步 `uart.write` |
| 脚本 `uart.reg` | gps 回调之后 | 否，约束同 [`uart`](../peripherals/uart.md) |

---

## 3. 阻塞语义

`open` / `datain` / `fix` 同步。`set_rate` / `send` 只把命令丢进 UART 发送队列，不等模组 ACK。

---

## 4. 常量与枚举

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `gps.UART` | `2` | 默认口 UART2 | `open` 省略 `uart` 时 |
| `gps.PROTO_NONE` | `"none"` | 不发配置句 | `opts.proto` |
| `gps.PROTO_PMTK` | `"pmtk"` | 只发 PMTK | 同上 |
| `gps.PROTO_PCAS` | `"pcas"` | 只发 PCAS | 同上 |
| `gps.PROTO_AUTO` | `"auto"` | PMTK 和 PCAS 都发 | 同上 |
| `gps.RATE_MS.HZ_10` | `100` | 10 Hz 周期 ms | `set_rate` |
| `gps.RATE_MS.HZ_5` | `200` | | |
| `gps.RATE_MS.HZ_2` | `500` | | |
| `gps.RATE_MS.HZ_1` | `1000` | | |

口编号与 [`uart`](../peripherals/uart.md) 相同，业务口 1～3，不要 UART0。

---

## 5. 类型约定

| 名 | 类型 | 说明 |
| --- | --- | --- |
| `opts.keep_raw` | boolean | 必须 `true`/`false`。数字 `0` 在 Lua 布尔里为真，不要写 `0` |
| `set_sentences` 开关 | 整数 `0`/`1` | 走整数，不是 gpio 布尔 |
| 快照 | table | 每次回调新建；不要长期攥着改 |

---

## 6. 模块函数

### 6.1 `gps.open`

```lua
gps.open({ uart = uart.UART3, baud = 9600 })
gps.open({
    uart = 3,
    baud = 9600,
    proto = gps.PROTO_NONE,
    keep_raw = false,
    auto_reg = true,
})
```

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `uart` | `gps.UART`（2） | 1～3 |
| `baud` | 9600 | 热改，不写盘 |
| `proto` | `"none"` | 见第 4 节 |
| `keep_raw` | `false` | `true` 才把本包挂 `ev.raw` |
| `auto_reg` | `true` | `true`：分发层把该口数据注入 gps，**不调用、不覆盖** `uart.reg`。`false`：不监听，自己 `uart.reg` 后 `gps.datain` |

成功 `true`。非法口抛错 `gps.open: invalid uart`。会 `rtu.option("pass_up"/"pass_down", false)`，避免当 AT 透传吃报文。同一口再 `uart.reg` 仍然有效；脚本回调里可读 `gps.fix()`，不要再 `datain`。

`pin_map`、分包 `max_wait_ms` 只能写 `rtu_config.cfg` 的 `[uart.N]`。GPS 建议 `max_wait_ms` ≥ 200，好让 GGA+RMC 同一包。

### 6.2 `gps.close`

```lua
gps.close()
```

停监听、清占用。**不** `uart.unreg`，脚本自己的串口回调还在。返回 `true`。

### 6.3 `gps.datain`

```lua
gps.datain(data)
```

`auto_reg=false` 时在 `uart.reg` 回调里调用。`data` 为 string。返回 `true`。`auto_reg=true` 时不要再调，会同一包解析两次。

### 6.4 `gps.on` / `gps.reg`

```lua
gps.reg(cb)
gps.on("all", cb)
gps.on("fix", cb)
gps.on("rmc", cb)
```

`cb(ev)` 只有一个参数：第 7 节快照。`reg` 等价 `on("all")`。`fix`：本包含 RMC/GGA/GNS。`rmc`/`gga`/…：本包含对应句。同一包、同一个 `cb` 只调一次。

登记满抛错 `gps.on: too many callbacks`；未知 kind 抛错 `gps.on: unknown kind`。

### 6.5 `gps.fix`

```lua
local ev = gps.fix()
```

当前快照，形状与回调相同。尚无数据时多数字段为 `nil`。

### 6.6 `gps.keep_raw`

```lua
gps.keep_raw(true)
gps.keep_raw(1)
gps.keep_raw(false)
gps.keep_raw(0)
```

布尔或整数 `0`/`1`（这里整数 `0` 为关）。返回当前是否打开。

### 6.7 `gps.send`

```lua
gps.send("PMTK605")
```

不要带 `$` 和校验，模块会补。返回 `uart.write` 的布尔。

### 6.8 `gps.set_rate`

```lua
gps.set_rate(1000)
gps.set_rate(gps.RATE_MS.HZ_1)
```

夹到 100～10000 ms。`proto=="none"` 返回 `false` 且不发送。

### 6.9 `gps.set_sentences`

```lua
gps.set_sentences({ rmc = 1, gga = 1, gsv = 0 })
```

列出的键：`0` 本地不塞对应子表；`proto` 不是 `none` 时再发芯片命令。未列出的键不改本地允许位。返回 `true`，或写串口后的布尔。

---

## 7. 快照 `ev`

```lua
ev = {
  updated = "rmc",   -- 本包主更新：有 RMC 就是 rmc
  lat, lon, valid,   -- RMC 优先，否则 GGA / GNS
  raw,               -- 本包 UART 数据；keep_raw 关闭则为 nil
  rmc = { valid, status, lat, lon, speed_kn, speed_kmh, course, mode, time, date },
  gga = { valid, lat, lon, alt, geoid, age, quality, sats, hdop, time },
  gns = { valid, lat, lon, alt, mode, sats, hdop, time },
  gsa = { fix_select, fix_type, sats, pdop, hdop, vdop, system_id },
  gsv = { total, in_view, sats = { { prn, elev, az, snr }, ... } },
  gll = { ... }, vtg = { ... }, zda = { ... }, gst = { ... },
  txt = { text }, ack = { cmd, flag },
}
```

屏蔽或尚未收到的子表为 `nil`。取用：`ev.rmc and ev.rmc.valid`。GSV 多包拼进 `ev.gsv.sats`（最多 32 颗）。

---

## 8. 回调

签名：`function(ev) ... end`。在 Lua 调度循环执行，与 `uart.reg` 同一约束：短、只投递或打日志，不要 `rt.delay`。

`gps.reg` 和 `uart.reg` 是两套槽。同一口可以同时登记：先 gps 回调，再脚本串口回调。`uart.reg` 同一口仍是后写覆盖，与 gps 无关。

---

## 9. 错误与返回约定

| 摘要 | 原因 |
| --- | --- |
| `gps.open: invalid uart` | 口不是 1～3 |
| `gps.open: no mem` | 1K 工作缓冲分配失败 |
| `gps.on: callback required` / `unknown kind` / `too many callbacks` | 登记方式不对或超过 8 个 |
| `bad argument #n` | `luaL_check*` 类型不对 |

`open`/`datain`/`close` 成功为 `true`。配置类在 `proto=="none"` 时 `set_rate` 为 `false`。

---

## 10. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 同时 GPS 实例 | **1**（整机一份快照） |
| 回调槽 | 8 |
| GSV 星 | 32 |
| `ev.raw` | 1024 字节（超长截断） |
| VM 退出 | 自动 `unreg` 回调引用 |

脚本须在生命周期内 `require("gps")` 并保持回调函数不被自己清掉。

---

## 11. 选型对照

| 需求 | 用 |
| --- | --- |
| 产品固件、C 解析 | 本模块 |
| 教学、可改 Lua 解析器 | [gps_uart2](../../../../examples/nt26/apps/uart_collect/gps_uart2)（工程内 `nmea.lua`/`gps.lua`） |
| 只拆一句、不接 UART | [`nmea`](nmea.md) |

---

## 12. 完整示例

与 [examples/nt26/module/gps/gps_api](../../../../examples/nt26/module/gps/gps_api) 一致：

```lua
local uart = require("uart")
local gps = require("gps")

local function on_gps(ev)
    if ev.valid and ev.lat then
        print(ev.lat, ev.lon, ev.gga and ev.gga.alt)
    end
end

gps.reg(on_gps)
gps.open({ uart = uart.UART3, baud = 9600, proto = gps.PROTO_NONE })
```

接线（NT26-PRO UART3 出厂 `pin_map=0`）：GPS TX → PIN 53，GPS RX → PIN 52（只收数可不接 RX）。日志走 UART1。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-16 | 首版 |
| 1.1.0 | 2026-09-16 | 收包改成分发层注入：不占 `uart.reg`；`close` 不再 `unreg` 脚本回调 |
| 1.1.1 | 2026-09-16 | 修一包超过原 256 字节窗口时丢掉包头 GGA：`ev.gga` 的 alt/sats/hdop 会是 nil |
| 1.2.0 | 2026-09-16 | `ev.raw` 与解析工作缓冲改为 1024 字节 |
