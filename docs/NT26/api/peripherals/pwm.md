# pwm

**文档版本** `1.0.1`

对象化硬件 PWM。按模块管脚号或芯片 PAD 打开一路，再 `start` 出波。波形由 TIMER 或常电 APWM 产生，不是 GPIO 翻转。

```lua
local pwm = require("pwm")
```

平台预加载模块，无需额外 `.lua` 文件。

同一颗脚不要再 `gpio.open`。开发板 NET 灯若接到 PWM 脚，先把 `rtu_config.cfg` 里 `net_led` 的 `enable` 设成 `0`，否则和脚本抢脚。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `pwm.open`](#6-1-open)
  - [6.2 `pwm.pins`](#6-2-pins)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:start`](#7-1-start)
  - [7.2 `obj:set_duty`](#7-2-set-duty)
  - [7.3 `obj:set_freq`](#7-3-set-freq)
  - [7.4 `obj:stop`](#7-4-stop)
  - [7.5 `obj:close`](#7-5-close)
  - [7.6 `obj:info`](#7-6-info)
- [8. `start` 配置表](#8-start-配置表)
- [9. TIMER 与 APWM](#9-timer-与-apwm)
- [10. 互补输出](#10-互补输出)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

典型用法：

1. `pwm.pins()` 看当前机型哪些脚能出 PWM / APWM。
2. `pwm.open(pwm.INPUT_PINNO, pin)` 占用那颗脚，得到对象。此时还不出波。
3. `obj:start(opt)` 选 TIMER 或 APWM，设频率/占空比，硬件开始出方波。
4. 运行中用 `set_duty` / `set_freq` 微调；`stop` 停波但脚仍占用；`close` 释放。

两条硬件路径不要混用在一次 `start` 里：

| 路径 | 适合 | 不适合 |
| --- | --- | --- |
| `MODE_TIMER` | LED 调光、蜂鸣器、电机、kHz～MHz | 休眠后还要闪（休眠时钟会停） |
| `MODE_APWM` | 休眠状态灯，周期 32 ms～4096 ms | 蜂鸣器、电机、精细调光 |

默认 `start` 走 TIMER。能出 APWM 的脚也必须显式 `mode = pwm.MODE_APWM`。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  open → start / set_duty / set_freq / stop / close       │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  pwm 对象                                                │
│  · 一脚一个实例                                          │
│  · open 占 PAD，start 才出波                             │
│  · 回收 / close 停波并释放                               │
└────────────────────────────┬────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼                             ▼
┌─────────────────────┐          ┌─────────────────────┐
│  TIMER PWM           │          │  APWM（常电）        │
│  通道 0～5，可到 MHz │          │  通道 0～2           │
│  可选互补脚          │          │  8 档毫秒周期        │
└─────────────────────┘          └─────────────────────┘
```

| 路径 | 谁在出波 | 是否占用 Lua 调度 |
| --- | --- | --- |
| `start` / `set_duty` / `set_freq` | 硬件 | 否（配置当场完成） |
| `open` / `stop` / `close` | 占脚 / 停波 | 否 |
| `pins` / `info` | 只读表 | 否 |

没有回调。呼吸灯要自己 `rt.delay` 循环改占空比。

---

## 3. 对象模型

```lua
local ch = pwm.open(pwm.INPUT_PINNO, 16)
```

`open` 返回 userdata。方法只在对象元表上。

### 3.1 两种调用写法

```lua
ch:start(opt)
ch.start(ch, opt)     -- 等价
```

错误：`ch.start(opt)`（缺对象）、`pwm.start(ch, opt)`（模块表没有实例方法）。

模块表上只有 `open`、`pins` 和枚举常量。

### 3.2 引用

请持有 `ch`。引用丢了会走回收：停波并释放 PAD。互补脚随正相一起释放。

`open` 成功后脚已被占用，即使还没 `start`。同一 PAD 再 `open` 会抛 `pwm busy`。

---

## 4. 常量与枚举

### 4.1 打开类型（`pwm.open` 第一参）

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `pwm.INPUT_PDDR` | `0` | 芯片 PAD 地址 | `open` 的 `type`；`comp.type` |
| `pwm.INPUT_PINNO` | `1` | 模块对外管脚号 | 同上 |

编号与 [`gpio`](gpio.md) 的 `INPUT_PINNO` 是同一套模块脚号，但 PWM **不按 GPIO 号打开**。PAD 与脚的对应以 `pwm.pins()` 为准。

### 4.2 出波模式（`opt.mode`）

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `pwm.MODE_TIMER` | `0` | TIMER 硬件 PWM（默认） |
| `pwm.MODE_APWM` | `1` | 常电 APWM |

其它整数：`start` 失败抛 `invalid param`。

### 4.3 TIMER 时钟（`opt.clk`）

| 符号 | 值 | 大约频率 | 用途 |
| --- | --- | --- | --- |
| `pwm.CLK_40K` | `0` | 40 kHz | 很低的 TIMER 频率 |
| `pwm.CLK_26M` | `1` | 26 MHz | **默认**，kHz～约 1 MHz |
| `pwm.CLK_102M` | `2` | 102 MHz | 更高频、占空比更细（视芯片是否提供） |

`freq` 必须 **小于** 所选时钟。26 M 下 1 MHz 大约 26 个 tick，占空比步进会变粗。

### 4.4 停波电平（`opt.stop`，仅 TIMER）

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `pwm.STOP_LOW` | `0` | 停止后保持低（默认） |
| `pwm.STOP_HIGH` | `1` | 停止后保持高 |
| `pwm.STOP_HOLD` | `2` | 停止后保持当前电平 |

APWM 忽略此项。

### 4.5 APWM 周期档（`opt.period`）

芯片没有连续频率，只能 8 档。数值是档位，**不是毫秒数**。请用符号，不要写 `1024`。

| 符号 | 值 | 周期 | 大约频率 |
| --- | --- | --- | --- |
| `pwm.APWM_4096MS` | `0` | 4096 ms | ~0.24 Hz |
| `pwm.APWM_2048MS` | `1` | 2048 ms | ~0.49 Hz |
| `pwm.APWM_1024MS` | `2` | 1024 ms | ~0.98 Hz |
| `pwm.APWM_512MS` | `3` | 512 ms | ~1.95 Hz |
| `pwm.APWM_256MS` | `4` | 256 ms | ~3.91 Hz |
| `pwm.APWM_128MS` | `5` | 128 ms | ~7.81 Hz |
| `pwm.APWM_64MS` | `6` | 64 ms | ~15.63 Hz |
| `pwm.APWM_32MS` | `7` | 32 ms | ~31.25 Hz |

未挂到模块的其它档位不要传。超出 `0`～`7`：`start` 抛 `invalid param`。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `type` | integer | `INPUT_PDDR` / `INPUT_PINNO` |
| `id` | integer | 0～255，PAD 或模块脚号 |
| `opt` | table | `start` 配置，见 [第 8 节](#8-start-配置表) |
| `duty` | integer | 0～100，百分占空比 |
| `freq` / `hz` | integer | 赫兹，必须 `> 0` |
| `comp` | table | `{ type = ..., id = ... }` |

`start` 表里的数字键走 **整数或 number**（`1000.0` 能当 1000）。`set_duty` / `set_freq` / `open` 的独立参数走 `checkinteger`，请写整数。

`duty`、`high`、`low` 都是 0～100 的百分比，不是 tick。

---

## 6. 模块函数

---

### 6.1 `pwm.open(type, id)` {#6-1-open}

占用一颗可 PWM 的脚，返回对象。**此时还没有波形。**

**调用模式**

```lua
pwm.open(pwm.INPUT_PINNO, id)
pwm.open(pwm.INPUT_PDDR, id)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `type` | 是 | `INPUT_PINNO` 或 `INPUT_PDDR` |
| `id` | 是 | 模块脚号或 PAD；0～255 |

成功：userdata。失败：**抛错**。

| 文案 | 原因 |
| --- | --- |
| `invalid type, expect INPUT_PDDR/INPUT_PINNO` | `type` 不是那两个 |
| `invalid id` | `id` 小于 0 或大于 255 |
| `pwm.open failed: pin not found / no pwm` | 脚不存在，或表里没有 PWM 能力 |
| `pwm.open failed: pwm busy` | 该 PAD 已被另一个对象占用（含被别人当互补脚占用） |

```lua
local ch = pwm.open(pwm.INPUT_PINNO, 16)
```

先 `pwm.pins()` 确认这颗脚有 `timer` 或 `apwm` 字段。

---

### 6.2 `pwm.pins()` {#6-2-pins}

列出当前机型可作 PWM 的 PAD，不占用、不出波。

**调用模式**

```lua
pwm.pins()
```

成功：数组表。每项字段：

| 字段 | 何时有 | 说明 |
| --- | --- | --- |
| `pddr` | 总有 | 芯片 PAD，给 `open(INPUT_PDDR, …)` |
| `pin_no` | 有模块引出时 | 模块管脚号 |
| `timer` | 能出正相 TIMER PWM | 通道 0～5 |
| `mux` | 有 `timer` 时 | 正相复用号 |
| `n_ch` | 可作互补输出时 | 可作为哪一路的反相（PWM*n*） |
| `apwm` | 能出 APWM 时 | APWM 序号 0～2 |

没有该能力的字段直接缺省，不是 `nil` 填进去。用 `ipairs` 遍历。

```lua
for i, p in ipairs(pwm.pins()) do
    -- p.pddr / p.pin_no / p.timer / p.apwm
end
```

---

## 7. 对象方法

---

### 7.1 `obj:start(opt)` {#7-1-start}

按配置出波。已在跑会先停再按新配置开。成功返回 `true`。配置表或硬件失败 **抛错**。对象已 `close`：`pwm already closed`。

**调用模式**

第二参必须是 table，否则抛 `start expects a table`。

TIMER（`freq` 必填，须 `> 0`）：

```lua
obj:start({ freq = hz })
obj:start({ mode = pwm.MODE_TIMER, freq = hz })
obj:start({ mode = pwm.MODE_TIMER, freq = hz, duty = d })
obj:start({ mode = pwm.MODE_TIMER, freq = hz, duty = d, clk = pwm.CLK_26M })
obj:start({ mode = pwm.MODE_TIMER, freq = hz, duty = d, clk = pwm.CLK_26M, stop = pwm.STOP_LOW })
obj:start({
    mode = pwm.MODE_TIMER,
    freq = hz,
    duty = d,
    clk = pwm.CLK_26M,
    stop = pwm.STOP_LOW,
    comp = { type = pwm.INPUT_PINNO, id = n_pin },
})
```

省略 `mode` 等于 `MODE_TIMER`。省略 `duty` 为 `0`，`clk` 为 `CLK_26M`，`stop` 为 `STOP_LOW`。

APWM 推荐写法（档位 + 高低点）：

```lua
obj:start({
    mode = pwm.MODE_APWM,
    period = pwm.APWM_1024MS,
    high = 30,
    low = 80,
})
```

APWM 简写（内部把 `freq` 收成最接近的周期档，`duty` 当成 `high=0, low=duty`）：

```lua
obj:start({ mode = pwm.MODE_APWM, freq = 1, duty = 30 })
```

`high` 和 `low` 必须成对出现，缺一个抛 `high and low must be set together`。硬件还要求 `high < low` 且都不超过 100。

这颗脚没有对应能力（没有 TIMER 通道却走 TIMER，或没有 APWM 却走 APWM）：抛 `pin has no such pwm function`。TIMER 通道或 APWM 序号已被其它对象占用：`pwm busy`。

字段非法的抛错摘要见 [第 11 节](#11-错误与返回约定)。

---

### 7.2 `obj:set_duty(duty)` {#7-2-set-duty}

运行中改占空比。必须已经 `start`。

**调用模式**

```lua
obj:set_duty(duty)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `duty` | 是 | 整数 0～100 |

成功：`true`。失败：`false`（已 close、未 start、越界、硬件拒绝）。**不抛错**（参数不是整数除外，那是 Lua 参数检查）。

TIMER：只改占空比，频率不变。互补两脚一起变。

APWM：等价于 `high=0`、`low=duty`，原先 `start` 里精细的 high/low 会被盖掉。

```lua
obj:set_duty(50)
```

---

### 7.3 `obj:set_freq(hz)` {#7-3-set-freq}

运行中改频率。必须已经 `start`。

**调用模式**

```lua
obj:set_freq(hz)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `hz` | 是 | 整数，必须 `> 0` |

成功：`true`。失败：`false`（已 close、未 start、`hz<=0`、TIMER 重配失败）。

TIMER：停一下再按原时钟、占空比、停波电平重配。APWM：把 Hz 收成 8 档周期，高低点不变。APWM 没有连续频率，不要指望 `set_freq(3)` 得到精确 3 Hz。

---

### 7.4 `obj:stop()` {#7-4-stop}

停波，**脚仍占用**，可以再 `start`。TIMER 脚电平按上次 `stop` 选项。

**调用模式**

```lua
obj:stop()
```

成功：`true`。已 close 再 `stop` 也返回 `true`。硬件失败：`false`。

互补输出一并停掉。

---

### 7.5 `obj:close()` {#7-5-close}

停波并释放 PAD（含自动占用的互补脚）。之后方法里 `start` 会抛 `pwm already closed`；`set_duty` / `set_freq` 返回 `false`；`info` 返回 `nil`。

**调用模式**

```lua
obj:close()
```

总是返回 `true`（内部忽略重复 close）。对象回收走同一条释放路径。

---

### 7.6 `obj:info()` {#7-6-info}

读运行快照。

**调用模式**

```lua
obj:info()
```

成功：table。已 close 或读失败：`nil`。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `pddr` | integer | PAD |
| `pin_no` | integer | 有模块引出才出现 |
| `running` | boolean | 是否在出波 |
| `mode` | integer | `MODE_TIMER` / `MODE_APWM` |
| `timer` | integer | TIMER 通道，仅 TIMER 模式且有效时出现 |
| `apwm` | integer | APWM 序号，仅 APWM 且有效时出现 |
| `comp_pddr` | integer | 互补脚 PAD，未配互补则没有 |
| `freq` | integer | 当前频率（APWM 可能是简写时记的 Hz） |
| `duty` | integer | 当前占空比 0～100 |

```lua
local inf = obj:info()
if inf and inf.running then
    -- inf.freq / inf.duty
end
```

---

## 8. `start` 配置表

| 键 | 类型 | 默认 | 用于 | 说明 |
| --- | --- | --- | --- | --- |
| `mode` | integer | `MODE_TIMER` | 两者 | 出波路径 |
| `freq` | integer `>0` | 无 | TIMER **必填**；APWM 可与 `period` 二选一 | 赫兹 |
| `duty` | integer 0～100 | `0` | TIMER；APWM 简写 | 百分占空比 |
| `clk` | integer | `CLK_26M` | TIMER | 时钟源 |
| `stop` | integer | `STOP_LOW` | TIMER | 停波电平 |
| `comp` | `{type,id}` | 无 | TIMER | 互补脚，见 [第 10 节](#10-互补输出) |
| `period` | integer | 无 | APWM | 必须是 `APWM_*MS` 符号 |
| `high` | integer 0～100 | 无 | APWM | 周期内百分之几处拉高，须与 `low` 成对 |
| `low` | integer 0～100 | 无 | APWM | 百分之几处拉低，必须 **大于** `high` |

键类型不是数字：抛 `invalid mode` / `invalid freq` / `invalid duty` 等。

`freq <= 0`：抛 `freq must be > 0`。`duty` 不在 0～100：抛 `duty must be 0~100`。

`comp` 必须是表且含整数 `type`、`id`，否则抛 `comp expects {type,id}` / `comp needs type and id`。

---

## 9. TIMER 与 APWM

### 9.1 TIMER

硬件定时器 PWM，最多 **6** 路（通道 0～5），一路同时只能被一个对象占用。同一 `timer` 号的两颗脚不能一起 `start`。

`freq` 必须小于 `clk`。默认 26 M 可做 1 kHz 呼吸灯，也可以 1 MHz（示波器才能看清）。占空比分辨率 ≈ 时钟 / 频率。

示例见 [examples/NT26/peripherals/pwm/timer](../../../../examples/NT26/peripherals/pwm/timer)、`timer_mhz`。

### 9.2 APWM

挂在常电域，休眠后仍可闪。只有表里带 `apwm` 字段的脚能开，常见是少数几颗（以 `pins()` 为准，不要假设任意 PWM 脚都行）。最多 **3** 路（0～2）。

周期只能 8 档。`high`/`low` 是周期上的两个百分位置：先到 `high` 拉高，再到 `low` 拉低。例如 1024 ms、`high=30`、`low=80` → 约 307 ms 拉高、819 ms 拉低。

不要拿 APWM 做蜂鸣器。`set_duty` 会把波形收成从 0% 高、到 `duty%` 低。

示例见 [examples/NT26/peripherals/pwm/apwm](../../../../examples/NT26/peripherals/pwm/apwm)。

---

## 10. 互补输出

同一路 TIMER 的正相和反相。脚本 **只 `open` 正相脚**，在 `start` 里给出反相脚：

```lua
comp = { type = pwm.INPUT_PINNO, id = n_pin }
```

`type`/`id` 规则与 `open` 相同。反相脚的 `n_ch` 必须等于正相的 `timer` 通道（PWM1 只能配 PWM1n）。对不上、或 `comp` 指到自己：抛 `pin has no such pwm function`。

**不要**再对互补脚 `pwm.open`，否则正相 `start` 会 `pwm busy`。`start` 会把互补脚切到反相复用并占住；`close` 一起释放。

`set_duty` 改的是这一对，两脚始终反相。

示例见 [examples/NT26/peripherals/pwm/timer_comp](../../../../examples/NT26/peripherals/pwm/timer_comp)。单端 LED 不必配 `comp`。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `open` | userdata | **抛** |
| `pins` | 表 | 空表也是成功 |
| `start` | `true` | **抛** |
| `set_duty` / `set_freq` | `true` | `false` |
| `stop` | `true` | `false` |
| `close` | `true` | — |
| `info` | table | `nil` |

`start` 配置类抛错：

| 文案 | 原因 |
| --- | --- |
| `start expects a table` | 第二参不是表 |
| `invalid mode` / `freq` / `duty` / `clk` / `stop` / `period` / `high` / `low` | 对应键不是数字 |
| `freq must be > 0` | `freq` 有填但 ≤0 |
| `duty must be 0~100` | 占空比越界 |
| `high and low must be set together` | 只写了其中一个 |
| `comp expects {type,id}` | `comp` 不是表 |
| `invalid comp.type` / `invalid comp.id` | 不是数字 |
| `comp needs type and id` | 缺键 |
| `pwm already closed` | 对象已 close |
| `pwm.start failed: …` | 下层，见下表 |

`open` / `start` 下层摘要：

| 片段 | 含义 |
| --- | --- |
| `invalid param` | 频率 0、时钟非法、APWM 档位/高低点非法、模式非法 |
| `pin not found / no pwm` | 脚不在表里 |
| `pwm busy` | PAD / TIMER 通道 / APWM 序号 / 互补脚被占 |
| `pin has no such pwm function` | 这颗脚没有所选模式，或互补通道对不上 |
| `pwm hw failed` | 定时器配置失败 |

需要收 `open`/`start` 时用 `pcall`。

---

## 12. 资源上限与生命周期

| 项 | 上限 / 说明 |
| --- | --- |
| TIMER 通道 | **6** 路（0～5），一路一主 |
| APWM 通道 | **3** 路（0～2） |
| 同一 PAD | 同时只能被一个 pwm 对象打开 |
| 占空比 | 0～100 |
| APWM 周期 | 仅 8 档 |
| `id` | 0～255 |
| 回调 | 无 |

`open` 占 PAD；`start` 再占 TIMER 或 APWM 通道。`stop` 放通道、留 PAD。`close` / `__gc` / 虚拟机退出放干净。

互补脚不算你 `open` 的第二个对象，但会占第二个 PAD 槽，直到正相 `close`。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| LED 调光、1 kHz 呼吸 | `MODE_TIMER` + `set_duty` 循环 |
| 蜂鸣器 / 电机 / MHz | `MODE_TIMER`，时钟 26M 或 102M |
| 休眠后还要慢闪 | `MODE_APWM` + `period`/`high`/`low` |
| 差分 / H 桥 | TIMER + `comp` |
| 查脚 | `pwm.pins()` |
| GPIO 翻转波形 | [`gpio`](gpio.md) 的 `wave_*`，精度和功耗都不同 |
| 软件模拟 PWM | 没有。不要用 `gpio` 循环冒充 kHz PWM |

---

## 14. 完整示例

脚号按板子改。下面与 [examples/NT26/peripherals/pwm/timer](../../../../examples/NT26/peripherals/pwm/timer) 同类：模块脚 16、TIMER 1 kHz。

```lua
local pwm = require("pwm")
local rt  = require("rt")

local ch = pwm.open(pwm.INPUT_PINNO, 16)
ch:start({
    mode = pwm.MODE_TIMER,
    freq = 1000,
    duty = 0,
    clk = pwm.CLK_26M,
    stop = pwm.STOP_LOW,
})

while true do
    for d = 0, 100, 5 do
        ch:set_duty(d)
        rt.delay(40)
    end
    for d = 100, 0, -5 do
        ch:set_duty(d)
        rt.delay(40)
    end
end
```

APWM 慢闪：

```lua
local ch = pwm.open(pwm.INPUT_PINNO, 100)
ch:start({
    mode = pwm.MODE_APWM,
    period = pwm.APWM_1024MS,
    high = 30,
    low = 80,
})
```

先跑 [examples/NT26/peripherals/pwm/pins](../../../../examples/NT26/peripherals/pwm/pins) 对照自己的管脚表，再选 TIMER / APWM / 互补 demo。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
