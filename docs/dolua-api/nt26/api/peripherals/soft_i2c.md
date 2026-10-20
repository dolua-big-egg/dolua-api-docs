# soft_i2c

**文档版本** `1.6.1`

**对应 SDK** `NT26-PRO-RTU-D1.3.7`

标准开漏（等 ACK、读数据时放开 SDA）和 `cfg.no_ext_pullup` 从 `NT26-PRO-RTU-D1.3.7` 起生效。`disable` / `sleep_enter` / `sleep_exit` 自 `NT26-PRO-RTU-D1.3.2` 起就有。

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
- [5. 总线电平与时序](#5-总线电平与时序)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
- [8. 对象方法](#8-对象方法)
  - [8.1 `obj:write`](#8-1-write)
  - [8.2 `obj:read`](#8-2-read)
  - [8.3 `obj:is_ready`](#8-3-is-ready)
  - [8.4 `obj:scan`](#8-4-scan)
  - [8.5 `obj:test_hardware`](#8-5-test-hardware)
  - [8.6 `obj:state`](#8-6-state)
  - [8.7 `obj:error`](#8-7-error)
  - [8.8 `obj:pins`](#8-8-pins)
  - [8.9 `obj:deinit`](#8-9-deinit)
  - [8.10 `obj:disable`](#8-10-disable)
  - [8.11 `obj:sleep_enter`](#8-11-sleep-enter)
  - [8.12 `obj:sleep_exit`](#8-12-sleep-exit)
- [9. 设备地址与数据](#9-设备地址与数据)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

1. `soft_i2c.new(sda, scl [, cfg])` 指定两根脚，得到总线对象。
2. `write` / `read` 做主机收发。没有 `mem_write` / `mem_read`：寄存器访问自己把地址拼进 `write` 的数据里，或 `write` 完再 `read`。
3. 调试可用 `scan`、`is_ready`、`test_hardware`。
4. 进休眠时固件会自动把脚切成高阻，唤醒后自动恢复；对象不用重新 `new`。脚本也可以自己调 `sleep_enter` / `sleep_exit`。彻底不用了再 `disable`/`deinit`。

时序在当前线程里用 GPIO 翻转 + 微秒延时模拟，**会占住 Lua 调度和 CPU**。短交易可以；不要在 UART 回调里扫整条总线。电平有两种，默认是标准开漏。半周期、起始/停止、ACK 采样点见 [第 5 节](#5-总线电平与时序)。

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
│  两根 GPIO。默认标准开漏 + 外部上拉；                   │
│  no_ext_pullup 打开后高电平保持驱动，ACK 时放开 SDA   │
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

没有按真假解释的布尔开关，例外是 `no_ext_pullup`：可写 `true` / `false`，也可写下面的整数常量。其它数字键只认整数。`input` 必须是 `INPUT_GPIO` / `INPUT_PINNO` 整数，写错 **抛** `"invalid input, expect INPUT_GPIO/INPUT_PINNO"`。`no_ext_pullup` 不是 0/1、也不是布尔，**抛** `"invalid no_ext_pullup, expect NO_EXT_PULLUP_DISABLE/NO_EXT_PULLUP_ENABLE"`。

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

下列常量都会导出，也可写进 `cfg`。当前主机 `write` / `read` / `scan` **只按 7bit 地址换算**（见第 9 节）；`clock_speed` 才会改变 SCL 半周期。10bit、双地址、广播、禁时钟拉伸没有单独的从机实现，保持默认即可。

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

### 4.3 上拉方式 `no_ext_pullup`

默认标准开漏，需要外部上拉。这个标志打开后，才走免外部上拉。标准开漏和这个标志都从固件 `NT26-PRO-RTU-D1.3.7` 起生效。

| 符号 | 值 | 含义 | 默认 |
| --- | --- | --- | --- |
| `soft_i2c.NO_EXT_PULLUP_DISABLE` | `0` | 标准：高电平只释放，依赖外部上拉 | 是 |
| `soft_i2c.NO_EXT_PULLUP_ENABLE` | `1` | 免外部上拉：主机高电平保持驱动，等 ACK 和读数据时放开 SDA | |

`true` 等于 `NO_EXT_PULLUP_ENABLE`，`false` 等于 `NO_EXT_PULLUP_DISABLE`。省略 `cfg` 或省略该键时是标准开漏。两种电平怎么驱动脚、什么时候放开 SDA，见 [第 5 节](#5-总线电平与时序)。

未挂到模块、却出现在 `state()` / `error()` 返回值里的整数见 8.6 / 8.7。

---

## 5. 总线电平与时序

本节的脚电平和两种高电平从固件 `NT26-PRO-RTU-D1.3.7` 起生效。更早固件没有 `no_ext_pullup`，高电平也不是这里写的开漏。

软件 I2C 没有硬件控制器。每次 `write` / `read` / `is_ready` / `scan` 都在当前协程里按下面的节拍翻转两根脚，半周期用忙等，中间不让出。

`new` 时两根脚都打开内部上拉。内部上拉只适合维持已经很高的线，上升沿很慢，**不能代替外部上拉**。

### 5.1 半周期

记 \(T_{1/2}\) 为 SCL 高、SCL 低各持续的时间：

\[
T_{1/2}(\mu s) = \max\left(1,\ \left\lfloor \frac{500000}{\texttt{clock\_speed}} \right\rfloor\right)
\]

| `clock_speed` | \(T_{1/2}\) | 一个 SCL 周期（高 + 低） |
| --- | --- | --- |
| 省略、或 `0` | 50 µs | 100 µs（10 kHz） |
| `10000`（默认） | 50 µs | 100 µs |
| `100000` | 5 µs | 10 µs |
| 大于 500000 | 1 µs | 2 µs，到不了标称速率 |

`timeout_ms` 会留在 `write` / `read` / `is_ready` 的参数里，**不改变** \(T_{1/2}\)，也不会在一个字节中途返回。

数据位在 SCL 为低时变化。SCL 拉高之前先等一个 \(T_{1/2}\)，SCL 保持高再等一个 \(T_{1/2}\)。除最后一位之外，SCL 拉低后不再多等，下一位自己的建立时间就是下一段低电平。

### 5.2 两种高电平

低电平两种模式相同：打开输出，把脚驱动成 0。高电平由 `no_ext_pullup` 决定。SDA 和 SCL 用同一套规则，下面表格里的「放开」只在注明的窗口额外作用于 SDA。

| | 标准开漏 `NO_EXT_PULLUP_DISABLE`（默认） | 免外部上拉 `NO_EXT_PULLUP_ENABLE` |
| --- | --- | --- |
| 何时启用 | 省略 `cfg`、省略该键、`false` 或 `0` | `cfg.no_ext_pullup = true` 或 `1` |
| 输出 0 | 驱动低 | 驱动低 |
| 输出 1 | 关掉输出，脚改为输入。高电平只靠上拉 | 打开输出并驱动高，**一直保持**到下一次改电平 |
| SCL 为高 | 输入 + 上拉。从机可以把 SCL 拉住（时钟延展） | 推挽驱动高。从机拉不住 SCL |
| 等从机 ACK | SDA 在 SCL 仍为低时改为输入，再抬 SCL | 同样先把 SDA 改为输入，再抬 SCL。这一拍不能继续驱动高 |
| 读数据位 | 整字节开始前 SDA 改为输入，8 个时钟都由从机驱动 | 同左 |
| 主机 ACK（后面还有字节） | SDA 驱动低 | SDA 驱动低 |
| 主机 NACK（最后一个读字节） | SDA 改为输入，靠上拉为高 | SDA 推挽驱动高 |
| 外部上拉 | 必须有。没有时上升沿会拖到几百微秒，超过 \(T_{1/2}\) 后从机看到的 1 仍是 0 | 可以没有。板上已经有上拉时也能通信，但不是必须开这个模式 |
| 和 I2C 规范 | 开漏，只拉低、不推高 | **不符合**开漏规范。主机在数据 1 和 SCL 高期间推挽输出 |

免外部上拉的风险：

1. 从机时钟延展时拉 SCL，和主机的推挽高对拉，电平下不去，两边引脚过流。
2. 总线上还有别的主机时，对方拉不低 SDA，仲裁失效。
3. 从机 ACK 偏慢，或应答后 SDA 还没松开，主机已经推下一个高电平，出现短时间对拉。

单主机、从机不延展、线很短、板上没有上拉时，用免外部上拉可以把线抬高。有外部上拉的模块用标准开漏。

### 5.3 起始与停止

下面每一步之后都等一个 \(T_{1/2}\)。「高」「低」按 [5.2](#52-两种高电平) 的当前模式解释。

**起始（SCL 为高时 SDA 下降）**

1. SDA 高。
2. SCL 高。
3. SDA 低（此时 SCL 仍为高）。
4. SCL 低。

**停止（SCL 为高时 SDA 上升）**

1. SDA 低。
2. SCL 高。
3. SDA 高（此时 SCL 仍为高）。

停止之后总线停在 SDA 高、SCL 高。标准开漏下这两根脚是输入；免外部上拉下是推挽高。

### 5.4 主机发送一个字节

高位在先。每一位：

1. SCL 为低时，把 SDA 设成该位。
2. 等 \(T_{1/2}\)。
3. SCL 高，再等 \(T_{1/2}\)。从机在这段高电平里采样。
4. SCL 低。

8 位之后是 ACK，SCL 此时为低：

1. **放开 SDA**（改为输入）。标准开漏本来就是输入；免外部上拉必须在这里关掉推挽，从机才拉得动。
2. 等 \(T_{1/2}\)，再把 SCL 拉高。
3. SCL 高保持 \(T_{1/2}\) **之后**读 SDA。读到 0 是 ACK，读到 1 是 NACK。
4. SCL 拉低，再等 \(T_{1/2}\)。

任一字节 NACK：立刻发停止，`write` 返回 `false`，`read` 返回 `nil`。不再发后面的字节。

### 5.5 主机接收一个字节

1. 整字节开始前放开 SDA，8 个时钟都不再驱动它。
2. 每一位：SCL 高，等 \(T_{1/2}\)，读 SDA，SCL 低，再等 \(T_{1/2}\)。高位先读。
3. 然后主机发应答位，时序与 [5.4](#54-主机发送一个字节) 的数据位相同，只是只发 1 位：后面还有字节则 SDA 驱动低（ACK）；这是最后一个字节则 SDA 为高（NACK，电平见 5.2）。

### 5.6 一次交易 {#56-一次交易}

**`write(dev_addr, data)`**

1. 起始。
2. 发送 8bit 写地址（7bit 左移 1 位，最低位 0）。NACK 则停止并返回 `false`。
3. 按顺序发送 `data` 的每个字节，每个字节都等 ACK。中途 NACK 则停止并返回 `false`。
4. 停止。全部 ACK 则返回 `true`。

**`read(dev_addr, len)`**

1. 起始。
2. 发送 8bit 读地址（写地址的最低位置 1）。NACK 则停止并返回 `nil`。
3. 接收 `len` 个字节。除最后一字节发 ACK，最后一字节发 NACK。
4. 停止。返回这 `len` 个字节。

**`is_ready`**

起始，只发写地址，停止。ACK 则成功。失败且还有剩余次数时，等 1 ms 再来一次。`trials` 小于 1 时按 1 次。

**`scan`**

对 `0x08`～`0x77` 各做一次与 `is_ready` 相同的写地址探测（只试 1 次）。地址之间没有额外的 50 ms 等待。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `SoftI2cObj` | userdata | `new` 的返回值 |
| `sda` / `scl` | integer | GPIO 号或 pinno，由 `input` 决定 |
| `dev_addr` | integer | 7bit 或 8bit 写地址，见第 9 节 |
| `data` | string | 二进制。不收字节表 |
| `len` | integer | `> 0`，否则 `read` 返回 `nil` |
| `timeout_ms` | integer | 默认 `100` |
| `trials` | integer | `is_ready` 默认 `1` |
| `clock_speed` | integer | Hz，默认 `10000`；`0` 在驱动里也当 10000 |

---

## 7. 模块函数

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
| `no_ext_pullup` | `NO_EXT_PULLUP_DISABLE` | 见 4.3。`0`/`1` 或 `false`/`true`；非法值 **抛** |

脚非法或初始化失败 **抛** `"soft_i2c init failed: N"`。`N` 按失败点区分，取值见 [第 10 节](#10-错误与返回约定)。

```lua
-- GPIO8=SDA，GPIO9=SCL（demo 常用）
local bus = soft_i2c.new(8, 9, {
    input = soft_i2c.INPUT_GPIO,
    clock_speed = 10000,
})
-- 同一对脚按模块序号，标准开漏
local bus2 = soft_i2c.new(66, 67, { clock_speed = 10000 })
-- 不接外部上拉
local bus3 = soft_i2c.new(66, 67, { no_ext_pullup = soft_i2c.NO_EXT_PULLUP_ENABLE })
```

---

## 8. 对象方法

---

### 8.1 `obj:write(dev_addr, data [, timeout_ms])` {#8-1-write}

**调用模式**

```lua
obj:write(dev_addr, data)
obj:write(dev_addr, data, timeout_ms)
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `timeout_ms` | `100` | 省略或 `nil` 用默认 |

成功 `true`，未初始化或某一字节 NACK `false`。`timeout_ms` 不裁短比特时序，见 [第 5 节](#5-总线电平与时序)。`data` 必须是 string，否则 **抛**。

```lua
bus:write(0x38, string.char(0xAC, 0x33, 0x00))
bus:write(0x38, "\xAC\x33\x00", 100)
```

没有 `mem_*`：写寄存器可 `write(addr, string.char(reg, d0, d1, ...))`。

---

### 8.2 `obj:read(dev_addr, len [, timeout_ms])` {#8-2-read}

每次现问从机。

**调用模式**

```lua
obj:read(dev_addr, len)
obj:read(dev_addr, len, timeout_ms)
```

成功：长度为 `len` 的二进制 string。未初始化、`len==0`、地址或传输失败：`nil`。`timeout_ms` 默认 `100`，不裁短时序，见 [第 5 节](#5-总线电平与时序)。

```lua
local raw = bus:read(0x38, 7)
```

---

### 8.3 `obj:is_ready(dev_addr [, trials [, timeout_ms]])` {#8-3-is-ready}

发地址看从机是否 ACK。

**调用模式**

```lua
obj:is_ready(dev_addr)
obj:is_ready(dev_addr, trials)
obj:is_ready(dev_addr, trials, timeout_ms)
```

不能跳过 `trials` 只改超时。`trials` 默认 `1`。`timeout_ms` 默认 `100`，不裁短这一次探测。失败后隔 1 ms 再试。未初始化或无应答：`false`。时序见 [5.6](#56-一次交易)。

---

### 8.4 `obj:scan()` {#8-4-scan}

`0x08`～`0x77`，每个地址做一次写地址探测（起始 + 地址 + 停止）。返回 7bit 地址数组，可空。未初始化返回空表。单次探测的耗时是比特时序，不是固定 50 ms。

```lua
local addrs = bus:scan()
```

---

### 8.5 `obj:test_hardware()` {#8-5-test-hardware}

测 SCL 能否被拉高、拉低。成功 `true`。对地短路、没上拉、脚不对：`false`。未初始化 `false`。

```lua
obj:test_hardware()
```

---

### 8.6 `obj:state()` {#8-6-state}

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

### 8.7 `obj:error()` {#8-7-error}

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

### 8.8 `obj:pins()` {#8-8-pins}

```lua
obj:pins()
```

两个返回值：SDA、SCL 的 **模块引脚序号**（即使 `new` 时用的是 GPIO 编号，这里也是解析后的 pinno）。

```lua
local sda, scl = bus:pins()
```

---

### 8.9 `obj:deinit()` {#8-9-deinit}

释放两根脚：关掉输出、切断输入缓冲、关掉内部上下拉，脚进入高阻。始终 `true`。对象回收同样清理。

释放后对象不能再读写；同一对脚要再用，必须再 `new`。与 `disable` 是同一套清理。

```lua
obj:deinit()
```

---

### 8.10 `obj:disable()` {#8-10-disable}

失能软件 I2C。语义与 `deinit` 完全相同。始终 `true`。已关闭再调一次仍是 `true`。

这是**彻底关掉**这条总线。休眠省电不需要调它：进睡前固件会走 `sleep_enter`，唤醒走 `sleep_exit`。

```lua
obj:disable()
```

---

### 8.11 `obj:sleep_enter()` {#8-11-sleep-enter}

休眠前处理：SDA/SCL 切成高阻（关输出、关输入缓冲、关内部上下拉），**对象和配置保留**。始终尽量 `true`；对象已 `disable` 也是 `true`。

脚本一般不必调。进入 Sleep1 / Sleep2 / Hibernate 时固件会对所有已打开实例自动调用。

```lua
obj:sleep_enter()
```

---

### 8.12 `obj:sleep_exit()` {#8-12-sleep-exit}

休眠后处理：按 `new` 时的脚和速率把 SDA/SCL 配回总线，随后可继续 `write`/`read`。成功 `true`，恢复脚失败 `false`。对象已 `disable` 为 `true`。

脚本一般不必调。从上述休眠档唤醒时固件会自动调用。若唤醒后立刻读写、而恢复尚未完成，第一次收发也会先把脚拉起来。

```lua
obj:sleep_exit()
```

---

## 9. 设备地址与数据

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

## 10. 错误与返回约定

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
| `invalid no_ext_pullup, expect NO_EXT_PULLUP_DISABLE/NO_EXT_PULLUP_ENABLE` | `cfg.no_ext_pullup` 不是 `0`/`1`，也不是 `true`/`false` |
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

## 11. 资源上限与生命周期

| 资源 | 说明 |
| --- | --- |
| 实例数 | Lua 侧无固定槽位，受脚和内存限制。自动休眠处理最多同时照顾 8 路已打开实例 |
| `scan` | `0x08`～`0x77`，每地址一次写地址探测，耗时由 `clock_speed` 决定 |
| `clock_speed` | Hz；过快半周期会收到 1 µs 下限，实际达不到标称 |

`new` 占两根脚。进 Sleep1 / Sleep2 / Hibernate 前固件自动 `sleep_enter`（高阻），唤醒后自动 `sleep_exit`（恢复总线），**不必**再 `new`。`disable` / `deinit` / `__gc` 才彻底释放脚。没有 VM 退出专用清扫以外的全局表：对象被回收即可。

---

## 12. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 原理图已接到硬件 I2C | [`i2c`](i2c.md)，更快 |
| 任意脚、硬件口已占用、多路传感器 | **`soft_i2c`** |
| 寄存器读写 | 自己拼进 `write`；硬件口才有 `mem_*` |
| 确认接线 | `test_hardware` + `scan` |
| 100 kHz 以上稳定 | 优先硬件 `i2c` |

和 gpio 编号一致：`INPUT_GPIO` 的 8/9 就是 `gpio.open(gpio.BY_GPIO, 8)` 那套编号（`gpio.BY_GPIO` 旧名 `gpio.INPUT_GPIO`）。

---

## 13. 完整示例

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
| 1.4.2 | 2026-10-16 | 短线、默认速率可以不接外部上拉：高电平短推后放开，内部上拉维持，ACK 窗口从机能把 SDA 拉低 |
| 1.5.0 | 2026-10-16 | 免外部上拉改为 `cfg.no_ext_pullup` 单独打开。默认 `NO_EXT_PULLUP_DISABLE`，标准开漏，需要外部上拉 |
| 1.5.1 | 2026-10-16 | 免外部上拉时主机高电平保持驱动，只在等 ACK 和读数据时放开 SDA。避免高电平靠弱上拉爬升，从机认错地址 |
| 1.6.0 | 2026-10-16 | 新增第 5 节：标准开漏与免外部上拉的脚电平、半周期、起始/停止、收发与 ACK 采样。写明免上拉不符合 I2C 开漏规范及风险。`timeout_ms` 不裁短比特时序 |
| 1.6.1 | 2026-10-16 | 标准开漏与 `no_ext_pullup` 标明从固件 `NT26-PRO-RTU-D1.3.7` 起生效。`disable` / `sleep_enter` / `sleep_exit` 仍是 `NT26-PRO-RTU-D1.3.2` |
