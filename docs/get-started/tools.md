# 开发工具使用指南

**文档版本** `1.1.0`

本页是 [开始使用](get-started.md) 的续篇，讲 doLua 开发助手侧边栏的日常操作。安装与第一份工程见入门页；下载口细节见 [下载与云端](download.md)。

[← 工程形态](project.md) · [调度导读 →](schedule.md)

---

## 目录

- [工作目录](#工作目录)
- [工程日常操作](#工程日常操作)
  - [创建工程](#创建工程)
  - [增加文件](#增加文件)
  - [移动文件](#移动文件)
  - [文件转工程](#文件转工程)
  - [例程中心](#例程中心)
  - [下载](#下载)
  - [打包与导出](#打包与导出)
  - [配合编辑器的 Agent](#配合编辑器的agent)
- [常用注意](#常用注意)

---

## 工作目录

| 目录 | 建议放什么 |
| --- | --- |
| Lua workspace | 你自己的业务工程 |
| demo | 官方例程、临时试验 |
| 其它 | 只浏览、不默认写入的目录 |

注意一定要被选中的文件才会被下载哦，如果一个文件暂时不需要下载，可以先不勾选。

![checked-files](img/checked-files.png)

## 工程日常操作

### 创建工程

可以直接在文件按钮创建工程，这个时候会弹出文件确认框让你选择落脚的位置，你可以放在任何地方，但是如果放在 workspace 路径之外，目录树中便不会显示。

![new-project-1](img/new-project-1.png)

第二个方式是点击总目录右键来创建，比如点击 `workspace`，或者`demo`，则创建的工程就会在点击的区域的路径下。

![new-project-2](img/new-project-2.png)

直接选中已有工程，在其同级位置新建工程。你可能会好奇这和上一种方式有什么差异 —— 该方式虽然是在根目录下创建工程，但支持树形目录结构，便于在目标工程的同一目录下完成新建操作。

![new-project-3](img/new-project-3.png)

### 增加文件

你如果直接点击工程右键，会发现没有新建文件的地方，因为那是工程目录，新建文件得在`工程文件`区进行。

注意一点，主文件区只能创建主文件，模块区也只能创建模块，这是一个规则，配置文件区也只能存放配置文件，所以对应栏的右键快捷键都是直接适配成对应文件。

![new-in-zone](img/new-in-zone.png)

![new-module](img/new-module.png)

但是内置文件系统和其他文件区则可以新建任意文件

![new-other](img/new-other.png)

也可以直接拖动文件，放到工程文件中，则文件会先自动放到其他文件中

![drag-in-file](img/drag-in-file.png)

![dropped-to-other](img/dropped-to-other.png)

### 移动文件

右键文件，则可以移动到对应的分区

![move-zone](img/move-zone.png)

因为有规则限制，有些移动必须是指定后缀的，比如一定得 `.lua` 的移动，才有移动到模块和主文件的选项。

![to-module](img/to-module.png)

### 文件转工程

这里讲的是，如果你有一份代码，要怎么把他变成工程，很简单，你只需要构建工程信息，先在工作目录下新建一个文件夹，把文件夹名字改成你要的工程名，比如这里是`my-project`，然后在里面放入你的代码，有什么就放什么，只有main 也行。

![make-project-folder](img/make-project-folder.png)

此时目录树下还无法显示该文件夹。

![hidden-folder](img/hidden-folder.png)

此时需要打开对没有工程描述文件的文件夹的显示

![show-folders](img/show-folders.png)

当打开显示后，可以看到这个文件夹了，右键他，构建工程描述文件

![create-luaproj](img/create-luaproj.png)

此时他在目录树中，就由文件夹转变成了工程

![folder-as-project](img/folder-as-project.png)

### 例程中心

不要从零手写第一份脚本去试接口，直接 **一键下载** 不同的 demo 来测试功能，可以用搜索功能来搜索例程哦。

![demo-center](img/demo-center.png)

### 下载

选对你的端口，然后点击下载按钮即可，如果用了USB链接，优先使用USB下载，其次使用串口下载，注意这里演示的 SERIAL-A 是我们的开发板枚举出来的名字，如果你用自己的串口助手链接模块，则使用对应的能通过 AT 指令 ping 通的端口即可。

![download-port](img/download-port.png)

![download-run](img/download-run.png)

### 打包与导出

选中工程后点击导出，即可导出 `.luapk` 这个是可以直接给设备下载的固件，也可以拖动到工程目录进行还原。注意打包文件只会打包选中的文件，也就是`工程文件`中没有被选中的文件不会参与打包到`.luapk`。

![export-project](img/export-project.png)

### 配合编辑器的Agent

在 Cursor / VS Code / Trae 里启用 MCP 服务器 **doLua 开发助手** 后，对话里的助手可以直接在 **当前 Lua workspace** 里建工程、写 `main.lua`、登记模块、做语法初筛。

刚装好或者升级的插件，可以注册一次 MCP ，之后就不需要再注册

![mcp-register](img/mcp-register.png)

![mcp-refresh](img/mcp-refresh.png)

引用我们的 skill

![use-skill](img/use-skill.png)

写个简单的需求试试，这里没有详细的描述，让 AI 自由发挥

![ask-ai](img/ask-ai.png)

等待一段时间后，AI输出如下

![ai-done](img/ai-done.png)

## 常用注意

- 改完 Lua 后，以设备上跑起来的为准；电脑上能打开的 `.lua` 若没进模块区或者未勾选，设备 `require` 会失败。
- 不要把平台模块实现成同名用户文件，比如你自己新建的模块不要叫 `gpio`。
- 布尔参数写真 / 假。走布尔语义的接口里，**数字 `0` 往往是「真」**这是lua语法。
- 接外部硬件先读 [硬件脚位](../nt26/hardware/README.md)，再打开当前产品那一篇（NT26-PRO 为 [pro.md](../nt26/hardware/pro.md)）。
- 日常等待用 `rt.delay`。不要用 `sys.delay_ms` 当循环延时。

---

[← 工程形态](project.md) · [调度导读 →](schedule.md)
