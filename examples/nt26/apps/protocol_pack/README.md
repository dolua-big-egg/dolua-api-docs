# 协议打包

组帧、拆帧、粘包、自定义二进制 / 文本协议。常用 `framekit`、`hex`、`modbus` 的打包能力，再接到 UART 或网络。

接口扫一遍请看 [framekit_cmd](../../module/framekit/framekit_cmd)、[modbus_api](../../module/modbus/modbus_api)。

| 工程 | 说明 |
| --- | --- |
| [rtu_ch1_uart_frame](rtu_ch1_uart_frame) | 关透传，登记 RTU 通道 1 回调；下行加上 `7E 5A` + 长度 + XOR 后从 UART1 发出 |
| [tcp_uart_frame](tcp_uart_frame) | `tcp.create` 直连服务器；回调数据按同一帧格式从 UART1 发出 |

两份工程帧格式相同。串口助手开 HEX。`HOST` / 端口在 `main.lua` 或 `rtu_config.cfg` 里改。
