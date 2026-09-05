# NT26-PRO 全 IO 表（F6E0 / F6D0）

**文档版本** `1.0.0`

**NT26-PRO** 使用 **F6E0** 与 **F6D0**。两款封装共用下表：模块 PIN、默认功能、复用名称一致。F6D0 多几颗脚，表中标 **仅 F6D0**；F6E0 不要按这些脚布线。

脚本侧 GPIO↔PIN 是这张表的**子集**，且当前**不能改绑**。能 `gpio.open` 的编号以 [`gpio.md` 1.2](../api/peripherals/gpio.md#12-nt26-pro-map) 为准，不要用芯片焊盘名里的 `GPIO16` 去对 `gpio.open(gpio.INPUT_GPIO, 16)`——调试口焊盘也叫 GPIO16，和脚本 GPIO16（PIN 103）不是同一条脚。

---

## 目录

- [1. 怎么读](#1-怎么读)
- [2. F6E0 / F6D0 差异](#2-f6e0--f6d0-差异)
- [3. 全脚表](#3-全脚表)
- [4. 与脚本模块的关系](#4-与脚本模块的关系)
- [修订记录](#修订记录)

---

## 1. 怎么读

| 列 | 含义 |
| --- | --- |
| 模块脚名 | 原理图 / 丝印常用名 |
| PIN | 模块对外脚序号，即 `gpio.INPUT_PINNO` 的 `id`（仅当「脚本 GPIO」有编号时） |
| 默认功能 | 出厂 / 未改外设占用时的第一功能 |
| 第二功能 | 表内写明的指令复用或自动复用（如 UART 脚改 GPIO、常电域自动 AGPIO） |
| 脚本 GPIO | 当前固件允许 `gpio.open(gpio.INPUT_GPIO, n)` 的 `n`。`—` 表示脚本打不开 |
| 电气 | 芯片表缩写：`I&PU` 输入上拉，`I&PD` 输入下拉，`NI&NP` 无输入使能、无上下拉 |
| 其它复用 | 同一焊盘上还出现过的功能名，供做板选脚；**不是**脚本可自由切换的清单 |
| 备注 | 占用、封装差异、与脚本编号撞名 |

「通过指令复用」指改对应外设占用（例如 UART `pin_map`），不是改 GPIO 映射表。

---

## 2. F6E0 / F6D0 差异

| 模块脚名 | PIN | F6E0 | F6D0 |
| --- | ---: | --- | --- |
| AGPIO8 / GPIO28 | 74 | 无此脚 | 硬件有。当前脚本绑定仍**没有** GPIO28，`gpio.open` 打不开 |
| ADC2 | 77 | 无此脚 | 有，对应 `adc.AIO3`（以 [adc](../api/peripherals/adc.md) 为准） |
| ADC3 | 76 | 无此脚 | 有，对应 `adc.AIO4` |

其余脚两款按同一 PIN 对。

---

## 3. 全脚表

| 模块脚名 | PIN | 默认功能 | 第二功能 | 脚本 GPIO | 电气 | 其它复用 | 备注 |
| --- | ---: | --- | --- | ---: | --- | --- | --- |
| CAM_RST_N | 103 | GPIO16 | | 16 | I&PU | SWCLK0, SWCLKA, SWCLKC | AP 域。脚本 GPIO16 是这脚，不是 DBG_RXD |
| MAIN_DCD | 21 | GPIO17 | | 17 | I&PU | SWDIO0, SWDIOA, SWDIOC | AP 域。脚本 GPIO17 是这脚，不是 DBG_TXD |
| CAM_I2C0_SCL | 57 | I2C_SCL | | — | I&PU | SWCLK1, SWCLKC, USP2_LRCK, I2C0_SCL, I2C1_SCL, GPIO18, PWM0, KPC_R4 | 片上 I2C。焊盘名 GPIO18 ≠ 脚本 GPIO18 |
| CAM_I2C0_SDA | 58 | I2C_SDA | | — | I&PU | SWDIO1, USP2_LSPI_TE, I2C0_SDA, I2C1_SDA, GPIO19, PWM1, KPC_C4 | 焊盘名 GPIO19 ≠ 脚本 GPIO19 |
| USB_BOOT | 82 | USBboot | | — | I&PD | GPIO0, KPC_R4 | 脚本 GPIO0 未导出 |
| MAIN_RTS | 22 | GPIO1 | | 1 | NI&NP | USP2_LSPI_D3, UART1_DCDn, UART1_RTSn, PWM1n, PWM0, KPC_R3 | |
| MAIN_CTS | 23 | GPIO2 | | 2 | NI&NP | USP2_LSPI_D2, UART1_DTRn, UART1_CTSn, ONEW, PWM1, KPC_R2, USP2_LSPI_TE | |
| CAM_MCLK | 54 | GPIO3 | | 3 | NI&NP | USP1_MCLK, USP1_DCX, USP2_LSPI_RCLK, ONEW, PWM2, KPC_C4, CSPI_MCLK | |
| CAM_SPI_CLK | 80 | GPIO4 | | 4 | NI&NP | USP1_BCLK, I2C1_SDA, UART1_RTSn, USIM1_URSTn, USP2_LSPI_D4, KPC_R1, CSPI_BCLK | |
| CAM_PWDN | 81 | GPIO5 | | 5 | NI&NP | USP1_LRCK, I2C1_SCL, UART1_CTSn, USIM1_UCLK, USP2_LSPI_D5, KPC_R0, CAM-PD | |
| CAM_SPI_DATA0 | 55 | GPIO6 | | 6 | NI&NP | USP1_DIN, UART2_RXD, UART1_RTSn, USIM1_UIO, USP2_LSPI_D6, KPC_C3, CSPI_RX0 | |
| CAM_SPI_DATA1 | 56 | GPIO7 | | 7 | NI&NP | USP1_DOUT, UART2_TXD, UART1_CTSn, ONEW, USP2_LSPI_D7, KPC_C2, CSPI_RX1 | |
| I2C1_SDA | 66 | GPIO8 | | 8 | NI&NP | SPI0_SSn0, I2C1_SDA, UART2_RTSn, UART0_RTSn | 默认可与 SPI0 / Flash 脚重叠 |
| I2C1_SCL | 67 | GPIO9 | | 9 | NI&NP | SPI0_MOSI, I2C1_SCL, UART2_CTSn, UART0_CTSn | 同上 |
| AUX_RXD | 28 | UART2_RXD | GPIO10（指令复用） | 10 | NI&NP | SPI0_MISO, UART2_RXD | 默认 UART2；与 SPI0 / Flash 重叠时改 UART `pin_map` |
| AUX_TXD | 29 | UART2_TXD | GPIO11（指令复用） | 11 | NI&NP | SPI0_SCLK, SPI1_SSn1, UART2_TXD | 同上 |
| USIM2_DATA | 64 | USIM2_DATA | | — | NI&NP | GPIO12, SPI1_SSn0, UART1_RTSn, UART2_RXD, USIM1_UIO, UART3_RTSn, KPC_C1, CAN_RXD | 脚本 GPIO12 未导出 |
| USIM2_RST | 63 | USIM2_RST | | — | NI&NP | GPIO13, SPI1_MOSI, UART1_CTSn, UART2_TXD, USIM1_URSTn, UART3_CTSn, KPC_C0, CAN_TXD | 脚本 GPIO13 未导出 |
| USIM2_CLK | 62 | USIM2_CLK | | — | NI&NP | GPIO14, SPI1_MISO, I2C0_SDA, UART3_RXD, USIM1_UCLK, PWM0, KPC_C3, CAN_STB | 脚本 GPIO14 未导出 |
| LCD_RST | 49 | GPIO15 | | 15 | NI&NP | SPI1_SCLK, I2C0_SCL, UART3_TXD, USP2_MCLK, PWM1, KPC_C2 | |
| DBG_RXD | 38 | UART0_RXD | | — | NI&NP | GPIO16, I2C0_SDA | 日志口。焊盘名 GPIO16 ≠ 脚本 GPIO16 |
| DBG_TXD | 39 | UART0_TXD | | — | NI&NP | GPIO17, I2C0_SCL | 日志口。焊盘名 GPIO17 ≠ 脚本 GPIO17 |
| MAIN_RXD | 17 | UART1_RXD / LPUART | | — | NI&NP | GPIO18 | AT / 主串口。焊盘名 GPIO18 ≠ 脚本 GPIO |
| MAIN_TXD | 18 | UART1_TXD / LPUART | | — | NI&NP | GPIO19 | 同上 |
| PCM_CLK | 30 | GPIO29 | | 29 | NI&NP | USP0_BCLK, PWM0 | Codec / I2S |
| PCM_SYNC | 31 | GPIO30 | | 30 | NI&NP | USP0_LRCK, PWM1 | Codec / I2S |
| PCM_DIN | 32 | GPIO31 | | 31 | NI&NP | USP0_DIN, USP1_MCLK, PWM2 | Codec / I2S |
| PCM_DOUT | 33 | GPIO32 | | 32 | NI&NP | USP0_DOUT, PWM3 | Codec / I2S |
| I2S_MCLK | 26 | GPIO33 | | 33 | NI&NP | USP0_MCLK, USP0_DCX, PWM4 | Codec / I2S |
| LCD_CLK | 53 | UART3_RXD | GPIO34（指令复用） | 34 | NI&NP | USP2_BCLK, I2C0_SDA, UART3_RXD, USP2_LSPI_WCLK | 默认 UART3；亦可作 LSPI DCX/CLK |
| LCD_CS | 52 | UART3_TXD | GPIO35（指令复用） | 35 | NI&NP | USP2_LRCK, I2C0_SCL, UART3_TXD | 默认 UART3；亦可作 LSPI CSX |
| LCD_TE | 78 | GPIO36 | | 36 | NI&NP | USP2_DIN, I2C1_SCL, UART0_RTSn, USP2_LSPI_D1 | |
| LCD_SIO | 50 | GPIO37 | | 37 | NI&NP | USP2_DOUT, I2C1_SDA, UART0_CTSn, USP2_LSPI_D0 | LSP_SDA |
| LCD_SDC | 51 | GPIO38 | | 38 | NI&NP | USP2_MCLK, USP2_DCX, USP2_LSPI_D1 | LSP_WRX |
| AGPIOWU0 | 5 | GPIO20 | WKEUP / AGPIOWU（自动） | 20 | NI&NP | PWM4n, FEM7, PWM3, KPC_C2 | 常电域 |
| AGPIOWU1 | 6 | GPIO21 | WKEUP / AGPIOWU（自动） | 21 | NI&NP | PWM3n, FEM6, PWM4, KPC_C3 | 常电域 |
| MAIN_DTR | 19 | GPIO22 | WKEUP / AGPIOWU（自动） | 22 | NI&NP | PWM4n, FEM5, PWM5, KPC_C4 | 常电域 |
| AGPIO3 | 100 | 电压域选择 | AGPIO（自动） | 23 | NI&NP | APWM0, PWM1n, FEM4, PWM0, KPC_R4 | 常电域 |
| AGPIO4 | 101 | GPIO24 | AGPIO（自动） | 24 | NI&NP | APWM1, PWM0n, FEM3, PWM1, KPC_R3 | 常电域 |
| NET_STATUS | 16 | 网络指示灯 | AGPIO（自动） | 25 | NI&NP | APWM2, PWM3n, FEM2, PWM2, KPC_R2, CAN_RXD | 默认网络灯占用；脚本要用须先关掉网络灯 |
| STATUS | 25 | 硬件看门狗喂狗 | AGPIO（自动） | 26 | NI&NP | PWM2n, FEM1, PWM3, KPC_R1, CAN_TXD | 常电域 |
| MAIN_RI | 20 | GPIO27 | AGPIO（自动） | 27 | NI&NP | PWM5n, FEM0, PWM4, KPC_R0, CAN_STB | 常电域 |
| AGPIO8 | 74 | GPIO28 | AGPIO（自动） | — | NI&NP | PWM4n, ONEW, PWM5, CAN_STB, CAN_RXD | **仅 F6D0**。当前脚本无 GPIO28 |
| WAKEUP0 | 87 | WAKEUP0 | | — | | | 低功耗唤醒 |
| USB_VBUS | 61 | WAKEUP1（支持中） | | — | | USB_DET | |
| USIM_DET | 79 | WAKEUP2（支持中） | | — | | | |
| PWRKEY | 7 | PWRKEY（支持中） | | — | | | |
| CHG_DET | 97 | CHRG_DET（支持中） | | — | | | 非 GPIO，见 [charge](../api/peripherals/charge.md) |
| ADC0 | 9 | ADC0 | AGPIO1 | — | | AIO1 | [adc](../api/peripherals/adc.md) 的 `AIO1` / `ADC0` |
| ADC1 | 96 | ADC1 | AGPIO2 | — | | AIO2 | `AIO2` |
| ADC2 | 77 | ADC2 | AGPIO3 | — | | AIO3 | **仅 F6D0** |
| ADC3 | 76 | ADC3 | AGPIO4 | — | | AIO4 | **仅 F6D0** |

原稿脚名 `MIAN_DCD` 已改正为 `MAIN_DCD`。

---

## 4. 与脚本模块的关系

| 需求 | 看哪里 |
| --- | --- |
| `gpio.open` 用 GPIO 号还是 PIN 号 | [gpio.md](../api/peripherals/gpio.md) 1.2；以本表「脚本 GPIO」列为准 |
| UART2 / UART3 默认脚、改组 | [uart](../api/peripherals/uart.md)、[rtu_config](../api/rtu_config/rtu_config.md) 的 `pin_map` |
| PWM / APWM 出哪颗脚 | [pwm](../api/peripherals/pwm.md)，脚号与本表 PIN 同一套 |
| 充电检测 PIN 97 | [charge](../api/peripherals/charge.md) |
| 模拟量 | [adc](../api/peripherals/adc.md) |

同一颗 PIN 不要同时交给 `gpio` 和另一路已占用的外设。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版。整理 NT26-PRO（F6E0 / F6D0）全 IO；标明仅 D 系列脚与脚本 GPIO 子集 |
