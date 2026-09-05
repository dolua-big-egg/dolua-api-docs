# gpio

**文档版本** `1.2.3`

GPIO 对象化驱动模块。按编号打开引脚对象后，可配置方向、读写电平、同步时序播放、异步波形任务，以及边沿回调。

```lua
local gpio = require("gpio")
```

平台预加载模块，无需额外 `.lua` 文件。

---
c
## 目录

- [1. 模块定位](#1-模块定位)
  - [1.1 GPIO 与模块脚绑定](#11-gpio-与模块脚绑定)
  - [1.2 NT26-PRO 映射表（F6E0 / F6D0）](#12-nt26-pro-map)
  - [1.3 NT26-F6B0 映射表](#13-nt26-f6b0-映射表)
  - [1.4 未对脚本开放的编号](#14-未对脚本开放的编号)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:config`](#7-1-config)
  - [7.2 `obj:set`](#7-2-set)
  - [7.3 `obj:get`](#7-3-get)
  - [7.4 `obj:tog`](#7-4-tog)
  - [7.5 `obj:pins`](#7-5-pins)
  - [7.6 `obj:seq`](#7-6-seq)
  - [7.7 `obj:wave_reg`](#7-7-wave-reg)
  - [7.8 `obj:wave_set`](#7-8-wave-set)
  - [7.9 `obj:wave_insert`](#7-9-wave-insert)
  - [7.10 `obj:wave_stop`](#7-10-wave-stop)
  - [7.11 `obj:reg`](#7-11-reg)
  - [7.12 `obj:unreg`](#7-12-unreg)
- [8. 时序 payload（seq）](#8-时序-payloadseq)
- [9. 波形 payload（wave）](#9-波形-payloadwave)
- [10. 边沿回调协议](#10-边沿回调协议)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`gpio` 把一条物理脚抽象成 **Lua userdata 对象**。脚本不直接操作端口寄存器，而是：

1. `gpio.open` 用编号解析并打开引脚，得到对象。
2. `obj:config` 设定输入 / 输出、初始电平、上下拉。
3. 之后在该对象上读写、播时序、挂波形或注册边沿回调。

同一条脚可以用两种编号打开：

| 打开方式 | 含义 |
| --- | --- |
| `gpio.INPUT_GPIO` | 按芯片 GPIO 编号（GPIOX） |
| `gpio.INPUT_PINNO` | 按模块对外引脚序号 |

打开时完成编号解析。之后 `set` / `get` / `tog` / `seq` 走对象上的快速句柄，不再反复查表。两种编号必须落在**本机型固定映射表**里，对不上就 `open` 抛 `invalid pin`。

### 1.1 GPIO 与模块脚绑定

框架为每条可用脚维护一对固定关系：**芯片 GPIO 编号 ↔ 模块对外 PIN 序号**。`gpio.open(gpio.INPUT_GPIO, n)` 与 `gpio.open(gpio.INPUT_PINNO, pin)` 打开的是同一条物理脚时，`obj:pins()` 会给出互相对应的两个编号。

**NT26-PRO** 使用 **F6E0** 与 **F6D0** 两种封装。F6D0 固件不另开一张表，GPIO↔PIN **与 F6E0 完全相同**，做板与脚本都按 [1.2](#12-nt26-pro-map) 对脚。丝印脚名、默认外设和全部复用见 [NT26-PRO 全 IO 表](../../hardware/pro.md)。固件落地的 GPIO / PIN / PDDR 见同篇 [4.1](../../hardware/pro.md#41-gpio)。F6B0 是另一封装，PIN 不同，见 [1.3](#13-nt26-f6b0-映射表)。

| 产品 | 封装 | 用哪张表 |
| --- | --- | --- |
| NT26-PRO | F6E0 | [1.2](#12-nt26-pro-map) |
| NT26-PRO | F6D0 | 与 F6E0 **同一张**（[1.2](#12-nt26-pro-map)），不单独列出 |
| — | F6B0 | [1.3](#13-nt26-f6b0-映射表)，不可与上表混用 |

**当前不支持用户手动改映射。** 做板、硬件原理图、量产物料都以固定表为准：GPIO10 永远对应本机型表里那颗 PIN，脚本不能把 GPIO10 改绑到别的脚，也不能把未出现在表里的 PIN 当 GPIO 用。打开时框架按这张表配好电气复用，脚本只选编号、配方向和电平。

这样做是为了保证各封装原理图一致、外设默认脚（UART / 网络指示 / I2C 等）不互相踩空。后续固件**可能**开放自由映射；在开放之前，请按本节表格布线，不要假设脚本能改绑。

同一颗模块脚不要同时交给 `gpio` 和另一路外设（例如默认 UART2 占用 NT26-PRO 的 GPIO10 / GPIO11）。要腾出那两脚给脚本，应改 UART 的 `pin_map`，而不是改 GPIO 映射。网络指示灯默认常占 NT26-PRO 的 GPIO25（PIN 16）；脚本要用这脚，须先关掉网络灯占用。

表中标「常电域」的脚属于掉电后仍可保持的 IO 域，做低功耗或唤醒脚时优先考虑它们。未标的脚在主电源域。

### 1.2 NT26-PRO 映射表（F6E0 / F6D0） {#12-nt26-pro-map}

**NT26-PRO** 的 F6E0、F6D0 共用下表。F6D0 未单独标出条目，编号与 F6E0 一一对应，不要另找一张 D0 表。`INPUT_GPIO` 填「GPIO」列，`INPUT_PINNO` 填「模块 PIN」列。

| GPIO | 模块 PIN | 常电域 | 备注 |
| --- | ---: | --- | --- |
| 1 | 22 | 否 | |
| 2 | 23 | 否 | |
| 3 | 54 | 否 | |
| 4 | 80 | 否 | |
| 5 | 81 | 否 | |
| 6 | 55 | 否 | |
| 7 | 56 | 否 | |
| 8 | 66 | 否 | |
| 9 | 67 | 否 | |
| 10 | 28 | 否 | 默认 UART2 RXD 复用 |
| 11 | 29 | 否 | 默认 UART2 TXD 复用 |
| 15 | 49 | 否 | |
| 16 | 103 | 否 | |
| 17 | 21 | 否 | |
| 20 | 5 | 是 | |
| 21 | 6 | 是 | |
| 22 | 19 | 是 | |
| 23 | 100 | 是 | |
| 24 | 101 | 是 | |
| 25 | 16 | 是 | 默认网络状态指示 |
| 26 | 25 | 是 | |
| 27 | 20 | 是 | |
| 29 | 30 | 否 | |
| 30 | 31 | 否 | |
| 31 | 32 | 否 | |
| 32 | 33 | 否 | |
| 33 | 26 | 否 | |
| 34 | 53 | 否 | 默认 UART3 RXD 复用 |
| 35 | 52 | 否 | 默认 UART3 TXD 复用 |
| 36 | 78 | 否 | |
| 37 | 50 | 否 | |
| 38 | 51 | 否 | |

等价写法示例（NT26-PRO，F6E0 / F6D0 相同）：

```lua
local a = gpio.open(gpio.INPUT_GPIO, 9)     -- GPIO9
local b = gpio.open(gpio.INPUT_PINNO, 67)   -- 同一条脚，模块 PIN 67
```

### 1.3 NT26-F6B0 映射表

另一封装，**不是** NT26-PRO 的 F6E0 / F6D0。GPIO 编号看起来相近，**PIN 序号与 [1.2](#12-nt26-pro-map) 不同**，不可混用。换封装时按本表重对原理图。

| GPIO | 模块 PIN | 常电域 | 备注 |
| --- | ---: | --- | --- |
| 0 | 82 | 否 | |
| 1 | 22 | 否 | |
| 2 | 23 | 否 | |
| 3 | 54 | 否 | |
| 7 | 56 | 否 | |
| 8 | 83 | 否 | |
| 9 | 85 | 否 | |
| 10 | 84 | 否 | |
| 11 | 86 | 否 | |
| 12 | 28 | 否 | 默认 UART2 RXD 复用 |
| 13 | 29 | 否 | 默认 UART2 TXD 复用 |
| 14 | 58 | 否 | |
| 15 | 57 | 否 | |
| 16 | 97 | 否 | |
| 17 | 100 | 否 | |
| 20 | 102 | 是 | |
| 21 | 74 | 是 | |
| 22 | 19 | 是 | |
| 23 | 99 | 是 | |
| 24 | 20 | 是 | |
| 25 | 106 | 是 | |
| 26 | 25 | 是 | |
| 27 | 16 | 是 | 默认网络状态指示 |
| 28 | 78 | 是 | |
| 29 | 30 | 否 | |
| 30 | 31 | 否 | |
| 31 | 32 | 否 | |
| 32 | 33 | 否 | |
| 33 | 26 | 否 | |
| 34 | 53 | 否 | 默认 UART3 RXD 复用 |
| 35 | 52 | 否 | 默认 UART3 TXD 复用 |
| 36 | 49 | 否 | |
| 37 | 50 | 否 | |
| 38 | 51 | 否 | |

### 1.4 未对脚本开放的编号

下列编号**不在映射表里**，`open` 会失败。不是漏写，是刻意留给调试口、主串口、第二卡或片上总线：

| 范围 | NT26-PRO（F6E0 / F6D0） | F6B0 | 原因 |
| --- | --- | --- | --- |
| GPIO 0 | 未导出 | 已导出（PIN 82） | PRO 封装不做板用脚 |
| GPIO 4 / 5 / 6 | 已导出 | 未导出 | F6B0 留给 SIM2 |
| GPIO 12 / 13 / 14 | 未导出 | 已导出 | PRO 封装留给 SIM2 |
| GPIO 18 / 19 | 两边都不导出 | 两边都不导出 | 片上 I2C |
| GPIO 28 | **无此脚** | 已导出（PIN 78） | PRO 封装硬件没有 GPIO28 |
| 调试 UART、主 UART 专用焊盘 | 不导出为 GPIO | 不导出为 GPIO | 日志口 / UART1，脚本不要占用 |

芯片上另有一组与 GPIO16～19 同名的调试/主串口焊盘，**不是**表中的 GPIO16 / GPIO17。表中 GPIO16 / GPIO17 已改绑到别的模块 PIN（NT26-PRO 为 103 / 21）。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("gpio") → open → 对象方法 / 回调函数            │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  gpio 模块（对象层）                                      │
│  · 模块表：open + 全部枚举常量                            │
│  · 引脚对象：userdata + 元表方法                          │
│  · 对象回收 / 虚拟机退出时释放本 VM 的回调与波形绑定      │
└────────────────────────────┬────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ IO 管理        │  │ 运行时事件队列   │  │ 波形引擎         │
│ 编号解析       │  │ 边沿捕获         │  │ 独立 IO 任务     │
│ 方向 / 上下拉  │  │ 消抖结算         │  │ 循环槽 + 插播    │
│ 快速读写       │  │ 投递到 Lua 调度  │  │ 与脚本并行       │
└───────────────┘  └────────┬────────┘  └─────────────────┘
                            │
                            ▼
                   Lua 调度循环里调用 cb
```

四条路径互不混用，按场景选一条即可。

| 路径 | 谁在跑时序 | 是否占用 Lua 调度 | 典型用途 |
| --- | --- | --- | --- |
| 读写 `set` / `get` / `tog` | 调用当场完成 | 极短 | 开关量、读按键电平 |
| 同步时序 `seq` | **当前 Lua 调用一直阻塞到播完** | 是，整段占用 | 一次性短脉冲、协议脚时序 |
| 波形 `wave_*` | **独立 IO 任务** | 否，脚本可继续 `rt.delay` | 指示灯、状态灯、心跳灯 |
| 边沿 `reg` | 硬件边沿唤醒 → 滤波结算 → 队列 → 调度循环回调 | 回调期间占用调度 | 按键、插拔、开关量变化 |

要点：

- **Lua 回调不在硬件中断里执行。** 中断路径只负责捕获和投递；滤波确认电平稳定后，才进入运行时队列；真正调用脚本函数发生在 Lua 调度循环。
- **所有 Lua 边沿回调都带消抖。** 没有“零滤波、边沿立刻进 Lua”的模式。短毛刺会被丢掉。
- **`seq` 与 `wave` 都按“起始电平 + 各段保持 + 结束动作”描述波形**，但执行位置不同：`seq` 在 Lua 调用栈上同步翻转；`wave` 把描述交给 IO 任务循环播放。
- 虚拟机退出时，本 VM 登记过的边沿回调和波形通道会被框架收回，避免脚本结束后仍占着硬件资源。

---

## 3. 对象模型

```lua
local led = gpio.open(gpio.INPUT_GPIO, 9)
```

`open` 返回带元表的 userdata。方法必须通过该对象调用。

### 3.1 两种调用写法

冒号是推荐写法，会把对象作为第一个参数传入：

```lua
led:set(true)           -- 推荐
led.set(led, true)      -- 等价
```

下面这种会失败（缺少对象自身）：

```lua
led.set(true)           -- 错误
gpio.set(led, true)     -- 错误：模块表上没有实例方法
```

### 3.2 布尔参数与整数参数

这是本模块最容易写错的地方，必须分开记。

| 接口 | 电平 / 方向怎么传 | 引擎 | `0` 表示什么 |
| --- | --- | --- | --- |
| `config` 的 `is_output`、`init_level` | **Lua 布尔语义** | `false` / `nil` 为假，其余为真 | **`0` 为真**（会当成输出 / 高电平） |
| `set` 的 `level` | 同上 | 同上 | **`0` 为高电平** |
| `seq` / `wave` 的起始电平、结束动作 | **整数 0 / 1** | 只接受 `0` 或 `1` | `0` = 低 |
| `wave_stop` 的 `hold_level` | **整数 -1 / 0 / 1** | 整数检查 | `0` = 落到低电平 |

推荐：

```lua
led:config(true, false)   -- 输出，初始低
led:set(true)             -- 拉高
led:set(false)            -- 拉低
led:seq(gpio.TIME_MS, {1, 200, 200, 0})   -- 数组里用 0/1
```

不要写 `led:set(0)` 指望拉低。在 Lua 里数字 `0` 是真值。

### 3.3 引用必须保住

边沿回调和波形通道挂在对象及当前虚拟机上。对象被垃圾回收后，对应回调和波形会被拆除。

```lua
local din = gpio.open(gpio.INPUT_GPIO, 1)
din:config(false, false, gpio.PULL_UP)
din:reg(gpio.IRQ_BOTH, 20, on_io)
-- 必须一直持有 din；不要只 open 一次不保存
```

---

## 4. 常量与枚举

全部挂在模块表上，值为整数。业务代码应使用符号名，不要散写魔数。

### 4.1 打开类型 `io_type`

用于 `gpio.open(type, id)` 的第一个参数。

| 符号 | 值 | 含义 | `id` 填什么 |
| --- | --- | --- | --- |
| `gpio.INPUT_GPIO` | `0` | 按芯片 GPIO 编号打开 | GPIOX，例如 `9` 表示 GPIO9 |
| `gpio.INPUT_PINNO` | `1` | 按模块引脚序号打开 | 模块对外 pin 号 |

两种写法打开的是同一条物理脚时，后续 `pins()` 会给出互相对应的 GPIO 编号和 pin 序号。编号必须落在 [1.2](#12-nt26-pro-map) / [1.3](#13-nt26-f6b0-映射表) 本机型表内，否则 `open` 抛错。当前不能改这对关系，见 [1.1](#11-gpio-与模块脚绑定)。

### 4.2 上下拉 `pull_mode`

用于 `obj:config(..., pull_mode)` 的第三参（可选）。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `gpio.PULL_AUTO` | `0` | 由复用功能自动控制（默认） |
| `gpio.PULL_UP` | `1` | 内部上拉 |
| `gpio.PULL_DOWN` | `2` | 内部下拉 |

输入脚建议显式 `PULL_UP` 或 `PULL_DOWN`，避免悬空抖动。输出脚通常用 `PULL_AUTO`。

### 4.3 边沿触发 `irq_mode`

用于 `obj:reg(irq_mode, ...)`。Lua 只导出边沿三种，**不导出电平触发、不导出关闭中断常量**。取消回调请用 `unreg()`。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `gpio.IRQ_FALLING` | `3` | 下降沿（高→低，滤波确认后回调） |
| `gpio.IRQ_RISING` | `4` | 上升沿（低→高，滤波确认后回调） |
| `gpio.IRQ_BOTH` | `5` | 双边沿 |

底层另有禁用 / 低电平 / 高电平取值，但 **未挂到 `gpio` 模块**，传入这些值会注册失败并抛错。

### 4.4 同步时序时间单位 `time_unit`

用于 `obj:seq(time_unit, payload)`。payload 中间每一段“保持多久”都按这个单位解释。

| 符号 | 值 | 单位 | 延时方式 |
| --- | --- | --- | --- |
| `gpio.TIME_SEC` | `0` | 秒 | 按系统 tick 休眠（让出 OS 线程） |
| `gpio.TIME_MS` | `1` | 毫秒 | 按系统 tick 休眠（让出 OS 线程） |
| `gpio.TIME_US` | `2` | 微秒 | 见下 |

`TIME_US` 细则：

- 保持值 `< 1000`：忙等微秒延时（占用 CPU，不让出调度）。
- 保持值 `≥ 1000`：先按毫秒部分 tick 休眠，再忙等剩余微秒。
- 保持值 `0`：该段不等待，立刻翻转到下一段。

`seq` 整段调用是同步的：返回前 Lua 调度循环被占住，其它 Lua 任务、定时器、IO 回调都要等它结束。短脉冲可以；长闪灯请用 `wave`。

### 4.5 波形量化

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `gpio.WAVE_QUANT_MS` | `100` | 波形保持时间的最小粒度（毫秒） |

`wave_reg` / `wave_insert` 的保持时间必须 `≥ WAVE_QUANT_MS`，且为它的整数倍。人眼可辨的指示灯用 100 / 200 / 500 / 1000 ms；不要拿 wave 做几十微秒的精确定时。

波形槽位数量、通道数量没有单独常量，见 [第 12 节](#12-资源上限与生命周期)：每脚槽位 `1..8`，整机同时跑 wave 的脚最多 8 路。

---

## 5. 类型约定

文档里用这些名字描述参数，不是独立的 Lua 类型。

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `GpioObj` | userdata | `gpio.open` 的返回值 |
| `io_type` | integer | `INPUT_GPIO` / `INPUT_PINNO` |
| `id` | integer | 0–255 范围内的合法编号 |
| `bool_level` | boolean（按真假） | `true` 高 / `false` 低 |
| `bit_level` | integer | 仅 `0` 或 `1` |
| `pull_mode` | integer | `PULL_AUTO` / `PULL_UP` / `PULL_DOWN` |
| `irq_mode` | integer | `IRQ_FALLING` / `IRQ_RISING` / `IRQ_BOTH` |
| `time_unit` | integer | `TIME_SEC` / `TIME_MS` / `TIME_US` |
| `wave_id` | integer | **Lua 从 1 起算**，`1..8` |
| `hold_level` | integer | `-1` 保持，`0` 低，`1` 高 |
| `SeqPayload` | table | 见第 8 节 |
| `WavePayload` | number 或 table | 见第 9 节 |
| `IrqInfo` | table | 见第 10 节 |

---

## 6. 模块函数

模块表上 **只有** `open` 一个函数，其余都是对象方法。

### `gpio.open(type, id) → GpioObj`

打开一条脚，返回对象。

**调用模式（仅一种）**

```lua
gpio.open(type, id)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `io_type` | 是 | `gpio.INPUT_GPIO` 或 `gpio.INPUT_PINNO` |
| `id` | integer | 是 | 对应类型下的编号 |

**返回**

- 成功：`GpioObj`
- 失败：抛错，不返回 `nil`

| 失败原因 | 错误信息（摘要） |
| --- | --- |
| `type` 不是两种打开类型之一 | `invalid io_type, expect INPUT_GPIO/INPUT_PINNO` |
| IO 框架初始化失败 | `gpio init failed` |
| 编号无法解析到合法脚 | `invalid pin` |
| 打开失败 | `gpio open failed` |

**示例**

```lua
local led  = gpio.open(gpio.INPUT_GPIO, 9)   -- GPIO9
local din  = gpio.open(gpio.INPUT_GPIO, 1)
local by_pin = gpio.open(gpio.INPUT_PINNO, 23)  -- 按模块 pin 23
```

打开不等于配置。未 `config` 前不要假设方向和电平。

---

## 7. 对象方法

除特别说明外，第一个隐含参数都是 `self`（冒号调用自动传入）。

---

### 7.1 `obj:config(is_output, init_level [, pull_mode]) → boolean` {#7-1-config}

配置方向、初始电平和上下拉。

**调用模式**

```lua
obj:config(is_output, init_level)
obj:config(is_output, init_level, pull_mode)
```

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `is_output` | boolean 语义 | 是 | — | `true` 输出，`false` 输入 |
| `init_level` | boolean 语义 | 是 | — | 输出时的初始电平；输入脚可传 `false` |
| `pull_mode` | `pull_mode` | 否 | `gpio.PULL_AUTO` | 省略或 `nil` 即默认 |

第三参省略、显式 `nil` 都走默认上拉模式 `PULL_AUTO`。传入整数 `0/1/2` 与三个符号等价，但推荐符号。

**返回**

- `true` 配置成功
- `false` 配置失败（非法脚、硬件拒绝等），**不抛错**

**示例**

```lua
led:config(true, false)                          -- 输出，初始低，默认 PULL_AUTO
led:config(true, false, gpio.PULL_AUTO)
din:config(false, false, gpio.PULL_UP)           -- 输入上拉
din:config(false, false, gpio.PULL_DOWN)
```

`init_level` 仅在输出时有硬件意义。输入模式仍必须传第二参，占位即可。

---

### 7.2 `obj:set(level) → boolean` {#7-2-set}

把输出脚写成指定电平。

**调用模式（仅一种）**

```lua
obj:set(level)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `level` | boolean 语义 | 是 | `true` 高，`false` 低 |

**返回**

- `true` 成功
- `false` 失败（未配置成输出、句柄无效等），**不抛错**

```lua
led:set(true)
led:set(false)
```

对输入脚调用没有明确的业务含义，不要依赖其副作用。

---

### 7.3 `obj:get() → integer | nil` {#7-3-get}

读当前电平。输入、输出都可以读。

**调用模式（仅一种）**

```lua
obj:get()
```

无参数。

**返回**

- 成功：整数 `0`（低）或 `1`（高）
- 失败：`nil`

注意返回的是 **整数 0/1**，不是 boolean。判断时请写 `== 1` / `== 0`，不要直接当条件（`0` 在 Lua 里也是真）。

```lua
local lv = led:get()
if lv == nil then
    -- 读失败
elseif lv == 1 then
    -- 高
else
    -- 低
end
```

---

### 7.4 `obj:tog() → integer | nil` {#7-4-tog}

读当前电平，翻转后写出，返回翻转后的电平。

**调用模式（仅一种）**

```lua
obj:tog()
```

无参数。

**返回**

- 成功：翻转后的 `0` 或 `1`
- 读失败或写失败：`nil`

一般只用于输出脚。

```lua
local after = led:tog()
```

---

### 7.5 `obj:pins() → gpio, pin_no, type, id` {#7-5-pins}

查询该对象实际绑定关系。一次返回四个整数。返回的 GPIO 与 PIN 就是 [1.2](#12-nt26-pro-map) / [1.3](#13-nt26-f6b0-映射表) 里的固定对，脚本改不了。

**调用模式（仅一种）**

```lua
local gpio_id, pin_no, type, id = obj:pins()
```

| 返回序号 | 名字 | 含义 |
| --- | --- | --- |
| 1 | `gpio` | 解析后的芯片 GPIO 编号 |
| 2 | `pin_no` | 对应的模块引脚序号（无映射时为 `255`） |
| 3 | `type` | 打开时用的 `io_type` |
| 4 | `id` | 打开时传入的编号 |

四个值都是 number，打开成功后始终可取。

```lua
local g, pin, typ, id = led:pins()
-- typ == gpio.INPUT_GPIO 或 gpio.INPUT_PINNO
```

---

### 7.6 `obj:seq(time_unit, payload) → true` {#7-6-seq}

在 **当前调用里同步播放** 一段电平时序，播完才返回。

**调用模式（仅一种）**

```lua
obj:seq(time_unit, payload)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `time_unit` | `time_unit` | 是 | `TIME_SEC` / `TIME_MS` / `TIME_US` |
| `payload` | `SeqPayload` | 是 | 必须是 table，见第 8 节 |

**返回**

- 成功：`true`
- 失败：抛错（单位非法、数组不合法、硬件翻转失败）

```lua
led:seq(gpio.TIME_MS, {1, 200, 200, 200, 0})
led:seq(gpio.TIME_US, {1, 50, 50, 0})
led:seq(gpio.TIME_SEC, {1, 1, 1, 0})
```

阻塞语义见第 2 节、第 8 节。指示灯长循环不要用 `seq`。

---

### 7.7 `obj:wave_reg(wave_id, payload) → true` {#7-7-wave-reg}

把一种波形登记到本脚的槽位。第一次对某脚调用任意 `wave_*` 时，框架会把该脚绑定到一条波形通道。

**调用模式（payload 两种形态）**

```lua
obj:wave_reg(wave_id, 0)                 -- 常灭
obj:wave_reg(wave_id, 1)                 -- 常亮
obj:wave_reg(wave_id, {0})               -- 等价常灭
obj:wave_reg(wave_id, {1})               -- 等价常亮
obj:wave_reg(wave_id, {start, ms..., end})  -- 循环图案
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `wave_id` | integer | 是 | `1..8`（Lua 从 1 起算） |
| `payload` | number 或 table | 是 | 见第 9 节 |

同一 `wave_id` 再次 `wave_reg` 会覆盖该槽。登记不等于播放，必须再 `wave_set`。

**返回**

- 成功：`true`
- 失败：抛错

| 失败原因 | 错误信息（摘要） |
| --- | --- |
| `wave_id` 越界 | `wave_id expect 1..8` |
| payload 非法（含保持时间不是 100ms 倍数） | `invalid wave payload ...` |
| 整机波形通道用尽或绑定失败 | `wave bind failed` |
| 登记失败 | `wave_reg failed` |

---

### 7.8 `obj:wave_set(wave_id) → true` {#7-8-wave-set}

选择已登记的槽，开始 **循环播放**。

**调用模式（仅一种）**

```lua
obj:wave_set(wave_id)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `wave_id` | integer | 是 | `1..8`，且该槽已 `wave_reg` |

切换时机：

- 常亮 / 常灭：立刻生效。
- 闪烁图案：在当前段边界切换，不会在一段保持中间切断。

脚本调用返回后即可去做别的事，灯由 IO 任务继续闪。

**返回**

- 成功：`true`
- 失败：抛错（未登记、通道绑定失败等）

---

### 7.9 `obj:wave_insert(payload) → true` {#7-9-wave-insert}

插播 **一次** 图案。播完自动回到当前正在循环的波形。

**调用模式（仅一种，且必须是完整图案表）**

```lua
obj:wave_insert({start, ms..., end})
```

不接受数字 `0` / `1`，不接受单元素 `{0}` / `{1}`。插播只支持完整图案（至少：起始电平、一段保持、结束动作）。

在段边界开始插播。Lua 调用本身立即返回，不阻塞到插播结束。

**返回**

- 成功：`true`
- 失败：抛错（`wave_insert needs pattern table` / 绑定失败 / 插入失败）

---

### 7.10 `obj:wave_stop([hold_level]) → true` {#7-10-wave-stop}

停止本脚的循环波形和插播。

**调用模式**

```lua
obj:wave_stop()          -- 保持停止瞬间的电平
obj:wave_stop(nil)       -- 同上
obj:wave_stop(-1)        -- 同上，显式“保持”
obj:wave_stop(0)         -- 停到低电平
obj:wave_stop(1)         -- 停到高电平
```

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `hold_level` | integer | 否 | `-1`（保持） | 省略或 `nil` 视为保持；只能 `-1` / `0` / `1` |

本脚从未绑定过波形通道时，视为已停止，返回 `true`，不抛错。

非法值（如 `2`）抛错：`hold_level expect -1/0/1`。

---

### 7.11 `obj:reg(irq_mode, debounce_ms, cb) → true` {#7-11-reg}

注册边沿回调。同一脚在同一虚拟机上重复 `reg` 会覆盖旧回调。

**调用模式（仅一种）**

```lua
obj:reg(irq_mode, debounce_ms, cb)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `irq_mode` | `irq_mode` | 是 | `IRQ_FALLING` / `IRQ_RISING` / `IRQ_BOTH` |
| `debounce_ms` | integer | 是 | 稳定窗口，毫秒。小于 10 会被抬到 10 |
| `cb` | function | 是 | 见第 10 节，必须是函数 |

**返回**

- 成功：`true`
- 失败：抛错

| 失败原因 | 错误信息（摘要） |
| --- | --- |
| 第四参不是函数 | Lua 类型错误 |
| 框架未就绪 | `gpio init failed` |
| 不在合法虚拟机上下文 | `rt vm context missing` |
| 回调槽用尽（整机上限 80） | `gpio reg full` |
| 底层注册失败 | `gpio reg failed: <code>` |

回调执行路径、滤波语义、第四参字段见第 10 节。

---

### 7.12 `obj:unreg() → boolean` {#7-12-unreg}

取消本脚在当前虚拟机上的边沿回调。

**调用模式（仅一种）**

```lua
obj:unreg()
```

无参数。

**返回**

- `true`：确实卸掉了一条登记
- `false`：本脚当前没有登记，或框架未就绪

`unreg` **不抛错**。对象被回收、虚拟机退出时，框架也会自动卸载，不必每个对象都手动 `unreg`，但长时间不用的脚主动卸掉更清晰。

---

## 8. 时序 payload（seq）

### 8.1 数组形态

必须是 Lua 数组（下标从 1 起的整数表），长度 **至少 3**：

```
{ 起始电平, 保持1, 保持2, ..., 保持N, 结束动作 }
```

| 位置 | 约束 | 含义 |
| --- | --- | --- |
| `[1]` 起始电平 | 整数 `0` 或 `1` | 一开始先写成该电平 |
| `[2] .. [#n-1]` 保持 | 整数 `≥ 0`，不超过 32 位无符号上限 | 保持 **当前电平** 这么多个单位，然后翻转 |
| `[#n]` 结束动作 | 整数 `0` 或 `1` | `0`：最后一段保持并翻转后停住；`1`：整段结束后再翻转一次 |

不是“高低列表”，而是“保持多久再翻一次”。翻转次数 = 保持段数；结束动作再决定要不要多翻一次。

### 8.2 逐步推演

```lua
led:seq(gpio.TIME_MS, {1, 200, 200, 200, 0})
```

| 步骤 | 动作 | 电平 |
| --- | --- | --- |
| 起始 | 写成 `1` | 高 |
| keep 200 | 高保持 200ms，然后翻转 | 低 |
| keep 200 | 低保持 200ms，然后翻转 | 高 |
| keep 200 | 高保持 200ms，然后翻转 | 低 |
| 结束动作 `0` | 不再翻转 | **停在低** |

若结束动作改为 `1`，最后会再翻一次，停在高。

最短合法例子：

```lua
{1, 200, 0}   -- 拉高 → 高 200ms → 翻到低 → 结束不翻 → 停在低
{0, 100, 1}   -- 拉低 → 低 100ms → 翻到高 → 结束再翻 → 停在低
```

### 8.3 非法形态

以下都会使 `seq` 抛错 `gpio seq failed` 或参数错误：

- 不是 table
- 长度小于 3
- 起始 / 结束不是 `0` 或 `1`
- 保持值为负，或超出 32 位无符号范围
- `time_unit` 不是三个时间常量之一

### 8.4 阻塞与精度

- 调用线程（Lua 调度所在 OS 线程）被占到播完。
- `TIME_MS` / `TIME_SEC` 按系统 tick 取整向上，不是示波器级精度。
- `TIME_US` 短于 1ms 的段是忙等，会卡住 CPU；只适合极短脉冲。
- 保持 `0` 表示该段不等待、立刻翻转，可用来在逻辑上插入一次翻转。

---

## 9. 波形 payload（wave）

与 `seq` 同形，但：

- 时间单位固定为毫秒，粒度 `gpio.WAVE_QUANT_MS`（100）。
- 由独立 IO 任务循环执行，不阻塞 Lua。
- 额外支持“常亮 / 常灭”快捷写法。

### 9.1 三种合法写法（`wave_reg`）

| 写法 | 长度 | 含义 |
| --- | --- | --- |
| 数字 `0` | — | 常灭（长低） |
| 数字 `1` | — | 常亮（长高） |
| `{0}` 或 `{1}` | 1 | 与数字快捷等价 |
| `{start, ms..., end}` | ≥ 3 | 循环图案 |

图案规则：

- `start`、`end` 只能是 `0` 或 `1`。
- 中间每一段是毫秒，必须 `≥ 100` 且 `% 100 == 0`。
- 每一段保持结束后翻转，语义与 `seq` 相同。
- 保持段数最多 16，因此完整表最长为 `2 + 16 = 18` 个元素。

```lua
led:wave_reg(1, 0)                         -- 常灭
led:wave_reg(2, 1)                         -- 常亮
led:wave_reg(3, {1, 1000, 1000, 0})        -- 1s 亮 / 1s 灭，循环
led:wave_reg(4, {1, 200, 200, 0})          -- 200ms 闪
led:wave_reg(5, {1, 200, 200, 200, 800, 0}) -- 两短一长
```

`{1, 200, 200, 0}` 循环时：高 200ms → 低 200ms → 结束不额外翻转 → 下一圈再从起始电平开始。结束动作 `0` 时，一圈结束时电平已是“最后一次翻转后”的值；引擎按图案循环，不必在 Lua 里再补翻转。

### 9.2 `wave_insert` 只接受图案表

```lua
led:wave_insert({1, 100, 100, 100, 100, 0})  -- 合法
led:wave_insert(1)                            -- 非法
led:wave_insert({1})                          -- 非法
```

插播在段边界生效。结束后回到 `wave_set` 正在循环的那条槽（若当时是常亮/常灭，就回到常亮/常灭）。

### 9.3 通道绑定时机

第一次 `wave_reg` / `wave_set` / `wave_insert` 会把该脚绑到一条波形通道。之后同一对象复用这条通道。对象回收或虚拟机退出时解绑。

整机同时绑定上限 8 路。第 9 路会 `wave bind failed`。指示灯用 wave；不要给每一根普通 IO 都开 wave。

---

## 10. 边沿回调协议

### 10.1 不是实时中断业务

```
硬件边沿
  → 中断路径只投递（不做 Lua、不做业务）
  → 滤波状态机：候选电平必须在 debounce_ms 窗口内保持稳定
  → 窗口走满且电平仍稳定，才算一次结算
  → 结算结果进入运行时事件队列
  → Lua 调度循环取出后调用 cb
```

因此：

- 回调里看到的是 **结算后的稳定电平**，不是每一次硬件毛刺。
- 短于窗口的脉冲会被丢掉。
- 时延是“滤波窗口 + 排队 + 调度”，量级在毫秒以上，不适合测脉宽、高速码流、微秒级捕获。
- `debounce_ms < 10` 会被抬到 10。没有关闭滤波的参数。

适合：按键、插拔、门磁、开关量。不适合：软件串口、编码器高速计数、精确脉宽。

### 10.2 回调签名

```lua
function cb(gpio_id, pin_no, level, info)
```

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `gpio_id` | integer | 芯片 GPIO 编号 |
| `pin_no` | integer | 模块引脚序号 |
| `level` | integer | 结算后的电平，`0` 或 `1` |
| `info` | table | 时间元数据，见下 |

`info` 字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `info.os_tick` | integer | 结算瞬间的内核 tick |
| `info.os_tick_ms` | number | 该 tick 换算的毫秒 |
| `info.utc_ms` | number | 结算瞬间 UTC 毫秒时间戳；取不到时为 `0` |
| `info.keep_ms` | number | **上一次结算到本次结算** 维持了多久（毫秒）。不区分高/低，只表示上一段状态持续时长。首次无法计算时为 `0`。数值较粗，可做长按/短按的粗判断，不要当精密计时。 |

回调在 **调度循环** 里执行，不是独立 `rt.task`。回调返回前，整台 Lua 调度被占住：

- 不要 `rt.delay`（不是任务协程，会报错或卡死调度）。
- 不要打长 log、组包、`seq`、死循环。
- 正确用法：把事件投递到邮箱 / 置标志，立刻返回；打印和业务状态机放到 `rt.task_start` 的任务里做。

```lua
local function on_io(gpio_id, pin_no, level, info)
    rt.mbox_send("gpio1", {
        gpio = gpio_id,
        pin_no = pin_no,
        level = level,
        keep_ms = info and info.keep_ms or 0,
    })
end

din:reg(gpio.IRQ_BOTH, 20, on_io)
```

回调内部若抛错，框架会记录后吞掉，不影响调度循环继续跑，但这次事件已经结束。

---

## 11. 错误与返回约定

本模块混用了两种失败风格，按接口记：

| 风格 | 接口 | 成功 | 失败 |
| --- | --- | --- | --- |
| 抛错 | `open` / `seq` / `wave_*` / `reg` | 对象或 `true` | `error` |
| 布尔 / nil | `config` / `set` | `true` | `false` |
| 布尔 / nil | `get` / `tog` | `0` 或 `1` | `nil` |
| 布尔 / nil | `unreg` | `true` 卸掉了 | `false` 本来就没有 |
| 多返回值 | `pins` | 四个 integer | 打开都成功才有对象，不会在这里失败 |

用 `pcall` 包住会抛错的接口：

```lua
local ok, err = pcall(function()
    led:wave_reg(1, {1, 150, 0})  -- 150 不是 100 的倍数，会抛错
end)
```

参数类型错误（该 table 给了 number、该 function 给了 nil）走 Lua 标准 `bad argument` 报错。

**全部抛错摘要**（`config`/`set` 失败只回 `false`，`get`/`tog` 失败只回 `nil`，没有第二返回值）：

| 摘要 | 可能原因 |
| --- | --- |
| `gpio init failed` | 底层 GPIO 没起来（极少，整机初始化） |
| `invalid pin` | 编号不在本机型固定映射表里（见 [1.2](#12-nt26-pro-map) / [1.3](#13-nt26-f6b0-映射表)），或该脚未对脚本开放 |
| `gpio open failed` | 打开失败：脚已被占用或映射无效 |
| `gpio seq failed` | `seq` 图案非法、粒度不对、或执行中失败 |
| `gpio seq final toggle failed` | 收尾翻转没做成 |
| `wave_id expect 1..N` | 波形 id 超出 1～8（N 为当时上限） |
| `wave bind failed` | 该脚绑不到波形通道（通道满 8 路，或脚不能做波形） |
| `invalid wave payload (ms must be >=N and multiple of N)` | 保持时间不是 100ms 粒度（N 现为 100） |
| `wave_reg failed` | 登记图案失败（段数超 16 等） |
| `wave_set failed` | 切换已登记波形失败（id 未 reg） |
| `wave_insert needs pattern table` | `wave_insert` 第二参不是 table |
| `wave_insert failed` | 插入失败（通道未绑定或图案非法） |
| `hold_level expect -1/0/1` | `wave_stop` 的保持电平 |
| `wave_stop failed` | 停止失败 |
| `rt vm context missing` | `reg` 时不在脚本 VM |
| `gpio reg full` | 整机边沿回调槽满（80） |
| `gpio reg failed: N` | 底层登记失败，N 为内部返回值 |

`unreg` 本来就没有回调时返回 `false`，不是错误。诊断：`invalid pin`/`open failed` 对原理图；`reg full` 先 `unreg` 不用的脚；波形类先查 100ms 粒度和通道数。

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 边沿回调登记 | 80 | 整机 Lua 侧槽位；满则 `gpio reg full` |
| 波形通道 | 8 | 同时把脚交给 IO 任务的数量 |
| 每脚波形槽 | 8 | `wave_id` 为 `1..8` |
| 每条图案保持段 | 16 | `wave` 图案中间最多 16 个保持值 |
| 消抖下限 | 10 ms | `reg` 的窗口会被抬到至少 10 |
| 波形时间粒度 | 100 ms | `WAVE_QUANT_MS` |

生命周期：

1. `open` 创建对象，按本机型固定表解析 GPIO ↔ PIN（见 [1.1](#11-gpio-与模块脚绑定)）。表外编号打不开。
2. `config` 设定电气属性。
3. `reg` 把回调挂到当前虚拟机；重复 `reg` 覆盖。
4. `wave_*` 首次使用时绑定通道；对象回收时解绑并停止波形。
5. 对象 `__gc`：卸边沿回调、解波形。
6. 虚拟机退出：清掉该 VM 的全部 GPIO 回调与波形绑定。

脚本应把仍在使用的对象放在模块级或长生命周期的 `local` 里，避免被过早回收导致灯停、回调丢失。

---

## 13. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 拉高 / 拉低 / 读一下 | `set` / `get` / `tog` |
| 一次性短脉冲、同步协议脚 | `seq`（注意阻塞） |
| 多盏灯各自闪、脚本还要干活 | `wave_reg` + `wave_set` |
| 告警时插一下快闪再回到慢闪 | `wave_insert` |
| 按键 / 插拔 / 开关量 | `config` 输入 + `reg` |
| 微秒级脉宽、高速边沿计数 | **不要用本模块回调** |

`seq` 和 `wave` 数组长得像，执行模型完全不同：一个卡 Lua，一个不卡。选错会把整台脚本拖成“闪灯专用机”。

---

## 14. 完整示例

### 14.1 输出 + 输入 + 同步时序

```lua
local rt   = require("rt")
local log  = require("log")
local gpio = require("gpio")

local led = gpio.open(gpio.INPUT_GPIO, 9)
local din = gpio.open(gpio.INPUT_GPIO, 1)

led:config(true, false, gpio.PULL_AUTO)
din:config(false, false, gpio.PULL_UP)

local g, pin, typ, id = led:pins()
log.info("led gpio=%d pin=%d type=%d id=%d", g, pin, typ, id)

led:set(true)
log.info("get=%s", led:get())
log.info("tog -> %s", led:tog())

led:seq(gpio.TIME_MS, {1, 200, 200, 200, 0})

while true do
    log.info("led=%s din=%s", led:tog(), din:get())
    rt.delay(1000)
end
```

### 14.2 边沿回调 + 工作任务

```lua
local rt   = require("rt")
local log  = require("log")
local gpio = require("gpio")

local TOPIC = "gpio1"

rt.task_start(function()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok and type(ev) == "table" then
            log.info("gpio=%d level=%d keep_ms=%s",
                     ev.gpio, ev.level, ev.keep_ms)
        end
    end
end)

local din = gpio.open(gpio.INPUT_GPIO, 1)
din:config(false, false, gpio.PULL_UP)
din:reg(gpio.IRQ_BOTH, 20, function(gpio_id, pin_no, level, info)
    rt.mbox_send(TOPIC, {
        gpio = gpio_id,
        pin_no = pin_no,
        level = level,
        keep_ms = info and info.keep_ms or 0,
    })
end)

while true do
    rt.delay(10000)
end
```

### 14.3 指示灯交给 IO 任务

```lua
local rt   = require("rt")
local log  = require("log")
local gpio = require("gpio")

local W_OFF, W_ON, W_SLOW, W_FAST, W_BEAT = 1, 2, 3, 4, 5

local led = gpio.open(gpio.INPUT_GPIO, 9)
led:config(true, false, gpio.PULL_AUTO)

led:wave_reg(W_OFF, 0)
led:wave_reg(W_ON, 1)
led:wave_reg(W_SLOW, {1, 1000, 1000, 0})
led:wave_reg(W_FAST, {1, 200, 200, 0})
led:wave_reg(W_BEAT, {1, 200, 200, 200, 800, 0})

while true do
    led:wave_set(W_SLOW)
    rt.delay(4000)
    led:wave_set(W_FAST)
    rt.delay(4000)
    led:wave_insert({1, 100, 100, 100, 100, 0})
    rt.delay(4000)
    led:wave_stop(0)
    rt.delay(2000)
end
```

---

## 附录 A. 方法速查

| 调用 | 参数模式 | 返回 |
| --- | --- | --- |
| `gpio.open(type, id)` | 2 个必填 | `GpioObj` 或抛错 |
| `obj:config(out, level)` | 2 个必填 | `boolean` |
| `obj:config(out, level, pull)` | 3 个 | `boolean` |
| `obj:set(level)` | 1 个必填，布尔语义 | `boolean` |
| `obj:get()` | 无 | `0\|1\|nil` |
| `obj:tog()` | 无 | `0\|1\|nil` |
| `obj:pins()` | 无 | 4 个 integer |
| `obj:seq(unit, table)` | 2 个必填 | `true` 或抛错 |
| `obj:wave_reg(id, 0\|1)` | 快捷常亮/灭 | `true` 或抛错 |
| `obj:wave_reg(id, table)` | 图案或 `{0}`/`{1}` | `true` 或抛错 |
| `obj:wave_set(id)` | 1 个必填 | `true` 或抛错 |
| `obj:wave_insert(table)` | 仅完整图案表 | `true` 或抛错 |
| `obj:wave_stop()` | 无，保持电平 | `true` 或抛错 |
| `obj:wave_stop(-1\|0\|1)` | 保持 / 低 / 高 | `true` 或抛错 |
| `obj:reg(mode, ms, cb)` | 3 个必填 | `true` 或抛错 |
| `obj:unreg()` | 无 | `boolean` |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `gpio.INPUT_GPIO` | 0 |
| `gpio.INPUT_PINNO` | 1 |
| `gpio.PULL_AUTO` | 0 |
| `gpio.PULL_UP` | 1 |
| `gpio.PULL_DOWN` | 2 |
| `gpio.IRQ_FALLING` | 3 |
| `gpio.IRQ_RISING` | 4 |
| `gpio.IRQ_BOTH` | 5 |
| `gpio.TIME_SEC` | 0 |
| `gpio.TIME_MS` | 1 |
| `gpio.TIME_US` | 2 |
| `gpio.WAVE_QUANT_MS` | 100 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.1.0 | 2026-09-05 | 补全全部抛错摘要与可能原因 |
| 1.2.0 | 2026-09-05 | 写入 F6E0 / F6B0 的 GPIO↔PIN 固定映射；说明当前不支持用户改绑 |
| 1.2.1 | 2026-09-05 | 标明 NT26-PRO 使用 F6E0 与 F6D0；F6D0 与 F6E0 共用同一张映射表 |
| 1.2.2 | 2026-09-05 | 脚本 GPIO 表链到 hardware 全 IO 文档 |
| 1.2.3 | 2026-09-05 | 链到硬件落盘区 GPIO（含 PDDR） |
