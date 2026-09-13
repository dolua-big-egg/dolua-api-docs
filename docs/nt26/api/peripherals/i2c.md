# i2c

**文档版本** `1.1.1`

对象化硬件 I2C 主机。按控制器编号打开一路，再 `write` / `read` / 寄存器读写。每路同时只能有一个实例。

```lua
local i2c = require("i2c")
```

平台预加载模块，无需额外 `.lua` 文件。

任意脚位的软件模拟见 [`soft_i2c`](soft_i2c.md)。本模块走芯片 I2C 控制器，脚由机型固定（PIN + PDDR，不经 `gpio`），Lua 只选 `I2C0` / `I2C1`。NT26-PRO 落盘见 [硬件表 4.2](../../hardware/pro.md#42-i2c)：当前镜像只有 I2C0（PIN 57/58，PDDR 13/14）。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:write`](#7-1-write)
  - [7.2 `obj:read`](#7-2-read)
  - [7.3 `obj:mem_write`](#7-3-mem-write)
  - [7.4 `obj:mem_read`](#7-4-mem-read)
  - [7.5 `obj:scan`](#7-5-scan)
  - [7.6 `obj:bus_recover`](#7-6-bus-recover)
  - [7.7 `obj:id`](#7-7-id)
  - [7.8 `obj:deinit`](#7-8-deinit)
- [8. 设备地址与数据](#8-设备地址与数据)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

典型用法：

1. `i2c.new(i2c.I2C0 [, cfg])` 打开控制器，得到总线对象。
2. `obj:write(addr, cmd)` 发命令，`obj:read(addr, n)` 收回包。
3. 寄存器型芯片用 `mem_write` / `mem_read`（先发寄存器地址，再写或读）。
4. 不用时 `deinit`，同一路才能再 `new`。

没有回调、没有后台传输完成事件。每次收发在调用里等到成功、NACK 或超时才返回。

不要在 UART / MQTT 等短回调里调用：传输会占住整台 Lua 调度。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  i2c.new → write / read / mem_* / scan                   │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  i2c 对象                                                │
│  · 一路控制器一个实例                                    │
│  · 7bit / 8bit 写地址换算                                │
│  · 同步主机传输（等到 STOP）                              │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  硬件 I2C 控制器（脚由机型固定）                          │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `new` / `deinit` | 开关控制器 | **否** | 当前协程 |
| `write` / `read` / `mem_*` | 总线上完整一笔，等到结束或超时 | **否** | 整台 Lua 调度 |
| `scan` | 逐个地址探测 `0x08`～`0x77` | **否** | 可能较久 |
| `bus_recover` | 发恢复时序 | **否** | 当前协程 |

---

## 3. 对象模型

`new` 返回 userdata。方法在对象元表上：

```lua
bus:write(addr, data)        -- 推荐
bus.write(bus, addr, data)   -- 等价
```

`bus.write(addr, data)` 或 `i2c.write(bus, addr, data)` 都是错的。

没有按真假解释的布尔开关。`cfg` 字段只认 **整数**（`lua_isinteger`）：写 `100` 可以，写 `100.0` 会被忽略并保持默认。

脚本必须持有对象引用。`deinit` 或对象回收会释放该路；不持有引用时回收时机不确定，同一路可能仍显示占用。

---

## 4. 常量与枚举

### 4.1 控制器

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `i2c.I2C0` | `0` | 第 0 路控制器 | `new` 的 `id` |
| `i2c.I2C1` | `1` | 第 1 路控制器 | 同上 |

其它整数 **抛** `"invalid i2c_id …"`。

### 4.2 总线速率 `bus_speed`

用于 `new` 的 `cfg.bus_speed`。这是档位枚举，**不是** 写成 `100000` 这种 Hz。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `i2c.BUS_SPEED_STANDARD` | `1` | 100 kHz（常用） |
| `i2c.BUS_SPEED_FAST` | `2` | 400 kHz |
| `i2c.BUS_SPEED_FAST_PLUS` | `3` | 1 MHz |
| `i2c.BUS_SPEED_HIGH` | `4` | 3.4 MHz |

省略 `cfg` 或省略该键：按标准速。传入未导出的其它整数，硬件可能 init 失败并抛 `"i2c init failed: …"`。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `I2cObj` | userdata | `i2c.new` 的返回值 |
| `id` | integer | `i2c.I2C0` / `I2C1` |
| `dev_addr` | integer | 7bit（`0x38`）或 8bit 写地址（`0x70`），见第 8 节 |
| `data` | string | **非空** 二进制。不收字节表 |
| `len` | integer | `> 0` |
| `mem_addr` | integer | 寄存器地址，大端按 `mem_addr_len` 拆字节 |
| `mem_addr_len` | integer | `1`～`4`，默认 `1` |
| `timeout_ms` | integer | 单次传输超时，默认 `100` |

---

## 6. 模块函数

模块表上只有工厂 `new`。

### `i2c.new(id [, cfg]) → I2cObj`

打开一路控制器。

**调用模式**

```lua
i2c.new(id)
i2c.new(id, cfg)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | integer | 是 | `I2C0` / `I2C1` |
| `cfg` | table | 否 | 不是表则整表忽略，用默认 |

| `cfg` 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `bus_speed` | integer | 标准速 | 见 4.2，必须是整数常量 |
| `timeout_ms` | integer | `100` | 毫秒 |

成功返回对象。失败 **抛错**：id 非法、该路已被占用、互斥初始化失败、硬件 init 失败。

```lua
local bus = i2c.new(i2c.I2C0, {
    bus_speed = i2c.BUS_SPEED_STANDARD,
    timeout_ms = 100,
})
```

---

## 7. 对象方法

---

### 7.1 `obj:write(dev_addr, data)` {#7-1-write}

主机发送一笔，带 STOP。

```lua
obj:write(dev_addr, data)
```

| 参数 | 类型 | 必填 |
| --- | --- | --- |
| `dev_addr` | integer | 是 |
| `data` | string | 是 |

成功 `true`。未初始化、空串、NACK/超时：`false`（不抛）。`data` 不是字符串会 **抛** 类型错。

```lua
bus:write(0x38, string.char(0xBE, 0x08, 0x00))
bus:write(0x38, "\xAC\x33\x00")
```

---

### 7.2 `obj:read(dev_addr, len)` {#7-2-read}

主机读 `len` 字节，带 STOP。每次都是现问从机，不是读本地缓存。

```lua
obj:read(dev_addr, len)
```

成功：长度为 `len` 的二进制 string。未初始化、`len==0`、总线失败：`nil`。

```lua
local raw = bus:read(0x38, 7)
```

---

### 7.3 `obj:mem_write(dev_addr, mem_addr, data [, mem_addr_len])` {#7-3-mem-write}

先发寄存器地址，再发 `data`。适合 EEPROM / 寄存器芯片。

**调用模式**

```lua
obj:mem_write(dev_addr, mem_addr, data)
obj:mem_write(dev_addr, mem_addr, data, mem_addr_len)
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `mem_addr_len` | `1` | 地址字节数 `1`～`4`，大端 |

`data` 非空；单次载荷（不含地址字节）最大 **256**。超范围或空数据：`false`。

```lua
bus:mem_write(0x48, 0x00, string.char(0xAB))
bus:mem_write(0x50, 0x1234, "\x00\x01", 2)
```

---

### 7.4 `obj:mem_read(dev_addr, mem_addr, len [, mem_addr_len])` {#7-4-mem-read}

先发寄存器地址（repeated start），再读 `len` 字节。

**调用模式**

```lua
obj:mem_read(dev_addr, mem_addr, len)
obj:mem_read(dev_addr, mem_addr, len, mem_addr_len)
```

成功 string，失败 `nil`。`len` 须 `> 0` 且不超过 256。`mem_addr_len` 默认 `1`，合法 `1`～`4`。

```lua
local val = bus:mem_read(0x48, 0x00, 2)
```

---

### 7.5 `obj:scan()` {#7-5-scan}

探测 `0x08`～`0x77` 有 ACK 的 7bit 地址。调试用。

```lua
obj:scan()
```

返回 1-based 数组，可能是空表。未初始化或扫描失败也返回空表（不是 `nil`）。业务在线检测请用真实 `write`/`read`。

---

### 7.6 `obj:bus_recover()` {#7-6-bus-recover}

SDA 被从机拉死时发恢复时序。

```lua
obj:bus_recover()
```

成功 `true`，未初始化或失败 `false`。

---

### 7.7 `obj:id()` {#7-7-id}

```lua
obj:id()
```

返回控制器编号：`0` 或 `1`。

---

### 7.8 `obj:deinit()` {#7-8-deinit}

释放该路。始终 `true`。之后才能再 `new` 同一路。对象回收也会走同一套清理。

```lua
obj:deinit()
```

---

## 8. 设备地址与数据

**地址：** 手册上的 7bit 直接写（AHT20=`0x38`）。若写成 8bit 写地址（`0x70`）：数值 `> 0x7F` 时右移 1 位再送给控制器。`≤ 0x7F` 原样当 7bit。

**数据必须是二进制 string**，不收 `{0xBE, 0x08}` 这种表（会抛类型错）。

| 写法 | 实际发出 |
| --- | --- |
| `string.char(0xBE, 0x08, 0x00)` | 三字节 |
| `"\xBE\x08\x00"` | 同上 |
| `"0xBE 0x08"` | ASCII 文本，不是 hex |
| `{0xBE, 0x08}` | 不接受 |

数字会被收成十进制文本：`write(addr, 65)` 发出 `"65"` 两个字符。

需要「写寄存器 + 读」且芯片要求中间不要 STOP 时，用 `mem_read`，不要自己 `write` 完再 `read`（那两笔各自带 STOP）。AHT20 这类「写命令、等转换、再读」中间本来就要停，用 `write` + `rt.delay` + `read` 即可。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `new` | userdata | **抛** |
| `write` / `mem_write` / `bus_recover` | `true` | 只 `false`（**无**错误串） |
| `read` / `mem_read` | string | 只 `nil`（**无**错误串） |
| `scan` | table（可空） | 空表（未初始化或扫描失败也是空表，**无**错误串） |
| `id` | integer | — |
| `deinit` | `true` | 不失败 |

`new` 缺整数 `id`、方法缺对象 / 地址 / 数据：标准 Lua 参数错。需要收 `new` 时用 `pcall`。

抛错摘要：

| 摘要 | 可能原因 |
| --- | --- |
| `invalid i2c_id N` | `id` 不是 `i2c.I2C0`(0) / `i2c.I2C1`(1)；`N` 是传入的整数 |
| `mutex init failed` | 打开控制器时系统互斥量创建失败 |
| `i2cN already in use` | 该路已有实例未 `deinit`（`N` 为 0 或 1） |
| `i2c init failed: N` | 控制器没打开。`N` 是底层返回码：脚被别的外设占用、该路未编进、或硬件初始化失败 |

读写失败**没有**第二返回值：对象已 `deinit`、`data` 为空、`len` 为 0、地址无应答、NACK、或总线卡死都会变成 `false`/`nil`。先 `scan` 看地址，再考虑 `bus_recover`。

不是 userdata 却调方法：抛元表类型错。

---

## 10. 资源上限与生命周期

| 资源 | 上限 |
| --- | --- |
| 控制器 | **2**（I2C0 / I2C1） |
| 每路实例 | **1** |
| `mem_*` 单次载荷 | **256** 字节（不含地址） |
| `mem_addr_len` | **1～4** |
| `scan` 范围 | `0x08`～`0x77` |

没有回调槽。`new` 占路，`deinit` / `__gc` 释放。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 机型自带的 I2C 脚、要 100/400 kHz | **`i2c`** |
| 任意 GPIO、或硬件口已被占用 | [`soft_i2c`](soft_i2c.md) |
| 写命令再读（AHT20） | `write` + 延时 + `read` |
| 寄存器/EEPROM | `mem_write` / `mem_read` |
| 找地址 | `scan`，仅调试 |
| 总线死锁 | `bus_recover` |

---

## 12. 完整示例

AHT20：[examples/nt26/peripherals/iic/iic_aht20](../../../../examples/nt26/peripherals/iic/iic_aht20)。

```lua
local rt = require("rt")
local i2c = require("i2c")

local ADDR = 0x38
local bus = i2c.new(i2c.I2C0, {
    bus_speed = i2c.BUS_SPEED_STANDARD,
    timeout_ms = 100,
})

rt.delay(50)
bus:write(ADDR, string.char(0xBE, 0x08, 0x00))
rt.delay(10)

bus:write(ADDR, string.char(0xAC, 0x33, 0x00))
rt.delay(80)
local raw = bus:read(ADDR, 7)
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误文案/错误码与可能原因 |
| 1.1.1 | 2026-09-05 | 脚位改为 PIN+PDDR，并链到硬件落盘表 |
