# flashdb

**文档版本** `1.1.1`

对象化的 **FlashDB**：在已经 `sfud.bind` 好的外挂 NOR 上开 **KV 库** 或 **时序库（TS）**。值按 MessagePack 存，Lua 侧直接收发 string / number / bool / table。

```lua
local flashdb = require("flashdb")
```

平台预加载模块，无需额外 `.lua` 文件。

**必须先有 [`sfud`](sfud.md) 对象。** 本模块不碰 SPI、不认片。FlashDB 把 sfud 当存储中间件：读写擦都走那颗已初始化的芯片，再按 `offset`/`size` 切分区。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `flashdb.kv`](#6-1-kv)
  - [6.2 `flashdb.ts`](#6-2-ts)
- [7. KV 对象方法](#7-kv-对象方法)
  - [7.1 `kv:set`](#7-1-set)
  - [7.2 `kv:get`](#7-2-get)
  - [7.3 `kv:del`](#7-3-del)
  - [7.4 `kv:name`](#7-4-name)
- [8. TS 对象方法](#8-ts-对象方法)
  - [8.1 `ts:append`](#8-1-append)
  - [8.2 `ts:last_time`](#8-2-last-time)
  - [8.3 `ts:iter`](#8-3-iter)
  - [8.4 `ts:peek_oldest`](#8-4-peek-oldest)
  - [8.5 `ts:pop_oldest`](#8-5-pop-oldest)
  - [8.6 `ts:del_oldest`](#8-6-del-oldest)
  - [8.7 `ts:clean`](#8-7-clean)
  - [8.8 `ts:name`](#8-8-name)
- [9. 挂载配置、同步与进度](#9-挂载配置同步与进度)
- [10. 存进去的值](#10-存进去的值)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

外挂 Flash 上两种库，互不替代：

| 库 | 工厂 | 典型用途 |
| --- | --- | --- |
| KV | `flashdb.kv(sfud, cfg)` | 配置、计数器、小表。按 key 读写，重启还在 |
| TS | `flashdb.ts(sfud, cfg)` | 日志、待上报队列。按时间序追加，可从最老的弹出 |

典型顺序：

1. SPI + CS GPIO → [`sfud.bind`](sfud.md)
2. `flash:capacity()` / `erase_gran()` 算分区（按粒度向下对齐，每区 ≥ **8KB**）
3. `flashdb.kv(flash, { offset, size, ... })` 和/或 `flashdb.ts(...)`
4. 同一颗芯片也可再给 LittleFS 一块不重叠的分区（见 [examples/nt26/storage/mix](../../../../examples/nt26/storage/mix)）

未挂载成功不要读写。大分区第一次格式化可能数秒到几十秒：请走异步挂载（配 `on_event` 或 `mount_timeout_ms`），否则整条 Lua 引擎线程被占住，心跳可能喂不上。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  sfud.bind → flashdb.kv / flashdb.ts → set/get / append  │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  flashdb 模块                                            │
│  · 在 sfud 芯片上登记分区（offset + size）                 │
│  · KV：键值；TS：追加日志                                  │
│  · 值先 MessagePack 再落盘                                │
│  · 钉住 sfud 对象（进而钉住 SPI / CS）                     │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  sfud                                                    │
│  分区内的读 / 写 / 擦都走这颗已认片的 NOR                  │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `kv`/`ts` **同步**挂载 | 可能预擦 + 建库 | **否** | 整条 Lua 引擎线程 |
| `kv`/`ts` **异步**挂载 | 后台建库；当前协程等到完成或超时 | **是**（当前协程让出） | 其它 Lua 任务能跑；`on_event` 在调度循环里进 |
| `set` / `get` / `append` 等 | 同步访问芯片 | **否** | 当前协程 + 引擎线程 |

异步条件：配置里出现 **`on_event` 函数**，或出现 **整数** `mount_timeout_ms`（含 `0`、`-1`）。两者都没有则同步。异步还要求当前在 `rt` 调度上下文里，否则 `nil, "async … mount requires rt context"`。

进度回调 **不在** 硬件中断里执行，通常也不是独立 `rt.task`。

---

## 3. 对象模型

两种 userdata，元表不同，方法不能混用。

```lua
kv:set(key, value)     -- 推荐
kv.set(kv, key, value) -- 等价
```

错误：`kv.set(key, value)`、`flashdb.set(kv, ...)`（模块表没有实例方法）、把 `kv` 传给 `ts:append`。

挂载成功会钉住传入的 sfud 对象。脚本须自己保住 `kv`/`ts`（以及 spi、cs、sfud）。`__gc` 拆库：对象被回收后分区不可再用。仍挂着库时不要 `flash:unbind()`。

布尔配置（`format`、`format_full_erase`、`rollover`）**只认 `true`/`false`**。数字 `0` 不是假：字段不是布尔就被忽略，落到默认值。`ts:iter` 回调的返回值见 [8.3](#8-3-iter)。

---

## 4. 常量与枚举

三个字符串常量，给 `cfg.format_erase_unit` 用。直接写 `"min"` / `"large"` / `"chip"` 也可以。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `flashdb.ERASE_MIN` | `"min"` | 按芯片最小擦除粒度（常见 4KB）一块块擦 | `format_erase_unit` |
| `flashdb.ERASE_LARGE` | `"large"` | 按芯片宣称的最大擦除块（常见 64KB） | 同上；**默认** |
| `flashdb.ERASE_CHIP` | `"chip"` | 整片一条擦除命令 | 仅当 `offset==0` 且 `size` 等于整片容量 |

其它字符串（含空串）按 `"large"` 处理。非字符串则用默认 `"large"`。

`chip` 但分区不是整片：不会发整片命令，回退成按块擦。同片还挂了 LittleFS / 另一块库时 **不要** 用 `chip`。

没有事件枚举。进度 `phase` / `kind` 是字符串，见 [第 9 节](#9-挂载配置同步与进度)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `sfud` | userdata | [`sfud.bind`](sfud.md) 成功且未 `unbind` |
| `cfg` | table | 见第 6、9 节 |
| `kv` / `ts` | userdata | 对应工厂的返回值 |
| `key` | string | KV 键，最长 **63** 字节（库上限 64 含结尾 0） |
| `value` | 可 MessagePack 的 Lua 值 | KV 编码后 ≤ **4096** 字节；TS 编码后 ≤ 该库 `max_len` |
| `cnt` | integer / number | TS 时间序，整数语义 |
| `on_event` | function | `function(ev)`，`ev` 为 table |

分区名 `cfg.name` 最长 **23** 字节。省略则自动生成 `kv_<offset>_<size>` / `ts_<offset>_<size>`。

---

## 6. 模块函数

---

### 6.1 `flashdb.kv(sfud, cfg)` {#6-1-kv}

在分区上打开 KV 库。

```lua
flashdb.kv(sfud, cfg)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `sfud` | 是 | sfud 对象 | 非法 / 未初始化 → `"invalid sfud object"` |
| `cfg` | 是 | table | 必须是表 |

`cfg` 字段：

| 键 | 必填 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `size` | **是** | integer | — | 分区字节数，须 `> 0` 且 ≥ **8192** |
| `offset` | 否 | integer | `0` | 在芯片内的起始地址；非整数当 0 |
| `name` | 否 | string | 自动生成 | 分区名，≤ 23 字节 |
| `sec_size` | 否 | integer | 芯片 `erase_gran`，再没有则 `4096` | 库扇区大小 |
| `format` | 否 | boolean | 省略 = **AUTO** | `true` 强制预擦再建；`false` 从不预擦。只认布尔 |
| `format_full_erase` | 否 | boolean | `true` | AUTO 时：分区头不像本库则先整区预擦。只认布尔 |
| `format_erase_unit` | 否 | string | `"large"` | 见第 4 节 |
| `default` | 否 | table | 无 | 首次可用的默认键值，最多 **32** 条；值编码后各 ≤ **512** 字节 |
| `on_event` | 否 | function | 无 | 有则 **异步**挂载，并收进度 |
| `mount_timeout_ms` | 否 | integer | 无此键则看是否异步 | 有此键（值为整数）则 **异步**。`-1` 一直等到完成 |
| `progress_step_pct` | 否 | integer | `10` | 进度回调步进，夹到 `1`～`100` |

成功：同步立刻返回 `kv`；异步在挂载结束后返回 `kv`。  
失败：`nil, err`。异步超时同样 `nil, err`。

```lua
local kv, err = flashdb.kv(flash, {
    name = "demo_kv",
    offset = 0,
    size = part_size,
    format_full_erase = true,
    format_erase_unit = flashdb.ERASE_LARGE,
    mount_timeout_ms = -1,
    on_event = on_kv,
    default = { ver = 1 },
})
```

整机最多 **8** 个 KV 实例。满则 `"too many kv instances"`。

AUTO 挂载后会做一次健康检查（默认键能否读到；没有默认键则试写再删探针）。失败会再擦一遍重建。

---

### 6.2 `flashdb.ts(sfud, cfg)` {#6-2-ts}

在分区上打开时序库。

```lua
flashdb.ts(sfud, cfg)
```

与 KV 共用：`sfud`、`offset`、`size`、`name`、`sec_size`、`format`、`format_full_erase`、`format_erase_unit`、`on_event`、`mount_timeout_ms`、`progress_step_pct`。

TS 额外字段：

| 键 | 必填 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `max_len` | **是** | integer | — | 单条记录 MessagePack 后的最大字节数。缺或 `0` → `"max_len required"` |
| `rollover` | 否 | boolean | `true` | `true`：写满擦最老扇区再写。`false`：写满拒绝新写入，已有记录保留。只认布尔 |
| `get_time` | 否 | function | 无 | 无参，立刻返回整数。FlashDB 内部取时用。脚本 `append` 不传第三参时 **不会**走它，而是「上次时间 + 1」 |

成功返回 `ts`，失败 `nil, err`。最多 **8** 个 TS 实例。

```lua
local ts, err = flashdb.ts(flash, {
    name = "demo_ts",
    offset = ts_off,
    size = ts_size,
    max_len = 500,
    rollover = true,
    format_full_erase = true,
    format_erase_unit = "large",
    mount_timeout_ms = -1,
    on_event = on_ts,
})
```

---

## 7. KV 对象方法

推荐 `kv:foo(...)`。对象被回收或挂载失败后的空壳：`set`/`get` 会失败。

---

### 7.1 `kv:set(key, value)` {#7-1-set}

写入（覆盖）一个键。`value` 先 MessagePack 再落盘。

```lua
kv:set(key, value)
```

| 参数 | 必填 | 类型 |
| --- | --- | --- |
| `key` | 是 | string |
| `value` | 是 | 可编码的 Lua 值 |

成功 `true`。失败 `false, err`。编码超过 4096 → 编码失败文案；库满 → `"set failed: storage full"`。

`http.save` 落到 KV 时，正文按 **字符串** 存，和本接口一致，`kv:get` 能读回 string。

---

### 7.2 `kv:get(key)` {#7-2-get}

按键读取并解回 Lua 值。

```lua
kv:get(key)
```

| 情况 | 返回 |
| --- | --- |
| 有值且解码成功 | 那个 Lua 值（1 个返回值） |
| 键不存在 | **只有** `nil`（没有第二返回值） |
| 解码失败 | 删除该键，**只有** `nil` |
| 未初始化 | `nil, "kv not initialized"` |
| 原始值 > 4096 | `nil, "value too large"` |
| 分配失败 | `nil, "alloc failed"` |

不要用 `nil, err = kv:get(k)` 判断「有没有这个键」：不存在也是单独一个 `nil`。

---

### 7.3 `kv:del(key)` {#7-3-del}

删键。

```lua
kv:del(key)
```

成功 `true`。未初始化或底层删除失败：只返回 `false`（**没有**错误串）。

---

### 7.4 `kv:name()` {#7-4-name}

分区名。槽已释放则 `nil`。

```lua
kv:name()
```

---

## 8. TS 对象方法

记录带一个整数时间序（`cnt`）。可以是墙上秒，也可以只是单调计数。`append` 省略第三参时用「当前最后一条的时间 + 1」，从 0 开始第一次就是 1。

---

### 8.1 `ts:append(value [, cnt])` {#8-1-append}

追加一条。

```lua
ts:append(value)
ts:append(value, cnt)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `value` | 是 | 可编码的 Lua 值 | 编码后须 `> 0` 且 ≤ `max_len` |
| `cnt` | 否 | integer / number | 时间序。省略则 last+1 |

成功 `true`。失败 `false, err`。写满且 `rollover=false` → `"append failed: storage full …"`。

---

### 8.2 `ts:last_time()` {#8-2-last-time}

当前最后一条的时间序。空库一般为 `0`。

```lua
ts:last_time()
```

成功 integer。未初始化 `nil, "ts not initialized"`。

---

### 8.3 `ts:iter(callback)` {#8-3-iter}

从旧到新遍历仍有效的记录。

```lua
ts:iter(callback)
```

`callback` 必须是 function，否则抛类型错。

```lua
function(cnt, value)
```

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `cnt` | integer | 该条时间序 |
| `value` | 任意 | 解码后的 Lua 值 |

**返回值决定是否继续：**

- 返回 `false` 或 `nil`：**停止**
- 返回 `true` 或其它在布尔语义下为真的值：**继续**
- 数字 **`0` 为真**，不能当「停止」。要停请返回 `false`

解码失败的记录会被标成已删并跳过。回调里抛错：记日志后 **中止** 遍历。`iter` 本身仍返回 `true`（遍历过程结束）。

成功 `true`。未初始化 `false, "ts not initialized"`。

回调在 **当前这次 `iter` 调用里同步执行**，占住引擎线程。保持短；不要 `rt.delay`、不要再挂盘。

---

### 8.4 `ts:peek_oldest()` {#8-4-peek-oldest}

看最老一条，不删除。

```lua
ts:peek_oldest()
```

| 情况 | 返回 |
| --- | --- |
| 有记录 | `true, cnt, value` |
| 空 | `true, nil, nil` |
| 失败 | `false, err` |

---

### 8.5 `ts:pop_oldest()` {#8-5-pop-oldest}

取出最老一条并标删除。返回值与 `peek_oldest` 相同。删失败：`false, err`。

```lua
ts:pop_oldest()
```

适合「读出上报，成功后再视为消费」。若要先看再决定删，用 `peek` + `del_oldest`。

---

### 8.6 `ts:del_oldest()` {#8-6-del-oldest}

只删最老一条，不把值返回给脚本。

```lua
ts:del_oldest()
```

有记录且删成功、或库已空：`true`。失败 `false, err`。

---

### 8.7 `ts:clean()` {#8-7-clean}

清空时序库。始终返回 `true`（槽无效时也是 `true`，不会报错）。

```lua
ts:clean()
```

---

### 8.8 `ts:name()` {#8-8-name}

分区名。槽已释放则 `nil`。

```lua
ts:name()
```

---

## 9. 挂载配置、同步与进度

### 9.1 `format` 三种模式

| `cfg.format` | 模式 | 行为 |
| --- | --- | --- |
| 省略 / 非布尔 | AUTO | 分区头不像本库且 `format_full_erase==true` 则预擦再建；KV 还会健康检查失败后再擦 |
| `true` | 强制 | 一定先擦分区再挂 |
| `false` | 从不预擦 | 不因头校验去整区擦（底层仍可能修复坏扇区） |

空片、换过别的 demo 的脏片：AUTO + `format_full_erase=true` + `"large"` 与官方 demo 一致，先按大块擦再写扇区头，避免按 4KB 修几百上千次。

合法旧库再挂：头校验通过，走 `fs_ok`，不会整区擦。

### 9.2 同步 vs 异步

| 配法 | 模式 | `kv`/`ts` 返回时机 |
| --- | --- | --- |
| 不写 `on_event`，也不写整数 `mount_timeout_ms` | 同步 | 函数返回前库已好或已失败 |
| `on_event = fn` | 异步 | 当前协程让出，完成后恢复，返回对象或 `nil, err` |
| `mount_timeout_ms = n`（整数） | 异步 | 同上；`-1` 无限等；`≥0` 为毫秒超时 |

大分区请异步，并给 `mount_timeout_ms = -1`。只配 `on_event` 时超时默认也是 `-1`。

`on_event` 在调度循环里调用。参数是一张表（邮箱投递后解码）。不要在里面 `delay`、不要再 `kv`/`ts` 挂盘。

### 9.3 进度表字段

不是每次都带齐。有则类型如下：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `phase` | string | 阶段名 |
| `kind` | string | `none` / `repair` / `format_all` / `force_erase` |
| `index` | integer | 已完成量或块序号 |
| `total` | integer | 总量 |
| `pct` | integer | `0`～`100`（仅带进度时） |
| `addr` | integer | 相关地址 |
| `repaired` | integer | 已修复扇区数 |

常见 `phase`：

| `phase` | 何时 |
| --- | --- |
| `check` | 开始检查 |
| `mount_progress` | 保底 0% / 100% |
| `format_start` | 开始格式化或预擦 |
| `erase_all` | 整区预擦开始 |
| `erase_progress` | 预擦进度 |
| `repair_sector` | 逐扇区修复（带 `addr`/`repaired`） |
| `build_progress` | 建头进度 |
| `fs_ok` | 旧库直接可用，没有整区格式化 |
| `mount_summary` | 本次有擦/修，结束汇总 |

`progress_step_pct` 控制擦/建进度的汇报密度。修复阶段前 32 个扇区会较密，之后降频，避免事件洪泛。

---

## 10. 存进去的值

KV / TS 都先 **MessagePack** 再写芯片。`get` / `iter` / `pop` 再解回 Lua。

适合：string、number、boolean、由这些组成的 table。不适合：function、userdata、带环的表、超大二进制（受 4096 / `max_len` 限制）。

KV 单值编码上限 **4096** 字节（含编码头）。TS 单条上限是该库的 `max_len`（demo 常用 500）。`http` 落到 FlashDB 时还会再扣约 8 字节给字符串头，正文请留余量。

`default` 里每条编码上限 **512**，最多 **32** 条。超了挂载失败 `"too many default kv entries"`。键太长的默认项会被跳过。

解码失败：KV 删掉该键并当不存在；TS 把该条标删除。

---

## 11. 错误与返回约定

缺参、`cfg` 不是表、`iter` 第二参不是函数：标准 Lua 参数错，需要 `pcall` 才能收。`kv:del` 失败、`ts:clean` 未初始化、`kv:get` 不存在或解码失败：**没有**第二返回值。

业务失败返回值：

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `kv` / `ts` | userdata | `nil, err` |
| `kv:set` / `ts:append` | `true` | `false, err` |
| `kv:get` | 值；或不存在单独 `nil` | 未初始化 / 值超限 / 分配失败见下表；解码失败只 `nil` |
| `kv:del` | `true` | 只 `false` |
| `ts:last_time` | integer | `nil, err` |
| `ts:iter` | `true` | 未初始化时 `false, err` |
| `ts:clean` | `true` | 未初始化也返回 `true` |
| `peek` / `pop` | `true, cnt, value` 或空 `true, nil, nil` | `false, err` |
| `del_oldest` | `true`（含库已空） | `false, err` |
| `name` | string 或 `nil` | 不抛 |

`kv init failed: …`、`ts init failed: …`、`set failed: …`、`append failed: … (cnt=N payload=M)`、`del oldest failed: …`、`peek oldest failed: …`、`pop oldest failed: …` 里的 `…` 来自下表底层短句。

底层短句（出现在上述前缀之后，或单独作为 `err`）：

| `err` 片段 | 可能原因 |
| --- | --- |
| `ok` | 成功映射，不会作为失败第二返回值 |
| `erase error` | 片上擦除失败：分区未按擦除粒度对齐、片选/接线、或芯片忙 |
| `read error` | 读分区失败：接线、供电、或分区头损坏 |
| `write error` | 写分区失败：写保护、接线、或介质损坏 |
| `partition not found` | 分区名未登记成功，或登记后已被拆掉再访问 |
| `kv name error` | 键名非法或找不到该键（过长、空、或库内格式不对） |
| `kv name exist` | 键名冲突（重建默认项或内部重名） |
| `storage full` | 分区写满。KV 删旧键再写；TS 开 `rollover` 或加大 `size` |
| `init failed` | 建库失败：分区太小、头损坏且不允许格式化、或介质不可用 |
| `unknown error` | 未单独翻译的底层码 |

挂载与对象固定 `err`：

| `err` | 可能原因 |
| --- | --- |
| `invalid sfud object` | 第一参不是已 `sfud.bind` 成功的对象，或芯片未认片 |
| `invalid kv cfg` | `size` 不是正整数、`offset` 为负、分区小于 8 KB、或 `name` 超过 23 字节 |
| `invalid ts cfg` | 同上（TS 配置） |
| `max_len required` | `flashdb.ts` 未给正整数 `max_len` |
| `too many kv instances` | 整机已有 8 个 KV |
| `too many ts instances` | 整机已有 8 个 TS |
| `too many default kv entries` | `default` 超过 32 条，或某条默认值编码失败（单条编码上限 512） |
| `partition register failed` | 分区名重名、范围越界、或与已挂分区重叠 |
| `partition erase failed` | 预擦失败：越出芯片容量、擦除粒度不对、或片上擦除失败 |
| `kv init failed: …` | 建 KV 失败；`…` 见上表底层短句 |
| `ts init failed: …` | 建 TS 失败；`…` 同上 |
| `async kv mount requires rt context` | 写了 `on_event` 或整数 `mount_timeout_ms`，但当前不在 `rt` 调度里 |
| `async ts mount requires rt context` | 同上（TS） |
| `on_event register failed` | 异步进度话题登记失败 |
| `mount thread failed` | 异步挂载线程没建起来（系统资源不足） |
| `mount failed` | 异步结束时没有更具体文案：超时、worker 失败、或结果丢失 |
| `mount slot invalid` | 异步完成后槽已释放（对象被回收、或槽号已无效） |
| `mutex failed` | 该库的互斥量创建失败 |
| `kv not initialized` | KV 对象已拆、挂载未完成、或挂载失败后的空壳 |
| `ts not initialized` | 同上（TS） |

读写与编解码 `err`：

| `err` | 可能原因 |
| --- | --- |
| `msgpack encode failed` | 编码失败且没有更细文案 |
| `set failed: …` | `kv:set` 底层写失败；`…` 常见 `storage full` / `write error` / `erase error` |
| `value too large` | `kv:get` 读到的编码长度超过 4096 |
| `alloc failed` | 读值或读 TS 记录时分配缓冲失败 |
| `ts encode failed (max_len=N): …` | `append` 编码失败；`N` 是配置的 `max_len`，`…` 是编码细节 |
| `ts encode failed (max_len=N)` | 同上，但没有更细编码文案 |
| `ts payload too large: encoded=A max_len=B` | 编码后长度 `A` 为 0 或大于 `max_len`=`B` |
| `append failed: … (cnt=N payload=M)` | TS 追加失败；`N` 是本次时间戳，`M` 是编码字节数 |
| `read failed` | TS 记录读回长度为 0 |
| `invalid arg` | 读最老记录时内部参数不完整（正常脚本路径少见） |
| `read oldest failed` | 遍历最老记录时读/分配失败 |
| `peek oldest failed` | `peek_oldest` 失败且没有更细文案 |
| `pop oldest failed` | `pop_oldest` 失败且没有更细文案 |
| `peek oldest failed: …` / `pop oldest failed: …` | 取出后标删除失败；`…` 见底层短句 |
| `del oldest failed` | `del_oldest` 失败且没有更细文案 |
| `del oldest failed: …` | 标删除失败；`…` 见底层短句 |
| `table too large` | `set`/`append`/`default` 单表项数过多 |
| `table depth exceeded` | 嵌套超过编码上限 |
| `float unsupported` | 值里出现了非整数 number |
| `string too large` | 单个 string 超编码上限 |
| `unsupported table key type: …` | 表键不是 string / number / boolean |
| `unsupported value type: …` | function / userdata / thread 等不能编码 |
| `msgpack buffer alloc failed` | 编码缓冲分配失败 |
| `encode overflow: used A/B bytes, next write needs C bytes` | 编码将超过上限（KV 4096，TS 为 `max_len`，默认项 512） |
| `encode overflow: used A/B bytes (…)` | 同上，带底层写失败说明 |
| `cmp write failed` | 编码写缓冲失败且没有溢出细节 |
| `not msgpack data` | 解码侧看到的不是本库格式（`get` 会删键后只返回 `nil`，一般看不到这句） |

诊断：`invalid sfud object` 先确认 `sfud.bind` 成功；`storage full` 查分区大小和 `rollover`；`async * requires rt context` 不要在非 `rt` 协程里写 `on_event` / `mount_timeout_ms`；`value too large` / `ts payload too large` 缩小写入结构或加大 `max_len`。

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| KV 实例 | **8** | 整机 |
| TS 实例 | **8** | 整机 |
| 分区最小 | **8192** 字节 | |
| 分区名 | **23** 字节 | |
| KV 键 | **63** 字节 | |
| KV 值（编码后） | **4096** 字节 | |
| KV `default` | **32** 条，每条编码 ≤ **512** | |
| TS 单条 | `cfg.max_len` | |
| sfud 芯片 | 先过 [`sfud`](sfud.md) 的 8 槽 | 多个库可共享 **同一** sfud 对象 |

`kv`/`ts` 钉住 sfud。`__gc` 与虚拟机退出拆库、解引用。id / 分区名不保证跨固件布局复用。

同片多库：分区 **不要重叠**。`offset`/`size` 按 `flash:erase_gran()` 对齐。换过整片 KV demo 再跑 mix，各区会按自己的 AUTO 规则格式化，旧数据不共享。

---

## 13. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 认片、容量 | [`sfud`](sfud.md) |
| 少量配置 / 状态 | **`flashdb.kv`** |
| 追加日志、待发队列 | **`flashdb.ts`**（`pop_oldest` 消费） |
| 文件路径、HTTP 下大文件 | [`lfs`](lfs.md)（同样先 sfud） |
| 同片文件 + 日志 + 配置 | 一块 sfud，三块不重叠分区（`storage/mix`） |
| 模组内部几十 KB | `ufs` / `ublob`，不是本模块 |

KV 不是文件系统。TS 不是按墙钟自动对齐的 cron。

---

## 14. 完整示例

先认片再挂 KV。完整工程（含脚位、`rtu_config.cfg`）见 [examples/nt26/storage/flashdb_kv](../../../../examples/nt26/storage/flashdb_kv)；TS 见 `flashdb_ts`。

```lua
local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local flashdb = require("flashdb")
local log = require("log")

local function on_event(ev)
    if type(ev) == "table" then
        log.info("kv %s pct=%s", tostring(ev.phase), tostring(ev.pct))
    end
end

local spi_dev = spi.new(spi.SPI0, {
    bus_hz = 24 * 1000000,
    data_bits = 8,
    frame_format = spi.CPOL0_CPHA0,
    work_mode = spi.WORK_MODE_FULL_DUPLEX,
})
local cs = gpio.open(gpio.BY_GPIO, 8)
assert(cs:config(true, true, gpio.PULL_UP))

local flash, fe = sfud.bind(spi_dev, "flash0", cs, { cs_active_low = true })
if not flash then
    log.info("sfud: %s", tostring(fe))
    return
end

local gran = flash:erase_gran()
local size = flash:capacity() - (flash:capacity() % gran)

local kv, ke = flashdb.kv(flash, {
    name = "demo_kv",
    offset = 0,
    size = size,
    format_full_erase = true,
    format_erase_unit = flashdb.ERASE_LARGE,
    mount_timeout_ms = -1,
    on_event = on_event,
})
if not kv then
    log.info("kv: %s", tostring(ke))
    return
end

assert(kv:set("node", { seq = 1, name = "nt26" }))
local node = kv:get("node")
log.info("seq=%s", tostring(node and node.seq))
```

TS 消费队列：

```lua
local ts = assert(flashdb.ts(flash, {
    name = "demo_ts",
    offset = 0,
    size = size,
    max_len = 500,
    rollover = true,
    mount_timeout_ms = -1,
}))
assert(ts:append({ t = 1, msg = "hello" }))
local ok, cnt, val = ts:pop_oldest()
if ok and val then
    log.info("pop cnt=%s msg=%s", tostring(cnt), tostring(val.msg))
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误文案/错误码与可能原因 |
| 1.1.1 | 2026-09-09 | 示例片选改为 `gpio.BY_GPIO` |
