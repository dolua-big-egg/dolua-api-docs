# random

**文档版本** `1.1.0`

纯函数随机数。数值、从序列里抽、洗牌、不放回 / 可放回抽样。熵来自芯片真随机，不是 `math.random`。没有对象、没有回调、不能设种子。

```lua
local random = require("random")
```

平台预加载模块，无需额外 `.lua` 文件。

业务失败返回 `nil, err`。缺参、类型明显不对时，部分接口会 **抛错**（走整数/数字检查），见各节。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `random.random`](#6-1-random)
  - [6.2 `random.randint`](#6-2-randint)
  - [6.3 `random.uniform`](#6-3-uniform)
  - [6.4 `random.randrange`](#6-4-randrange)
  - [6.5 `random.choice`](#6-5-choice)
  - [6.6 `random.shuffle`](#6-6-shuffle)
  - [6.7 `random.sample`](#6-7-sample)
  - [6.8 `random.choices`](#6-8-choices)
- [7. 表与字符串怎么当总体](#7-表与字符串怎么当总体)
- [8. 错误与返回约定](#8-错误与返回约定)
- [9. 资源上限与生命周期](#9-资源上限与生命周期)
- [10. 选型对照](#10-选型对照)
- [11. 完整示例](#11-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

接口形状接近 Python `random`：

| 需求 | 函数 |
| --- | --- |
| `[0, 1)` 浮点 | `random()` |
| 闭区间整数 | `randint(a, b)` |
| `a` 到 `b` 的浮点 | `uniform(a, b)` |
| 半开区间整数（可步长） | `randrange(start, stop[, step])` |
| 抽一个 | `choice` |
| 原地打乱表 | `shuffle` |
| 不放回抽 k 个 | `sample` |
| 可放回抽 k 个（可加权） | `choices` |

整数区间用拒绝采样，避免 `% bound` 偏差。浮点随机元取 24 bit，映射到 `[0, 1)`。

不要用本模块当密码学密钥派生的唯一依据（没有提供字节流 / HMAC 接口）；做骰子、抽样、口令字符挑选可以。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  random / randint / choice / sample / …                  │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  random 模块                                             │
│  · 当场向硬件要随机位                                    │
│  · 再映射成整数、浮点或下标                              │
│  · 无实例、无种子、全 VM 共用同一熵源                    │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| 各接口 | 取熵 + 换算完再返回 | **否** |

硬件取数失败时返回 `nil, "trng failed"`，不抛错。

---

## 3. 阻塞语义

同步。一次调用通常只要几十字节熵，可在短回调里用。`choices` / `sample` 的 `k` 很大时会循环多次取数，会占住调度。

没有 `seed()`，也没有可复现模式。同一调用两次结果应不同（硬件允许的范围内）。要可复现的号码见 [`dream`](dream.md) 的 `stable`。

---

## 4. 常量与枚举

没有整数枚举。模块表上是 **字符集 string**，给 `choice` / `sample` / `choices` 当总体：

| 符号 | 内容 |
| --- | --- |
| `random.ascii_lowercase` | `abcdefghijklmnopqrstuvwxyz` |
| `random.ascii_uppercase` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ` |
| `random.ascii_letters` | 小写 + 大写 |
| `random.digits` | `0123456789` |
| `random.octdigits` | `01234567` |
| `random.hexdigits` | `0123456789abcdefABCDEF` |
| `random.punctuation` | `!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~` |
| `random.whitespace` | 空格、Tab、`\n`、`\r`、`\f`、`\v` |
| `random.printable` | digits + letters + punctuation + whitespace |

这些是普通 string，可拼接：`random.ascii_letters .. random.digits`。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `a` / `b` | integer 或 number | `randint` 必须整数；`uniform` 是 number |
| `start` / `stop` / `step` | integer | `randrange` |
| `seq` / `pop` | table 或 string | 总体，见 [第 7 节](#7-表与字符串怎么当总体) |
| `k` | integer | 抽样个数，`≥ 0` |
| `weights` | table | 与总体等长的非负 number |

`randint` / `randrange` 的区间参数走整数检查：写成 `1.5` 会 **抛错**。`uniform` 收 number。

---

## 6. 模块函数

下列接口成功时返回值见各节；熵源失败统一 `nil, "trng failed"`。

---

### 6.1 `random.random()` {#6-1-random}

`[0.0, 1.0)` 的浮点。无参数。

**调用模式**

```lua
random.random()
```

成功：number。失败：`nil, err`。

精度大约 24 bit（约 1/16777216）。不要拿它拼 64 bit 密钥。

```lua
local u = random.random()   -- 0 <= u < 1
```

---

### 6.2 `random.randint(a, b)` {#6-2-randint}

闭区间整数。`a`、`b` 谁大谁小都行，内部会排成 `[min, max]`。

**调用模式**

```lua
random.randint(a, b)
```

缺参或不是整数：**抛错**。

```lua
random.randint(1, 6)
random.randint(6, 1)   -- 与上一行同一区间
random.randint(3, 3)   -- 总是 3
```

成功：integer。失败：`nil, err`。

---

### 6.3 `random.uniform(a, b)` {#6-3-uniform}

`a + (b - a) * t`，`t` 在 `[0, 1)`。因此 **含 `a`，一般到不了 `b`**（`a < b` 时是左闭右开）。`a > b` 时从 `a` 往 `b` 走，同样到不了 `b`。不会像 `randint` 那样交换端点。

**调用模式**

```lua
random.uniform(a, b)
```

缺参或无法当数字：**抛错**。

```lua
random.uniform(1.5, 3.5)
random.uniform(0, 1)
```

---

### 6.4 `random.randrange(start, stop[, step])` {#6-4-randrange}

半开区间，类似 Python：`start, start+step, …`，**不含 `stop`**。

**调用模式**

```lua
random.randrange(start, stop)
random.randrange(start, stop, step)
```

`step` 省略或 `nil` 为 `1`。

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `start` | 是 | 起点（含） |
| `stop` | 是 | 终点（不含） |
| `step` | 否 | 默认 `1`，**不能为 0** |

少于 2 个参数：`nil, "randrange requires start, stop[, step]"`。`step == 0`：`nil, "step must not be zero"`。区间里一个点都没有：`nil, "empty range"`（例如 `randrange(5, 5)`，或 `start >= stop` 且步长为正）。

正步长：`start < stop`。负步长：`start > stop`。

```lua
random.randrange(0, 10)       -- 0..9
random.randrange(0, 10, 2)    -- 0,2,4,6,8
random.randrange(10, 0, -3)   -- 10,7,4,1
```

`start`/`stop`/`step` 不是整数会 **抛错**。

---

### 6.5 `random.choice(seq)` {#6-5-choice}

从总体里均匀抽 **一个**。

**调用模式**

```lua
random.choice(t)
random.choice(s)
```

| `seq` | 成功返回 |
| --- | --- |
| 非空 table | `t[i]`，`i` 均匀来自 `1..#t` |
| 非空 string | 长度为 1 的 string（一个 **字节**，不是 UTF-8 码点） |

```lua
random.choice({ "red", "green", "blue" })
random.choice("ABCDE")
random.choice(random.digits)
```

失败：`nil, err`。

| `err` | 原因 |
| --- | --- |
| `choice requires table or string` | 不是表也不是 string（含漏传） |
| `choice requires non-empty table` | `#t < 1` |
| `choice requires non-empty string` | 空串 |

---

### 6.6 `random.shuffle(t)` {#6-6-shuffle}

原地打乱数组部分 `1..#t`，返回 **同一张表**。

**调用模式**

```lua
random.shuffle(t)
```

```lua
local cards = { 1, 2, 3, 4, 5 }
random.shuffle(cards)   -- cards 已被打乱
```

不是非空表：`nil, "shuffle requires non-empty table"`。字符串不能洗，请先拆成表。

---

### 6.7 `random.sample(pop, k)` {#6-7-sample}

不放回抽 `k` 个，相对顺序随机。`k` 可以是 `0`（空结果）。

**调用模式**

```lua
random.sample(t, k)
random.sample(s, k)
```

| `pop` | 成功返回 |
| --- | --- |
| table | 长度为 `k` 的新表（不改原表） |
| string | 长度为 `k` 的新 string（按字节抽） |

`k` 必须是整数，缺了或类型不对 **抛错**。

`k > #pop`：`nil, "sample larger than population"`。`k < 0`：`nil, "invalid k"`。

```lua
random.sample({ 10, 20, 30, 40, 50 }, 3)
random.sample(random.ascii_lowercase, 4)
```

---

### 6.8 `random.choices(pop [, weights] [, k])` {#6-8-choices}

**可放回** 抽 `k` 次，允许重复。`k` 默认 `1`。

**调用模式**

```lua
random.choices(pop)
random.choices(pop, k)
random.choices(pop, weights)
random.choices(pop, weights, k)
random.choices(pop, nil, k)
```

第二参若是 **number**（含可转成数字的值），一律当成 `k`，不再当权重。权重必须传 table。

| `pop` | 成功返回 |
| --- | --- |
| table | 长度为 `k` 的表 |
| string | 长度为 `k` 的 string |

`weights` 与总体 **等长**，元素 `≥ 0`，总和必须 `> 0`。省略则每项权重 1。

```lua
random.choices({ "A", "B", "C" }, 5)
random.choices({ "A", "B", "C" }, { 1, 1, 8 }, 8)  -- C 更常出现
random.choices(random.digits, 6)
random.choices(random.hexdigits, nil, 16)
```

权重表长度不对、有负数、全 0：`nil, "invalid weights"`。某个权重元素不是数字会 **抛错**（不是 `invalid weights`）。

`k < 0`：`nil, "invalid k"`。`k` 很大时按次取熵，会变慢。

---

## 7. 表与字符串怎么当总体

长度一律按 Lua `#`（`luaL_len`）：

- 表：只看数组部分 `1 .. #t`。字符串键、空洞后面的项不会被抽到。
- string：按 **字节** 计数。多字节 UTF-8 会被拆开，不要拿中文当「字符」总体。

`choice` / `sample` / `choices` 对表用 `rawgeti`，不走 `__index`。

`shuffle` 只交换 `1..#t`，哈希部分不动。

---

## 8. 错误与返回约定

业务失败走 `nil, err`，不抛。缺参/类型错部分接口会抛 Lua 标准 `bad argument`。没有数字业务码。兜底文案 `random error` 仅在内部未带出原因时出现。

| 接口 | 成功 | 业务失败 | 类型 / 缺参 |
| --- | --- | --- | --- |
| `random` | number | `nil, err` | — |
| `randint` / `uniform` | number/integer | `nil, err` | 缺参或类型 **抛** |
| `randrange` | integer | `nil, err` | `start`/`stop`/`step` 非整数 **抛**；少参则 `nil, err` |
| `choice` / `shuffle` | 元素或原表 | `nil, err` | 见下表 |
| `sample` | 表或 string | `nil, err` | `k` 非整数 **抛** |
| `choices` | 表或 string | `nil, err` | `k` 或权重元素类型不对可能 **抛** |

**返回的 `err`**

| `err` | 可能原因 |
| --- | --- |
| `trng failed` | 硬件真随机没给出数（各抽样接口都可能） |
| `randrange requires start, stop[, step]` | `randrange` 参数少于 2 个 |
| `step must not be zero` | `step == 0` |
| `empty range` | 半开区间为空（`start`/`stop`/`step` 组不出任何整数） |
| `choice requires table or string` | 第一参既不是表也不是 string |
| `choice requires non-empty table` | 空表 |
| `choice requires non-empty string` | 空串 |
| `shuffle requires non-empty table` | 不是非空表 |
| `sample requires table or string` | 总体类型不对 |
| `sample requires non-empty table` | 空表 |
| `sample requires non-empty string` | 空串 |
| `sample larger than population` | `k` 大于总体长度 |
| `choices requires table or string` | 总体类型不对 |
| `choices requires non-empty table` | 空表 |
| `choices requires non-empty string` | 空串 |
| `invalid k` | `k < 0` 或超出整数上限 |
| `invalid weights` | 权重表长度/数值不合格 |

需要区分抛错时用 `pcall`。

---

## 9. 资源上限与生命周期

| 项 | 说明 |
| --- | --- |
| 实例 | 无 userdata |
| 种子 | 无。每次向硬件取 |
| `k` / 表长 | 受 Lua 整数和内存限制；极大的 `choices` 会长时间占调度 |
| 浮点随机 | 约 24 bit |
| 回调 | 无 |

---

## 10. 选型对照

| 需求 | 做法 |
| --- | --- |
| 骰子、延时抖动 | `randint` / `uniform` |
| 从名单抽一个 | `choice` |
| 打乱播放列表 | `shuffle` |
| 抽不重复的 k 个 | `sample` |
| 加权、允许重复 | `choices` |
| 8 位口令字符 | `sample(letters..digits, 8)`（不重复）或 `choices(..., 8)`（可重复） |
| 可复现的双色球 | [`dream`](dream.md)，`stable=true` |
| Lua 自带伪随机 | `math.random`，与本模块不是同一套 |

---

## 11. 完整示例

与 [examples/NT26/module/random/random_api](../../../../examples/NT26/module/random/random_api) 一致：

```lua
local random = require("random")

random.random()
random.randint(1, 6)
random.uniform(1.5, 3.5)
random.randrange(0, 10, 2)

random.choice({ "red", "green", "blue" })
random.choice("ABCDE")

local cards = { 1, 2, 3, 4, 5, 6, 7, 8 }
random.shuffle(cards)

random.sample({ 10, 20, 30, 40, 50 }, 3)
random.choices({ "A", "B", "C" }, { 1, 1, 8 }, 8)

local pool = random.ascii_letters .. random.digits
random.sample(pool, 8)
random.choices(random.hexdigits, 16)

local v, err = random.sample({ 1, 2 }, 5)  -- nil, sample larger than population
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部 `err` 文本与可能原因 |
