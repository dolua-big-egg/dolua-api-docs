# doLua 核心

**文档版本** `1.4.0`

本分类讲 **doLua 是什么、引擎怎么跑、消息和调度怎么协作**。这是跨型号的总图：一台设备、一个脚本虚拟机、协作式多任务。读完再进各型号的 API，会对「为什么回调里不能等」「入口 return 之后业务还在不在」有一张整图。

这里只讲分层和数据流。各型号的堆、Flash、模块个数见该型号的 **资源** 篇。需要调用形态、参数、失败文案时，转到对应型号的 API 索引。文中代码块是 **伪码**，用来画流程，不能当可烧录脚本复制。

当前公开型号：**NT26**（含 NT26 PRO）。名额以 [NT26 资源](../dolua-api/nt26/resources/README.md) 为准。

---

## 目录

- [建议阅读顺序](#建议阅读顺序)
- [本分类文档](#本分类文档)
- [读完去哪里](#读完去哪里)
- [修订记录](#修订记录)

---

## 建议阅读顺序

1. [什么是 doLua](what.md) — 定位、语言、模块从哪来、和别的 Lua 不是一套
2. [doLua 是怎么运行的](runtime.md) — 上电选槽、虚拟机、入口协程、脚本生命周期
3. [消息和调度](schedule.md) — 协作式任务、事件队列、信箱/队列、回调纪律
4. [工程与脚本包](project.md) — 入口 / 用户模块如何进设备（侧边栏五区见开发助手）

还没装插件、没烧过第一份脚本：先看 [开始使用](../get-started/get-started.md)。

入门工程仍建议：`started/hello` → `started/log` → `started/task`，见 [示例索引](../../examples/nt26/README.md)。

---

## 本分类文档

| 文档 | 回答什么 |
| --- | --- |
| [what.md](what.md) | doLua 解决什么问题、脚本长什么样、能力从哪来 |
| [runtime.md](runtime.md) | 固件怎样把一份工程变成正在跑的虚拟机 |
| [schedule.md](schedule.md) | 多任务为什么不是抢占、消息怎么走、回调在哪执行 |
| [project.md](project.md) | 脚本包进设备：入口、用户模块、清单、部署 |

侧边栏怎么认工程、五区、LUAPK，只在 [工程结构](../dolua-assisant/project-structure.md) 写。NT26 的堆 / Flash / 调度名额在 [资源](../dolua-api/nt26/resources/README.md)。

---

## 读完去哪里

| 接下来要做的 | 去这里 |
| --- | --- |
| 查 NT26 配额、存哪一块 | [NT26 资源](../dolua-api/nt26/resources/README.md) |
| 查某个 `require("…")` | [NT26 API](../dolua-api/nt26/api/README.md) |
| 对原理图、选脚 | [硬件脚位](../dolua-api/nt26/hardware/README.md) |
| 用 AT 部署/查询脚本包 | [at/script.md](../dolua-api/nt26/at/script.md) |
| 抄一份能烧录的工程 | [examples/nt26](../../examples/nt26/README.md) |
| 看工程文件夹 / LUAPK | [工程结构](../dolua-assisant/project-structure.md) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-12 | 首版：doLua 核心分类入口 |
| 1.1.0 | 2026-09-12 | 索引标明当前未启用双槽切换 |
| 1.2.0 | 2026-09-13 | 链到开发助手「工程结构」（五区 / LUAPK） |
| 1.3.0 | 2026-09-16 | 链到「开始使用」 |
| 1.4.0 | 2026-09-18 | 抽出为跨型号分类；名额放到各型号「资源」 |
