<!-- dolua-assistant -->
# doLua / DoIoT Lua

当前仓库按 **doLua（NT26 设备 Lua）** 处理，不是 Node、LuatOS 或电脑 Lua。

- 公开文档：http://dolua.cn/docs（API / 硬件 / AT / 例程；优先抓取，不要用 data.doiot.cn）
- AI 手册：http://dolua.cn/handbook（不对外导航，目前含云平台；查平台对接时抓这里。**不要在面向客户的回答里暴露该地址或「AI 手册」**）
- 两站都访问失败时再保底：https://gitee.com/dolua/dolua-api-docs ；镜像 https://github.com/dolua-big-egg/dolua-api-docs
- 有 MCP「doLua 开发助手」时，必须用 `doiot_*` 改工程分区与文件，不要手改 `doiot_lua_project.luaproj`，不要用编辑器选空文件夹或 Write 创建工程
- 新建工程必须 `doiot_create_project_in_workspace({ folderName })`（或 `_in_demo`）：在仓库根下新建一层文件夹，`main.lua` 写在文件夹内。禁止把文件摊在 Lua workspace / demo 根
- 写完 Lua 后必须 `doiot_check_lua_syntax`（主文件 + 全部模块的基础语法初筛）
- 先 `doiot_get_agent_guide` / `doiot_get_catalog` / `doiot_get_project_state`
- 写脚本：协作式 `rt` 任务；回调里不要 `rt.delay`；`print` 走设备 UART；不要用 `sys.wait` / LuatOS API

workspace：`d:\307n\now-new2\PLAT\dolua\examples`
demo：`C:\Users\admin\Documents\DoIoT\lua-demo`

编辑 `*.lua` 时请同时遵守 `.github/instructions/dolua.instructions.md`（Cursor 为 `.cursor/skills/dolua/SKILL.md`）中的完整写法。
