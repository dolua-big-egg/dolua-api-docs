# NT26 硬件脚位

全 IO / 复用表按**映射是否相同**分篇，不按销售名各拷一份。脚本怎么 `open` 仍看 [`gpio`](../api/peripherals/gpio.md)。每篇里的大表是芯片**能力总表**；GPIO / UART / I2C / SPI 当前固件占用的 PIN、PDDR 在同篇「当前固件外设落盘」。

| 产品 | 封装 | 全 IO 文档 |
| --- | --- | --- |
| NT26-PRO | F6E0 | [pro.md](pro.md) |
| NT26-PRO | F6D0 | 与 F6E0 **同一篇**（[pro.md](pro.md)）。表中标「仅 F6D0」的脚，E 系列没有 |
| — | F6B0 | 全 IO 表尚未收录。脚本 GPIO↔PIN 见 [gpio.md 1.3](../api/peripherals/gpio.md#13-nt26-f6b0-映射表) |

当前固件**不支持**用户改 GPIO↔PIN 绑定。做板以本目录表格为准。
