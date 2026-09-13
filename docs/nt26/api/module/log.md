# log

**文档版本** `1.2.0`

带级别、带调用点的调试输出模块。三个函数用法相同，仅级别不同；单参原样打印，多参按 `string.format` 组包。

```lua
local log = require("log")
```

平台预加载模块，无需额外 `.lua` 文件。主脚本虚拟机启动时还会放入全局 `_G.log`；推荐仍写 `local log = require("log")`。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 常量与枚举](#3-常量与枚举)
- [4. 类型约定](#4-类型约定)
- [5. 模块函数](#5-模块函数)
  - [5.1 `log.info`](#5-1-info)
  - [5.2 `log.warn`](#5-2-warn)
  - [5.3 `log.error`](#5-3-error)
- [6. 正文生成规则](#6-正文生成规则)
- [7. 输出行格式](#7-输出行格式)
- [8. 错误与返回约定](#8-错误与返回约定)
- [9. 资源上限与生命周期](#9-资源上限与生命周期)
- [10. 输出路由](#10-输出路由)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`log` 是纯函数模块，没有对象、没有 `open`。脚本 `require` 之后直接调用：

```lua
log.info("hello")
log.warn("low battery")
log.error("open fail")
```

每条日志都会：

1. 自动带上调用点（函数名、源文件、行号）。
2. 按级别打出 `INFO` / `WARN` / `ERROR`。
3. 直出指定 UART 或 USB AT，与内置 `print` 独立，也不跟 `AT+LOG` 输出口走。

只做输出，无返回值，不参与业务状态机。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  require("log") → info / warn / error                    │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  log 模块                                                │
│  · 采集调用点：函数名、源文件、行号                        │
│  · 生成正文：单参 tostring；多参 string.format            │
│  · 参数预处理：nil / boolean / 其它类型转成可格式化值      │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  输出通道                                                 │
│  · 固定行格式 [Lua][级别][函数][源:行] 正文 CRLF           │
│  · 默认 uart1；可与 print 分别指定 uart1/2/3 或 usb_at     │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 谁在输出 | 是否占用 Lua 调度 | 典型用途 |
| --- | --- | --- | --- |
| `log.info` / `warn` / `error` | 当前调用当场组包并写串口 | 是，通常很短 | 调试、状态、错误 |

组包在调用栈上同步完成：`format` 失败不会抛回脚本，而是把错误说明写进这一条日志。超长正文超过上限时本条丢弃，改打一条超限提示。

---

## 3. 常量与枚举

本模块不向 Lua 表挂任何整数常量。没有 `log.INFO`、`log.WARN`、`log.ERROR` 这类符号。

级别只由三个函数名区分：

| 调用 | 输出行里的级别标签 |
| --- | --- |
| `log.info` | `INFO` |
| `log.warn` | `WARN` |
| `log.error` | `ERROR` |

不要传级别数字，也不要在模块表上查找级别枚举。

---

## 4. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `msg` | 任意 Lua 值 | 单参路径：经 `tostring` 变成正文 |
| `fmt` | 通常为 string | 多参路径的第一参，作为 `string.format` 的格式串 |
| `arg` | 任意 Lua 值 | 多参路径第二参起；会先做类型预处理再交给 `string.format` |

本模块 **没有布尔语义的开关参数**。数字 `0` 按数字输出，不会被当成“假”。

---

## 5. 模块函数

三个函数签名、调用模式、失败风格完全相同，只改输出行上的级别标签。细则以 [5.1](#5-1-info) 为准；`warn` / `error` 仍把每一种调用模式单独列出。

---

### 5.1 `log.info(...)` {#5-1-info}

输出一条 `INFO` 日志。

**调用模式**

```lua
log.info()
```

```lua
log.info(msg)
```

```lua
log.info(fmt, arg1)
```

```lua
log.info(fmt, arg1, arg2, ...)
```

| 形态 | 参数 | 必填 | 正文如何生成 |
| --- | --- | --- | --- |
| 无参 | （无） | — | 空字符串 |
| 单参 | `msg` | 是 | `tostring(msg)` 原样作为正文 |
| 多参 | `fmt, arg1[, arg2, ...]` | `fmt` 与至少一参 | 始终 `string.format(fmt, ...)`，见 [第 6 节](#6-正文生成规则) |

多参时 **第一参永远当格式串**，不会检测它有没有 `%`，也不会把剩余参数用空格拼起来。

**返回**

无返回值（Lua 侧为 `nil`）。`format` 失败不抛错。

**示例**

```lua
log.info("this is log info")
log.info("count=%d name=%s", 3, "ec7xx")
log.info("ok=%s", true)
log.info("progress=%d%%", 80)
```

---

### 5.2 `log.warn(...)` {#5-2-warn}

输出一条 `WARN` 日志。参数与正文规则与 [5.1](#5-1-info) 相同。

**调用模式**

```lua
log.warn()
```

```lua
log.warn(msg)
```

```lua
log.warn(fmt, arg1)
```

```lua
log.warn(fmt, arg1, arg2, ...)
```

**返回**

无返回值。`format` 失败不抛错。

**示例**

```lua
log.warn("this is log warning")
log.warn("low battery pct=%d", 12)
```

---

### 5.3 `log.error(...)` {#5-3-error}

输出一条 `ERROR` 日志。参数与正文规则与 [5.1](#5-1-info) 相同。

**调用模式**

```lua
log.error()
```

```lua
log.error(msg)
```

```lua
log.error(fmt, arg1)
```

```lua
log.error(fmt, arg1, arg2, ...)
```

**返回**

无返回值。`format` 失败不抛错。

**示例**

```lua
log.error("this is log error")
log.error("open fail: %s", err)
```

---

## 6. 正文生成规则

### 6.1 单参

唯一参数经 `tostring` 后作为正文。`nil`、布尔、数字、字符串、table 都可以。

```lua
log.info("hello")          -- hello
log.info(123)              -- 123
log.info(true)             -- true
log.info(nil)              -- nil
```

### 6.2 多参

调用等价于：

```lua
string.format(预处理后的fmt, 预处理后的arg1, 预处理后的arg2, ...)
```

第一参即使不含 `%`，也按格式串处理。不要把 `log.info("a", "b")` 理解成 `print` 那种空格拼接。

### 6.3 参数预处理

交给 `string.format` 之前，每个参数（含格式串本身）按类型转换：

| Lua 类型 | 交给 format 的值 |
| --- | --- |
| `nil` | 字符串 `"nil"` |
| `boolean` | 字符串 `"true"` 或 `"false"` |
| `number` | 原样 |
| `string` | 原样 |
| 其它（table、userdata、function…） | `tostring` 的结果 |

因此：

- 布尔和 `nil` 必须用 `%s`。Lua `string.format` 没有 `%b`。
- 整数用 `%d` / `%i` 等，浮点用 `%f` 等。
- 字面百分号写成 `%%`。
- table 打出的是 `tostring` 默认形态（通常带类型和指针），不是内容 dump。

```lua
log.info("count=%d ok=%s", 3, true)     -- count=3 ok=true
log.info("progress=%d%%", 80)           -- progress=80%
log.info("v=%s", nil)                   -- v=nil
```

占位符集合与 Lua `string.format` 相同（`%s` `%q` `%d` `%f` `%x` 等）。类型与占位符不匹配时走 [6.4](#64-format-失败)。

### 6.4 format 失败

`string.format` 失败时：

- **不向脚本抛错**
- **不回退成空格拼接**
- 本条日志的正文变成 `format error: ` 加上失败原因

例如占位符与参数类型不符、格式串非法、`string.format` 不可用。脚本侧看不到返回值，只能在串口上看到这条 `format error:` 行。

对象若提供会抛错的 `__tostring`，单参路径仍可能把错误抛回脚本。这是 `tostring` 本身的行为，不是 format 失败通道。

---

## 7. 输出行格式

每一条成功组包的日志是一行，以 `\r\n`（CRLF）结束：

```
[Lua][<LEVEL>][<func>][<src>:<line>] <message>\r\n
```

| 字段 | 含义 |
| --- | --- |
| `LEVEL` | `INFO` / `WARN` / `ERROR` |
| `func` | 调用处函数名。有名字用名字；主chunk 为 `main`；匿名函数为 `anon`；取不到为 `?` |
| `src` | 源文件短名（如 `@main.lua`） |
| `line` | 调用行号；取不到为 `-1` |
| `message` | 第 6 节生成的正文 |

```
[Lua][INFO][main][@main.lua:13] this is log info
[Lua][WARN][main][@main.lua:14] this is log warning
[Lua][ERROR][main][@main.lua:15] this is log error
```

函数名、源路径过长会截断，见 [第 9 节](#9-资源上限与生命周期)。

---

## 8. 错误与返回约定

三个接口都**无返回值、不抛业务错**。失败只体现在串口打出的正文。

| 接口 | 成功 | 失败风格 |
| --- | --- | --- |
| `log.info` / `log.warn` / `log.error` | 无返回值 | 打出错误说明，不抛、不回退拼接 |

**超限提示原文**（本条业务正文丢弃，改打这一行 `ERROR`）：

```
[Lua][ERROR][lua_log][?:-1] log output exceeds 8192 limit (need N)
```

`N` 是估算需要的字节数（含级别头）。可能原因：单条 `fmt` 展开后超过 8192，或堆缓冲分配失败时仍按这个上限提示。

**`format` 失败时打到日志里的正文**

| 正文 | 可能原因 |
| --- | --- |
| `format error: string.format unavailable` | 运行时没有 `string.format`（极少） |
| `format error: unknown` | `string.format` 失败且没有字符串错误信息 |
| `format error: <下层原文>` | `string.format` 抛错，`<下层原文>` 为其错误串（占位符与参数个数/类型不配等） |
| `format error: non-string result` | `string.format` 没返回字符串 |

无参也允许，正文为空。没有必填检查，不会因缺参抛 `bad argument`。

---

## 9. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 单条输出 | 8192 字节 | 含级别头和 CRLF 的整行。超过则丢弃本条，改打超限提示 |
| 函数名字段 | 63 字符 | 更长截断 |
| 源路径字段 | 95 字符 | 更长截断 |

无对象、无回调登记、无通道占用。模块随虚拟机存在；不需要关闭。输出路由是进程级设置，脚本里改完立刻生效，重启后回到配置文件中的值。

---

## 10. 输出路由

`log` 直出指定路由，**不受 `AT+LOG` 输出口切换影响**，也与内置 `print` 互相独立。

| 项 | 值 |
| --- | --- |
| 默认 | `"uart1"` |
| 可选 | `"uart1"` / `"uart2"` / `"uart3"` / `"usb_at"` |

`log` 模块表上 **没有** 改路由的函数。改法在别的模块：

**配置文件（启动时生效，持久）**

`/rtu_config.cfg` 的 `[lua]` 段：

```ini
[lua]
print_route=uart1
log_route=usb_at
```

配置文件仍接受旧写法 `1` / `2` / `3`（当作 uart1/2/3）。`sys.option` 只认字符串名。

**运行时（立即生效，重启后恢复为配置文件）**

```lua
local sys = require("sys")
sys.option("log_route", "uart2")
local route = sys.option("log_route")
```

`sys.option` 的完整契约见 `sys` 模块文档。非法路由名会由 `sys` 抛错，不是 `log` 抛错。

---

## 11. 选型对照

| | `print` | `log.info` / `warn` / `error` |
| --- | --- | --- |
| 来源 | Lua 内置 | 平台扩展模块 |
| 级别 | 无 | 三个级别 |
| 调用点 | 无 | 函数名 + 文件 + 行号 |
| 多参 | 空格或制表拼接 | 第一参是 format |
| 布尔 / nil | 各有默认打印 | 多参时变成 `"true"` / `"false"` / `"nil"`，用 `%s` |
| 路由 | `print_route` | `log_route`，二者独立 |
| 返回值 | 无 | 无 |

调试、带上下文的状态请用 `log`。临时随手打印可以用 `print`。不要用 `log` 当数据通道（没有读接口，也没有回调）。

---

## 12. 完整示例

与 [examples/nt26/started/log](../../../../examples/nt26/started/log) 一致：

```lua
local rt  = require("rt")
local log = require("log")

log.info("this is log info")
log.warn("this is log warning")
log.error("this is log error")

-- boolean / nil 请用 %s
log.info("string %s, number %d, boolean %s, float %f",
         "hello world", 123, true, 3.1415926)

while true do
    rt.delay(1000)
end
```

---

## 附录 A. 方法速查

| 调用 | 参数模式 | 返回 |
| --- | --- | --- |
| `log.info()` | 无参，正文为空 | 无 |
| `log.info(msg)` | 单参，`tostring` | 无 |
| `log.info(fmt, ...)` | 多参，`string.format` | 无 |
| `log.warn(...)` | 与 `info` 相同 | 无 |
| `log.error(...)` | 与 `info` 相同 | 无 |

## 附录 B. 枚举值一览

无。级别不是模块常量。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：超限提示原文、format 失败正文与可能原因 |
| 1.2.0 | 2026-09-09 | 输出路由改为 `"uart1"` / `"uart2"` / `"uart3"` / `"usb_at"`，可打到 USB AT 口 |
