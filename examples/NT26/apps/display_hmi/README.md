# 屏显界面

LCD / LVGL 做状态页、菜单、按键。SPI0 与 UART2 默认脚重叠时，先在 `rtu_config.cfg` 写 `[uart.2] pin_map=1`，需要的话关掉 `[net_led]`。

对照 [lvgl_demo](../../module/lvgl/lvgl_demo)、[lvgl_img](../../module/lvgl/lvgl_img)、[spi_st7789](../../peripherals/spi/spi_st7789)。
