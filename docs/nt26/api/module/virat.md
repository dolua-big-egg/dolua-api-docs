# virat

**文档版本** `1.1.0`

纯函数虚拟 AT：在 Lua 里同步发一条指令、收回显。没有对象、没有回调。两条路 **不是同一个解析器，命令集不通**。

```lua
local virat = require("virat")
```

平台预加载模块，无需额外 `.lua` 文件。

能用 [`info`](info.md) / [`sys`](sys.md) / [`dns`](../network/dns.md) 等 Lua API 办到的事，不要走本模块。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `virat.exec`](#6-1-exec)
  - [6.2 `virat.ril_exec`](#6-2-ril-exec)
- [7. 原厂 EC 通道（严重警告）](#7-原厂-ec-通道严重警告)
- [8. 错误与返回约定](#8-错误与返回约定)
- [9. 资源上限与生命周期](#9-资源上限与生命周期)
- [10. 选型对照](#10-选型对照)
- [11. 完整示例](#11-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

两套接口：

| 接口 | 对接谁 | 什么时候用 |
| --- | --- | --- |
| `virat.exec` | **度云未来**已注册的应用层 AT | 常规：串口/远程 AT 同一套指令，在脚本里同步拿回显 |
| `virat.ril_exec` | **原厂 EC 内置** AT 引擎 | **仅**特殊场合做功能补充；日常业务不要走这条 |

两条路互不转发：`exec` 打不到的原厂指令，不会自动去 `ril_exec`；反过来也一样。不要拿同一条命令两边都试「看谁通」。

`exec` 是给脚本对接度云未来 AT 用的。`ril_exec` 直通芯片原厂指令，能改射频、NV、鉴权一类底层状态。误发可能导致模块异常或损坏。使用条件见 [第 7 节](#7-原厂-ec-通道严重警告)。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  exec / ril_exec                                         │
└───────────────┬─────────────────────────┬───────────────┘
                │                         │
                ▼                         ▼
┌───────────────────────────┐  ┌───────────────────────────┐
│  exec                     │  │  ril_exec                 │
│  度云未来 AT 解析          │  │  原厂 EC 内置引擎         │
│  回显回到第二个返回值      │  │  等到出现 OK / ERROR      │
└───────────────────────────┘  └───────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `exec` | 同步解析一条度云未来 AT，收齐回显再返回 | **否** |
| `ril_exec` | 同步交给原厂引擎，等到结束或超时 | **否**（可能占住整条 Lua 引擎线程数秒到数十秒） |

没有回调。响应不会再抄到 USB/UART AT 口，除非该条度云未来指令自己还往某路串口写（这时才用得上 `route_id`）。

---

## 3. 阻塞语义

全部同步。当前协程和整条 Lua 引擎线程都会等到这条 AT 结束。`ril_exec` 的等待上限与 `timeout_ms` 有关，期间其它 Lua 任务、心跳都跑不了。不要在定时器回调里调用。

---

## 4. 常量与枚举

模块表 **没有** 导出整数常量。超时默认值、回显上限见 [第 9 节](#9-资源上限与生命周期)，不是 `virat.xxx` 符号。

---

## 5. 类型约定

| 文档用名 | Lua 类型 | 说明 |
| --- | --- | --- |
| `at_cmd` | string | 完整 AT 行。建议以 `\r\n` 结尾；`ril_exec` **至少**要以 `\r` 结尾 |
| `route_id` | integer | 可选，默认 `0`。见 [6.1](#6-1-exec) |
| `timeout_ms` | integer | 可选。省略或 `nil` 为 **10000**；显式传 `0` 就是 0，不是默认 |
| `ok` | boolean | 见各接口；**不是**「这条 AT 业务一定成功」 |
| `resp` | string | 原始回显，可能含 `\r` `\n`；没有正文时是空串 |

`at_cmd` 不是 string 时 **抛错**。业务失败走 `ok == false`，一般不抛。

---

## 6. 模块函数

### 6.1 `virat.exec(at_cmd [, route_id])` {#6-1-exec}

把一条指令交给 **度云未来** 已注册的 AT 解析，同步返回回显。

**调用模式**

```lua
ok, resp = virat.exec(at_cmd)
```

```lua
ok, resp = virat.exec(at_cmd, route_id)
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `at_cmd` | string | 是 | — | 完整一行，建议 `"AT+IMEI\r\n"` 这种带结尾 |
| `route_id` | integer | 否 | `0` | 该指令若还要往某路串口/通道回写才需要改；Lua 已经能从 `resp` 拿到回显，日常保持默认 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 解析流程走完 | `ok` 为 `true`，`resp` 为回显（可能仍是 `+CME ERROR: …`） |
| 解析未能开始（空串、内部失败等） | `false, ""` 或 `false` + 已有正文 |

`ok == true` 只表示「解析器收了这条命令」。指令未注册时，常见仍是 `ok == true`，`resp` 里是 `+CME ERROR: 1`（未注册）。请读 `resp` 判断业务成败，不要只看 `ok`。

未注册的原厂指令 **不会** 转去 `ril_exec`。

有对应 Lua API 时请走 Lua，不要用 `exec` 当查询封装：

| AT 例子 | 优先 |
| --- | --- |
| `AT+IMEI` | [`info.imei`](info.md) |
| `AT+ICCID` / `AT+IMSI` | [`info.iccid`](info.md) / [`info.imsi`](info.md) |
| `AT+CSQ` / `AT+CEREG` | [`info.csq`](info.md) / [`info.cereg`](info.md) |
| `AT+VERSION` | [`sys.version`](sys.md) |
| `AT+UTC` | [`info.timestamp`](info.md) |

**示例**

```lua
local ok, resp = virat.exec("ATI\r\n")
log.info("ok=%s resp=%s", tostring(ok), resp)
```

---

### 6.2 `virat.ril_exec(at_cmd [, timeout_ms])` {#6-2-ril-exec}

把一条指令交给 **原厂 EC 内置** AT 引擎，等到回显里出现 `OK` 或 `ERROR`（含 `+CME ERROR` / `+CMS ERROR` 等），或等到超时。

**调用本接口前必须先读 [第 7 节](#7-原厂-ec-通道严重警告)。** 不是「多一条 AT 入口」，是直通芯片原厂命令集。

**调用模式**

```lua
ok, resp = virat.ril_exec(at_cmd)
```

```lua
ok, resp = virat.ril_exec(at_cmd, timeout_ms)
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `at_cmd` | string | 是 | — | 必须以 `\r` 结尾（`\r\n` 可以） |
| `timeout_ms` | integer | 否 | `10000` | 等待原厂引擎的毫秒数。请传非负整数 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 发送成功且 `resp` 中出现 `"OK"` | `true, resp` |
| 空命令 | `false, ""` |
| 发送失败、超时、回显只有 `ERROR`、本固件未开此通道 | `false, resp` |

`ok` 用回显文本里是否出现子串 `"OK"` 判断。`ERROR` 而没有 `OK` 时 `ok` 为 `false`，但 `resp` 仍可能有正文，请保存下来给支持人员。

空命令不会进引擎。`at_cmd` 不是 string 时 **抛错**。

部分固件未打开原厂 AT 通道：`ok == false`，`resp == "FEATURE_RIL_AT_API_ENABLE off"`。此时不要再重试，这条路对本机不可用。

`resp` 最长约 **4096** 字节，超出会截断。

---

## 7. 原厂 EC 通道（严重警告）

`virat.ril_exec` 只应用在 **度云未来书面指导** 的特殊场合，用来补度云未来 AT / Lua API 尚未覆盖的能力。它不是通用 AT 调试口。

1. **不要自己编、不要从网上抄、不要拿模组原厂手册逐条试。** 原厂指令能改射频、存储、校准和鉴权相关状态。发错可能导致模块工作异常或硬件损坏。
2. **必须先知道这条 EC 指令在本产品上的准确写法、参数和后果**，并且是本公司给出的用法。没有指导就当这个接口不存在。
3. 因擅自调用 `ril_exec`（含乱发原厂指令）造成的模块损坏、失效或数据丢失，**不在保修、换货范围内**。
4. **模块会记录对本接口的调用。** 售后、失效分析时可以核对是否使用过原厂通道。

日常查询身份、信号、版本、DNS：用 [`info`](info.md)、[`sys`](sys.md)、[`dns`](../network/dns.md)，或 `virat.exec` 打度云未来已注册指令。不要为了「AT 比较熟」就走 `ril_exec`。

---

## 8. 错误与返回约定

两套接口都返回 `ok, resp`，**没有数字业务码**。业务失败不抛（缺参除外）。判断顺序：先看有没有抛；再看 `ok`；最后读 `resp`。

| 接口 | 成功形态 | 失败形态 | 缺参 |
| --- | --- | --- | --- |
| `exec` | `true, resp`（`resp` 里仍可能是 CME 错误） | `false, resp`（常为空串） | `at_cmd` 非 string：**抛** |
| `ril_exec` | `true, resp`（文本里含 `OK`） | `false, resp` | 同上 |

**`ok` 怎么判定（两套不一样）**

| 接口 | `ok == true` 的条件 | `ok == false` 时 `resp` |
| --- | --- | --- |
| `exec` | 度云未来 AT 解析成功（返回码为 0） | 解析失败时常为 `""`；成功时也可能是带 CME 的正文 |
| `ril_exec` | **发送成功且** 回显文本里能找到子串 `OK` | 发送失败、回显为空、回显不含 `OK`：多为 `""`；见下表固定串 |

空命令、命令过长：`ok` 为 `false`，`resp` 为 `""`，不抛。

**固定返回文本**

| 文本 | 出现在 | 可能原因 |
| --- | --- | --- |
| `""`（空串） | `exec` / `ril_exec` 第二返回值 | 无回显、解析失败、`at_cmd` 为空、命令过长 |
| `FEATURE_RIL_AT_API_ENABLE off` | 仅 `ril_exec` 的 `resp` | 本固件未打开原厂 AT 通道；`ok` 必为 `false` |

**抛错**

| 摘要 | 可能原因 |
| --- | --- |
| Lua 标准 `bad argument #1`（string expected） | `at_cmd` 缺省或不是 string |

没有 `err_code`。不要用数字去对业务失败；只看 `ok` 和 `resp` 文本。

---

## 9. 资源上限与生命周期

| 项 | 上限 / 说明 |
| --- | --- |
| 对象 | 无 userdata，无 `close` |
| `ril_exec` 默认等待 | **10000** ms |
| `ril_exec` 回显缓冲 | 约 **4096** 字节 |
| 并发 | 内部串行；重叠调用会互相等 |
| 回调 | 无 |

没有需要脚本钉住的引用。VM 退出不留句柄。

---

## 10. 选型对照

| 需求 | 用谁 |
| --- | --- |
| IMEI / ICCID / CSQ / 版本 / 时钟 | [`info`](info.md) / [`sys`](sys.md)，不要虚拟 AT |
| 度云未来产品 AT（与串口同一套） | `virat.exec` |
| 原厂 EC 指令、Lua/度云未来 AT 都没有的能力 | **仅在本公司指导下** `virat.ril_exec` |
| DNS 查询/配置 | 优先 [`dns`](../network/dns.md) |
| 自己拼 AT 当远程控制协议 | 用产品公开的度云未来 AT + `exec`，不要走原厂引擎 |

---

## 11. 完整示例

与 [examples/nt26/module/virt/virt_api](../../../../examples/nt26/module/virt/virt_api) 一致。下面只演示 `exec` 只读查询；`ril_exec` 的可运行调用以该 demo 当时采用的指令为准，**不要改成别的原厂命令。**

```lua
local rt    = require("rt")
local log   = require("log")
local virat = require("virat")

local ok, resp = virat.exec("ATI\r\n")
log.info("exec ATI ok=%s resp=%s", tostring(ok), resp)

ok, resp = virat.exec("AT+VERSION\r\n")
log.info("exec VERSION ok=%s resp=%s", tostring(ok), resp)

-- 原厂通道：仅在书面指导的指令上使用。乱发不予保修，且模块会记录调用。
-- local ok2, resp2 = virat.ril_exec("AT+CGSN=1\r\n")
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：`ok`/`resp` 判定、固定返回文本与缺参抛错 |
