# soft_i2c

**文档版本** `1.1.1`

对象化软件 I2C 主机。用两根普通 GPIO 模拟 SCL/SDA，不占用硬件 I2C 控制器。可同时开多路（脚不要冲突）。

```lua
local soft_i2c = require("soft_i2c")
```

平台预加载模块，无需额外 `.lua` 文件。

硬件控制器见 [`i2c`](i2c.md)。软件口速率由 `clock_speed`（Hz）决定，默认 10 kHz，适合线长、上拉一般的场景；不要指望跑到硬件 400 kHz。

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
  - [7.3 `obj:is_ready`](#7-3-is-ready)
  - [7.4 `obj:scan`](#7-4-scan)
  - [7.5 `obj:test_hardware`](#7-5-test-hardware)
  - [7.6 `obj:state`](#7-6-state)
  - [7.7 `obj:error`](#7-7-error)
  - [7.8 `obj:pins`](#7-8-pins)
  - [7.9 `obj:deinit`](#7-9-deinit)
- [8. 设备地址与数据](#8-设备地址与数据)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

1. `soft_i2c.new(sda, scl [, cfg])` 指定两根脚，得到总线对象。
2. `write` / `read` 做主机收发。没有 `mem_write` / `mem_read`：寄存器访问自己把地址拼进 `write` 的数据里，或 `write` 完再 `read`。
3. 调试可用 `scan`、`is_ready`、`test_hardware`。

时序在当前线程里用 GPIO 翻转 + 微秒延时模拟，**会占住 Lua 调度和 CPU**。短交易可以；不要在 UART 回调里扫整条总线。

SDA/SCL 需要外部上拉。`test_hardware` 只测 SCL 能否拉高/拉低。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  soft_i2c.new(sda, scl) → write / read / scan            │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  soft_i2c 对象                                           │
│  · 解析 GPIO / pinno                                     │
│  · 按 clock_speed 打半周期延时                            │
│  · 7bit 地址左移成 8bit 写地址后发主机时序                │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  两根 GPIO（开漏式模拟 + 板上拉）                         │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `new` / `deinit` | 占脚 / 放脚 | **否** | 当前协程 |
| `write` / `read` / `is_ready` | 比特级时序，忙等半周期 | **否** | 整台 Lua 调度 |
| `scan` | `0x08`～`0x77` 逐个探测 | **否** | 较久 |
| `test_hardware` | 拉 SCL 看能否高低 | **否** | 当前协程 |

没有回调、没有独立 I2C 线程。

---

## 3. 对象模型

`new` 返回 userdata。冒号调用；`obj.write(...)` 缺 self 是错的。

`cfg` 里的数字键只认 **整数**。`clock_speed = 10000` 有效；`10000.0` 会被忽略，退回默认 10000。

没有按真假解释的布尔开关。`input` 必须是 `INPUT_GPIO` / `INPUT_PINNO` 整数，写错 **抛** `"invalid input, expect INPUT_GPIO/INPUT_PINNO"`。

脚本须持有引用。`deinit` 或对象回收释放这两根脚。

可同时多个对象；不要两路点同一对脚。

---

## 4. 常量与枚举

### 4.1 脚编号方式 `input`

与 [`gpio`](gpio.md) 同一套：

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `soft_i2c.INPUT_GPIO` | `0` | 前两个参数是芯片 GPIO 编号 | `cfg.input` |
| `soft_i2c.INPUT_PINNO` | `1` | 前两个参数是模块引脚序号 | 同上；**省略 cfg 时的默认** |

### 4.2 寻址 / 从机相关（写入 cfg）

下列常量都会导出，也可写进 `cfg`。当前主机 `write` / `read` / `scan` **只按 7bit 地址换算**（见第 8 节）；`clock_speed` 才会改变 SCL 半周期。10bit、双地址、广播、禁时钟拉伸没有单独的从机实现，保持默认即可。

| 符号 | 值 | 默认 |
| --- | --- | --- |
| `soft_i2c.ADDRESSING_MODE_7BIT` | `0` | 是 |
| `soft_i2c.ADDRESSING_MODE_10BIT` | `1` | |
| `soft_i2c.DUAL_ADDRESS_DISABLE` | `0` | 是 |
| `soft_i2c.DUAL_ADDRESS_ENABLE` | `1` | |
| `soft_i2c.GENERAL_CALL_DISABLE` | `0` | 是 |
| `soft_i2c.GENERAL_CALL_ENABLE` | `1` | |
| `soft_i2c.NO_STRETCH_DISABLE` | `0` | 是 |
| `soft_i2c.NO_STRETCH_ENABLE` | `1` | |

未挂到模块、却出现在 `state()` / `error()` 返回值里的整数见 7.6 / 7.7。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `SoftI2cObj` | userdata | `new` 的返回值 |
| `sda` / `scl` | integer | GPIO 号或 pinno，由 `input` 决定 |
| `dev_addr` | integer | 7bit 或 8bit 写地址，见第 8 节 |
| `data` | string | 二进制。不收字节表 |
| `len` | integer | `> 0`，否则 `read` 返回 `nil` |
| `timeout_ms` | integer | 默认 `100` |
| `trials` | integer | `is_ready` 默认 `1` |
| `clock_speed` | integer | Hz，默认 `10000`；`0` 在驱动里也当 10000 |

---

## 6. 模块函数

### `soft_i2c.new(sda, scl [, cfg]) → SoftI2cObj`

**调用模式**

```lua
soft_i2c.new(sda, scl)
soft_i2c.new(sda, scl, cfg)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sda` | integer | 是 | 含义由 `cfg.input` 决定 |
| `scl` | integer | 是 | 同上 |
| `cfg` | table | 否 | 不是表则整表忽略：按 **pinno**、10000 Hz、7bit |

| `cfg` 键 | 默认 | 说明 |
| --- | --- | --- |
| `input` | `INPUT_PINNO` | 见 4.1；非法值 **抛** |
| `clock_speed` | `10000` | 整数 Hz |
| `addressing_mode` 等 | 见 4.2 | 整数常量 |

脚非法或初始化失败 **抛** `"soft_i2c init failed: N"`。

```lua
-- GPIO8=SDA，GPIO9=SCL（demo 常用）
local bus = soft_i2c.new(8, 9, {
    input = soft_i2c.INPUT_GPIO,
    clock_speed = 10000,
})
-- 同一对脚按模块序号
local bus2 = soft_i2c.new(66, 67, { clock_speed = 10000 })
```

---

## 7. 对象方法

---

### 7.1 `obj:write(dev_addr, data [, timeout_ms])` {#7-1-write}

**调用模式**

```lua
obj:write(dev_addr, data)
obj:write(dev_addr, data, timeout_ms)
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `timeout_ms` | `100` | 省略或 `nil` 用默认 |

成功 `true`，未初始化或 NACK/超时 `false`。`data` 必须是 string，否则 **抛**。

```lua
bus:write(0x38, string.char(0xAC, 0x33, 0x00))
bus:write(0x38, "\xAC\x33\x00", 100)
```

没有 `mem_*`：写寄存器可 `write(addr, string.char(reg, d0, d1, ...))`。

---

### 7.2 `obj:read(dev_addr, len [, timeout_ms])` {#7-2-read}

每次现问从机。

**调用模式**

```lua
obj:read(dev_addr, len)
obj:read(dev_addr, len, timeout_ms)
```

成功：长度为 `len` 的二进制 string。未初始化、`len==0`、失败：`nil`。`timeout_ms` 默认 `100`。

```lua
local raw = bus:read(0x38, 7)
```

---

### 7.3 `obj:is_ready(dev_addr [, trials [, timeout_ms]])` {#7-3-is-ready}

发地址看从机是否 ACK。

**调用模式**

```lua
obj:is_ready(dev_addr)
obj:is_ready(dev_addr, trials)
obj:is_ready(dev_addr, trials, timeout_ms)
```

不能跳过 `trials` 只改超时。`trials` 默认 `1`，`timeout_ms` 默认 `100`。未初始化或无应答：`false`。

---

### 7.4 `obj:scan()` {#7-4-scan}

`0x08`～`0x77`，每个地址试 1 次、超时 50 ms。返回 7bit 地址数组，可空。未初始化返回空表。

```lua
local addrs = bus:scan()
```

---

### 7.5 `obj:test_hardware()` {#7-5-test-hardware}

测 SCL 能否被拉高、拉低。成功 `true`。对地短路、没上拉、脚不对：`false`。未初始化 `false`。

```lua
obj:test_hardware()
```

---

### 7.6 `obj:state()` {#7-6-state}

当前状态整数。未挂到模块表，调试对照：

| 值 | 含义 |
| --- | --- |
| `0` | reset |
| `1` | ready |
| `2` | busy |
| `3` | busy_tx |
| `4` | busy_rx |
| `5` | listen |
| `6` | busy_tx_listen |
| `7` | busy_rx_listen |
| `8` | abort |
| `9` | timeout |
| `10` | error |

空闲主机常见 `1`。不要用这些数字当 `new` 的配置。

---

### 7.7 `obj:error()` {#7-7-error}

最近一次错误码，**0 表示无错误**。值为位标志（可组合），未挂到模块表：

| 值 | 含义 |
| --- | --- |
| `0` | 无 |
| `1` | 总线错误 |
| `2` | 仲裁丢失 |
| `4` | ACK 失败 |
| `8` | 溢出 |
| `16` | DMA |
| `32` | 超时 |
| `64` | 长度 |
| `128` | DMA 参数 |

业务判断优先看 `write`/`read` 的 `true`/`nil`，这两个整数只辅助排查。

---

### 7.8 `obj:pins()` {#7-8-pins}

```lua
obj:pins()
```

两个返回值：SDA、SCL 的 **模块引脚序号**（即使 `new` 时用的是 GPIO 编号，这里也是解析后的 pinno）。

```lua
local sda, scl = bus:pins()
```

---

### 7.9 `obj:deinit()` {#7-9-deinit}

释放两根脚。始终 `true`。对象回收同样清理。

```lua
obj:deinit()
```

---

## 8. 设备地址与数据

**地址：** 7bit（`0x38`）会 **左移 1 位** 变成 8bit 写地址再发送。写成 `> 0x7F` 的 8bit 写地址（`0x70`）则清掉最低位后使用。与硬件 `i2c` 模块「大于 0x7F 才右移」方向不同，但对 AHT20 两种写法都能对上。

**数据必须是二进制 string**，不收字节表。

| 写法 | 结果 |
| --- | --- |
| `string.char(0xBE, 0x08, 0x00)` | 三字节 |
| `"\xBE\x08\x00"` | 同上 |
| `{0xBE, 0x08}` | 抛类型错 |
| `"0xBE 0x08"` | ASCII，不是 hex |

`read` 不是读缓存：每次都是总线上的一笔接收。AHT20 要先 `write` 测量命令，`rt.delay` 等转换，再 `read`。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `new` | userdata | **抛** |
| `write` / `is_ready` / `test_hardware` | `true` | 只 `false`（**无**错误串） |
| `read` | string | 只 `nil`（**无**错误串） |
| `scan` | table（可空） | 空表（未初始化也是空表，**无**错误串） |
| `state` / `error` | integer | — |
| `pins` | 两个 integer | — |
| `deinit` | `true` | 不失败 |

`sda`/`scl` 不是整数、`data` 不是字符串、缺对象：标准 Lua 参数错。需要收 `new` 时用 `pcall`。

抛错摘要：

| 摘要 | 可能原因 |
| --- | --- |
| `invalid input, expect INPUT_GPIO/INPUT_PINNO` | `cfg.input` 写了整数，但不是 `soft_i2c.INPUT_GPIO` / `INPUT_PINNO` |
| `soft_i2c init failed: N` | 脚号解析失败、脚已被占用、或软件总线初始化失败。`N` 是底层返回码 |

读写 / `is_ready` / `test_hardware` 失败没有文案：对象已 `deinit`、从设备无应答、超时、或接线错误都会变成 `false`/`nil`。`error()` 只给整数状态，没有对应英文短句表。先 `test_hardware` 再 `scan`。

---

## 10. 资源上限与生命周期

| 资源 | 说明 |
| --- | --- |
| 实例数 | Lua 侧无固定槽位，受脚和内存限制 |
| `scan` | `0x08`～`0x77`，每地址超时 50 ms |
| `clock_speed` | Hz；过快半周期会收到 1 µs 下限，实际达不到标称 |

`new` 占两根脚；`deinit` / `__gc` 释放。没有 VM 退出专用清扫以外的全局表：对象被回收即可。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 原理图已接到硬件 I2C | [`i2c`](i2c.md)，更快 |
| 任意脚、硬件口已占用、多路传感器 | **`soft_i2c`** |
| 寄存器读写 | 自己拼进 `write`；硬件口才有 `mem_*` |
| 确认接线 | `test_hardware` + `scan` |
| 100 kHz 以上稳定 | 优先硬件 `i2c` |

和 gpio 编号一致：`INPUT_GPIO` 的 8/9 就是 `gpio.open(gpio.BY_GPIO, 8)` 那套编号（`gpio.BY_GPIO` 旧名 `gpio.INPUT_GPIO`）。

---

## 12. 完整示例

AHT20：[examples/nt26/peripherals/iic/soft_iic_aht20](../../../../examples/nt26/peripherals/iic/soft_iic_aht20)。

```lua
local rt = require("rt")
local soft_i2c = require("soft_i2c")

local ADDR = 0x38
local bus = soft_i2c.new(8, 9, {
    input = soft_i2c.INPUT_GPIO,
    clock_speed = 10000,
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
| 1.1.1 | 2026-09-09 | 与 gpio 编号对照改为 `gpio.BY_GPIO` |
