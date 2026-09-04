# lp

**文档版本** `1.0.1`

低功耗与驻网模块。用来设定休眠**目标**、等驻网、收网络/唤醒事件，以及用投票在“有业务要保活”和“允许睡”之间切换。本模块还提供本地 SIM 配置读写和运行时切卡。

```lua
local lp = require("lp")
```

平台预加载模块，无需额外 `.lua` 文件。主脚本虚拟机启动时还会放入全局 `_G.lp`；推荐仍写 `local lp = require("lp")`。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 低功耗机制](#3-低功耗机制)
- [4. 对象模型](#4-对象模型)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [7.1 `lp.set_mode`](#7-1-set-mode)
  - [7.2 `lp.get_mode`](#7-2-get-mode)
  - [7.3 `lp.islink`](#7-3-islink)
  - [7.4 `lp.wait_link` / `lp.wait_attach`](#7-4-wait-link)
  - [7.5 `lp.reg_netcb`](#7-5-reg-netcb)
  - [7.6 `lp.vote_create`](#7-6-vote-create)
  - [7.7 `lp.config`](#7-7-config)
  - [7.8 `lp.simslot`](#7-8-simslot)
- [8. 对象方法（vote）](#8-对象方法vote)
  - [8.1 `obj:acquire`](#8-1-acquire)
  - [8.2 `obj:release`](#8-2-release)
  - [8.3 `obj:vote`](#8-3-vote)
  - [8.4 `obj:clear`](#8-4-clear)
  - [8.5 `obj:status`](#8-5-status)
- [9. 网络与唤醒回调](#9-网络与唤醒回调)
- [10. 投票语义](#10-投票语义)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`lp` 管两件相关的事：

1. **休眠目标**：告诉设备“空闲时希望睡到哪一档”，而不是“现在立刻睡着”。
2. **驻网与卡**：查是否已 PDP 驻网、阻塞等待驻网、收驻网/掉网/插拔卡/模式变化/唤醒事件；读写本地 SIM 策略、运行时切卡。

业务脚本的典型顺序：

```lua
lp.reg_netcb(on_net)
lp.wait_link(-1)                 -- 需要网络时
lp.set_mode(lp.MODE_LOW_POWER)   -- 设目标：空闲后 Sleep1、保持在网
-- 之后用 rt.delay / mbox_recv 让出，系统才可能真睡
```

投票实例（`lp.vote_create`）给多任务场景用：有人 `acquire` 就拉回常电；票全部释放并过了延迟，再把目标设回约定的休眠档。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  set_mode / wait_link / reg_netcb / vote_* / config     │
└────────────────────────────┬────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ 目标模式       │  │ 驻网与卡         │  │ 投票实例         │
│ 当前档 / 目标档 │  │ 等待驻网         │  │ acquire 保活     │
│ 不立刻入睡     │  │ 事件投递到调度   │  │ 全释放后延迟切档  │
└───────┬───────┘  └────────┬────────┘  └────────┬────────┘
        │                   │                    │
        └───────────────────┼────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────┐
│  休眠门控                                                │
│  目标允许睡 且 整机所有线程都空闲 → 才进入对应休眠        │
│  任一任务在跑、在打日志、在忙等 → 保持清醒                │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否马上睡着 | 典型用途 |
| --- | --- | --- | --- |
| `set_mode` | 更新目标档，网络侧按档切射频/驻网策略 | 否 | 选定 Sleep1 / 飞行休眠 / 常电 |
| `vote` 保活 | 有票则目标拉到常电 | 否 | 多任务：干活时不准睡 |
| `wait_link` / `mbox_recv` / `rt.delay` | 当前 Lua 任务让出 | 让出后**有机会**睡 | 空闲等待 |
| `reg_netcb` | 登记回调 | 否 | 看驻网、切档、唤醒源 |

---

## 3. 低功耗机制

### 3.1 目标，不是开关

`lp.set_mode(mode)` 以及投票在“全票释放”后切回去的档，都是 **目标休眠等级**：

- 表示：当整机真正空闲时，**允许**进入哪一档。
- **不表示**：函数返回的那一瞬间设备已经睡着。

`lp.get_mode()` 读到的是网络管理当前采用的目标档，同样不能当成“此刻 CPU 已经停钟”。电流表上看到入睡，一定还要满足下面的空闲条件。

### 3.2 必须全体空闲

休眠是整机行为。Lua 只是其中一条（或几条）任务，协议栈、定时器、串口、其它 OS 线程同样参与门控。

**会进入空闲、从而给休眠开门的写法：**

| 写法 | 为何算空闲 |
| --- | --- |
| `rt.delay(ms)` | 当前任务挂起，到期前不占 CPU |
| `rt.delay(-1)` | 一直让出，直到被事件唤醒 |
| `rt.mbox_recv(topic)` / 带超时的 recv | 阻塞在邮箱上 |
| `lp.wait_link` / `lp.wait_attach` | 阻塞等驻网（内部同样是让出） |
| 所有已启动的 `rt.task` 都处于上述状态 | 没有人在跑脚本 |

**会挡住休眠的写法：**

| 写法 | 为何睡不着 |
| --- | --- |
| `while true do end` 空转 | 任务永远 busy |
| 主循环里不 `delay`、不 `mbox_recv` | 入口协程一直占着调度 |
| 长时间 `log.*` / `print` | 串口输出把系统拉在工作态，电流波形会被打印脉冲抬高 |
| `gpio` 的 `seq` 等同步占住 Lua 线程的接口 | 调用返回前整条 Lua 线程不空闲 |
| 硬件忙等（微秒级空转） | CPU 不让出 |

一条任务在 `delay`，另一条还在 `while true` 里转，**整机不能睡**。必须全体空闲。

测电流时：业务回调和 `log` 都先关掉或降到极少，否则串口会把休眠电流画成一串尖峰。

### 3.3 醒来之后

空闲入睡后，下列情况会把设备拉起来，然后再根据**当时的目标档**决定能不能睡回去：

- `rt.delay` / cron 到期（常见唤醒源是 RTC）
- 邮箱来了数据、`wait_link` 等到驻网
- 串口有数据、引脚、USB、电源键、充电
- Sleep1 在网时协议栈自己的寻呼/测量（见 [3.6](#36-sleep1在网一秒一次扫站是正常现象)）

唤醒会通过 `lp.WAKE` 回调通知（见 [第 9 节](#9-网络与唤醒回调)）。脚本不必、也不应该在回调里再调一次 `set_mode` 来“恢复睡眠”——目标档还在，空闲后会再睡。

### 3.4 四档目标

| 符号 | 值 | 射频 / 网络 | 空闲后的休眠 | 说明 |
| --- | --- | --- | --- | --- |
| `lp.MODE_NORMAL` | `0` | 开，保持驻网 | 不主动进休眠 | 常电，CPU 保持工作 |
| `lp.MODE_LOW_POWER` | `1` | 开，**保持在网** | Sleep1 | 低功耗 1。见 3.6 |
| `lp.MODE_LOW_POWER_2` | `2` | **关**（飞行） | 可睡 | 低功耗 2。无蜂窝，`islink` 固定为 `0` |
| `lp.MODE_PSM_PLUS` | `3` | 关 | 深睡 | 唤醒按复位路径恢复，脚本会重新跑。一般产品流程慎用 |

`MODE_LOW_POWER_2` / `MODE_PSM_PLUS` 下 `lp.islink()` 恒为 `0`，不要用它判断“卡还在不在”。切回 `MODE_NORMAL` 或 `MODE_LOW_POWER` 后才会重新开射频、重新驻网。

### 3.5 网络协议会跟着目标档自动挂起

平台上的网络协议（TCP socket、MQTT 等）已经按低功耗目标做过适配。

切到 **不在网** 的休眠档（`MODE_LOW_POWER_2`、`MODE_PSM_PLUS`）时：

- 协议自己感应休眠目标，把连接和协议线程 **自动挂起**。
- **不必**先手动 `close` / 断开 MQTT / 拆 socket。先关连接再 `set_mode` 是多余的，也容易把业务状态机写乱。
- 脚本侧对象还可以留着；射频关掉期间它们不再占着会话。

切回在网档（`MODE_NORMAL` / `MODE_LOW_POWER`）后，这些协议会按自身的重连 / 恢复逻辑继续跑，同样不需要为了“配合休眠”先拆再建。

`MODE_LOW_POWER`（Sleep1）保持在网，协议会话继续有效，只是空闲时整机可以 Sleep1。

### 3.6 Sleep1：在网，一秒一次扫站是正常现象

`MODE_LOW_POWER` 的目标是 **Sleep1 且保持驻网**。

设备并没有离开蜂窝网。空闲入睡后，协议栈仍要维持小区：大约 **每秒一次** 的寻呼监听 / 测基站脉冲。电流表上会看到周期性尖峰，这是 Sleep1 的正常行为，不是漏睡、也不是脚本把系统反复打醒。

不要为了“削平这一秒一跳”去改 Lua 逻辑。若业务允许长时间离网，应把目标改成 `MODE_LOW_POWER_2`（关射频），脉冲才会消失，但同时没有网络。

Sleep1 周期醒来时，`reg_netcb` 里有时会看到 `WAKE` + `WAKE_RTC`，往往一闪而过。不必对每一次 RTC 都做重业务。

### 3.7 和脚本节奏的关系

推荐结构：

```lua
lp.set_mode(lp.MODE_LOW_POWER)   -- 只设目标
while true do
    -- 短业务
    rt.delay(60000)              -- 让出 60s：这段空闲才可能 Sleep1
end
```

入口若不再干活，用 `rt.delay(-1)`，避免自己用短周期 `delay` 把休眠打成“定时闹钟”。投票 demo 就是这种写法：干活的 task 自己 `delay`，入口 `delay(-1)`。

---

## 4. 对象模型

模块函数直接挂在 `lp` 表上。另外 `lp.vote_create` 返回 **vote userdata**：

```lua
local vote, err = lp.vote_create({
    sleep_mode = lp.MODE_LOW_POWER_2,
    max_keys = 8,
    sleep_delay_ms = 3000,
})
vote:acquire("task_a")
```

方法必须通过该对象调用：

```lua
vote:acquire("k")            -- 推荐
vote.acquire(vote, "k")      -- 等价
vote.acquire("k")            -- 错误
lp.acquire(vote, "k")        -- 错误：模块表上没有实例方法
```

对象被回收后实例拆除。仍在投票的脚本必须持有引用。

本模块其它接口都不是对象方法。

---

## 5. 常量与枚举

全部挂在 `lp` 表上，值为整数。

### 5.1 休眠目标 `mode`

用于 `lp.set_mode` / `lp.get_mode`、`vote_create` 的 `sleep_mode`、`MODE_CHANGE` 的第二参。

| 符号 | 值 | 用在哪个参数 |
| --- | --- | --- |
| `lp.MODE_NORMAL` | `0` | 目标档；**不能**作为 `vote_create` 的 `sleep_mode` |
| `lp.MODE_LOW_POWER` | `1` | 目标档 / 投票入睡档 |
| `lp.MODE_LOW_POWER_2` | `2` | 同上，投票默认档 |
| `lp.MODE_PSM_PLUS` | `3` | 目标档 / 投票入睡档 |

语义见 [3.4](#34-四档目标)。没有未导出却能用的第五档；越界会在 `set_mode` 抛错，在 `vote_create` 返回 `nil, err`。

### 5.2 网络回调 `state`

`reg_netcb` 回调第一参。

| 符号 | 值 | 含义 | 第二参 `extra` |
| --- | --- | --- | --- |
| `lp.NET_DETACHED` | `0` | 未驻网 | 无（不要读） |
| `lp.NET_ATTACHED` | `1` | 已驻网 | 无 |
| `lp.SIM_REMOVED` | `2` | SIM 拔出/不可用 | 无 |
| `lp.SIM_READY` | `3` | SIM 就绪 | 无 |
| `lp.MODE_CHANGE` | `4` | 工作模式已切换 | 切换后的 `mode` |
| `lp.WAKE` | `5` | 从休眠唤醒恢复 | 唤醒源 `WAKE_*` |

### 5.3 唤醒源

仅当 `state == lp.WAKE` 时，第二参为下列之一。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `lp.WAKE_POR` | `0` | 上电 / 复位 |
| `lp.WAKE_RTC` | `1` | RTC（含 delay/cron 到期、Sleep1 周期醒） |
| `lp.WAKE_PAD` | `2` | 引脚 |
| `lp.WAKE_UART` | `3` | 串口 |
| `lp.WAKE_USB` | `4` | USB |
| `lp.WAKE_PWRKEY` | `5` | 电源键 |
| `lp.WAKE_CHARG` | `6` | 充电 |

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `mode` | integer | `MODE_NORMAL` / `MODE_LOW_POWER` / `MODE_LOW_POWER_2` / `MODE_PSM_PLUS` |
| `VoteObj` | userdata | `vote_create` 成功返回值 |
| `key` | string | 非空，最长 31 字节 |
| `timeout_ms` | integer | `-1` 或省略=无限等；`>=0` 为毫秒 |
| `sim_id` | integer | `0` 翻转，`1` / `2` 指定卡槽 |
| `pdp` | integer | `0` 未驻网，`1` 已驻网（**不是 boolean**） |

`lp.islink()` 返回整数 `0`/`1`。在 Lua 里 `0` 仍为真，不要写 `if lp.islink() then`，应写 `if lp.islink() == 1 then`。

`wait_link` 返回的才是 boolean。

---

## 7. 模块函数

---

### 7.1 `lp.set_mode(mode)` {#7-1-set-mode}

设定休眠**目标**。不阻塞，不等待入睡。

**调用模式**

```lua
lp.set_mode(mode)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `mode` | `mode` | 是 | 四个 `MODE_*` 之一 |

**返回**

无返回值。非法 `mode` 抛错：`invalid sleep mode: <n>`。

```lua
lp.set_mode(lp.MODE_NORMAL)
lp.set_mode(lp.MODE_LOW_POWER)
lp.set_mode(lp.MODE_LOW_POWER_2)
lp.set_mode(lp.MODE_PSM_PLUS)
```

切到 `MODE_LOW_POWER_2` / `MODE_PSM_PLUS` 会关射频，随后会收到掉网 / SIM 不可用一类回调。TCP / MQTT 等会感应目标档并自动挂起，不必先手动 close。切回在网档后重新驻网，协议按自身逻辑恢复。

---

### 7.2 `lp.get_mode()` {#7-2-get-mode}

读当前目标档。

**调用模式**

```lua
lp.get_mode()
```

无参数。

**返回**

整数，四个 `MODE_*` 之一。

```lua
local m = lp.get_mode()
```

---

### 7.3 `lp.islink()` {#7-3-islink}

读缓存的 PDP 驻网状态。

**调用模式**

```lua
lp.islink()
```

无参数。

**返回**

- `1`：已驻网
- `0`：未驻网

在 `MODE_LOW_POWER_2` / `MODE_PSM_PLUS` 下 **恒为 `0`**。

```lua
if lp.islink() == 1 then
    -- 已驻网
end
```

---

### 7.4 `lp.wait_link([timeout_ms])` / `lp.wait_attach([timeout_ms])` {#7-4-wait-link}

阻塞当前任务，直到驻网或超时。`wait_attach` 是同一函数的别名。

已驻网则立即返回 `true`，不等待。

必须跑在 Lua 任务 / 协程里（与 `rt.delay` 相同）。在非法上下文会抛 `wait must run in coroutine/task` 或 `rt context not found`。

**调用模式**

```lua
lp.wait_link()
```

```lua
lp.wait_link(nil)
```

```lua
lp.wait_link(-1)
```

```lua
lp.wait_link(timeout_ms)
```

```lua
lp.wait_attach()
```

```lua
lp.wait_attach(timeout_ms)
```

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `timeout_ms` | integer | 否 | `-1`（无限等） | `nil`、省略、小于 `-1` 都按无限等；`0` 及以上为毫秒 |

**返回**

boolean：`true` 等到驻网（或调用时已经驻网）；`false` 超时。

等待期间当前任务空闲，**有利于**整机在目标档下入睡；驻网事件到来会唤醒该任务。

```lua
local ok = lp.wait_link(60000)
local ok2 = lp.wait_link(-1)
```

在 `MODE_LOW_POWER_2` 下射频是关的，会一直等不到驻网，不要用无限等待。

---

### 7.5 `lp.reg_netcb(cb)` {#7-5-reg-netcb}

登记网络 / 模式 / 唤醒回调。同一虚拟机重复登记会覆盖旧回调。

不允许在快捷回调上下文调用，否则抛 `reg_netcb not allowed in quick callback`。

登记成功后会 **立刻补一次** 当前驻网状态（`NET_ATTACHED` 或 `NET_DETACHED`），避免“先驻网后注册”丢首事件。

**调用模式**

```lua
lp.reg_netcb(cb)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cb` | function | 是 | 见 [第 9 节](#9-网络与唤醒回调) |

**返回**

- 成功：`true`
- 失败：抛错（`main vm not found` / `register rt topic failed` / 类型错误）

---

### 7.6 `lp.vote_create(...)` {#7-6-vote-create}

创建投票实例。成功返回 userdata；失败返回 `nil, err`（**不抛错**）。

默认：入睡档 `MODE_LOW_POWER_2`，最多 8 个 key，全释放后延迟 **10000 ms** 再切档。

创建时 active 票数为 0，会马上启动入睡倒计时（与“全释放”相同）。若你紧接着 `acquire`，倒计时会被取消并拉回常电。

`sleep_mode` **不能** 是 `MODE_NORMAL`。

**调用模式（表）**

```lua
lp.vote_create()
```

```lua
lp.vote_create({})
```

```lua
lp.vote_create({sleep_mode = lp.MODE_LOW_POWER_2})
```

```lua
lp.vote_create({mode = lp.MODE_LOW_POWER})
```

```lua
lp.vote_create({target_mode = lp.MODE_LOW_POWER_2})
```

```lua
lp.vote_create({sleep_mode = lp.MODE_LOW_POWER_2, max_keys = 8})
```

```lua
lp.vote_create({sleep_mode = lp.MODE_LOW_POWER_2, max_key_depth = 8})
```

```lua
lp.vote_create({sleep_mode = lp.MODE_LOW_POWER_2, sleep_delay_ms = 3000})
```

```lua
lp.vote_create({sleep_mode = lp.MODE_LOW_POWER_2, delay_ms = 3000})
```

```lua
lp.vote_create({
    sleep_mode = lp.MODE_LOW_POWER_2,
    max_keys = 8,
    sleep_delay_ms = 3000,
})
```

表字段别名（后写的覆盖先写的）：

| 字段 | 别名 | 默认 | 约束 |
| --- | --- | --- | --- |
| `sleep_mode` | `mode`，`target_mode` | `MODE_LOW_POWER_2` | 必须是可睡档，不能是 `MODE_NORMAL` |
| `max_keys` | `max_key_depth` | `8` | `1..32` |
| `sleep_delay_ms` | `delay_ms` | `10000` | `>= 0`；`0` 表示全释放后立刻切档 |

**调用模式（位置参）**

```lua
lp.vote_create(sleep_mode)
```

```lua
lp.vote_create(sleep_mode, max_keys)
```

```lua
lp.vote_create(sleep_mode, max_keys, sleep_delay_ms)
```

第一参必须是数字（模式）。不是 table 也不是数字时，三个参数都走默认值。

**返回**

- 成功：`VoteObj`
- 失败：`nil, err`，`err` 为下列之一：`invalid sleep mode` / `invalid max_keys` / `invalid sleep_delay_ms` / `vote instance limit reached` / `out of memory`

```lua
local vote, err = lp.vote_create({
    sleep_mode = lp.MODE_LOW_POWER_2,
    max_keys = 8,
    sleep_delay_ms = 3000,
})
if not vote then
    log.error("%s", err)
    return
end
```

---

### 7.7 `lp.config([tbl])` {#7-7-config}

读写 **本地 KV 里的 SIM / 驻网策略**（与 `AT+SIMCFG` 同类，不是当前瞬时射频状态）。改完下次按配置生效；运行时立刻切卡请用 `simslot`。

**调用模式**

```lua
lp.config()
```

```lua
lp.config(nil)
```

```lua
lp.config({slot = 1})
```

```lua
lp.config({
    slot = 1,
    sw_auto = 1,
    ready_time = 3,
    attach_time = 60,
    sw_num = 8,
    sw_silent = 600,
    remember = 0,
})
```

无参或 `nil`：只读，返回完整表。有表：只改出现的字段，未出现的字段保持原值。

| 字段 | 类型 | 合法取值 | 含义 |
| --- | --- | --- | --- |
| `slot` | integer | `1` 或 `2` | 默认卡槽（对外编号） |
| `sw_auto` | integer | `0` / `1` | 双卡自动切换 |
| `ready_time` | integer | `> 0` | 卡就绪超时（秒） |
| `attach_time` | integer | `> 0` | 驻网超时（秒） |
| `sw_num` | integer | `1..255` | 连续自动切卡上限 |
| `sw_silent` | integer | `> 0` | 达上限后的静默秒数 |
| `remember` | integer | `0` / `1` | 是否记忆上次驻网成功的卡槽 |

这些开关是 **整数 0/1**，不是 Lua boolean。`sw_auto = true` 会当成非法。

**返回**

- 成功：完整配置 table（含未改的字段）
- 失败：`nil, err`（`read failed` / `invalid param` / `write failed`）

自动切卡监测只在 `MODE_NORMAL` / `MODE_LOW_POWER`（在网档）下进行。

---

### 7.8 `lp.simslot([sim_id])` {#7-8-simslot}

查询或请求 **运行时** 切卡。始终返回当前生效卡槽（对外编号 `1` / `2`）。

**调用模式**

```lua
lp.simslot()
```

```lua
lp.simslot(nil)
```

```lua
lp.simslot(0)
```

```lua
lp.simslot(1)
```

```lua
lp.simslot(2)
```

| 参数 | 含义 |
| --- | --- |
| 省略 / `nil` | 只查询 |
| `0` | 在 `1` ↔ `2` 之间翻转后请求切换 |
| `1` | 请求切到卡槽 1 |
| `2` | 请求切到卡槽 2 |

切换是异步请求。函数返回的是 **此刻读到的槽位**，可能仍是切换前的值。非法参数或读槽失败抛错：`invalid sim_id (0|1|2)` / `get sim slot failed` / `invalid current sim slot`。

不写本地 KV；与 `config().slot` 不是同一层。

---

## 8. 对象方法（vote）

`key`：非空字符串，最长 31 字节。同一 key 重复 `acquire` 视为成功（幂等）。`release` 一个未持有的 key 失败。

有任一 key 处于 acquire：取消入睡倒计时，并把目标拉到 `MODE_NORMAL`。  
票数降到 0：启动 `sleep_delay_ms` 倒计时，到期且期间没有新的 acquire，才把目标设为创建时的 `sleep_mode`。这仍然只是改目标，真正入睡还要整机空闲。

失败风格：多数返回 `false, err`；`status` 在实例无效时抛错。

---

### 8.1 `obj:acquire(key)` {#8-1-acquire}

本 key 投票保活。从 0 票到 1 票时拉到常电。

**调用模式**

```lua
obj:acquire(key)
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `key` | string | 是 | 业务名，如 `"mqtt"`、`"task_a"` |

**返回**

- 成功：`true`（含重复 acquire 同一 key）
- 失败：`false, err`（`invalid vote instance` / `invalid key` / `key table full`）

---

### 8.2 `obj:release(key)` {#8-2-release}

本 key 允许睡。最后一张票释放后启动入睡倒计时。

**调用模式**

```lua
obj:release(key)
```

**返回**

- 成功：`true`
- 失败：`false, err`（`invalid vote instance` / `invalid key` / `key not active` / `schedule sleep failed`）

---

### 8.3 `obj:vote(key, active)` {#8-3-vote}

按第二参在 acquire / release 之间选择。第二参的“真假”**不是**纯 Lua boolean：

| 第二参 | 视为保活（acquire） | 视为释放（release） |
| --- | --- | --- |
| boolean | `true` | `false` |
| integer | **非 0**（此处 `0` 为释放） | `0` |
| string | `"1"` / `"on"` / `"active"` | 其它字符串 |
| 其它 / 省略 | — | 释放 |

多传的第三参不参与判定。业务 key 请用 `acquire` / `release`，避免和上述字符串规则搅在一起。

**调用模式**

```lua
obj:vote(key, true)
```

```lua
obj:vote(key, false)
```

```lua
obj:vote(key, 1)
```

```lua
obj:vote(key, 0)
```

```lua
obj:vote("on")
```

```lua
obj:vote("active")
```

```lua
obj:vote("1")
```

**返回**

与 `acquire` / `release` 相同。

---

### 8.4 `obj:clear()` {#8-4-clear}

清空全部 key，票数归零，启动入睡倒计时。

**调用模式**

```lua
obj:clear()
```

无参数。

**返回**

- 成功：`true`
- 失败：`false, err`

---

### 8.5 `obj:status()` {#8-5-status}

查询实例状态。

**调用模式**

```lua
obj:status()
```

无参数。

**返回** table：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `active_count` | integer | 当前保活票数 |
| `sleep_mode` | integer | 全释放后要回到的目标档 |
| `sleep_delay_ms` | integer | 倒计时毫秒 |
| `max_keys` | integer | 槽位数 |
| `keys` | string 数组 | 当前仍 acquire 的 key，从下标 1 起 |

实例已回收时抛 `invalid vote instance`。

---

## 9. 网络与唤醒回调

```lua
function cb(state, extra)
```

| 参数 | 何时有意义 |
| --- | --- |
| `state` | 每次都有，见 [5.2](#52-网络回调-state) |
| `extra` | 仅 `MODE_CHANGE`（新 `mode`）和 `WAKE`（`WAKE_*`） |

跑在 Lua **调度循环**里，不是硬件中断、也不是独立 task：

- 立刻返回。不要 `rt.delay`、不要 `uart` 阻塞、不要长 log。
- 打印和业务放到 `rt.task_start` 的任务里，用邮箱接力。

`WAKE` 的队列有限（16 个唤醒源）。极端连续唤醒时旧源会被挤掉；对不齐时退回 `WAKE_POR`。

回调内部抛错会被吞掉并记日志，不影响调度继续。

---

## 10. 投票语义

```
acquire ─(票 0→1)─→ 目标 = MODE_NORMAL（保活）
release ─(票 →0)─→ 等 sleep_delay_ms ──→ 目标 = 创建时的 sleep_mode
```

倒计时期间再次 `acquire`：取消定时器，继续常电。

`sleep_delay_ms == 0`：最后一张票释放后立刻改目标。

多实例互相独立，但它们改的是 **同一份整机目标档**。两套 vote 同时用时，后一次 `set_mode` 会覆盖前一次，容易打架。通常全机一个 vote 实例。

真正入睡仍要 [第 3 节](#3-低功耗机制) 的全体空闲。投票只负责“准不准睡这档”，不负责把其它 task 挂起。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `set_mode` | 无返回 | 抛错 |
| `get_mode` | integer | — |
| `islink` | `0` 或 `1` | — |
| `wait_link` / `wait_attach` | boolean | 超时 `false`；非法上下文抛错 |
| `reg_netcb` | `true` | 抛错 |
| `vote_create` | userdata | `nil, err` |
| `config` | table | `nil, err` |
| `simslot` | integer 槽位 | 抛错 |
| `acquire` / `release` / `vote` / `clear` | `true` | `false, err` |
| `status` | table | 抛错 |

```lua
local vote, err = lp.vote_create({sleep_mode = lp.MODE_NORMAL})
-- vote == nil, err == "invalid sleep mode"
```

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| vote 实例 | 8 | 超出 `vote instance limit reached` |
| 每实例 key 槽 | 1..32 | 默认 8 |
| key 长度 | 31 字节 | 空串非法 |
| 唤醒源排队 | 16 | 过密时丢最旧的 |
| 网络回调 | 每 VM 一条 | 重复 `reg_netcb` 覆盖 |

vote 对象 `__gc` 拆除实例（停倒计时、释放槽）。虚拟机退出后回调登记失效。没有“关闭 lp 模块”的接口。

`wait_link` / `delay` / `mbox_recv` 会让出当前任务，这是休眠能发生的前提，不是泄漏。

---

## 13. 选型对照

| 需求 | 用法 |
| --- | --- |
| 在网、可接受一秒一跳的寻呼电流 | `set_mode(MODE_LOW_POWER)` + 全体 `delay`/`recv` |
| 长期离网、要压电流 | `set_mode(MODE_LOW_POWER_2)`；socket / MQTT 会自动挂起，不必先 close |
| 常电调试 | `MODE_NORMAL` |
| 多任务有人干活、有人歇 | 一个 `vote_create` + `acquire`/`release` |
| 等能上网再发 MQTT | `wait_link(timeout)` 且当时必须是在网档 |
| 看从哪醒的 | `reg_netcb` 判断 `WAKE` |
| 改默认卡槽策略 | `config` |
| 立刻切另一张卡 | `simslot(1\|2)` |

`set_mode` 和 `vote` 不要各管各的互相覆盖。常用：vote 的 `sleep_mode` 与产品休眠档一致；干活 `acquire`，干完 `release`。

---

## 14. 完整示例

### 14.1 设定目标后让出（Sleep1 在网）

```lua
local rt = require("rt")
local log = require("log")
local lp = require("lp")

lp.reg_netcb(function(state, extra)
    if state == lp.WAKE then
        log.info("WAKE src=%s", tostring(extra))
    elseif state == lp.MODE_CHANGE then
        log.info("MODE_CHANGE %s", tostring(extra))
    end
end)

lp.set_mode(lp.MODE_LOW_POWER)
while true do
    rt.delay(120000)   -- 让出：空闲才 Sleep1；一秒一跳扫站正常
end
```

### 14.2 投票保活

与 [examples/NT26/module/lp/lowpower_vote](../../../../examples/NT26/module/lp/lowpower_vote) 一致：干活 `acquire`，结束 `release`，入口 `delay(-1)`。

```lua
local rt = require("rt")
local log = require("log")
local lp = require("lp")

lp.set_mode(lp.MODE_LOW_POWER_2)
local vote, err = lp.vote_create({
    sleep_mode = lp.MODE_LOW_POWER_2,
    max_keys = 8,
    sleep_delay_ms = 3000,
})
if not vote then
    log.error("%s", err)
    return
end

rt.task_start(function()
    while true do
        vote:acquire("task_a")
        rt.delay(8000)          -- 模拟业务；此时目标是常电
        vote:release("task_a")
        rt.delay(22000)         -- 让出：全票释放并过了 3s 后才允许低功耗 2
    end
end)

rt.delay(-1)
```

### 14.3 等驻网

```lua
local linked = lp.wait_link(60000)
if not linked then
    log.warn("网络超时")
    return
end
```

---

## 附录 A. 方法速查

| 调用 | 参数模式 | 返回 |
| --- | --- | --- |
| `lp.set_mode(mode)` | 1 个必填 | 无 / 抛错 |
| `lp.get_mode()` | 无 | integer |
| `lp.islink()` | 无 | `0\|1` |
| `lp.wait_link()` | 无限等 | boolean |
| `lp.wait_link(ms)` | 超时毫秒 | boolean |
| `lp.wait_attach(...)` | 与 `wait_link` 相同 | boolean |
| `lp.reg_netcb(cb)` | 1 个函数 | `true` / 抛错 |
| `lp.vote_create()` | 全默认 | userdata 或 `nil, err` |
| `lp.vote_create({...})` | 表，字段均可选 | 同上 |
| `lp.vote_create(mode[, keys[, delay]])` | 位置参 | 同上 |
| `lp.config()` | 只读 | table 或 `nil, err` |
| `lp.config(tbl)` | 局部写 | 同上 |
| `lp.simslot()` | 查询 | `1\|2` |
| `lp.simslot(0\|1\|2)` | 翻转或指定 | `1\|2` / 抛错 |
| `obj:acquire(key)` | 1 个字符串 | `true` 或 `false, err` |
| `obj:release(key)` | 1 个字符串 | 同上 |
| `obj:vote(key, active)` | 见 8.3 | 同上 |
| `obj:clear()` | 无 | 同上 |
| `obj:status()` | 无 | table / 抛错 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `lp.MODE_NORMAL` | 0 |
| `lp.MODE_LOW_POWER` | 1 |
| `lp.MODE_LOW_POWER_2` | 2 |
| `lp.MODE_PSM_PLUS` | 3 |
| `lp.NET_DETACHED` | 0 |
| `lp.NET_ATTACHED` | 1 |
| `lp.SIM_REMOVED` | 2 |
| `lp.SIM_READY` | 3 |
| `lp.MODE_CHANGE` | 4 |
| `lp.WAKE` | 5 |
| `lp.WAKE_POR` | 0 |
| `lp.WAKE_RTC` | 1 |
| `lp.WAKE_PAD` | 2 |
| `lp.WAKE_UART` | 3 |
| `lp.WAKE_USB` | 4 |
| `lp.WAKE_PWRKEY` | 5 |
| `lp.WAKE_CHARG` | 6 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
