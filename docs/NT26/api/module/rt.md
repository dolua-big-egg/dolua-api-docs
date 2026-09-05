# rt

**文档版本** `1.1.0`

运行时调度：协作式任务、让出延时、信箱、显式队列、软件定时器。没有对象。脚本里的「多任务」是同一虚拟机里的协程，不是操作系统抢占线程。

```lua
local rt = require("rt")
```

平台预加载模块，无需额外 `.lua` 文件。`require("rt")` 时会挂上本虚拟机的调度上下文；失败抛 `rt ctx alloc failed`。

除 `mem` 外，下列名字还会写到 **全局**：`task_start`、`delay`、`mbox_*`、`mq_*`、`tmr_*`。推荐始终写 `rt.xxx`，避免和脚本局部变量撞名。

日常等待用 `rt.delay`。不要用 [`sys.delay_ms`](sys.md) 代替：那会卡住整条 Lua 引擎线程。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞与回调语义](#3-阻塞与回调语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `rt.task_start`](#6-1-task-start)
  - [6.2 `rt.delay`](#6-2-delay)
  - [6.3 `rt.mem`](#6-3-mem)
  - [6.4 `rt.mbox_send`](#6-4-mbox-send)
  - [6.5 `rt.mbox_recv`](#6-5-mbox-recv)
  - [6.6 `rt.mbox_reg`](#6-6-mbox-reg)
  - [6.7 `rt.mq_create`](#6-7-mq-create)
  - [6.8 `rt.mq_send`](#6-8-mq-send)
  - [6.9 `rt.mq_recv`](#6-9-mq-recv)
  - [6.10 `rt.mq_count`](#6-10-mq-count)
  - [6.11 `rt.mq_reset`](#6-11-mq-reset)
  - [6.12 `rt.mq_delete`](#6-12-mq-delete)
  - [6.13 `rt.tmr_once`](#6-13-tmr-once)
  - [6.14 `rt.tmr_loop`](#6-14-tmr-loop)
  - [6.15 `rt.tmr_stop`](#6-15-tmr-stop)
  - [6.16 `rt.tmr_start`](#6-16-tmr-start)
  - [6.17 `rt.tmr_delete`](#6-17-tmr-delete)
- [7. 信箱 / 队列里能放什么](#7-信箱--队列里能放什么)
- [8. `mbox` 与 `mq`](#8-mbox-与-mq)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

五类能力：

1. **任务**：`task_start` 开协程；入口 `main.lua` 本身也是一条协程，顶层就能 `delay`。
2. **让出**：`delay` 只挂起当前协程，调度循环继续跑别的任务、定时器和外设回调。
3. **信箱 `mbox_*`**：按 topic 广播。`send` 进事件队列，正在 `recv` 的协程和 `reg` 的回调都能收到同一条。不排队积压给后来的 `recv`。
4. **队列 `mq_*`**：必须先 `create`。FIFO 积压，一条消息只唤醒一个 `recv`。
5. **定时器 `tmr_*`**：定时器到期后投进调度循环再调 Lua，最多 8 路。

UART / GPIO / MQTT 的回调也由同一套循环派发。回调里只能做短事（例如 `mbox_send`），不要 `delay` / `mbox_recv` / `mq_recv`。

当前固件 **一个脚本虚拟机**。模块表没有整数枚举常量。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  task_start / delay / mbox_* / mq_* / tmr_*              │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  rt 调度                                                 │
│  · 协程槽：让出 / 唤醒                                   │
│  · 事件队列：信箱、定时器到期、外设完成                   │
│  · 同一时刻只跑一条 Lua 协程                             │
└──────────────┬───────────────────────────┬──────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────┐       ┌──────────────────────┐
│ 任务协程              │       │ 调度循环里的短回调    │
│ delay / recv 在这里   │       │ uart.reg / tmr /     │
│                      │       │ mbox_reg：马上返回    │
└──────────────────────┘       └──────────────────────┘
```

| 路径 | 谁在等 | 其它 Lua 协程 | 典型用途 |
| --- | --- | --- | --- |
| `delay` / `mbox_recv` / `mq_recv` | 当前协程让出 | **能跑** | 周期任务、等消息 |
| `mbox_send` / `mq_send` | 入队即返回 | 不让出 | 从回调投递到工作协程 |
| `tmr_*` 回调 | 调度循环里执行 | 回调期间占用调度 | 周期打点、超时 |
| [`sys.delay_ms`](sys.md) | 整条引擎线程 | **都不能跑** | 不要当日常 delay |

入口若 `while true` 且从不 `delay`，其它任务和定时器回调都会饿死。

---

## 3. 阻塞与回调语义

**必须在任务协程里让出的**：`delay`（有效毫秒）、`mbox_recv`、`mq_recv`（队列空时）。入口脚本顶层算任务协程。在 UART / MQTT / 定时器 / `mbox_reg` 回调里调用会失败或卡死调度（主状态上会抛 `wait must run in coroutine/task`）。

**必须马上返回的**：`mbox_reg` 回调、`tmr_once` / `tmr_loop` 回调、以及 uart/gpio 等模块回调。里面可以 `mbox_send` / `mq_send`，不要 `delay`。

超时单位是 **毫秒**。底层按内核 tick 换算，不足 1 tick 按 1 tick。`timeout < -1` 的等待一律当成 **-1（无限等）**。

[`uart.block`](../peripherals/uart.md) 走同一套让出，全脚本同一时刻只能有一个 UART block。

---

## 4. 常量与枚举

模块表 **没有** 整数枚举常量。上限见 [第 10 节](#10-资源上限与生命周期)，用数字写在调用里（例如队列深度 `4`）。

topic 是 string，最长 **23** 字节（第 24 字节留给结尾）。超长会被截断，不同 topic 截成相同前缀会撞车。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `fn` / `callback` | function | 任务入口或定时器/信箱回调 |
| `ms` / `timeout_ms` | integer / number | 毫秒 |
| `topic` | string | 信箱或队列名 |
| `value` / `data` | nil / boolean / number / string / table | 见 [第 7 节](#7-信箱--队列里能放什么) |
| `depth` | integer | `1`～`128`（不是布尔：这里的 `0` 就是非法深度） |
| `timer_id` | integer | `1`～`8` |
| `arg1` / `arg2` | 任意（`nil` 不登记） | 定时器回调额外参数，最多 2 个 |

本模块公开参数 **没有**「数字 `0` 当布尔真」的接口。`delay` 的 `0` 表示不让出；`mq_create` 的 `depth`、`tmr_*` 的 `ms` / `timer_id` 都按整数读。

---

## 6. 模块函数

---

### 6.1 `rt.task_start(fn)` {#6-1-task-start}

立刻开一条协程跑 `fn`（无参数）。`fn` 一遇到 `delay` / `recv` 就让出，`task_start` 随即返回 `true`。若 `fn` 跑完都没让出，协程结束，槽位释放，仍然返回 `true`。

**调用模式**

```lua
rt.task_start(fn)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `fn` | 是 | function |

成功：`true`。失败 **抛错**：

| 文案 | 原因 |
| --- | --- |
| `rt context not found` | 调度未就绪 |
| 类型错 | `fn` 不是 function |
| `no task slot` | 已满 16 条（含入口占用的槽） |
| `task start failed: …` | `fn` 在第一次让出前就报错 |

`fn` 里死循环且从不让出，会卡在 `task_start` 里，后面的脚本不会执行。

```lua
rt.task_start(function()
    while true do
        -- 干活
        rt.delay(1000)
    end
end)
```

---

### 6.2 `rt.delay(ms)` {#6-2-delay}

让出当前协程。

**调用模式**

```lua
rt.delay()
rt.delay(ms)
```

| `ms` | 行为 |
| --- | --- |
| 省略 / `nil` / 无法当成数字（boolean、table、function 等） | **不让出**，立即返回（无返回值） |
| `0` | 同上，不让出 |
| `> 0` | 睡这么多毫秒后唤醒 |
| `-1` | 无限让出，不设超时（几乎用不到） |
| `< -1` | 按 `-1` |

能转成数字的 string（如 `"1000"`）按数字处理。浮点会截成整数。

有效让出时无返回值（yield）。必须在任务协程里。

```lua
rt.delay(1000)
rt.delay(0)      -- 空操作
```

对比 [`sys.delay_ms`](sys.md)：那种会卡住所有 Lua 协程。

---

### 6.3 `rt.mem()` {#6-3-mem}

看本 VM 的 Lua 堆。

**调用模式**

```lua
rt.mem()
```

成功：`used_bytes, max_bytes` 两个整数。分配器不可用：两个 `nil`。

不写到全局，只能 `rt.mem()`。

```lua
local used, maxb = rt.mem()
```

---

### 6.4 `rt.mbox_send(topic[, value])` {#6-4-mbox-send}

向信箱投一条。进本 VM 事件队列，**不在 mbox 里排队给迟到的 recv**。当时正在该 topic 上 `mbox_recv` 的协程，以及 `mbox_reg` 的回调，都会收到。

**调用模式**

```lua
rt.mbox_send(topic)
rt.mbox_send(topic, value)
```

省略 `value` 当作 `nil`。

成功：`true`。编码失败或事件队列满 **抛错**（不是 `false`）：

| 文案 | 原因 |
| --- | --- |
| `mbox msgpack encode failed (max 8192 bytes): …` | 值非法或太大，后缀见第 7 节 |
| `mbox data alloc failed` | 内存 |
| `evt queue full` | 事件队列（深度 128）满 |

可在短回调里调用。

```lua
rt.mbox_send("uart1", data)
rt.mbox_send("tick")          -- value 为 nil
```

---

### 6.5 `rt.mbox_recv(topic[, timeout_ms])` {#6-5-mbox-recv}

当前协程等待该 topic 的下一条信箱消息。

**调用模式**

```lua
rt.mbox_recv(topic)
rt.mbox_recv(topic, timeout_ms)
```

`timeout_ms` 默认 `-1`（一直等）。

成功收到：`true, data`。超时：`false, nil`。

`topic` 必须是 string，否则 **抛错**。必须在任务协程里。

没有积压：若 send 时没有人 recv、也没有 reg，这条就丢了（和 `mq` 不同）。

```lua
local ok, data = rt.mbox_recv("uart1")
local ok2, data2 = rt.mbox_recv("uart1", 1000)
```

---

### 6.6 `rt.mbox_reg(topic, callback)` {#6-6-mbox-reg}

登记信箱回调。同一 topic 可挂多路，每 topic 最多 **8** 个。

**调用模式**

```lua
rt.mbox_reg(topic, callback)
```

`callback(data)`：`data` 与 `mbox_recv` 解出来的值同类。跑在调度循环，必须马上返回。

成功：`true`。失败 **抛**：`no subscriber slot`（topic 槽满，最多 124 个不同 topic）、`subscriber full`、`rt context not found`，或 callback 不是 function。

没有 `mbox_unreg`。虚拟机退出时一起拆掉。

UART 收到后丢给工作协程：见 [examples/NT26/os/rt/mbox_uart](../../../../examples/NT26/os/rt/mbox_uart)。

---

### 6.7 `rt.mq_create(topic, depth)` {#6-7-mq-create}

创建显式队列。必须先 create 才能 send/recv。

**调用模式**

```lua
rt.mq_create(topic, depth)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `topic` | 是 | string |
| `depth` | 是 | 整数 `1`～`128` |

成功：`true`。失败：`false, err`（不抛，除缺参/类型）。

| `err` | 原因 |
| --- | --- |
| `bad depth` | 不在 1～128 |
| `exists` | 同名队列已在 |
| `no slot` | topic 槽用完 |
| `no memory` | 分配失败 |

```lua
local ok, err = rt.mq_create("demo_mq", 4)
```

---

### 6.8 `rt.mq_send(topic[, value])` {#6-8-mq-send}

把值追加到队列尾。队列满不会覆盖。

**调用模式**

```lua
rt.mq_send(topic)
rt.mq_send(topic, value)
```

省略 value 为 `nil`。值规则与 mbox 相同。

成功：`true`。失败：`false, err`。

| `err` | 原因 |
| --- | --- |
| `not found` | 未 create |
| `full` | 已达 depth |
| `no memory` / `wake failed` | 内存或唤醒失败 |
| `encode failed (max 8192 bytes): …` | 与 mbox 同类 |

可在短回调里 send。

---

### 6.9 `rt.mq_recv(topic[, timeout_ms])` {#6-9-mq-recv}

FIFO 取一条。队列非空立即返回；空则让出等待。一条消息只给 **一个** 等待者。

**调用模式**

```lua
rt.mq_recv(topic)
rt.mq_recv(topic, timeout_ms)
```

默认超时 `-1`。

成功：`true, data, nil`。失败：`false, nil, err`。

| `err` | 原因 |
| --- | --- |
| `not found` | 未 create |
| `timeout` | 等到超时仍空 |
| `deleted` | 等待中被 `mq_delete` |
| `pop failed` | 取出失败（极少） |

必须在任务协程里（队列空走让出时）。

```lua
local ok, data, err = rt.mq_recv("demo_mq", 100)
```

---

### 6.10 `rt.mq_count(topic)` {#6-10-mq-count}

**调用模式**

```lua
rt.mq_count(topic)
```

存在：`count, depth, nil`。不存在：`-1, 0, "not found"`。

```lua
local count, depth, err = rt.mq_count("demo_mq")
```

---

### 6.11 `rt.mq_reset(topic)` {#6-11-mq-reset}

清空已缓存消息，**容器还在**，正在 `recv` 的协程继续等。

**调用模式**

```lua
rt.mq_reset(topic)
```

成功：`true`。不存在：`false, "not found"`。

---

### 6.12 `rt.mq_delete(topic)` {#6-12-mq-delete}

清空并删掉队列。正在 `recv` 的协程得到 `false, nil, "deleted"`。

**调用模式**

```lua
rt.mq_delete(topic)
```

成功：`true`。不存在：`false, "not found"`。之后同名可再 `create`。

---

### 6.13 `rt.tmr_once(ms, callback[, arg1[, arg2]])` {#6-13-tmr-once}

一次性定时器。到期后在调度循环调 `callback(arg1, arg2)`，然后 **自动释放槽**。

**调用模式**

```lua
rt.tmr_once(ms, callback)
rt.tmr_once(ms, callback, arg1)
rt.tmr_once(ms, callback, arg1, arg2)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `ms` | 是 | 毫秒；`<= 0` 按 **1** |
| `callback` | 是 | function |
| `arg1` / `arg2` | 否 | `nil` 不算参数 |

成功：`timer_id`（`1`～`8`）。失败 **抛**：`no timer slot`、`tmr_once create failed`、`tmr_once start failed`。

回调必须短。不要在回调里 `delay`。

```lua
local id = rt.tmr_once(2000, function(tag)
    log.info("once %s", tag)
end, "hello")
```

---

### 6.14 `rt.tmr_loop(ms, callback[, arg1[, arg2]])` {#6-14-tmr-loop}

周期定时，一直占槽直到 `tmr_delete`。参数与 `tmr_once` 相同。

**调用模式**

```lua
rt.tmr_loop(ms, callback)
rt.tmr_loop(ms, callback, arg1)
rt.tmr_loop(ms, callback, arg1, arg2)
```

成功：`timer_id`。失败抛 `no timer slot` / `tmr_loop create failed` / `tmr_loop start failed`。

```lua
local id = rt.tmr_loop(1000, function()
    -- 每秒一次
end)
```

---

### 6.15 `rt.tmr_stop(timer_id)` {#6-15-tmr-stop}

暂停，不释放 callback 和槽。

**调用模式**

```lua
rt.tmr_stop(timer_id)
```

成功：`true`。失败：`false, "not found"` 或 `"stop failed"`。

---

### 6.16 `rt.tmr_start(timer_id)` {#6-16-tmr-start}

用创建时的 `ms` 再开。会先 stop 再 start。

**调用模式**

```lua
rt.tmr_start(timer_id)
```

成功：`true`。失败：`false, "not found"` / `"start failed"`。

once 已经触发并释放后不能再 start。

---

### 6.17 `rt.tmr_delete(timer_id)` {#6-17-tmr-delete}

停止并释放槽。

**调用模式**

```lua
rt.tmr_delete(timer_id)
```

成功：`true`。不存在：`false, "not found"`。

---

## 7. 信箱 / 队列里能放什么

`mbox_send` 与 `mq_send` 同一套编码。逻辑值：

| 可发送 | 收到时 |
| --- | --- |
| `nil` | `nil` |
| boolean | boolean |
| 整数 / 浮点 | number（整数尽量保持整数） |
| string（可含 `0x00`） | string |
| table | table（数组或字符串/数字/布尔键的映射） |

嵌套表最多 **10** 层。表项合计最多 **4096**。键只支持 string / number / boolean。

**不能发**：function、userdata、thread、循环引用、以 `nil` 为键。失败文案常见：

- `unsupported value type`
- `unsupported table key`
- `table depth exceeded` / `table too large`
- `string too large`
- `payload exceeds mbox limit: …`（整包超过 8192 字节）

整包（含编码开销）上限 **8192** 字节。

---

## 8. `mbox` 与 `mq`

| | `mbox` | `mq` |
| --- | --- | --- |
| 创建 | 不用 | 必须 `mq_create` |
| 积压 | 无。没人听就丢 | 有，直到 recv / reset / delete |
| 多个等待者 | **广播**（都收到） | **一个** 拿走 |
| 回调 | `mbox_reg` | 无，靠协程 recv |
| send 失败 | **抛错** | `false, err` |
| 典型 | 回调 → 工作协程 | 生产者积压、消费者拉空 |

topic 名字空间：mbox 的订阅槽和 mq 的队列槽是两套，各最多 124 个名字，但不要用同一字符串混用两套，以免自己看晕。

内部主题（UART/GPIO/SMS 完成事件等）**不会**进 `mbox_recv` / `mbox_reg`。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `task_start` | `true` | **抛** |
| `delay`（有效） | 无返回值 | 不在协程里 **抛** |
| `mem` | 两整数 | 两个 `nil` |
| `mbox_send` / `mbox_reg` | `true` | **抛** |
| `mbox_recv` | `true, data` | `false, nil`（超时） |
| `mq_create` / `mq_send` / `mq_reset` / `mq_delete` | `true` | `false, err` |
| `mq_recv` | `true, data, nil` | `false, nil, err` |
| `mq_count` | `count, depth, nil` | `-1, 0, "not found"` |
| `tmr_once` / `tmr_loop` | `timer_id` | **抛** |
| `tmr_stop` / `tmr_start` / `tmr_delete` | `true` | `false, err` |

让出类在主状态（非协程）上：`wait must run in coroutine/task`。槽满：`wait no task slot`。

**抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `rt context not found` | 不在脚本 VM（几乎只见于错误嵌入） |
| `wait must run in coroutine/task` | 在非协程上下文 `delay`/`mbox_recv`/`wait_connect` |
| `wait no task slot` / `no task slot` | 任务槽满（含入口，约 16） |
| `wait timer create failed` / `wait timer start failed` | 系统定时器资源 |
| `no subscriber slot` / `subscriber full` | mbox 订阅满（topic 124 / 每 topic 回调 8） |
| `mbox msgpack encode failed (max N bytes): …` | 投递的值编码超过 8192 或类型不能打包 |
| `mbox data alloc failed` | 投递缓冲分配失败 |
| `evt queue full` | 事件队列 128 满，生产快于消费 |
| `no timer slot` | 8 路定时器用完 |
| `tmr_once create/start failed` / `tmr_loop create/start failed` | 系统定时器 |
| `task start failed: …` | 协程没建起来 |
| `invalid uart id` | 内部串口等待 id 非法 |
| `invalid internal wait topic` | 内部同步 topic 空（tcp/mqtt wait_connect 异常） |
| `invalid flashdb/lfs mount topic` | 异步挂载 topic 非法 |

**`mq_*` / `tmr_stop` 等返回的 `err`**

| `err` | 可能原因 |
| --- | --- |
| `bad depth` | `mq_create` 深度不是 1～128 |
| `exists` | 同名队列已在 |
| `no slot` | 队列名字数量满（124） |
| `no memory` | 队列缓冲分配失败 |
| `not found` | 名字不存在或定时器 id 无效 |
| `encode failed (max N bytes): …` | `mq_send` 值超 8192 或不能打包 |
| `wake failed` | 唤醒接收方失败 |
| `pop failed` | 出队失败 |
| `stop failed` / `start failed` | 定时器启停失败 |
| `busy` | 内部同步等待同 topic 重入（uart block / wait_connect） |

诊断：`evt queue full` 回调里少 `mbox_send` 大表、加快工作协程 `mbox_recv`；`no task slot` 少开死循环任务；`encode failed` 不要投 function/userdata。

---

## 10. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 脚本 VM | **1** |
| 任务协程 | **16**（含入口第一次 delay 占用的槽） |
| 不同 topic（mbox 订阅） | **124** |
| 每 topic 的 mbox 回调 | **8** |
| mq 深度 | **128** |
| mq 不同名字 | **124** |
| topic 字符串 | **23** 字节 |
| 定时器 | **8**，id 从 1 计；每路最多 2 个额外参数 |
| 事件队列 | **128** |
| 单条 mbox/mq 编码 | **8192** 字节 |
| 表嵌套 | **10** 层 |
| 表项 | **4096** |

虚拟机退出：任务、等待、信箱回调、队列、定时器全部拆掉。没有用户态 `close` 整个 rt。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 周期干活、不卡死别人 | `task_start` + `delay` |
| 回调里把数据交给协程处理 | `mbox_send` + 工作协程 `mbox_recv` |
| 需要积压、一对一消费 | `mq_*` |
| 周期回调、不要开协程 | `tmr_loop` |
| 一次性延迟回调 | `tmr_once` |
| 等一包串口 | [`uart.block`](../peripherals/uart.md) |
| 精确忙等、不允许插队 | [`sys.delay_ms`](sys.md) / `delay_us`（慎用） |

demo：[examples/NT26/os/rt/task_delay](../../../../examples/NT26/os/rt/task_delay)、[examples/NT26/os/rt/mbox_uart](../../../../examples/NT26/os/rt/mbox_uart)、[examples/NT26/os/rt/mq_api](../../../../examples/NT26/os/rt/mq_api)、[examples/NT26/os/rt/tmr_api](../../../../examples/NT26/os/rt/tmr_api)。

---

## 12. 完整示例

协作三协程（与 `task_delay` demo 同类）：

```lua
local rt = require("rt")

rt.task_start(function()
    while true do
        -- 任务 A
        rt.delay(1000)
    end
end)

while true do
    -- 入口协程
    rt.delay(2000)
end
```

回调投递到工作协程：

```lua
rt.task_start(function()
    while true do
        local ok, data = rt.mbox_recv("uart1")
        if ok then
            -- 处理 data
        end
    end
end)

-- 在 uart.reg 回调里：
-- rt.mbox_send("uart1", data)
```

FIFO 队列：

```lua
rt.mq_create("demo_mq", 4)
rt.mq_send("demo_mq", { n = 1 })
local ok, data, err = rt.mq_recv("demo_mq", 100)
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全抛错摘要、mq/tmr 的 err 文案与可能原因 |
