# 串口采集

从 UART 读仪表或 MCU：按空闲 / 长度切包，解析后再本地缓存或上云。回调里只投递，解析放工作协程。

分包参数在 `rtu_config.cfg` 的 `[uart.N]`。接口对照 [uart_block](../../peripherals/uart/uart_block)、[uart_normal](../../peripherals/uart/uart_normal)。
