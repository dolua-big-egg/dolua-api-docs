# soft_i2c

**文档版本** `1.4.1`

**对应 SDK** `NT26-PRO-RTU-D1.3.2`

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
  - [7.10 `obj:disable`](#7-10-disable)
  - [7.11 `obj:sleep_enter`](#7-11-sleep-enter)
  - [7.12 `obj:sleep_exit`](#7-12-sleep-exit)
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
4. 进休眠时固件会自动把脚切成高阻，唤醒后自动恢复；对象不用重新 `new`。脚本也可以自己调 `sleep_enter` / `sleep_exit`。彻底不用了再 `disable`/`deinit`。

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
| `new` / `deinit` / `disable` | 占脚 / 彻底放脚（高阻） | **否** | 当前协程 |
| `sleep_enter` / `sleep_exit` | 休眠切高阻 / 唤醒恢复脚 | **否** | 当前协程 |
| `write` / `read` / `is_ready` | 比特级时序，忙等半周期 | **否** | 整台 Lua 调度 |
| `scan` | `0x08`～`0x77` 逐个探测 | **否** | 较久 |
| `test_hardware` | 拉 SCL 看能否高低 | **否** | 当前协程 |

没有回调、没有独立 I2C 线程。

---

## 3. 对象模型

`new` 返回 userdata。冒号调用；`obj.write(...)` 缺 self 是错的。

`cfg` 里的数字键只认 **整数**。`clock_speed = 10000` 有效；`10000.0` 会被忽略，退回默认 10000。

没有按真假解释的布尔开关。`input` 必须是 `INPUT_GPIO` / `INPUT_PINNO` 整数，写错 **抛** `"invalid input, expect INPUT_GPIO/INPUT_PINNO"`。

脚本须持有引用。进休眠时固件会暂时把脚切高阻，唤醒后恢复，**对象仍可继续 `write`/`read`**。`disable` / `deinit` 或对象回收才真正释放这两根脚；之后要再用必须再 `new`。

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

脚非法或初始化失败 **抛** `"soft_i2c init failed: N"`。`N` 按失败点区分，取值见 [第 9 节](#9-错误与返回约定)。

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

释放两根脚：关掉输出、切断输入缓冲、关掉内部上下拉，脚进入高阻。始终 `true`。对象回收同样清理。

释放后对象不能再读写；同一对脚要再用，必须再 `new`。与 `disable` 是同一套清理。

```lua
obj:deinit()
```

---

### 7.10 `obj:disable()` {#7-10-disable}

失能软件 I2C。语义与 `deinit` 完全相同。始终 `true`。已关闭再调一次仍是 `true`。

这是**彻底关掉**这条总线。休眠省电不需要调它：进睡前固件会走 `sleep_enter`，唤醒走 `sleep_exit`。

```lua
obj:disable()
```

---

### 7.11 `obj:sleep_enter()` {#7-11-sleep-enter}

休眠前处理：SDA/SCL 切成高阻（关输出、关输入缓冲、关内部上下拉），**对象和配置保留**。始终尽量 `true`；对象已 `disable` 也是 `true`。

脚本一般不必调。进入 Sleep1 / Sleep2 / Hibernate 时固件会对所有已打开实例自动调用。

```lua
obj:sleep_enter()
```

---

### 7.12 `obj:sleep_exit()` {#7-12-sleep-exit}

休眠后处理：按 `new` 时的脚和速率把 SDA/SCL 配回总线，随后可继续 `write`/`read`。成功 `true`，恢复脚失败 `false`。对象已 `disable` 为 `true`。

脚本一般不必调。从上述休眠档唤醒时固件会自动调用。若唤醒后立刻读写、而恢复尚未完成，第一次收发也会先把脚拉起来。

```lua
obj:sleep_exit()
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
| `deinit` / `disable` | `true` | 不失败 |
| `sleep_enter` | `true` | 不失败 |
| `sleep_exit` | `true` | 只 `false`（脚恢复失败） |

`sda`/`scl` 不是整数、`data` 不是字符串、缺对象：标准 Lua 参数错。需要收 `new` 时用 `pcall`。

抛错摘要：

| 摘要 | 可能原因 |
| --- | --- |
| `invalid input, expect INPUT_GPIO/INPUT_PINNO` | `cfg.input` 写了整数，但不是 `soft_i2c.INPUT_GPIO` / `INPUT_PINNO` |
| `soft_i2c init failed: N` | `new` 打开两根脚失败。`N` 是整数，按下表对照；常见是解析失败或脚已被占用 |

`new` 抛错里的 `N`：

| `N` | 含义 | 可能原因 |
| --- | --- | --- |
| `-1` | 内部句柄为空 | 正常脚本走不到 |
| `-2` | 打开类型非法 | 一般会被上面的 `invalid input` 先拦住 |
| `-3` | SDA 编号无法解析 | `sda` 不在当前型号脚表里，或 `cfg.input` 和编号体系对不上（GPIO 号当成 pinno，或反过来） |
| `-4` | SCL 编号无法解析 | 同上，换 SCL |
| `-5` | SDA 脚配置失败 | 这根脚不能当输出/上拉，或已被其它外设占用 |
| `-6` | SCL 脚配置失败 | 同上，换 SCL |
| `-7` | SDA 打开失败 | 脚无效、已被占用，或配置过后仍打不开 |
| `-8` | SCL 打开失败 | 同上，换 SCL |

读写 / `is_ready` / `test_hardware` 失败没有文案：对象已 `disable`/`deinit`、从设备无应答、超时、或接线错误都会变成 `false`/`nil`。`error()` 只给整数状态，没有对应英文短句表。先 `test_hardware` 再 `scan`。

---

## 10. 资源上限与生命周期

| 资源 | 说明 |
| --- | --- |
| 实例数 | Lua 侧无固定槽位，受脚和内存限制。自动休眠处理最多同时照顾 8 路已打开实例 |
| `scan` | `0x08`～`0x77`，每地址超时 50 ms |
| `clock_speed` | Hz；过快半周期会收到 1 µs 下限，实际达不到标称 |

`new` 占两根脚。进 Sleep1 / Sleep2 / Hibernate 前固件自动 `sleep_enter`（高阻），唤醒后自动 `sleep_exit`（恢复总线），**不必**再 `new`。`disable` / `deinit` / `__gc` 才彻底释放脚。没有 VM 退出专用清扫以外的全局表：对象被回收即可。

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

AHT20：[examples/nt26/peripherals/iic/soft_iic_aht20](../../../../../examples/nt26/peripherals/iic/soft_iic_aht20)。

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
| 1.2.0 | 2026-09-18 | `new` 抛错 `soft_i2c init failed: N` 按失败点列出 `N`（解析 / 配置 / 打开，分 SDA、SCL） |
| 1.3.0 | 2026-09-28 | 新增 `obj:disable()`；`disable`/`deinit` 把 SDA/SCL 切成高阻（关输出、关输入缓冲、关内部上下拉）。休眠前由脚本关闭，唤醒后必须再 `new` |
| 1.4.0 | 2026-09-28 | 新增 `sleep_enter` / `sleep_exit`。进休眠时固件自动把脚切高阻，唤醒后自动恢复总线，对象不用重新 `new`。`disable` 仍表示彻底关掉 |
| 1.4.1 | 2026-09-28 | 文首标注 `disable` / `sleep_enter` / `sleep_exit` 对应 SDK `NT26-PRO-RTU-D1.3.2` |
