# dolua

**dolua** 是成都度云未来科技有限公司模组上的 Lua 运行时：外设、网络、存储、系统能力都以 `require("模块名")` 的形式提供给脚本。

本仓库是这份运行时的 **手册和示例**，不是固件本身。读文档、对照可烧录工程，即可在设备上验证接口。

当前公开型号：**NT26**（含 NT26 PRO）。

## 仓库结构

```
docs/NT26/api/     模块 API（一篇文档对应一个 require）
examples/NT26/     可直接导入烧录的示例工程
```

| 你想… | 去这里 |
| --- | --- |
| 按模块查参数、返回值、失败约定 | [API 索引](docs/NT26/api/README.md) |
| 找一份能跑的工程 | [示例索引](examples/NT26/README.md) |
| 本型号总入口 | [NT26 文档](docs/NT26/README.md) |

API 按主题放在 `peripherals` / `network` / `module`；示例按工程用途放在 `started` / `os` / `peripherals` / `network` / `storage` / `module`。两边分类不完全相同，用上面的索引跳转即可。

## 建议阅读顺序

1. 用配套工具导入 [examples/NT26/started/hello](examples/NT26/started/hello)，确认能烧录、能看日志。
2. 再跑 `started/log`、`started/task`，熟悉日志和协作式任务。
3. 需要哪块能力，打开 [API 索引](docs/NT26/api/README.md) 对应模块，并对照同页给出的示例目录。

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
