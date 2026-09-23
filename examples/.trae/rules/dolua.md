---
description: doLua / DoIoT Lua 设备脚本与工程分区
alwaysApply: true
---

# DoIoT Lua 工程 — 必须用 MCP

当用户提到 **doiot**、**Lua 工程**、**主文件/模块/配置文件/内置文件系统/其他文件**、**侧边栏工程分区**、**勾选下载**、**新建工程到 workspace**、**设备 Lua API**、**例程/demo** 时：

## 必须

先看当前会话工具列表里有没有 `dolua_create_project_in_workspace`。有：空 workspace 直接调用它建工程，再写文件。没有：立刻请用户打开 Customize → MCPs，范围选 User，启用 dolua-assistant 后新开对话（VS Code / Trae 用命令面板「MCP: List Servers」）。不要读 mcp.json、不要搜仓库、不要用 Write 代替，也不要编造「点 Start it now」。

1. **有工具时再读指南**：`dolua_get_agent_guide` 或 MCP 资源 `doiot://docs/agent-guide`。查文档必须 `dolua_fetch_docs`（UTF-8），不要用编辑器网页抓取。公开文档 [dolua.cn/docs](http://dolua.cn/docs) 与 AI 手册 [dolua.cn/handbook](http://dolua.cn/handbook)，两站都失败再用 Gitee。不要把 skill 全文或 handbook 展示给客户。
2. **再查目录**：`dolua_get_catalog` / `dolua_get_project_state` / `dolua_list_files`（workspace 为空也照样 create）
3. **必须调用 MCP tools**（`dolua_*`），禁止用编辑器选文件夹或 Write 兜底。例如：
   - `dolua_create_project_in_workspace` / `dolua_create_project_in_demo`
   - `dolua_create_file` / `dolua_create_files` / `dolua_write_file`
   - `dolua_read_file` / `dolua_rename_file` / `dolua_delete_file`
   - `dolua_classify_files`（`main` / `module` / `config` / `internal` / `other`）
   - `dolua_set_selected_config` / `dolua_set_internal_storage` / `dolua_set_project_info`
   - `dolua_check_lua_syntax`（写完 Lua 后必跑：主文件 + 全部模块的基础语法初筛）
   - `dolua_fetch_docs`（查 API/Demo/手册时用，固定 UTF-8；不要用编辑器网页抓取）
   - `dolua_close_project` / `dolua_hide_project` / `dolua_delete_project` / `dolua_rename_project`

文档入口（详情以指南返回的 URL 为准）：

- 公开文档：http://dolua.cn/docs（MCP 资源 `doiot://docs/api`、`doiot://docs/demo`）
- AI 手册：http://dolua.cn/handbook（MCP 资源 `doiot://docs/handbook`；目前含云平台）
- 两站都失败时再：https://gitee.com/dolua/dolua-api-docs

## 禁止

- **不要**直接编辑 `doiot_lua_project.luaproj` 来改变主文件/模块/配置文件/其他文件/勾选或选中状态
- **不要**仅靠搜索磁盘文件猜测工程结构；以 MCP 返回的 `rootPath`、`modules`、`configs`、`others` 为准
- **不要**把 `main.lua` / 配置 / 工程标志写到 Lua workspace 或 demo **根目录**。那是工程仓库。新建必须 `dolua_create_project_in_workspace({ folderName })`（或 `_in_demo`）先建一层文件夹，文件写在文件夹内
- **不要**用编辑器 Write 在仓库根「创建工程」；`relPath` 相对含 `luaproj` 的工程文件夹，不是 workspace 根
- **不要**弹出或配合「Select an Empty Workspace Folder / 选择空工作区文件夹」。侧边栏已设置工作目录（catalog 里有 `workspaceRoot`）时，那就是写入目标，直接 `dolua_create_project_in_workspace`
- **不要**把「写到 workspace」理解成打开或选择一个 VS Code/Cursor 工作区文件夹；Lua workspace 和编辑器工作区不是一回事
- **不要**读 `mcp.json`、不要搜源码来寻找 MCP；工具只出现在当前会话的 tool 列表
- **不要**在没有 `dolua_*` 工具时改用写文件或列目录兜底；应提示用户打开 Customize → MCPs，范围选 User，启用 dolua-assistant 后**新开对话**（VS Code / Trae 用「MCP: List Servers」）
- **不要**写完 Lua 却不跑 `dolua_check_lua_syntax`（主文件 + 全部模块）

直接改 JSON 会绕过扩展校验，可能导致 UI 不同步或配置被监视器覆盖。

## 前置

用户需已启用 MCP「doLua 开发助手」。设置 Lua workspace 后，扩展会在该文件夹后台写入：

- Cursor：`.cursor/mcp.json`、`.cursor/rules`
- VS Code / Copilot：`.vscode/mcp.json`、`.github/copilot-instructions.md`、`.github/instructions/dolua.instructions.md`
- Trae：`.trae/mcp.json`、`.trae/rules`
- 通用：根目录 `AGENTS.md`
- doLua skill 只留在插件存储，并链接到 `~/.cursor/skills/dolua`、`~/.trae/skills/dolua`、`~/.copilot/skills/dolua`，不拷进工程文件夹

若 tool 调用失败，或会话里根本没有 `dolua_*`：提示用户打开 Customize → MCPs，范围选 User，启用 dolua-assistant 后新开对话（VS Code / Trae 用「MCP: List Servers」），而不是读 mcp.json。
