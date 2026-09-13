# charge

**文档版本** `1.0.1`

充电 **状态检测**，不是充电器。纯函数模块：读外部充电 IC 接到 CHG_DET 脚上的 STAT/CHG 电平，得到未插 / 充电中 / 充满。没有对象、没有 Lua 回调。

```lua
local charge = require("charge")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 这不是充电器](#1-这不是充电器)
- [2. 模块定位](#2-模块定位)
- [3. 框架结构](#3-框架结构)
- [4. 阻塞语义](#4-阻塞语义)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [7.1 `charge.init`](#7-1-init)
  - [7.2 `charge.deinit`](#7-2-deinit)
  - [7.3 `charge.getstatus`](#7-3-getstatus)
- [8. 检测原理与充电 IC](#8-检测原理与充电-ic)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 这不是充电器

模组 **没有** 充电管理芯片，也 **不会** 给电池充电。本模块只读一根专用检测脚。

典型接法（当前机型 NT26-F6E0）：

```
USB 5V → 外部充电 IC（VIN）→ BAT → 电池
                │
              STAT / CHG / CHRG   （开漏状态脚）
                │
          模块 Pin97  CHG_DET
```

| 项目 | 说明 |
| --- | --- |
| 模块管脚 | Pin97 |
| 信号 | CHG_DET |
| 芯片功能 | Charge Pad（专用充电检测垫） |
| 复用 | F6E0 上 **不与 GPIO 复用**，不能用 `gpio` 去配这根脚 |
| 禁止 | 不要接到 VBUS / VBAT / CE，只能接充电 IC 的开漏状态脚 |

充电路径、限流、保护全部由板级充电 IC 负责。Lua 只回答「现在像没插、在充、还是充满」。

---

## 2. 模块定位

1. 先 `charge.init()` 打开检测硬件和唤醒中断。
2. 周期 `charge.getstatus()` 读当前状态（demo 用 `rt.delay(1000)` 自己轮询）。
3. 不用了再 `charge.deinit()`。

**没有** `charge.on(...)` 一类脚本回调。`init({ monitor = true })` 也不会把状态推到 Lua：绑定没有登记回调，周期监视对脚本 **没有可见效果**。要看变化，请自己 `getstatus`。

`init` / `deinit` / `getstatus` 成功路径都返回值，不抛业务失败。未 `init` 就 `getstatus`，读到的值不可靠。

---

## 3. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  init → getstatus 轮询 → deinit                          │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  charge 模块                                             │
│  · 打开 / 关闭 Charge Pad                                │
│  · 读三态：浮空 / 强下拉 / 弱下拉                         │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Pin97 CHG_DET  ←  外部充电 IC 的 STAT/CHG               │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `init` | 打开检测脚与唤醒中断 | 否（很快） |
| `getstatus` | 读当前三态 | 否 |
| `deinit` | 关闭检测 | 否 |

---

## 4. 阻塞语义

三个接口都不是 `rt.delay` 那种让出，但本身很快。轮询间隔用 `rt.delay`，不要在 UART / MQTT 回调里死循环 `getstatus`。

反复 `init`：会先关掉再开。

---

## 5. 常量与枚举

`getstatus()` 第一返回值，以及表里的比较符号：

| 符号 | 值 | 英文名（第二返回值） | 硬件含义 |
| --- | --- | --- | --- |
| `charge.DISCONNECT` | `0` | `"disconnect"` | 浮空：未接充电器 |
| `charge.CHARGING` | `1` | `"charging"` | 强下拉：正在充电 |
| `charge.FINISH` | `2` | `"finish"` | 弱下拉：充电完成 |

未导出的其它整数不要当状态。万一读到未知值，第二返回值是 `"unknown"`。

两态充电 IC 分不清「拔掉」和「充满」，**不要依赖 `FINISH`**，见 [第 8 节](#8-检测原理与充电-ic)。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `opts` | table | `init` 可选；省略 / `nil` = 默认 |
| `opts.monitor` | boolean | **走 `toboolean`：数字 `0` 为真**。请用 `true`/`false`。默认 `false` |
| `opts.sample_ms` | integer | 采样周期毫秒，默认 `1000`；小于 1 收成 `1`。仅 `monitor=true` 时底层会用到 |
| `code` | integer | `0` / `1` / `2` |
| `name` | string | `"disconnect"` / `"charging"` / `"finish"` |

---

## 7. 模块函数

模块表：`init`、`deinit`、`getstatus`。

---

### 7.1 `charge.init([opts])` {#7-1-init}

打开充电检测硬件与唤醒中断。总是返回 `true`。已 init 过会先 deinit 再开。

**调用模式**

```lua
charge.init()
```

```lua
charge.init(nil)
```

```lua
charge.init({})
```

```lua
charge.init({ monitor = false })
```

```lua
charge.init({ monitor = true })
```

```lua
charge.init({ monitor = true, sample_ms = 500 })
```

```lua
charge.init({ sample_ms = 2000 })
```

第一参既不是 table 也不是 `nil`：抛类型错。`sample_ms` 出现但不是 integer：抛类型错。

`monitor` 用数字 `0` 会被当成 **真**。要关监视写 `false` 或不写。

即使 `monitor=true`，Lua 也收不到回调。正式脚本用默认 `init()` + 自己轮询即可。

**返回**：`true`

---

### 7.2 `charge.deinit()` {#7-2-deinit}

关闭检测硬件与中断。无参数。未 init 过也可以调。总是 `true`。

**调用模式**

```lua
charge.deinit()
```

---

### 7.3 `charge.getstatus()` {#7-3-getstatus}

读当前状态。无参数。两个返回值：整数码、英文短名。

**调用模式**

```lua
charge.getstatus()
```

```lua
local code, name = charge.getstatus()
```

```lua
if code == charge.CHARGING then
    -- 正在充电
end
```

先 `init` 再读。比较请用 `charge.DISCONNECT` / `CHARGING` / `FINISH`，不要只认字符串。

---

## 8. 检测原理与充电 IC

Charge Pad **不是**测电压或电流。内部可开关约 10k 上拉，再读脚电平，区分三种外部状态：

1. 先关上拉：脚为高 / 浮空 → `DISCONNECT`（STAT 开路）；脚为低 → 外部有下拉，再做第 2 步。
2. 打开上拉后再读：仍为低 → 强下拉 → `CHARGING`；被拉高 → 弱下拉 → `FINISH`。

**三态 IC**（可完整区分三种状态）：强下拉充电中、弱下拉充满、浮空未插。例如 LTC4054 / LTC1734，以及部分 C/10 时 CHRG 改为弱下拉的线性充芯片。

**两态 IC**（只能区分「在充 / 不在充」）：强下拉 = `CHARGING`；浮空 = 未插 **或** 充满，软件上 `DISCONNECT` 与 `FINISH` 不可靠。常见 TP4054 / TP4056 / TP4057、SGM4054/4056、LP4054/4056、ETA4056、MCP73831/73832；开关充如 SGM41511、BQ25601、ETA6005 的 STAT 也多是开漏两态。

两态板子：把「没在充」当成一类，不要用 `FINISH==2` 做充满指示灯。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `init` | `true` | 仅 opts 类型错时抛错 |
| `deinit` | `true` | 无 |
| `getstatus` | `code, name` | 无业务失败返回 |

没有 `nil, err`。状态是否可信取决于是否已 `init`、以及充电 IC 是三态还是两态。

---

## 10. 资源上限与生命周期

| 资源 | 说明 |
| --- | --- |
| 检测脚 | 全机一根 CHG_DET（F6E0 为 Pin97） |
| 回调 | Lua **没有** 回调槽 |
| 默认轮询建议 | demo 1 秒一次 `getstatus` |
| `sample_ms` 下限 | 1 |

`deinit` 或虚拟机退出后检测关掉。没有 userdata 要持有。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 看有没有在充电 | `init` 后 `getstatus`，比 `CHARGING` |
| 三态 IC 看充满 | 比 `FINISH` |
| 两态 IC | 只区分充电中 / 其它，不要用 `FINISH` |
| 给电池充电 | 板级充电 IC，不是本模块 |
| 等状态推送 | **没有**；自己 `rt.delay` 再读 |
| 用 GPIO 配 Pin97 | **不要**（F6E0 非 GPIO） |

---

## 12. 完整示例

与仓库 [examples/NT26/module/charge/charge_api](../../../../examples/NT26/module/charge/charge_api) 一致：init 后每秒读一次。下面补上 `require("rt")`。

```lua
local charge = require("charge")
local log    = require("log")
local rt     = require("rt")

local STATUS_CN = {
    [charge.DISCONNECT] = "未接充电器",
    [charge.CHARGING]   = "正在充电",
    [charge.FINISH]     = "充电完成",
}

charge.init()
log.info("init ok, CHG_DET")

local last_code = nil
while true do
    local code, name = charge.getstatus()
    local cn = STATUS_CN[code] or "未知"
    if code ~= last_code then
        log.info("变化 code=%d name=%s %s", code, name, cn)
        last_code = code
    else
        log.info("当前 code=%d name=%s %s", code, name, cn)
    end
    rt.delay(1000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `charge.init()` | 打开检测（推荐） | `true` |
| `charge.init(nil)` / `init({})` | 同上 | `true` |
| `charge.init({ monitor = true, sample_ms = n })` | 仍无 Lua 回调，不必用 | `true` |
| `charge.deinit()` | 关闭检测 | `true` |
| `charge.getstatus()` | 读状态 | `code, name` |

## 附录 B. 枚举值一览

| 符号 | 值 | 英文名 |
| --- | --- | --- |
| `charge.DISCONNECT` | 0 | `disconnect` |
| `charge.CHARGING` | 1 | `charging` |
| `charge.FINISH` | 2 | `finish` |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
