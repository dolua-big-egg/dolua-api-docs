# rndis

**文档版本** `1.1.0`

USB 网卡开关。纯函数模块：把模组的蜂窝网络通过 USB 共享给电脑。没有对象、没有回调、没有 `open`。

```lua
local rndis = require("rndis")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 什么是 RNDIS](#1-什么是-rndis)
- [2. 模块定位](#2-模块定位)
- [3. 框架结构](#3-框架结构)
- [4. 阻塞语义](#4-阻塞语义)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [7.1 `rndis.set`](#7-1-set)
  - [7.2 `rndis.save`](#7-2-save)
  - [7.3 `rndis.get`](#7-3-get)
  - [7.4 `rndis.saved`](#7-4-saved)
- [8. `enable` / `bound` / `saved`](#8-enable--bound--saved)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 什么是 RNDIS

**RNDIS**（Remote Network Driver Interface Specification）是微软定义的一套 USB 协议：USB 设备在电脑上伪装成一块 **以太网卡**，而不是普通的串口或 U 盘。

接到本模组上时：

1. USB 线连到电脑。
2. 脚本 `rndis.set(true)`（或开机策略已打开）。
3. 电脑枚举出一块虚拟网卡。
4. 模组把蜂窝（4G/LTE 等）数据转到这条 USB 网上，电脑就能上网——相当于 **USB 网络共享 / 网卡模式**。

和 AT 口不是一回事：AT/日志仍走串口或另一路 USB 功能；RNDIS 专门扛 IP 流量。电脑侧流量全部走模组的 SIM 套餐，**注意流量消耗**。

常见电脑表现：

| 系统 | 大致情况 |
| --- | --- |
| Windows | 多数版本自带 RNDIS 驱动，设备管理器里会出现远程 NDIS / 远程网络适配器 |
| Linux | 内核多有 `rndis_host`，插上后多一块 `usb0` / `enx…` |
| macOS | 往往要额外驱动或用不了，不要默认当成可用 |

电脑能上网的前提：模组已经驻网（SIM、PDP），并且 `get()` 的 **`bound` 为 1**。只把 `enable` 置 1、USB 没插上或还没绑上时，电脑侧看不到可用网卡。

本模块 **不**配置 IP、DNS、NAT 细节，只开关「要不要当 USB 网卡」。绑的是默认数据承载（CID 1），脚本不用填 CID。

---

## 2. 模块定位

四个函数：本次开关、开机策略、读本次状态、读开机策略。

1. `rndis.set(enable)`：**仅本次**打开或关闭。不改开机策略。重启后仍看 `saved()`。
2. `rndis.save(enable)`：本次立刻生效，**并写入掉电保存的开机策略**。`true`/`1` = 以后开机自动开；`false`/`0` = 开机不再自动。
3. `rndis.get()`：本次 `enable`（是否已请求打开）和 `bound`（是否已绑上）。
4. `rndis.saved()`：开机是否自动打开。

demo 只演示 `set`，不调 `save`，避免改设备出厂后的开机行为。正式产品要开机即网卡再用 `save`。

---

## 3. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  set / save / get / saved                                │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  rndis 模块                                              │
│  · set：只改本次                                         │
│  · save：本次 + 开机策略                                 │
│  · 开关等到控制完成再返回                                │
└────────────────────────────┬────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         USB RNDIS      蜂窝数据承载     开机策略
         电脑侧网卡      （需已驻网）     （save 才写）
```

| 路径 | 调用当场做什么 | 是否让出协程 | 是否改开机策略 |
| --- | --- | --- | --- |
| `set` | 提交开/关，等到控制完成 | **否** | 否 |
| `save` | 同上，并写入开机策略 | **否** | **是** |
| `get` / `saved` | 读状态 | 否 | 否 |

---

## 4. 阻塞语义

`set` / `save` **不是** `rt.delay` 那种让出：当前协程停住，等到网卡控制完成才返回。其它 Lua 任务、定时器、IO 回调都要等。

`get` / `saved` 只读快照，很快。

不要在 UART / USB / MQTT 回调里调 `set`/`save`。

---

## 5. 常量与枚举

`luaopen` **没有**往模块表挂任何符号。比较状态用整数 `0` / `1`，不要发明 `rndis.ON`。

| 值 | `enable` / `saved` | `bound` |
| --- | --- | --- |
| `0` | 关 / 开机不自动 | 尚未绑上 |
| `1` | 开 / 开机自动 | 已绑定，电脑侧网卡可用 |

其它整数不要当查询结果的第三态。

---

## 6. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `enable`（入参） | boolean 或 integer | 见下 |
| `enable`（`get` 返回） | integer | `0` 或 `1` |
| `bound` | integer | `0` 或 `1` |
| `saved` | integer | `0` 或 `1` |

入参 `enable` 两条路：

| 传入类型 | 关 | 开 |
| --- | --- | --- |
| boolean | `false` | `true` |
| integer | `0` | 非 `0`（推荐只传 `1`） |

推荐脚本里统一用 `true`/`false`，或统一用 `0`/`1`。`nil`、字符串会抛类型错。

这里 **不是**「数字 `0` 当布尔真」：整数 `0` 明确为关。只有类型是 boolean 时才走布尔转换。

---

## 7. 模块函数

模块表只有 `set`、`save`、`get`、`saved`。

---

### 7.1 `rndis.set(enable)` {#7-1-set}

仅本次打开或关闭 USB 网卡，**不改**开机策略。重启后仍由 `saved()` 决定是否自动开。

**调用模式**

```lua
rndis.set(true)
```

```lua
rndis.set(false)
```

```lua
rndis.set(1)
```

```lua
rndis.set(0)
```

缺参或类型不对：抛错。

**返回**

- 成功：`true`
- 失败：`false, "fail"`

```lua
local ok, err = rndis.set(true)
if not ok then
    log.warn("set fail %s", err)
end
```

---

### 7.2 `rndis.save(enable)` {#7-2-save}

本次立刻开或关，并写入开机策略：开则以后上电自动当网卡；关则开机不再自动。

**调用模式**（与 `set` 相同的四种）

```lua
rndis.save(true)
```

```lua
rndis.save(false)
```

```lua
rndis.save(1)
```

```lua
rndis.save(0)
```

**返回**：同 `set`（`true` 或 `false, "fail"`）。

调试、临时共享请用 `set`。确定产品默认要网卡再用 `save(true)`。

---

### 7.3 `rndis.get()` {#7-3-get}

读本次运行状态。无参数。两个返回值都是整数 `0`/`1`，查询本身不走失败三返回值。

**调用模式**

```lua
rndis.get()
```

```lua
local enable, bound = rndis.get()
```

含义见 [第 8 节](#8-enable--bound--saved)。

---

### 7.4 `rndis.saved()` {#7-4-saved}

读开机策略。无参数。返回整数 `0`/`1`。

**调用模式**

```lua
rndis.saved()
```

```lua
local saved = rndis.saved()
```

`1`：开机自动打开。`0`：开机不自动（仍可用 `set(true)` 本次打开）。

---

## 8. `enable` / `bound` / `saved`

| 量 | 来源 | `1` 表示 |
| --- | --- | --- |
| `enable` | `get()` 第一返回值 | 本次已请求打开 |
| `bound` | `get()` 第二返回值 | USB 已绑定成功，电脑侧网卡可用 |
| `saved` | `saved()` | 开机自动打开 |

关系：

- `set(true)` 之后 `enable` 很快会变成 `1`；`bound` 还要等 USB 枚举和绑定，可能仍是 `0`。
- 没插 USB、电脑没装驱动、模组没驻网：常见 `enable=1` 且 `bound=0`。电脑这时上不了网。
- `set(false)` 只关本次；`saved()` 仍可能是 `1`，下次开机又会自动开。
- `save(false)` 才会把开机策略改成不自动。

电脑要上网：USB 已连接 + 模组已驻网 + `bound==1`。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `set` / `save` | `true` | `false, err` |
| `get` | `enable, bound`（整数） | 不走失败返回 |
| `saved` | 整数 `0`/`1` | 不走失败返回 |

没有数字业务码。`enable` 不是 boolean 也不是 integer：Lua 标准类型错。

**返回的 `err`**

| `err` | 可能原因 |
| --- | --- |
| `fail` | 本次开关或落盘失败：控制忙、提交被拒、USB 网卡状态不允许 |

`get` / `saved` 总是返回整数，即使硬件未插 USB。看 `bound` 是否为 1，不要用它们判断 `set` 成败。

---

## 10. 资源上限与生命周期

| 资源 | 说明 |
| --- | --- |
| 网卡实例 | 全机这一路 USB RNDIS，没有多路 `open` |
| 数据承载 | 固定默认 CID，脚本不能改 |
| 对象 | 无 userdata |
| `set`/`save` | 等到控制完成；忙或提交失败则 `false, "fail"` |

无回调、无需持有引用。关机后本次 `set` 丢失；`save` 的策略还在。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 临时给电脑上网 | USB 插上，`set(true)`，看 `bound` |
| 用完关掉，重启别自动开 | `set(false)`（若 `saved()` 已是 0） |
| 产品默认开机即网卡 | `save(true)` |
| 取消开机自动 | `save(false)` |
| 只查询 | `get()` / `saved()` |
| 电脑当 U 盘 / 纯 AT 口 | 不要开 RNDIS |
| 在回调里开关 | **不要** 调 `set`/`save` |

---

## 12. 完整示例

与仓库 [examples/nt26/network/rndis/rndis_api](../../../../examples/nt26/network/rndis/rndis_api) 一致：只 `set`，不 `save`，最后还原进入脚本前的本次开关。

```lua
local rt    = require("rt")
local log   = require("log")
local rndis = require("rndis")

local function dump(tag)
    local enable, bound = rndis.get()
    log.info("%s enable=%s bound=%s saved=%s",
             tag, enable, bound, rndis.saved())
end

local orig_enable = rndis.get()
dump("query")

local ok, err = rndis.set(true)
log.info("set on ok=%s err=%s", ok, tostring(err))
dump("after on")

ok, err = rndis.set(false)
log.info("set off ok=%s err=%s", ok, tostring(err))
dump("after off")

ok, err = rndis.set(orig_enable ~= 0)
log.info("restore ok=%s", ok)
dump("final")

while true do
    rt.delay(10000)
end
```

电脑实际上网请确认 USB 已连接、模组已驻网，并且 `bound` 变为 `1`。

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `rndis.set(true)` / `set(1)` | 本次打开 | `true` 或 `false, "fail"` |
| `rndis.set(false)` / `set(0)` | 本次关闭 | 同上 |
| `rndis.save(true)` / `save(1)` | 打开并开机自动 | 同上 |
| `rndis.save(false)` / `save(0)` | 关闭且开机不自动 | 同上 |
| `rndis.get()` | 本次状态 | `enable, bound` |
| `rndis.saved()` | 开机策略 | `0` 或 `1` |

## 附录 B. 枚举值一览

模块未导出符号。查询结果只用 `0` / `1`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：固定 `err` 文本 `fail` 与可能原因 |
