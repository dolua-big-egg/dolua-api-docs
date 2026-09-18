# nmea

**文档版本** `1.2.0`

纯函数 NMEA-0183 解析。XOR 校验、组帧、拆一行、按包 feed。没有对象、不占串口。定位快照与串口收发见 [`gps`](gps.md)。

```lua
local nmea = require("nmea")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `nmea.checksum`](#6-1-checksum)
  - [6.2 `nmea.frame`](#6-2-frame)
  - [6.3 `nmea.parse`](#6-3-parse)
  - [6.4 `nmea.feed`](#6-4-feed)
  - [6.5 `nmea.reset`](#6-5-reset)
- [7. 句表字段](#7-句表字段)
- [8. 错误与返回约定](#8-错误与返回约定)
- [9. 资源上限与生命周期](#9-资源上限与生命周期)
- [10. 选型对照](#10-选型对照)
- [11. 完整示例](#11-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

把 `$GxRMC...*xx` 这类文本变成表。只处理**已经拿到的字节**，不 `uart.reg`。

1. `checksum` / `frame`：XOR 与补 `$` `*CS` `\r\n`。
2. `parse`：完整一行（可无 `\r\n`）。
3. `feed`：粘包攒行，完整行才 parse。`reset` 清空行缓冲。

支持 RMC / GGA / GNS / GSA / GSV / GLL / VTG / ZDA / GST / TXT，以及 `PMTK001`（`type="ack"`）。其它专有句校验通过后仍返回表，`type` 为句名，不再拆语义。

---

## 2. 框架结构

```
脚本  checksum / frame / parse / feed
        │
        ▼
nmea 模块  当场拆行、XOR、填表。feed 工作缓冲 1024 字节，半行才进缓冲。
```

| 路径 | 当场做什么 | 是否让出协程 |
| --- | --- | --- |
| 全部接口 | CPU 上解析完再返回 | **否** |

---

## 3. 阻塞语义

同步。短句可在串口回调里 `feed`；不要在回调里再 `rt.delay`。

---

## 4. 常量与枚举

模块表 **没有** 整数常量。句型看返回表的 `type` 字符串。

---

## 5. 类型约定

| 文档名 | Lua 类型 | 说明 |
| --- | --- | --- |
| 行 / 块 | string | `parse` 一行；`feed` 一块（可多行） |
| 句表 | table | 见第 7 节 |
| 校验 | integer | XOR，0～255 |

空字段不出现在表里（`nil`），不是 `0`。

---

## 6. 模块函数

### 6.1 `nmea.checksum`

```lua
nmea.checksum(body)
```

`body` 是 `$` 与 `*` 之间的文本。返回 XOR 整数。

### 6.2 `nmea.frame`

```lua
nmea.frame("PMTK220,1000")
```

返回 `"$PMTK220,1000*1F\r\n"`。`body` 不要自带 `$` / `*`。失败 `nil`。

### 6.3 `nmea.parse`

```lua
nmea.parse("$GNRMC,...,A*7D")
```

成功句表，校验失败或不成句 `nil`。

### 6.4 `nmea.feed`

```lua
local list = nmea.feed(chunk)
```

返回句表数组（可能空）。按行扫完整块，半行进 1024 字节工作缓冲。校验失败的完整行 `type="bad"`，带 `raw`。一包里有多少完整句就吐多少。

### 6.5 `nmea.reset`

```lua
nmea.reset()
```

清空 `feed` 行缓冲。无返回值。

---

## 7. 句表字段

公共：`type`、`talker`、`msgid`、`raw`。

| type | 主要字段 |
| --- | --- |
| RMC | `valid` `status` `lat` `lon` `speed_kn` `speed_kmh` `course` `time` `date` `mode` |
| GGA | `valid` `lat` `lon` `alt` `quality` `sats` `hdop` `geoid` `age` `time` |
| GNS | 同 GGA 语义（`mode` 代替 quality） |
| GSA | `fix_select` `fix_type` `sats`（PRN 数组）`pdop` `hdop` `vdop` `system_id` |
| GSV | `total` `msg` `in_view` `sats`=`{prn,elev,az,snr}` |
| GLL | `valid` `lat` `lon` `status` `mode` `time` |
| VTG | `course_t` `course_m` `speed_kn` `speed_kmh` `mode` |
| ZDA | `time` `day` `month` `year` `tz_hour` `tz_min` |
| GST | `rms` `smjr` `smin` `orient` `lat_err` `lon_err` `alt_err` |
| TXT | `text` |
| ack | `cmd` `flag` |
| bad | 仅 `raw` |

`time` = `{hour,min,sec}`，`date` = `{day,month,year}`。

---

## 8. 错误与返回约定

| 接口 | 失败 |
| --- | --- |
| `parse` / `frame` | `nil`，不抛错 |
| `checksum` | 缺参走 Lua `bad argument` |
| `feed` | 永远返回表（可空） |

无第二返回值、无错误码。

---

## 9. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 单行 | 127 字节 |
| `feed` 工作缓冲 | 1024 字节 |
| 一次 `feed` 吐出 | 本块全部完整句 |

`feed` 缓冲是模块一份，多路串口请各自用 [`gps`](gps.md)，不要并行 `feed`。

---

## 10. 选型对照

| 需求 | 用 |
| --- | --- |
| 只要拆句 | `nmea` |
| UART + 融合 lat/lon + 回调 | [`gps`](gps.md) |
| 纯 Lua 教学实现 | [gps_uart2](../../../../../examples/nt26/apps/uart_collect/gps_uart2) |

---

## 11. 完整示例

```lua
local nmea = require("nmea")
local list = nmea.feed("$GNRMC,000000.000,V,,,,,,,,,,N*2D\r\n")
-- list[1].type == "RMC"，list[1].valid == false
```

接串口的完整工程见 [`gps`](gps.md) 与 [gps_api](../../../../../examples/nt26/module/gps/gps_api)。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-16 | 首版 |
| 1.1.0 | 2026-09-16 | `feed` 按行扫完整块：半行缓冲 127 字节；一次吐出全部完整句（不再 256 字节窗口 / 最多 8 句） |
| 1.2.0 | 2026-09-16 | `feed` 工作缓冲改为 1024 字节 |
