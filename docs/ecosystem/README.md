# 生态

**文档版本** `1.0.0`

官方提供的开发入口都记在这一类。设备上的任务、让出、定时器、信箱和队列在固件里，见 [应用框架与调度](../dolua-core/schedule.md)。这里只写电脑和网页上的官方工具。新的入口会补进文首这张表。

| 入口 | 是什么 |
| --- | --- |
| [doLua 开发助手](#dolua-开发助手) | 装在 VS Code、Cursor、Trae 里的插件 |
| [在线编辑器](#在线编辑器) | 浏览器里打开工程、编辑、下载到设备 |
| [官网 Ask AI](#官网-ask-ai) | 文档站上的官方问答，按公开文档回答 |

---

## doLua 开发助手

编辑器插件。安装包在 [dolua.cn/plugins](https://dolua.cn/plugins)。装上之后，侧边栏用来建工程、划分主文件 / 模块 / 配置 / 内置文件，并把勾选的文件下载到设备。

第一次安装和第一份工程见 [开始使用](../get-started/get-started.md)。侧边栏的日常操作见 [开发工具](../get-started/tools.md)。工程文件夹、五区和 LUAPK 见 [工程结构](../dolua-assisant/project-structure.md)。

在 Cursor、VS Code 或 Trae 里启用 MCP 服务器 **doLua 开发助手** 之后，编辑器里的 Agent 可以在当前 Lua workspace 建工程、写脚本、做语法初筛。这是插件交给编辑器的能力，操作见 [配合编辑器的 Agent](../get-started/tools.md)。它和下面的官网 Ask AI 不是同一个入口。

## 在线编辑器

浏览器里的 **doLua 编辑器**，地址是 [dolua.cn/studio](https://dolua.cn/studio)。可以打开本机工程，编辑脚本，再下载到设备。不必先安装插件。

## 官网 Ask AI

打开 [dolua.cn](https://dolua.cn)，用页面上的 **Ask AI**。它按本站公开文档回答 doLua 的写法、接口和工具用法。

问设备脚本、接口怎么调用，用这个。问「帮我在当前工程里新建文件」，用上一节的编辑器 Agent。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-10-14 | 首版：开发助手插件、在线编辑器、官网 Ask AI |
