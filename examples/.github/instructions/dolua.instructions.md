---
name: dolua
description: doLua NT26 设备 Lua 写法与官方 API 查阅
applyTo: "**/*.{lua,cfg,luaproj}"
---

<!-- dolua-assistant -->

# doLua 插件 skill 入口

完整写法在网页上。写、改、查设备脚本之前，先调用：

`dolua_fetch_docs({ url: "http://dolua.cn/skill/plugin.md" })`

按抓回来的正文做。正文里的文档链接继续用 `dolua_fetch_docs` 打开。网页若仍写 `doiot_*`，调用时把前缀换成 `dolua_`（例如 `doiot_write_file` → `dolua_write_file`）。工程标志文件名仍是 `doiot_lua_project.luaproj`。不要用编辑器自带的网页抓取。不要把抓到的全文贴给用户。

当前插件 **Lua workspace**（工程仓库根，不是单个工程）：`d:\307n\now-new2\PLAT\dolua\examples`
当前插件 demo 目录：`C:\Users\admin\Documents\DoIoT\lua-demo`

这两条路径只在本地。网页 skill 里的 `<workspace>`、`<demo>` 就是这两行。

**列表里没有 `dolua_*`：** 立刻停。Cursor 打开 Customize → MCPs，范围选 User，启用 **dolua-assistant**，然后新开一轮对话。其它编辑器用命令面板 `MCP: List Servers`。不要搜仓库，不要用 Write 写 `main.lua`。
