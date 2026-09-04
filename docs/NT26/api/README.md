# NT26 API

一篇文档对应一个 `require("…")` 模块。交叉引用已按当前目录写好相对路径。示例在 [examples/NT26](../../../examples/NT26/README.md)，分类与这里不完全相同。

## 外设 `peripherals/`

| 模块 | 文档 | 示例 |
| --- | --- | --- |
| gpio | [gpio.md](peripherals/gpio.md) | [gpio/normal](../../../examples/NT26/peripherals/gpio/normal)、[interrupt](../../../examples/NT26/peripherals/gpio/interrupt)、[io_task](../../../examples/NT26/peripherals/gpio/io_task) |
| uart | [uart.md](peripherals/uart.md) | [uart_normal](../../../examples/NT26/peripherals/uart/uart_normal)、[uart_block](../../../examples/NT26/peripherals/uart/uart_block) |
| spi | [spi.md](peripherals/spi.md) | [spi_api](../../../examples/NT26/peripherals/spi/spi_api)、[spi_lcd](../../../examples/NT26/peripherals/spi/spi_lcd)、[spi_st7789](../../../examples/NT26/peripherals/spi/spi_st7789) |
| i2c | [i2c.md](peripherals/i2c.md) | [iic_aht20](../../../examples/NT26/peripherals/iic/iic_aht20) |
| soft_i2c | [soft_i2c.md](peripherals/soft_i2c.md) | [soft_iic_aht20](../../../examples/NT26/peripherals/iic/soft_iic_aht20) |
| pwm | [pwm.md](peripherals/pwm.md) | [pins](../../../examples/NT26/peripherals/pwm/pins)、[timer](../../../examples/NT26/peripherals/pwm/timer)、[apwm](../../../examples/NT26/peripherals/pwm/apwm)、[timer_mhz](../../../examples/NT26/peripherals/pwm/timer_mhz)、[timer_comp](../../../examples/NT26/peripherals/pwm/timer_comp) |
| adc | [adc.md](peripherals/adc.md) | 无单独工程，见文档内示例 |
| charge | [charge.md](peripherals/charge.md) | [charge_api](../../../examples/NT26/module/charge/charge_api) |

## 网络 `network/`

| 模块 | 文档 | 示例 |
| --- | --- | --- |
| tcp | [tcp.md](network/tcp.md) | [tcp_api](../../../examples/NT26/network/tcp/tcp_api)、[tcp_cmd](../../../examples/NT26/network/tcp/tcp_cmd) |
| http | [http.md](network/http.md) | [http_request](../../../examples/NT26/network/http/http_request)、[https](../../../examples/NT26/network/http/https)、[http_file_ublob](../../../examples/NT26/network/http/http_file_ublob)、[http_file_lfs](../../../examples/NT26/network/http/http_file_lfs) |
| mqtt | [mqtt.md](network/mqtt.md) | [mqtt_client](../../../examples/NT26/network/mqtt/mqtt_client)、[mqtt_cmd](../../../examples/NT26/network/mqtt/mqtt_cmd) |
| dns | [dns.md](network/dns.md) | [dns_api](../../../examples/NT26/network/dns/dns_api) |
| ntp | [ntp.md](network/ntp.md) | [ntp_api](../../../examples/NT26/network/ntp/ntp_api) |
| lbs | [lbs.md](network/lbs.md) | [lbs_api](../../../examples/NT26/network/lbs/lbs_api) |
| rndis | [rndis.md](network/rndis.md) | [rndis_api](../../../examples/NT26/network/rndis/rndis_api) |
| wifiscan | [wifiscan.md](network/wifiscan.md) | [wifiscan_api](../../../examples/NT26/network/wifiscan/wifiscan_api) |

短信文档在 `module/`：[sms.md](module/sms.md) → [sms_api](../../../examples/NT26/network/sms/sms_api)、[sms_cmd](../../../examples/NT26/network/sms/sms_cmd)。

## 模块 `module/`

含系统、存储、协议与工具。对应示例可能在 `os/`、`storage/` 或 `module/`。

| 模块 | 文档 | 示例 |
| --- | --- | --- |
| rt | [rt.md](module/rt.md) | [task_delay](../../../examples/NT26/os/rt/task_delay)、[mbox_uart](../../../examples/NT26/os/rt/mbox_uart)、[mq_api](../../../examples/NT26/os/rt/mq_api)、[tmr_api](../../../examples/NT26/os/rt/tmr_api) |
| sys | [sys.md](module/sys.md) | [sys_api](../../../examples/NT26/os/sys/sys_api)、[sys_cmd](../../../examples/NT26/os/sys/sys_cmd) |
| script | [script.md](module/script.md) | [script_api](../../../examples/NT26/os/script/script_api) |
| log | [log.md](module/log.md) | [started/log](../../../examples/NT26/started/log) |
| info | [info.md](module/info.md) | [info_api](../../../examples/NT26/module/info/info_api)、[started/info](../../../examples/NT26/started/info) |
| lp | [lp.md](module/lp.md) | [lowpower_api](../../../examples/NT26/module/lp/lowpower_api)、[lowpower_vote](../../../examples/NT26/module/lp/lowpower_vote)、[lowpower_cron](../../../examples/NT26/module/lp/lowpower_cron) |
| cron | [cron.md](module/cron.md) | [lowpower_cron](../../../examples/NT26/module/lp/lowpower_cron) |
| ufs | [ufs.md](module/ufs.md) | [ufs_api](../../../examples/NT26/storage/ufs/ufs_api)、[ufs_cmd](../../../examples/NT26/storage/ufs/ufs_cmd) |
| ublob | [ublob.md](module/ublob.md) | [ublob_api](../../../examples/NT26/storage/ublob/ublob_api)、[ublob_cmd](../../../examples/NT26/storage/ublob/ublob_cmd) |
| sfud | [sfud.md](module/sfud.md) | [flashdb_kv](../../../examples/NT26/storage/flashdb_kv) 等外挂盘工程 |
| flashdb | [flashdb.md](module/flashdb.md) | [flashdb_kv](../../../examples/NT26/storage/flashdb_kv)、[flashdb_ts](../../../examples/NT26/storage/flashdb_ts)、[mix](../../../examples/NT26/storage/mix) |
| lfs | [lfs.md](module/lfs.md) | [littlefs](../../../examples/NT26/storage/littlefs)、[mix](../../../examples/NT26/storage/mix) |
| lcd | [lcd.md](module/lcd.md) | [spi_lcd](../../../examples/NT26/peripherals/spi/spi_lcd)、[spi_st7789](../../../examples/NT26/peripherals/spi/spi_st7789) |
| json | [json.md](module/json.md) | [json_api](../../../examples/NT26/module/json/json_api) |
| hex | [hex.md](module/hex.md) | [hex_api](../../../examples/NT26/module/hex/hex_api) |
| tls | [tls.md](module/tls.md) | [tls_api](../../../examples/NT26/module/tls/tls_api) |
| random | [random.md](module/random.md) | [random_api](../../../examples/NT26/module/random/random_api) |
| dream | [dream.md](module/dream.md) | [dream_api](../../../examples/NT26/module/dream/dream_api) |
| framekit | [framekit.md](module/framekit.md) | [framekit_cmd](../../../examples/NT26/module/framekit/framekit_cmd) |
| modbus | [modbus.md](module/modbus.md) | [modbus_api](../../../examples/NT26/module/modbus/modbus_api)、[modbus_rs485](../../../examples/NT26/module/modbus/modbus_rs485) |
| rtu | [rtu.md](module/rtu.md) | [rtu_api](../../../examples/NT26/module/rtu/rtu_api)、[rtu_cmd](../../../examples/NT26/module/rtu/rtu_cmd) |
| virat | [virat.md](module/virat.md) | [virt_api](../../../examples/NT26/module/virt/virt_api) |
| sms | [sms.md](module/sms.md) | [sms_api](../../../examples/NT26/network/sms/sms_api)、[sms_cmd](../../../examples/NT26/network/sms/sms_cmd) |

LVGL 目前只有示例、没有 API 文档：[lvgl_demo](../../../examples/NT26/module/lvgl/lvgl_demo)。
