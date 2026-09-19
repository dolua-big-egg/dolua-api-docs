# 屏显界面

LCD / LVGL 做状态页、菜单、按键。SPI0 与 UART2 默认脚重叠时，先在 `rtu_config.cfg` 写 `[uart.2] pin_map=1`，需要的话关掉 `[net_led]`。

对照 [lvgl_demo](../../module/lvgl/lvgl_demo)、[lvgl_btn](../../module/lvgl/lvgl_btn)、[lvgl_arclabel](../../module/lvgl/lvgl_arclabel)、[lvgl_bar](../../module/lvgl/lvgl_bar)、[lvgl_arc](../../module/lvgl/lvgl_arc)、[lvgl_checkbox](../../module/lvgl/lvgl_checkbox)、[lvgl_dropdown](../../module/lvgl/lvgl_dropdown)、[lvgl_textarea](../../module/lvgl/lvgl_textarea)、[lvgl_keyboard](../../module/lvgl/lvgl_keyboard)、[lvgl_switch](../../module/lvgl/lvgl_switch)、[lvgl_spinner](../../module/lvgl/lvgl_spinner)、[lvgl_msgbox](../../module/lvgl/lvgl_msgbox)、[lvgl_watchface](../../module/lvgl/lvgl_watchface)、[lvgl_span](../../module/lvgl/lvgl_span)、[lvgl_canvas](../../module/lvgl/lvgl_canvas)、[lvgl_led](../../module/lvgl/lvgl_led)、[lvgl_chart](../../module/lvgl/lvgl_chart)、[lvgl_img](../../module/lvgl/lvgl_img)、[spi_st7789](../../peripherals/spi/spi_st7789)。
