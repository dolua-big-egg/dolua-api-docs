# spi

**文档版本** `1.1.0`

对象化 SPI 主机。`spi.new` 打开一路控制器，之后在对象上发、收、全双工对传。每路控制器同一时刻只允许一个实例。

```lua
local spi = require("spi")
```

平台预加载模块，无需额外 `.lua` 文件。

命令和数据必须是 **字符串**（可含 `0x00`），不收字节表。

```lua
dev:transfer(string.char(0x9F, 0x00, 0x00, 0x00))
dev:transfer("\x9F\x00\x00\x00")   -- 等价
-- { 0x9F, 0x00 }                  -- 错
```

当前机型 **SPI0** 固定在 pin66～pin29 这一组，和 UART2 默认脚重叠。外挂 Flash / 自己摸总线时，通常要在 `rtu_config.cfg` 里把 UART2 挪开：`[uart.2] pin_map=1`。demo 片选用 GPIO8（模块 pin66）。

彩屏请用 [`lcd`](../module/lcd.md)，不要本模块再发屏命令。NOR 文件系统走 [`sfud`](../module/sfud.md)，片选用 GPIO 对象，不要和 `cs_gpio`+`set_cs` 两套一起抢同一脚。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `spi.new`](#6-1-new)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:send`](#7-1-send)
  - [7.2 `obj:recv`](#7-2-recv)
  - [7.3 `obj:transfer`](#7-3-transfer)
  - [7.4 `obj:set_cs`](#7-4-set-cs)
  - [7.5 `obj:get_status`](#7-5-get-status)
  - [7.6 `obj:get_bus_hz`](#7-6-get-bus-hz)
  - [7.7 `obj:id`](#7-7-id)
  - [7.8 `obj:deinit`](#7-8-deinit)
- [8. `new` 配置表](#8-new-配置表)
- [9. 时钟 `bus_hz`](#9-时钟-bus_hz)
- [10. 片选两种做法](#10-片选两种做法)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本侧流程：

1. `spi.new(spi.SPI0, cfg)` 打开控制器，得到对象。
2. 事务期间自己管片选（`set_cs` 或 GPIO），再 `send` / `recv` / `transfer`。
3. 不用时 `deinit`，或丢掉引用让回收拆掉，整机才能再 `new` 同一路。

两路控制器：`spi.SPI0`、`spi.SPI1`。SPI0 脚位见上；SPI1 按板级复用，文档不以 SPI0 那组脚去套。

`lcd.new` 若占用了同一路通用 SPI，再 `spi.new` 会失败（该路已在用）。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  spi.new → send / recv / transfer / set_cs               │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  spi 对象                                                │
│  · 每路控制器一个实例                                    │
│  · 请求 bus_hz → 落到偶数分频档                          │
│  · 收发同步等到完成或超时                                │
└────────────────────────────┬────────────────────────────┘
                             │
        MOSI / MISO / SCLK（固定复用脚）
        CS：配置表 cs_gpio，或脚本自己的 GPIO 对象
```

| 路径 | 当场做什么 | 是否占用 Lua 调度 |
| --- | --- | --- |
| `new` / `deinit` | 打开 / 释放控制器 | 短 |
| `send` / `recv` / `transfer` | **阻塞到传完或超时** | **是** |
| `set_cs` | 改片选脚电平 | 极短 |
| `get_bus_hz` / `get_status` / `id` | 查询 | 极短 |

没有本模块回调。大包会卡住其它协程，Flash 读写交给 sfud，不要在短回调里 `transfer` 整页。

---

## 3. 对象模型

```lua
local dev = spi.new(spi.SPI0, { bus_hz = 1000000 })
```

`new` 成功返回带元表的 userdata。方法必须通过该对象调用。

### 3.1 两种调用写法

```lua
dev:transfer(tx)           -- 推荐
dev.transfer(dev, tx)      -- 等价
```

下面这种会失败：

```lua
dev.transfer(tx)           -- 错误：缺对象
spi.transfer(dev, tx)      -- 错误：模块表上没有实例方法
```

### 3.2 布尔参数

两套规则，不要混：

| 参数 | 怎么传 | 数字 `0` |
| --- | --- | --- |
| `cfg.lsb_first`、`cs_gpio.enabled`、`cs_gpio.active_low` | 必须是 **boolean** | **被忽略**（保持默认），不会当成假 |
| `obj:set_cs(active)` | Lua 真假语义 | **`0` 为真**（片选有效） |

请写 `true` / `false`。不要写 `set_cs(0)` 指望释放片选，也不要用 `0`/`1` 填配置表里的布尔项。

`bus_hz`、`data_bits`、`frame_format`、`work_mode`、`timeout_ms`、`gpio` / `pin_no` / `pull_mode` 走 **整数**。

### 3.3 引用必须保住

对象被回收会自动 `deinit`，控制器空出来。挂 Flash 时把 `spi` 对象放在模块表或全局里，和 CS GPIO、sfud 对象一起拿住。

```lua
M._hold = { spi = dev }    -- 对
-- local 临时变量出函数就可能被回收
```

---

## 4. 常量与枚举

### 4.1 控制器

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `spi.SPI0` | `0` | 第 0 路 | `new` 的 `spi_id` |
| `spi.SPI1` | `1` | 第 1 路 | 同上 |

其它整数 `new` 失败：`invalid spi_id …`。

### 4.2 工作模式

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `spi.WORK_MODE_TX_ONLY` | `0` | 只发，不配 MISO | `cfg.work_mode` |
| `spi.WORK_MODE_FULL_DUPLEX` | `1` | 全双工（默认） | 同上 |

`TX_ONLY` 下 `recv` / `transfer` 失败，文案含 `not allowed in TX_ONLY mode`。刷屏只写可用 TX_ONLY；读 Flash 必须全双工。

未挂到模块的其它工作模式不要当可用值传入。

### 4.3 时钟相位（`frame_format`）

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `spi.CPOL0_CPHA0` | `0` | CPOL=0 CPHA=0（默认，NOR 常用） |
| `spi.CPOL0_CPHA1` | `256` | CPOL=0 CPHA=1 |
| `spi.CPOL1_CPHA0` | `512` | CPOL=1 CPHA=0 |
| `spi.CPOL1_CPHA1` | `768` | CPOL=1 CPHA=1 |

底层还有 TI / Microwire 帧格式，**没有**挂到模块表，不要当 `spi.xxx` 用。

### 4.4 片选上下拉（`cs_gpio.pull_mode`）

与 [`gpio`](gpio.md) 同一套数值，符号在 `spi` 表上也有一份：

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `spi.PULL_AUTO` | `0` | 由复用自动控制 |
| `spi.PULL_UP` | `1` | 内部上拉（`cs_gpio` 默认） |
| `spi.PULL_DOWN` | `2` | 内部下拉 |

低有效 CS 建议 `PULL_UP`。

### 4.5 超时

| 符号 | 值 | 含义 | 用在 |
| --- | --- | --- | --- |
| `spi.TIMEOUT_FOREVER` | `4294967295` | 一直等到传完 | `send` / `recv` / `transfer` 的 `timeout_ms` |

省略超时时默认 **1000** ms，不是无限等。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `spi_id` | integer | `spi.SPI0` / `SPI1` |
| `cfg` | table | 见 [第 8 节](#8-new-配置表) |
| `tx` | string | 非空；可二进制 |
| `len` | integer | `recv` 字节数，必须 `> 0` |
| `timeout_ms` | integer | 默认 `1000`；可用 `TIMEOUT_FOREVER` |
| `active` | boolean | `set_cs`：片选是否有效 |

---

## 6. 模块函数

---

### 6.1 `spi.new(spi_id[, cfg])` {#6-1-new}

打开一路控制器并完成初始化。

**调用模式**

```lua
spi.new(spi_id)
spi.new(spi_id, cfg)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `spi_id` | 是 | `spi.SPI0` 或 `spi.SPI1` |
| `cfg` | 否 | 配置表；省略则用第 8 节默认值 |

成功：spi 对象。失败：`nil, err`（不抛业务错）。

| `err` 摘要 | 原因 |
| --- | --- |
| `invalid spi_id …` | 不是 0/1 |
| `spi0 already in use` / `spi1 already in use` | 该路已有实例（含 lcd 占用） |
| `bus_hz must be > 0` | 显式写成了 `0` |
| `mutex init failed` | 锁创建失败 |
| `spi0 init failed: … (n)` | 硬件初始化失败，后缀见第 11 节 |

`id` 类型不对会 **抛**（整数检查）。

```lua
local dev, err = spi.new(spi.SPI0, {
    bus_hz = 1 * 1000000,
    frame_format = spi.CPOL0_CPHA0,
    work_mode = spi.WORK_MODE_FULL_DUPLEX,
})
```

---

## 7. 对象方法

---

### 7.1 `obj:send(tx[, timeout_ms])` {#7-1-send}

只发，不读回。片选要自己包住整段事务。

**调用模式**

```lua
obj:send(tx)
obj:send(tx, timeout_ms)
```

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `tx` | 是 |  | 非空 string |
| `timeout_ms` | 否 | `1000` | 毫秒 |

成功：`true`。失败：`false, err`。

未初始化或空 `tx`：`spi not initialized or empty tx data`。

```lua
obj:set_cs(true)
obj:send("\x9F")
obj:set_cs(false)
```

---

### 7.2 `obj:recv(len[, timeout_ms])` {#7-2-recv}

只收 `len` 字节（控制器打时钟，MOSI 填默认字节）。

**调用模式**

```lua
obj:recv(len)
obj:recv(len, timeout_ms)
```

成功：string（长度即 `len`）。失败：`nil, err`。

`TX_ONLY`、未初始化、`len == 0` 会失败。

```lua
obj:set_cs(true)
obj:send("\x9F")
local id = obj:recv(3)
obj:set_cs(false)
```

---

### 7.3 `obj:transfer(tx[, timeout_ms])` {#7-3-transfer}

全双工，发出 `tx` 的同时收回等长数据。

**调用模式**

```lua
obj:transfer(tx)
obj:transfer(tx, timeout_ms)
```

成功：string，长度等于 `#tx`。失败：`nil, err`。`TX_ONLY` 不可用。

读 JEDEC 时第 1 个收回字节通常是命令拍上的空位，ID 从第 2 字节起。

```lua
local rx = obj:transfer(string.char(0x9F, 0x00, 0x00, 0x00))
-- rx:byte(2), rx:byte(3), rx:byte(4) 才是厂商/类型/容量
```

---

### 7.4 `obj:set_cs(active)` {#7-4-set-cs}

按 `new` 时的 `cs_gpio` 拉片选。`active == true` 表示 **片选有效**（`active_low == true` 时脚为低）。

**调用模式**

```lua
obj:set_cs(true)
obj:set_cs(false)
```

必须 `cs_gpio.enabled == true`，否则失败 `set_cs failed: invalid state`。sfud 那条路径不要调这个，改用 GPIO 对象。

成功：`true`。失败：`false, err`。未初始化：`spi not initialized`。

`active` 走真假语义：**不要传数字 `0`**。

---

### 7.5 `obj:get_status()` {#7-5-get-status}

**调用模式**

```lua
obj:get_status()
```

成功：表。失败：`nil, err`。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `busy` | boolean | 控制器忙 |
| `data_lost` | integer | 数据丢失标志 |
| `mode_fault` | integer | 模式错误标志 |
| `spi_id` | integer | `0` 或 `1` |

---

### 7.6 `obj:get_bus_hz()` {#7-6-get-bus-hz}

分频后 **实际生效** 的 SCLK（Hz），不是 `new` 时写入的请求值。

**调用模式**

```lua
obj:get_bus_hz()
```

成功：integer。失败：`nil, err`。

---

### 7.7 `obj:id()` {#7-7-id}

**调用模式**

```lua
obj:id()
```

返回打开时的控制器号（`0` / `1`）。未 `deinit` 也可查。无失败返回。

---

### 7.8 `obj:deinit()` {#7-8-deinit}

释放控制器。成功后本对象不能再收发；该路可以再次 `new`。

**调用模式**

```lua
obj:deinit()
```

成功：`true`。已释放再调也当成功。失败：`false, err`。

对象回收时会自动走同一套释放。

---

## 8. `new` 配置表

全部可选。缺省：

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `bus_hz` | `1000000` | 请求 SCLK（Hz），必须是整数且 `> 0` |
| `data_bits` | `8` | 每帧位宽，硬件支持 **4～16** |
| `frame_format` | `spi.CPOL0_CPHA0` | 见第 4.3 节 |
| `lsb_first` | `false` | 须 boolean |
| `work_mode` | `spi.WORK_MODE_FULL_DUPLEX` | 见第 4.2 节 |
| `cs_gpio` | 不启用 | 子表，见下 |

`cs_gpio` 子表（整表省略 = 不走 `set_cs`）：

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `enabled` | `false` | 须 boolean；`true` 才接管片选 |
| `gpio` | — | 芯片 GPIO 编号（如 `8`）。一旦是整数，按 GPIO 编号，忽略脚序号 |
| `pin_no` | `0` | 模块对外脚序号；仅当没写 `gpio` 时用 |
| `active_low` | `true` | 须 boolean |
| `pull_mode` | `spi.PULL_UP` | `PULL_*` |

`gpio` 与 [`gpio.open(gpio.INPUT_GPIO, n)`](gpio.md) 的编号同一套。demo 用 `gpio = 8`，不要和 `pin_no = 66` 混填两套。

---

## 9. 时钟 `bus_hz`

写入的是 **请求值**，控制器按偶数分频就近落到档位。以 `get_bus_hz()` 为准。

未抬功能时钟时，常见上限约 **13 MHz**；写 24M/48M 也会落到约 13M。请求较高时功能时钟会切到更快源，例如：

| 请求 | 大约落到 |
| --- | --- |
| 1 MHz | 接近 1 M（杜邦线调试常用） |
| 13 MHz | 约 12.75～13.3 M |
| 24 MHz | 约 23.5 M |
| 48 MHz | 约 51 M |
| 80 MHz | 约 76.5 M |

外挂 NOR 还受芯片命令上限和布线限制（普通读常 ≤50 M）。先 1 M 把 JEDEC 跑通，再往上加。

---

## 10. 片选两种做法

| 做法 | 配置 | 谁拉 CS | 适用 |
| --- | --- | --- | --- |
| 交给 spi 对象 | `cs_gpio.enabled = true` | `obj:set_cs(true/false)` | `spi_api`、自己拼命令、ST7789 demo |
| 交给 GPIO 对象 | `new` 时不要 `cs_gpio` | `gpio.open` + `sfud.bind(..., cs_io)` | LittleFS / FlashDB |

同一脚不要两套同时配。sfud 要求 CS 是 GPIO 对象。

SPI 硬件 SSn 复用脚（SPI0 上常是 GPIO8 那根）若改成 GPIO 片选，就按 GPIO 用，不要指望控制器自动拉 SSn。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `spi.new` | userdata | `nil, err` |
| `send` / `set_cs` / `deinit` | `true` | `false, err` |
| `recv` / `transfer` / `get_status` / `get_bus_hz` | 值 | `nil, err` |
| `id` | integer | — |

缺对象、`tx` 不是 string、`len` 不是整数等会 **抛**标准 Lua 参数错，需要 `pcall` 才能收。业务失败用返回值，请判断 `if not dev then`。

硬件失败文案形如 `"send failed: timeout (-3)"`，括号里的整数：

| 码 | 文案片段 | 可能原因 |
| --- | --- | --- |
| `-1` | `invalid parameter` | 控制器编号、缓冲区、长度或配置非法 |
| `-2` | `invalid state` | 控制器未初始化、已 `deinit`、或当前状态不允许这次传输 |
| `-3` | `timeout` | 传输在 `timeout_ms` 内没完成：从设备没拉时钟、接线、或超时太短 |
| `-4` | `driver error` | 控制器硬件/驱动报错（脚冲突、时钟切不过、总线故障） |
| `-5` | `unsupported spi controller` | 该编号的控制器本机没有或未启用 |
| 其它 | `unknown error` | 未单独翻译的码 |

固定 `err` 文本：

| `err` | 可能原因 |
| --- | --- |
| `invalid spi_id N, expect spi.SPI0(0) or spi.SPI1(1)` | `new` 的第一参不是 `0`/`1`（`N` 是你传入的整数） |
| `mutex init failed` | `new`/`deinit` 时系统互斥量失败 |
| `spi0 already in use` / `spi1 already in use` | 该路已有实例未 `deinit`（非法 id 时可能看到 `spi? already in use`） |
| `bus_hz must be > 0` | 配置表把 `bus_hz` 写成了 0，或没写且解析结果为 0 |
| `spi0 init failed: … (N)` / `spi1 init failed: … (N)` | 控制器初始化失败；`…` 与 `N` 见上表 |
| `deinit failed: … (N)` | 关控制器失败 |
| `spi not initialized or empty tx data` | 对象已 `deinit`，或 `send`/`transfer` 的 `tx` 是空串 |
| `spi not initialized or invalid length` | 对象已 `deinit`，或 `recv` 的长度为 0 |
| `spi not initialized` | `set_cs` / `get_status` / `get_bus_hz` 时对象已关 |
| `recv not allowed in TX_ONLY mode` | `work_mode` 是只发，却调了 `recv` |
| `transfer not allowed in TX_ONLY mode` | 只发模式却调了 `transfer` |
| `send failed: … (N)` | 发送失败 |
| `recv failed: … (N)` | 接收失败 |
| `transfer failed: … (N)` | 全双工对传失败 |
| `set_cs failed: … (N)` | 软件片选失败（没配 `cs_gpio`、脚已被占用、或控制器未就绪） |
| `get_status failed: … (N)` | 读控制器状态失败 |
| `get_bus_hz failed: … (N)` | 读实际分频时钟失败 |

诊断：`already in use` 先 `deinit` 或不要对同一路 `new` 两次；`TX_ONLY` 只用 `send`；`timeout (-3)` 查从设备与 `timeout_ms`；`bus_hz must be > 0` 写明确的正整数 Hz。

---

## 12. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 控制器 | **2**（SPI0 / SPI1），每路 **1** 个实例 |
| `data_bits` | 4～16 |
| 默认超时 | 1000 ms |

`deinit`、对象回收、虚拟机退出都会放掉该路。与 [`lcd`](../module/lcd.md) 共用同一路通用 SPI 时，先 `lcd` 对象 `deinit` 再 `spi.new`，或反过来。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| 摸总线、读 JEDEC | 本模块 `set_cs` + `transfer`，[examples/NT26/peripherals/spi/spi_api](../../../../examples/NT26/peripherals/spi/spi_api) |
| 外挂 NOR + 文件系统 | [`sfud.bind`](../module/sfud.md)，不要本模块发 03h/02h |
| 彩屏 | [`lcd`](../module/lcd.md)；本仓库 [examples/NT26/peripherals/spi/spi_st7789](../../../../examples/NT26/peripherals/spi/spi_st7789) 是手搓屏命令的参考 |
| 只发不收（刷像素） | `WORK_MODE_TX_ONLY` + `send` |

---

## 14. 完整示例

SPI0 + GPIO8 片选，读 JEDEC（与 `spi_api` demo 同类）。先确认 `rtu_config.cfg` 里 `[uart.2] pin_map=1`。

```lua
local rt = require("rt")
local log = require("log")
local spi = require("spi")

local dev, err = spi.new(spi.SPI0, {
    bus_hz = 1 * 1000000,
    data_bits = 8,
    frame_format = spi.CPOL0_CPHA0,
    work_mode = spi.WORK_MODE_FULL_DUPLEX,
    cs_gpio = {
        enabled = true,
        gpio = 8,
        active_low = true,
        pull_mode = spi.PULL_UP,
    },
})
if not dev then
    log.error("spi.new %s", tostring(err))
    return
end

log.info("id=%s actual_hz=%s", dev:id(), tostring(dev:get_bus_hz()))

dev:set_cs(true)
local rx, te = dev:transfer(string.char(0x9F, 0x00, 0x00, 0x00))
dev:set_cs(false)

if rx and #rx >= 4 then
    log.info("JEDEC %02X %02X %02X", rx:byte(2), rx:byte(3), rx:byte(4))
else
    log.error("transfer %s", tostring(te))
end

while true do
    rt.delay(10000)
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误文案/错误码与可能原因 |
