# ublob

**文档版本** `1.1.1`

纯字节存储。值必须是 **string**（Lua 的 string 就是字节流，可含 `\0`）。适合流式拼文件、稍大的二进制；读侧有 **view**，整包留在视图缓冲里，切片才进 Lua 堆，摘要可以完全不进 Lua 堆。

```lua
local ublob = require("ublob")
```

平台预加载模块，无需额外 `.lua` 文件。

和 [`ufs`](ufs.md)、**Lua 脚本区**共用同一块配额，总额随型号而变（NT26 PRO 为 220 KB，见 [第 11 节](#11-共享配额)）。本模块不是对象库：不会序列化 table，也没有 `cmp`。配置表请用 `ufs`。对照见 [第 1 节](#1-模块定位) 与 [第 14 节](#14-选型对照)。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 阻塞语义](#4-阻塞语义)
- [5. 常量与枚举](#5-常量与枚举)
- [6. 类型约定](#6-类型约定)
- [7. 模块函数](#7-模块函数)
  - [7.1 `ublob.write`](#7-1-write)
  - [7.2 `ublob.append`](#7-2-append)
  - [7.3 `ublob.read`](#7-3-read)
  - [7.4 `ublob.open`](#7-4-open)
  - [7.5 `ublob.size`](#7-5-size)
  - [7.6 `ublob.stat`](#7-6-stat)
  - [7.7 `ublob.remove`](#7-7-remove)
  - [7.8 `ublob.list`](#7-8-list)
  - [7.9 `ublob.usage`](#7-9-usage)
- [8. 视图方法](#8-视图方法)
  - [8.1 `view:read`](#8-1-read)
  - [8.2 `view:size`](#8-2-size)
  - [8.3 `view:crc32`](#8-3-crc32)
  - [8.4 `view:md5`](#8-4-md5)
  - [8.5 `view:close`](#8-5-close)
- [9. `read` 与 view](#9-read-与-view)
- [10. 文件名](#10-文件名)
- [11. 共享配额](#11-共享配额)
- [12. 错误与返回约定](#12-错误与返回约定)
- [13. 资源上限与生命周期](#13-资源上限与生命周期)
- [14. 选型对照](#14-选型对照)
- [15. 完整示例](#15-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

内部受限仓里的二进制文件：覆盖写、追加、按偏移切片读。HTTP 下载内部盘走的就是这一套（[`http.save.ublob`](../network/http.md)）。

典型顺序：

1. `ublob.write` 或多次 `append` 拼出文件
2. 偶尔读一小段：`ublob.read(name, offset, len)`
3. 多次分块读或算整包 CRC/MD5：`ublob.open` → `view:read` / `view:crc32` / `view:md5` → `view:close()`

**和 `ufs` 的差异（同一块空间，两套用法）：**

| | `ublob`（本模块） | [`ufs`](ufs.md) |
| --- | --- | --- |
| 存什么 | **只能 string** | Lua 值（nil / bool / number / string / **table**） |
| 格式 | 原样字节 | 自带序列化，读回是对象 |
| 适合 | 流式、稍大文件、HTTP body、固件片 | 短小配置 / 状态对象 |
| 大小 | 单文件明文 **256 KiB** | 编码 RAM **80 KiB**，宜更短 |
| 写入 | `write` + **`append`** | 只有整值覆盖 |
| 读取 | 切片；**view 省 Lua 堆** | 整值还原到 Lua，没有 view |
| 摘要 | `view:crc32` / `view:md5` | 无 |
| 列表 | 只看见 ublob | 只看见 ufs |
| 配额 | 与 ufs、**Lua 脚本区**共用一块空间，总额按型号（见 [第 11 节](#11-共享配额)） | 同左 |

同名两边可以各存一份。`ublob.list()` 看不到 `ufs.write("cfg", t)`。

Lua 的 string 按长度取值，不要当 C 字符串在 `\0` 处截断。长度用 `#s` 或 `nread`。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  write / append / read                                   │
│  open → view:read / crc32 / md5 → close                  │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  ublob 模块                                              │
│  · 模块函数管文件                                        │
│  · open 得到 view：整包明文挂在 userdata 上               │
│  · 切片才变成 Lua string；crc32/md5 可完全不进 Lua 堆     │
│  · 与 ufs 分命名空间                                     │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  内部受限存储                                            │
│  压缩落盘；脚本区 + ufs + ublob 共用一块配额（额度按型号） │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `write` | 压缩并覆盖写 | **否** |
| `append` | 读出整包明文 → 拼接 → 再压缩覆盖 | **否**（大文件占 RAM） |
| `read` | 整包解压到临时缓冲 → 切片成 Lua string → 释放缓冲 | **否** |
| `open` | 整包解压到 view 缓冲，直到 `close` / GC | **否** |
| `view:read` | 从已解压缓冲拷一段到 Lua | **否** |
| `view:crc32` / `view:md5` | 在 view 缓冲上算，默认不把数据拷进 Lua | **否** |

没有回调。

---

## 3. 对象模型

模块表上只有文件级函数。`ublob.open` 返回 **view** userdata。

```lua
view:read(0, 64)       -- 推荐
view.read(view, 0, 64) -- 等价
```

错误：`view.read(0, 64)`（少了 self）、`ublob.read(view, 0, 64)`（模块 `read` 要的是文件名）、把 view 传给 `ufs.read`。

脚本必须保住 `view` 引用。`close` 之后对象还在，再读会失败。未 `close` 时 `__gc` 会释放缓冲并归还「同时打开」名额。

同时打开的 view **默认 1 个**。第二个 `open` 得到 `nil, "too many open views"`，直到现有 view `close` 或被回收。

`view:md5` 的 `raw` 走布尔语义：`false`/`nil` 为假，**数字 `0` 为真**。请写 `true`/`false`。

---

## 4. 阻塞语义

全部同步，不让出协程。大文件的 `append` / `read` / `open` 会占住引擎线程一段时间。

---

## 5. 常量与枚举

模块表 **没有** 导出整数常量。上限见 [第 13 节](#13-资源上限与生命周期)。

---

## 6. 类型约定

| 文档用名 | Lua 类型 | 说明 |
| --- | --- | --- |
| `name` | string | 逻辑短名，规则见 [第 10 节](#10-文件名) |
| `data` | string | 字节；允许空串 |
| `offset` / `len` | integer | ≥ 0；单位字节，从 0 起 |
| `nread` | integer | 实际读到的字节数 |
| `view` | userdata | `open` 的返回值 |
| `info` | table | `stat`：只有 `name`、`size`（无 `is_dir`） |
| `usage` | table | 与 `ufs.usage()` 字段相同 |

`size` / `stat().size` / `view:size()` 都是 **解压后明文长度**，不是压缩占盘。占盘看 `usage().used`。

---

## 7. 模块函数

`name` 不是 string、或 `read` 的 `offset`/`len` 不是整数时 **抛错**。业务失败走返回值。

### 7.1 `ublob.write(name, data)` {#7-1-write}

覆盖写。允许空串，得到 0 字节文件。

**调用模式**

```lua
ok, err = ublob.write(name, data)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 是 | 短名 |
| `data` | string | 是 | 明文；可含 `\0` |

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `true, nil` |
| 失败 | `false, err` |

典型 `err`：`"quota exceeded"`、`"invalid param"`（文件名非法，或明文超过 **256 KiB**）、`"io error"`、`"no mem"`。

`ufs.write` 的第二参可以是 table；这里第二参必须是 string，传 table 会抛错。

---

### 7.2 `ublob.append(name, data)` {#7-2-append}

追加。不存在则等同 `write`。这是流式 **写** 的入口：多次短 string 拼成一个文件。

**调用模式**

```lua
ok, err = ublob.append(name, data)
```

| `data` | 行为 |
| --- | --- |
| 空串 | 成功，文件不变 |
| 非空 | 拼到现有明文末尾后整包重写 |

实现是整包读出再写回，不是只追加磁盘尾。大文件每次 append 都会再占一份明文 RAM，峰值约为「旧明文 + 本段」。拼完后的明文仍受 **256 KiB** 限制，超出 `"invalid param"`。

`ufs` 没有 append。

---

### 7.3 `ublob.read(name, offset, len)` {#7-3-read}

整包解压后按区间切一段到 Lua string。`offset`、`len` **都必填**。

**调用模式**

```lua
data, nread, err = ublob.read(name, offset, len)
```

**切片规则**

| 条件 | 返回 |
| --- | --- |
| 成功切到数据 | `data, nread, nil`（`nread` 可能小于 `len`） |
| `len == 0` 或 `offset >= size` | `"", 0, nil` |
| 文件为空 | `"", 0, nil` |
| `offset` 或 `len` 为负，或超出整数范围 | `nil, 0, "invalid param"` |
| 文件不存在等 | `nil, 0, err` |

每次调用都整包解压。循环扫大文件请改用 [第 9 节](#9-read-与-view) 的 `open`。

---

### 7.4 `ublob.open(name)` {#7-4-open}

打开内存视图：解压一次，挂到 userdata。空文件也可以打开，`view:size()` 为 0。

**调用模式**

```lua
view, err = ublob.open(name)
```

| 结果 | 返回 |
| --- | --- |
| 成功 | `view` |
| 失败 | `nil, err` |

典型 `err`：`"not found"`、`"too many open views"`、`"no mem"`、`"open target is dir"`、`"bad record"`。

`ufs` 没有对应接口。

---

### 7.5 `ublob.size(name)` {#7-5-size}

明文长度。

**调用模式**

```lua
n, err = ublob.size(name)
```

成功 `n, nil`；失败 `nil, err`。

---

### 7.6 `ublob.stat(name)` {#7-6-stat}

**调用模式**

```lua
info, err = ublob.stat(name)
```

成功 `{ name = string, size = integer }`。没有 `is_dir`（`ufs.stat` 有）。

---

### 7.7 `ublob.remove(name)` {#7-7-remove}

不存在也返回 `true`。

**调用模式**

```lua
ok = ublob.remove(name)
-- 失败：nil, err
```

---

### 7.8 `ublob.list()` {#7-8-list}

只含本模块文件。空仓 `{}`。

**调用模式**

```lua
items, err = ublob.list()
```

每项 `{ name, size }`。

---

### 7.9 `ublob.usage()` {#7-9-usage}

与 `ufs.usage()` **同一套数字**。

**调用模式**

```lua
usage, err = ublob.usage()
```

| 字段 | 含义 |
| --- | --- |
| `used` | ufs + ublob 当前压缩落盘 |
| `limit` | 二者可占用上限（`shared_limit − script_used`） |
| `script_used` | **Lua 脚本区**当前落盘 |
| `shared_limit` | 脚本区 + ufs + ublob 的本机总额；NT26 PRO 为 220 KB，其它型号以读到的值为准 |

---

## 8. 视图方法

`view` 来自 `ublob.open`。已 `close` 后再用，除 `close` 本身外都会失败。

### 8.1 `view:read(offset, len)` {#8-1-read}

从已解压缓冲切片。规则与 `ublob.read` 相同，但 **不再解压**。`offset`、`len` 必填。

**调用模式**

```lua
data, nread, err = view:read(offset, len)
```

已 close：`nil, 0, "closed"`。

只把 `nread` 字节拷进 Lua，整包仍留在 view 上。这是省 Lua 堆的读法。

---

### 8.2 `view:size()` {#8-2-size}

**调用模式**

```lua
n = view:size()
-- 已 close：nil, "closed"
```

无参。不要写成 `view:size(name)`。

---

### 8.3 `view:crc32([offset], [len])` {#8-3-crc32}

IEEE CRC-32（以太网 / zip），与 [`tls.crc32`](tls.md) 默认多项式一致。在 view 缓冲上算，**不**把区间拷进 Lua 堆。

**调用模式**（每种单独合法）

```lua
crc = view:crc32()
```

```lua
crc = view:crc32(offset)
```

```lua
crc = view:crc32(offset, len)
```

| 写法 | 区间 |
| --- | --- |
| 无参 | 整包 |
| 只给 `offset` | 从该处到末尾；`offset > size` → `nil, "invalid param"` |
| `offset, len` | 从 `offset` 起最多 `len` 字节；越界截成空区间（空区间仍返回 CRC，不是错误） |

`offset`/`len` 为负：`nil, "invalid param"`。已 close：`nil, "closed"`。

成功返回无符号 32 位整数（Lua integer）。

---

### 8.4 `view:md5([offset], [len], [raw])` {#8-4-md5}

区间规则与 `crc32` 相同。流式计算，不拷贝输入。

**调用模式**

```lua
digest = view:md5()
```

```lua
digest = view:md5(offset)
```

```lua
digest = view:md5(offset, len)
```

```lua
digest = view:md5(offset, len, raw)
```

```lua
digest = view:md5(0, nil, true)
```

最后一种：从 0 到末尾，`raw == true`。第三参为 `nil` 时按「省略长度」处理，不是长度为 0。

| `raw` | 返回 |
| --- | --- |
| 省略 / `false` / `nil` | 32 字符小写 hex |
| 真 | 16 字节 binary string |

`raw` 用布尔语义：**数字 `0` 为真**。请写 `true`/`false`。

本固件未开 MD5 时：`nil, "md5 not enabled"`。已 close：`nil, "closed"`。

---

### 8.5 `view:close()` {#8-5-close}

释放 view 缓冲，归还同时打开名额。

**调用模式**

```lua
ok = view:close()
```

恒为 `true`。重复 `close` 仍是 `true`。未调用时等 userdata 回收也会释放。

OTA / HTTP 读完应立刻 `close`，否则下一个 `open` 会 `"too many open views"`。

---

## 9. `read` 与 view

| 方式 | Lua 堆 | 解压次数 | 适用 |
| --- | --- | --- | --- |
| `ublob.read` | 每次把切片变成 string | **每次整包** | 偶发读一小段 |
| `open` + `view:read` | 只为切片分配 string | 打开时一次 | 多次分块、扫文件 |
| `view:crc32` / `view:md5` | 默认 **0**（hex/md5 结果除外） | 打开时一次 | 校验 |

循环里反复 `ublob.read(name, off, 4096)` 会反复整包解压，又慢又费临时 RAM。

`ufs.read` 没有这种分流：它总是把整个对象重建到 Lua。

---

## 10. 文件名

与 `ufs` **同一套规则**：短名、禁止 `/` `\` `:`、控制字符、`..`、空串。非法 → `"invalid param"`。

不要自己加前缀。与 ufs 分命名空间，同名互不可见。

[`http.save.ublob`](../network/http.md) 另有文件名长度限制（95 字节），比本模块路径上限更紧；HTTP 落盘请遵守 HTTP 文档。

---

## 11. 共享配额

**Lua 脚本区**、[`ufs`](ufs.md)、本模块三家合用同一块内部空间。按 **压缩后实际占盘** 核算。与 `ufs.usage()` 是同一套数字。

```
脚本区落盘 + ufs 落盘 + ublob 落盘  ≤  shared_limit
ufs/ublob 可写上限 limit = shared_limit − 脚本区落盘
```

总额 **随型号而变**。本机以 `ublob.usage()` 的 `shared_limit` 为准。目前公布的型号：

| 型号 | Lua 脚本 + ufs + ublob 合计 |
| --- | --- |
| NT26 PRO | **220 KB** |

脚本越大，ufs/ublob 能用的就越少。明文上限 256 KB 的单文件，压完仍可能把本机配额打满。

HTTP 落到 ublob 也吃这块配额；超限时 HTTP 侧是保存失败码，不是本模块的 `"quota exceeded"` 字符串。见 [`http`](../network/http.md)「落到 ublob」。

外挂 NOR 上的 [`lfs`](lfs.md) / [`flashdb`](flashdb.md) **不走** 这块配额。

---

## 12. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `write` / `append` | `true, nil` | `false, err` |
| `read` / `view:read` | `data, nread, nil` | `nil, 0, err` |
| `open` | view | `nil, err` |
| `size` / `stat` / `list` / `usage` / `view:size` / `view:crc32` / `view:md5` | 值 | `nil, err` |
| `remove` | `true` | `nil, err` |
| `view:close` | `true` | 无失败路径 |

缺参、类型不对：**抛错**（`read` 的 offset/len、`write` 的 data 等）。

常见 `err`：

| `err` | 何时 |
| --- | --- |
| `not found` | 文件不存在 |
| `quota exceeded` | 共享配额不够 |
| `invalid param` | 文件名非法、负偏移、明文超 256 KiB 等 |
| `no mem` | 解压或视图缓冲不够 |
| `io error` / `fs error` / `bad record` | 存储或记录损坏 |
| `too many open views` | 已有未关闭的 view |
| `closed` | 对已 close 的 view 操作 |
| `md5 not enabled` | 固件未开 MD5 |
| `read target is dir` / `open target is dir` | 目标是目录（当前仓少见） |

切片越界是成功空读，不是 `"invalid param"`（负偏移才是）。

---

## 13. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 总配额（脚本区 + ufs + ublob） | 按型号，见 [第 11 节](#11-共享配额)；本机读 `usage().shared_limit` |
| 单文件解压明文 | **256 KiB** |
| 同时打开的 view | **1** |
| `view` 存活 | 直到 `close` 或 userdata GC |
| 模块函数 | 无对象；`read` 的临时缓冲在返回前释放 |

`open` 期间整包明文占着一块缓冲。用完 `close`，不要指望只靠 GC 及时腾出名额。

---

## 14. 选型对照

| 需求 | 用谁 |
| --- | --- |
| 配置表、状态对象、短 KV | [`ufs`](ufs.md) |
| 原始字节、可含 `\0` 的包 | **`ublob`** |
| 分多次写入拼文件 | `ublob.append` |
| 多次分块读、少占 Lua 堆 | `ublob.open` + `view:read` |
| 整包 CRC / MD5 且不想 `table.concat` | `view:crc32` / `view:md5` |
| HTTP 下到内部盘 | [`http.save.ublob`](../network/http.md)，再本模块读 |
| 超过本机共享配额或单文件明文上限 | 外挂 [`lfs`](lfs.md) |
| 外挂 KV / 时序 | [`flashdb`](flashdb.md) |

不要把 table 直接 `ublob.write`。不要用 ufs 存固件或 HTTP body。

---

## 15. 完整示例

与 [examples/NT26/storage/ublob/ublob_api](../../../../examples/NT26/storage/ublob/ublob_api) 一致：

```lua
local rt    = require("rt")
local log   = require("log")
local ublob = require("ublob")

local NAME = "b_demo"
ublob.remove(NAME)

assert(ublob.write(NAME, "hello"))
ublob.append(NAME, " world")

local data, nread, err = ublob.read(NAME, 0, 32)
assert(err == nil and data == "hello world")

local view, verr = ublob.open(NAME)
assert(view, verr)
local chunk = view:read(0, 5)
log.info("slice=%s crc=0x%08X md5=%s", chunk, view:crc32(), view:md5())

local v2, e2 = ublob.open(NAME)
-- e2 == "too many open views"
view:close()
if v2 == nil then
    local again = ublob.open(NAME)
    again:close()
end

local u = ublob.usage()
log.info("used=%s limit=%s", u.used, u.limit)
ublob.remove(NAME)
```

分块扫文件：

```lua
local v = ublob.open("mcu.bin")
local off = 0
while off < v:size() do
    local chunk, n = v:read(off, 2048)
    if n == 0 then break end
    -- 处理 chunk，不要攒成整包再塞进 Lua
    off = off + n
end
v:close()
```

HTTP 落到 ublob 后同样 `open` 分块读，见 [examples/NT26/network/http/http_file_ublob](../../../../examples/NT26/network/http/http_file_ublob)。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.1.0 | 2026-09-04 | 配额改为与脚本区共用、额度按型号；列出 NT26 PRO 合计 220 KB |
| 1.1.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
