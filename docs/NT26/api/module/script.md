# script

**文档版本** `1.1.0`

纯函数模块。查询当前正在跑的脚本副本（boot bundle），以及 A/B 两槽的清单；试运行（trial）成功后可 `confirm`。

没有对象、没有回调。失败一律 **抛错**。

```lua
local script = require("script")
```

平台预加载模块，无需额外 `.lua` 文件。

日常用 `script.info()` 读本工程的 `version` / `build` / `bundle_id`。`script.switch`、`script.rollback` 是 **预留接口，暂未部署，请不要使用**。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `script.info`](#6-1-info)
  - [6.2 `script.confirm`](#6-2-confirm)
  - [6.3 `script.switch`（预留，勿用）](#6-3-switch)
  - [6.4 `script.rollback`（预留，勿用）](#6-4-rollback)
- [7. `info` 返回表](#7-info-返回表)
- [8. trial 与确认](#8-trial-与确认)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本以 **A、B 两槽** 存放。开机选中并真正跑起来的那一份叫 **boot bundle**。

| 需求 | 调用 |
| --- | --- |
| 当前这份脚本的版本 | `script.info()` |
| 看某一槽清单 | `script.info("A")` / `script.info("B")` |
| trial 跑通，升成正式副本 | `script.confirm()` |

`confirm` 只改副本状态，**不会立刻重启**。trial 由下载/AT 选槽进入；脚本侧只负责跑起来之后 `confirm`。

`switch` / `rollback` 见 [6.3](#6-3-switch)、[6.4](#6-4-rollback)：预留，未部署，不要调用。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  info / confirm                                          │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  script 模块                                             │
│  · 读 boot 或指定槽的清单                                │
│  · trial 时 confirm 写成正式副本                         │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  脚本副本状态                                            │
│  槽 A · 槽 B · 当前 boot · confirmed · 模式 normal/trial │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `info` | 读清单，返回表 | 否 |
| `confirm` | trial → normal，写入已确认槽 | 否 |
| `switch` / `rollback` | **预留，未部署，不要调用** | — |

---

## 3. 阻塞语义

`info` / `confirm` 都是同步读写状态，不让出协程。没有后台任务、没有本模块回调。

不要调用 `switch` / `rollback`。

---

## 4. 常量与枚举

模块表 **没有** 整数枚举。槽名用字符串 `"A"` / `"B"`（小写 `"a"` / `"b"` 可接受）。

`mode` 只出现在 `info` 返回表里，取值 `"normal"` 或 `"trial"`，不是模块常量。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `slot` | string | `"A"` 或 `"B"` |
| `info` | table | 见 [第 7 节](#7-info-返回表) |

没有布尔开关参数。`confirm` 成功返回 `true`。

---

## 6. 模块函数

---

### 6.1 `script.info([slot])` {#6-1-info}

读副本信息。

**调用模式**

```lua
script.info()
script.info(slot)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `slot` | 否 | 省略：当前 boot bundle。传入：该槽的 manifest |

成功：一张表，字段见 [第 7 节](#7-info-返回表)。

失败 **抛**：

| 文案 | 原因 |
| --- | --- |
| `script.info: bundle not ready` | 无参，且当前 boot 尚未就绪 |
| `script.info: slot invalid or manifest unavailable` | 槽名非法，或该槽没有可读清单 |

`slot` 必须是 string，否则类型检查抛错。

指定槽时：`slot` / `version` / `build` / `bundle_id` 来自 **该槽清单**；`mode` 仍是 **整机当前模式**；`first_run` 仍是 **本次启动** 脚本第一次真正跑起来的本地时间，不是那一槽的历史记录。

```lua
local cur = script.info()
log.info("version=%s build=%s", cur.version, cur.build)

local ok_a, a = pcall(script.info, "A")
local ok_b, b = pcall(script.info, "B")
```

---

### 6.2 `script.confirm()` {#6-2-confirm}

确认当前 trial 副本运行成功：模式回到 `"normal"`，该槽记为已确认。

**调用模式**

```lua
script.confirm()
```

无参数。成功：`true`。

不在 trial、trial 槽与当前 boot 不一致、或 trial 的 `bundle_id` 对不上：**抛** `script.confirm: not in trial or mismatch`。

只在 `info().mode == "trial"` 时调用。normal 下调用会抛错，请用 `pcall`。

```lua
local cur = script.info()
if cur.mode == "trial" then
    script.confirm()
end
```

---

### 6.3 `script.switch(slot)` {#6-3-switch}

**预留接口，暂未部署，请不要使用。**

名字挂在模块表上，产品路径尚未开放 A/B 切槽。调用后行为未作为对外契约保证。

---

### 6.4 `script.rollback([reason])` {#6-4-rollback}

**预留接口，暂未部署，请不要使用。**

与 `switch` 相同：未部署，不要调用。trial 失败由固件自己处理，脚本不必、也不应手动 rollback。

---

## 7. `info` 返回表

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `slot` | string | `"A"` 或 `"B"` |
| `version` | string | 版本串（清单里的 version，最长约 31 字符） |
| `build` | integer | 构建号 |
| `bundle_id` | string | 副本 ID（最长约 47 字符） |
| `mode` | string | `"normal"` 或 `"trial"` |
| `first_run` | string | 本次启动后脚本首次运行的本地时间 `"YYYY-MM-DD HH:MM:SS"`；未记录或时钟不可用时为 **空串** |

空槽或出厂占位清单常见 `bundle_id` 为 `factory-empty`、`version` 为 `0.0.0`、`build` 为 `0`。

`first_run` 用墙上时钟反推「脚本真正开始跑」的时刻；没授时或尚未标记时不要当有效时间用，只判断空串。

---

## 8. trial 与确认

```
写新包到空闲槽 →（外部）下次以 trial 启动该槽
        → 新脚本跑起来
        → 自检通过：script.confirm()  → 正式副本
        → 自检失败 / 超时 / 崩掉     → 固件回已确认槽（下次启动）
```

- **normal**：已确认路径，开机直接跑当前副本。
- **trial**：新副本试跑。必须 `confirm`，否则下次仍可能被策略打回旧槽。
- 不要用 Lua `switch` / `rollback` 自己切槽。

---

## 9. 错误与返回约定

业务失败 **抛错**，没有 `nil, err`，也没有数字业务码。查询对槽、尝试 `confirm` 请用 `pcall`。

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `info` | table | **抛** |
| `confirm` | `true` | **抛** |
| `switch` / `rollback` | 预留，不要调用；失败也 **抛** | |

**抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `script.info: slot invalid or manifest unavailable` | `info("A"/"B")` 槽名非法，或该槽没有可读清单 |
| `script.info: bundle not ready` | 无参 `info()` 时当前 boot 副本还没就绪 |
| `script.confirm: not in trial or mismatch` | 当前不是 trial，或确认条件不匹配 |
| `script.switch: slot invalid or incomplete` | 目标槽非法或副本不完整（预留接口，不要当业务用） |
| `script.rollback failed` | 回退失败（预留接口） |

`slot` 不是字符串：Lua 标准类型错。`rollback` 可带可选原因串，缺省为 `"script rollback"`（这是传给回退路径的说明，不是返回给脚本的 `err`）。

---

## 10. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 主脚本 VM | **1** |
| 副本槽 | **2**（A / B） |
| 清单 JSON | 约 **8 KB** |
| `version` | 约 **31** 字符 |
| `bundle_id` | 约 **47** 字符 |
| `first_run` | `"YYYY-MM-DD HH:MM:SS"`（19 字符）或空串 |

本模块不持有回调、不占任务槽。`confirm` 写入的是掉电仍在的副本状态。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 日志里打工程版本 | `script.info()` |
| 看另一槽有没有包 | `pcall(script.info, "B")` |
| 新包 trial 跑通 | `mode == "trial"` 时 `confirm` |
| 脚本自己延时、多任务 | [`rt`](rt.md)，与本模块无关 |
| 用 Lua 切槽 / 回退 | **不要**。`switch` / `rollback` 未部署 |

demo：[examples/NT26/os/script/script_api](../../../../examples/NT26/os/script/script_api)。

---

## 12. 完整示例

```lua
local rt = require("rt")
local log = require("log")
local script = require("script")

local function dump(tag, info)
    log.info("%s slot=%s version=%s build=%s id=%s mode=%s first_run=%s",
             tag, info.slot, info.version, info.build,
             info.bundle_id, info.mode, info.first_run)
end

local ok, cur = pcall(script.info)
if ok then
    dump("boot", cur)
    if cur.mode == "trial" then
        local cok, err = pcall(script.confirm)
        log.info("confirm %s", cok and "ok" or tostring(err))
    end
end

for _, slot in ipairs({ "A", "B" }) do
    local sok, inf = pcall(script.info, slot)
    if sok then
        dump(slot, inf)
    else
        log.warn("info(%s) %s", slot, tostring(inf))
    end
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
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部抛错摘要与可能原因 |
