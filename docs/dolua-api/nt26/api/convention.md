# 通用约定

**文档版本** `1.2.0`

Lua API 各模块共用的命名和调用方式。一篇模块文档只写本模块的差异，不再另起一套名字或返回风格。应用 AT 的行格式见 [AT 通用约定](../at/manual/convention.md)，两套入口不互相套用语法。

已有模块里和下面不一致的写法，以该模块自己的文档为准。新接口按本篇写，不要把那些旧写法再抄到新模块。

---

## 目录

- [1. 名字](#1-名字)
  - [1.1 动词](#11-动词)
  - [1.2 `open`、`new`、`create`](#12-opennewcreate)
- [2. 调用形态](#2-调用形态)
- [3. 参数类型](#3-参数类型)
- [4. 字节从哪来](#4-字节从哪来)
- [5. 成功与失败](#5-成功与失败)
  - [5.1 三种返回](#51-三种返回)
- [6. 回调与阻塞](#6-回调与阻塞)
- [7. 对象活多久](#7-对象活多久)
- [8. 已有模块里不要再扩散的写法](#8-已有模块里不要再扩散的写法)
- [修订记录](#修订记录)

---

## 1. 名字

| 项 | 写法 | 现有例子 |
| --- | --- | --- |
| 模块名 | 小写。多词用下划线。`require` 的名字和文档文件名相同 | `gpio`、`soft_i2c`、`flashdb`、`ublob` |
| 函数、方法 | 小写蛇形。动词在前，名词在后 | `open`、`read`、`wait_connect`、`send_async`、`wave_stop` |
| 配置键 | 小写蛇形 | `server_host`、`tls_enable`、`clean_session` |
| 时间 | 毫秒键以 `_ms` 结尾。秒要在键名里写出单位 | `connect_timeout_ms`、`poll_interval_ms` |
| 常量 | 挂在模块表上，全大写，词用下划线 | `gpio.BY_GPIO`、`http.TLS_SERVER_AUTH`、`mqtt.TLS_MUTUAL_AUTH` |
| 事件名 | 回调表里的小写字符串 | `connected`、`message`、`error` |

同一含义跨模块用同一组数。TLS 校验级别在 `http` 和 `mqtt` 都是 `1` 不校验、`2` 校验服务端、`3` 双向，常量名都是 `TLS_INSECURE`、`TLS_SERVER_AUTH`、`TLS_MUTUAL_AUTH`。

开关用 `true` / `false`。关掉某项就写 `false`，不要把 `0` 同时当成「关」和「默认」。`mqtt` 的加密开关是 `tls_enable = false`，`tls_seclevel` 里没有 `0`。

模块表上放工厂函数和常量。对象方法只挂在对象上：`led:set(true)` 可以，`gpio.set` 不行。

### 1.1 动词 {#11-动词}

新函数按动作取名，仍然是小写蛇形。

| 动作 | 名字 | 现有例子 |
| --- | --- | --- |
| 打开设备或会话 | `open` | `gpio.open`、`pwm.open` |
| 关掉，对象还在 | `close` | `pwm:close`、`view:close` |
| 造一个托管对象，这时还不连、还不占外设动作 | `create` | `tcp.create`、`mqtt.create` |
| 改一项状态 | `set_` | `lp.set_mode`、`pwm:set_duty` |
| 读一项状态 | `get_` | `lp.get_mode`、`uart.get_config` |
| 一次写下整组线路参数 | `config` | `gpio:config`、`uart.config` |
| 问是不是 | `is_` | `rtu.is_connect` |
| 存储、串口、I2C 上的字节 | `read` / `write` | `ublob.read`、`uart.write`、`i2c:mem_read` |
| 总线上的一拍收发 | `send` / `recv` | `spi:send`、`spi:recv` |
| 连接上发出去，调用方等到这一拍结束 | `send` 或 `pub` | `tcp:send`、`mqtt:pub` |
| 交出去就返回 | 同一动词加 `_async` | `tcp:send_async`、`mqtt:pub_async` |

进来的数据走回调：`tcp` 在收包回调里，`mqtt` 在 `message` 事件里，`uart` 在 `reg` 的回调里。不再为入站配一个和 `send` 成对的 `recv`。

已经用 `status()` 表示「现在连着吗」的，继续用 `status`。新的是否判断用 `is_`。

### 1.2 `open`、`new`、`create` {#12-opennewcreate}

三个词都是「拿到一个对象」，分的是对象从哪来。

| 词 | 什么时候用 | 现有例子 |
| --- | --- | --- |
| `open` | 机子上已经有这一份，按编号去占。关掉只结束这次占用，设备或文件还在 | `gpio.open`、`pwm.open`、`audio.open`、`ublob.open` |
| `new` | 没有固定的「第几个」，对象是按参数拼出来的 | `lcd.new`、`soft_i2c.new` |
| `create` | 造一条还没开始工作的托管对象。后面的 `open` 才是去连 | `tcp.create` 然后 `tcp` 的 `open`；`mqtt` 相同 |

控制器有编号、同一编号只能占一路的，用 `open`。`i2c`、`spi` 就是这样：`open` 是 `new` 的别名，`close` 是 `deinit` 的别名，参数和返回值相同，调用哪一个都进同一个函数。`camera.open` / `camera.close` 同样是 `init` / `deinit` 的别名。新脚本写 `open` / `close`。旧名字继续可用。

屏和软件 I2C 没有这种编号，继续只用 `new`，不加 `open`。

## 2. 调用形态

模块函数写成 `mod.func(...)`。对象方法用冒号，点号调用必须自己把对象放在第一参。

```lua
led:set(true)
led.set(led, true)
```

两种模块，不要混成第三种：

| 种类 | 入口 | 现有例子 |
| --- | --- | --- |
| 纯函数 | 一次调用做完，没有长期对象 | `http.request`、`ublob.write`、`dns`、`ntp` |
| 对象 | `open` 或 `create` 返回 userdata，之后都在对象上操作 | `gpio.open`、`ublob.open` 的 view、`tcp.create`、`mqtt.create` |

托管连接（`tcp`、`mqtt`）的顺序固定：

1. `create(cb[, cfg])` 得到对象并拉起线程，此时还不连。
2. `open` 只把目标改成「要连」。返回成功表示已经交给内部，不表示已经连上。
3. `close` 把目标改成挂起，停掉重连。
4. `delete` 拆掉这一路。丢了对象引用，回收时也会拆。

配置用一张表。`create` 的第二参和 `update` 吃的是同一套键：表里没写的键保持原值，类型不对的键不生效。未在该篇列出的键忽略。

一个函数有多种参数个数或类型时，该篇把每一种调用模式分开写。用 `nil` 表示「这一项不改」，见 `mqtt:auth`。省略和 `nil` 在该篇写清楚，不要让读者猜。

## 3. 参数类型

| 文档写的类型 | 调用时 |
| --- | --- |
| boolean | `true` 或 `false` |
| number / integer | 该篇写出的闭区间。越界只走一种失败：要么抛错，要么返回 `err`，同一个函数不要两种都有 |
| string | Lua 字符串。二进制按字符串长度，不在 `\0` 处截断 |
| table | 配置表，或下面第 4 节的存储描述 |
| userdata | 本模块 `open` / `create` 返回的对象。别的模块的对象要在该篇点名 |

文档写成 boolean 的参数，新接口只认 `true` / `false`。写成 `1` 或 `0` 按类型错误处理（返回 `err` 或抛错，与该函数其它类型错误同一条路）。

## 4. 字节从哪来

正文和「去哪读」分成两种值。

字符串就是正文本身：PEM、HTTP body、PCM、要写入 `ublob` 的字节。

要从一块存储读或写，用表，靠字段区分存储。短名规则与 [`ublob`](module/ublob.md) 第 10 节相同：不能含 `/`、`\`、`:`。

| 表 | 含义 | 现有例子 |
| --- | --- | --- |
| `{ ublob = "ca.pem" }` | 内部 ublob 的短名 | `http` 的 `save`、`lvgl` 的图片和字库、`mqtt` 的证书、录音落盘 |
| `{ lfs = fs, path = "/logo.jpg" }` | 已经 `lfs.mount` 的对象加路径 | `http.save.lfs`、`lvgl` |
| `{ kv = db, key = key }` | 已挂载的 FlashDB KV | `http.save.kv` |
| `{ ts = db }` | 已挂载的 FlashDB 时序 | `http.save.ts` |

`http.save.ublob(name)` 这类构造函数只是帮你做出上面的表，字段含义不变。

## 5. 成功与失败

一个函数只占下面一种返回。该篇的「错误与返回约定」把 `err` 原文列全。`err` 是稳定的短英文，脚本可以比较。同一原因始终同一句。

业务上的失败用返回值：名字不存在、没连上、配额不够、队列满。调用方式错才抛错：缺参、类型不对、参数个数对不上某一种调用模式。抛错要用 `pcall` 才接得住，文案同样是短英文。

`ublob.write` 是这条分界的样子：`name` 不是字符串时抛错；盘满、名字非法返回 `nil, err`。

回调里的抛错是否吞掉，由该模块写明。`uart` 的收包回调会记日志后吞掉。

### 5.1 三种返回 {#51-三种返回}

**问成不成。** 成功返回 `true`。失败返回 `nil, err`。`0` 和 `1` 只表示数量或电平，不表示成功或失败。

**问干了多少。** 成功返回字节数。一个字节都没处理返回 `0`。失败仍是 `nil, err`，`0` 不兼表失败。

**拿到一段数据。** 成功返回字符串。没有内容返回 `""`。这一路若用 `nil` 表示失败，该篇在返回值里写明，并带上 `err`。

问「现在是不是」可以只返回 boolean：`status()` 为真即已连接，`wait_connect` 超时为 `false`。对象已经无效时带上 `err`，该篇写明是 `false, err` 还是 `nil, err`。

## 6. 回调与阻塞

回调跑在 Lua 调度循环里。回调要短：不要 `rt.delay`，不要 `wait_connect`，不要同步的 `pub` / `request`。往连接上回数据用异步接口，例如 `pub_async`、`send_async`。

会占住整条引擎的调用，不要放进别的回调。已经这样的有 `http.request`、`gpio` 的 `seq`、大块的 `ublob.read` / `ublob.append`。

托管连接断线后内部自己重连。不要在 `disconnected` 或 `error` 里再 `open`。

结果要等一会儿才有的，用回调，或模块自己的等待方法，例如 `wait_connect`。脚本不订内部 topic。能拆成短调用加回调的，不再加一个会占住调度很久的同步函数。

## 7. 对象活多久

脚本必须自己留着对象（模块级 `local` 或等价的长期引用）。引用没了会被回收，这一路资源一起释放。

虚拟机退出时，本虚拟机打开的对象由模块收掉。同时能开几路、缓冲多大，写在该篇的资源表里，不挂成一个没有业务含义的常量，除非脚本需要拿这个数做判断（`tcp.MAX_CLIENTS` 就是这种）。

`close` 之后对象还在，再操作按该篇的失败文案返回。需要立刻腾出名额时调用 `close`，不要只等回收。`ublob` 的 view 同时只能开一个，漏 `close` 下一个 `open` 会得到 `"too many open views"`。

## 8. 已有模块里不要再扩散的写法

这些是现有行为，文档已经写明。新接口不要再做成这样：

| 现有写法 | 出现在 | 新接口怎么做 |
| --- | --- | --- |
| 成功多返回一个 `"ok"` | `tcp:update`、`mqtt:update` | 成败成功只返回 `true` |
| 数字 `0` 在布尔语义里为真 | `gpio` 的 `set` / `config`；`ublob` view 的 `md5` 第三参 | 布尔只认 `true` / `false` |
| 失败只有 `false`，没有 `err` | `uart.write` | 业务失败带上稳定的 `err` |
| 失败是 `nil, err_code, err_msg` 三个返回值 | `http.request` | 业务失败两个返回值：`nil, err` 或 `false, err` |
| 时间键没有单位后缀，单位是秒 | `mqtt` / `tcp` 的 `keepalive_interval` | 新的毫秒键用 `_ms`，秒在键名里写明 |
| 同一种参数错误，有的抛错、有的只返回 `false` | `uart` 的口编号：多数函数抛 `"invalid uart id"`，`unreg` 越界只返回 `false` | 同一个函数的同类错误只走一条路 |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-10-13 | 首版。从现有模块归纳命名、调用形态、存储表、返回值与回调 |
| 1.1.0 | 2026-10-13 | 补动词前缀，以及成败、字节数、数据三种返回 |
| 1.2.0 | 2026-10-14 | 写明 `open` / `new` / `create` 各用于哪类对象；`i2c`、`spi`、`camera` 的 `open`/`close` 是别名 |
