# sys

**文档版本** `1.0.1`

系统级工具模块：版本与复位原因、串口路由、授时、看门狗、复位/关机，以及 **不让出 Lua 协程** 的三类延时。日常等待请优先用 `rt.delay`。

```lua
local sys = require("sys")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 延时：`sys` 与 `rt.delay` 的本质区别](#3-延时sys-与-rtdelay-的本质区别)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `sys.delay_ms`](#6-1-delay-ms)
  - [6.2 `sys.delay_until`](#6-2-delay-until)
  - [6.3 `sys.delay_us`](#6-3-delay-us)
  - [6.4 `sys.wdt_kick`](#6-4-wdt-kick)
  - [6.5 `sys.option`](#6-5-option)
  - [6.6 `sys.version`](#6-6-version)
  - [6.7 `sys.reset_reason`](#6-7-reset-reason)
  - [6.8 `sys.reset`](#6-8-reset)
  - [6.9 `sys.poweroff`](#6-9-poweroff)
  - [6.10 `sys.set_ts`](#6-10-set-ts)
  - [6.11 `sys.set_ts_ms`](#6-11-set-ts-ms)
  - [6.12 `sys.nitz_reg`](#6-12-nitz-reg)
- [7. 授时回调](#7-授时回调)
- [8. 错误与返回约定](#8-错误与返回约定)
- [9. 资源上限与生命周期](#9-资源上限与生命周期)
- [10. 选型对照](#10-选型对照)
- [11. 完整示例](#11-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`sys` 是纯函数模块，没有对象、没有 `open`。两类用途：

1. **查询与控制整机**：版本、上次复位原因、`print`/`log` 串口路由、写本机时间、NITZ 授时回调、软件复位、关机、喂硬件看门狗。
2. **线程级 / 忙等延时**：`delay_ms`、`delay_until`、`delay_us`。它们 **不是** `rt.delay` 的换皮，调度模型完全不同，见 [第 3 节](#3-延时sys-与-rtdelay-的本质区别)。

日常“等一会儿再干活”用 `rt.delay`。`sys` 的 delay 只留给：时序必须尽快返回、不能被其它 Lua 协程插队，或只要几十～几百微秒的脚线时序。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("sys") / require("rt")                          │
└────────────────────────────┬────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ rt.delay      │  │ sys.delay_ms    │  │ sys.delay_us    │
│               │  │ sys.delay_until │  │                 │
│ 让出当前协程   │  │ 挂起整条 Lua    │  │ CPU 空转        │
│ 其它协程可跑   │  │ 引擎线程        │  │ 连线程调度都无  │
│ Lua 层调度工具 │  │ 全体协程都停    │  │ 看门狗也进不去  │
└───────────────┘  └─────────────────┘  └─────────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────┐
│  其它 sys 能力                                            │
│  版本 / 复位原因 / option 路由 / 授时 / 复位关机 / 喂狗   │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 谁在等 | Lua 其它协程 | OS 其它线程 | 典型用途 |
| --- | --- | --- | --- | --- |
| `rt.delay` | 当前协程让出 | **能跑** | 能跑 | 日常等待、低功耗空闲 |
| `sys.delay_ms` / `delay_until` | 整条 Lua 引擎线程挂起 | **全停** | 能跑（含喂狗监控） | 要尽快到点、不准被别的协程插队 |
| `sys.delay_us` | 当前 CPU 空转 | 全停 | **也跑不了** | 仅极短微秒时序 |

---

## 3. 延时：`sys` 与 `rt.delay` 的本质区别

这是本模块最容易用错的地方。

### 3.1 `rt.delay`：让出协程，Lua 层调度工具

`rt.delay(ms)` / `rt.delay(-1)` 属于 `rt` 模块：

- 只让出 **当前这条 Lua 协程**。
- 调度器可以去跑别的 `rt.task`、定时器、IO 回调。
- 本质是 Lua 层的调度工具，不是“把整台解释器按停”。
- 空闲时整机才有机会按 `lp` 的目标档休眠。

日常等待、循环里歇一歇、等网络、配合低功耗，**默认用它**。

### 3.2 `sys.delay_ms` / `sys.delay_until`：不让出协程，挂起整条 Lua 引擎线程

这两类 delay **不会**让出当前协程给其它 Lua 任务：

- 从 Lua 脚本看，就是一段 **纯阻塞业务**：调用返回前，本协程后面的语句、其它协程、Lua 回调全部走不到。
- 底层挂起的是 **整条跑 Lua 引擎的 OS 线程**。相当于整个 Lua 都睡着了。
- 其它 OS 线程（含系统监控、喂狗）**还能跑**，所以毫秒级用它们一般不会把看门狗饿死。
- 因为中间没有 Lua 协程调度插队，到期后通常能 **尽快回到调用点**，时序比 `rt.delay` 更硬。其它协程再忙，也不会把这次延时拖长。

适用：短时序必须准、不能被别的 Lua 协程抢走 CPU 的场景。  
不适用：秒级循环等待、多任务并存时的“歇一会儿”——那种必须用 `rt.delay`，否则整台脚本被按停。

`delay_until` 在本平台是「以调用当下为起点再睡这么久」，不是墙上时钟的绝对时刻。和 `delay_ms` 一样都是挂起整条 Lua 线程；`ms <= 0` 立即返回。

### 3.3 `sys.delay_us`：纯忙等，连线程调度都不参与

`delay_us` 是 CPU 空转：

- 不让出协程。
- **也不**挂起线程去进 OS 调度。当前核就在这儿空转。
- 系统监控线程得不到运行，**无法喂狗**。
- API **不截断**数值，传多大就空转多久。

因此 **只能延时很短的时间**（几十～几百微秒的脚线时序）。  
**到了毫秒级必须改用 `sys.delay_ms`（或日常场景的 `rt.delay`）**。

反例：

```lua
sys.delay_us(10 * 1000 * 1000)   -- 空转十秒
```

整机会卡在这儿十秒：监控线程跑不了、看门狗喂不上，设备复位。不要用 `delay_us` 凑“等几秒”。

### 3.4 怎么选

| 你想做什么 | 用哪个 |
| --- | --- |
| 等 1 秒、等网络、多任务歇一歇、配合休眠 | `rt.delay` |
| 要毫秒级、且必须尽快回到本调用、不准别的协程插队 | `sys.delay_ms`（或 `delay_until`） |
| 只要 50µs / 200µs 的脚线间隔 | `sys.delay_us` |
| `delay_us(1000)` 或更长 | **不要**，改 `delay_ms` / `rt.delay` |

---

## 4. 常量与枚举

本模块只导出复位原因常量，挂在 `sys` 表上。没有 delay 档位、没有 option 的符号常量（路由 key 是字符串）。

用于 `sys.reset_reason()` 返回的 `ap` / `cp`，以及自己做比较。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `sys.RST_CLEAR` | `0` | 深睡唤醒等，不是一次真正掉电复位 |
| `sys.RST_POR` | `1` | 上电复位 |
| `sys.RST_PAD` | `2` | 复位脚被拉低 |
| `sys.RST_SWRESET` | `3` | 软件复位（含 `sys.reset`） |
| `sys.RST_HARDFAULT` | `4` | AP 硬故障 |
| `sys.RST_ASSERT` | `5` | 断言失败 |
| `sys.RST_WDTSW` | `6` | 软件看门狗 |
| `sys.RST_WDTHW` | `7` | 硬件看门狗（`delay_us` 堵太久也可能落到这类） |
| `sys.RST_LOCKUP` | `8` | CPU lockup |
| `sys.RST_AONWDT` | `9` | Always-On 看门狗 |
| `sys.RST_BATLOW` | `10` | 电压过低 |
| `sys.RST_TEMPHI` | `11` | 温度过高 |
| `sys.RST_FOTA` | `12` | FOTA 升级复位 |
| `sys.RST_EXTRST` | `13` | 外部复位（本芯片导出） |
| `sys.RST_UNKNOWN` | `14` | 未能识别 |

未挂到模块表上的内部上限值不要当 API 用。比较时用符号，不要散写魔数。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `ms` | integer | 毫秒；`< 0` 在 `delay_ms` 里当 `0`；`delay_until` 里 `<= 0` 立即返回 |
| `us` | integer | 微秒；`< 0` 当 `0` |
| `option_key` | string | 仅 `"print_route"` / `"log_route"` |
| `uart_id` | integer | `1` / `2` / `3` |
| `ts` | integer | UTC Unix 秒，必须 `> 0` |
| `ts_ms` | integer | UTC Unix 毫秒，必须 `> 0` |
| `rst` | integer | `RST_*` |

`option` 写路由时第二参必须是 **integer**。`true` / `"2"` 会抛 `integer expected`。

---

## 6. 模块函数

---

### 6.1 `sys.delay_ms(ms)` {#6-1-delay-ms}

按毫秒挂起 **整条 Lua 引擎线程**。不让出协程，全体 Lua 协程停住。其它 OS 线程仍可跑。

见 [第 3.2 节](#32-sysdelay_ms--sysdelay_until不让出协程挂起整条-lua-引擎线程)。

**调用模式**

```lua
sys.delay_ms(ms)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ms` | integer | 是 | 毫秒。`< 0` 按 `0`（立即返回） |

**返回**

无返回值。

```lua
sys.delay_ms(10)
```

不要用它做多任务之间的日常等待。那种用 `rt.delay`。

---

### 6.2 `sys.delay_until(ms)` {#6-2-delay-until}

同样挂起整条 Lua 引擎线程。本平台按「调用当下再睡 `ms`」，不是绝对闹钟。

`ms <= 0` 立即返回。

**调用模式**

```lua
sys.delay_until(ms)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ms` | integer | 是 | 相对当前时刻的毫秒数 |

**返回**

无返回值。

```lua
sys.delay_until(10)
```

调度语义与 `delay_ms` 同类：Lua 全停，OS 其它线程能跑。时序含义是“从现在再等这么久”，不要理解成“睡到某个墙上时间”。

---

### 6.3 `sys.delay_us(us)` {#6-3-delay-us}

CPU 忙等微秒。不让出协程，也不进线程调度。

**只能用于很短的时间。到毫秒必须换 `delay_ms`。**  
`sys.delay_us(10 * 1000 * 1000)` 会空转十秒，监控线程喂不上狗，设备复位。

见 [第 3.3 节](#33-sysdelay_us纯忙等连线程调度都不参与)。

**调用模式**

```lua
sys.delay_us(us)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `us` | integer | 是 | 微秒。`< 0` 按 `0`。**不截断上限** |

**返回**

无返回值。

```lua
sys.delay_us(100)     -- 可以：百微秒级脚线
sys.delay_us(1000)    -- 不要：已到 1ms，改 delay_ms(1) 或 rt.delay(1)
```

---

### 6.4 `sys.wdt_kick()` {#6-4-wdt-kick}

主动喂硬件看门狗（AP 与 Always-On）。**不让出**任何调度。

忙循环里只 `wdt_kick` 能暂时避免看门狗复位，但其它任务仍可能被饿死。优先把长等待改成 `rt.delay` / `delay_ms`。若确实有一段算很久、又必须占着 Lua 线程，应在分片里 kick。

固件未编进 AP 看门狗时，AP 侧为空操作，Always-On 侧仍会喂。

**调用模式**

```lua
sys.wdt_kick()
```

无参数，无返回值。

---

### 6.5 `sys.option(key [, value])` {#6-5-option}

读或写 Lua 输出串口路由。`print` 与 `log` 互相独立。

**调用模式**

```lua
sys.option(key)
```

```lua
sys.option(key, value)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `key` | string | 是 | `"print_route"` 或 `"log_route"` |
| `value` | integer | 写时必填 | `1` / `2` / `3`（UART1/2/3） |

参数个数不是 1 或 2 时抛 `sys.option: usage sys.option(key) or sys.option(key, value)`。  
写时第二参不是 integer 抛 `integer expected`。  
`value` 不是 1/2/3 抛 `print_route must be 1, 2 or 3` 或 `log_route must be 1, 2 or 3`。  
未知 `key` 抛 `unsupported key`。

**返回**

当前（或刚写入的）路由编号，integer。

```lua
local pr = sys.option("print_route")
local lr = sys.option("log_route")
sys.option("log_route", 2)
```

运行时改的值重启后回到配置文件 `[lua]` 段。详见 `log` 模块「输出路由」。

---

### 6.6 `sys.version()` {#6-6-version}

读固件版本，字段与 `AT+VERSION` 查询一致。立即返回，不阻塞。

**调用模式**

```lua
sys.version()
```

无参数。

**返回** table：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `sdk` | string | SDK 版本 |
| `evb` | string | 硬件/EVB 版本 |
| `cmp` | string | C 编译期日期时间 |
| `app` | string | 应用完整名称，如 `NT26-PRO-RTU-B1.2.10` |
| `ver` | string | 纯版本号，如 `1.2.10` |
| `ver_f` | number | 版本号浮点，如 `1.210` |
| `build` | string | Build Number |
| `btime` | string | 打包时间 |

`cmp` 与 `btime` 来源不同，不要当同一个时间用。`app` 是产品全名，比较版本用 `ver` / `ver_f`。

```lua
local v = sys.version()
log.info("app=%s ver=%s build=%s", v.app, v.ver, v.build)
```

---

### 6.7 `sys.reset_reason()` {#6-7-reset-reason}

读上次复位原因。模组有 AP（跑 Lua/应用）和 CP（协议栈）两套核。

**调用模式**

```lua
sys.reset_reason()
```

无参数。

**返回** table：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `ap` | integer | AP 复位码，与 `sys.RST_*` 相同 |
| `cp` | integer | CP 复位码 |
| `ap_name` | string | AP 名称，如 `"POR"`、`"WDTHW"` |
| `cp_name` | string | CP 名称 |

```lua
local r = sys.reset_reason()
if r.ap == sys.RST_HARDFAULT then
    log.warn("AP hardfault reboot")
end
```

---

### 6.8 `sys.reset()` {#6-8-reset}

请求软件复位。先阻塞约 **1000 ms**（挂起 Lua 引擎线程），再复位。正常情况下 **不会回到下一行**。

**调用模式**

```lua
sys.reset()
```

无参数，无返回值。不要在 UART/快捷回调里调用，丢到独立 task 再执行。

---

### 6.9 `sys.poweroff()` {#6-9-poweroff}

请求关机。同样先阻塞约 **1000 ms**，再关机。正常情况下不会回到下一行。

**调用模式**

```lua
sys.poweroff()
```

无参数，无返回值。

---

### 6.10 `sys.set_ts(ts)` {#6-10-set-ts}

写本机 RAM 中的 UTC Unix **秒**。不冒充 NITZ（`info.nitz_ready()` 不会因此变真）。

**调用模式**

```lua
sys.set_ts(ts)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ts` | integer | 是 | UTC 秒，必须 `> 0` |

**返回**

boolean：`true` 成功；`ts <= 0` 或底层失败为 `false`，不抛错。

---

### 6.11 `sys.set_ts_ms(ts_ms)` {#6-11-set-ts-ms}

写本机 RAM 中的 UTC Unix **毫秒**。同样不冒充 NITZ。

**调用模式**

```lua
sys.set_ts_ms(ts_ms)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ts_ms` | integer | 是 | UTC 毫秒，必须 `> 0` |

**返回**

boolean，语义同 `set_ts`。

---

### 6.12 `sys.nitz_reg(cb)` {#6-12-nitz-reg}

登记基站 NITZ 授时成功回调。重复调用覆盖旧回调。

注册时若已经授时成功，会 **立刻回调一次**，避免“先授时后注册”丢首事件。

不允许在快捷回调上下文调用（抛 `nitz_reg not allowed in quick callback`）。  
禁止在 NITZ 回调里再 `nitz_reg`：会跳过，返回 `false`，并打一条警告日志。

**调用模式**

```lua
sys.nitz_reg(cb)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cb` | function | 是 | `function(ts)`，见 [第 7 节](#7-授时回调) |

**返回**

- 成功：`true`
- 回调内递归登记：`false`（不抛错）
- 其它失败：抛错（`main vm not found` / `register rt topic failed` / `register PS MM event failed: <n>`）

---

## 7. 授时回调

```lua
function cb(ts)
```

| 参数 | 类型 | 含义 |
| --- | --- | --- |
| `ts` | integer | UTC Unix 秒；取时间失败时为 `0` |

只在授时成功（本机已同步）时触发。协议栈上报后投进运行时队列，在 Lua **调度循环**里执行，不是中断：

- 立刻返回。不要 `rt.delay`、不要 `sys.delay_*`、不要再 `nitz_reg`。
- 打印和业务放到独立 `rt.task`。

---

## 8. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `delay_ms` / `delay_until` / `delay_us` | 无返回 | 缺参走 Lua 类型错 |
| `wdt_kick` | 无返回 | — |
| `option` 读/写 | integer 路由 | 抛错 |
| `version` / `reset_reason` | table | — |
| `reset` / `poweroff` | 通常不再返回 | — |
| `set_ts` / `set_ts_ms` | `true` | `false`（`<=0` 或写失败） |
| `nitz_reg` | `true` | 递归登记 `false`；否则抛错 |

---

## 9. 资源上限与生命周期

| 项 | 说明 |
| --- | --- |
| NITZ 回调 | 每 VM 一条，重复 `nitz_reg` 覆盖 |
| `delay_us` 上限 | **无软件截断**，长了会复位，靠调用方自制 |
| `reset` / `poweroff` 前等待 | 约 1000 ms |
| 路由 | `1..3` |

无对象、无 `__gc`。NITZ 回调挂在当前虚拟机上。

---

## 10. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 等 1 秒、循环歇、多任务、低功耗空闲 | `rt.delay` |
| 毫秒级、必须尽快回到本句、不准协程插队 | `sys.delay_ms` |
| 从现在再相对睡一截（同线程语义） | `sys.delay_until` |
| 几十～几百微秒脚线 | `sys.delay_us`（到 ms 禁止） |
| 超长计算占着线程 | 分片 + `wdt_kick`，能让出就让出 |
| 看版本 / 为何复位 | `version` / `reset_reason` |
| 改 print/log 串口 | `option` |
| 写本机时间 | `set_ts` / `set_ts_ms` |
| 等基站授时 | `nitz_reg` |
| 重启 / 关机 | `reset` / `poweroff`（独立 task 里调） |

---

## 11. 完整示例

与 [examples/NT26/os/sys/sys_api](../../../../examples/NT26/os/sys/sys_api) 一致（不调用复位/关机）：

```lua
local rt  = require("rt")
local log = require("log")
local sys = require("sys")
local info = require("info")

local v = sys.version()
log.info("app=%s ver=%s build=%s", v.app, v.ver, v.build)

local r = sys.reset_reason()
log.info("ap=%s %s  cp=%s %s", r.ap, r.ap_name, r.cp, r.cp_name)

log.info("print_route=%s log_route=%s",
         sys.option("print_route"), sys.option("log_route"))

sys.delay_us(100)       -- 只演示极短忙等
sys.delay_ms(10)        -- 挂起整条 Lua 线程 10ms
sys.delay_until(10)
sys.wdt_kick()

local ts = info.timestamp()
if ts and ts > 0 then
    sys.set_ts(ts)
end

sys.nitz_reg(function(utc)
    log.info("nitz ts=%s", utc)
end)

while true do
    rt.delay(10000)     -- 日常等待用 rt，不要用 sys.delay_us 凑秒
end
```

---

## 附录 A. 方法速查

| 调用 | 参数模式 | 返回 |
| --- | --- | --- |
| `sys.delay_ms(ms)` | 1 个整数 | 无 |
| `sys.delay_until(ms)` | 1 个整数；`<=0` 立即回 | 无 |
| `sys.delay_us(us)` | 1 个整数；只许很短 | 无 |
| `sys.wdt_kick()` | 无 | 无 |
| `sys.option(key)` | 读 | integer |
| `sys.option(key, value)` | 写 1/2/3 | integer / 抛错 |
| `sys.version()` | 无 | table |
| `sys.reset_reason()` | 无 | table |
| `sys.reset()` | 无 | 通常不返回 |
| `sys.poweroff()` | 无 | 通常不返回 |
| `sys.set_ts(ts)` | Unix 秒 `>0` | boolean |
| `sys.set_ts_ms(ts_ms)` | Unix 毫秒 `>0` | boolean |
| `sys.nitz_reg(cb)` | 1 个函数 | `true` / `false` / 抛错 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `sys.RST_CLEAR` | 0 |
| `sys.RST_POR` | 1 |
| `sys.RST_PAD` | 2 |
| `sys.RST_SWRESET` | 3 |
| `sys.RST_HARDFAULT` | 4 |
| `sys.RST_ASSERT` | 5 |
| `sys.RST_WDTSW` | 6 |
| `sys.RST_WDTHW` | 7 |
| `sys.RST_LOCKUP` | 8 |
| `sys.RST_AONWDT` | 9 |
| `sys.RST_BATLOW` | 10 |
| `sys.RST_TEMPHI` | 11 |
| `sys.RST_FOTA` | 12 |
| `sys.RST_EXTRST` | 13 |
| `sys.RST_UNKNOWN` | 14 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
