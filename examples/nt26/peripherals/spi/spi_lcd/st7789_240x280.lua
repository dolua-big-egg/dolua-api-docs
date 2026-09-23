-- 240×280，族名 lcd.ST7789：不写 init 时走固件内置上电表。
-- 外部 init 驱动其它料号请用 lcd.TFT，见 spi_lcd_cfg。

return {
    driver = "st7789",
    width  = 240,
    height = 280,
    offset = {
        [0] = { x = 0,  y = 20 },
        [1] = { x = 20, y = 0  },
        [2] = { x = 0,  y = 20 },
        [3] = { x = 20, y = 0  },
    },
    reset = { high_ms = 10, low_ms = 10, wait_ms = 120 },
}
