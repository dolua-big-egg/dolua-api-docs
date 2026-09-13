# NT26 文档

本型号的文档入口。先读 **DoLua 核心**（是什么、怎么跑、消息与调度、资源上限），再按模块查 API。硬件全 IO 在 `hardware/`；应用 AT 在 `at/`；示例按工程用途分在 `examples/nt26` 的 `started` / `os` / `peripherals` / `network` / `storage` / `module` / `apps`。分类不必一一对应，用下面的索引跳转即可。

| | 路径 |
| --- | --- |
| **DoLua 核心**（运行机制、调度、资源） | [core/README.md](core/README.md) |
| 工程文件夹 / 五区 / LUAPK | [../dolua-assisant/工程结构.md](../dolua-assisant/工程结构.md) |
| 模块 API 索引 | [api/README.md](api/README.md) |
| 全 IO / 封装脚位 | [hardware/README.md](hardware/README.md) |
| 应用 AT 指令 | [at/README.md](at/README.md) |
| `rtu_config.cfg` 语法 | [api/rtu_config/rtu_config.md](api/rtu_config/rtu_config.md) |
| 示例索引 | [../../examples/nt26/README.md](../../examples/nt26/README.md) |
| 入门工程 | [../../examples/nt26/started](../../examples/nt26/started) |
| 应用场景分类 | [../../examples/nt26/apps](../../examples/nt26/apps) |

阅读顺序： [核心分类](core/README.md) → [工程结构](../dolua-assisant/工程结构.md) → `started/hello` → `started/log` → `started/task` → 再进对应模块的 API。
