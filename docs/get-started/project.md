# doLua 工程形态

**文档版本** `1.1.2`

本页是 [开始使用](get-started.md) 的续篇。侧边栏规则的全文见 [工程结构](../dolua-assisant/project-structure.md)；设备上这份包怎么跑见 [工程与脚本包](../dolua-core/project.md)。

[← 下载与云端](download.md) · [开发工具 →](tools.md)

---

## 目录

- [本地工程：仓库、文件夹、五区](#本地工程仓库文件夹五区)
- [打包格式：LUAPK](#打包格式luapk)

---

## 本地工程：仓库、文件夹、五区

**仓库 ≠ 工程。** workspace / demo 根是仓库；含 `doiot_lua_project.luaproj` 的那一层才是工程。

```
workspace/                      ← Lua workspace，不要在这里摊 main.lua
  hello/
    doiot_lua_project.luaproj
    main.lua
    rtu_config.cfg
  led_blink/
    ...
```

侧边栏上半「工程目录」多份工程，下半「工程文件」五区

| 分区 | 典型文件 | 进不进 LUAPK |
| --- | --- | --- |
| 主文件 | 只能 1 个，几乎总是 `main.lua` | 必须进，作为虚拟机入口 |
| 模块 | 你的 `.lua` | 已归入模块区的才进；未登记的设备上 `require` 不到 |
| 配置 | 如 `rtu_config.cfg`，可多份 | **只带当前选中的那一份**，烧录时以固定名写入设备 |
| 内置文件系统 | 图片、字库、清单等 | 已勾选且选了存储位置（`ufs` / `blob`）的才进，占内部共享配额 |
| 其他 | README、原理图 | **默认不进包、不烧录** |

`doiot_lua_project.luaproj` 是身份和分区账本（显示名、型号、主文件、模块列表、勾选等）。**不要手改这份 JSON** 来改分区或勾选，用侧边栏操作，否则界面可能把改动盖掉。

扫描规则：从上往下走文件夹树，某一层出现描述文件就记成一个工程，**不再进入它的子目录找工程**。因此不要在工程里面再套一份 `luaproj`。

用户模块三件事必须同时成立：

1. 文件在工程里，且登记在模块区。
2. `require` 的名字 = 文件名去掉 `.lua`。
3. 文件末尾 `return` 一张表。

```lua
-- led.lua（须登记为模块）
local M = {}
function M.on() end
return M

-- main.lua
local led = require("led")
led.on()
```

个数和名字长度有上限，见当前型号的 [资源](../dolua-api/nt26/resources/README.md)。不要用 `gpio`、`rt`、`mqtt` 这类平台名当用户文件名。

配置文件 **不是** Lua 模块，不能 `require("rtu_config")`。语法见 [rtu_config.cfg](../dolua-api/nt26/api/rtu_config/rtu_config.md)。

## 打包格式：LUAPK

**LUAPK**（Lua Update Package，扩展名 `.luapk`）是由当前工程生成的可烧录包。

包内会带：主文件、模块区 `.lua`、当前选中配置、已勾选且选了 `ufs`/`blob` 的内置文件。其他文件和 `doiot_lua_project.luaproj` 本身不进包。

设备侧大致是：收完整包 → 校验 → 解压写入脚本区（及配置、内置文件）→ 复位或按固件启动路径重建虚拟机。当前未启用双槽切换，不要按「写到空闲槽再试跑」规划发布。

一次能传多大、落盘后脚本和内部文件还能写多少、跑起来堆有多大，都随型号而变，不在本页列数字。当前公开型号 NT26 见 [资源 · 下载包体积](../dolua-api/nt26/resources/README.md#8-下载包体积)。

发布建议：

1. 本地跑通 `hello` / 业务工程。
2. 导出一份 `.luapk` 留底。
3. 产线用 USB DOWNLOAD 或 UART 工装下发；已部署设备用云端上传。
4. 用 `ATI`、脚本 AT 或 `require("script").info()` 核对版本。

导出本地 `.luapk` 文件

把 `.luapk` 拖进侧边栏还原工程

---

[← 下载与云端](download.md) · [开发工具 →](tools.md)
