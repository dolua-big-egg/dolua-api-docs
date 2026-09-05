# wifiscan

**文档版本** `1.1.0`

同步 WiFi 扫描与云端 WiFi 定位。纯函数模块：`scan` 扫周围 AP，`location` 先扫再向云端要经纬度。没有对象、没有回调、没有后台轮询。

```lua
local wifiscan = require("wifiscan")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `wifiscan.scan`](#6-1-scan)
  - [6.2 `wifiscan.location`](#6-2-location)
- [7. 扫描配置](#7-扫描配置)
- [8. 定位配置](#8-定位配置)
- [9. 返回表](#9-返回表)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

模组本身没有独立 WiFi 网卡，扫描走蜂窝侧的 WiFi 嗅探。`scan` 只要射频能工作；`location` 还要把扫到的 AP 送到云端，**必须已经能上网**。

1. `wifiscan.scan([cfg])`：同步扫一圈，返回 AP 列表。扫不到也算成功，得到空表 `{}`。
2. `wifiscan.location([cfg])`：先扫，AP 数量够了再 HTTP 问 DoIoT 云端，返回经纬度和地址。
3. 两个接口都是当场做完。失败是 `nil, err_code, err_msg` 三个返回值。
4. 配置表里没写的 key 保持默认。想跳过某项就不要写，或写 `nil`。

这不是 TCP/MQTT 那种托管连接，也不会在后台持续扫描。要周期性定位，自己 `rt.delay` 后再调。

不要在 UART / MQTT / TCP 回调里调用：扫描默认就要等十几秒，会把整条 Lua 引擎线程堵住。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("wifiscan") → scan(cfg) / location(cfg)         │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  wifiscan 模块                                           │
│  · 填扫描 / 定位参数（缺省用默认）                        │
│  · 同步等到结果或失败                                    │
└────────────────────────────┬────────────────────────────┘
              │                              │
              ▼                              ▼
┌─────────────────────┐          ┌────────────────────────┐
│  WiFi 嗅探           │          │  云端定位               │
│  扫 AP 列表          │          │  先扫，再 HTTP 上报     │
│  不必先驻网          │          │  必须已 PDP             │
└─────────────────────┘          └────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 要不要网 |
| --- | --- | --- | --- |
| `scan` | 嗅探周围 AP | **否** | 不必驻网 |
| `location` | 嗅探 + 云端定位 | **否** | **必须**已驻网 |

全系统同时只能跑 **一路** 扫描。第二路会等到第一路结束。

---

## 3. 阻塞语义

两个函数都 **不是** `rt.delay` 那种让出：

- 当前协程停住
- 其它 Lua 任务、定时器、IO 回调都要等它结束
- 默认扫描总超时 12000 ms；`location` 还要加上 HTTP 发送/接收超时（默认各 10 秒）和有限次重试

超时开得太大，整机业务会卡住。正式业务把扫描丢到独立任务里跑。

`scan` 失败不会自己重试。`location` 的 HTTP 段按 `retry_count` 重试（默认 2）；扫描失败则整次失败。

---

## 4. 常量与枚举

模块表只导出错误码，没有扫描档位符号。比较失败码时用这些符号。

| 符号 | 值 | 含义 | 谁会返回 |
| --- | --- | --- | --- |
| `wifiscan.ERR_OK` | `0` | 成功（只作对照；成功路径不走这个三返回值） | — |
| `wifiscan.ERR_INVALID_PARAM` | `-1` | 参数无效。`scan` 在底层拒参时返回；`location` 主要是 AP 数少于 `min_ap_count` | `scan` / `location` |
| `wifiscan.ERR_NETWORK_NOT_READY` | `-3` | 未驻网 / PDP 未激活 | 仅 `location` |
| `wifiscan.ERR_GET_IMEI` | `-5` | 读不到 IMEI | 仅 `location` |
| `wifiscan.ERR_PARSE_RESPONSE` | `-10` | 云端回包解析失败，或经纬度为空 | 仅 `location` |
| `wifiscan.ERR_TIMEOUT` | `-12` | 扫描或 HTTP 超时 | `scan` / `location` |
| `wifiscan.ERR_GET_WIFI_SCAN` | `-13` | 扫描失败（含忙、参数不被底层接受） | `scan` / `location` |

底层还有内存不足、HTTP 连接/发送/接收/DNS、服务器错误等负数，**没有挂到模块表**。失败时第二返回值仍是这些整数，第三返回值是英文短句。不要发明 `wifiscan.ERR_HTTP_RECV` 这类符号。

`wifi_priority` 用整数 `0` / `1`，没有模块常量：

| 值 | 含义 |
| --- | --- |
| `0` | 数据优先（默认） |
| `1` | WiFi 扫描优先 |

其它值未导出，不要当可用档位。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `cfg` | table | 扫描或定位配置；省略 / `nil` = 全默认 |
| `scan_list` | table（数组） | 1 起下标；元素是 AP 表 |
| `ap` | table | `ssid` / `rssi` / `bssid` / `channel` |
| `resp` | table | 定位结果，见第 9 节 |
| `err_code` | integer | `ERR_*` 或未导出负数 |
| `err_msg` | string | 英文短句，可能为空串 |
| `channel_id` | table | 1 起下标的信道号数组 |

配置里的数字项走 **integer**。`false`/`nil` 表示「这项不改」；不要用 boolean 当 `0`/`1`。负数在多数 8 位项里会被收成 `0`，超过 255 收成 `255`。

---

## 6. 模块函数

模块表上只有 `scan`、`location`。

---

### 6.1 `wifiscan.scan([cfg])` {#6-1-scan}

同步扫周围 AP。成功返回数组；失败返回 `nil, err_code, err_msg`。

不必先 `lp.wait_link`。一个 AP 都没有时仍成功，得到 `{}`。

**调用模式**

```lua
wifiscan.scan()
```

```lua
wifiscan.scan(nil)
```

```lua
wifiscan.scan(cfg)
```

第一参既不是 table 也不是 `nil`：抛类型错。`cfg` 里个别 key 类型不对也会抛（例如 `channel_id` 不是 table）。

**返回**

- 成功：AP 数组（可能为空）
- 失败：`nil, err_code, err_msg`。`err_msg` 固定为 `"wifi scan failed"`

```lua
local list, code, msg = wifiscan.scan()
if not list then
    log.warn("scan fail %s %s", code, msg)
    return
end
for i = 1, #list do
    local ap = list[i]
    log.info("%s rssi=%s ch=%s mac=%s", ap.ssid, ap.rssi, ap.channel, ap.bssid)
end
```

---

### 6.2 `wifiscan.location([cfg])` {#6-2-location}

先扫描，再把 AP 列表交给 DoIoT 云端定位。成功返回结果表；失败 `nil, err_code, err_msg`。

**必须已经驻网。** 扫到的 AP 少于 `min_ap_count`（默认 5）会 `ERR_INVALID_PARAM`。经纬度任一为空会 `ERR_PARSE_RESPONSE`（`"wifi location empty result"`）。

**调用模式**

```lua
wifiscan.location()
```

```lua
wifiscan.location(nil)
```

```lua
wifiscan.location(cfg)
```

`cfg.scan` 若出现，必须是 table，里面的 key 与 `scan` 的配置相同。

**返回**

- 成功：定位表，见 [第 9.2 节](#92-定位结果)
- 失败：`nil, err_code, err_msg`（`err_msg` 来自错误码对应的英文短句，或空结果那句）

```lua
if not lp.wait_link(60000) then
    return
end
local resp, code, msg = wifiscan.location({ min_ap_count = 5 })
if not resp then
    log.warn("loc fail %s %s", code, msg)
    return
end
log.info("%s %s %s", resp.longitude, resp.latitude, resp.address)
```

---

## 7. 扫描配置

`scan(cfg)` 的表，以及 `location({ scan = ... })` 里的嵌套 `scan` 表，认同一套 key。没写的保持默认。

| key | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `max_time_out_ms` | integer | `12000` | 整次扫描总超时（毫秒） |
| `round` | integer | `1` | 扫描轮数 |
| `max_bssid_num` | integer | `5` | 最多上报多少个 AP，上限 40 |
| `scan_timeout_s` | integer | `5` | 每轮超时（秒） |
| `wifi_priority` | integer | `0` | `0` 数据优先；`1` 扫描优先 |
| `channel_rec_len_ms` | integer | `280` | 每个信道停留（毫秒） |
| `channel_count` | integer | `1` | 信道个数 |
| `channel_id` | table | `{0}` | 信道列表，Lua 下标从 1 起。最多 14 个，读到第一个 `nil` 就停 |

`channel_count == 1` 且 `channel_id[1] == 0` 表示 **全信道**。这是默认。

只写 `channel_id = {1, 6, 11}`、不改 `channel_count` 时，个数仍是默认 `1`，实际只用第一项。指定信道时请两个一起写：

```lua
wifiscan.scan({
    channel_count = 3,
    channel_id = {1, 6, 11},
    max_bssid_num = 10,
    max_time_out_ms = 15000,
})
```

建议：`max_time_out_ms >= round * scan_timeout_s * 1000`，否则底层可能直接失败。

与 AT 扫描命令常用范围对齐（绑定不强制卡死，越界可能底层失败）：

| key | 常用范围 |
| --- | --- |
| `max_time_out_ms` | 4000～255000 |
| `round` | 1～3 |
| `max_bssid_num` | 4～40 |
| `scan_timeout_s` | 1～255 |
| `wifi_priority` | 0 / 1 |
| `channel_rec_len_ms` | 100～280 |
| `channel_count` | 1～14 |

未出现在表里的内部项（指定单个 BSSID 等）Lua 配不了。

---

## 8. 定位配置

`location(cfg)` 除嵌套 `scan` 外，还认这些 key。值为 `0` 的项按「用默认」处理（与省略相同）。

| key | 类型 | 默认（写 0 / 省略时） | 说明 |
| --- | --- | --- | --- |
| `timeout_s` | integer | `10` | HTTP 发送超时（秒） |
| `timeout_r` | integer | `10` | HTTP 接收超时（秒） |
| `pdp_id` | integer | `1` | PDP 上下文；`0` 回落到 1 |
| `retry_count` | integer | `2` | HTTP 重试次数；`0` 回落到 2 |
| `precision` | integer | `6` | 经纬度小数位，合法 1～8；`0` 或越界用 6 |
| `min_ap_count` | integer | `5` | 最少 AP 数；不够则 `ERR_INVALID_PARAM` |
| `scan` | table | 与 `scan()` 相同的默认扫描参 | 同第 7 节 |

```lua
wifiscan.location({
    min_ap_count = 3,
    precision = 6,
    timeout_s = 10,
    timeout_r = 10,
    scan = {
        max_bssid_num = 10,
        max_time_out_ms = 15000,
    },
})
```

室内 AP 少时把 `min_ap_count` 调低；低于云端能算出来的密度时，结果会变差或失败。

---

## 9. 返回表

### 9.1 AP 列表元素

`scan` 成功时返回数组，`list[i]`：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `ssid` | string | SSID；隐藏网络为空串 |
| `rssi` | integer | 信号强度（dBm，一般为负） |
| `bssid` | string | MAC，形如 `"AA:BB:CC:DD:EE:FF"` |
| `channel` | integer | 信道，常见 1～13 |

SSID 最长 32 字节（不含结尾 0）。下标从 1 起，与 `#list` 一致。

### 9.2 定位结果

`location` 成功时：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `longitude` | string | 经度 |
| `latitude` | string | 纬度 |
| `address` | string | 地址文本，可能为空 |
| `precision` | integer | 小数位数（1～8） |
| `server_err_code` | integer | 云端业务码，成功一般为 `0` |
| `server_err_msg` | string | 云端说明，可能为空串 |

坐标是字符串，方便保持小数位。需要运算时再 `tonumber`。

---

## 10. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `scan` | AP 数组（可为 `{}`） | `nil, err_code, err_msg` |
| `location` | 定位表 | `nil, err_code, err_msg` |

配置不是 table、`channel_id` / `scan` 不是 table、数字 key 不是 integer：抛 Lua 类型错，不是三返回值。

`scan` 失败时 `err_msg` 都是 `"wifi scan failed"`，用 `err_code` 区分。`location` 扫描阶段：超时 `ERR_TIMEOUT`，其余扫描失败 `ERR_GET_WIFI_SCAN`。定位阶段文案与 [`lbs`](lbs.md) 完成后同一套英文短句。

未导出但会出现的码：

| `err_code` | 典型 `err_msg` | 可能原因 |
| --- | --- | --- |
| `-2` | `memory alloc failed` | 组包失败 |
| `-6` | `get pid failed` | 读不到产品 ID |
| `-7` / `-8` / `-9` / `-14` | `http connect/send/recv/dns failed` | 定位云连不上；先驻网 |
| `-11` | `server response error` | 云端业务错 |
| `-10` | `parse response failed` 或 `wifi location empty result` | 回包坏，或经纬度为空 |

`location` AP 少于 `min_ap_count`：`ERR_INVALID_PARAM`。诊断：`scan` 空表不是失败；`location` 先保证扫到足够 AP 且已驻网。

---

## 11. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 一次上报 AP | 40 | `max_bssid_num` 默认 5 |
| 信道列表 | 14 | `channel_id` 最多读 14 项 |
| SSID | 32 字节 | 超出截断 |
| BSSID 字符串 | `"AA:BB:CC:DD:EE:FF"` | 大写十六进制，冒号分隔 |
| 并发扫描 | 1 路 | 第二路等待 |
| 默认扫描总超时 | 12000 ms | `max_time_out_ms` |
| 定位最少 AP | 5 | `min_ap_count` |
| 经纬度小数位 | 1～8 | 默认 6 |

无对象、无回调槽。不需要持有引用。

---

## 12. 选型对照

| 需求 | 做法 |
| --- | --- |
| 只要周围热点 | `wifiscan.scan()` |
| 扫更多 AP | `scan({ max_bssid_num = 20 })` |
| 只扫 1/6/11 | `channel_count` 与 `channel_id` 一起设 |
| 要经纬度 | 先 `lp.wait_link`，再 `location()` |
| 室内 AP 少 | `location({ min_ap_count = 3 })` |
| 扫描参数带进定位 | `location({ scan = { ... } })` |
| 周期性定位 | 独立任务里 `rt.delay` 后再调 |
| 在回调里扫 | **不要** |

---

## 13. 完整示例

仓库里目前没有单独的 wifiscan demo。下面可直接跑：先扫一圈打日志，有网再定位。

```lua
local rt       = require("rt")
local log      = require("log")
local lp       = require("lp")
local wifiscan = require("wifiscan")

local function dump_scan(list)
    log.info("scan count=%d", #list)
    for i = 1, #list do
        local ap = list[i]
        log.info("[%d] ssid=%s rssi=%s ch=%s bssid=%s",
                 i, ap.ssid, ap.rssi, ap.channel, ap.bssid)
    end
end

local list, code, msg = wifiscan.scan({
    max_bssid_num = 10,
    max_time_out_ms = 15000,
})
if not list then
    log.warn("scan fail code=%s msg=%s", code, msg)
else
    dump_scan(list)
end

if not lp.wait_link(60000) then
    log.warn("网络超时，跳过 location")
else
    local resp
    resp, code, msg = wifiscan.location({
        min_ap_count = 5,
        precision = 6,
        scan = { max_bssid_num = 10, max_time_out_ms = 15000 },
    })
    if not resp then
        log.warn("location fail code=%s msg=%s", code, msg)
        if code == wifiscan.ERR_NETWORK_NOT_READY then
            log.warn("未驻网")
        elseif code == wifiscan.ERR_INVALID_PARAM then
            log.warn("AP 数量不够")
        end
    else
        log.info("lon=%s lat=%s addr=%s prec=%s",
                 resp.longitude, resp.latitude, resp.address, resp.precision)
    end
end

while true do
    rt.delay(10000)
end
```

---

## 附录 A. 方法速查

| 调用 | 动作 | 返回 |
| --- | --- | --- |
| `wifiscan.scan()` | 默认参数扫 AP | 数组或 `nil, code, msg` |
| `wifiscan.scan(nil)` | 同上 | 同上 |
| `wifiscan.scan(cfg)` | 按表扫 | 同上 |
| `wifiscan.location()` | 默认扫 + 云端定位 | 定位表或 `nil, code, msg` |
| `wifiscan.location(nil)` | 同上 | 同上 |
| `wifiscan.location(cfg)` | 可带 `min_ap_count` / `scan` 等 | 同上 |

## 附录 B. 枚举值一览

| 符号 | 值 |
| --- | --- |
| `wifiscan.ERR_OK` | 0 |
| `wifiscan.ERR_INVALID_PARAM` | -1 |
| `wifiscan.ERR_NETWORK_NOT_READY` | -3 |
| `wifiscan.ERR_GET_IMEI` | -5 |
| `wifiscan.ERR_PARSE_RESPONSE` | -10 |
| `wifiscan.ERR_TIMEOUT` | -12 |
| `wifiscan.ERR_GET_WIFI_SCAN` | -13 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.1.0 | 2026-09-05 | 补全未导出错误码、文案与可能原因 |
