# 透传网关

串口数据原样或经路由转到 TCP / MQTT / 传统 RTU 四路通道，下行再写回串口。

单模块接口请看 [rtu_api](../../module/rtu/rtu_api)、[tcp_api](../../network/tcp/tcp_api)、[uart_normal](../../peripherals/uart/uart_normal)。通道参数写 `rtu_config.cfg`，不要在脚本里 `tcp.create` 冒充 DTU。
