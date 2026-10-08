#  透传任务（RTU / DTU）

**文档版本** `1.1.3`

四路透传任务选 SOCK 还是 MQTT、心跳/注册包、上下行路由、往通道写裸数据、暂停恢复、AT 口密码锁、云配置拉取策略。与 [`[task.N]`](../../api/rtu_config/rtu_config.md#17-task--taskn--tasknheart--tasknreg)、[`[netio.N]`](../../api/rtu_config/rtu_config.md#21-netion)、`[loader]` 同一套。

通道 1～4 与 Socket/MQTT **同一路 N**。透传场景见 [专栏 · Socket](../topics/socket.md)、[专栏 · MQTT 连接](../topics/mqtt.md)。串口上行 / 四路通道下行见 [专栏 · 路由](../topics/route.md)。通用约定见 [convention.md](convention.md)。`DTUPSUP` / `DTUPSDN` / `RTUWRITE` 的路由串见 [route.md](route.md)（`DTUHEART` / `DTUREG` 最后一段不是这套语法）。失败短 reason。

---

## 目录

- [1. 指令一览](#1-指令一览)
- [2. AT+RTUCONFIG](#2-atrtuconfig)
- [3. AT+DTUTASK / AT+DTUSTATE](#3-atdtutask--atdtustate)
- [4. AT+NETIO](#4-atnetio)
- [5. AT+DTUHEART / AT+DTUREG](#5-atdtuheart--atdtureg)
- [6. AT+DTUPSUP / AT+DTUPSDN](#6-atdtupsup--atdtupsdn)
- [7. AT+RTUWRITE / AT+RTUWRITEQ](#7-atrtuwrite--atrtuwriteq)
- [8. AT+RTUCTL / AT+RTUPSD / AT+DTUMSGHEAD](#8-atrtuctl--atrtupsd--atdtumsghead)
- [9. AT+CLDCFG](#9-atcldcfg)
- [10. 联调顺序](#10-联调顺序)
- [修订记录](#修订记录)

---

## 1. 指令一览

| 指令 | 作用 |
| --- | --- |
| `AT+RTUCONFIG` | `write` 覆盖写入本地 `/rtu_config.cfg`；`read` 读出该文件；`delete` 只删本地文件（固件 `1.3.5` 起）。三条都不改当前运行时 |
| `AT+DTUTASK` | `<id>,<en>,"SOCK"\|"MQTT"` |
| `AT+DTUSTATE` | 查该路任务是否在跑 |
| `AT+NETIO` | 通道在线指示 IO |
| `AT+DTUHEART` / `DTUREG` | 心跳 / 注册包（hex + 本路发布槽列表） |
| `AT+DTUPSUP` / `DTUPSDN` | 串口上行总闸 / 通道下行路由 |
| `AT+RTUWRITE` | 按路由写裸数据，成功回 `OK` |
| `AT+RTUWRITEQ` | 同 WRITE，**成功不回 OK** |
| `AT+RTUCTL` | `0` 暂停 / `1` 恢复该路 |
| `AT+RTUPSD` | AT 口密码锁 |
| `AT+DTUMSGHEAD` | 接收数据是否带头 |
| `AT+CLDCFG` | 云端拉配置策略（`[loader]`） |

写任务配置默认不拆已建立连接，与 Socket 篇相同。

---

## 2. AT+RTUCONFIG {#2-atrtuconfig}

读写内置文件系统上的本地配置文件 **`/rtu_config.cfg`**（最大 32 KB）。`write` / `read` / `delete` 都只动这个文件，不套用、不改当前已经生效的业务配置。文件更新或删除后，**下次开机**才再解析；文件不在则开机跳过，沿用机内已有配置。语法见 [`rtu_config.cfg`](../../api/rtu_config/rtu_config.md)。

`delete` 从固件 **`1.3.5`**（`NT26-PRO-RTU-D1.3.5`）起支持。更早的包没有这个动作，会回 `"error action"`。

```lua
AT+RTUCONFIG="write"
>
<一整包配置文本>
+RTUCONFIG: "write",<len>

OK
```

`write` 先回 `>`，约 10 秒内收一包原始配置文本，整包覆盖写入 `/rtu_config.cfg`。成功回写入长度。

```lua
AT+RTUCONFIG="read"
+RTUCONFIG: "read",<len>
<文件原文>

OK
```

文件不存在或长度为 0 时回 `+RTUCONFIG: "read",0`，后面直接 `OK`，没有正文。

```lua
AT+RTUCONFIG="delete"
+RTUCONFIG: "delete"

OK
```

只删除本地 `/rtu_config.cfg`。文件本来就不在也回 `OK`。已经在跑的配置保持不动。

失败统一 `+RTUCONFIG: "error <reason>"` 再 `ERROR`。reason：`param`、`action`、`read`、`write`、`stat`、`size`、`malloc`、`delete`。

---

## 3. AT+DTUTASK / AT+DTUSTATE {#3-atdtutask--atdtustate}

```lua
AT+DTUTASK=1,1,"MQTT"
+DTUTASK: 1,1,"MQTT"

OK

AT+DTUTASK=1?
+DTUTASK: 1,1,"MQTT"

OK

AT+DTUSTATE=1
+DTUSTATE: 1,<state>

OK
```

`taskid` 大小写不敏感：`SOCK` / `MQTT`。`enable=0` 时不必给合法 taskid。reason：`param`、`id`、`enable`、`taskid`、`read`、`save`。

---

## 4. AT+NETIO {#4-atnetio}

```lua
AT+NETIO=1,1,3,1
```

`<id>,<enable>,<gpio>,<active_mode>`。gpio 0～38；`active_mode` `0` 低有效 / `1` 高有效。查询 `AT+NETIO=<id>?`。

---

## 5. AT+DTUHEART / AT+DTUREG {#5-atdtuheart--atdtureg}

```lua
AT+DTUHEART=<id>,<en>,<interval>,"<hex包>","<路由>"
AT+DTUREG=<id>,<en>,"<hex包>","<路由>"
```

心跳 interval 1～65535（秒或毫秒以帮助/配置文件为准，配置文件 `[task.N.heart]`）。hex 包是**十六进制文本**。最后一段是 `channel_str`：只用 `|` 并选**本路** MQTT 发布槽 1～8（例如 `"1|2"`），**不是** [路由串](route.md)。写 `6[1]` 不会出 UART。该路是 SOCK 时这段不改变发送目标。非法 `"error channel_str"`。

---

## 6. AT+DTUPSUP / AT+DTUPSDN {#6-atdtupsup--atdtupsdn}

```lua
AT+DTUPSUP=<uart1-3>,"<路由>"
AT+DTUPSDN=<id1-4>,"<路由>"
```

上行：哪路 UART 的数据转到哪些出口。下行：通道数据转到哪些口。路由串见 [route.md](route.md)，例如 `"1|2"`、`"6[1]"`、`"1[1:2]|6[1]"`。查询 `=<id>?`。

---

## 7. AT+RTUWRITE / AT+RTUWRITEQ {#7-atrtuwrite--atrtuwriteq}

```lua
AT+RTUWRITE="<路由>",<TAILRAW>
```

第一个逗号之后是**原始字节**（不是 hex 解码）。成功 `OK`。`RTUWRITEQ` 成功**完全静默**（方便透传）。路由串见 [route.md](route.md)。路由非法 / 发送失败短 reason。

---

## 8. AT+RTUCTL / AT+RTUPSD / AT+DTUMSGHEAD {#8-atrtuctl--atrtupsd--atdtumsghead}

```lua
AT+RTUCTL=1,0
AT+RTUCTL=1,1
AT+RTUPSD=1,"secret"
AT+DTUMSGHEAD=1
```

密码锁密码最长 80。`DTUMSGHEAD` 对应配置 `is_recv_header`。查询 `AT+DTUMSGHEAD?`。

---

## 9. AT+CLDCFG {#9-atcldcfg}

云端配置拉取，key 与 `[loader]` 相同。形态类似其它 CFG：`"key"` 查询，`"key",值` 设置。测试 `AT+CLDCFG=?`。

---

## 10. 联调顺序

先 `AT+SOCK` 或 `AT+MQTT` 配对端，再：

```lua
AT+DTUTASK=1,1,"SOCK"
AT+DTUSTATE=1
```

串口透传再配 `DTUPSUP` / `DTUPSDN`。脚本侧对照 `require("rtu")`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：任务、路由、写通道、密码锁、云配置策略 |
| 1.1.0 | 2026-09-07 | 上下行/写出链到 [route.md](route.md)；纠正 HEART/REG 最后一段是发布槽列表，不是路由串 |
| 1.1.1 | 2026-09-19 | 随目录迁到 `at/manual/`；文首链到 Socket / MQTT 专栏 |
| 1.1.2 | 2026-09-19 | 文首链到 [专栏 · 路由](../topics/route.md) |
| 1.1.3 | 2026-10-08 | `AT+RTUCONFIG` 改为读写本地 `/rtu_config.cfg`，不改运行时；新增 `delete`（固件 `1.3.5` 起） |
