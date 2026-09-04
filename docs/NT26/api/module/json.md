# json

**文档版本** `1.0.1`

纯函数 JSON 编解码。Lua 值 ↔ 紧凑 JSON 文本。没有对象、没有回调。失败返回 `nil, err`，不抛业务错（`option` 的非法键除外）。

```lua
local json = require("json")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与模块字段](#4-常量与模块字段)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `json.encode`](#6-1-encode)
  - [6.2 `json.decode`](#6-2-decode)
  - [6.3 `json.option`](#6-3-option)
- [7. Lua ↔ JSON 对照](#7-lua--json-对照)
- [8. 数组还是对象](#8-数组还是对象)
- [9. `null` 与空洞](#9-null-与空洞)
- [10. 数字怎么打出来](#10-数字怎么打出来)
- [11. `option` 键一览](#11-option-键一览)
- [12. 错误与返回约定](#12-错误与返回约定)
- [13. 资源上限与生命周期](#13-资源上限与生命周期)
- [14. 选型对照](#14-选型对照)
- [15. 完整示例](#15-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

MQTT / HTTP 报文、配置落盘、和云端对字段，都把 Lua 表编成 JSON、再解回来。

1. `json.encode(value)` → 紧凑文本（无换行、无缩进）。
2. `json.decode(str)` → Lua 值。
3. `json.option(key [, value])` 调数字格式、空表是 `{}` 还是 `[]` 等。

对象的键顺序不保证。往返请比字段，不要比两段 JSON 字符串是否全等。

JSON 的 `null` 解出来 **不是** Lua `nil`（`nil` 会删掉表项），而是 `json.null`。见 [第 9 节](#9-null-与空洞)。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  encode / decode / option                                │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  json 模块                                               │
│  · encode/decode：pcall 包一层，失败变 nil, err          │
│  · option：短别名或长名，改本模块这份配置                 │
│  · 开机：嵌套上限 100、不缓存缓冲、拒绝非法数字解码       │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  紧凑 JSON 文本                                          │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `encode` / `decode` | 整棵值转完再返回 | **否**（大包会占住调度） |
| `option` | 读/写本模块配置 | **否** |

配置挂在 `require("json")` 得到的这一份模块表上，全脚本共用。不要调用模块表上的 `new()` 再开一份，否则 `option` 改的不是你正在 `encode` 的那份。

---

## 3. 阻塞语义

同步 CPU 转换。短对象可在回调里用；很大的嵌套表或数 KB 文本会占住整台 Lua。没有后台任务。

---

## 4. 常量与模块字段

没有整数枚举。模块表上有：

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `json._NAME` | `"json"` | 模块名 |
| `json._VERSION` | `"2.1devel"` | 编解码器版本串 |
| `json.null` | 空轻量 userdata | JSON `null` 在 Lua 里的占位。用 `== json.null` 判断 |

`option` 的 `"on"` / `"off"` / `"null"` 是字符串取值，未做成 `json.ON` 这种符号。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `value` | 见第 7 节 | `encode` 的入参 |
| `str` | string | `decode` 的 JSON 文本 |
| `key` | string | `option` 短名或长名 |
| `err` | string | 失败第二返回值 |

`empty_arr`、`num_sci`、`num_trim` 等可收布尔。这里走 **真假语义**：`false`/`nil` 为假，**数字 `0` 为真**。请写 `true`/`false` 或 `"on"`/`"off"`，不要传 `0`/`1` 当开关。

---

## 6. 模块函数

---

### 6.1 `json.encode(value)` {#6-1-encode}

**调用模式**

```lua
json.encode(value)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `value` | 是 | 要编码的 Lua 值 |

成功：紧凑 JSON string（无空格换行）。失败：`nil, err`。

缺参：`nil, "json encode expects one argument"`。

```lua
json.encode({ name = "demo", n = 3, ok = true, tags = { "a", "b" } })
json.encode({ 1, 2, 3 })
json.encode("hi")     -- "\"hi\""
json.encode(nil)      -- "null"
json.encode(true)     -- "true"
```

不能编码：function、thread、普通 userdata、循环引用（嵌套超深当深度错）、键不是 string/number 的表、过疏数组（见第 8 节）。这些会变成 `nil, err`（文案里常见 `Cannot serialise …`）。

---

### 6.2 `json.decode(str)` {#6-2-decode}

```lua
json.decode(str)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `str` | 是 | 一整段 JSON 文本 |

成功：对应的 Lua 值（表、字符串、数字、布尔，或 `json.null`）。失败：`nil, err`。缺参：`nil, "json decode expects a string argument"`。

数字一律按 **浮点** 推进 Lua（`lua_pushnumber`）。JSON `3` 解出来 `math.type` 往往是 `"float"`，和 Lua 整数 `3` 用 `==` 仍相等，但类型不同。demo 往返比的是字段值，不是 `math.type`。

对象 → 字符串键的表。数组 → 下标从 1 起的连续表。空对象 `{}`、空数组 `[]` 解出来都是空表，之后再 `encode` 会受 `empty_arr` 影响（默认都变成 `{}`）。

非法 JSON、截断、尾部垃圾、超过嵌套上限：`nil, err`。`err` 里常有 `character N` 指出位置（从 1 计）。

```lua
local t, err = json.decode('{"a":1}')
local bad, berr = json.decode("{bad")   -- nil, 错误串
```

---

### 6.3 `json.option(key [, value])` {#6-3-option}

**调用模式**

```lua
json.option(key)           -- 读
json.option(key, value)    -- 写，并返回写入后的值
```

只能 1 个或 2 个参数，否则 **抛** `"json.option: usage json.option(key) or json.option(key, value)"`。未知 `key`：**抛** `"json.option: unsupported key"`。

短名与长名等价，见 [第 11 节](#11-option-键一览)。

```lua
json.option("empty_arr", true)
json.encode({})                 -- "[]"
json.option("empty_arr", false)

json.option("num_sci", "off")
json.encode({ id = 1782873378 })  -- 不会打成 1.78e+09
```

写错类型（例如给整数键传表）会 **抛**（配置函数自己的参数检查）。

---

## 7. Lua ↔ JSON 对照

| Lua | encode 结果 | decode 回来 |
| --- | --- | --- |
| `nil` | `null` | （作根值）`json.null`，不是 `nil` |
| `true` / `false` | `true` / `false` | 布尔 |
| 整数 / 浮点 | JSON number | **浮点** number |
| string（可含 `0x00`、UTF-8） | JSON string，控制字符转义 | string |
| 连续整数下标表 `{1,2,3}` | `[1,2,3]` | 同样的数组表 |
| 字符串键表 `{a=1}` | `{"a":1}` | 字符串键表 |
| 空表 `{}` | 默认 `{}`；`empty_arr=true` 时 `[]` | 空表 |
| `json.null` | `null` | `json.null` |
| function / userdata / thread | 失败 | — |

JSON 对象的键在文本里总是字符串。Lua 用 **数字当键** 的对象（判定为 object 而非 array 时）会把数字键打成 `"1":...` 这种字符串键。

---

## 8. 数组还是对象

编码时看表里的键：

1. **所有键**都是 ≥1 的整数（无小数、无字符串键、无 0 或负数键）→ 当数组，长度 = **最大下标**（不是 `#t`）。
2. 出现任何非这类键 → 整个表当 **对象**。
3. 一个键都没有（空表）→ 默认对象 `{}`；`empty_arr==true` 则为 `[]`。

因此：

| Lua | JSON |
| --- | --- |
| `{ "a", "b" }` | `["a","b"]` |
| `{ name = "x" }` | `{"name":"x"}` |
| `{ 1, 2, name = "x" }` | 对象（有字符串键），不是数组 |
| `{ [1] = 1, [3] = 3 }` | **过疏数组**：最大下标 3、实有 2 项。开机配置为「不允许过疏」→ **编码失败** |
| `{ [2] = "a" }` | 下标从 2 起，最大 2、1 号是空洞，同样容易被判过疏而失败 |

需要 `[1,null,3]` 时：写成 `{ 1, json.null, 3 }`（中间用 `json.null` 占住，不要留空洞）。

`#t` 在 Lua 里碰到空洞会截断，不要用 `#` 判断能不能当数组。连续 `1..n` 无空洞即可。

对象键遍历顺序不稳定：`{ a = 1, b = 2 }` 两次 `encode` 文本可能不同。

---

## 9. `null` 与空洞

JSON `null` 不能变成 Lua `nil`，否则 `t.k = nil` 会把 `k` 从桌上抹掉，字段就丢了。

| 方向 | 行为 |
| --- | --- |
| encode `nil`（根值或数组槽里取到 nil） | `null` |
| encode `json.null` | `null` |
| decode `null` | **`json.null`**（空轻量 userdata） |

判断：

```lua
local t = json.decode('{"a":null}')
if t.a == json.null then
    -- 字段存在，值是 JSON null
end
if t.a == nil then
    -- 不会走到：decode 不会用 nil 表示 null
end
```

`t.b` 若 JSON 里根本没有键 `b`，才是 Lua `nil`。

---

## 10. 数字怎么打出来

默认（模块刚 `require` 完）：

- 允许科学计数法（大数可能变成 `1.782873378e+09`）。
- 有效数字约 14 位。
- 未开「固定小数位」（`num_dp == -1`）。
- 不允许把 NaN / Infinity 编进 JSON（会失败）。
- 解码也不接受 JSON 里的 `NaN` / `Infinity`。

MQTT 设备 ID、IMEI 这类 **大于 2^31 的整数** 若被打成科学计数，对端可能当浮点解析错。需要完整十进制时：

```lua
json.option("num_sci", "off")
```

固定小数（传感器、金额）：

```lua
json.option("num_dp", 2)       -- 始终两位，12 → 12.00
json.option("num_trim", true)  -- 12.00 → 12（仍按固定小数模式生成后再削 0）
json.option("num_dp", -1)      -- 回到默认精度模式
```

`num_dp >= 0` 时走固定小数，不再走科学计数那条路。范围 `-1`～`14`。

`bad_num`：

| 值 | 编码 NaN / ±Inf |
| --- | --- |
| `"off"` / `false`（默认） | 失败 |
| `"on"` / `true` | 打出 `NaN` / `Infinity`（不是严格 JSON） |
| `"null"` | 打成 `null` |

---

## 11. `option` 键一览

短名优先。长名与编解码器配置函数同名，也可以传给 `option`。

| 短名 | 长名 | 取值 | 开机默认 | 作用 |
| --- | --- | --- | --- | --- |
| `num_sci` | `encode_number_scientific` | `true`/`false` 或 `"on"`/`"off"` | 开 | 是否允许科学计数法 |
| `num_dp` | `encode_number_decimal_places` | 整数 `-1`～`14` | `-1` | 固定小数位；`-1` 关闭 |
| `num_trim` | `encode_number_trim_zero` | 布尔 / on/off | 开 | 固定小数时去掉尾 0 |
| `bad_num` | `encode_invalid_numbers` | `"off"` / `"on"` / `"null"` | `"off"` | NaN/Inf 怎么编 |
| `empty_arr` | `encode_empty_table_as_array` | 布尔 / on/off | **关**（空表 → `{}`） | 空表编成 `[]` |
| — | `encode_number_precision` | 整数 `1`～`14` | `14` | 非固定小数时的有效位 |
| — | `decode_invalid_numbers` | 布尔 / on/off | **关** | 解码是否接受 NaN/Inf |
| — | `encode_keep_buffer` | 布尔 / on/off | **关** | 是否复用内部缓冲；一般保持关 |
| — | `encode_max_depth` | 整数 ≥1 | **100** | 编码嵌套上限 |
| — | `decode_max_depth` | 整数 ≥1 | **100** | 解码嵌套上限 |

读：`json.option("empty_arr")` 返回当前布尔或对应字符串（`bad_num` 返回 `"off"`/`"on"`/`"null"`）。

不在上表的键（包括 `encode_sparse_array`）`option` 会抛 unsupported。过疏数组策略在开机已设成「不允许」，一般不要改模块表上的同名函数。

---

## 12. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `encode` | string | `nil, err` |
| `decode` | Lua 值 | `nil, err` |
| `option` 读/写 | 当前设置 | 非法键/参数个数/**取值类型**：**抛** |

`encode`/`decode` 缺参时的 `err`：

- `"json encode expects one argument"`
- `"json decode expects a string argument"`

内部转失败时 `err` 可能是编解码器原文（`Cannot serialise number: must not be NaN or Infinity`、`excessively sparse array`、`Expected … at character N` 等）。配置函数不可用时 option 抛 `"json.option: option function unavailable"`。

---

## 13. 资源上限与生命周期

| 项 | 上限 / 说明 |
| --- | --- |
| 嵌套深度 | 编码、解码均为 **100**（可用 option 改，不建议盲目加大） |
| 空表 | 默认 `{}` |
| 过疏数组 | 编码失败，不是自动变对象 |
| 数字精度 | 默认 14 位 |
| 实例 | 一份模块配置，全 VM 共用 |

没有 userdata 生命周期。`encode_keep_buffer` 默认关，每次编码用临时缓冲。

---

## 14. 选型对照

| 需求 | 做法 |
| --- | --- |
| 普通对象/数组 | `encode` / `decode` |
| 设备 ID 不要科学计数 | `option("num_sci", "off")` |
| 空列表发给云端必须是 `[]` | `option("empty_arr", true)`，或不要发空表 |
| JSON `null` | `json.null`，不要用 `nil` 当字段值 |
| 二进制 / hex | [`hex`](hex.md)，不是 JSON |
| 协议粘包 | [`framekit`](framekit.md) |

---

## 15. 完整示例

与 [examples/NT26/module/json/json_api](../../../../examples/NT26/module/json/json_api) 一致：

```lua
local json = require("json")

local obj = { name = "demo", n = 3, ok = true, tags = { "a", "b" } }
local s, err = json.encode(obj)
local back = json.decode(s)
-- back.name == "demo"；键顺序可能和 s 再 encode 不一致

json.option("empty_arr", true)
json.encode({})                    -- "[]"

json.option("num_sci", "off")
json.encode({ id = 1782873378 })   -- 完整十进制

local v, e = json.decode("{bad")   -- nil, 错误串
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
