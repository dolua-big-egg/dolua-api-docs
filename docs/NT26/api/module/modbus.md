# modbus

**文档版本** `1.1.0`

纯函数。从一帧二进制里按规则抠数，以及算 / 校验 Modbus RTU 的 CRC16。没有对象、没有主从状态机、不发串口。

```lua
local modbus = require("modbus")
```

平台预加载模块，无需额外 `.lua` 文件。

组包、粘包、真正的 485 收发分别看 [`framekit`](framekit.md)、[`uart`](../peripherals/uart.md)。本模块只处理**已经拿到的一整段字节**。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `modbus.analyze`](#6-1-analyze)
  - [6.2 `modbus.crc`](#6-2-crc)
- [7. 数据怎么写](#7-数据怎么写)
- [8. `analyze` 规则](#8-analyze-规则)
- [9. 字节序](#9-字节序)
- [10. CRC16](#10-crc16)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

两个函数：

1. `modbus.analyze(data, rules)`：按每条规则从 `data` 切一段字节，解成 number，按规则顺序放进返回表。
2. `modbus.crc(data, "gen"|"check")`：对载荷生成 2 字节 CRC，或把整段当完整报文校验末尾两字节。

不识别从站地址、功能码、异常应答。规则从第几个字节抠、抠几种类型，全部由脚本写死。接到仪表后先对照手册确认寄存器布局和 float 的字序，再写规则。

模拟帧、不碰串口：[examples/NT26/module/modbus/modbus_api](../../../../examples/NT26/module/modbus/modbus_api)。UART 一问一答：`modbus_rs485`。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  uart / framekit 拿到一整包 → analyze / crc              │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  modbus 模块                                             │
│  · analyze：按规则切字节、换序、解成 number              │
│  · crc：RTU CRC16 生成或校验                             │
│  · 无实例、无回调、不占总线                              │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `analyze` | 整段拷入、逐条规则解析 | **否** |
| `crc` | 对整段算 CRC16 | **否** |

没有后台任务。收发仍走 UART：`write` + `block` 或 `reg`。

---

## 3. 阻塞语义

同步 CPU 转换。短帧可在回调里用；不要在 UART / MQTT 短回调里对很长的表做 `analyze`。真正等仪表应答用 [`uart.block`](../peripherals/uart.md)，不要在本模块里空转。

---

## 4. 常量与枚举

模块表 **没有** 挂常量（没有 `modbus.UINT16` 这种符号）。`analyze` 的类型、字节序都写整数；`crc` 的模式写字符串 `"gen"` / `"check"`。

### 4.1 数据类型（规则第 3 项 `mode`）

`len` 必须和类型占用字节数一致，否则整次 `analyze` 失败（`nil`）。

| 值 | 含义 | 必须的 `len` |
| --- | --- | --- |
| `1` | UINT8 | `1` |
| `2` | INT8（有符号） | `1` |
| `3` | UINT16 | `2` |
| `4` | INT16 | `2` |
| `5` | UINT32 | `4` |
| `6` | INT32 | `4` |
| `7` | UINT64 | `8` |
| `8` | INT64 | `8` |
| `9` | FLOAT32（IEEE754 单精度） | `4` |

没有 FLOAT64。`mode` 不在 `1`～`9`：规则失败。

解出来一律是 Lua **number**（浮点）。整数请用 `%.0f` 打日志，不要用 `%d`。UINT64 / INT64 先变成双精度，大于 2^53 的整数会丢精度。

### 4.2 字节序（规则第 4 项 `endian`）

| 值 | 习惯叫法 | 4 字节 `ABCD` 变成 |
| --- | --- | --- |
| `0` | 小端 | `ABCD`（不换） |
| `1` | 大端 | `DCBA` |
| `2` | 小端交换 / BADC | `BADC` |
| `3` | 大端交换 / CDAB | `CDAB` |

2 字节、8 字节的具体变换见 [第 9 节](#9-字节序)。`endian` 不在 `0`～`3`：规则失败。

Modbus 寄存器默认大端，规则里写 `1`。部分仪表的 float 是 CDAB（`3`）。解出来乱跳时先改这一项。

### 4.3 CRC 模式（`crc` 第二参）

| 值 | 含义 |
| --- | --- |
| `"gen"` | 对**整段** `data` 生成 CRC（`data` 不要含已有 CRC） |
| `"check"` | `data` 是完整报文，校验**最后两字节** |

其它字符串：`false, "mode need gen/check"`。必须是 string，数字 `0` 不行。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `data` | string 或连续字节表 | 见 [第 7 节](#7-数据怎么写) |
| `rules` | table | 数组，每项 4 个数字 |
| `mode`（crc） | string | `"gen"` 或 `"check"` |
| `vals` | table | `analyze` 成功：`vals[i]` 对应 `rules[i]` |
| `ok` | boolean | `crc` 第一返回值 |
| `result` / `err` | string 或 nil | `crc` 第二返回值 |

`analyze` 的字节表元素走 **number**（`10.0` 能用）。`crc` 的字节表元素必须是 **整数**（Lua 5.3 下 `10.0` 可能失败）。统一写 `0x01` 这种整数最省事。

---

## 6. 模块函数

---

### 6.1 `modbus.analyze(data, rules)` {#6-1-analyze}

按 `rules` 逐条从 `data` 取值。

**调用模式**

```lua
modbus.analyze(data, rules)
```

必须恰好 2 个参数。`data` 是二进制 string 或字节表，`rules` 是规则数组。

成功：结果表，下标从 1 起，与规则一一对应。任一条规则失败：**整个**返回 `nil`（没有第二返回值、没有部分结果）。

用法错（参数个数、类型、空数据、空规则、字节不是 0～255）**抛错**，不是 `nil`。

`lua_isstring` 对数字为真：`analyze(123, rules)` 会把 `123` 当成三个字符的文本 `"123"`，不是三个字节。请传二进制 string 或表。

```lua
local rules = {
    {4, 2, 3, 1}, -- 从第 4 字节起，2 字节 UINT16 大端
    {6, 4, 9, 1}, -- 从第 6 字节起，4 字节 FLOAT32 大端
}
local vals = modbus.analyze(pkt, rules)
if vals == nil then
    -- 规则越界、len 和类型不配、某条不是 4 元组
else
    -- vals[1]、vals[2] 是 number
end
```

---

### 6.2 `modbus.crc(data, mode)` {#6-2-crc}

**调用模式**

```lua
modbus.crc(data, "gen")
modbus.crc(data, "check")
```

必须恰好 2 个参数。失败风格与 `analyze` 不同：**不抛业务错**，一律 `false, reason`。

`"gen"`：对整段 `data` 算 CRC16。成功 `true, crc`，`crc` 是 **2 字节 string**，低字节在前，可直接拼：

```lua
local ok, crc = modbus.crc(payload, "gen")
local frame = payload .. crc
```

`"check"`：把 `data` 当完整帧。前面字节算出的 CRC 与最后两字节比较。

- 符合：只返回 `true`（没有第二值）。
- 不符：`false, "crc mismatch"`。
- 短于 3 字节：`false, "too short"`（至少 1 字节载荷 + 2 字节 CRC）。

`data` 写法与 `analyze` 相同（string 或连续字节表），但更严：必须是真正的 string 类型或表，数字会被拒。最长 **256** 字节。

```lua
local ok, err = modbus.crc(frame, "check")
if ok then
    -- 末两字节是合法 CRC
else
    -- err 可能是 "crc mismatch" / "too short" / "empty data" / ...
end
```

---

## 7. 数据怎么写

两种入参等价，下标都从 1 计。

**连续字节表**

```lua
{ 0x01, 0x03, 0x06, 0x00, 0x7B }
```

必须是数组部分连续。空洞、字符串键不计入长度。每个元素 `0`～`255`。

**二进制 string**

```lua
"\x01\x03\x06\x00\x7B"
```

`\x` 后两位十六进制是一个字节。不要传 `"01 03 06"` 这种 ASCII 文本，也不要先 `hex.bytes2hex` 再拿去 `analyze`。

空表、空串：`analyze` 抛 `"empty data array"` / `"empty data string"`；`crc` 返回 `false, "empty data"`。

---

## 8. `analyze` 规则

`rules` 是数组，每条必须是 **恰好 4 个数字** 的表：

```lua
{ start, len, mode, endian }
```

| 项 | 含义 |
| --- | --- |
| `start` | 从 1 开始的字节下标（Lua 习惯，不是 0） |
| `len` | 取几个字节，且必须等于该 `mode` 的宽度 |
| `mode` | 见 [4.1](#41-数据类型规则第-3-项-mode) |
| `endian` | 见 [4.2](#42-字节序规则第-4-项-endian) |

`start + len - 1` 不能超出 `data` 长度。`len` 范围 `1`～`8`。

多条规则互不影响，可以重叠、可以跳过中间字节（例如跳过从站、功能码、CRC）。

任一条不是 4 元组、越界、类型和长度不配：整次返回 `nil`。失败原因只打到设备日志，Lua 侧看不到字符串。

典型 03 读保持寄存器应答：

```
下标   1     2     3  |  4 …     |  …     | 末两字节
含义  从站  功能  字节数 |  寄存器数据      |  CRC
```

数据从第 **4** 字节开始。demo 那帧：

```lua
-- 01 03 06 00 7B 41 CC 00 00 11 7C
{ {4, 2, 3, 1}, {6, 4, 9, 1} }   -- 123 和 25.5
```

本模块不替你核对「字节数」字段是否等于后面数据长度，也不跳过 CRC；CRC 要另外 `crc(..., "check")`。

---

## 9. 字节序

先按 `endian` 重排切出来的字节，再按本机小端拼成整数 / float。表里的 `ABCD` 是 **线上从左到右** 的原始顺序。

**2 字节（UINT16 / INT16）**

| `endian` | 变换 |
| --- | --- |
| `0` | 不换 |
| `1` / `2` / `3` | 两字节对调（效果相同） |

**4 字节（UINT32 / INT32 / FLOAT32）**

| `endian` | `A B C D` → |
| --- | --- |
| `0` | `A B C D` |
| `1` | `D C B A` |
| `2` | `B A D C`（BADC） |
| `3` | `C D A B`（CDAB） |

**8 字节（UINT64 / INT64）**

| `endian` | `A B C D E F G H` → |
| --- | --- |
| `0` | 不换 |
| `1` | 完全反转 |
| `2` | 每对字节对调：`B A D C F E H G` |
| `3` | 前后 4 字节对调：`E F G H A B C D` |

1 字节类型不受字节序影响，但 `endian` 仍必须写 `0`～`3`。

---

## 10. CRC16

算法就是 Modbus RTU 那套：初值 `0xFFFF`，多项式 `0xA001`（反转后的 `0x8005`），结果 **低字节在前**。

`"gen"` 只对你传入的整段计算，**不会自动跳过**末尾。要对载荷生成 CRC，传入的必须是不含 CRC 的前缀。

`"check"` 固定认为最后两字节是 CRC、前面是载荷。自己拼的帧如果 CRC 不在末尾，不要用 `check`。

与 [`framekit`](framekit.md) 里 `"crc16_modbus"` + `"endian":"little"` 是同一类算法；拆包仍用 framekit，本模块的 `crc` 适合脚本里手组一帧或抽查。

上限 256 字节（含 CRC）。更长：`false, "data too long"`。

---

## 11. 错误与返回约定

| 接口 | 成功 | 用法错 | 规则 / 校验失败 |
| --- | --- | --- | --- |
| `analyze` | 结果表 | **抛** | `nil`（无 `err`：规则对不上数据） |
| `crc` `"gen"` | `true,` 2 字节串 | `false, reason` | — |
| `crc` `"check"` | `true` | `false, reason` | `false, "crc mismatch"` |

`pcall` 只包得住 `analyze` 的抛错；`crc` 不用 `pcall`。没有数字业务码。

**`analyze` 抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `need data+rule` | 不是恰好 2 个参数 |
| `rule must table` | 第二参不是表 |
| `data must str/table` | 第一参既不是 string 也不是表 |
| `empty data string` | 数据串长度为 0 |
| `empty data array` | 数据表长度为 0 |
| `data[N] not number` | 表里第 `N` 项不是数字（`N` 从 1 计） |
| `data[N] need 0-255` | 第 `N` 项超出单字节 |
| `rule table empty` | 规则表长度为 0 |
| `alloc data fail` | 拷贝数据表时分配失败（极少） |

**`crc` 返回的 `reason`**

| `reason` | 可能原因 |
| --- | --- |
| `need data+mode` | 不是恰好 2 个参数 |
| `mode must string` | 第二参不是 string |
| `mode need gen/check` | 不是 `"gen"` / `"check"` |
| `data must str/table` | 第一参类型不对 |
| `empty data` | 空串或空表 |
| `data too long` | 超过 256 字节 |
| `data item not integer` | 表元素不是整数 |
| `data item need 0-255` | 表元素超出单字节 |
| `too short` | `"check"` 时短于 3 字节（载荷+CRC） |
| `crc mismatch` | 末两字节与载荷算出来的 CRC 对不上 |

---

## 12. 资源上限与生命周期

| 项 | 上限 / 说明 |
| --- | --- |
| 实例 | 无 userdata |
| `analyze` 单字段 | 最多 8 字节 |
| `crc` 整段 | 最多 256 字节 |
| 规则条数 | 无单独上限，受 Lua 内存和调用时间限制 |
| 回调 | 无 |

没有需要持有的对象。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| 从应答里抠寄存器 / float | `analyze` |
| 组请求、校验应答 CRC | `crc("gen")` / `crc("check")` |
| 串口一问一答 | [`uart.write`](../peripherals/uart.md) + `uart.block`，见 [examples/NT26/module/modbus/modbus_rs485](../../../../examples/NT26/module/modbus/modbus_rs485) |
| 粘包 / 按 CRC 切帧 | [`framekit`](framekit.md)，算法用 `crc16_modbus` |
| 当 hex 文本打印 | [`hex`](hex.md)，不要把 hex 文本直接喂给 `analyze` |
| 完整 Modbus 主站（超时重试、多从站队列） | **没有。** 自己用 UART 轮询 |

---

## 14. 完整示例

与 [examples/NT26/module/modbus/modbus_api](../../../../examples/NT26/module/modbus/modbus_api) 同一帧：

```lua
local modbus = require("modbus")

-- 01 03 06 00 7B 41 CC 00 00 11 7C
local raw = "\x01\x03\x06\x00\x7B\x41\xCC\x00\x00\x11\x7C"
local payload = "\x01\x03\x06\x00\x7B\x41\xCC\x00\x00"
local rules = {
    {4, 2, 3, 1}, -- UINT16 大端 = 123
    {6, 4, 9, 1}, -- FLOAT32 大端 = 25.5
}

local vals = modbus.analyze(raw, rules)
-- vals[1] == 123，vals[2] == 25.5（均为 float number）

local ok, crc = modbus.crc(payload, "gen")
-- ok == true；crc 两字节为 0x11、0x7C；payload .. crc == raw

local good = modbus.crc(raw, "check")          -- true
local bad, why = modbus.crc(payload, "check") -- 太短或 mismatch
```

UART 轮询骨架（方向脚按板子自己拉）：

```lua
uart.write(uart.UART1, req)
local ok, pkt = uart.block(uart.UART1, 3000)
if ok then
    local vals = modbus.analyze(pkt, rules)
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部抛错摘要、`crc` 返回文本与可能原因 |
