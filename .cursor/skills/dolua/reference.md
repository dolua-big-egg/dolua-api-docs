# DoLua 模块地图与选型

需要某模块的参数、返回值、失败约定时，打开对应 markdown，不要凭记忆。本地路径相对文档仓根；网上用 Gitee raw，失败再用 GitHub raw。

**Gitee 前缀**（优先）

```
https://gitee.com/dolua/dolua-api-docs/raw/main/
```

**GitHub 前缀**

```
https://raw.githubusercontent.com/dolua-big-egg/dolua-api-docs/main/
```

拼路径：`docs/NT26/api/<dir>/<file>.md` 或 `examples/NT26/<category>/...`。

索引：

| | 本地 | Gitee raw |
| --- | --- | --- |
| API 索引 | `docs/NT26/api/README.md` | `.../docs/NT26/api/README.md` |
| 示例索引 | `examples/NT26/README.md` | `.../examples/NT26/README.md` |
| 型号入口 | `docs/NT26/README.md` | `.../docs/NT26/README.md` |

API 按 `peripherals` / `network` / `module` 分目录；示例按 `started` / `os` / `peripherals` / `network` / `storage` / `module`。两边分类不完全相同。

---

## 1. 外设 `docs/NT26/api/peripherals/`

| require | 文档 | 对照例程（`examples/NT26/`） |
| --- | --- | --- |
| `gpio` | `peripherals/gpio.md` | `peripherals/gpio/normal`、`interrupt`、`io_task`；入门 `started/led` |
| `uart` | `peripherals/uart.md` | `peripherals/uart/uart_normal`、`uart_block` |
| `spi` | `peripherals/spi.md` | `peripherals/spi/spi_api`、`spi_lcd`、`spi_st7789` |
| `i2c` | `peripherals/i2c.md` | `peripherals/iic/iic_aht20` |
| `soft_i2c` | `peripherals/soft_i2c.md` | `peripherals/iic/soft_iic_aht20` |
| `pwm` | `peripherals/pwm.md` | `peripherals/pwm/pins`、`timer`、`apwm`、`timer_mhz`、`timer_comp` |
| `adc` | `peripherals/adc.md` | 文档内示例 |
| `charge` | `peripherals/charge.md` | `module/charge/charge_api` |

`gpio` 要点：`open` 返回 userdata；边沿 `reg` 全带消抖（没有零滤波模式）；`seq` 同步占着调用栈翻转，`wave` 交给独立 IO 任务。边沿回调只 `mbox_send`。布尔电平不要传数字 `0`（`0` 会被当成真/高）。

---

## 2. 网络 `docs/NT26/api/network/`

| require | 文档 | 对照例程 |
| --- | --- | --- |
| `tcp` | `network/tcp.md` | `network/tcp/tcp_api`、`tcp_cmd` |
| `http` | `network/http.md` | `network/http/http_request`、`https`、`http_file_ublob`、`http_file_lfs` |
| `mqtt` | `network/mqtt.md` | `network/mqtt/mqtt_client`、`mqtt_cmd` |
| `dns` | `network/dns.md` | `network/dns/dns_api` |
| `ntp` | `network/ntp.md` | `network/ntp/ntp_api` |
| `lbs` | `network/lbs.md` | `network/lbs/lbs_api` |
| `rndis` | `network/rndis.md` | `network/rndis/rndis_api` |
| `wifiscan` | `network/wifiscan.md` | `network/wifiscan/wifiscan_api` |

短信在 `module/`：`sms` → `module/sms.md`，例程 `network/sms/sms_api`、`sms_cmd`。

MQTT：客户端对象必须长期持有。回调里只能 `pub_async` 一类立刻返回的接口，不要 `pub` / `wait_connect` / `rt.delay`。`pre_connect` 可改三元组，同样禁止阻塞。可先 `lp.wait_link`，也可直接 `open` 让内部等网重连——以当前文档和例程为准。

HTTP 落内部盘走 `ublob`（或外挂 `lfs`），不要 `http.save` 进 `ufs`。

---

## 3. 模块 `docs/NT26/api/module/`（运行时 / 存储 / 协议）

| require | 文档 | 对照例程 |
| --- | --- | --- |
| `rt` | `module/rt.md` | `os/rt/task_delay`、`mbox_uart`、`mq_api`、`tmr_api`；入门 `started/task` |
| `sys` | `module/sys.md` | `os/sys/sys_api`、`sys_cmd` |
| `script` | `module/script.md` | `os/script/script_api` |
| `log` | `module/log.md` | `started/log` |
| `info` | `module/info.md` | `module/info/info_api`、`started/info` |
| `lp` | `module/lp.md` | `module/lp/lowpower_api`、`lowpower_vote`、`lowpower_cron` |
| `cron` | `module/cron.md` | `module/lp/lowpower_cron` |
| `ufs` | `module/ufs.md` | `storage/ufs/ufs_api`、`ufs_cmd` |
| `ublob` | `module/ublob.md` | `storage/ublob/ublob_api`、`ublob_cmd` |
| `sfud` | `module/sfud.md` | `storage/flashdb_kv` 等外挂盘 |
| `flashdb` | `module/flashdb.md` | `storage/flashdb_kv`、`flashdb_ts`、`mix` |
| `lfs` | `module/lfs.md` | `storage/littlefs`、`mix` |
| `lcd` | `module/lcd.md` | `peripherals/spi/spi_lcd`、`spi_st7789` |
| `lvgl` | `module/lvgl.md` | `module/lvgl/lvgl_demo` |
| `json` | `module/json.md` | `module/json/json_api` |
| `hex` | `module/hex.md` | `module/hex/hex_api` |
| `tls` | `module/tls.md` | `module/tls/tls_api` |
| `random` | `module/random.md` | `module/random/random_api` |
| `dream` | `module/dream.md` | `module/dream/dream_api` |
| `framekit` | `module/framekit.md` | `module/framekit/framekit_cmd` |
| `modbus` | `module/modbus.md` | `module/modbus/modbus_api`、`modbus_rs485` |
| `rtu` | `module/rtu.md` | `module/rtu/rtu_api`、`rtu_cmd` |
| `virat` | `module/virat.md` | `module/virt/virt_api` |
| `sms` | `module/sms.md` | `network/sms/sms_api`、`sms_cmd` |

平台还预加载 `oneos` 等未出现在公开 API 索引里的名字。公开脚本不要用未文档化模块。

---

## 4. 选型（先选对模块，再打开文档）

### 等待 / 延时

| 需求 | 用 | 不要 |
| --- | --- | --- |
| 任务休眠、让出调度 | `rt.delay(ms)` | `sys.delay_ms` 当循环等待 |
| 必须尽快到点、不准别的协程插队 | `sys.delay_ms` / `delay_until`（读 sys 文档第 3 节） | 在回调里用 |
| 几十微秒脚线间隔 | `sys.delay_us` | 用它睡毫秒以上 |

`rt.delay(0)` 或非法参数不让出。`rt.delay(-1)` 无限让出当前协程。

### 存储

| 需求 | 用 |
| --- | --- |
| 配置表、短状态、可序列化 Lua 值 | `ufs`（整值覆盖，读回是对象） |
| 二进制、日志块、HTTP body、可 append | `ublob`（只要 string；`open` 视图省 Lua 堆） |
| 外挂 Flash 文件树 | `lfs`（LittleFS，经 `sfud`） |
| 外挂 KV / 时序 | `flashdb` |

`ufs` 与 `ublob` 命名空间独立：同名各存一份，彼此 `list`/`read` 看不见。二者与 Lua **脚本区共用配额**，总额按型号（NT26 PRO 为 220 KB）。多个配置字段打成一张表一次 `ufs.write`，不要拆成很多小文件。

### AT

| 需求 | 用 |
| --- | --- |
| 度云未来已注册应用层 AT | `virat.exec` |
| 原厂 EC 指令（仅特殊补充） | `virat.ril_exec`，先读文档第 7 节严重警告 |
| IMEI、驻网、DNS 等已有 Lua API | `info` / `lp` / `dns` / `sys`，不要 virat |

`exec` 与 `ril_exec` 不是同一个解析器，命令集不通，不要两边都试。

### 彩屏

| 需求 | 用 |
| --- | --- |
| 验证 SPI 出纯色 / 色块 | `lcd`（`full` / `fill`），尚未 `lvgl.create` |
| 标签、按钮、主题 | `lvgl`（先 `lcd.new` 再 `create`） |
| create 之后填色 | `ui:set_bg` / 样式，不要 `panel:full` |

### GPIO 动作

| 需求 | 用 |
| --- | --- |
| 指示灯、心跳灯（不阻塞脚本） | `wave_*` |
| 调用栈上同步翻转一段波形 | `seq` |
| 按键 / 插拔 / 开关量 | `reg`（强制消抖，回调只投递） |

不是实时中断里跑 Lua，微秒级脉冲和精确脉宽不要用 `reg`。

---

## 5. 入门例程

多模块场景工程在 `examples/NT26/apps/<分类>/`（协议打包、透传、云上报等）。分类索引：`examples/NT26/apps/README.md`。查单个 `require` 的接口仍用下面的 `started` / 各模块 `*_api`。

`examples/NT26/started/`：

| 工程 | 先看什么 |
| --- | --- |
| `hello` | 最小循环：`print` + `rt.delay`；确认串口 |
| `log` | `log.info` 格式化 |
| `task` | `task_start` + 入口协程并列 |
| `led` | gpio 输出 |
| `info` | 读本机信息 |
| `module` | 自定义 `led.lua` 登记进 `modules` 再 `require` |

---

## 6. 工程文件备忘

标志：`doiot_lua_project.luaproj`。分区：main / module / config / internal / other。

有 `doiot_*` MCP 时用工具改分区和文件，不要手改 luaproj。

配置常见 `rtu_config.cfg`（开机解析 `/rtu_config.cfg`，**不是** `require` 模块）。完整语法、每个 key、总覆盖权与联合影响：

- 本地：`docs/NT26/api/rtu_config/rtu_config.md`
- Gitee raw：`.../docs/NT26/api/rtu_config/rtu_config.md`

最小 Lua 工程通常只需：

```
[lua]
print_route=1
log_route=1
```

改 UART 脚/分包、关 NET 灯、配 DTU 四路、占位符总闸，都写这份文件，不要在脚本里猜。`[script.N]` 当前不会被解析。

`manifest.json` 是例程元数据（id、requires.libs 等），给工具展示用；运行时入口仍是 `main.lua`。

典型插件路径（以当前工作区为准）：

- workspace：`d:\project\dolua-project`
- demo：`C:\Users\33177\Documents\DoIoT\lua-demo`
