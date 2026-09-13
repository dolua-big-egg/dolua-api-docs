# dolua

**dolua** 是成都度云未来科技有限公司模组上的 Lua 运行时：外设、网络、存储、系统能力都以 `require("模块名")` 的形式提供给脚本。

本仓库是这份运行时的 **手册和示例**，不是固件本身。读文档、对照可烧录工程，即可在设备上验证接口。

当前公开型号：**NT26**（含 NT26 PRO）。

## 仓库结构

```
docs/NT26/core/          DoLua 核心（是什么、怎么跑、调度、资源上限）
docs/NT26/api/           模块 API（一篇文档对应一个 require）
docs/NT26/hardware/      全 IO / 封装脚位（按映射表分篇，不是 require）
docs/NT26/at/            应用 AT 指令（一篇一类业务，不是 require）
docs/dolua-assisant/     开发助手：工程文件夹、五区、LUAPK
examples/NT26/           可直接导入烧录的示例工程
```

| 你想… | 去这里 |
| --- | --- |
| 先建立整图：运行时、消息、配额 | [DoLua 核心](docs/NT26/core/README.md) |
| 工程文件夹、侧边栏五区、LUAPK | [工程结构](docs/dolua-assisant/工程结构.md) |
| 按模块查参数、返回值、失败约定 | [API 索引](docs/NT26/api/README.md) |
| 对原理图、查 PIN / 复用 | [NT26 硬件脚位](docs/NT26/hardware/README.md) |
| 查 `AT+` 指令 | [AT 索引](docs/NT26/at/README.md) |
| 找一份能跑的工程 | [示例索引](examples/NT26/README.md) |
| 本型号总入口 | [NT26 文档](docs/NT26/README.md) |

API 按主题放在 `peripherals` / `network` / `module`；示例按工程用途放在 `started` / `os` / `peripherals` / `network` / `storage` / `module` / `apps`。两边分类不完全相同，用上面的索引跳转即可。

## 建议阅读顺序

1. 读 [DoLua 核心](docs/NT26/core/README.md)：虚拟机、协作调度、RAM / Flash / 模块个数。
2. 建工程或看侧边栏分区时，对照 [工程结构](docs/dolua-assisant/工程结构.md)。
3. 用配套工具导入 [examples/NT26/started/hello](examples/NT26/started/hello)，确认能烧录、能看日志。
4. 再跑 `started/log`、`started/task`，熟悉日志和协作式任务。
5. 需要哪块能力，打开 [API 索引](docs/NT26/api/README.md) 对应模块，并对照同页给出的示例目录。

不要从零手写第一份脚本去「试接口」：示例工程已带 `main.lua`、`manifest.json` 和工程文件。

## 能力一览

细节以各模块文档为准，这里只帮你对号入座：

| 类别 | 典型模块 |
| --- | --- |
| 入门 / 运行时 | `log`、`rt`、`sys`、`info`、`script` |
| 外设 | `gpio`、`uart`、`spi`、`i2c`、`pwm`、`adc`、`lcd`、`lvgl` |
| 网络 | `tcp`、`http`、`mqtt`、`dns`、`ntp`、`sms` |
| 存储 | 内部文件、外挂 Flash（LittleFS / KV） |
| 协议与工具 | `json`、`hex`、`modbus`、`framekit`、`rtu` |

完整模块表见 [docs/NT26/api/README.md](docs/NT26/api/README.md)。

## 其它说明

- 每篇 API 文首的 **文档版本** 只表示该篇 markdown 的修订，不是模组固件版本。
- 许可证见 [LICENSE](LICENSE)（Apache-2.0）。
- 国内镜像（优先）：[Gitee](https://gitee.com/dolua/dolua-api-docs)；GitHub：[dolua-big-egg/dolua-api-docs](https://github.com/dolua-big-egg/dolua-api-docs)。
