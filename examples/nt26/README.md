# NT26 示例

每个子目录是一份可直接打开的 Lua 工程（`main.lua`、`manifest.json`、`.luaproj`）。用配套工具导入该目录即可烧录。先建立运行时整图请读 [doLua 核心](../../docs/dolua-core/README.md)；NT26 名额见 [资源](../../docs/dolua-api/nt26/resources/README.md)；工程文件夹和 LUAPK 见 [工程结构](../../docs/dolua-assisant/project-structure.md)；API 说明在 [docs/dolua-api/nt26/api](../../docs/dolua-api/nt26/api/README.md)。

先从 `started/` 跑通：打印、日志、任务。再按外设 / 网络 / 存储选工程。多模块场景工程放 [apps](apps/README.md)。

## started — 入门

| 工程 | 说明 | API |
| --- | --- | --- |
| [hello](started/hello) | 最小脚本 | — |
| [log](started/log) | 日志 | [log](../../docs/dolua-api/nt26/api/module/log.md) |
| [task](started/task) | 多任务 | [rt](../../docs/dolua-api/nt26/api/module/rt.md) |
| [led](started/led) | 指示灯 | [gpio](../../docs/dolua-api/nt26/api/peripherals/gpio.md) |
| [info](started/info) | 读本机信息 | [info](../../docs/dolua-api/nt26/api/module/info.md) |
| [module](started/module) | 模块一览 | — |

## os — 运行时

| 工程 | API |
| --- | --- |
| [rt/task_delay](os/rt/task_delay)、[mbox_uart](os/rt/mbox_uart)、[mq_api](os/rt/mq_api)、[tmr_api](os/rt/tmr_api) | [rt](../../docs/dolua-api/nt26/api/module/rt.md) |
| [sys/sys_api](os/sys/sys_api)、[sys_cmd](os/sys/sys_cmd) | [sys](../../docs/dolua-api/nt26/api/module/sys.md) |
| [script/script_api](os/script/script_api) | [script](../../docs/dolua-api/nt26/api/module/script.md) |

## peripherals — 外设

| 工程 | API |
| --- | --- |
| [gpio/normal](peripherals/gpio/normal)、[interrupt](peripherals/gpio/interrupt)、[io_task](peripherals/gpio/io_task) | [gpio](../../docs/dolua-api/nt26/api/peripherals/gpio.md) |
| [uart/uart_normal](peripherals/uart/uart_normal)、[uart_block](peripherals/uart/uart_block) | [uart](../../docs/dolua-api/nt26/api/peripherals/uart.md) |
| [spi/spi_api](peripherals/spi/spi_api)、[spi_lcd](peripherals/spi/spi_lcd)、[spi_lcd_cfg](peripherals/spi/spi_lcd_cfg)、[spi_st7789](peripherals/spi/spi_st7789) | [spi](../../docs/dolua-api/nt26/api/peripherals/spi.md)、[lcd](../../docs/dolua-api/nt26/api/module/lcd.md) |
| [iic/iic_aht20](peripherals/iic/iic_aht20) | [i2c](../../docs/dolua-api/nt26/api/peripherals/i2c.md) |
| [iic/iic_ssd1306](peripherals/iic/iic_ssd1306) | [i2c](../../docs/dolua-api/nt26/api/peripherals/i2c.md)（纯 Lua SSD1306，不用 lcd） |
| [iic/soft_iic_aht20](peripherals/iic/soft_iic_aht20) | [soft_i2c](../../docs/dolua-api/nt26/api/peripherals/soft_i2c.md) |
| [pwm/…](peripherals/pwm) | [pwm](../../docs/dolua-api/nt26/api/peripherals/pwm.md) |

## network — 网络

| 工程 | API |
| --- | --- |
| [tcp](network/tcp) | [tcp](../../docs/dolua-api/nt26/api/network/tcp.md) |
| [http](network/http) | [http](../../docs/dolua-api/nt26/api/network/http.md) |
| [mqtt](network/mqtt) | [mqtt](../../docs/dolua-api/nt26/api/network/mqtt.md) |
| [dns](network/dns) | [dns](../../docs/dolua-api/nt26/api/network/dns.md) |
| [ntp](network/ntp) | [ntp](../../docs/dolua-api/nt26/api/network/ntp.md) |
| [lbs](network/lbs) | [lbs](../../docs/dolua-api/nt26/api/network/lbs.md) |
| [sms](network/sms) | [sms](../../docs/dolua-api/nt26/api/module/sms.md) |
| [rndis](network/rndis) | [rndis](../../docs/dolua-api/nt26/api/network/rndis.md) |
| [wifiscan](network/wifiscan) | [wifiscan](../../docs/dolua-api/nt26/api/network/wifiscan.md) |

## storage — 存储

| 工程 | API |
| --- | --- |
| [ufs](storage/ufs) | [ufs](../../docs/dolua-api/nt26/api/module/ufs.md) |
| [ublob](storage/ublob) | [ublob](../../docs/dolua-api/nt26/api/module/ublob.md) |
| [flashdb_kv](storage/flashdb_kv)、[flashdb_ts](storage/flashdb_ts) | [flashdb](../../docs/dolua-api/nt26/api/module/flashdb.md)、[sfud](../../docs/dolua-api/nt26/api/module/sfud.md) |
| [littlefs](storage/littlefs) | [lfs](../../docs/dolua-api/nt26/api/module/lfs.md) |
| [mix](storage/mix) | flashdb + lfs 同芯片 |

## module — 其它模块

| 工程 | API |
| --- | --- |
| [json](module/json) | [json](../../docs/dolua-api/nt26/api/module/json.md) |
| [hex](module/hex) | [hex](../../docs/dolua-api/nt26/api/module/hex.md) |
| [gps](module/gps)（[gps_api](module/gps/gps_api)） | [gps](../../docs/dolua-api/nt26/api/module/gps.md)、[nmea](../../docs/dolua-api/nt26/api/module/nmea.md) |
| [tls](module/tls) | [tls](../../docs/dolua-api/nt26/api/module/tls.md) |
| [info](module/info) | [info](../../docs/dolua-api/nt26/api/module/info.md) |
| [random](module/random) | [random](../../docs/dolua-api/nt26/api/module/random.md) |
| [dream](module/dream) | [dream](../../docs/dolua-api/nt26/api/module/dream.md) |
| [lp](module/lp) | [lp](../../docs/dolua-api/nt26/api/module/lp.md) |
| [modbus](module/modbus) | [modbus](../../docs/dolua-api/nt26/api/module/modbus.md) |
| [framekit](module/framekit) | [framekit](../../docs/dolua-api/nt26/api/module/framekit.md) |
| [rtu](module/rtu) | [rtu](../../docs/dolua-api/nt26/api/module/rtu.md) |
| [virt](module/virt) | [virat](../../docs/dolua-api/nt26/api/module/virat.md) |
| [charge](module/charge) | [charge](../../docs/dolua-api/nt26/api/peripherals/charge.md) |
| [lvgl](module/lvgl)（[lvgl_demo](module/lvgl/lvgl_demo)、[lvgl_btn](module/lvgl/lvgl_btn)、[lvgl_ssd1306](module/lvgl/lvgl_ssd1306)、[lvgl_arclabel](module/lvgl/lvgl_arclabel)、[lvgl_bar](module/lvgl/lvgl_bar)、[lvgl_arc](module/lvgl/lvgl_arc)、[lvgl_checkbox](module/lvgl/lvgl_checkbox)、[lvgl_dropdown](module/lvgl/lvgl_dropdown)、[lvgl_textarea](module/lvgl/lvgl_textarea)、[lvgl_keyboard](module/lvgl/lvgl_keyboard)、[lvgl_switch](module/lvgl/lvgl_switch)、[lvgl_spinner](module/lvgl/lvgl_spinner)、[lvgl_msgbox](module/lvgl/lvgl_msgbox)、[lvgl_watchface](module/lvgl/lvgl_watchface)、[lvgl_span](module/lvgl/lvgl_span)、[lvgl_canvas](module/lvgl/lvgl_canvas)、[lvgl_led](module/lvgl/lvgl_led)、[lvgl_chart](module/lvgl/lvgl_chart)、[lvgl_img](module/lvgl/lvgl_img)） | [lvgl](../../docs/dolua-api/nt26/api/module/lvgl.md) |

## apps — 应用场景

多模块拼起来的场景，不扫单个接口。目录名英文，标题中文。分类说明见 [apps/README.md](apps/README.md)。

| 分类 | 中文 |
| --- | --- |
| [protocol_pack](apps/protocol_pack) | 协议打包：[rtu_ch1_uart_frame](apps/protocol_pack/rtu_ch1_uart_frame)、[tcp_uart_frame](apps/protocol_pack/tcp_uart_frame) |
| [passthrough](apps/passthrough) | 透传网关 |
| [cloud_report](apps/cloud_report) | 云上报 |
| [uart_collect](apps/uart_collect) | 串口采集：[gps_uart2](apps/uart_collect/gps_uart2) |
| [modbus_gateway](apps/modbus_gateway) | Modbus 网关 |
| [io_control](apps/io_control) | IO 采集与控制 |
| [env_sensor](apps/env_sensor) | 环境传感 |
| [lbs_track](apps/lbs_track) | 定位追踪 |
| [sms](apps/sms) | 短信：[sms_forward](apps/sms/sms_forward) |
| [lowpower](apps/lowpower) | 低功耗 |
| [data_logger](apps/data_logger) | 本地记录 |
| [ota_update](apps/ota_update) | 远程升级 |
| [display_hmi](apps/display_hmi) | 屏显界面 |
