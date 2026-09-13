#  Lua 脚本包

**文档版本** `1.1.0`

脚本底层按 **A/B** 双槽设计：部署、写文件、清单。与 Lua [`script`](../api/module/script.md) 操作同一套包。**当前产品配置未启用双槽切换**（本版本可用空间偏紧；日后 8+8 / CAT4 才可能打开），不要把选槽、试运行、回滚当成已交付业务。虚拟机如何跑这份包、配额见 [DoLua 核心](../core/README.md)。通用约定见 [convention.md](convention.md)。失败短 reason。

`SCRIPTCB`（把 UART/SMS 回调脚本当文件读写）**部分镜像没有**。没有时发该指令会当未知命令。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. 擦除](#3-擦除)
- [4. AT+SCRIPTBUNDLE / AT+SCRIPTDEPLOY](#4-atscriptbundle--atscriptdeploy)
- [5. AT+SCRIPTFILE / AT+SCRIPTMANIFEST](#5-atscriptfile--atscriptmanifest)
- [6. AT+SCRIPTSELECT / CONFIRM / ROLLBACK](#6-atscriptselect--confirm--rollback)
- [7. AT+SCRIPTCB](#7-atscriptcb)
- [8. 联调顺序](#8-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 槽名 | `A` / `B`（大小写不敏感）。省略 = **当前 active** |
| `stream` | 回 `>` 后用 UARTQUE 再收一包（须 UART） |
| trial | `SCRIPTSELECT` 第二参 `1`=试运行（未确认，可回滚），`0`=直接切。**当前配置未启用切槽，不要当产品路径** |

不要在回调里热更新自己正在跑的文件。

---

## 2. 指令一览

| 指令 | 作用 |
| --- | --- |
| `AT+SCRIPTCLEAR` | 清脚本相关（查询形态触发，见帮助） |
| `AT+SCRIPTDEL` | 擦脚本存储（不卸载正在跑的 VM） |
| `AT+SCRIPTBUNDLE` | 查 AB 包状态 |
| `AT+SCRIPTDEPLOY` | 指定后续写入落到哪一槽 |
| `AT+SCRIPTFILE` | 写/读/删 `main` 或 `module` |
| `AT+SCRIPTMANIFEST` | 写 / 重建 / 读清单 |
| `AT+SCRIPTSELECT` | 选下次启动槽 |
| `AT+SCRIPTCONFIRM` | 确认 trial |
| `AT+SCRIPTROLLBACK` | 回到已确认槽 |
| `AT+SCRIPTCB` | 可选：uart/sms 回调脚本 |

---

## 3. 擦除 {#3-擦除}

```lua
AT+SCRIPTCLEAR
AT+SCRIPTDEL
```

测试 `=?`。成功 `OK`。`SCRIPTDEL` **不会**卸掉当前已在跑的脚本 VM，复位后才按空包/另一槽启动。

---

## 4. AT+SCRIPTBUNDLE / AT+SCRIPTDEPLOY {#4-atscriptbundle--atscriptdeploy}

```lua
AT+SCRIPTBUNDLE?
```

给出 deploy / active / confirmed、版本信息，以及每槽 `valid` 与清单长度。

```lua
AT+SCRIPTDEPLOY="A"
AT+SCRIPTDEPLOY
```

无参或空槽 = 当前 active。非法槽 `"error slot"`。

---

## 5. AT+SCRIPTFILE / AT+SCRIPTMANIFEST {#5-atscriptfile--atscriptmanifest}

```lua
AT+SCRIPTFILE="A","main",1,"stream"
>
```

`kind`：`main` / `module`。`id` 1～35。`action`：`stream` / `read` / `delete`。可省略槽名（四段变三段）。

读：

```lua
+SCRIPTFILE:"A","main",1,"read",<len>
<字节>

OK
```

清单：

```lua
AT+SCRIPTMANIFEST="A","stream"
AT+SCRIPTMANIFEST="A","rebuild"
AT+SCRIPTMANIFEST="A","read"
```

`read` 成功带长度和 valid（0/1）。空清单长度 0 仍 `OK`。

---

## 6. AT+SCRIPTSELECT / CONFIRM / ROLLBACK {#6-atscriptselect--confirm--rollback}

```lua
AT+SCRIPTSELECT?
```

回 active / confirmed / pending 及版本。

```lua
AT+SCRIPTSELECT="B",1
+SCRIPTSELECT:"B",1

OK

AT+SCRIPTCONFIRM?
AT+SCRIPTROLLBACK?
```

`trial=1`：设计上是下次启动试 B，不确认则按产品策略回滚。`CONFIRM` 把 trial 变成正式。`ROLLBACK` 回到已确认槽。

**当前版本未启用双槽切换**，这些指令不要当已开通的升级/回滚业务来联调。原因与后续版本见 [核心 · 运行第 2 节](../core/runtime.md#2-脚本副本a--b-两槽)。

---

## 7. AT+SCRIPTCB {#7-atscriptcb}

本镜像编译了才有。

```lua
AT+SCRIPTCB="uart","stream"
AT+SCRIPTCB="sms","read"
AT+SCRIPTCB="uart","enable",1
AT+SCRIPTCB="uart","delete"
```

`cb_name`：`uart` / `sms`。查询 `AT+SCRIPTCB?` 列出使能。reason：`name`、`action`、`stream_read`、`limit` 等。

---

## 8. 联调顺序

当前版本：DEPLOY → FILE 写入 → MANIFEST rebuild 或 stream → 复位验证。不要走 SELECT trial / CONFIRM / ROLLBACK。

（双槽切换若在日后 8+8 / CAT4 打开，设计顺序才是：DEPLOY → FILE → MANIFEST → SELECT trial → 复位 → CONFIRM；失败回 ROLLBACK。）

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：AB 槽部署、试运行、确认回滚 |
| 1.0.1 | 2026-09-12 | 文首链到 DoLua 核心（运行机制与配额） |
| 1.1.0 | 2026-09-12 | 标明双槽切换当前未启用；联调改为单份部署 |
