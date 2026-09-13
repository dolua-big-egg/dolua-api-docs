# DoLua 核心

**文档版本** `1.2.0`

本分类讲 **DoLua 是什么、怎么跑起来、消息和调度怎么协作、资源有多大**。读完再进各模块 API，会对「为什么回调里不能等」「脚本为什么突然没空间」有一张整图。

这里只讲分层、数据流和数字上限。需要调用形态、参数、失败文案时，转到 [API 索引](../api/README.md)。文中出现的代码块是 **伪码**，用来画流程，不能当可烧录脚本复制。

当前公开型号：**NT26**（含 NT26 PRO）。下文数字以该型号当前固件为准；其它型号若未单独公布，不要套用。

---

## 目录

- [建议阅读顺序](#建议阅读顺序)
- [本分类文档](#本分类文档)
- [读完去哪里](#读完去哪里)
- [修订记录](#修订记录)

---

## 建议阅读顺序

1. [什么是 DoLua](what.md) — 定位、语言、模块从哪来、和别的 Lua 不是一套
2. [DoLua 是怎么运行的](runtime.md) — 上电选槽、虚拟机、入口协程、脚本生命周期
3. [消息和调度](schedule.md) — 协作式任务、事件队列、信箱/队列、回调纪律
4. [可用资源](resources.md) — RAM、内部代码区、模块个数与长度、调度名额
5. [工程与脚本包](project.md) — 主文件 / 用户模块 / 配置 / 内置文件怎么进设备
6. [存储怎么分](storage.md) — 内部共享配额 vs 外挂盘，存什么用哪一块

侧边栏怎么认工程、五区、LUAPK，另见 [工程结构](../../dolua-assisant/工程结构.md)（开发助手分类）。

入门工程仍建议：`started/hello` → `started/log` → `started/task`，见 [示例索引](../../../examples/NT26/README.md)。

---

## 本分类文档

| 文档 | 回答什么 |
| --- | --- |
| [what.md](what.md) | DoLua 解决什么问题、脚本长什么样、能力从哪来 |
| [runtime.md](runtime.md) | 固件怎样把一份工程变成正在跑的虚拟机 |
| [schedule.md](schedule.md) | 多任务为什么不是抢占、消息怎么走、回调在哪执行 |
| [resources.md](resources.md) | 堆、栈、Flash、文件个数、调度槽位各多少 |
| [project.md](project.md) | 工程分区、打包部署（双槽切换当前未启用） |
| [storage.md](storage.md) | 内部文件、脚本区、外挂 Flash 各管什么 |
| [工程结构](../../dolua-assisant/工程结构.md) | 侧边栏五区、`luaproj`、LUAPK（开发助手，不在本目录） |

硬件脚位不在本分类：[hardware/](../hardware/README.md)。应用 AT 不在本分类：[at/](../at/README.md)。

---

## 读完去哪里

| 接下来要做的 | 去这里 |
| --- | --- |
| 查某个 `require("…")` | [api/README.md](../api/README.md) |
| 对原理图、选脚 | [hardware/README.md](../hardware/README.md) |
| 用 AT 部署/查询脚本包 | [at/script.md](../at/script.md) |
| 抄一份能烧录的工程 | [examples/NT26](../../../examples/NT26/README.md) |
| 看工程文件夹 / LUAPK | [工程结构](../../dolua-assisant/工程结构.md) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-12 | 首版：DoLua 核心分类入口 |
| 1.1.0 | 2026-09-12 | 索引标明当前未启用双槽切换 |
| 1.2.0 | 2026-09-13 | 链到开发助手「工程结构」（五区 / LUAPK） |
