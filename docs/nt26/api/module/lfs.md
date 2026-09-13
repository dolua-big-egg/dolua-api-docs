# lfs

**文档版本** `1.1.1`

对象化的 **LittleFS**：在已经 `sfud.bind` 好的外挂 NOR 上挂一块 POSIX 风格文件系统。路径如 `"/demo.txt"`，可建目录、开关文件、流式读写和摘要。

```lua
local lfs = require("lfs")
```

平台预加载模块，无需额外 `.lua` 文件。

**必须先有 [`sfud`](sfud.md) 对象。** 本模块不碰 SPI、不认片。读写擦都走那颗已初始化的芯片，再按 `offset`/`size` 切分区。同一颗芯片上可以再挂 [`flashdb`](flashdb.md) 的 KV/TS，分区不要重叠。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `lfs.mount`](#6-1-mount)
- [7. 文件系统对象](#7-文件系统对象)
  - [7.1 `fs:open`](#7-1-open)
  - [7.2 `fs:mkdir`](#7-2-mkdir)
  - [7.3 `fs:remove`](#7-3-remove)
  - [7.4 `fs:rename`](#7-4-rename)
  - [7.5 `fs:stat`](#7-5-stat)
  - [7.6 `fs:dir`](#7-6-dir)
  - [7.7 `fs:name`](#7-7-name)
  - [7.8 `fs:info`](#7-8-info)
  - [7.9 `fs:unmount`](#7-9-unmount)
- [8. 文件对象](#8-文件对象)
  - [8.1 `f:read`](#8-1-read)
  - [8.2 `f:write`](#8-2-write)
  - [8.3 `f:seek`](#8-3-seek)
  - [8.4 `f:tell`](#8-4-tell)
  - [8.5 `f:size`](#8-5-size)
  - [8.6 `f:sync`](#8-6-sync)
  - [8.7 `f:crc8`](#8-7-crc8)
  - [8.8 `f:crc16`](#8-8-crc16)
  - [8.9 `f:crc32`](#8-9-crc32)
  - [8.10 `f:md5`](#8-10-md5)
  - [8.11 `f:close`](#8-11-close)
- [9. 目录对象](#9-目录对象)
  - [9.1 `d:read`](#9-1-read)
  - [9.2 `d:close`](#9-2-close)
- [10. 挂载配置、同步与进度](#10-挂载配置同步与进度)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

LittleFS 是面向 NOR 的日志结构文件系统：断电相对安全、磨损均衡，适合外挂 Flash 上的文件，而不是键值。

典型顺序：

1. SPI + CS GPIO → [`sfud.bind`](sfud.md)
2. 用 `capacity()` / `erase_gran()` 算分区（按粒度对齐，≥ **8KB**）
3. `lfs.mount(flash, cfg)` 得到 `fs`
4. `fs:open` / `mkdir` / `dir` 操作路径
5. 不用了 `fs:unmount()`

`http.save.lfs(fs, path)` 要求 **已经挂好** 的 `fs`，HTTP 不会替你 mount。

大分区第一次格式化可能很久：请走 **异步挂载**（配 `on_event` 或 `mount_timeout_ms`）。同步挂载会占住整条 Lua 引擎线程。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  sfud.bind → lfs.mount → fs:open / mkdir / dir           │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  lfs 模块                                                │
│  · 在 sfud 芯片上登记分区                                 │
│  · 文件系统 / 文件 / 目录 三种对象                        │
│  · 钉住 sfud（进而钉住 SPI / CS）                         │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  sfud → SPI + CS → 外挂 NOR                              │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `mount` **同步** | 可能 format + 挂载 | **否** | 整条 Lua 引擎线程 |
| `mount` **异步** | 后台挂载；当前协程等到完成或超时 | **是** | 其它任务能跑；`on_event` 进调度循环 |
| `open` / 读写 / `mkdir` 等 | 同步访问芯片 | **否** | 当前协程 + 引擎线程 |
| `crc*` / `md5` | 按 1KB 块流式读盘累加 | **否** | 同上；不把整文件装进 Lua 堆 |

异步条件：配置里出现 **`on_event` 函数**，或出现 **整数** `mount_timeout_ms`。两者都没有则同步。异步须在 `rt` 调度上下文，否则 `"async lfs mount requires rt context"`。

**`format_full_erase` / `format_erase_unit` / 进度回调只在异步路径生效。** 同步挂载只认 `format`，空片或坏超级块由底层 AUTO 直接 format，没有预擦进度。

---

## 3. 对象模型

三种 userdata，元表不同：

| 对象 | 来源 | 作用 |
| --- | --- | --- |
| `fs` | `lfs.mount` | 分区上的文件系统 |
| `f` | `fs:open` | 已打开的文件 |
| `d` | `fs:dir` | 已打开的目录迭代 |

推荐冒号调用：`fs:open(path, "w")`。`fs.open(fs, path, "w")` 等价。

`mount` 钉住 sfud。`open`/`dir` 再钉住 `fs`。脚本须保住这些引用。`__gc`：文件/目录会 `close`，`fs` 会 `unmount`。

已 `unmount` 再调 `fs` 方法会 **抛** `"lfs fs closed"`。已关闭的文件/目录返回 `nil, "bad file"`。

仍有文件或目录开着时不要 `unmount`，也不要 `flash:unbind()`。

布尔配置（`format`、`format_full_erase`）**只认 `true`/`false`**。数字 `0` 不是假，字段会被忽略。`f:md5` 的 `raw` 走布尔语义：数字 **`0` 为真**，要 hex 请省略或传 `false`。

---

## 4. 常量与枚举

三个字符串常量，给异步挂载的 `cfg.format_erase_unit`。直接写 `"min"` / `"large"` / `"chip"` 也可以。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `lfs.ERASE_MIN` | `"min"` | 按最小擦除粒度（常见 4KB）一块块擦 | `format_erase_unit` |
| `lfs.ERASE_LARGE` | `"large"` | 按芯片最大擦除块（常见 64KB） | 同上；**默认** |
| `lfs.ERASE_CHIP` | `"chip"` | 整片一条命令 | 仅 `offset==0` 且 `size` 等于整片容量 |

其它字符串按 `"large"`。`chip` 但不是整片：回退成按块擦。同片还挂了 FlashDB 时不要用 `chip`。

没有事件枚举。进度 `phase` 见 [第 10 节](#10-挂载配置同步与进度)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `sfud` | userdata | [`sfud.bind`](sfud.md) 成功且未 `unbind` |
| `cfg` | table | 见 `mount` |
| `fs` / `f` / `d` | userdata | 对应工厂/open/dir 的返回值 |
| `path` | string | POSIX 风格，建议以 `/` 开头。组件名最长 **255** |
| `mode` | string | `r` `w` `a` `r+` `w+` `a+` |
| `on_event` | function | `function(ev)`，`ev` 为 table |

分区名 `cfg.name` 最长 **23** 字节。省略则 `lfs_<offset>_<size>`。

---

## 6. 模块函数

---

### 6.1 `lfs.mount(sfud, cfg)` {#6-1-mount}

在分区上挂载 LittleFS。

```lua
lfs.mount(sfud, cfg)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `sfud` | 是 | sfud 对象 | 非法 → `"invalid sfud object"` |
| `cfg` | 是 | table | 必须是表 |

`cfg` 字段：

| 键 | 必填 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `size` | **是** | integer | — | 分区字节数，须 `> 0` 且 ≥ **8192**；且 `offset+size` 不得超出芯片容量 |
| `offset` | 否 | integer | `0` | 芯片内起始；非整数当 0。须按块大小对齐 |
| `name` | 否 | string | 自动生成 | ≤ 23 字节 |
| `block_size` | 否 | integer | 芯片 `erase_gran`，再没有则 `4096` | 须是擦除粒度的整数倍；`offset`/`size` 须整除它 |
| `format` | 否 | boolean | 省略 = **AUTO** | `true` 强制 format；`false` 只挂不建。只认布尔 |
| `format_full_erase` | 否 | boolean | `true` | **仅异步**：格式化前是否整区预擦。`false` = 只写超级块，用到哪块再擦哪块 |
| `format_erase_unit` | 否 | string | `"large"` | **仅异步**预擦步长 |
| `on_event` | 否 | function | 无 | 有则 **异步**，并收进度 |
| `mount_timeout_ms` | 否 | integer | 无此键则看是否异步 | 有整数键则 **异步**。`-1` 一直等到完成 |
| `progress_step_pct` | 否 | integer | `10` | 预擦进度步进，夹到 `1`～`100` |

成功返回 `fs`。失败 `nil, err`。越界 → `"partition oob"`。整机最多 **4** 个已挂实例。

```lua
local fs, err = lfs.mount(flash, {
    name = "demo_fs",
    offset = 0,
    size = part_size,
    format_full_erase = false,
    format_erase_unit = lfs.ERASE_LARGE,
    mount_timeout_ms = -1,
    on_event = on_fs,
})
```

官方 littlefs demo：能挂就直接挂；空片/坏超级块再 format。`format_full_erase = false` 避免第一次空片把整片按块擦完。

---

## 7. 文件系统对象

---

### 7.1 `fs:open(path [, mode])` {#7-1-open}

打开或创建文件。

```lua
fs:open(path)
fs:open(path, mode)
```

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `path` | 是 | — | 文件路径 |
| `mode` | 否 | `"r"` | 见下表 |

| `mode` | 含义 |
| --- | --- |
| `r` | 只读，文件必须存在 |
| `w` | 只写，没有则创建，有则截断 |
| `a` | 只写，没有则创建，写在末尾 |
| `r+` | 读写，必须存在 |
| `w+` | 读写，创建或截断 |
| `a+` | 读写，创建，写在末尾 |

非法 mode → `nil, "bad mode"`。成功返回文件对象。失败 `nil, err`（如 `"no entry"`）。

打开后须 `f:close()`。`__gc` 会关，但不要靠回收落盘。

---

### 7.2 `fs:mkdir(path)` {#7-2-mkdir}

建一层目录。父目录必须已存在。

```lua
fs:mkdir(path)
```

成功 `true`。已存在 → `nil, "exist"`。

---

### 7.3 `fs:remove(path)` {#7-3-remove}

删文件，或删空目录。

```lua
fs:remove(path)
```

成功 `true`。目录非空 → `"not empty"`。不存在 → `"no entry"`。

`http` 落到本文件系统且 body 长度为 0 时，效果是删同名文件（没有也算成功）。

---

### 7.4 `fs:rename(old, new)` {#7-4-rename}

改名或移动（同一文件系统内）。

```lua
fs:rename(old, new)
```

成功 `true`。失败 `nil, err`。

---

### 7.5 `fs:stat(path)` {#7-5-stat}

查一项。

```lua
fs:stat(path)
```

成功返回表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `name` | string | 最后一级名字 |
| `type` | string | `"file"` 或 `"dir"` |
| `size` | integer | 文件字节数；目录一般为 0 |

失败 `nil, err`。

---

### 7.6 `fs:dir([path])` {#7-6-dir}

打开目录迭代器。

```lua
fs:dir()
fs:dir(path)
```

`path` 省略为 `"/"`。成功返回目录对象。然后循环 `d:read()`，用完 `d:close()`。

---

### 7.7 `fs:name()` {#7-7-name}

分区名。没有则空串。

```lua
fs:name()
```

---

### 7.8 `fs:info()` {#7-8-info}

分区信息表。

```lua
fs:info()
```

| 字段 | 类型 |
| --- | --- |
| `name` | string |
| `offset` | integer |
| `size` | integer |
| `block_size` | integer |

---

### 7.9 `fs:unmount()` {#7-9-unmount}

卸载并解开对 sfud 的钉住。之后这个对象上的方法会抛 `"lfs fs closed"`。

```lua
fs:unmount()
```

成功 `true`。失败 `false, "unmount failed"`。重复 unmount 仍是 `true`。`__gc` 也会走卸载。

先关掉仍打开的文件和目录。

---

## 8. 文件对象

未打开或已 close：多数方法 `nil, "bad file"`。

---

### 8.1 `f:read([n])` {#8-1-read}

从当前游标读。

```lua
f:read()
f:read(n)
```

| 参数 | 含义 |
| --- | --- |
| 省略 / `nil` | 读到文件末尾 |
| `n` ≥ 0 | 最多 `n` 字节 |
| `n` < 0 | `nil, "invalid"` |

成功返回 string（可能短于 `n`；已在末尾则 **空串**，不是 `nil`）。失败 `nil, err`。内部按 1KB 块拼，整文件读大会抬高 Lua 堆，大文件请分段或用摘要 API。

---

### 8.2 `f:write(data)` {#8-2-write}

从当前游标写原始字节。

```lua
f:write(data)
```

`data` 必须是 string。成功返回 **写出的字节数**（integer）。失败 `nil, err`。写完重要数据请 `sync` 或 `close`。

---

### 8.3 `f:seek([whence [, offset]])` {#8-3-seek}

移动游标，返回新的绝对位置。

```lua
f:seek()
f:seek(whence)
f:seek(whence, offset)
```

| 参数 | 默认 | 取值 |
| --- | --- | --- |
| `whence` | `"set"` | `"set"` 文件头、`"cur"` 当前位置、`"end"` 文件尾 |
| `offset` | `0` | 相对 `whence` 的偏移（可负，视 whence） |

非法 whence → `nil, "invalid"`。

---

### 8.4 `f:tell()` {#8-4-tell}

当前游标（从 0 起的绝对偏移）。

```lua
f:tell()
```

成功 integer。

---

### 8.5 `f:size()` {#8-5-size}

文件当前长度（字节）。

```lua
f:size()
```

---

### 8.6 `f:sync()` {#8-6-sync}

把缓存刷到 Flash。

```lua
f:sync()
```

成功 `true`。失败 `nil, err`。

---

### 8.7 `f:crc8([offset [, len]])` {#8-7-crc8}

流式 CRC-8/SMBUS（初值 0）。返回 `0`～`255`。不改变调用方看到的文件游标。

```lua
f:crc8()
f:crc8(offset)
f:crc8(offset, len)
```

区间语义见 [8.7–8.10 共用](#871010-摘要区间)。与 `tls.crc8` 默认算法对齐。

---

### 8.8 `f:crc16([offset [, len]])` {#8-8-crc16}

CRC-16/IBM（ARC），不是 CCITT，也不是 Modbus（初值 FFFF）。返回 `0`～`0xFFFF`。

```lua
f:crc16()
f:crc16(offset)
f:crc16(offset, len)
```

---

### 8.9 `f:crc32([offset [, len]])` {#8-9-crc32}

CRC-32/ISO-HDLC（以太网 / ZIP）。返回 32 位整数。与 `tls.crc32`、ublob 的 crc32 默认一致。MCU OTA 整包校验用这个。

```lua
f:crc32()
f:crc32(offset)
f:crc32(offset, len)
```

---

### 8.10 `f:md5([offset [, len [, raw]]])` {#8-10-md5}

流式 MD5。固件若未编进 MD5：`nil, "md5 not enabled"`。

```lua
f:md5()
f:md5(offset)
f:md5(offset, len)
f:md5(offset, len, raw)
```

| `raw` | 返回 |
| --- | --- |
| 省略 / `false` / `nil` | 32 字符小写 hex |
| `true` | 16 字节二进制 string |

`raw` 固定是 **第四参**。整文件要 raw 请写 `f:md5(0, nil, true)`，不要 `f:md5(true)`（会被当成 offset）。

数字 `0` 当作 `raw` 时为 **真**。要 hex 写 `false` 或省略。

---

#### 8.7–8.10 摘要区间

四个方法共用：

| 调用 | 区间 |
| --- | --- |
| `f:xxx()` | 整文件：`offset=0`，到文件尾 |
| `f:xxx(offset)` | 从 `offset` 到文件尾。`offset` 超出文件大小 → `"invalid param"` |
| `f:xxx(offset, len)` | `[offset, offset+len)`，超出文件尾则截断。`offset` 已超过文件大小 → 空区间，仍返回「空输入」摘要 |

`offset`/`len` 不能为负。空区间仍有合法摘要（例如 CRC32 空包为 `0`）。计算期间按 1KB 读盘，不把整包装进 Lua 字符串。

---

### 8.11 `f:close()` {#8-11-close}

关闭文件，刷盘并解开对 `fs` 的钉住。

```lua
f:close()
```

成功 `true`。底层 close 失败 `false, err`。已关闭再 close 仍是 `true`。

---

## 9. 目录对象

---

### 9.1 `d:read()` {#9-1-read}

读下一项。

```lua
d:read()
```

| 情况 | 返回 |
| --- | --- |
| 还有项 | 表：`name` / `type`（`"file"` 或 `"dir"`）/ `size` |
| 列完 | **只有** `nil` |
| 失败 | `nil, err` |

LittleFS 通常会先给出 `"."`、`".."`，脚本应跳过。

```lua
local d = assert(fs:dir("/"))
while true do
    local e, err = d:read()
    if e == nil then
        if err then error(err) end
        break
    end
    if e.name ~= "." and e.name ~= ".." then
        log.info("%s %s %s", e.type, e.name, tostring(e.size))
    end
end
d:close()
```

---

### 9.2 `d:close()` {#9-2-close}

关闭目录迭代器。成功 `true`；失败 `false, err`。`__gc` 会关。

```lua
d:close()
```

---

## 10. 挂载配置、同步与进度

### 10.1 `format`

| `cfg.format` | 模式 | 行为 |
| --- | --- | --- |
| 省略 / 非布尔 | AUTO | 能挂就挂；失败再 format（异步路径会先按 `format_full_erase` 决定是否整区预擦） |
| `true` | 强制 | 一定 format。异步且 `format_full_erase=true` 时先预擦 |
| `false` | 只挂 | 不 format；坏盘直接失败 |

合法旧文件系统再挂：异步走 `fs_ok`，不会整区擦。

### 10.2 同步 vs 异步

| 配法 | 模式 |
| --- | --- |
| 不写 `on_event`，也不写整数 `mount_timeout_ms` | 同步：返回前挂好或失败。无进度、不走 Lua 侧预擦 |
| `on_event` 和/或整数 `mount_timeout_ms` | 异步：当前协程让出。`-1` 无限等 |

大分区请异步 + `mount_timeout_ms = -1`。`on_event` 在调度循环里执行，参数是表。不要在里面 `delay`、不要再 `mount`。

### 10.3 进度表

| 字段 | 类型 | 何时有 |
| --- | --- | --- |
| `phase` | string | 每次 |
| `index` / `total` / `pct` | integer | 带进度的阶段 |

常见 `phase`：

| `phase` | 含义 |
| --- | --- |
| `check` | 开始检查 |
| `mount_progress` | 保底 0% / 100% |
| `fs_ok` | 旧文件系统直接可用 |
| `format_start` | 将要格式化 |
| `erase_all` | 整区预擦开始 |
| `erase_progress` | 预擦进度（有 `pct`） |
| `erase_skip` | `format_full_erase=false`，跳过整区预擦 |

LFS 进度表 **没有** FlashDB 那种 `kind` / `addr` / `repaired`。

---

## 11. 错误与返回约定

缺参、`cfg` 不是表、路径类型不对：标准 Lua 参数错，需要 `pcall` 才能收。  
已卸载的 `fs`：**抛** `"lfs fs closed"`。`d:read` 列完是单独一个 `nil`（不是错误）。

业务失败：

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `mount` | `fs` | `nil, err` |
| `open` / `dir` / `stat` | 对象或表 | `nil, err` |
| `mkdir` / `remove` / `rename` / `sync` | `true` | `nil, err` |
| `unmount` | `true` | `false, "unmount failed"` |
| `name` / `info` | string / 表 | fs 已关则抛 |
| `f:read` / 摘要 | string 或 integer | `nil, err` |
| `f:write` / `seek` / `tell` / `size` | integer | `nil, err` |
| `f:close` / `d:close` | `true` | `false, err` |
| `d:read` | 表；列完单独 `nil` | `nil, err` |

抛错摘要：

| 摘要 | 可能原因 |
| --- | --- |
| `lfs fs closed` | `fs` 已 `unmount` 或被回收后再调 `open`/`mkdir`/`stat` 等 |

挂载与对象固定 `err`：

| `err` | 可能原因 |
| --- | --- |
| `invalid sfud object` | 第一参不是已 `sfud.bind` 成功的对象，或芯片未认片 |
| `invalid lfs cfg` | `size` 不是正整数、小于 8 KB、`offset` 为负、或 `name` 超过 23 字节 |
| `partition oob` | `offset + size` 超出芯片容量 |
| `async lfs mount requires rt context` | 写了 `on_event` 或整数 `mount_timeout_ms`，但当前不在 `rt` 调度里 |
| `too many lfs mount jobs` | 同时进行的异步挂载超过 4 |
| `too many lfs instances` | 整机已挂满 4 个 LFS |
| `on_event register failed` | 异步进度话题登记失败 |
| `mount thread failed` | 异步挂载线程没建起来 |
| `partition register failed` | 分区名重名、范围非法、或与已挂分区冲突 |
| `mutex failed` | 该文件系统的互斥量创建失败 |
| `mount failed` | 挂载失败且没有更细码；异步超时或结果丢失时也会落到这句 |
| `lfs init failed` | 挂载/格式化失败，且不是上面几条专用码 |
| `mount job invalid` | 异步完成后任务号已无效 |
| `mount userdata failed` | 挂载成功但组装 `fs` 对象失败（随后会卸掉刚挂上的盘） |
| `bad mode` | `open` 的 mode 不是 `r` / `w` / `a` / `r+` / `w+` / `a+` |
| `unmount failed` | `unmount` 底层卸载失败（仍有未关文件，或介质忙） |
| `invalid param` | 摘要/CRC 的 `offset` 为负、或只给 offset 却越过文件末尾、或 `len` 为负 |
| `no mem` | 把摘要打成 hex 时内部缓冲不够（正常 16 字节 MD5 路径不应出现） |
| `md5 not enabled` | 当前固件未编进 MD5 |
| `md5 starts failed` | MD5 上下文启动失败 |
| `md5 update failed` | 流式更新 MD5 失败 |
| `md5 finish failed` | MD5 收尾失败 |

文件系统层短句（`open`/`read`/`write`/`mkdir`/`remove`/`rename`/`stat`/`dir`/`sync`/`close` 等）：

| `err` | 可能原因 |
| --- | --- |
| `ok` | 成功映射，不会作为失败第二返回值 |
| `io error` | 片上读写失败：接线、片选、或芯片无应答 |
| `corrupt` | 文件系统元数据损坏，考虑按配置格式化后重挂 |
| `no entry` | 路径不存在 |
| `exist` | 目标已存在（`mkdir` 等同名冲突） |
| `not dir` | 路径存在但不是目录 |
| `is dir` | 对目录做了文件操作（当文件 `open`/`remove` 等） |
| `not empty` | 删非空目录 |
| `bad file` | 文件/目录对象已 `close`，或从未打开成功 |
| `file too big` | 写入后将超过 LittleFS 单文件上限 |
| `invalid` | 参数对当前操作不合法（偏移、标志、或路径形态） |
| `no space` | 分区没有剩余空间 |
| `no memory` | 文件系统运行时内存不足 |
| `no attr` | 请求的属性不存在 |
| `name too long` | 路径组件超过 255 字节 |
| `lfs error` | 未单独翻译的文件系统码 |

诊断：`partition oob` 用 `flash:capacity()` 重算 `offset`/`size`；`no entry` 先 `stat`；`bad file` 不要对已 `close` 的句柄再读；`lfs fs closed` 说明 `fs` 已卸，要重新 `mount`。

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 同时挂载的 LFS | **4** | 整机 |
| 分区最小 | **8192** 字节 | |
| 分区名 | **23** 字节 | |
| 路径组件名 | **255** 字节 | |
| 默认块大小 | 芯片擦除粒度 / 4096 | `block_size` |
| 读/摘要块 | **1024** 字节 | 内部切片，不是 API 上限 |
| sfud 芯片 | 先过 [`sfud`](sfud.md) | 多库可共享同一 sfud |

`fs` 钉住 sfud；文件/目录钉住 `fs`。虚拟机退出或 `__gc` 会关文件、卸载。

`offset`/`size` 须按 `block_size`（默认即 `erase_gran`）对齐。和 FlashDB 同片时分区不要重叠。

---

## 13. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 认片 | [`sfud`](sfud.md) |
| 文件、目录、HTTP 下大文件 | **`lfs`** |
| 少量键值 / 时序日志 | [`flashdb`](flashdb.md) |
| 同片文件 + KV + TS | 一块 sfud，三块不重叠分区（`storage/mix`） |
| 模组内部几十 KB | `ufs` / `ublob` |

不要在 LittleFS 里用裸 `sfud:write` 改同一分区。

---

## 14. 完整示例

先认片再挂整片。完整工程见 [examples/nt26/storage/littlefs](../../../../examples/nt26/storage/littlefs)。

```lua
local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local lfs = require("lfs")
local log = require("log")

local function on_event(ev)
    if type(ev) == "table" then
        log.info("lfs %s pct=%s", tostring(ev.phase), tostring(ev.pct))
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

local fs, err = lfs.mount(flash, {
    name = "demo_fs",
    offset = 0,
    size = size,
    format_full_erase = false,
    format_erase_unit = lfs.ERASE_LARGE,
    mount_timeout_ms = -1,
    on_event = on_event,
})
if not fs then
    log.info("mount: %s", tostring(err))
    return
end

local f = assert(fs:open("/demo.txt", "w"))
assert(f:write("hello-littlefs"))
assert(f:close())

f = assert(fs:open("/demo.txt", "r"))
local data = assert(f:read())
log.info("read=%s crc32=%s", data, tostring(f:crc32()))
f:close()
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误文案/错误码与可能原因 |
| 1.1.1 | 2026-09-09 | 示例片选改为 `gpio.BY_GPIO` |
