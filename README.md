# dolua

度云未来科技有限公司推出的 **dolua** 库 API 文档与可烧录示例。按型号分目录，当前公开 **NT26**。

| | 入口 |
| --- | --- |
| 文档 | [docs/NT26](docs/NT26/README.md) |
| 模块 API | [docs/NT26/api](docs/NT26/api/README.md) |
| 示例 | [examples/NT26](examples/NT26/README.md) |

建议先跑 [examples/NT26/started/hello](examples/NT26/started/hello)，再按模块对照 API。

文档里的 `文档版本` 只表示该篇 markdown 的修订，不是固件版本。NT26 PRO 上 Lua 脚本、`ufs`、`ublob` 共用一块内部配额（合计 220 KB），细节见 [ufs](docs/NT26/api/module/ufs.md) / [ublob](docs/NT26/api/module/ublob.md)。
