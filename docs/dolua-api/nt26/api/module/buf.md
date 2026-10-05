# buf

**文档版本** `1.0.0`

一块可改的字节缓冲。句柄在 Lua 里，字节留在缓冲自己的额度里。适合编码表和字库的随机读取、按 StringBuilder 组字符串、以及把整数直接接成二进制，避免在 Lua 里反复拼接 string、或把整张表建成 Lua table。

```lua
local buf = require("buf")
```

平台预加载模块，无需额外 `.lua` 文件。

载荷**不计入**脚本虚拟机那 **700 KB** 堆（见 [资源 · Lua 堆](../../resources/README.md#2-lua-堆ram)）。全部未关闭对象的**容量**加在一起最多 **200 KB**（`buf.limit()` = 204800）。这 200 KB 仍占用模组内存；堆本身不够时，额度还有剩余也会失败。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 和 Lua 直接操作数据的差异](#3-和-lua-直接操作数据的差异)
- [4. 设计用途](#4-设计用途)
- [5. 对象模型](#5-对象模型)
- [6. 阻塞语义](#6-阻塞语义)
- [7. 常量与枚举](#7-常量与枚举)
- [8. 类型约定](#8-类型约定)
- [9. 模块函数](#9-模块函数)
  - [9.1 `buf.limit`](#9-1-limit)
  - [9.2 `buf.used`](#9-2-used)
  - [9.3 `buf.alloc`](#9-3-alloc)
  - [9.4 `buf.load`](#9-4-load)
  - [9.5 `buf.from`](#9-5-from)
- [10. 对象方法](#10-对象方法)
  - [10.1 `b:size`](#10-1-size)
  - [10.2 `b:cap`](#10-2-cap)
  - [10.3 `b:u8`](#10-3-u8)
  - [10.4 `b:u16`](#10-4-u16)
  - [10.5 `b:u32`](#10-5-u32)
  - [10.6 `b:set_u8`](#10-6-set_u8)
  - [10.7 `b:set_u16`](#10-7-set_u16)
  - [10.8 `b:set_u32`](#10-8-set_u32)
  - [10.9 `b:search_u16`](#10-9-search_u16)
  - [10.10 `b:append`](#10-10-append)
  - [10.11 `b:append_u8`](#10-11-append_u8)
  - [10.12 `b:append_u16`](#10-12-append_u16)
  - [10.13 `b:insert`](#10-13-insert)
  - [10.14 `b:remove`](#10-14-remove)
  - [10.15 `b:replace`](#10-15-replace)
  - [10.16 `b:clear`](#10-16-clear)
  - [10.17 `b:reserve`](#10-17-reserve)
  - [10.18 `b:string`](#10-18-string)
  - [10.19 `b:close`](#10-19-close)
- [11. 长度与容量](#11-长度与容量)
- [12. 错误与返回约定](#12-错误与返回约定)
- [13. 资源上限与生命周期](#13-资源上限与生命周期)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本要碰一块较大的二进制时，用本模块拿一个对象，在对象上按偏移读整数、改一段、最后再要一份 Lua string。

三件事是按这个对象定的：

1. **编码表 / 字库**：`load` 把 `.bin` 放进缓冲，用 `u16` / `search_u16` 查，得到整数，不把几千项建成 Lua 表。
2. **StringBuilder**：`alloc` 时按预计长度留容量，`append` / `insert` / `remove` / `replace` 改在这块缓冲里，结束时 `string()` 一次。
3. **二进制组包**：`append_u8` / `append_u16` 传入整数，中间不先做出一节节短 string。

`load` 的字节来自 [`ublob`](ublob.md) 的明文。读完就放进自己的缓冲，不占用 `ublob` 的 view 名额。

配置、短表继续用 [`ufs`](ufs.md)。要落盘的文件继续用 `ublob`。本模块是运行时的一块内存，关虚拟机或 `close` 之后字节就没了，不会自己写回存储。

---

## 2. 框架结构

```
┌──────────────────────────────────────────────┐
│  Lua 脚本                                     │
│  alloc / load / from                          │
│  u8 u16 u32 / search_u16 / append / string    │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│  buf 对象（userdata 句柄）                     │
│  · 长度：当前内容                               │
│  · 容量：已申请、可直接写入的空间                 │
│  · 字节块挂在句柄上，回收或 close 时释放          │
└────────────────────┬─────────────────────────┘
                     │ 仅 load
┌────────────────────▼─────────────────────────┐
│  ublob 明文                                    │
│  读入缓冲前部；多出来的容量留空                   │
└──────────────────────────────────────────────┘
```

| 路径 | 当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `alloc` / `from` | 按容量申请一块，可选拷入初值 | 否 |
| `load` | 读出 `ublob` 整份明文，拷到缓冲前部 | 否 |
| `u8` / `u16` / `u32` / `search_u16` | 在字节块上取整数或二分 | 否 |
| `append` / `insert` / `remove` / `replace` | 在字节块里挪动和写入；不够再扩大容量 | 否 |
| `string` | 按长度（或一段）拷出一份 Lua string | 否 |
| `close` | 释放字节块，退回额度 | 否 |

没有回调。

---

## 3. 和 Lua 直接操作数据的差异

同一份数据，放在 Lua 值里和放在 `buf` 里，差在语言怎么表示它，以及运行时堆怎么记账。

### 3.1 语言特性

Lua 的 string **不可变**。`a .. b` 每次都新做一份，旧的整段留下等回收。循环里 `s = s .. piece` 时，第 n 次要拷贝前面全部内容，中间还有 n 份废弃 string。表也是值的集合：一项一个结点，数字再单独占一份，几千个码点的查找表会远大于「码点个数 × 2 字节」。

`buf` 上的字节可以原地改。`append` 在容量里面只把长度往后推；`insert` / `remove` / `replace` 只挪动受影响的那一截。`u16` 返回一个 **number**，不制造 string。`search_u16` 在字节块里二分，返回记录下标。整段要交给别的模块时，再 `string()`，这时才出现一份不可变 string。

| | Lua string / table | `buf` |
| --- | --- | --- |
| string 拼接 | 每次 `..` 复制整段，留下中间结果 | 容量内追加只改长度；最后拷一次 |
| 随机读 2 字节 | `string.byte` / `string.unpack` 或再切一段 string | `u16(off)` 返回整数 |
| 上千项查找表 | 一张大 table | 一块按整数下标二分的字节 |
| 含 `\0` | string 按长度，不会在 `\0` 截断 | `from` / `append` / `string` 同样按长度 |
| 下标习惯 | 表常用从 1 起 | 偏移、`search_u16` 下标都从 **0** 起 |

`string.sub`、`string.char`、`string.pack` 的结果仍是新 string。组包路径用 `append_u8` / `append_u16` 时，参数是整数，这一步不先做 string。

### 3.2 底层特性

脚本虚拟机堆上限是 **700 KB**，string、table、闭包都算在里面。本模块的字节块**不进这 700 KB 的记账**。句柄本身很小，在虚拟机堆里。字节块另有合计 **200 KB** 的容量额度，用 `used()` / `limit()` 看。

因此：

- 一张约 46 KB 的编码表放进 `buf`，占用的是这 200 KB 里的容量，而不是虚拟机堆里一份大 table。
- 循环追加时，废弃的中间 string 不会因为拼接而堆满 700 KB；代价是缓冲容量要事先留够，或接受按 2 倍扩大（仍受 200 KB 限制）。
- `string()` 的那一份结果**会**进入 700 KB 堆。只在要发送、打印、写入 `ublob` 时调用。
- `close` 或对象被回收后，容量从 `used()` 里减去。不 `close` 就丢掉引用，要等回收才还额度；额度打满时下一次 `alloc` 会 `"quota exceeded"`。

`ublob` 的 view 也把明文放在虚拟机堆之外，但同时只能开一个 view，而且 view 绑定那一个文件。`buf` 可以同时拿着多块（合计不超过 200 KB），`load` 之后可以继续 `append`。文件本身仍由 `ublob` 落在内部配额里；`buf` 不代替那 220 KB 的存储配额。

---

## 4. 设计用途

### 4.1 编码表和字库

表做成小端 `u16` 的 `.bin`，放进工程内置文件，存储选 blob，设备上用 `ublob` 的文件名。先 `ublob.size`，再 `load`。

- 稠密表：下标算偏移，`u16(off)` 一次取到码点。
- 按码点排序的记录：每条开头是键 `u16`，`search_u16(base, stride, count, key)` 得到从 0 起的记录号，再用 `u16` 取同一条里的值。

GB2312 这种双字节，线上是高字节在前。缓冲里的 `u16` / `append_u16` 是**小端**。表内用 `u16` 读；往外送字节时用两次 `append_u8`，先高后低。不要把线上的 `0xB0A1` 直接 `append_u16`，那会写成 `A1 B0`。

查表对象保持只读用法。`insert` / `remove` 会挪动后面的字节，用在另一块用来组输出的缓冲上。

### 4.2 StringBuilder

`alloc(预计长度)`。长度从 0 开始，容量就是预计值。随后：

- `append` 接片段
- `insert(off, s)` 在中间插入
- `remove(off, len)` 删掉一段
- `replace(off, len, s)` 换成另一段
- `clear` 长度归零，容量留着，下一段可以复用同一块

预计长度够用时，这些操作不扩大容量。结束时 `string()` 一次。例程见 [buf_builder](../../../../../examples/nt26/storage/buf/buf_builder)。

### 4.3 二进制组包

协议字段是整数时，`append_u8` / `append_u16` 按小端写入并增加长度。比先 `string.char` 再 `..` 少一轮短 string。

### 4.4 文件在前、尾部预留

`load(name, cap)` 要求 `cap` 大于等于文件明文长度。文件放在前面，长度等于文件大小，容量等于 `cap`。尾部用来 `append`，不必先扩容。`cap` 小于文件时返回 `nil, "invalid param"`，不分配。不传 `cap` 时容量刚好等于文件。

---

## 5. 对象模型

`alloc` / `load` / `from` 返回 **buf** userdata。模块表上没有这些实例方法。

```lua
b:append("x")          -- 推荐
b.append(b, "x")       -- 等价
```

错误：`b.append("x")`（少了对象）、`buf.append(b, "x")`（模块表上没有 `append`）。

脚本要保住 `b`，直到 `close`。丢掉引用后，回收会释放字节块并退回额度。`close` 之后对象还在，再读再改得到 `nil, "closed"`。再 `close` 一次仍然返回 `true`。

本模块**没有布尔参数**。偏移、长度、容量、码值都是整数。整数 `0` 就是数值 0，不会被当成假。

多字节读写是**小端**：低地址是低字节。偏移可以是奇数；只要这一截还在长度里面。

---

## 6. 阻塞语义

全部同步，不让出协程。`load` 会读完整份明文。`insert` / `remove` / `replace` 在长缓冲中间改，会搬动尾部。大块上的这些调用会占住引擎线程一段时间。

---

## 7. 常量与枚举

模块表**没有**导出整数常量。额度用函数读：

| 调用 | 值 | 含义 |
| --- | --- | --- |
| `buf.limit()` | `204800` | 全部存活对象的容量合计上限，即 200 KB |

`search_u16` 的步长至少为 2，这是参数约束，不是枚举。

---

## 8. 类型约定

| 文档用名 | Lua 类型 | 说明 |
| --- | --- | --- |
| `cap` / `off` / `len` / `n` | integer | ≥ 0；字节偏移从 0 起 |
| `name` | string | `ublob` 短名，规则与 [`ublob`](ublob.md) 相同 |
| `s` | string | 字节；可含 `\0`；长度用 `#s` |
| `v` | integer | `u8` 为 0..255，`u16` 为 0..65535，`u32` 为 0..4294967295 |
| `b` | userdata | `alloc` / `load` / `from` 的返回值 |
| `idx` | integer | `search_u16` 的记录下标，从 0 起 |

缺参或类型不是 integer / string 时**抛错**（`bad argument`）。数值越界、负数、偏移超出长度，返回 `nil, "invalid param"`，不抛错。

---

## 9. 模块函数

### 9.1 `buf.limit()` {#9-1-limit}

额度上限，固定 204800。

**调用模式**

```lua
n = buf.limit()
```

**返回**

整数 `204800`。不失败。

---

### 9.2 `buf.used()` {#9-2-used}

当前已分配容量之和。只计还没 `close`、也还没被回收的对象的 `cap`，不是长度。

**调用模式**

```lua
n = buf.used()
```

**返回**

整数，0 .. 204800。不失败。

---

### 9.3 `buf.alloc(cap)` {#9-3-alloc}

申请一块空缓冲。长度 0，容量 `cap`。组字符串、组包时按预计结果长度来填，后面在容量内追加就不会扩大。

**调用模式**

```lua
b, err = buf.alloc(cap)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `cap` | integer | 是 | ≥ 0。0 得到空对象，尚不占额度；第一次追加再申请 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `b` |
| 失败 | `nil, err` |

`cap` 为负，或大到放不进 32 位无符号整数：`"invalid param"`。`cap` 或「已用 + cap」超过 204800：`"quota exceeded"`。申请失败：`"no mem"`。失败时不留下对象，`used()` 不变。

---

### 9.4 `buf.load(name [, cap])` {#9-4-load}

从 `ublob` 读入明文，放在缓冲前面。

**调用模式**

```lua
b, err = buf.load(name)
b, err = buf.load(name, cap)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 是 | `ublob` 短名 |
| `cap` | integer | 否 | 省略则容量 = 文件明文长度。传入则必须 ≥ 文件长度 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `b`。长度 = 文件明文长度，容量 = 实际申请值，文件在偏移 0 |
| 失败 | `nil, err` |

`cap` 小于文件明文长度：`"invalid param"`，不分配。文件不存在：`"not found"`。目标是目录：`"open target is dir"`。记录损坏：`"bad record"`。额度或内存不够：`"quota exceeded"` / `"no mem"`。

读失败时对象会关掉，不会把半截缓冲交给脚本。建议先 `ublob.size(name)`，再传入大于等于该长度的 `cap`，或省略 `cap`。

空文件可以加载。省略 `cap` 时长度和容量都是 0；传入正的 `cap` 时长度为 0、容量为 `cap`。

---

### 9.5 `buf.from(s)` {#9-5-from}

用一份已有 string 做初值。长度和容量都等于 `#s`。

**调用模式**

```lua
b, err = buf.from(s)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `s` | string | 是 | 原样拷贝，可含 `\0` |

**返回**

成功 `b`。空串得到长度 0、容量 0 的对象。额度或内存不够：`nil, "quota exceeded"` / `nil, "no mem"`。

之后若要再 `append`，容量已经等于长度，下一次追加会扩大。想留余量时用 `alloc` 再 `append`，或 `from` 之后 `reserve`。

---

## 10. 对象方法

读和 `string` 的范围是**长度**，不是容量。容量里尚未写入的尾部不能 `u16`，也不能 `set_*`。要写入尾部，用 `append` / `append_u8` / `append_u16`，或先让长度覆盖那里。

### 10.1 `b:size()` {#10-1-size}

当前内容长度。

**调用模式**

```lua
n, err = b:size()
```

**返回**

成功为整数。已 `close`：`nil, "closed"`。

---

### 10.2 `b:cap()` {#10-2-cap}

已申请容量。

**调用模式**

```lua
n, err = b:cap()
```

**返回**

成功为整数。已 `close`：`nil, "closed"`。

---

### 10.3 `b:u8(off)` {#10-3-u8}

读 1 字节，无符号。

**调用模式**

```lua
v, err = b:u8(off)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | ≥ 0，且 `off + 1` ≤ 长度 |

**返回**

成功为 0..255。越界或已关闭：`nil, err`。

---

### 10.4 `b:u16(off)` {#10-4-u16}

读 2 字节，小端，无符号。

**调用模式**

```lua
v, err = b:u16(off)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | `off + 2` ≤ 长度 |

**返回**

成功为 0..65535。`off` 可以是奇数。

---

### 10.5 `b:u32(off)` {#10-5-u32}

读 4 字节，小端，无符号。

**调用模式**

```lua
v, err = b:u32(off)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | `off + 4` ≤ 长度 |

**返回**

成功为 0..4294967295。

---

### 10.6 `b:set_u8(off, v)` {#10-6-set_u8}

在长度范围内改 1 字节。不改变长度。

**调用模式**

```lua
ok, err = b:set_u8(off, v)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 同 `u8` |
| `v` | integer | 是 | 0..255 |

**返回**

成功 `true`。`v` 越界、偏移越界或已关闭：`nil, err`。

长度仍是 0 时，`set_u8(0, v)` 失败。先 `append_u8`。

---

### 10.7 `b:set_u16(off, v)` {#10-7-set_u16}

在长度范围内按小端改 2 字节。不改变长度。

**调用模式**

```lua
ok, err = b:set_u16(off, v)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 同 `u16` |
| `v` | integer | 是 | 0..65535 |

**返回**

成功 `true`。失败 `nil, err`。

---

### 10.8 `b:set_u32(off, v)` {#10-8-set_u32}

在长度范围内按小端改 4 字节。不改变长度。

**调用模式**

```lua
ok, err = b:set_u32(off, v)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 同 `u32` |
| `v` | integer | 是 | 0..4294967295 |

**返回**

成功 `true`。失败 `nil, err`。

---

### 10.9 `b:search_u16(base, stride, count, key)` {#10-9-search_u16}

在一段记录里二分查找。每条记录长 `stride` 字节，**开头 2 字节**是小端键，记录按键升序排列。返回第一条相等记录的下标（从 0 起）。

**调用模式**

```lua
idx, err = b:search_u16(base, stride, count, key)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `base` | integer | 是 | 第一条记录的字节偏移 |
| `stride` | integer | 是 | ≥ 2。键占每条开头 2 字节 |
| `count` | integer | 是 | 记录条数。`base + count * stride` 必须 ≤ 长度 |
| `key` | integer | 是 | 0..65535 |

**返回**

| 结果 | 返回 |
| --- | --- |
| 找到 | 整数下标 `0 .. count-1` |
| 没有这条键 | `nil, "not found"` |
| 范围、步长、键不合法，或已关闭 | `nil, err` |

`count == 0` 且范围合法时，结果是 `"not found"`。有重复键时返回最左边那条。

取值：`b:u16(base + idx * stride + 值在记录内的偏移)`。

---

### 10.10 `b:append(s)` {#10-10-append}

把一段 string 接到长度的末尾。

**调用模式**

```lua
ok, err = b:append(s)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `s` | string | 是 | 可空串。空串成功，长度不变 |

**返回**

成功 `true`。容量不够时按 [第 11 节](#11-长度与容量) 扩大；扩大失败则缓冲保持原样，返回 `nil, err`。

---

### 10.11 `b:append_u8(v)` {#10-11-append_u8}

接 1 字节。参数是整数，不先做 string。

**调用模式**

```lua
ok, err = b:append_u8(v)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `v` | integer | 是 | 0..255 |

**返回**

成功 `true`，长度加 1。失败 `nil, err`。

---

### 10.12 `b:append_u16(v)` {#10-12-append_u16}

接 2 字节，小端。

**调用模式**

```lua
ok, err = b:append_u16(v)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `v` | integer | 是 | 0..65535 |

**返回**

成功 `true`，长度加 2。`append_u16(0x1234)` 之后，末尾两字节是 `0x34`、`0x12`。

线上高字节在前的编码（例如 GB2312）不要用本函数直接送出，用两次 `append_u8`。

---

### 10.13 `b:insert(off, s)` {#10-13-insert}

在 `off` 之前插入。`off == 长度` 等同接到末尾。后面的字节后移。

**调用模式**

```lua
ok, err = b:insert(off, s)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 0 .. 长度 |
| `s` | string | 是 | 可空串 |

**返回**

成功 `true`。`off` 大于长度：`nil, "invalid param"`。扩大失败时内容不变。

---

### 10.14 `b:remove(off, len)` {#10-14-remove}

删掉 `[off, off+len)`，后面的字节前移。长度减少 `len`。容量不变。

**调用模式**

```lua
ok, err = b:remove(off, len)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 起点 |
| `len` | integer | 是 | 删掉的字节数。0 表示不改内容 |

**返回**

成功 `true`。区间超出长度：`nil, "invalid param"`。

---

### 10.15 `b:replace(off, len, s)` {#10-15-replace}

用 `s` 替换 `[off, off+len)`。新段可以更短或更长，尾部跟着挪。

**调用模式**

```lua
ok, err = b:replace(off, len, s)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 是 | 起点 |
| `len` | integer | 是 | 被替换的字节数 |
| `s` | string | 是 | 新内容，可空（空则等同删掉这一段） |

**返回**

成功 `true`。区间超出长度，或扩大失败：`nil, err`。失败时原内容还在。

---

### 10.16 `b:clear()` {#10-16-clear}

长度归零。容量和已申请的字节块保留，`used()` 不变。

**调用模式**

```lua
ok, err = b:clear()
```

**返回**

成功 `true`。已关闭：`nil, "closed"`。

---

### 10.17 `b:reserve(n)` {#10-17-reserve}

保证容量至少为 `n`。长度不变。`n` 不大于当前容量时成功返回，不重新申请。

**调用模式**

```lua
ok, err = b:reserve(n)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `n` | integer | 是 | ≥ 0，目标容量 |

**返回**

成功 `true`。额度或内存不够：`nil, err`，原容量不变。

---

### 10.18 `b:string([off, len])` {#10-18-string}

按长度拷出一份 Lua string。这是进入虚拟机堆的那一次复制。

**调用模式**

```lua
s, err = b:string()
s, err = b:string(off, len)
```

**参数**

| 名字 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `off` | integer | 与 `len` 成对 | 起点 |
| `len` | integer | 与 `off` 成对 | 字节数。`off + len` ≤ 长度 |

只写 `b:string(off)`、不写 `len`：`nil, "invalid param"`。

**返回**

成功为 string，可以是空串。区间越界或已关闭：`nil, err`。长度为 0 时 `b:string()` 得到 `""`。

---

### 10.19 `b:close()` {#10-19-close}

释放字节块，容量从 `used()` 扣除。

**调用模式**

```lua
ok = b:close()
```

**返回**

`true`。重复调用仍是 `true`。

---

## 11. 长度与容量

| | 长度 `size()` | 容量 `cap()` |
| --- | --- | --- |
| `alloc(cap)` | 0 | `cap` |
| `load(name)` | 文件长度 | 文件长度 |
| `load(name, cap)` | 文件长度 | `cap`（≥ 文件长度） |
| `from(s)` | `#s` | `#s` |
| `append` / `insert` / `replace` | 变成新内容的长度 | 不够才变大 |
| `remove` / `clear` | 变小或变 0 | 不变 |
| `reserve(n)` | 不变 | 至少为 `n` |
| `u8` / `u16` / `u32` / `set_*` / `string` | 不得超出长度 | 尾部空容量不可读 |

追加或替换导致新长度大于容量时：

1. 新容量从「当前容量与 64 的较大者」起，按 2 倍增加，直到能放下新长度。
2. 若 2 倍会超过剩余额度，但新长度本身仍在额度里，则按新长度申请，不再翻倍。
3. 新长度放不进剩余额度：`"quota exceeded"`。申请失败：`"no mem"`。
4. 这两种失败都不会改掉原来的长度、容量和内容。

`alloc` 时把容量一次给够，热路径上就只增加长度。

---

## 12. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `limit` / `used` | 整数 | 不失败 |
| `alloc` / `load` / `from` | 对象 | `nil, err` |
| `size` / `cap` | 整数 | `nil, err` |
| `u8` / `u16` / `u32` | 整数 | `nil, err` |
| `search_u16` | 下标整数 | `nil, err` |
| `set_*` / `append` / `append_u8` / `append_u16` / `insert` / `remove` / `replace` / `clear` / `reserve` | `true` | `nil, err` |
| `string` | string | `nil, err` |
| `close` | `true` | 无失败路径 |

缺参、类型不对：**抛错**。

`err` 全表：

| `err` | 可能原因 |
| --- | --- |
| `invalid param` | 负的容量或偏移；容量、码值超出范围；`u16`/`u32`/`set_*`/`string` 区间超出**长度**；`load` 的 `cap` 小于文件；`search_u16` 的步长 &lt; 2、键 &gt; 65535，或记录范围超出长度；`string` 只给了偏移没给长度；插入点大于长度 |
| `quota exceeded` | 这次容量（含扩大后的容量）会使 `used()` 超过 204800 |
| `no mem` | 额度还有，但模组堆分配失败 |
| `not found` | `load` 的名字在 `ublob` 里没有；或 `search_u16` 没有这条键 |
| `closed` | 已经 `close`（或已释放）还在读、改、`string` |
| `open target is dir` | `load` 的目标是目录 |
| `bad record` | `ublob` 记录损坏，或读出的长度和记录不一致 |
| `io error` / `fs error` | 读 `ublob` 时存储失败 |
| `already exists` | 存储层短句，`load` 路径上少见 |

`"not found"` 既表示文件没有，也表示二分没找到键。看是 `load` 的返回值还是 `search_u16` 的返回值。

---

## 13. 资源上限与生命周期

| 项 | 上限 |
| --- | --- |
| 全部未关闭对象的容量之和 | **200 KB**（204800）。`limit()` / `used()` |
| 单块容量 | 不超过剩余额度，因此最大也是 200 KB |
| 是否计入虚拟机 700 KB 堆 | 字节块不计；`string()` 拷出的那份 string 计入 |
| 同时存在的对象个数 | 不单限个数，只限容量之和 |
| 掉电保存 | 不保存。要留盘用 `ublob` / `ufs` |

`close` 立刻释放并减少 `used()`。未 `close` 时，对象回收会做同样的释放。虚拟机退出时一并释放。

`load` 期间会短时间再占文件明文那么大的读缓冲，读完即弃。不要用 `load` 去顶满 200 KB 的同时再假设堆里还有同样大的空闲。

---

## 14. 完整示例

接口逐项对照：[buf_api](../../../../../examples/nt26/storage/buf/buf_api)。  
StringBuilder 组句：[buf_builder](../../../../../examples/nt26/storage/buf/buf_builder)。

查表（记录为小端 `u16` 键 + `u16` 值，步长 4）：

```lua
local buf = require("buf")
local ublob = require("ublob")

local n = ublob.size("gb2312.bin")
local map = buf.load("gb2312.bin", n)
local out = buf.alloc(64)

local i = map:search_u16(0, 4, map:size() // 4, codepoint)
if i then
    local gb = map:u16(i * 4 + 2)
    out:append_u8(gb >> 8)
    out:append_u8(gb & 0xFF)
end
local s = out:string()
out:close()
map:close()
```

组一行，容量内不扩大，只在最后取出 string：

```lua
local buf = require("buf")

local line = buf.alloc(64)
local names = { "alpha", "beta", "gamma" }
for i = 1, #names do
    line:append(names[i])
    line:append(",")
end
line:remove(line:size() - 1, 1)
line:insert(0, "[")
line:append("]")
-- line:string() == "[alpha,beta,gamma]"，cap 仍为 64
line:close()
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-10-05 | 首版：长度/容量、200 KB 独立额度、相对 Lua string/table 的差异，以及编码表、StringBuilder、二进制组包 |
