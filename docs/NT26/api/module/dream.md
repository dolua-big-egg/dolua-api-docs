# dream

**文档版本** `1.1.0`

纯函数。按福利彩票规则抽双色球 / 大乐透注数。独立模块，`require("dream")`，不是 `random` 的子表。

```lua
local dream = require("dream")
```

平台预加载。默认用芯片真随机；可给生日等 `seed`。`stable=true` 时同一种子可复现。

这是玩法抽样，不是购彩通道，也不保证中奖。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `dream.ssq` / `dream.shuangseqiu`](#6-1-ssq)
  - [6.2 `dream.dlt` / `dream.daletou`](#6-2-dlt)
- [7. 参数怎么传](#7-参数怎么传)
- [8. 一注的结构](#8-一注的结构)
- [9. 种子与可复现](#9-种子与可复现)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

| 玩法 | 函数 | 前区 | 后区 |
| --- | --- | --- | --- |
| 双色球 | `ssq`（别名 `shuangseqiu`） | 6 个，`1`～`33`，不重复升序 | 1 个，`1`～`16` |
| 大乐透 | `dlt`（别名 `daletou`） | 5 个，`1`～`35`，不重复升序 | 2 个，`1`～`12`，不重复升序 |

一次可出多注（默认 1，最多 `dream.COUNT_MAX` = **100**）。前区、后区各自不放回抽样，两区互相独立。

通用骰子 / 洗牌用 [`random`](random.md)。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  dream.ssq / dream.dlt                                   │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  dream 模块                                              │
│  · 无 seed：每号向硬件要熵                               │
│  · 有 seed：种子哈希开流；stable=false 再混一次硬件盐    │
│  · 不放回抽样后排序，拼 text                             │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `ssq` / `dlt` | 抽完 `count` 注再返回 | **否** |

---

## 3. 阻塞语义

同步。100 注会多次取数。无回调。

---

## 4. 常量与枚举

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `dream.COUNT_MAX` | `100` | 单次最多注数 |
| `dream.SSQ_FRONT_COUNT` | `6` | 双色球前区个数 |
| `dream.SSQ_FRONT_MAX` | `33` | 前区号码上限 |
| `dream.SSQ_BACK_COUNT` | `1` | 后区个数 |
| `dream.SSQ_BACK_MAX` | `16` | 后区上限 |
| `dream.DLT_FRONT_COUNT` | `5` | 大乐透前区个数 |
| `dream.DLT_FRONT_MAX` | `35` | 前区上限 |
| `dream.DLT_BACK_COUNT` | `2` | 后区个数 |
| `dream.DLT_BACK_MAX` | `12` | 后区上限 |

玩法数字写死在模块里，不能改「从 1～40 抽 7 个」。规则变了要等固件，不要自己改这些常量指望生效。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `count` | integer | `1`～`100` |
| `seed` | string 或 integer | 非空串，或整数 |
| `stable` | 布尔或整数 | 见 [第 9 节](#9-种子与可复现) |
| `opt` | table | `{ count=, seed=, stable= }` |
| `tickets` | table | 长度为 `count` 的注数组 |

`stable` 若传数字：`0` 为假，非 `0` 为真（按整数，**不是**「数字 0 为真」那套）。推荐 `true` / `false`。

---

## 6. 模块函数

`ssq` 与 `dlt` 的参数、失败风格完全相同，只是号码范围不同。别名指向同一套实现。

---

### 6.1 `dream.ssq(...)` / `dream.shuangseqiu(...)` {#6-1-ssq}

抽双色球。

**调用模式**

```lua
dream.ssq()
dream.ssq(count)
dream.ssq(seed)
dream.ssq(count, seed)
dream.ssq(seed, count)
dream.ssq(seed, stable)
dream.ssq(count, seed, stable)
dream.ssq(seed, count, stable)
dream.ssq(opt)
```

`opt` 示例：

```lua
dream.ssq({ count = 5, seed = "1990-08-15", stable = true })
dream.ssq({ count = 3, seed = 20260831 })
```

成功：注数表（见 [第 8 节](#8-一注的结构)）。失败：`nil, err`。

`shuangseqiu` 与 `ssq` 等价。

---

### 6.2 `dream.dlt(...)` / `dream.daletou(...)` {#6-2-dlt}

抽大乐透。调用模式与 `ssq` 相同。

```lua
dream.dlt()
dream.dlt(5)
dream.dlt("1990-08-15", true)
dream.daletou({ count = 2, seed = 20260831, stable = false })
```

---

## 7. 参数怎么传

位置参数靠 **第一参类型** 分支，不要混用看不懂的组合。

| 第一参 | 第二参 | 第三参 | 含义 |
| --- | --- | --- | --- |
| 省略 / `nil` | — | — | 1 注，纯硬件随机 |
| 正整数 `count` | 省略 | — | `count` 注，纯硬件随机 |
| 正整数 `count` | `seed` | `stable` 可选 | 多注 + 种子 |
| 非空 string `seed` | 省略 | — | 1 注 + 种子（默认再混硬件，每次不同） |
| 非空 string `seed` | 布尔 `stable` | — | 1 注；`true` 则可复现 |
| 非空 string `seed` | 正整数 `count` | `stable` 可选 | 多注 + 种子 |
| table | — | — | 只认键 `count` / `seed` / `stable` |

`count` 超出 `1`～`100`：`nil, "count out of range"`。第一参既不是数字、字符串、表：`nil, "invalid argument"`。

表形式里省略的键用默认：`count=1`，无 `seed` 则纯硬件，`stable` 默认假。

---

## 8. 一注的结构

成功返回的是数组，`tickets[i]`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `front` | table | 前区，已升序，双色球 6 个、大乐透 5 个 |
| `back` | table | 后区，已升序；双色球长度为 1 |
| `text` | string | 展示串，两位补零，后区前有 ` +` |

双色球示例：`text` 形如 `"01 08 15 22 27 33 + 07"`。大乐透后区两个数：`"… + 03 11"`。

```lua
local tickets = dream.ssq(3)
for i, t in ipairs(tickets) do
    -- t.front[1] .. t.front[6]，t.back[1]，t.text
end
```

---

## 9. 种子与可复现

| `seed` | `stable` | 行为 |
| --- | --- | --- |
| 无 | — | 每颗号码都向硬件要 |
| 有 | `false` / 省略 | 种子哈希后再 XOR 一次硬件盐，**每次不同** |
| 有 | `true` | 只用种子开流，同一 `seed` + `count` + 玩法 **结果固定** |

`seed` 可以是生日字符串（`"1990-08-15"`、`"19900815"` 都会进哈希，内容不同则号码不同）或整数。空字符串：`nil, "invalid seed"`。

`stable` 类型不对：`nil, "invalid stable"`。无 `seed` 时 `stable` 无意义（表里只写 `stable` 不写 `seed` 仍是纯硬件）。

可复现请同时固定：玩法函数、`seed`、`count`、`stable=true`。固件若更换哈希/开流实现，旧结果不必再对齐。

---

## 10. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `ssq` / `dlt` 及别名 | 注数表 | `nil, err` |

没有数字业务码。部分位置类型不对会 **抛** Lua 标准整数检查，不完全都是 `nil, err`。推荐表形式 `dream.ssq({ count = 5, seed = "…" })`。

**返回的 `err`**

| `err` | 可能原因 |
| --- | --- |
| `count out of range` | 注数不是 1～100 |
| `invalid seed` | 种子不是 string/integer，或空串 |
| `invalid stable` | `stable` 不是布尔（也不是可当布尔读的整数） |
| `invalid argument` | 第一参既不是 nil、也不是 number/string/table |
| `trng failed` | 硬件真随机失败（纯随机，或 `stable=false` 混盐时） |
| `draw failed` | 已开种子流却抽号失败（极少） |

兜底 `random error` 仅在内部未带出原因时出现。

---

## 11. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 单次注数 | **100** |
| 号码池 | 前区最多 35，后区随玩法 |
| 实例 | 无 userdata |

---

## 12. 选型对照

| 需求 | 做法 |
| --- | --- |
| 双色球 / 大乐透 | 本模块 |
| 普通抽样、骰子 | [`random`](random.md) |
| 可复现演示 | `seed` + `stable=true` |
| 每次不同但带生日偏置 | 只传 `seed`，不要 `stable` |

---

## 13. 完整示例

```lua
local dream = require("dream")

local one = dream.ssq()
-- one[1].text  例如 "01 08 15 22 27 33 + 07"

local five = dream.ssq(5, "1990-08-15")
for i, t in ipairs(five) do
    print(i, t.text)
end

local same = dream.ssq("19900815", true)
local again = dream.ssq({ seed = "19900815", stable = true })
-- same[1].text == again[1].text

local dlt = dream.dlt(2)
-- dlt[1].front 5 个数，dlt[1].back 2 个数
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部 `err` 文本与可能原因 |
