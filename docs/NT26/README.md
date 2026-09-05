# NT26 文档

本型号的 Lua API 与示例入口。文档按主题分在 `api/module`、`api/network`、`api/peripherals`、`api/rtu_config`；硬件全 IO 在 `hardware/`；应用 AT 在 `at/`；示例按工程用途分在 `examples/NT26` 的 `started` / `os` / `peripherals` / `network` / `storage` / `module` / `apps`。分类不必一一对应，用下面的索引跳转即可。

| | 路径 |
| --- | --- |
| 模块 API 索引 | [api/README.md](api/README.md) |
| 全 IO / 封装脚位 | [hardware/README.md](hardware/README.md) |
| 应用 AT 指令 | [at/README.md](at/README.md) |
| `rtu_config.cfg` 语法 | [api/rtu_config/rtu_config.md](api/rtu_config/rtu_config.md) |
| 示例索引 | [../../examples/NT26/README.md](../../examples/NT26/README.md) |
| 入门工程 | [../../examples/NT26/started](../../examples/NT26/started) |
| 应用场景分类 | [../../examples/NT26/apps](../../examples/NT26/apps) |

入门建议顺序：`started/hello` → `started/log` → `started/task` → 再进对应模块的 API。
