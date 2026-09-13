# apps — 应用场景

这里放 **多模块拼起来的场景工程**，不扫单个 `require` 的接口。查某个模块怎么调用，仍去 `started` / `os` / `peripherals` / `network` / `storage` / `module` 里的 `*_api` / `*_cmd`。

目录名英文，标题中文。分类下再放具体工程（`main.lua` + `manifest.json` + `.luaproj`），工程名用场景词，不要 `_api` / `_cmd` / `_demo`。

`protocol_pack` 下已有可烧录工程，见该分类 README。

| 分类 | 中文 | 放什么 |
| --- | --- | --- |
| [protocol_pack](protocol_pack) | 协议打包 | 组帧、拆帧、自定义协议、`framekit` |
| [passthrough](passthrough) | 透传网关 | 串口 ↔ TCP / MQTT / 传统 RTU 通道 |
| [cloud_report](cloud_report) | 云上报 | 定时或变化上报到 MQTT / HTTP |
| [uart_collect](uart_collect) | 串口采集 | 读仪表、拼包、本地缓存后再上云 |
| [modbus_gateway](modbus_gateway) | Modbus 网关 | RS485 轮询后转发云端 |
| [io_control](io_control) | IO 采集与控制 | GPIO 输入输出、变化上报、时序 |
| [env_sensor](env_sensor) | 环境传感 | I2C / ADC 温湿度、电压等 |
| [lbs_track](lbs_track) | 定位追踪 | 基站定位、定时轨迹 |
| [sms_alert](sms_alert) | 短信告警 | 收发、转发、条件触发短信 |
| [lowpower](lowpower) | 低功耗 | 投票休眠、cron 唤醒、驻网策略 |
| [data_logger](data_logger) | 本地记录 | ufs / ublob / FlashDB 落盘与回放 |
| [ota_update](ota_update) | 远程升级 | HTTP 拉包、脚本更新、配置同步 |
| [display_hmi](display_hmi) | 屏显界面 | LCD / LVGL 状态页、按键菜单 |
