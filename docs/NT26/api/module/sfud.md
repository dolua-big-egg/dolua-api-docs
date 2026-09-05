# sfud

**文档版本** `1.1.0`

对象化的 **SPI NOR Flash** 驱动。用已初始化的 SPI 对象 + GPIO 片选认片，得到 Flash 对象后读、写、擦。FlashDB、LittleFS 都挂在这个对象上，不直接碰 SPI。

```lua
local sfud = require("sfud")
```

平台预加载模块，无需额外 `.lua` 文件。

和 [`flashdb`](flashdb.md) 的关系：`flashdb.kv` / `flashdb.ts` 的第一个参数必须是本模块 `bind` 成功的对象。同一颗芯片上可以再切分区给 LittleFS。先认片，再挂库。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `sfud.bind`](#6-1-bind)
- [7. 对象方法](#7-对象方法)
  - [7.1 `flash:read`](#7-1-read)
  - [7.2 `flash:write`](#7-2-write)
  - [7.3 `flash:erase`](#7-3-erase)
  - [7.4 `flash:erase_write`](#7-4-erase-write)
  - [7.5 `flash:capacity`](#7-5-capacity)
  - [7.6 `flash:erase_gran`](#7-6-erase-gran)
  - [7.7 `flash:jedec_id`](#7-7-jedec-id)
  - [7.8 `flash:name`](#7-8-name)
  - [7.9 `flash:unbind`](#7-9-unbind)
- [8. 写擦语义](#8-写擦语义)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

外挂 SPI NOR（常见 W25Q 系列）没有文件系统，只是一块按地址访问的芯片。本模块做三件事：

1. `sfud.bind(spi, name, cs [, opts])`：用总线和片选探测 JEDEC，初始化芯片。
2. 在返回的对象上 `read` / `write` / `erase` / `erase_write`，或查容量、擦除粒度。
3. 把这个对象交给 `flashdb` / `lfs` 当存储后端。

脚本不要自己拼 Flash 命令。CS 必须是 **GPIO 对象**控片选，不要指望 SPI 硬件 SSn 脚自动拉。

当前机型 SPI0 固定脚常和 UART2 重叠（MOSI/MISO/SCLK）。外挂盘工程通常要在 `rtu_config.cfg` 里改 `[uart.2] pin_map`。demo 用 GPIO8（模块 pin66）做 CS。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  spi 配好 + gpio CS → sfud.bind → 读写真擦 / 交给上层     │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  sfud 模块                                               │
│  · 认片、缓存容量 / 擦除粒度 / JEDEC                      │
│  · 按地址读写擦（单次最长 64KB）                          │
│  · 钉住 SPI、CS 对象，避免被提前回收                      │
└───────────────┬─────────────────────────┬───────────────┘
                │                         │
                ▼                         ▼
┌───────────────────────┐   ┌─────────────────────────────┐
│  直接 flash:read/write │   │  flashdb / lfs               │
│  裸地址访问            │   │  在分区上建 KV / 时序 / 文件 │
└───────────────────────┘   └─────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  SPI 总线 + GPIO 片选 → 外挂 NOR                          │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `bind` | 探测芯片、初始化 | **否** | 整条 Lua 引擎线程（认片可能数秒） |
| `read` / `write` / `erase` / `erase_write` | 同步总线传输 | **否** | 同上；大块擦会很久 |
| `flashdb` / `lfs` 挂载 | 经本对象访问芯片 | 见对应模块 | 上层决定同异步 |

`flashdb`、`lfs` 只认 **已经 `bind` 成功** 的对象。未初始化或已 `unbind` 会失败。

---

## 3. 对象模型

`bind` 返回 userdata。实例方法在对象元表上：

```lua
flash:read(addr, size)      -- 推荐
flash.read(flash, addr, size)  -- 等价
```

错误写法：`flash.read(addr, size)`（少了对象）、`sfud.capacity(flash)`（`capacity` 不在模块表）。

模块表上另有一套与对象同名的 IO 函数，第一参仍是 Flash 对象：

```lua
sfud.read(flash, addr, size)
sfud.write(flash, addr, data)
sfud.erase(flash, addr, size)
sfud.erase_write(flash, addr, data)
```

和 `flash:read` 等是同一套实现。查询类（`capacity` / `jedec_id` / `name` / `unbind`）只有冒号方法。

`bind` 会钉住传入的 SPI、CS 对象。脚本仍应把 `flash`（以及交给 `flashdb`/`lfs` 的引用）放在模块级或长生命周期 `local` 里。对象 `__gc` 等价于 `unbind`：芯片槽释放，上层库若还在用会坏。

`opts.cs_active_low` 只认 **布尔**。数字 `0` **不会**当成假（字段不是布尔就被忽略，保持默认低有效）。请写 `true` / `false`。

---

## 4. 常量与枚举

模块表 **没有** `lua_setfield` 整数常量。没有事件枚举。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `spi` | userdata | 已初始化的 SPI 对象 |
| `name` | string | 非空，最长 **31** 字节；整机唯一 |
| `cs` | userdata | 已 `gpio.open` 的片选脚，须先配成输出 |
| `opts` | table | 可选，见 `bind` |
| `addr` | integer | 芯片内字节地址，从 0 起 |
| `size` | integer | 读/擦长度，须 `> 0`，单次 ≤ **65536** |
| `data` | string | 写入的原始字节，长度须 `> 0`，单次 ≤ **65536** |
| `flash` | userdata | `bind` 成功返回的对象 |

---

## 6. 模块函数

---

### 6.1 `sfud.bind(spi, name, cs [, opts])` {#6-1-bind}

认片并占用一个设备槽。

```lua
sfud.bind(spi, name, cs)
sfud.bind(spi, name, cs, opts)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `spi` | 是 | SPI 对象 | 未初始化 → `"spi not initialized"` |
| `name` | 是 | string | 给这颗芯片起的名字，给 `flashdb`/`lfs` 当设备名 |
| `cs` | 是 | GPIO 对象 | 非法 → `"invalid cs gpio object"` |
| `opts` | 否 | table | 见下 |

`opts` 字段（均可省略）：

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `cs_active_low` | boolean | `true` | 只认布尔。`true` = 低有效（W25Q 常见） |
| `retry_times` | integer | `10000` | 总线重试次数；非整数则用默认 |
| `timeout_ms` | integer | `5000` | 单次操作超时（毫秒）；非整数则用默认 |

成功返回 Flash 对象。失败 `nil, err`。

同名已绑定 → `"flash name 'xxx' already bound"`。整机超过 **8** 颗 → `"too many flash devices, max 8"`。认片失败文案带原因，例如超时、找不到芯片。

```lua
local flash, err = sfud.bind(spi_dev, "flash0", cs_io, {
    cs_active_low = true,
    timeout_ms = 5000,
})
```

---

## 7. 对象方法

推荐 `flash:foo(...)`。`flash.foo(flash, ...)` 等价。

未 `bind` 成功或已 `unbind`：查询/IO 返回 `nil, "flash not initialized"`（写/擦类则是 `false` 语义，见各节）。

---

### 7.1 `flash:read(addr, size)` {#7-1-read}

按地址读原始字节。

```lua
flash:read(addr, size)
sfud.read(flash, addr, size)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `addr` | 是 | integer | 起始地址 |
| `size` | 是 | integer | 字节数，`1`～`65536` |

成功返回 string（长度等于 `size`）。失败 `nil, err`。`size == 0` → `"size must be > 0"`；过大 → `"size too large, max 65536 bytes"`。

---

### 7.2 `flash:write(addr, data)` {#7-2-write}

按地址编程。 **不会先擦。** NOR 只能把 1 写成 0，已写过的页通常要先 `erase` 或改用 `erase_write`。

```lua
flash:write(addr, data)
sfud.write(flash, addr, data)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `addr` | 是 | integer | 起始地址 |
| `data` | 是 | string | 非空，长度 ≤ 65536 |

成功 `true`。失败 `false, err`。空串 → `"data length must be > 0"`。

---

### 7.3 `flash:erase(addr, size)` {#7-3-erase}

擦一段。实际擦除会按芯片擦除粒度对齐扩大，可能比请求的区间更大。擦完是 `0xFF`。

```lua
flash:erase(addr, size)
sfud.erase(flash, addr, size)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `addr` | 是 | integer | 起始地址 |
| `size` | 是 | integer | 长度，`1`～`65536` |

成功 `true`。失败 `false, err`。`size == 0` 走与写相同的长度检查文案。

整片或数兆擦除不要用本接口循环 64KB 自己拼（可以，但会长时间占住 Lua）。上层 `flashdb`/`lfs` 挂载时的预擦在它们自己的路径里做。

---

### 7.4 `flash:erase_write(addr, data)` {#7-4-erase-write}

先擦覆盖区间，再写入 `data`。适合改一块已有内容。

```lua
flash:erase_write(addr, data)
sfud.erase_write(flash, addr, data)
```

参数与 `write` 相同。成功 `true`。失败 `false, err`。擦除仍按粒度对齐，可能伤及相邻数据。

---

### 7.5 `flash:capacity()` {#7-5-capacity}

芯片总容量（字节）。认片时读出，不是你传入的。

```lua
flash:capacity()
```

成功返回 integer。失败 `nil, "flash not initialized"`。

挂 `flashdb` / `lfs` 时用这个值和 `erase_gran()` 对齐分区，不要写死 16MB。

---

### 7.6 `flash:erase_gran()` {#7-6-erase-gran}

最小擦除粒度（字节），常见 `4096`。

```lua
flash:erase_gran()
```

成功 integer。分区 `offset`/`size` 应按它向下对齐。

---

### 7.7 `flash:jedec_id()` {#7-7-jedec-id}

厂商 / 型号 / 容量 ID，空格分隔的大写十六进制，例如 `"EF 40 18"`。

```lua
flash:jedec_id()
```

成功 string。用来确认接线是否认到预期芯片。

---

### 7.8 `flash:name()` {#7-8-name}

`bind` 时的名字。

```lua
flash:name()
```

成功 string。

---

### 7.9 `flash:unbind()` {#7-9-unbind}

释放设备槽和钉住的 SPI/CS 引用。之后这个对象上的 IO 都会报未初始化。

```lua
flash:unbind()
```

成功只返回 `true`。互斥量创建失败才 `false, "mutex init failed"`。重复 unbind 仍是 `true`。

仍有 `flashdb` / `lfs` 挂在这颗芯片上时 **不要** unbind。上层会钉住本对象，但显式 `unbind` 仍会拆槽，后续读写会坏。先丢掉库对象，再 unbind。

`__gc` 也会走释放路径。

---

## 8. 写擦语义

NOR Flash 不是 RAM：

1. 擦除粒度通常 4KB（以 `erase_gran()` 为准）。擦一块，块内旧数据全没。
2. `write` 只编程，不擦。往未擦过的地址写，结果不可靠。
3. `erase_write` 按粒度擦完再写，邻页若落在同一擦除块会被抹掉。
4. 单次 IO 上限 **64KB**。更大请自己切片。
5. 越界地址失败，文案含 `address out of bound`。

做键值、时序日志、文件，请用 [`flashdb`](flashdb.md) 或 LittleFS，不要自己在裸地址上模拟文件系统。

---

## 9. 错误与返回约定

缺参、类型不对：**抛** Lua 标准 `bad argument #n`。业务失败走返回值，不抛。

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `bind` | userdata | `nil, err` |
| `read` / `capacity` / `erase_gran` / `jedec_id` / `name` | 值 | `nil, err` |
| `write` / `erase` / `erase_write` | `true` | `false, err` |
| `unbind` | `true` | 仅互斥失败时 `false, err` |

**固定 `err`**

| `err` | 可能原因 |
| --- | --- |
| `mutex init failed` | 互斥锁创建失败（系统资源） |
| `invalid spi object` | 第一参不是 SPI 对象 |
| `spi not initialized` | SPI 对象还没初始化 |
| `invalid name, max 31 chars` | 名为空或超过 31 字符 |
| `invalid cs gpio object` | 第三参不是 GPIO 对象 |
| `flash name '<名>' already bound` | 同名已被占用（`<名>` 为你传入的名字） |
| `too many flash devices, max 8` | 整机已绑满 8 颗 |
| `flash not initialized` | 未 `bind`、已 `unbind`，或对象已失效 |
| `size must be > 0` | `read` 长度为 0 |
| `data length must be > 0` | `write` / `erase` / `erase_write` 长度为 0 |
| `size too large, max 65536 bytes` | `read` 单次超过 64 KB |
| `data too large, max 65536 bytes` | 写/擦单次超过 64 KB |
| `out of memory` | 读缓冲分配失败 |

**带原因与数字码的 `err`（格式固定）**

形如 `操作 failed: <原因> (<码>)`。`bind` 认片失败时操作为 `sfud_device_init`：

| 全文形态 | 可能原因 |
| --- | --- |
| `sfud_device_init failed: <原因> (<码>)` | 认片失败：接线、片选、SPI 脚冲突、芯片不支持、超时 |
| `read failed: <原因> (<码>)` | 读总线失败或地址越界 |
| `write failed: <原因> (<码>)` | 写失败（未擦除、写保护、越界、超时） |
| `erase failed: <原因> (<码>)` | 擦除失败 |
| `erase_write failed: <原因> (<码>)` | 先擦后写失败 |

`<原因>` 与 `<码>` 对照：

| 码 | `<原因>` | 可能原因 |
| --- | --- | --- |
| `1` | `not found` | 芯片型号未识别或不支持 |
| `2` | `write error` | 写周期失败、写保护、总线错误 |
| `3` | `read error` | 读周期失败、总线错误 |
| `4` | `timeout` | 等待芯片就绪超时（接线/供电/`timeout_ms` 过短） |
| `5` | `address out of bound` | 地址或长度超出芯片容量 |
| 其它 | `unknown error` | 未单独翻译的码 |

诊断：`already bound` 先 `unbind` 或换名；`not initialized` 检查是否还持有 `bind` 返回的对象；`address out of bound` 用 `capacity` 核对偏移。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 同时绑定的芯片 | **8** | 整机一份槽 |
| 设备名 | **31** 字节 | 且不可重名 |
| 单次读/写/擦 | **65536** 字节 | |
| 默认超时 | **5000** ms | `opts.timeout_ms` |
| 默认重试 | **10000** 次 | `opts.retry_times` |

没有回调。`bind` 钉住 SPI 与 CS。`flashdb`/`lfs` 再钉住本对象。虚拟机退出或 `__gc` 会拆槽。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 认片、看容量 / JEDEC | **`sfud.bind` + `capacity` / `jedec_id`** |
| 键值（重启还在） | 认片后 [`flashdb.kv`](flashdb.md) |
| 追加日志 / 队列 | 认片后 [`flashdb.ts`](flashdb.md) |
| POSIX 文件 | 认片后 [`lfs.mount`](lfs.md) |
| 同片混挂 | 一块 `sfud`，按 `erase_gran` 切不重叠分区 |
| 自己按页写固件 | `erase` + `write` 或 `erase_write` |

同一颗芯片不要两套 `bind` 抢同一 CS。

---

## 12. 完整示例

SPI0 + GPIO8 CS，认片后打印容量。完整外挂盘流程见 [examples/NT26/storage/flashdb_kv](../../../../examples/NT26/storage/flashdb_kv)（以及 [examples/NT26/storage/flashdb_ts](../../../../examples/NT26/storage/flashdb_ts)、[examples/NT26/storage/littlefs](../../../../examples/NT26/storage/littlefs)、[examples/NT26/storage/mix](../../../../examples/NT26/storage/mix)）。

```lua
local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local log = require("log")

local spi_dev = spi.new(spi.SPI0, {
    bus_hz = 24 * 1000000,
    data_bits = 8,
    frame_format = spi.CPOL0_CPHA0,
    work_mode = spi.WORK_MODE_FULL_DUPLEX,
})

local cs = gpio.open(gpio.INPUT_GPIO, 8)
assert(cs:config(true, true, gpio.PULL_UP))

local flash, err = sfud.bind(spi_dev, "flash0", cs, {
    cs_active_low = true,
    timeout_ms = 5000,
})
if not flash then
    log.info("bind fail: %s", tostring(err))
    return
end

log.info("name=%s cap=%s gran=%s id=%s",
    flash:name(), tostring(flash:capacity()),
    tostring(flash:erase_gran()), tostring(flash:jedec_id()))
```

把 `flash` 交给 FlashDB（分区须 ≥ 8KB，并按粒度对齐）：

```lua
local flashdb = require("flashdb")
local kv, ke = flashdb.kv(flash, {
    name = "demo_kv",
    offset = 0,
    size = flash:capacity() - (flash:capacity() % flash:erase_gran()),
    mount_timeout_ms = -1,
})
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部 `err` 文本、数字码与可能原因 |
