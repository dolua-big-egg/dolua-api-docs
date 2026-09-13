# ufs

**文档版本** `1.2.2`

纯函数模块。把 **可序列化的 Lua 值**（配置表、状态、短字符串）写成内部受限文件，读回仍是 Lua 对象。自带格式化，落盘会压缩。适合短小对象，不适合大二进制、也不适合流式拼文件。

```lua
local ufs = require("ufs")
```

平台预加载模块，无需额外 `.lua` 文件。

和 [`ublob`](ublob.md)、**Lua 脚本区**共用同一块配额，总额随型号而变（NT26 PRO 为 220 KB，见 [第 9 节](#9-共享配额)）。用法与 ublob 不同：本模块存对象；`ublob` 只存 string、适合流式和稍大的文件。见 [第 1 节对照](#1-模块定位) 与 [第 12 节](#12-选型对照)。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `ufs.write`](#6-1-write)
  - [6.2 `ufs.read`](#6-2-read)
  - [6.3 `ufs.remove`](#6-3-remove)
  - [6.4 `ufs.stat`](#6-4-stat)
  - [6.5 `ufs.list`](#6-5-list)
  - [6.6 `ufs.usage`](#6-6-usage)
  - [6.7 `ufs.cmp`](#6-7-cmp)
- [7. 可序列化值](#7-可序列化值)
- [8. 文件名](#8-文件名)
- [9. 共享配额](#9-共享配额)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

不是 POSIX 文件系统：没有目录、没有路径、没有 `open` 句柄。一次 `write` 覆盖整个逻辑文件，一次 `read` 还原整个值。

典型顺序：

1. `ufs.write("cfg", { id = 1, tags = { "a" } })`
2. `ufs.read("cfg")` 得到 table
3. 改配置前用 `ufs.cmp("cfg", newcfg)` 判断有没有变
4. `ufs.usage()` 看和 `ublob` 还剩多少可写空间

**和 `ublob` 的差异（同一块空间，两套用法）：**

| | `ufs`（本模块） | [`ublob`](ublob.md) |
| --- | --- | --- |
| 存什么 | Lua 值：nil / bool / number / string / table | **只能 string**（字节，可含 `\0`） |
| 格式 | 自带序列化，读回就是对象 | 原样字节，不会帮你解码 table |
| 适合 | 配置、状态、短小对象 | 日志块、固件片、HTTP 下来的二进制 |
| 大小 | 编码 RAM 上限 **80 KiB**；宜短小 | 单文件明文上限 **256 KiB**；可稍大 |
| 写入 | 整值覆盖；没有 append | `write` 覆盖，**`append` 分块拼** |
| 读取 | 整值还原到 Lua | `read` 切片，或 **`open` 视图**（数据留在视图侧，只把切片拷进 Lua） |
| 摘要 | 无 | `view:crc32` / `view:md5`，不必先拷进 Lua 堆 |
| 列表 | 只看见 ufs 文件 | 只看见 ublob 文件 |
| 配额 | 与 ublob、**Lua 脚本区**共用一块空间，总额按型号（见 [第 9 节](#9-共享配额)） | 同左 |

同名可以两边各存一份，互不可见：`ufs.read("x")` 读不到 `ublob.write("x", ...)` 写进去的内容。

多个字段请打成 **一张表一次写入**，不要拆成很多小文件：每次落盘都有压缩记录开销，合并更省配额。

大二进制、HTTP 正文、MCU 镜像走 [`ublob`](ublob.md)（或外挂 [`lfs`](lfs.md)）。`http.save` **不能**直接写 ufs。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  write / read / cmp / list / usage                       │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  ufs 模块                                                │
│  · 把 Lua 值编成内部对象格式（table 变数组或映射）         │
│  · 读回自动还原                                          │
│  · 与 ublob、脚本分命名空间，只认本模块写下的短名          │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  内部受限存储                                            │
│  压缩落盘；脚本区 + ufs + ublob 共用一块配额（额度按型号） │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `write` | 序列化 → 压缩 → 覆盖写 | **否** |
| `read` / `cmp` | 解压 → 反序列化（`cmp` 再深度比较） | **否** |
| `stat` / `list` / `usage` / `remove` | 查元数据或删文件 | **否** |

大表会占住整条 Lua 引擎线程。没有回调、没有 userdata。

---

## 3. 阻塞语义

全部同步。没有超时参数，不会把当前协程让给别的 Lua 任务。

---

## 4. 常量与枚举

模块表 **没有** 导出整数常量。上限见 [第 11 节](#11-资源上限与生命周期)，不是挂在 `ufs.xxx` 上的符号。

---

## 5. 类型约定

| 文档用名 | Lua 类型 | 说明 |
| --- | --- | --- |
| `name` | string | 逻辑短名，规则见 [第 8 节](#8-文件名) |
| `value` | nil / boolean / number / string / table | 可序列化值，见 [第 7 节](#7-可序列化值) |
| `ok` | boolean | `write` 成败；失败是 `false` 不是 `nil` |
| `info` | table | `stat`：`name`、`size`、`is_dir` |
| `items` | 数组 table | `list` 的每一项同 `info` |
| `usage` | table | 见 [6.6](#6-6-usage) |
| `equal` | boolean | `cmp` 是否与已存对象深度相等 |

`size` 是解压后的逻辑长度（对象编码后的明文），**不是**压缩落盘字节。占了多少盘看 `usage().used`。

---

## 6. 模块函数

缺 `name`、或类型不是 string 时会 **抛错**。业务失败走返回值，不抛。

### 6.1 `ufs.write(name, value)` {#6-1-write}

覆盖写入一个逻辑文件。已存在则替换。

**调用模式**

```lua
ok, err = ufs.write(name, value)
```

`value` 可以是 `nil`（会存成「这个文件的内容是 nil」）。

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 是 | 短名 |
| `value` | 可序列化值 | 是 | 缺省或类型不支持 → 失败，不抛 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `true, nil` |
| 失败 | `false, err`（**不是** `nil, err`） |

典型 `err`：`"unsupported value type"`、`"table too large"`、`"table depth exceeded"`、`"unsupported table key"`、`"quota exceeded"`、`"invalid param"`、`"序列化失败"`。

**示例**

```lua
local ok, err = ufs.write("cfg", { id = 1, name = "demo" })
if not ok then
    log.error("%s", err)
end
```

---

### 6.2 `ufs.read(name)` {#6-2-read}

解压并还原成 Lua 值。

**调用模式**

```lua
value, err = ufs.read(name)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `value, nil`（`value` 也可以是 `nil`） |
| 失败 | `nil, err` |

你写入了 `nil` 时，成功也是 `nil, nil`。要用 **第二返回值** 区分「读失败」和「存的就是 nil」：

```lua
local v, err = ufs.read("flag")
if err ~= nil then
    -- 失败：文件不存在、损坏等
elseif v == nil then
    -- 成功，内容就是 nil
end
```

典型 `err`：`"not found"`、`"read target is dir"`、`"not msgpack ufs data"`、`"反序列化失败"`、`"bad record"`。

旧版 JSON 文本、或未按本模块格式写下的内容，读会失败，不要指望兼容。

---

### 6.3 `ufs.remove(name)` {#6-3-remove}

删除逻辑文件。不存在也算成功。

**调用模式**

```lua
ok = ufs.remove(name)
-- 失败：nil, err
```

| 结果 | 返回 |
| --- | --- |
| 文件存在并删掉，或不存在 | `true` |
| 其它失败 | `nil, err` |

---

### 6.4 `ufs.stat(name)` {#6-4-stat}

查单个文件。

**调用模式**

```lua
info, err = ufs.stat(name)
```

成功时 `info`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `name` | string | 逻辑短名 |
| `size` | integer | 解压后逻辑长度 |
| `is_dir` | boolean | 当前仓里一般是 `false` |

失败：`nil, err`（不存在为 `"not found"`）。

`ublob.stat` **没有** `is_dir` 字段；不要混用两套返回表。

---

### 6.5 `ufs.list()` {#6-5-list}

列举本模块写下的全部文件。不含 ublob、不含脚本。

**调用模式**

```lua
items, err = ufs.list()
```

成功是数组（空仓为 `{}`，不是 `nil`）。每项与 `stat` 相同；列表里 `is_dir` 固定为 `false`。

---

### 6.6 `ufs.usage()` {#6-6-usage}

查询 **ufs + ublob 合计** 占用。与 `ublob.usage()` 是同一套数字。

**调用模式**

```lua
usage, err = ufs.usage()
```

| 字段 | 含义 |
| --- | --- |
| `used` | ufs + ublob 当前压缩落盘字节 |
| `limit` | 二者可占用上限（`shared_limit − script_used`） |
| `script_used` | **Lua 脚本区**当前落盘字节 |
| `shared_limit` | 脚本区 + ufs + ublob 的本机总额；NT26 PRO 为 220 KB，其它型号以读到的值为准 |

`used >= limit` 时再 `write` 会 `"quota exceeded"`（除非覆盖写且新纪录更小）。

---

### 6.7 `ufs.cmp(name, value)` {#6-7-cmp}

把 `value` 与已存对象做深度比较。适合「没变就别写」，少一次压缩落盘。

**调用模式**

```lua
equal, err = ufs.cmp(name, value)
```

| 结果 | 返回 |
| --- | --- |
| 文件不存在 | `false`（视为不同，**不是**错误） |
| 比较完成 | `true` / `false` |
| 读或解码失败 | `nil, err` |

比较规则：

- 类型必须相同。
- 数字按浮点相等（`1` 与 `1.0` 视为相同）。
- 字符串按字节（可含 `\0`）。
- table：两边键集合相同，且每个键的值递归相等。多一个字段即 `false`。

`value` 缺省会抛错（「需要一个值」）。

```lua
if not ufs.cmp("cfg", newcfg) then
    ufs.write("cfg", newcfg)
end
```

---

## 7. 可序列化值

| 类型 | 写入 | 读回 |
| --- | --- | --- |
| `nil` | 可以 | `nil` |
| `boolean` | 可以 | `boolean` |
| `number` | 整数或浮点 | 整数尽量仍是 integer；过大的无符号整数可能变成 number |
| `string` | 可以，按长度不是 C 字符串 | 同内容 string |
| `table` | 键只能是 string / number / boolean | table |
| `function` / userdata / thread / 协程 | **不行** | — |

table 形态：

- 键为连续整数 `1 .. n`、无空洞、项数等于 `#t` → 存成数组，读回仍是 1 起的数组。
- 否则存成映射（字符串键、稀疏数字键、布尔键都会走这条）。

上限：嵌套深度 **10**；单表项数 **4096**。超出 `"table depth exceeded"` / `"table too large"`。

不支持的键（例如把 table 当键）→ `"unsupported table key"`。

本模块 **不会** 把 table 编成 JSON 文本。若你把 `json.encode(t)` 的结果当 string 写入，读回仍是 string，要用 [`json.decode`](json.md) 再解。对象落盘请直接 `write` table。

---

## 8. 文件名

只允许 **短文件名**，不是路径。

| 非法 | 结果 |
| --- | --- |
| 空串 | `"invalid param"` |
| 含 `/` `\` `:` | `"invalid param"` |
| 含 `..` | `"invalid param"` |
| 含控制字符（字节值小于 `0x20`） | `"invalid param"` |
| 过长（拼不上内部路径） | `"invalid param"` |

脚本不要自己加前缀。底层按模块分命名空间：`ufs` 与 `ublob` 同名互不影响。

---

## 9. 共享配额

**Lua 脚本区**、`ufs`、`ublob` 三家合用同一块内部空间。按 **压缩后实际占盘** 核算。

```
脚本区落盘 + ufs 落盘 + ublob 落盘  ≤  shared_limit
ufs/ublob 可写上限 limit = shared_limit − 脚本区落盘
```

总额 **随型号而变**。本机以 `ufs.usage()` / `ublob.usage()` 的 `shared_limit` 为准。目前公布的型号：

| 型号 | Lua 脚本 + ufs + ublob 合计 |
| --- | --- |
| NT26 PRO | **220 KB** |

脚本越大，ufs/ublob 能用的就越少。底层两槽的脚本若都落盘会一起计入脚本区；**当前未启用双槽切换**，不要按两份完整包预留。脚本升级变大时 `limit` 会下降，可能把已有文件挤到写不下。清空间：删本模块文件或 `ublob.remove`，两边的 `usage().used` 会一起下降。整图见 [可用资源](../../core/resources.md)、[存储怎么分](../../core/storage.md)。

重复性高的文本压缩比好；已经压过的二进制往往几乎不缩小。不要按 Lua 里 `#string` 或 table「看起来多大」估配额。

外挂 NOR 上的 [`lfs`](lfs.md) / [`flashdb`](flashdb.md) **不走** 这块配额。

---

## 10. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `write` | `true, nil` | `false, err` |
| `read` | `value, nil` | `nil, err` |
| `remove` | `true` | `nil, err` |
| `stat` / `list` / `usage` | table | `nil, err` |
| `cmp` | `true`/`false`；缺文件为 `false` | `nil, err` |

缺 string 类型的 `name`：**抛错**。

`err` 全表（存储层 + 编解码）：

| `err` | 可能原因 |
| --- | --- |
| `ok` | 不会作为失败第二返回值出现 |
| `not found` | `read`/`stat`/`remove` 名字不存在 |
| `quota exceeded` | 与脚本区、ublob 共用配额满；删文件或缩短对象。看 `usage()` |
| `invalid param` | 文件名非法（空、过长、非法字符） |
| `io error` | 介质读写失败 |
| `not empty` | 当前仓一般碰不到（无目录树） |
| `not dir` | 同上 |
| `already exists` | 内部已存在冲突（少见） |
| `bad record` | 落盘记录损坏，删了重写 |
| `fs error` | 未单独翻译的存储码 |
| `table too large` | 单表超过 4096 项，或编码将超 80 KiB |
| `table depth exceeded` | 嵌套超过 10 层 |
| `float unsupported` | 出现了非整数 number（用整数或先格式化成 string） |
| `string too large` | 单个 string 太大 |
| `unsupported table key` | 键不是合法类型（只要 string/integer） |
| `unsupported value type` | function / userdata / thread 不能落盘 |
| `msgpack buffer alloc failed` | 编码缓冲分配失败 |
| `not msgpack ufs data` | 文件不是本模块格式（别用 ublob 同名去 read） |
| `序列化失败-输出为空` | 编码结果空 |
| `read target is dir` / `cmp target is dir` | 目标被当成目录（当前仓少见） |
| cmp 的 `cmp_strerror` 原文 | 编解码库报的细节（损坏或不完整） |

诊断：`quota exceeded` 先 `usage()` 再合并小文件；`unsupported *` 改数据结构；`not found` 查名字是否写过、是否写到了 ublob。

---

## 11. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 总配额（脚本区 + ufs + ublob） | 按型号，见 [第 9 节](#9-共享配额)；本机读 `usage().shared_limit` |
| 一次 `write` 的编码 RAM | **80 KiB** |
| table 嵌套 | **10** |
| 单表项数 | **4096** |
| userdata | 无；没有需要 `close` 的对象 |
| 并发 | 无视图名额；与 ublob 的「同时 1 个 view」无关 |

没有 `__gc` 要照顾。VM 退出文件仍在。

---

## 12. 选型对照

| 需求 | 用谁 |
| --- | --- |
| 配置表、设备状态、短 KV | **`ufs`** |
| 多个相关字段 | **一张表** `ufs.write`，不要拆很多文件 |
| 只判断配置有没有变 | `ufs.cmp`，变了再 `write` |
| 原始字节、固件、图片、HTTP body | [`ublob`](ublob.md) |
| 分块追加、分块读、算 CRC/MD5 又不想把整包拷进 Lua | **只能 ublob** |
| 外挂 Flash 上真正的文件/目录 | [`lfs`](lfs.md) |
| 外挂 Flash 上 KV / 时序库 | [`flashdb`](flashdb.md) |
| 和云端对 JSON 文本 | [`json`](json.md)，需要落盘对象时再 `ufs.write` 表 |

不要用 ufs 当「稍大的二进制盘」：没有 append、没有 view，一次读会把整个对象重建到 Lua 堆。反过来也不要把 table 塞进 ublob——它不会帮你格式化。

---

## 13. 完整示例

与 [examples/NT26/storage/ufs/ufs_api](../../../../examples/NT26/storage/ufs/ufs_api) 一致：

```lua
local rt  = require("rt")
local log = require("log")
local ufs = require("ufs")

local CFG = {
    id = 1,
    name = "ufs-demo",
    ok = true,
    tags = { "a", "b" },
    nested = { x = 10, y = 20 },
}

ufs.remove("d_tbl")
local ok, err = ufs.write("d_tbl", CFG)
assert(ok, err)

local v, rerr = ufs.read("d_tbl")
assert(rerr == nil)
log.info("id=%s tags[1]=%s", v.id, v.tags[1])

log.info("cmp same=%s", tostring(ufs.cmp("d_tbl", CFG)))
log.info("cmp missing field=%s", tostring(ufs.cmp("d_tbl", { id = 1 })))
log.info("cmp not found=%s", tostring(ufs.cmp("no_such_ufs", "x")))

local u = ufs.usage()
log.info("used=%s limit=%s script_used=%s shared_limit=%s",
         u.used, u.limit, u.script_used, u.shared_limit)

ufs.remove("d_tbl")
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.1.0 | 2026-09-04 | 配额改为与脚本区共用、额度按型号；列出 NT26 PRO 合计 220 KB |
| 1.1.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.2.0 | 2026-09-05 | 补全全部 `err` 文案与可能原因 |
| 1.2.1 | 2026-09-12 | 共享配额节标明 A/B 两槽都计数，并链到核心分类 |
| 1.2.2 | 2026-09-12 | 配额说明改为：两槽是设计，当前未启用切换 |
