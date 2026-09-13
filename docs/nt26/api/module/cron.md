# cron

**文档版本** `1.1.0`

按 **墙上时钟** 对齐触发的纯函数调度模块。没有对象、没有 `open`。登记 cron 表达式，到点后在 Lua 调度循环里调回调。

```lua
local cron = require("cron")
```

平台预加载模块，无需额外 `.lua` 文件。仅主脚本虚拟机可用；UART / SMS 等快捷回调脚本环境 **没有** 本模块。`require("cron")` 在后端未就绪或槽位耗尽时会 **抛错**。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞与回调语义](#3-阻塞与回调语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `cron.validate_expr`](#6-1-validate-expr)
  - [6.2 `cron.create_trigger`](#6-2-create-trigger)
  - [6.3 `cron.bind_trigger`](#6-3-bind-trigger)
  - [6.4 `cron.start`](#6-4-start)
  - [6.5 `cron.stop`](#6-5-stop)
  - [6.6 `cron.pause`](#6-6-pause)
  - [6.7 `cron.resume`](#6-7-resume)
  - [6.8 `cron.pause_trigger`](#6-8-pause-trigger)
  - [6.9 `cron.resume_trigger`](#6-9-resume-trigger)
  - [6.10 `cron.replace_trigger`](#6-10-replace-trigger)
  - [6.11 `cron.remove_trigger`](#6-11-remove-trigger)
  - [6.12 `cron.clear_trigger`](#6-12-clear-trigger)
- [7. Cron 表达式语法](#7-cron-表达式语法)
- [8. 回调协议](#8-回调协议)
- [9. 错误与返回约定](#9-错误与返回约定)
- [10. 资源上限与生命周期](#10-资源上限与生命周期)
- [11. 选型对照](#11-选型对照)
- [12. 完整示例](#12-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

`cron` 按日历时间对齐：到 **整点、整 5 分钟、每天 10:15:00** 这类钟面上的时刻才触发。不是 `rt.delay(300000)` 那种「从现在再等 5 分钟」。

典型顺序：

1. 本机墙上时钟已经授时（`info.time_ready()` 为真：基站 NITZ、NTP 写钟、`sys.set_ts` 均可）。
2. （可选）`cron.validate_expr(expr)` 先检查表达式。
3. `id, err = cron.create_trigger(expr)` 登记触发器。
4. `cron.bind_trigger(id, callback [, user_tag])` 绑回调。
5. `cron.start()` 开始调度。**不 start 不会跑。**
6. 之后按需 `pause` / `resume`、单条挂起、换表达式、删除。不用了再 `stop`。

`create` / `bind` 只登记。没有 `start`，到点也不会回调。

未授时时调度器拿不到有效时间，**不会按预期触发**。基站 NITZ 成功会立刻重算下一拍。推荐：**先等到 `info.time_ready()`，再 create / bind / start**。若已经 `start`、之后才用 NTP / `sys.set_ts` 写钟（而没有 NITZ），调度器不一定被立刻叫醒，需要一次会重算的操作（例如 `resume` 或 `replace_trigger`）。

当前产品基本只有 **1 个** Lua 主虚拟机。任务 id 只在本次脚本生命周期内有效，不保证下次开机复用同一个数字。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  validate → create → bind → start                        │
│  pause / resume / replace / remove / clear / stop        │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  cron 模块（当前主 VM 一份表）                             │
│  · 表达式解析与下次触发时间                                │
│  · 等到点再投递；空闲可进低功耗，到期由 RTC 拉起            │
│  · 到期事件进入运行时队列                                  │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Lua 调度循环                                            │
│  取出事件 → 调 callback(trigger_id, user_tag)            │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 | 谁在等 |
| --- | --- | --- | --- |
| `validate_expr` / `create` / `bind` / `start` 等 | 登记、启停、改表 | 否（很快返回） | 当前协程 |
| 等到点 | 调度器按墙上时钟休眠等待 | 不占 Lua 调度 | 系统可睡 |
| 到期回调 | 投递后在 **调度循环** 里执行脚本函数 | 回调返回前整台 Lua 调度被占住 | 其它任务 / 定时器 / IO 回调都要等 |

触发不是硬件中断里直接跑 Lua，通常也不是独立 `rt.task`。

---

## 3. 阻塞与回调语义

模块函数本身几乎都不阻塞：登记完立刻返回。真正占调度的是 **到期回调**。

回调必须短：投递邮箱、置标志、打一行短日志。不要在回调里：

- `rt.delay` / `sys.delay_ms` 长等待
- `http` / `ntp.get` / 同步网络问询
- 大段计算或刷屏

业务请丢到独立 `rt.task`（例如 `rt.mbox_send` 后在任务里 `mbox_recv`）。

回调里抛错会被吞掉并记一条错误日志，调度循环继续跑，这次触发已经结束。

到期投递有长度约 **16** 的队列。回调处理慢、触发又密时，队列满会 **丢掉更早还没处理的一次**，只保住较新的。高频不要用 cron。

---

## 4. 常量与枚举

模块表只导出一个整数常量。没有事件枚举。

| 符号 | 值 | 含义 | 用在哪 |
| --- | --- | --- | --- |
| `cron.MAX_TASKS` | `30` | 本 VM 可同时存在的触发器上限 | `create_trigger` 满员后失败 |

没有未导出却能当 API 用的第二个常量。表达式组数、回调队列长度等见 [第 10 节](#10-资源上限与生命周期)，它们不挂在模块表上。

---

## 5. 类型约定

| 名称 | 实际类型 | 取值 |
| --- | --- | --- |
| `expr` | string | 非空。Quartz 风格，见 [第 7 节](#7-cron-表达式语法) |
| `id` | integer 或十进制数字字符串 | `1` … `cron.MAX_TASKS`。`"1"` 可以，`"1.0"` / `"abc"` 不行 |
| `callback` | function | `function(trigger_id, user_tag)` |
| `user_tag` | 任意 Lua 值 | 省略或 `nil` 时回调第二参为 `nil` |
| `validate_expr` 返回 | boolean | `true` 合法，`false` 非法。不是 `nil` |
| `create_trigger` 成功 | integer, string | id ≥ 1，第二返回值为空串 `""` |
| `create_trigger` 失败 | integer, string | **id 为数字 `0`**，第二返回值为错误文案 |
| 其余多数接口成功 | boolean, `nil` | `true, nil` |
| 其余多数接口失败 | `nil`, string | `nil, err_msg` |

Lua 里数字 `0` 为真。失败 id 是 `0`，**不要** `assert(id)` 或 `if not id`，要写 `if id == 0`。

本模块没有 `lua_toboolean` 入参。`validate_expr` 的返回才是布尔。

---

## 6. 模块函数

全部在模块表上。没有 userdata，没有冒号方法。

---

### 6.1 `cron.validate_expr(expr)` {#6-1-validate-expr}

检查表达式是否合法（含分号拼接的多组）。**不创建**触发器。

```lua
cron.validate_expr(expr)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `expr` | 是 | string | 缺参或非字符串 **抛类型错** |

返回 **一个** boolean：合法 `true`，非法 `false`。空串、Unix 五段 crontab、日和星期都不是 `?` 等，都是 `false`。

```lua
if not cron.validate_expr("0 */5 * * * ?") then
    log.info("bad expr")
    return
end
```

---

### 6.2 `cron.create_trigger(expr)` {#6-2-create-trigger}

登记一条触发器，返回整数 id。此时 **还没有回调、也不会跑**，必须再 `bind_trigger` 和 `start`。

```lua
cron.create_trigger(expr)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `expr` | 是 | string | 非空。非法 / 空 / 非字符串 → `0, "invalid cron expr"` |

成功：`id, ""`（id 为 `1` … `30`）。  
失败：`0, err_msg`。满 30 条、表达式建失败、登记失败等文案见 [第 9 节](#9-错误与返回约定)。

```lua
local id, err = cron.create_trigger("0 */5 * * * ?")
if id == 0 then
    log.info("create fail: %s", err)
    return
end
```

---

### 6.3 `cron.bind_trigger(id, callback [, user_tag])` {#6-3-bind-trigger}

把回调绑到已创建的触发器。重复 bind 会 **换绑**，覆盖旧回调和 `user_tag`。

```lua
cron.bind_trigger(id, callback)
cron.bind_trigger(id, callback, user_tag)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | integer / 数字字符串 | 须已 `create_trigger` |
| `callback` | 是 | function | 不是函数 → `nil, "invalid callback"` |
| `user_tag` | 否 | 任意 | 省略则回调第二参为 `nil`；表、字符串、数字都可以 |

成功 `true, nil`。id 不存在 → `"cron trigger not exists"`。

未 `create` 就 bind 会失败。create 成功但还没 bind：到点也不会进脚本。

```lua
local ok, err = cron.bind_trigger(id, function(tid, tag)
    rt.mbox_send("cron_tick", tag or "tick")
end, "jobA")
```

---

### 6.4 `cron.start()` {#6-4-start}

启动本 VM 的调度。幂等：已启动再调一次不会再开一条调度。

```lua
cron.start()
```

成功 `true, nil`。失败 `nil, "cron start failed"` 等。

没有 start，create / bind 只是登记。

---

### 6.5 `cron.stop()` {#6-5-stop}

停止调度。触发器登记还在，可以再 `start`。幂等。

```lua
cron.stop()
```

成功 `true, nil`。不删除触发器、不解绑回调。要清表用 `clear_trigger` / `remove_trigger`。

---

### 6.6 `cron.pause()` {#6-6-pause}

**整表**挂起：不再计算、不再触发。已登记的触发器还在。

```lua
cron.pause()
```

必须已经 `start`。未 start 失败，文案是 `"cron not initialized"`（即使已经 `require` 成功）。

成功 `true, nil`。

---

### 6.7 `cron.resume()` {#6-7-resume}

整表恢复，并立刻重算下一拍。

```lua
cron.resume()
```

同样必须已经 `start`，否则 `"cron not initialized"`。

---

### 6.8 `cron.pause_trigger(id)` {#6-8-pause-trigger}

只挂起这一条。其它触发器照常。

```lua
cron.pause_trigger(id)
```

成功 `true, nil`。id 无效或不存在 → `"cron pause_trigger failed"`。

---

### 6.9 `cron.resume_trigger(id)` {#6-9-resume-trigger}

恢复这一条，并重算它的下次触发时间。

```lua
cron.resume_trigger(id)
```

成功 `true, nil`。失败 `"cron resume_trigger failed"`。

---

### 6.10 `cron.replace_trigger(id, expr)` {#6-10-replace-trigger}

换表达式，**保留 id 和已绑定的回调 / user_tag**。立刻作废旧计划并重算。

```lua
cron.replace_trigger(id, expr)
```

| 参数 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | integer / 数字字符串 | 须已存在 |
| `expr` | 是 | string | 非空。空 / 非字符串 → `"invalid cron expr"` |

成功 `true, nil`。表达式非法或 id 不存在 → `"cron replace_trigger failed"`。

```lua
assert(cron.replace_trigger(id, "0 */10 * * * ?"))
```

---

### 6.11 `cron.remove_trigger(id)` {#6-11-remove-trigger}

删除这一条：触发器、绑定、回调引用一并拆掉。id 可被后续 `create_trigger` 复用。

```lua
cron.remove_trigger(id)
```

成功 `true, nil`。不存在 → `"cron remove_trigger failed"`。

---

### 6.12 `cron.clear_trigger()` {#6-12-clear-trigger}

清空 **本 VM** 全部触发器与回调引用。调度启停状态不由本接口单独定义：清完若还在 `start`，只是表空了，不会再触发。

```lua
cron.clear_trigger()
```

成功 `true, nil`。

---

## 7. Cron 表达式语法

本平台是 **Quartz 风格**，不是 Linux / Unix 的五段 crontab。字段用 **空格** 分隔。年字段可省略。

```
秒  分  时  日  月  星期  [年]
```

| 字段 | 必填 | 取值 | 可用写法 |
| --- | --- | --- | --- |
| 秒 | 是 | `0`–`59` | `*` `A` `A-B` `A/S` `A-B/S` 逗号列表 |
| 分 | 是 | `0`–`59` | 同上 |
| 时 | 是 | `0`–`23` | 同上 |
| 日 | 是 | `1`–`31` | 上列，以及 `?` `L` `L-n` `nW` `C` |
| 月 | 是 | `1`–`12` 或 `JAN`…`DEC` | `*`、区间、步长、列表、英文三字母（大小写不敏感） |
| 星期 | 是 | `1`–`7` 或 `SUN`…`SAT` | `?` `*` `L` `nL` `n#k` `C`、区间、步长、列表、英文三字母 |
| 年 | 否 | `1970`–`2099` | 省略 = 任意年；也可 `*`、区间、步长、列表 |

合法长度：**6 段**（省略年）或 **7 段**。少一段、多一段、Unix 那种「分 时 日 月 星期」五段，都非法。

整串（含分号拼接）最长 **511** 字节。空白会在字段两侧被跳过。

### 7.1 和 Unix crontab 的差别

| 项目 | Unix crontab（常见） | 本模块 |
| --- | --- | --- |
| 字段数 | 5（无秒） | **6 或 7**（有秒，年可选） |
| 星期数字 | `0` 或 `7` = 周日 | **`1` = 周日，`7` = 周六**（Quartz） |
| 日与星期 | 常可同时写 `*` | **必须有一个写 `?`**，另一个才描述日期 |
| 特殊符 | 一般无 `L` / `W` / `#` / `?` | 支持这些 Quartz 符 |

把 `"*/5 * * * *"` 这类五段直接拿来用会失败。正确写法要补秒，并且日、星期里留一个 `?`，例如 `"0 */5 * * * ?"`。

### 7.2 日和星期：必须有一个 `?`

解析硬规则：日、星期 **不能同时指定**。其中一个必须是 `?`（「本字段不参与匹配，由另一个决定」）。

| 日 | 星期 | 含义 | 是否合法 |
| --- | --- | --- | --- |
| `*` | `?` | 每天（再靠时分秒） | 合法 |
| `?` | `MON-FRI` | 仅工作日 | 合法 |
| `15` | `?` | 每月 15 号 | 合法 |
| `*` | `*` | 两边都指定了 | **非法** |
| `1` | `MON` | 两边都指定了 | **非法** |
| `?` | `?` | 两边都不指定 | 合法但没有任何日期能匹配，等于永不触发 |

按日历排期用日字段 + 星期 `?`；按周几排期用星期字段 + 日 `?`。

### 7.3 通配、列表、区间、步长

对秒 / 分 / 时 / 月 / 年（以及日、星期的「集合」模式）适用：

| 写法 | 含义 |
| --- | --- |
| `*` | 该字段全部合法值 |
| `n` | 单个值 |
| `a,b,c` | 列表 |
| `a-b` | 闭区间，`a ≤ b` |
| `*/s` | 从该字段最小值起每隔 `s` |
| `a/s` | 从 `a` 到该字段最大值，每隔 `s`（等价 `a-max/s`） |
| `a-b/s` | 区间内每隔 `s` |

`s` 必须是大于 0 的整数。越界（秒写 `60`、时写 `24`、日写 `0`）非法。

秒、分的 `*` 从 `0` 起；时从 `0` 起；日从 `1` 起；月从 `1` 起；星期从 `1` 起。

因此：

- `"0 */5 * * * ?"`：分钟为 `0,5,10,…,55`，秒为 `0` → 每个整 5 分钟的 0 秒
- `"0/10 * * * * ?"`：秒为 `0,10,20,30,40,50` → 每 10 秒（太密，不建议用 cron）
- `"0 0 8,12,18 * * ?"`：每天 08:00:00、12:00:00、18:00:00

月、星期可用英文缩写，大小写不敏感，必须是三字母：

| 月 | `JAN` `FEB` `MAR` `APR` `MAY` `JUN` `JUL` `AUG` `SEP` `OCT` `NOV` `DEC` |
| 星期 | `SUN` `MON` `TUE` `WED` `THU` `FRI` `SAT` |

`MON-FRI`、`JAN-JUN` 可以。`Monday`、`January` 不行。

### 7.4 星期数字（Quartz）

| 值 | 星期 |
| --- | --- |
| `1` / `SUN` | 星期日 |
| `2` / `MON` | 星期一 |
| `3` / `TUE` | 星期二 |
| `4` / `WED` | 星期三 |
| `5` / `THU` | 星期四 |
| `6` / `FRI` | 星期五 |
| `7` / `SAT` | 星期六 |

`0` 非法。不要按 Unix「0=周日」来写。

### 7.5 日字段特殊符

| 写法 | 含义 | 约束 |
| --- | --- | --- |
| `L` | 当月最后一天 | 2 月会随闰年 28/29 |
| `L-n` | 月末再往前 `n` 天 | `n` 为 `1`–`30`。例如 `L-2` = 倒数第 3 天 |
| `nW` | 离公历日 `n` 最近的工作日（周一到周五） | `n` 为 `1`–`31`。落在周六则提前到周五（1 号是周六则改到 3 号周一）；落在周日则推到周一（月末周日则提前到周五） |
| `C` | 日历占位 | 当前按「该日可用」处理，效果接近「每天都能匹配」。日写 `C` 时星期仍须 `?` |

这些写法 **不能** 再和列表 / 区间混在同一字段（例如 `1,L` 非法）。星期字段此时必须是 `?`。

### 7.6 星期字段特殊符

| 写法 | 含义 | 约束 |
| --- | --- | --- |
| `L` | 当月最后一个 **周六** | Quartz 里单独一个 `L` 表示周六 |
| `nL` | 当月最后一个星期 `n` | `n` 为 `1`–`7` 或 `SUN`–`SAT`。例如 `5L` / `FRIL` 为当月最后一个周五 |
| `n#k` | 当月第 `k` 个星期 `n` | `k` 为 `1`–`5`。例如 `2#1` = 第一个周一；`6#2` = 第二个周五 |
| `C` | 日历占位 | 当前按「该星期可用」处理。星期写 `C` 时日仍须 `?` |

日字段此时必须是 `?`。

`n#k` 若本月没有第 5 个该星期，那一月就不会因这条匹配。

### 7.7 年字段

省略或 `*`：1970–2099 内凡匹配月日时分秒的都算。  
写具体年：`"0 0 0 1 1 ? 2026"` 仅 2026-01-01 00:00:00。  
`2026-2028`、`2026/2`（2026、2028、… 直到 2099）可以。超出 1970–2099 非法。

可表示范围内找不到下一次触发时，这条触发器不会再开火（不会报 Lua 错）。

### 7.8 多组表达式（分号）

一条触发器可以把多组表达式用 **`;`** 拼在一起，最多 **10** 组。也接受全角分号 `；`。

下次触发取各组里 **最早** 的那一拍。

```lua
-- 每天 12:30 和 13:45 各一次，共用同一个 id / 回调
cron.create_trigger("0 30 12 * * ?;0 45 13 * * ?")
```

空组（`;;`、首尾悬空分号）非法。超过 10 组非法。整串仍受 511 字节限制。

### 7.9 触发对齐方式

调度按「**严格晚于当前时刻**」找下一秒开始的匹配点。已经踩在触发秒上再登记，要等到下一轮，不会立刻再打一次。

这是钟面对齐，不是周期定时器：

| 需求 | 写法 | 实际 |
| --- | --- | --- |
| 每个整 5 分钟 | `"0 */5 * * * ?"` | `xx:00:00`、`xx:05:00`… 无论何时 start |
| 从现在起再过 5 分钟 | 不要用 cron | `rt.delay(300000)` |

### 7.10 常用合法例子

| 表达式 | 含义 |
| --- | --- |
| `"0 * * * * ?"` | 每分钟的 0 秒 |
| `"0 */5 * * * ?"` | 每 5 分钟整分 |
| `"0 0 * * * ?"` | 每小时整点 |
| `"0 15 10 * * ?"` | 每天 10:15:00 |
| `"0 0 8 * * MON-FRI"` | 工作日 08:00:00（日必须是 `?`） |
| `"0 0 0 1 * ?"` | 每月 1 号 00:00:00 |
| `"0 0 0 L * ?"` | 每月最后一天 00:00:00 |
| `"0 0 9 15W * ?"` | 每月离 15 号最近的工作日 09:00:00 |
| `"0 0 10 ? * 6#1"` | 每月第一个周五 10:00:00 |
| `"0 0 0 ? * 7L"` | 每月最后一个周六 00:00:00 |
| `"0 0 0 1 1 ? *"` | 每年 1 月 1 日 00:00:00（7 段，年任意） |
| `"0 30 12 * * ?;0 45 13 * * ?"` | 每天两拍，一组触发器 |

### 7.11 常见非法例子

| 表达式 | 原因 |
| --- | --- |
| `"*/5 * * * *"` | 五段，缺秒，且日/星期都不是 `?` |
| `"0 * * * * *"` | 日、星期都是 `*`，缺 `?` |
| `"0 0 0 * * MON"` | 日是 `*`、星期已指定，缺 `?` |
| `"60 * * * * ?"` | 秒越界 |
| `"0 0 24 * * ?"` | 时越界 |
| `"0 0 0 0 * ?"` | 日从 1 起 |
| `"0 0 0 * * 0"` | 星期不能写 `0` |
| `"0 0 0 1,L * ?"` | `L` 不能和列表混写 |
| `"0 0 0 32W * ?"` | `nW` 的 `n` 超过 31 |
| `"0 0 0 ? * 2#6"` | `#k` 的 `k` 只能 1–5 |
| `""` | 空串 |

先 `validate_expr` 再 `create_trigger`。`validate` 为 `false` 时不要指望 create 成功。

---

## 8. 回调协议

### 8.1 签名

```lua
function(trigger_id, user_tag)
```

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `trigger_id` | integer | `create_trigger` 返回的 id |
| `user_tag` | 任意 / `nil` | `bind_trigger` 第三参；未传则为 `nil` |

可以忽略参数：`function() ... end` 仍然合法。

### 8.2 执行位置

到期 → 投递到运行时事件 → **Lua 调度循环** 里 `pcall` 回调。

- 不是硬件中断
- 通常不是独立 `rt.task`
- 返回前整台 Lua 调度被占住

回调里抛错：记日志后吞掉，不影响后续调度。

### 8.3 建议写法

```lua
cron.bind_trigger(id, function(tid, tag)
    rt.mbox_send("cron_tick", tag or tid)
end)
```

打印、网络、长逻辑放到 `rt.task` 里做。测低功耗电流时不要在回调里打长日志，串口会把休眠脉冲放大。

---

## 9. 错误与返回约定

`require("cron")` 失败会 **抛错**（见下表）。业务接口除 `validate_expr` 缺参外 **不抛**，走返回值。缺参、类型错走 Lua 标准 `bad argument #n`。没有数字业务码。兜底文案 `unknown` 仅在内部未带出原因时出现。

**`require` 抛错摘要**

| 摘要 | 可能原因 |
| --- | --- |
| `cron owner invalid` | 当前虚拟机无法绑定（快捷回调 VM 等） |
| `cron ctx exhausted` | 主 VM 槽用尽（当前产品基本单 VM，正常遇不到） |
| `cron not initialized` | 调度后端未就绪 |

**`create_trigger`（失败是 `0, err`，不是 `nil`）**

| `err` | 可能原因 |
| --- | --- |
| `invalid cron expr` | 第一参不是非空字符串 |
| `cron create_trigger failed` | 已满 30 条，或表达式底层创建失败 |
| `cron register failed` | 到期事件登记失败 |
| `cron lock failed` | 内部锁失败 |
| `cron not initialized` / `cron owner invalid` | 后端未绑定或虚拟机无效 |

成功：`id, ""`。

**`validate_expr`**

| 情况 | 行为 |
| --- | --- |
| 缺参 / 非字符串 | **抛** Lua 类型错 |
| 合法 | `true` |
| 非法 | `false`（无第二返回值） |

**其余接口（`bind` / `start` / `stop` / `pause` / `resume` / 单条控制 / `replace` / `remove` / `clear`）**

成功 `true, nil`；失败 `nil, err`。

| `err` | 可能原因 |
| --- | --- |
| `invalid cron id` | id 不是整数也不是纯十进制串，或越界（1～30） |
| `invalid callback` | `bind` 第二参不是 function |
| `invalid cron expr` | `replace` 时表达式空 / 非字符串 |
| `cron trigger not exists` | bind 时还没 `create`，或已 `remove` |
| `cron bind_trigger failed` | 把回调绑到该 id 失败 |
| `cron start failed` | 启动整表调度失败 |
| `cron not initialized` | 后端未就绪；**或** `pause`/`resume` 时还没 `start` |
| `cron lock failed` | 内部锁失败 |
| `cron register failed` | 到期事件登记失败 |
| `cron remove_trigger failed` | id 不存在或删除失败 |
| `cron pause_trigger failed` | 该 id 不存在或暂停失败 |
| `cron resume_trigger failed` | 该 id 不存在或恢复失败 |
| `cron replace_trigger failed` | id 不存在或新表达式非法 |
| `cron owner invalid` | 当前虚拟机无法使用本模块 |

`start` / `stop` 设计为幂等，正常重复调用应成功。

---

## 10. 资源上限与生命周期

| 资源 | 上限 | 说明 |
| --- | --- | --- |
| 触发器 | `cron.MAX_TASKS` = **30** | 每主 VM 一份。`create` / `bind` 共用这一上限。满则 create 失败 |
| 一组触发器内的表达式 | **10** 组 | 分号拼接 |
| 表达式字符串 | **511** 字节 | 含分号后的整串 |
| 到期投递队列 | 约 **16** | 满则丢掉更早未处理的一次 |
| 主脚本 VM | 当前产品 **1** | 快捷回调 VM 无本模块 |

没有 userdata。回调和 `user_tag` 挂在模块与当前 VM 上。脚本结束 / 虚拟机退出会统一拆除，不会在脚本停了之后继续打回调。

id 不跨次运行保证不变。`stop` 不删表；`remove` / `clear` 才删。

未授时：调度器不轮询空转（避免把低功耗拉起来）。授时成功（尤其是 NITZ）后重算下一拍。等到点用可休眠的等待，系统可以进低功耗；到期由 RTC 唤醒再跑回调。

---

## 11. 选型对照

| 需求 | 用什么 |
| --- | --- |
| 对齐钟面（整 5 分钟、每天 10:15） | **`cron`** |
| 从现在再等 N 毫秒 / 周期循环 | `rt.delay` 或 `rt.tmr_loop` |
| 秒级以下、或每秒很多次 | **不要用 cron**，用 delay / 定时器 |
| 低功耗下「睡到整点再醒」 | cron + `lp` 低功耗档；回调里只投递 |
| UART/SMS 快捷回调里排程 | 本模块不可用，把需求丢回主脚本 |

`rt.delay(300000)` 和 `"0 */5 * * * ?"` 不是一回事：前者跟 start 时刻有关，后者跟墙上的 `xx:00` / `xx:05` 对齐。

---

## 12. 完整示例

先授时，再登记 5 分钟对齐。回调只投递，打印放在任务里。完整低功耗流程见 [examples/nt26/module/lp/lowpower_cron](../../../../examples/nt26/module/lp/lowpower_cron)。

```lua
local rt = require("rt")
local log = require("log")
local cron = require("cron")
local info = require("info")

local EXPR = "0 */5 * * * ?"
local TOPIC = "cron_5min"

rt.task_start(function()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok then
            log.info("aligned tick ev=%s time=%s", tostring(ev), tostring(info.times()))
        end
    end
end)

while not info.time_ready() do
    rt.delay(1000)
end

if not cron.validate_expr(EXPR) then
    log.info("invalid expr")
    return
end

local id, err = cron.create_trigger(EXPR)
if id == 0 then
    log.info("create_trigger fail: %s", tostring(err))
    return
end

local ok, bind_err = cron.bind_trigger(id, function()
    rt.mbox_send(TOPIC, "tick")
end)
if not ok then
    log.info("bind_trigger fail: %s", tostring(bind_err))
    return
end

ok, err = cron.start()
if not ok then
    log.info("start fail: %s", tostring(err))
    return
end

log.info("cron started id=%s next */5 now=%s", tostring(id), tostring(info.times()))
rt.delay(-1)
```

换周期、整表暂停示例：

```lua
assert(cron.pause_trigger(id))
assert(cron.resume_trigger(id))
assert(cron.replace_trigger(id, "0 */10 * * * ?"))
assert(cron.pause())
assert(cron.resume())
assert(cron.remove_trigger(id))
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.1.0 | 2026-09-05 | 补全错误与返回约定：全部 `err` 文本、抛错摘要与可能原因 |
