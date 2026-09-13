# lbs

**文档版本** `1.1.0`

同步基站定位。纯函数模块：向模组内置云端服务上报小区信息，换经纬度和（可选）地址。没有对象、没有 Lua 回调、没有 `open`。

```lua
local lbs = require("lbs")
```

平台预加载模块，无需额外 `.lua` 文件。不必填 PID。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `lbs.sync`](#6-1-sync)
  - [6.2 `lbs.cache`](#6-2-cache)
- [7. 请求配置](#7-请求配置)
- [8. 返回表](#8-返回表)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`lbs` 用当前驻留的蜂窝小区做云端定位。WiFi 热点请用 `wifiscan`。

1. **必须已经能上网**（PDP 激活）。可先 `lp.wait_link`，再 `sync`。
2. `lbs.sync([cfg])`：同步问一次。成功返回定位表；失败 `nil, err_code, err_msg`。
3. `lbs.cache()`：立刻读最近一次 **成功** 定位的经纬度，不再上网。从未成功过则失败。
4. `cfg` 里没写的 key 沿用 **当前运行配置**。想跳过某项就不要写，或写 `nil`。

这不是 TCP/MQTT 那种托管连接。Lua 侧没有周期定位接口；要周期性问，自己 `rt.delay` 后再 `sync`。

不要在 UART / MQTT / TCP 回调里调用 `sync`：会占住整条 Lua 引擎线程。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("lbs") → sync(cfg) / cache()                    │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  lbs 模块                                                │
│  · sync：提交一路定位，等到结果再返回                     │
│  · cache：读最近一次成功结果，不上网                      │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  定位任务                                                 │
│  取小区 → HTTP 问内置云端 → 写缓存                        │
│  全系统同时只跑一路；第二路立刻失败（忙）                  │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 要不要网 |
| --- | --- | --- | --- |
| `sync` | 提交定位并等到结束 | **否** | **必须**已驻网 |
| `cache` | 读成功缓存 | 否（立刻返回） | 不必 |

驻网后固件可能已经打过一路定位（例如开机后的一次）。`cache` 可能在第一次 `sync` 之前就有值。那一路还没结束时立刻 `sync`，会得到 `ERR_BUSY`。

---

## 3. 阻塞语义

`sync` **不是** `rt.delay` 那种让出：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 实际 HTTP 在独立定位任务里跑，但 Lua 引擎线程仍被这次调用占住，直到回调回来

超时按 `timeout_s` / `timeout_r` 和 `retry_count` 走。正式业务不要把超时开到十几秒以上。

`cache` 不阻塞在网络上。

同一时刻全系统只能有 **一路** 基站定位在飞。第二路（含另一次 `sync`、以及固件自己的定位）**立刻** `ERR_BUSY`，不会排队等。

---

## 4. 常量与枚举

### 4.1 定位模式（`cfg.lbs_mode`）

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `lbs.MODE_SINGLE_CELL` | `1` | 单基站。只上报当前服务小区。地址一般为空串 |
| `lbs.MODE_MULTI_CELL` | `2` | 多基站。上报服务小区和邻区，只要经纬度，成功后地址被清成空串 |
| `lbs.MODE_GEOCODE` | `3` | 多基站且尽量带地址（地理反编码） |

其它整数 **未挂到模块**，传入会提交失败（第二返回值常见 `-2`，文案 `"submit lbs request failed"`）。不要发明第四种模式。

### 4.2 错误码

| 符号 | 值 | 含义 | 谁会返回 |
| --- | --- | --- | --- |
| `lbs.ERR_OK` | `0` | 成功（只作对照；成功路径不走三返回值） | — |
| `lbs.ERR_BUSY` | `-4` | 已有一路定位在进行 | 仅 `sync` 提交阶段 |
| `lbs.ERR_TIMEOUT` | `-12` | HTTP / 定位超时 | `sync` 完成后 |

云端路径还会返回未导出的负数（第二返回值仍能见到，不要当模块符号去读）：

| 值 | 常见含义 |
| --- | --- |
| `-1` | 参数无效；或提交/等待失败、缓存未就绪（看 `err_msg`） |
| `-2` | 内存不足；或 `lbs_mode` 非法导致提交失败 |
| `-3` | 未驻网 / PDP 未激活 |
| `-4` | 取不到小区信息（与 `ERR_BUSY` 同值；`err_msg` 不同） |
| `-5` | 读不到 IMEI |
| `-7` / `-8` / `-9` / `-14` | HTTP 连接 / 发送 / 接收 / DNS |
| `-10` | 解析回包失败 |
| `-11` | 服务器错误 |

比较忙和超时时用 `lbs.ERR_BUSY`、`lbs.ERR_TIMEOUT`。区分 `-4` 是忙还是取小区失败：看第三返回值（`"lbs busy"` vs `"get cell info failed"`）。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `cfg` | table | 请求配置；省略 / `nil` = 沿用当前运行配置 |
| `resp` | table | `sync` 成功：见 [第 8.1 节](#81-sync-成功) |
| `cache` | table | `cache` 成功：只有 `longitude` / `latitude` |
| `err_code` | integer | `ERR_*` 或未导出负数 |
| `err_msg` | string | 英文短句，可能为空串 |

配置里的数字项走 **integer**。`false`/`nil` 表示「这项不改」。不要用 boolean 当 `0`/`1`。

`timeout_s` / `timeout_r` 负整数收成 `0`。`retry_count` 负整数收成 `0`，超过 255 收成 `255`。

---

## 6. 模块函数

模块表上只有 `sync`、`cache`。没有 `async`，没有 `open`。

---

### 6.1 `lbs.sync([cfg])` {#6-1-sync}

同步向内置云端要一次位置。成功返回定位表；失败 `nil, err_code, err_msg`。

必须已经驻网。占用 Lua 引擎线程直到结束。

**调用模式**

```lua
lbs.sync()
```

```lua
lbs.sync(nil)
```

```lua
lbs.sync(cfg)
```

第一参既不是 table 也不是 `nil`：抛类型错。`cfg` 里个别 key 不是 integer 也会抛。

常见表形态（仍属 `sync(cfg)`）：

```lua
lbs.sync({ lbs_mode = lbs.MODE_SINGLE_CELL })
```

```lua
lbs.sync({ lbs_mode = lbs.MODE_MULTI_CELL })
```

```lua
lbs.sync({ lbs_mode = lbs.MODE_GEOCODE })
```

```lua
lbs.sync({ lbs_mode = lbs.MODE_GEOCODE, timeout_s = 5, timeout_r = 8 })
```

```lua
lbs.sync({ timeout_s = 5, timeout_r = 8, retry_count = 2 })
```

**返回**

- 成功：定位表，见 [第 8.1 节](#81-sync-成功)
- 失败：`nil, err_code, err_msg`

```lua
if not lp.wait_link(60000) then
    return
end
local resp, code, msg = lbs.sync({ lbs_mode = lbs.MODE_GEOCODE })
if not resp then
    log.warn("lbs fail %s %s", code, msg)
    return
end
log.info("%s %s %s", resp.longitude, resp.latitude, resp.address)
```

---

### 6.2 `lbs.cache()` {#6-2-cache}

立刻返回最近一次 **成功** 基站定位的经纬度，不再发起网络请求。

函数名是 `cache`，不是 `get_cache`。无参数。

**调用模式**

```lua
lbs.cache()
```

**返回**

- 成功：`{ longitude, latitude }`（字符串；无 `address` / `precision`）
- 失败：`nil, err_code, err_msg`。`err_msg` 固定 `"lbs cache not ready"`。从未成功定位、或模块未就绪时都会失败。

设备几乎不动、只要粗位置时，可以只读缓存。缓存会被任何成功的基站定位刷新（包括本次 `sync` 之前固件自己打过的那次）。

```lua
local cache, code, msg = lbs.cache()
if cache then
    log.info("cache %s %s", cache.longitude, cache.latitude)
else
    log.info("cache empty %s %s", code, msg)
end
```

---

## 7. 请求配置

`sync(cfg)` 认这些 key。没写的保持 **当前运行配置**（不是一张写死的空表）。

出厂运行配置：

| key | 出厂值 |
| --- | --- |
| `lbs_mode` | `MODE_SINGLE_CELL`（`1`） |
| `timeout_s` | `3` |
| `timeout_r` | `3` |
| `retry_count` | `1` |

其它通道若改过定位参数，未写的 key 跟那份运行配置走。Lua **写不了** 周期上报、精度、PID、PDP 等项。

| key | 类型 | 省略 | 写 `0` | 说明 |
| --- | --- | --- | --- | --- |
| `lbs_mode` | integer | 当前运行配置 | 非法（不是 1/2/3） | 必须用上面三个 `MODE_*` |
| `timeout_s` | integer | 当前运行配置 | 协议层发送超时默认 **2** 秒 | HTTP 发送超时（秒） |
| `timeout_r` | integer | 当前运行配置 | 协议层接收超时默认 **5** 秒 | HTTP 接收超时（秒） |
| `retry_count` | integer | 当前运行配置 | 协议层重试默认 **2** | HTTP 重试次数 |

省略和写 `0` **不是**一回事：省略保留运行配置（出厂 3/3/1）；`0` 交给协议层内置默认（2/5/2）。

精度小数位 Lua 配不了，走协议层默认（一般为 6）。

---

## 8. 返回表

### 8.1 `sync` 成功 {#81-sync-成功}

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `longitude` | string | 经度 |
| `latitude` | string | 纬度 |
| `address` | string | 地址；`MODE_GEOCODE` 才常有，其余多为 `""` |
| `precision` | integer | 小数位数 |
| `server_err_code` | integer | 云端业务码，成功一般为 `0` |
| `server_err_msg` | string | 云端说明，可能为空串 |

坐标是字符串，方便保持小数位。需要运算时再 `tonumber`。

### 8.2 `cache` 成功

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `longitude` | string | 经度 |
| `latitude` | string | 纬度 |

没有地址、没有精度。经纬度最长约 31 个可见字符。

---

## 9. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `sync` | 定位表 | `nil, err_code, err_msg` |
| `cache` | `{ longitude, latitude }` | `nil, err_code, err_msg` |

配置不是 table、数字 key 不是 integer：抛 Lua 类型错，不是三返回值。

模块只导出 `lbs.ERR_OK`（`0`）、`lbs.ERR_BUSY`（`-4`）、`lbs.ERR_TIMEOUT`（`-12`）。其它负数仍会出现在第二返回值里，按下面全表认。

**同一数字可能对应不同文案**：`-1` 既可能是定位参数非法，也可能是提交阶段的通用失败。**先看 `err_msg`。**

| `err_code` | `err_msg` | 可能原因 |
| --- | --- | --- |
| `-4` | `lbs busy` | 已有一路 `sync` 没结束；等它完再调 |
| `-1` | `create semaphore failed` | 同步等待对象没建起来，系统资源 |
| `-1` | `wait lbs callback failed` | 等结果时被打断或信号异常 |
| （提交返回值） | `submit lbs request failed` | 模式非法、模块未就绪、参数被应用层拒（常见 `-2`） |
| （加载返回值） | `load lbs config failed` | 配置表写进内部失败 |
| `0` | （成功不走这里） | — |
| `-1` | `invalid param` | 定位参数无效（与上面 `-1` 文案不同） |
| `-2` | `memory alloc failed` | 组包/缓冲分配失败 |
| `-3` | `network not ready` | 未驻网；先 `lp.wait_link` |
| `-4` | `get cell info failed` | **注意：** 完成后的 `-4` 文案若是这句，是读基站失败，不是 busy。busy 的文案一定是 `lbs busy` |
| `-5` | `get imei failed` | 读不到 IMEI |
| `-6` | `get pid failed` | 读不到产品 ID |
| `-7` | `http connect failed` | 定位服务器 TCP 连不上 |
| `-8` | `http send failed` | 请求没发出去 |
| `-9` | `http recv failed` | 响应没收全 |
| `-14` | `http dns failed` | 定位域名解析失败 |
| `-10` | `parse response failed` | 云端回包不是预期 JSON/字段 |
| `-11` | `server response error` | 云端业务错误，可看结果表里的 `server_err_msg`（成功路径才有表） |
| `-12` | `timeout` | HTTP/整体超时 |
| `-13` | `get wifi scan failed` | 本模块基站定位一般碰不到；Wi‑Fi 定位见 [`wifiscan`](wifiscan.md) |
| 其它 | `unknown error` | 未翻译的码 |

`cache`：尚未成功过 `sync` 时 `nil, err_code, "lbs cache not ready"`。`err_code` 为内部未就绪码，**认文案**。

诊断：`lbs busy` 等上一趟；`network not ready` / `http dns` 查驻网；`get cell info` 查天线和是否已注册小区；`timeout` 加大超时或查服务器。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 并发定位 | 1 路 | 第二路立刻 `ERR_BUSY` |
| 出厂发送/接收超时 | 3 s / 3 s | `sync` 省略超时项时 |
| 协议层超时（cfg 里写 `0`） | 2 s / 5 s | 发送 / 接收 |
| 出厂 HTTP 重试 | 1 | 写 `0` 则协议层按 2 |
| 经纬度缓存 | 最近一次成功 | 失败不会清掉旧缓存 |
| 地址缓冲 | 最长 255 字节可见字符 | 仅 `sync` 结果表 |

无对象、无回调槽。不需要持有引用。`sync` 成功会刷新 `cache()` 读到的内容。

---

## 11. 选型对照

| 需求 | 做法 |
| --- | --- |
| 要经纬度，尽快 | `sync({ lbs_mode = lbs.MODE_SINGLE_CELL })` |
| 多小区、更稳一点 | `MODE_MULTI_CELL` |
| 还要地址文本 | `MODE_GEOCODE` |
| 已经定位过、先看旧值 | `lbs.cache()` |
| 周围 WiFi 热点 / WiFi 定位 | `wifiscan`，不是本模块 |
| 周期定位 | 独立任务里 `rt.delay` 后再 `sync` |
| 在回调里定位 | **不要** 调 `sync` |
| 碰上忙 | 稍后再试，或先读 `cache` |

---

## 12. 完整示例

与仓库 [examples/NT26/network/lbs/lbs_api](../../../../examples/NT26/network/lbs/lbs_api) 一致：先等网，读缓存，再依次打单基站、多基站、带地址。

```lua
local rt  = require("rt")
local log = require("log")
local lp  = require("lp")
local lbs = require("lbs")

local function dump_loc(tag, resp, err_code, err_msg)
    if resp then
        log.info("%s lon=%s lat=%s addr=%s prec=%s",
                 tag, resp.longitude, resp.latitude, resp.address, resp.precision)
        return true
    end
    log.warn("%s fail code=%s msg=%s", tag, err_code, err_msg)
    return false
end

if not lp.wait_link(60000) then
    log.warn("网络超时，没有网络无法测试 lbs")
    while true do
        rt.delay(10000)
    end
end

local cache, c_err, c_msg = lbs.cache()
if cache then
    log.info("cache lon=%s lat=%s", cache.longitude, cache.latitude)
else
    log.info("cache empty code=%s msg=%s", c_err, c_msg)
end

dump_loc("single", lbs.sync({ lbs_mode = lbs.MODE_SINGLE_CELL }))
dump_loc("multi", lbs.sync({ lbs_mode = lbs.MODE_MULTI_CELL }))
dump_loc("geocode", lbs.sync({ lbs_mode = lbs.MODE_GEOCODE }))

while true do
    rt.delay(10000)
end
```

`dump_loc` 直接接 `lbs.sync(...)` 的多返回值：成功时第一参是表，失败时后两个是码和文案。

若刚驻网就 `ERR_BUSY`，等一两秒再 `sync`，或先用 `cache`。

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `lbs.sync()` | 按当前运行配置定位 | 定位表或 `nil, code, msg` |
| `lbs.sync(nil)` | 同上 | 同上 |
| `lbs.sync(cfg)` | 覆盖表里写到的项 | 同上 |
| `lbs.cache()` | 读成功缓存 | `{ longitude, latitude }` 或 `nil, code, msg` |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `lbs.MODE_SINGLE_CELL` | 1 |
| `lbs.MODE_MULTI_CELL` | 2 |
| `lbs.MODE_GEOCODE` | 3 |
| `lbs.ERR_OK` | 0 |
| `lbs.ERR_BUSY` | -4 |
| `lbs.ERR_TIMEOUT` | -12 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全 err_code/err_msg 全表与可能原因，并说明 -1/-4 要先看文案 |
