---
name: dolua
description: >-
  Guides writing DoLua / DoIoT Lua device scripts for NT26 (and NT26 PRO)
  modules: cooperative rt tasks, preloaded require modules (gpio uart mqtt
  http ufs ublob lp …), luaproj partitions, and official API/demo lookup.
  Use when the workspace is a DoLua project (doiot_lua_project.luaproj),
  when editing main.lua or device Lua, or when the user mentions DoLua,
  DoIoT, NT26, dolua, lua-demo, or dolua-api-docs.
---

# 这是 DoLua / DoIoT Lua 工程

当前对话处理的是 **DoLua（DoIoT Lua）设备脚本工程**，不是普通 Node/Web 项目。

**dolua** 是成都度云未来科技有限公司模组上的 Lua 运行时：外设、网络、存储、系统能力都以 `require("模块名")` 的形式提供给脚本。当前公开型号是 **NT26**（含 NT26 PRO）。语言是 **Lua 5.5**，但标准库之外的能力全部来自平台预加载模块，**不是** LuatOS / Air800 / NodeMCU / OpenWrt / 电脑端 Lua。

本 skill 教如何写、改、查设备脚本。不要凭通用 Lua 或其它模组手册编接口。

## 例程与 API（请到这里查，不要凭记忆编造）

- **优先**官方仓库（国内）：https://gitee.com/dolua/dolua-api-docs
- 同步镜像：https://github.com/dolua-big-egg/dolua-api-docs
- 内含 Lua API 文档和 Demo 例程。该仓库通常未被模型收录，需要细节时请抓取或打开上述地址。
- **不要使用已废弃的 data.doiot.cn 手册。**

工作区里若已有该仓库的克隆（例如 `dolua/docs`、`dolua/examples`），**先读本地文件**，再上网。

### 抓取顺序

1. 本地：`docs/NT26/api/README.md`、`examples/NT26/README.md`
2. Gitee raw（优先）：
   - `https://gitee.com/dolua/dolua-api-docs/raw/main/docs/NT26/api/README.md`
   - `https://gitee.com/dolua/dolua-api-docs/raw/main/examples/NT26/README.md`
   - 单篇：`https://gitee.com/dolua/dolua-api-docs/raw/main/docs/NT26/api/<dir>/<module>.md`
3. Gitee 失败再用 GitHub raw：
   - `https://raw.githubusercontent.com/dolua-big-egg/dolua-api-docs/main/docs/NT26/api/README.md`
   - 单篇：`https://raw.githubusercontent.com/dolua-big-egg/dolua-api-docs/main/docs/NT26/api/<dir>/<module>.md`

`<dir>` 只能是 `module` / `network` / `peripherals`。模块 → 路径对照见 [reference.md](reference.md)。

查完 API 后，**对照同页给出的示例目录**打开 `main.lua`，按可烧录工程抄写法。不要从零手写第一份脚本去试接口。

## 工程约定

- 工程标志文件：`doiot_lua_project.luaproj`
- 分区：主文件 main、模块 module、配置 config、内置文件系统 internal、其他 other
- 有 MCP 工具（`doiot_*`）时优先用工具改分区和文件，不要手改 luaproj。

当前插件 workspace：`d:\project\dolua-project`
当前插件 demo 目录：`C:\Users\33177\Documents\DoIoT\lua-demo`

以上两条是常见本机路径。若当前 Cursor 工作区不同，以实际打开的工程为准；官方可导入例程在文档仓的 `examples/NT26/`。

### `doiot_lua_project.luaproj` 字段

| 字段 | 含义 |
| --- | --- |
| `main` | 入口脚本，几乎总是 `main.lua` |
| `modules` | 自定义 `.lua` 模块文件名列表；**未登记的 `.lua` 打不进包，`require` 不到** |
| `configs` / `selectedConfig` | 配置分区，常见 `rtu_config.cfg` |
| `internal` | 内置文件系统（如 `manifest.json`） |
| `checked` | 工具勾选要打包的文件 |
| `othersOrder` | other 分区文件顺序 |

自定义模块：文件名去掉 `.lua` 即 `require` 名，文件末尾 `return` 一张表。见例程 `examples/NT26/started/module`。

平台模块（`gpio`、`rt`、`mqtt`…）**没有**对应的用户 `.lua`，不要去工程里找实现，也不要自己写一份同名文件去覆盖。

## 运行时模型（写脚本前必须建立的图景）

一台设备、**一个 Lua 虚拟机**、协作式多协程：

- 引擎把整份 `main.lua` 放进**一条入口协程**再跑。顶层可以直接 `rt.delay` / `lp.wait_link`，不必再包一层 `task_start`。
- `rt.task_start(fn)` 再开一条协程，立刻执行 `fn`；`fn` 一碰到 `rt.delay` / `mbox_recv` 等让出点，`task_start` 就返回。
- **同一时刻只有一条协程在跑。** 看起来像并行，其实是协作调度。两次让出之间的代码互斥，一般不用锁。漏写 `delay` 的死循环会饿死其它任务和回调。
- 入口协程 `return` 只结束自己；其它已启动任务仍会跑。全部协程结束且没有待处理事件时，脚本生命周期结束。所以长期业务要留一条 `while true do rt.delay(...) end`。
- GPIO / UART / MQTT 等「回调」**不在硬件中断里执行 Lua**。硬件只投递，真正调用发生在 Lua 调度循环。回调期间占用调度，必须短：投递 `rt.mbox_send` 后立刻返回。回调里不要 `rt.delay`、`mbox_recv`、同步 `pub` / `wait_connect`。
- 任务数量有上限（当前最多约 16 条，含入口协程第一次 delay 占用的那条）。`mbox` topic 最长 23 字节，超长截断会撞车。

`print(...)` 是 Lua 5.5 内置，本平台重定向到模块 UART（默认 UART1），**不是**电脑终端。`log.info` 带级别和调用点，可与 `print` 走不同串口（`print_route` / `log_route`，见配置 `[lua]` 或 `sys.option`）。

## 怎么写

### 推荐骨架（长期脚本）

```lua
local rt = require("rt")
local log = require("log")

local function worker()
    while true do
        local ok, ev = rt.mbox_recv("events")
        if ok then
            -- 业务只放工作协程
        end
    end
end

rt.task_start(worker)

while true do
    rt.delay(10000)
end
```

`started/hello` 可以更短：顶层 `while true do print("hello world"); rt.delay(1000) end`。

### 对象与冒号

`gpio.open` / `uart.open` / `mqtt.create` 一类返回带元表的 userdata。方法必须通过该对象调用：

```lua
led:set(true)        -- 正确
led.set(led, true)   -- 等价
led.set(true)        -- 错：缺对象
gpio.set(led, true)  -- 错：模块表上没有实例方法
```

### 边沿 / 串口回调（只投递）

先 `task_start` 再 `reg`，保证接收协程已经卡在 `mbox_recv` 上：

```lua
rt.task_start(function()
    while true do
        local ok, ev = rt.mbox_recv("gpio1")
        if ok then
            log.info("level=%s", ev.level)
        end
    end
end)

local din = gpio.open(gpio.INPUT_GPIO, 1)
din:config(false, false, gpio.PULL_UP)
din:reg(gpio.IRQ_BOTH, 20, function(gpio_id, pin_no, level, info)
    rt.mbox_send("gpio1", { gpio = gpio_id, pin_no = pin_no, level = level })
end)
```

完整注释与滤波语义见 `examples/NT26/peripherals/gpio/interrupt`。

### 网络

先读 `lp` / `mqtt` / `http` 当前文档。常见顺序：`lp.wait_link` → 拿 `info` 拼 client_id → `create`/`open` → `wait_connect`。长连接对象放到 chunk 级 local，防止被 GC。MQTT 回调里用 `pub_async`，不要同步 `pub`。

### 自定义 `.lua` 模块

1. 新建 `led.lua`，末尾 `return M`
2. 用 `doiot_*` 工具把文件登记进 **module** 分区（写入 luaproj 的 `modules`）
3. `local led = require("led")` —— 模块名 = 文件名去掉 `.lua`
4. 同一模块只加载一次

平台预加载名（`gpio`、`rt`…）不要再用同名 `.lua` 去抢。

### 布尔

走 Lua 布尔语义的参数（gpio `config`/`set` 等）里，**数字 `0` 为真**。电平、方向写 `true`/`false`。`seq`/`wave` 等文档标明整数 `0`/`1` 的，才用整数。不要混用。

### 读一篇 API 时看什么

每篇结构类似。不要只扫函数名：

1. 文首定位：这个模块干什么、不干什么
2. 框架结构 / 阻塞语义：会不会让出协程、会不会卡住整条引擎线程
3. 对象模型：纯函数还是 userdata、冒号怎么写
4. 常量与枚举：必须用 `gpio.PULL_UP` 这种符号，不要猜数字（有的模块故意不导出枚举）
5. 每个函数的**全部合法调用形态**（少参、多参各写一遍的那种）
6. 「错误与返回约定」：有的失败返回 `false`，有的抛错，有的 `ok, err`
7. 「资源上限与生命周期」：句柄、回调、VM 退出时是否收回
8. 文末例程路径：打开对应 `examples/NT26/.../main.lua`

文首 **文档版本** 只表示该篇 markdown 的修订，不是模组固件版本。

## 和别的东西不是同一套

| 容易当成的 | 实际 |
| --- | --- |
| Node / 浏览器 / 电脑 Lua | 设备上的单 VM 脚本，`print` 出 UART |
| LuatOS / Air800 / `sys.wait` / `sys.publish` | 另一家运行时，API 不能用 |
| 本仓库里的 C 绑定 / `lua-api/` 文档规范 | 那是固件作者写手册用的；本 skill 只写设备 Lua |
| POSIX `io.open` 内部盘 | 内部用 `ufs`/`ublob`，外挂 Flash 才是 `lfs` |
| 硬件 ISR 里跑 Lua | 回调在调度循环，有强制滤波 |

## 硬性禁止

- 不要用 `sys.delay_ms` / `sys.delay_until` 当日常等待：它们挂起**整条 Lua 引擎线程**，其它协程和心跳都停。日常用 `rt.delay`。`sys.delay_us` 是忙等，只给极短脚线时序。
- 不要在回调、`rt.tmr_*` 回调、MQTT `pre_connect`/`message` 里 `rt.delay` 或同步阻塞 API。
- 不要把 LuatOS / `sys.wait` / `sys.publish` / `cc.xxx` 等其它生态 API 写进本工程。
- 不要发明未在当前模块文档出现的函数、枚举名、返回值形状。
- 能用 `info` / `sys` / `dns` / `lp` 等 Lua API 办到的事，不要走 `virat`。
- `virat.exec` = 度云未来已注册 AT。`virat.ril_exec` = **原厂 EC 通道**：仅书面指导的特殊补充；乱发不予保修，模块会记录调用。不要拿同一条命令两边都试。调用前必须先读 virat 文档第 7 节。
- `ufs` 存可序列化 Lua 值（配置表）；`ublob` 只存 string、可 append/view。二者与**脚本区共用配额**（NT26 PRO 合计 220 KB，其它型号以文档第「共享配额」节为准）。不要当 POSIX 文件系统用。`http.save` 不能直接写 ufs。
- 不要手改 `doiot_lua_project.luaproj` 来增删分区文件——有 `doiot_*` MCP 时用工具。
- 不要在入口协程里写从不 `delay` 的死循环（会饿死其它任务）。
- 不要假设 `require("gpio")` 需要用户提供 `gpio.lua`。

## 接到任务时怎么做

1. 确认工作区有 `doiot_lua_project.luaproj`（或用户在写例程/文档仓里的 `examples/NT26/...`）。
2. 用 [reference.md](reference.md) 对上 `require` 名 → 打开对应 API markdown（Gitee 优先）。
3. 打开同页列出的示例工程 `main.lua`，抄调度、回调、对象生命周期，再改业务。
4. 写完自查：入口是否让出、回调是否只投递、对象是否被持有、布尔是否没用错 `0`、存储是否选对 ufs/ublob/lfs。

## 延伸

- 模块地图、选型、URL 模板：[reference.md](reference.md)
- 入门例程顺序：`started/hello` → `started/log` → `started/task` → 再进对应模块
