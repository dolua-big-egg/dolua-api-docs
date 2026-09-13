# framekit

**文档版本** `1.1.0`

对象化帧解析模块。用一份 JSON 描述二进制协议，把 UART / TCP 上乱七八糟的字节流裁成一个一个独立完整帧。核心是 **流式解析**；组包只是附属。

```lua
local framekit = require("framekit")
```

平台预加载模块，无需额外 `.lua` 文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:on`](#7-1-on)
  - [7.2 `obj:reg`](#7-2-reg)
  - [7.3 `obj:input`](#7-3-input)
  - [7.4 `obj:poll`](#7-4-poll)
  - [7.5 `obj:reset`](#7-5-reset)
  - [7.6 `obj:calc_size`](#7-6-calc-size)
  - [7.7 `obj:build`](#7-7-build)
  - [7.8 `obj:config_json`](#7-8-config-json)
  - [7.9 `obj:info`](#7-9-info)
  - [7.10 `obj:close`](#7-10-close)
- [8. 协议 JSON](#8-协议-json)
- [9. 事件回调](#9-事件回调)
- [10. 粘包、断包、噪声](#10-粘包断包噪声)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本从串口、网口拿到的通常是 **字节流**，不是「一帧」。线路一抖、对端一连发，就会出现：

| 现象 | 线路上实际发生的事 | 自己在 Lua 里处理有多烦 |
| --- | --- | --- |
| **断包** | 一帧被拆成两次、三次到达 | 要自己攒缓冲、记「已经看到包头了、还差几字节」 |
| **粘包** | 两帧甚至三帧粘在同一次回调里 | 要按长度循环切，切错一次后面全乱 |
| **噪声** | 前面夹了垃圾字节，或半截坏帧 | 要重新找包头、对齐、丢掉残渣再继续 |

组包则相反：加几个字节的头尾、填长度、再算一段校验，Lua 几行就能拼好。所以本模块 **不把组包当卖点**。`obj:build` 只是用同一份规则帮你生成对照帧，保证收发格式一致；真正难、也真正该交给框架的，是 **流式解析**。

`uart.reg` 给你的「一包」是按空闲超时切的（一段时间没新字节就算一包），和协议帧边界不是一回事。发得快时两帧会粘在同一包里；发得慢时一帧会被拆成两包。framekit 不管空闲间隙，只认 JSON 里的包头 / 长度 / 固定载荷 / 包尾 / 校验：

1. `framekit.create(json [, cb])` 得到解析器对象。
2. 把收到的任意长度二进制丢进 `obj:input(data)`：半截、整帧、多帧粘连、垃圾+正包都可以。
3. 裁出完整合法帧就回调一次，`ev.payload` 是去掉头尾校验后的载荷；粘在一起的多帧会 **回调多次**，每次都是独立干净的一包。
4. 另起一个任务周期性 `obj:poll()`，半包超过 `rx_timeout_ms` 才会被丢掉。没有独立解析线程，不 poll 就发现不了「对端挂了、半包一直不齐」。

典型接法：UART 回调里只 `obj:input(data)` 然后立刻返回；业务放在 framekit 的事件回调或再投递到 task。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  UART/TCP 收到字节 → obj:input(任意长度)                  │
│  后台 task 周期性 obj:poll()                              │
│  事件回调里拿独立的 payload                               │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  framekit 对象                                           │
│  · JSON 规则：头 / 长度 / 载荷 / 尾 / 校验               │
│  · 流缓冲：找包头、拼半包、按长度切开、校验               │
│  · 裁出一帧就排队，等调度循环回调                         │
└────────────────────────────┬────────────────────────────┘
                             │
        字节流（可断、可粘、可夹噪声）
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Lua 调度循环                                            │
│  对每一帧：cb({ event, frame, payload, ... })            │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `create` / `on` / `reset` / `close` | 建实例、换回调、清缓存 | **否** | 当前协程 |
| `input` | 把这段字节喂进解析器，能裁几帧裁几帧 | **否**（回调稍后才跑） | 当前协程很快返回 |
| `poll` | 不喂数据，只看半包有没有超时 | **否** | 同上 |
| `build` / `calc_size` | 按同一规则估长度 / 组一帧 | **否** | 当前协程 |
| 事件回调 | 调度循环里执行 | 回调返回前整台 Lua 调度被占住 | 其它任务都要等 |

`input` 返回时回调通常 **还没执行**：解析结果先入队，等调度循环再 `pcall`。不要在 `input` 后面立刻假定回调已经跑过。

---

## 3. 对象模型

`create` / `new` 返回 userdata。方法在对象元表上：

```lua
obj:input(data)       -- 推荐
obj.input(obj, data)  -- 等价
```

`obj.input(data)` 或 `framekit.input(obj, data)` 都是错的（模块表没有实例方法）。

没有按真假解释的布尔开关。`tick_ms`、载荷长度走数字。

实例必须被脚本持有引用。回调登记在当前虚拟机上；对象被回收、`close`、或 VM 退出都会拆掉解析器和回调。

`on` / `reg` 是同一套换绑：后登记的覆盖先登记的。传 `nil` 或省略第二参表示卸掉回调。

---

## 4. 常量与枚举

模块表只导出一个整数常量。协议字段、事件名都是 JSON / 回调里的 **字符串**，没有 `framekit.CRC16_MODBUS` 这类符号。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `framekit.MAX_INSTANCES` | `8` | 整机同时存活的解析器上限 | 对照 `create` 是否还能再建 |

事件 `ev.event`（未挂到模块表，回调里按下表判断）：

| 字符串 | 含义 |
| --- | --- |
| `frame_ok` | 裁出一帧，头尾校验都过 |
| `timeout` | 已经看到包头，半包等超时，丢掉 |
| `pattern` | 长度、包尾、边界不合法，丢掉 |
| `checksum` | 长度对得上但校验失败，丢掉 |
| `unknown` | 其它 |

`ev.status` 更细（同样是字符串，不是模块常量）：

| 字符串 | 常见何时 |
| --- | --- |
| `ok` | 成功帧 |
| `timeout` | 半包超时 |
| `pattern` | 格式/边界错 |
| `checksum` | 校验错 |
| `arg` | 参数非法 |
| `json` | JSON 文本不合法 |
| `no_memory` | 内存不够 |
| `unsupported` | 当前规则不支持 |
| `incomplete` | 数据还不够一帧（`input`/`poll` 把这种情况当成功，见 7.3） |
| `unknown` | 其它 |

`info().profile` 是识别到的模式名，例如 `M + L + D(variable) + C`。白名单见 [第 8 节](#8-协议-json)。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `FrameKitObj` | userdata | `create` / `new` 的返回值 |
| `json` | string | 一整份协议对象文本，见第 8 节 |
| `CreateArg` | string 或 table | 字符串即 JSON；表则用 `json` 键，可选 `frame_buf_size` |
| `callback` | function | `function(ev)`，`ev` 为 table |
| `data` / `payload` / `frame` | string | 原始字节，可含 `0x00` |
| `tick_ms` | integer | 解析器用的时间戳；省略则用当前毫秒 |
| `Event` | table | 见第 9 节 |

`create` 的表参数里，`frame_buf_size` 用数字且必须 `> 0`；布尔、字符串会被忽略，退回 `max_frame_size`。

---

## 6. 模块函数

模块表上只有工厂：`create` 与 `new`（完全相同）。

### `framekit.create(arg [, callback]) → obj | nil, err`

按 JSON 规则建一个解析器。

**调用模式**

```lua
framekit.create(json_string)
framekit.create(json_string, callback)
framekit.create({ json = json_string })
framekit.create({ json = json_string, frame_buf_size = n })
framekit.create({ json = json_string }, callback)
framekit.create({ json = json_string, frame_buf_size = n }, callback)
framekit.new(...)   -- 与 create 相同
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `arg` | string 或 table | 是 | 见上。表必须有字符串键 `json` |
| `callback` | function | 否 | 不是函数则忽略（不当回调）。也可事后 `obj:on` |

| 表字段 | 类型 | 说明 |
| --- | --- | --- |
| `json` | string | 协议 JSON |
| `frame_buf_size` | integer | 解析缓存字节数。省略或 `≤0` 则用 `max_frame_size`。若小于 `max_frame_size` 会抬到 `max_frame_size` |

成功只返回对象（一个返回值）。失败 `nil, err`（`err` 是字符串：缺 JSON、配置 hint、没有槽、没有内存、没有调度上下文等）。须在 `rt` 调度上下文里调用。

第二参若不是 function（例如 `true`），不会抛错，只是没登记回调。

---

## 7. 对象方法

推荐冒号调用。

---

### 7.1 `obj:on([callback])` {#7-1-on}

换绑或卸掉事件回调。

**调用模式**

```lua
obj:on(callback)
obj:on(nil)
obj:on()
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `callback` | function | 否 | 省略或 `nil`：卸掉回调。其它非函数 **抛** 类型错 |

成功 `true`。对象已关闭：`nil, "framekit closed"`。

新函数覆盖旧函数。回调协议见 [第 9 节](#9-事件回调)。

---

### 7.2 `obj:reg([callback])` {#7-2-reg}

`on` 的别名，行为完全相同。

```lua
obj:reg(callback)
obj:reg(nil)
obj:reg()
```

---

### 7.3 `obj:input(data [, tick_ms])` {#7-3-input}

把一段二进制喂进解析器。长度随意：1 字节、半帧、整帧、多帧粘连、噪声+正包都可以。

**调用模式**

```lua
obj:input(data)
obj:input(data, tick_ms)
```

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `data` | string | 是 | — | 原始字节 |
| `tick_ms` | integer | 否 | 当前毫秒 | 给超时判断用。传了数字才覆盖 |

成功 `true`。这里的成功包括 **还没收齐一帧**（半包继续攒着）。解析器判定格式/校验等失败：`false,` 状态名（如 `"pattern"`）。已关闭：`nil, "framekit closed"`。

`data` 必须是字符串。数字会被收成十进制文本，不是那个字节。空串可以喂，相当于没新数据。

一次 `input` 里若粘了三帧，会排上三次 `frame_ok` 事件，不是一次回调三个 payload。

---

### 7.4 `obj:poll([tick_ms])` {#7-4-poll}

不喂新字节，只检查半包有没有超过 `rx_timeout_ms`。

**调用模式**

```lua
obj:poll()
obj:poll(tick_ms)
```

返回约定与 `input` 相同：成功 `true`（含「仍不齐」）；失败 `false,` 状态名；已关闭 `nil, "framekit closed"`。

没有独立后台解析循环。对端只发了半包、之后一直沉默时，**只有 poll 才会触发 `timeout`**。demo 每 200 ms 调一次。不要只在 `input` 时才 poll：没新数据就不会走进 `input`。

---

### 7.5 `obj:reset()` {#7-5-reset}

丢掉解析缓存和尚未回调的事件。配置不变。

```lua
obj:reset()
```

成功 `true`。已关闭 `nil, "framekit closed"`。

断包测超时前、换一段测试流时常用。正在等半包时 `reset` 等于放弃那半包，不会回调 `timeout`。

---

### 7.6 `obj:calc_size(payload_or_len)` {#7-6-calc-size}

按当前规则，给定载荷长度时完整帧会有多长。

**调用模式**

```lua
obj:calc_size(payload_string)
obj:calc_size(payload_len)
```

| 第二参 | 含义 |
| --- | --- |
| 数字 | 当作载荷字节数 |
| 字符串 | 用 `#payload` 当地载荷长度 |

成功返回整数帧长。失败 `nil,` 状态名。已关闭 `nil, "framekit closed"`。

数字优先于字符串：`calc_size(4)` 按 4 字节载荷算，不会去取字符串 `"4"`。

---

### 7.7 `obj:build(payload)` {#7-7-build}

按当前规则给载荷加上头、长度、尾、校验，得到完整帧。方便对照和自测；日常发包也可以自己拼，只要和 JSON 一致。

```lua
obj:build(payload)
```

| 参数 | 类型 | 必填 |
| --- | --- | --- |
| `payload` | string | 是 |

成功两个返回值：`frame`（二进制 string）、`info` 表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `frame_len` | integer | 完整帧长度 |
| `payload_offset` | integer | 载荷在完整帧里的偏移 |
| `payload_len` | integer | 载荷长度 |

失败 `nil,` 状态名（如 `"no_memory"`）。已关闭 `nil, "framekit closed"`。

```lua
local frame, info = obj:build("PING")
if frame then
    uart.write(uart.UART1, frame)
end
```

---

### 7.8 `obj:config_json()` {#7-8-config-json}

把当前生效配置导出成 JSON 文本（约 1024 字节缓冲，超了会失败）。

```lua
obj:config_json()
```

成功 string。失败 `nil,` hint。已关闭 `nil, "framekit closed"`。

---

### 7.9 `obj:info()` {#7-9-info}

```lua
obj:info()
```

成功表：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `slot` | integer | 实例槽位 `0`～`7` |
| `topic` | string | 内部投递主题（如 `__FK_00`），不要自己 `mbox_recv` |
| `profile` | string | 识别到的模式名 |
| `max_frame_size` | integer | JSON 里的上限 |
| `queue_depth` | integer | 配置里的建议深度，见第 12 节 |
| `closed` | boolean | 存活对象上为假；关闭后 `info` 会失败而不是返回真 |

失败 `nil, "framekit closed"`。

---

### 7.10 `obj:close()` {#7-10-close}

关掉解析器、卸回调、释放缓存。之后除了对已关闭对象再 `close` 仍返回 `true` 以外，其它方法都会失败。

```lua
obj:close()
```

始终返回 `true`。对象回收时也会走同一套清理。VM 退出会关掉本 VM 上全部实例。

---

## 8. 协议 JSON

`create` 吃的是 **一段 JSON 对象文本**，不是 Lua table 当协议（除非把 JSON 放在 `{ json = "..." }` 里）。不要尾逗号、不要注释。

必填：`header`、`payload`、`max_frame_size`。变长载荷还必须有 `length`；定长载荷 **禁止** 出现 `length`。

| 键 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `name` | 否 | 空 | 标识用，最长约 31 字符 |
| `rx_timeout_ms` | 否 | `3000` | 看到包头后，等多久还不齐就丢。须配合 `poll` |
| `queue_depth` | 否 | `8` | 写入配置，出现在 `info` |
| `max_frame_size` | **是** | — | 完整帧上限，防止长度字段被写炸 |
| `header` | **是** | — | 包头，1～4 字节 |
| `length` | 变长必填 | 不定长则禁用 | 长度字段 |
| `payload` | **是** | — | `fixed` 或 `variable` |
| `tail` | 否 | 无包尾 | 1～4 字节；`{}` 也表示无 |
| `checksum` | 否 | 无校验 | 算法、宽度、字节序、覆盖范围 |

### 8.1 `header` / `tail`

```json
"header": { "value_hex": "55AA", "size": 2 }
"tail":   { "value_hex": "0D0A", "size": 2 }
```

| 键 | 说明 |
| --- | --- |
| `value_hex` | 大写小写均可，长度必须是 `size * 2` |
| `size` | 头：`1`～`4`。尾：有尾时 `1`～`4` |

包头不能空对象。解析时在流里搜索这段魔数；对不上就逐字节滑过去（噪声可被跳过）。

### 8.2 `length`（仅变长）

```json
"length": { "size": 2, "endian": "big", "includes": "payload" }
```

| 键 | 合法值 |
| --- | --- |
| `size` | `1` / `2` / `4` |
| `endian` | `"big"` / `"little"` |
| `includes` | `"payload"`：字段只表示载荷长；`"payload_and_tail"`：载荷+包尾 |

三键都要有。定长模式写了 `length` 会创建失败。

### 8.3 `payload`

```json
"payload": { "mode": "variable" }
"payload": { "mode": "fixed", "fixed_size": 8 }
```

| `mode` | 其它键 |
| --- | --- |
| `"variable"` | 不要 `fixed_size`；必须有 `length` |
| `"fixed"` | 必须 `fixed_size > 0`；不要 `length` |

### 8.4 `checksum`

```json
"checksum": {
  "algorithm": "crc16_modbus",
  "size": 2,
  "endian": "little",
  "scope": "header_to_tail"
}
```

四键都要有。`size` 必须和算法宽度一致：

| `algorithm` | `size` |
| --- | --- |
| `checksum8` / `crc8` | `1` |
| `checksum16` / `crc16_ibm` / `crc16_modbus` / `crc16_ccitt_false` | `2` |
| `checksum32` / `crc32_ieee` | `4` |

`endian`：`"big"` / `"little"`。

`scope`：

| 值 | 覆盖 |
| --- | --- |
| `header_to_payload` | 从头到载荷结束（含载荷，不含校验本身） |
| `header_to_tail` | 从头到包尾（含尾） |
| `length_to_payload` | 从长度字段到载荷结束 |
| `length_to_tail` | 从长度字段到包尾 |
| `payload_only` | 只覆盖载荷 |

其它字符串会 JSON 失败。未导出、未出现在上表的算法名不要写。

### 8.5 模式白名单

配置必须落在下列组合之一，否则 hint 类似 `unsupported pattern; allowed only M+D(fixed)[+E][+C] or M+L+D(var)[+E][+C]`。

| 结构（M=头，L=长度，D=载荷，E=尾，C=校验） | `info.profile` 示例 |
| --- | --- |
| 头 + 定长载荷 | `M + D(fixed)` |
| 头 + 定长 + 尾 | `M + D(fixed) + E` |
| 头 + 定长 + 校验 | `M + D(fixed) + C` |
| 头 + 定长 + 尾 + 校验 | `M + D(fixed) + E + C` |
| 头 + 长度 + 变长载荷 | `M + L + D(variable)` |
| 头 + 长度 + 变长 + 尾 | `M + L + D(variable) + E` |
| 头 + 长度 + 变长 + 校验 | `M + L + D(variable) + C` |
| 头 + 长度 + 变长 + 尾 + 校验 | `M + L + D(variable) + E + C` |

没有「无包头」「纯分隔符切片」这类模式。

demo 用的变长 + CRC16 Modbus：

```json
{
  "name": "demo_uart",
  "rx_timeout_ms": 1500,
  "queue_depth": 8,
  "max_frame_size": 256,
  "header": { "value_hex": "55AA", "size": 2 },
  "length": { "size": 2, "endian": "big", "includes": "payload" },
  "payload": { "mode": "variable" },
  "checksum": {
    "algorithm": "crc16_modbus",
    "size": 2,
    "endian": "little",
    "scope": "header_to_tail"
  }
}
```

线上形态：`55 AA | len(u16 大端, 仅 payload) | payload | CRC16_Modbus(u16 小端)`。

---

## 9. 事件回调

```lua
function(ev)
```

`ev` 表字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `event` | string | `frame_ok` / `timeout` / `pattern` / `checksum` |
| `status` | string | 更细的状态名 |
| `frame` | string | 完整帧（含头尾校验），二进制 |
| `payload` | string | 载荷；失败事件里可能是空串 |
| `frame_len` | integer | |
| `payload_len` | integer | |
| `profile` | string | 该实例的模式名 |
| `topic` | string | 内部主题，不用自己订阅 |

**执行位置：** 调度循环，不是中断，通常也不是你的业务 task。`input` / `poll` 只负责入队。

**必须短。** 允许：改几个变量、`rt.mbox_send`。不要：`rt.delay`、`mbox_recv`、再 `create`/`close` 自己、长 log、在回调里同步组大包。回调抛错记日志后吞掉，这一帧已经结束。

没有登记回调时，裁出来的事件仍会被取走丢掉，脚本看不到。

---

## 10. 粘包、断包、噪声

和 `uart` 空闲切包对比着看：

| 场景 | 你喂给 `input` 的内容 | 回调 |
| --- | --- | --- |
| 单帧一次到齐 | `[帧A]` | 一次 `frame_ok`，payload 干净 |
| **粘包** | `[帧A][帧B][帧C]` 同一次 `input` | **三次** `frame_ok`，不会粘成一个 payload |
| **断包** | 先半截 A，`rx_timeout_ms` 内再后半 | 凑齐后 **一次** `frame_ok` |
| **断包超时** | 只到半截，超过 `rx_timeout_ms` 且调用了 `poll` | `timeout`，残包丢掉，继续找下一个头 |
| **噪声+正包** | `垃圾 + [帧A]` | 跳过对不上头的字节，仍 `frame_ok` A |
| **校验错** | 长度对、CRC 不对 | `checksum`，丢掉后再在剩余流里找头 |
| **长度/包尾非法** | | `pattern` |

超时时钟用 `input`/`poll` 的 `tick_ms`（省略则当前毫秒）。只 `input`、从不 `poll`：对端若不再发字节，半包会一直占着缓存，**不会**自己超时。

`rx_timeout_ms` 写成 `0` 时，几乎一 poll 就会判超时，不要这么配。省略则为 3000。

切包依据是协议，不是串口空闲。`max_wait_ms`（uart 分包）解决不了「两帧之间没有间隙」；那种情况必须靠长度字段或定长。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `create` / `new` | userdata | `nil, err` |
| `on` / `reg` / `reset` | `true` | 已关闭：`nil, "framekit closed"`；`on` 第二参类型不对则 **抛** |
| `input` / `poll` | `true`（含半包未齐） | 解析失败：`false,` 状态名；已关闭：`nil, "framekit closed"` |
| `calc_size` | integer | `nil,` 状态名 |
| `build` | `frame, info` | `nil,` 状态名 |
| `config_json` / `info` | string / table | `nil, err` |
| `close` | `true` | 不失败 |

不是 userdata 却调用方法：抛 Lua 标准类型错，不是 `framekit closed`。兜底 `unknown` 仅在内部未带出原因时出现。

**固定 `err`**

| `err` | 可能原因 |
| --- | --- |
| `mutex alloc failed` | 模块互斥锁创建失败 |
| `json string required` | 第一参不是 string，表里也没有 `json` 字符串 |
| `rt context not found` | 不在脚本调度上下文 |
| `no framekit slot` | 已有 8 个实例 |
| `no memory` | 解析缓存或导出缓冲分配失败 |
| `framekit callback register failed` | 内部到期/事件投递登记失败 |
| `framekit closed` | 已 `close` 或对象已回收仍调方法 |

**当作 `err` / 第二返回值的状态名**

| 文本 | 可能原因 |
| --- | --- |
| `ok` | 成功（正常不会当失败返回） |
| `arg` | 参数空或配置指针无效 |
| `unsupported` | 组合不被支持 |
| `json` | JSON 文本解析失败（同时看 hint） |
| `no_memory` | 内部缓冲不够 |
| `pattern` | 模式不在白名单（定长或变长两种） |
| `timeout` | 半包等到 `rx_timeout_ms` |
| `checksum` | 校验字节对不上 |
| `incomplete` | 半包未齐（`input`/`poll` 成功时也可能内部处于此态） |
| `unknown` | 未翻译的状态 |

**`create` / `config_json` 的 JSON 与校验 hint（原样作为 `err`）**

| `err` | 可能原因 |
| --- | --- |
| `expected '<字符>'` | JSON 当前位置不是该字符 |
| `expected string` | 该处应是 JSON 字符串 |
| `expected unsigned integer` | 该处应是无符号整数 |
| `expected ',' or '}'` | 对象少逗号或少右括号 |
| `expected ',' or '}' in header` / `in tail` / `in length` / `in payload` / `in checksum` / `in top-level object` | 对应对象里语法不完整 |
| `unsupported escape sequence` | 字符串转义非法 |
| `string too long` | 字符串超过内部上限 |
| `unterminated string` | 字符串没闭合 |
| `integer out of range` | 整数字面值溢出 |
| `unsupported JSON value` | 出现了不支持的 JSON 值类型 |
| `header is required` / `header object must not be empty` | 缺包头或 `header` 为空对象 |
| `header requires value_hex and size` | 包头缺字段 |
| `header.size must be 1..4` | 包头长度非法 |
| `header.value_hex length does not match header.size` | hex 长度与 `size` 不一致 |
| `unknown field in header` | `header` 里有不认识的键 |
| `tail requires size` / `tail.size must be 0..4` | 包尾长度非法 |
| `tail.size is 0 but tail.value_hex is not empty` | 声明无包尾却给了 hex |
| `tail requires value_hex when enabled` | 启用包尾但缺 hex |
| `tail.value_hex length does not match tail.size` | 包尾 hex 长度不对 |
| `unknown field in tail` | `tail` 里有不认识的键 |
| `length object must not be empty` | `length` 为空对象 |
| `length requires size, endian and includes` | 长度域缺字段 |
| `length.size must be 1, 2 or 4` | 长度域宽度非法 |
| `length.endian must be 'big' or 'little'` | 端序写错 |
| `length.includes is invalid` | `includes` 不是白名单值 |
| `unknown field in length` | `length` 里有不认识的键 |
| `payload is required` / `payload object must not be empty` | 缺载荷或为空对象 |
| `payload requires mode` | 缺 `mode` |
| `payload.mode must be 'fixed' or 'variable'` | 模式写错 |
| `payload.fixed mode requires fixed_size` | 定长却没给 `fixed_size` |
| `payload.variable must not contain fixed_size` | 变长却带了 `fixed_size` |
| `unknown field in payload` | `payload` 里有不认识的键 |
| `checksum object must not be empty` | `checksum` 为空对象 |
| `checksum requires algorithm, size, endian and scope` | 校验缺字段 |
| `checksum.algorithm is invalid` | 算法名不在白名单 |
| `checksum.endian must be 'big' or 'little'` | 端序写错 |
| `checksum.scope is invalid` | 范围不是白名单值 |
| `checksum.size must be 1, 2 or 4` | 校验宽度非法 |
| `unknown field in checksum` | `checksum` 里有不认识的键 |
| `unknown top-level field '<键>'` | 顶层多了不认识的键 |
| `top level object must not be empty` | 整份 JSON 是空对象 |
| `trailing characters after top-level object` | 顶层对象后面还有垃圾字符 |
| `max_frame_size is required` | 缺最大帧长 |
| `variable payload requires length field` | 变长却没配 `length` |
| `fixed payload must not contain length field` | 定长却配了 `length` |
| `header is required and size must be 1..4 bytes` | 校验：包头缺失或长度非法 |
| `max_frame_size and queue_depth must be non-zero` | 最大帧长或队列深度为 0 |
| `fixed payload requires payload.fixed_size > 0` | 定长 `fixed_size` 为 0 |
| `header/tail size exceeds allowed 1..4 bytes` | 包头/包尾超过 4 字节 |
| `checksum size enabled but algorithm not set` | 开了校验宽度却没算法 |
| `checksum size does not match algorithm width` | 校验宽度与算法不一致 |
| `unsupported pattern; allowed only M+D(fixed)[+E][+C] or M+L+D(var)[+E][+C]` | 字段组合不在两种白名单模式 |
| `json_text/cfg is null` / `cfg/json_text invalid` | 内部入参空（脚本侧少见） |
| `json_text buffer too small` | 导出 JSON 缓冲不够 |
| `cfg is null` | 内部配置空 |

---

## 12. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 同时实例 | **8**（`MAX_INSTANCES`） | 整机，满则 `no framekit slot` |
| 包头 / 包尾 | 各 **1～4** 字节 | |
| 导出 JSON | 约 **1024** 字节缓冲 | `config_json` |
| `max_frame_size` | 配置项 | 单帧上限；解析缓存至少这么大 |

`queue_depth` 会写进配置和 `info`，Lua 侧待回调事件按内存排队；内存或投递失败时该事件会被丢掉（日志里能看到 drop）。不要假设深度就是硬上限邮箱。

`create` 占一个槽；`close`、对象回收、VM 退出释放。关掉后请丢掉脚本里的引用。

`input` 本身很快返回；真正占调度的是随后的回调。高速粘包时一次 `input` 可能排队多帧，回调会连着跑完队列。

---

## 13. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 二进制协议、有包头/长度/校验 | **framekit**：按规则切独立帧 |
| 只按「一段时间没新字节」切 | `uart` 的 `max_wait_ms`，不要硬套 framekit |
| 粘包仍要一帧一次回调 | framekit（本模块主场景） |
| 断包要自动拼 | `input` 多次 + `rx_timeout_ms` + 周期 `poll` |
| 组一帧发出去 | 自己拼，或 `obj:build` 求对称 |
| UART 回调里解析 | **不要**。回调里只 `input` / `mbox_send` |
| 和 AT 抢口 | 同 uart：业务口关掉透传 |

和 [`uart`](../peripherals/uart.md) 是上下游：uart 负责把硬件字节交到脚本；framekit 负责把字节变成协议帧。uart 的「一包」仍可能是粘的或断的，所以协议口应把 uart 收到的东西原样 `input`，不要先按空闲包当完整帧。

---

## 14. 完整示例

UART 回调只喂流；独立任务 `poll`；事件里拿干净 payload。完整工程见 [examples/NT26/module/framekit/framekit_cmd](../../../../examples/NT26/module/framekit/framekit_cmd)。

```lua
local rt = require("rt")
local uart = require("uart")
local rtu = require("rtu")
local framekit = require("framekit")

local U = uart.UART1
local JSON = [[
{"name":"demo_uart","rx_timeout_ms":1500,"queue_depth":8,"max_frame_size":256,
 "header":{"value_hex":"55AA","size":2},
 "length":{"size":2,"endian":"big","includes":"payload"},
 "payload":{"mode":"variable"},
 "checksum":{"algorithm":"crc16_modbus","size":2,"endian":"little","scope":"header_to_tail"}}
]]

rtu.option("pass_up", false)
rtu.option("pass_down", false)

local function on_frame(ev)
    if ev.event == "frame_ok" then
        -- 短回调：只处理或投递。ev.payload 已是独立一包
        rt.mbox_send("frames", ev.payload)
        return
    end
    -- timeout / pattern / checksum：残包已被丢掉，流会继续找下一个头
end

local fk, err = framekit.create(JSON, on_frame)
if not fk then
    error(err)
end

uart.reg(U, function(id, data, meta)
    fk:input(data)
end)

rt.task_start(function()
    while true do
        rt.delay(200)
        fk:poll()
    end
end)

-- 自测：两帧粘在一次 input 里，回调仍是两次 frame_ok
local a = fk:build("PING")
local b = fk:build("HELLO")
fk:input(a .. b)
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部 `err` 文本、状态名、JSON hint 与可能原因 |
