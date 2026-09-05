# uart

**文档版本** `1.1.0`

纯函数串口模块。对外业务口是 UART1～UART3：热改线参数、写数据、登记收包回调、或阻塞等一整包。没有对象、没有 `open`。UART0 留给内部调试，**不对外使用**。

```lua
local uart = require("uart")
```

平台预加载模块，无需额外 `.lua` 文件。

回调和 `block` 拿到的都是已经按空闲超时 / 单包上限切好的 **一包**，不是每个字节一次。分包三参数不在本模块里改，写在 `rtu_config.cfg` 的 `[uart.N]`，开机生效。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞与回调语义](#3-阻塞与回调语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `uart.config`](#6-1-config)
  - [6.2 `uart.get_config`](#6-2-get-config)
  - [6.3 `uart.write`](#6-3-write)
  - [6.4 `uart.reg`](#6-4-reg)
  - [6.5 `uart.unreg`](#6-5-unreg)
  - [6.6 `uart.block`](#6-6-block)
- [7. 收包回调协议](#7-收包回调协议)
- [8. 分包与配置落盘](#8-分包与配置落盘)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

对外三路业务串口（UART1～UART3），用整数 id 或模块常量点名：

```lua
local U = uart.UART1   -- 1
```

UART0 不给脚本当业务口：脚不对外、`rtu_config.cfg` 里的 `[uart.0]` 会被忽略，收到的数据也不会进 `reg` / `block`。模块表虽导出 `uart.UART0`，请不要用。

典型用法：

1. （可选）`uart.config(id, { baudrate = 115200, ... })` 热改线参数，**立刻生效，不写盘**。
2. 收数据：`reg` 和 `block` **可以同时用**，不是二选一。
   - `uart.reg(id, cb)`：平时来一包调一次回调（须立刻返回）。
   - `uart.block(id, timeout_ms)`：当前任务协程等到一包或超时。即使已经 `reg`，正在 `block` 的那一口到来的包会先被这次 `block` **截走**，不进回调；`block` 结束后，后续包再回到 `reg`。
3. `uart.write(id, data)` 发送。字符串或连续字节表都可以。

引脚组 `pin_map`、分包 `max_packet_size` / `max_wait_ms` / `max_packets` **不能** 用本模块改。改 `rtu_config.cfg` 后重新加载配置。

`print` / `log` 默认也走某路串口（常见 UART1，只能是 1/2/3，不能是 UART0）。业务口若和日志同口，输出会搅在一起。用 `sys.option("print_route")` / `"log_route"` 把日志挪开。外挂 SPI 时 UART2 默认脚常冲突，见 [`sfud`](../module/sfud.md)。

做 RS485 / 透传时，demo 会 `rtu.option("pass_up", false)` 和 `"pass_down", false`，避免这路被当成 AT 通道吃掉报文。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  config / write / reg / unreg / block                    │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  uart 模块                                               │
│  · 按 id 热改波特率等（不写盘）                           │
│  · 写出排队发送                                          │
│  · 收包：block 优先；否则进本 VM 的 reg 回调              │
└────────────────────────────┬────────────────────────────┘
                             │
        硬件收字节 → 按分包规则攒成一包 → 投进运行时队列
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Lua 调度循环                                            │
│  block 恢复协程  或  调用 cb(id, data, meta)             │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `config` / `get_config` / `write` / `reg` / `unreg` | 改线、排队发送、登记 | **否** | 当前协程（很快返回） |
| `write` | 把数据交给发送队列 | 否 | **不等** 发完 |
| `block` | 挂起当前 **任务协程** 等一包 | **是**（仅当前协程） | 其它 task / 定时 / IO 能跑 |
| `reg` 回调 | 调度循环里执行 | 回调返回前整台 Lua 调度被占住 | 其它任务都要等 |

Lua 回调 **不在** 硬件中断、也不在驱动线程里跑。

---

## 3. 阻塞与回调语义

**`uart.reg` 回调必须短。** 允许：`rt.mbox_send`、改几个本地变量。不要：

- `rt.delay` / `rt.wait` / `rt.mbox_recv`
- `uart.block`
- 长 `log`、拼大包、死循环

业务写回、解析放独立 `rt.task`。回调里抛错会被吞掉并记日志，这次包已经结束。

**`uart.block` 和 `rt.delay` 同类**：只挂起当前任务协程。必须在任务协程里调用（`main.lua` 顶层可以）。不要在 `reg` 回调里调用。

同一时刻 **整台脚本只能有一个** `block`。第二个会立刻 `false, "busy"`。

已经 `reg` 的口照样可以 `block`。等待期间该口到来的包 **只给这次 block，不进 `reg`**；等到或超时返回后，后续包再进回调。没有人在 `block` 时，包才进回调。

---

## 4. 常量与枚举

模块表只导出四个口编号。校验、流控、引脚组 **没有** 符号常量，配置里写数字。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `uart.UART0` | `0` | 第 0 路，内部调试口 | **不对外**。传入不会抛 `invalid uart id`，但收包进不了 Lua，配置文件也配不了 |
| `uart.UART1` | `1` | 第 1 路 | 业务 `id`；demo 常用 |
| `uart.UART2` | `2` | 第 2 路 | 同上；常和 SPI0 抢脚 |
| `uart.UART3` | `3` | 第 3 路 | 同上 |

业务请用 `1`～`3`。`id` 是整数但不在 `0`～`3` 时 **抛** `"invalid uart id"`（`unreg` 除外，越界只返回 `false`）。`0` 不抛，也不当可用口。

配置表里的数字含义（未挂到模块表，按下表写）：

| 字段 | 合法值 | 含义 |
| --- | --- | --- |
| `baudrate` | `1200`～`3000000` | 波特率 |
| `data_bits` | `7` 或 `8` | 数据位 |
| `stop_bits` | `1` 或 `2` | 停止位 |
| `parity` | `0` 无 / `1` 奇 / `2` 偶 | 校验 |
| `flow_control` | `0` 无 / `1` RTS/CTS | 硬件流控 |

未导出却拿去当枚举用的其它整数会在 `config` 里失败（范围文案见第 9 节）。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `id` | integer | 业务 `1`～`3` 或 `uart.UART1`…`UART3` |
| `cfg` | table | `config` 的第二参；键见 6.1 |
| `data`（写出） | string 或连续整数数组 | 非空。表必须是 `1..n` 无空洞，每项 `0`～`255` |
| `timeout_ms` | integer | `block` 第二参；省略 `1000`；负值当 `0` |
| `callback` | function | `function(id, data, meta)` |
| `meta` | table | 至少有整数 `at_check` |

本模块收发包都是 **原始字节串**。Lua 字符串可以含 `0x00`。没有布尔开关参数。

`config` 的字段只认数字：整数、浮点都会收成整数。布尔、字符串写在 `baudrate` 等键上会被忽略，该字段保持当前值。请写整数。

---

## 6. 模块函数

全部在模块表上。没有 userdata，没有冒号方法。

---

### 6.1 `uart.config(id, cfg)` {#6-1-config}

热改该口线参数，**立即重配硬件，不写 KV / 不改 `rtu_config.cfg`**。重启后回到配置文件（或出厂默认）。

```lua
uart.config(id, cfg)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | integer | 业务 `1`～`3` |
| `cfg` | 是 | table | 不是表则 **抛** `"cfg table required"` |

`cfg` 只认这些键（均可省略；省略则保留 **当前** 值。口尚未初始化则基准为 115200 8N1、无流控）：

| 键 | 说明 |
| --- | --- |
| `baudrate` | 见第 4 节 |
| `data_bits` | |
| `stop_bits` | |
| `parity` | |
| `flow_control` | |

**不认** `pin_map`、`max_packet_size`、`max_wait_ms`、`max_packets`。写了也无效。

成功 `true, "ok"`。范围非法 `false,` 对应文案。硬件重配失败 `false, "reconfig fail"`。

```lua
local ok, msg = uart.config(uart.UART1, {
    baudrate = 115200,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
```

---

### 6.2 `uart.get_config(id)` {#6-2-get-config}

读该口 **当前实时** 配置（含刚 `config` 过的）。

```lua
uart.get_config(id)
```

成功返回表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `baudrate` | integer | |
| `data_bits` | integer | |
| `stop_bits` | integer | |
| `parity` | integer | |
| `pin_map` | integer | 当前引脚组；**本模块改不了** |

读不到（口未就绪）只返回 `nil`，没有错误串。  
表里 **没有** `flow_control`，也没有分包三字段。

---

### 6.3 `uart.write(id, data)` {#6-3-write}

把一帧交给发送队列。成功只表示入队，**不等发送完毕**。

```lua
uart.write(id, data_string)
uart.write(id, byte_table)
```

| `data` | 发出去的内容 |
| --- | --- |
| string | 原始字节。可用 `\r\n`、`\x01\x02` |
| 连续数组 | `{0x01, 0x02, 0xAA}`，下标必须是 `1..#t`，每项整数 `0`～`255`。带字符串键、空洞、越界值 → 失败 |

成功 `true`。失败只返回 `false`（**没有**第二返回值）：空串、空表、不是字符串也不是合法字节表。

数字也会被当成字符串发出去：`uart.write(U, 65)` 发出的是字符 `"65"`（两个字节），不是 `0x41`。二进制请用 `\xHH` 或字节表。

常见写错：

| 写法 | 实际发出 |
| --- | --- |
| `"hello\r\n"` | 文本 + CR LF |
| `"\x01\x02\xAA\xFF"` | 四个二进制字节 |
| `"0x01 0x02"` | 字符 `0` `x` `0` `1`…，不是 hex |
| `{0x01, 0x02}` | 两个字节 |

```lua
uart.write(U, "hello UART1\r\n")
uart.write(U, "\x01\x02\xAA\xFF\r\n")
uart.write(U, {0x01, 0x02, 0xAA, 0xFF, 0x0D, 0x0A})
```

---

### 6.4 `uart.reg(id, callback)` {#6-4-reg}

登记该口在 **当前虚拟机** 上的收包回调。同一 VM、同一口重复 `reg` **换绑**，覆盖旧函数。

```lua
uart.reg(id, callback)
```

| 参数 | 必填 | 类型 |
| --- | --- | --- |
| `id` | 是 | integer |
| `callback` | 是 | function；不是函数则 **抛** 类型错 |

成功 `true`。须在 `rt` 调度上下文（主脚本即可）。没有上下文 **抛** `"rt vm context missing"`。整机回调槽满（16）**抛** `"uart reg full"`。

回调签名与约束见 [第 7 节](#7-收包回调协议)。

---

### 6.5 `uart.unreg(id)` {#6-5-unreg}

取消当前 VM 在该口上的回调。

```lua
uart.unreg(id)
```

有登记且拆掉：`true`。没有登记、id 非法、或没有 VM 上下文：`false`（不抛）。

虚拟机退出会清掉本 VM 全部 `reg`，不必依赖脚本 `unreg`。

---

### 6.6 `uart.block(id [, timeout_ms])` {#6-6-block}

阻塞等该口 **下一整包**。

```lua
uart.block(id)
uart.block(id, timeout_ms)
```

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | — | 业务 `1`～`3` |
| `timeout_ms` | 否 | `1000` | 毫秒。负数当 `0` |

| 情况 | 返回 |
| --- | --- |
| 等到一包 | `true, data`（二进制 string） |
| 超时 | `false, "timeout"` |
| 已有一个 block 在等 | `false, "busy"` |
| 等到了但载荷异常 | `true, nil`（少见） |

不在 `rt` 上下文：**抛** `"rt context not found"`。

```lua
uart.write(U, req)
local ok, pkt = uart.block(U, 5000)
if ok then
    -- 解析 pkt
else
    -- pkt 是 "timeout" 或 "busy"
end
```

---

## 7. 收包回调协议

### 7.1 签名

```lua
function(id, data, meta)
```

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `id` | integer | 哪一路，与 `reg` 时相同 |
| `data` | string | 这一包的原始字节，长度 ≥ 1 |
| `meta` | table | 见下 |

`meta.at_check`（integer）：

| 值 | 含义 |
| --- | --- |
| `0` | 本包已被 AT 解析匹配/拦截（或被解锁口逻辑当成已处理） |
| 非 `0` | 未被 AT 拦截 |

Lua **两种情况都会收到这包**。若这路还开着 AT 透传，脚本可按 `at_check==0` 决定是否忽略。做 Modbus / 自定义协议时请关掉该口透传（见第 1 节）。

### 7.2 执行位置

硬件收齐一包 → 队列 → **Lua 调度循环** 里 `pcall`。不是中断，通常也不是独立 task。

返回前整台调度被占住。回调抛错：记日志后吞掉。

---

## 8. 分包与配置落盘

收包路径（`reg` 与 `block` 同一套）：

1. 字节进接收缓存。
2. 攒满 `max_packet_size` **或** 最后一个字节后再空闲 `max_wait_ms` 没有新数据 → 结算成一包。
3. 待处理包超过 `max_packets`：新包丢掉。

这三项只在 `rtu_config.cfg` 的 `[uart.1]` / `[uart.2]` / `[uart.3]` 里配。写 `[uart.0]` 会被忽略。例如：

```ini
[uart.1]
baudrate=115200
data_bits=8
stop_bits=1
parity=0
max_packet_size=256
max_wait_ms=50
max_packets=4
```

产品侧大致范围（改配置时不要超）：

| 项 | 范围 | 说明 |
| --- | --- | --- |
| `max_packet_size` | 1～12288 | 单包上限，默认常见 2048 |
| `max_wait_ms` | 1～60000 | 空闲断包，默认常见 100 |
| `max_packets` | 1～64 | 邮箱深度，默认常见 8 |
| 单包 × 包数 | 须小于约 60KB | 超了配置不会按预期生效 |

`pin_map` 也在同一段。UART2 常见几组脚，其中一组和 SPI0 重叠。`uart.config` 改不了它；`get_config` 能读到当前组号。

开机波特率等以配置文件为准。`uart.config` 只改 RAM 里正在跑的线参数。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `config` | `true, "ok"` | `false, err`；id/`cfg` 类型不对则 **抛** |
| `get_config` | table | 读不到：单独 `nil`（无错误串）；id 非法 **抛** |
| `write` | `true` | 只 `false`（空数据、类型不对、或发送未接受）；id 非法 **抛** |
| `reg` | `true` | 槽满/无 rt：**抛** |
| `unreg` | `true` | 只 `false`（id 越界、无调度上下文、或该口未 `reg`） |
| `block` | `true, data` | `false, "timeout"` / `"busy"`；无 rt / id 非法 **抛** |

`id` 必须是整数。传入字符串、布尔等会先抛类型错，到不了下面的文案。

抛错摘要：

| 摘要 | 可能原因 |
| --- | --- |
| `invalid uart id` | `id` 是整数但不在 0～3。`unreg` 越界只返回 `false` 不抛。`0` 不抛，但不对外收包 |
| `cfg table required` | `config` 第二参不是表 |
| `uart reg init fail` | `reg` 时系统互斥量创建失败 |
| `rt vm context missing` | `reg` 时没有 `rt` 调度上下文（不在脚本 VM 里调） |
| `uart reg full` | 整机 16 个回调槽用尽（按「虚拟机 + 口」各一条） |
| `rt context not found` | `block` 时没有 `rt` 调度上下文 |

`config` 失败文案（`false, err`）：

| `err` | 可能原因 |
| --- | --- |
| `cfg is null` | 配置指针无效（正常脚本路径不应出现） |
| `baudrate out of range [1200,3000000]` | `baudrate` 小于 1200 或大于 3000000 |
| `data_bits out of range [7,8]` | `data_bits` 不是 7 或 8 |
| `stop_bits out of range [1,2]` | `stop_bits` 不是 1 或 2 |
| `parity out of range [0,2]` | `parity` 不是 0/1/2 |
| `flow_control out of range [0,1]` | `flow_control` 不是 0 或 1 |
| `reconfig fail` | 硬件没吃下这次重配（口未打开、驱动拒绝该组合） |
| `ok` | 成功时的第二返回值，不是错误 |

`block` 失败文案：

| `err` | 可能原因 |
| --- | --- |
| `timeout` | 在 `timeout_ms` 内没收到完整一包（对端没回、分包超时、或口接错） |
| `busy` | 同一脚本里已有一次 `block` 还在等，同时只能有 1 个 |

诊断：`uart reg full` 先 `unreg` 不用的口；`reconfig fail` 确认该口已在配置文件里启用；`busy` 不要并行两个 `block`；`write` 失败没有文案，先查数据是否空、是否传了既非 string 也非 byte 表。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 对外业务口 | **3**（UART1～UART3） | UART0 保留，收包不进 Lua |
| `reg` 槽 | **16** | 整机；按「虚拟机 + 口」各一条。满则抛 `uart reg full` |
| 同时 `block` | **1** | 每脚本 VM 一个；第二个 `busy` |
| 单包 / 邮箱 | 见第 8 节 | 配置文件 |

没有 userdata。回调挂在当前 VM 上，VM 退出会清。脚本应在不用时 `unreg`。

`write` 走发送队列，调用返回不代表线上已经发完。高速连发可能在底层排队或丢，取决于驱动队列深度（脚本侧没有单独的“发完”回调）。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 长期收包、旁路分发 | `reg` + 独立 task + `mbox`（`uart_normal`） |
| 一问一答、Modbus 轮询 | `write` + `block`（`uart_block` / `modbus_rs485`） |
| `reg` 期间再 `block` | 可以。`block` 截走那一口的下一包，返回后回调继续收 |
| 改波特率（本次运行） | `uart.config` |
| 改脚、改分包 | `rtu_config.cfg`，不是本模块 |
| 日志串口 | `sys.option("print_route")` / `"log_route"`，只能是 1/2/3，不能是 UART0 |
| 想用 UART0 | 不要。内部口，脚本当业务口收不到包 |
| 外挂 Flash 占 UART2 脚 | 换 `pin_map` 或换口 |

不要在回调里自己按字节拼包：底层已经按空闲超时切过了。`max_wait_ms` 太短会把一帧拆成多包。

---

## 12. 完整示例

回环：回调只投递，task 里写回。完整工程见 [examples/NT26/peripherals/uart/uart_normal](../../../../examples/NT26/peripherals/uart/uart_normal)。

```lua
local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")

local U = uart.UART1
local TOPIC = "uart1"

rtu.option("pass_up", false)
rtu.option("pass_down", false)

rt.task_start(function()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok and type(ev) == "table" and ev.data then
            uart.write(U, ev.data)
        end
    end
end)

local ok, msg = uart.config(U, {
    baudrate = 115200,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("config ok=%s msg=%s", tostring(ok), tostring(msg))

uart.reg(U, function(id, data, meta)
    rt.mbox_send(TOPIC, { id = id, data = data, at_check = meta.at_check })
end)

uart.write(U, "hello UART1\r\n")
```

一问一答：

```lua
uart.write(U, "Q1\r\n")
local ok, pkt = uart.block(U, 5000)
if ok then
    log.info("got %s", pkt)
else
    log.info("wait fail: %s", tostring(pkt))
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误文案/错误码与可能原因 |
