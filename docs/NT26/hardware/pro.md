# NT26-PRO 全 IO 表（F6E0 / F6D0）

**文档版本** `1.2.0`

**NT26-PRO** 使用 **F6E0** 与 **F6D0**。两款封装共用下表：模块 PIN、PDDR、默认功能、复用名称一致。F6D0 多几颗脚，表中标 **仅 F6D0**；F6E0 不要按这些脚布线。

[第 3 节](#3-全脚表) 是芯片**能力总表**：焊盘上曾经出现过的功能名。它**不是**当前 SDK / 固件已经落地的外设清单。做板、写脚本要看 [第 4 节](#4-当前固件外设落盘)：GPIO / UART / I2C / SPI 在固件里实际占用的 PIN 与 PDDR。UART / I2C / SPI 多数不走 `gpio` 模块，只按 **PDDR + 模块 PIN** 对脚。

脚本侧 GPIO↔PIN 是总表的**子集**，且当前**不能改绑**。能 `gpio.open` 的编号以 [`gpio.md` 1.2](../api/peripherals/gpio.md#12-nt26-pro-map) 为准。不要用芯片焊盘名里的 `GPIO16` 去对 `gpio.open(gpio.INPUT_GPIO, 16)`——调试口焊盘也叫 GPIO16，和脚本 GPIO16（PIN 103）不是同一条脚。

---

## 目录

- [1. 怎么读](#1-怎么读)
- [2. F6E0 / F6D0 差异](#2-f6e0--f6d0-差异)
- [3. 全脚表](#3-全脚表)
- [4. 当前固件外设落盘](#4-当前固件外设落盘)
  - [4.1 GPIO](#41-gpio)
  - [4.2 UART](#41-uart)
  - [4.3 I2C](#42-i2c)
  - [4.4 SPI](#43-spi)
- [5. 与脚本模块的关系](#5-与脚本模块的关系)
- [修订记录](#修订记录)

---

## 1. 怎么读

| 列 | 含义 |
| --- | --- |
| 模块脚名 | 原理图 / 丝印常用名 |
| PIN | 模块对外脚序号。脚本 `gpio.INPUT_PINNO` / `pwm.INPUT_PINNO` 用这一列（仅当该模块认这颗脚时） |
| PDDR | 芯片焊盘序号。硬件外设（UART / I2C / SPI 等）按这一列落地；`pwm.INPUT_PDDR` 也是它。没有焊盘号的专用脚写 `—` |
| 默认功能 | 芯片表上的第一功能，**不等于**当前固件一定占用 |
| 第二功能 | 表内写明的指令复用或自动复用 |
| 脚本 GPIO | 当前固件允许 `gpio.open(gpio.INPUT_GPIO, n)` 的 `n`。`—` 表示脚本打不开 |
| 电气 | `I&PU` 输入上拉，`I&PD` 输入下拉，`NI&NP` 无输入使能、无上下拉 |
| 其它复用 | 焊盘能力，供对照原理图；**不是**脚本可自由切换的清单 |
| 备注 | 封装差异、与脚本编号撞名 |

「通过指令复用」对 UART 来说就是改 `[uart.N] pin_map`，不是改 GPIO 映射表。

---

## 2. F6E0 / F6D0 差异

| 模块脚名 | PIN | F6E0 | F6D0 |
| --- | ---: | --- | --- |
| AGPIO8 / GPIO28 | 74 | 无此脚 | 硬件有。当前脚本绑定仍**没有** GPIO28，`gpio.open` 打不开 |
| ADC2 | 77 | 无此脚 | 有，对应 `adc.AIO3`（以 [adc](../api/peripherals/adc.md) 为准） |
| ADC3 | 76 | 无此脚 | 有，对应 `adc.AIO4` |

其余脚两款按同一 PIN / PDDR 对。

---

## 3. 全脚表

能力总表。固件是否占用见 [第 4 节](#4-当前固件外设落盘)。

| 模块脚名 | PIN | PDDR | 默认功能 | 第二功能 | 脚本 GPIO | 电气 | 其它复用 | 备注 |
| --- | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| CAM_RST_N | 103 | 11 | GPIO16 | | 16 | I&PU | SWCLK0, SWCLKA, SWCLKC | AP 域。脚本 GPIO16 是这脚，不是 DBG_RXD |
| MAIN_DCD | 21 | 12 | GPIO17 | | 17 | I&PU | SWDIO0, SWDIOA, SWDIOC | AP 域。脚本 GPIO17 是这脚，不是 DBG_TXD |
| CAM_I2C0_SCL | 57 | 13 | I2C_SCL | | — | I&PU | SWCLK1, SWCLKC, USP2_LRCK, I2C0_SCL, I2C1_SCL, GPIO18, PWM0, KPC_R4 | 固件 I2C0 SCL。焊盘名 GPIO18 ≠ 脚本 GPIO18 |
| CAM_I2C0_SDA | 58 | 14 | I2C_SDA | | — | I&PU | SWDIO1, USP2_LSPI_TE, I2C0_SDA, I2C1_SDA, GPIO19, PWM1, KPC_C4 | 固件 I2C0 SDA。焊盘名 GPIO19 ≠ 脚本 GPIO19 |
| USB_BOOT | 82 | 15 | USBboot | | — | I&PD | GPIO0, KPC_R4 | 脚本 GPIO0 未导出 |
| MAIN_RTS | 22 | 16 | GPIO1 | | 1 | NI&NP | USP2_LSPI_D3, UART1_DCDn, UART1_RTSn, PWM1n, PWM0, KPC_R3 | |
| MAIN_CTS | 23 | 17 | GPIO2 | | 2 | NI&NP | USP2_LSPI_D2, UART1_DTRn, UART1_CTSn, ONEW, PWM1, KPC_R2, USP2_LSPI_TE | |
| CAM_MCLK | 54 | 18 | GPIO3 | | 3 | NI&NP | USP1_MCLK, USP1_DCX, USP2_LSPI_RCLK, ONEW, PWM2, KPC_C4, CSPI_MCLK | |
| CAM_SPI_CLK | 80 | 19 | GPIO4 | | 4 | NI&NP | USP1_BCLK, I2C1_SDA, UART1_RTSn, USIM1_URSTn, USP2_LSPI_D4, KPC_R1, CSPI_BCLK | 固件表 I2C1 SDA（控制器当前未开） |
| CAM_PWDN | 81 | 20 | GPIO5 | | 5 | NI&NP | USP1_LRCK, I2C1_SCL, UART1_CTSn, USIM1_UCLK, USP2_LSPI_D5, KPC_R0, CAM-PD | 固件表 I2C1 SCL（控制器当前未开） |
| CAM_SPI_DATA0 | 55 | 21 | GPIO6 | | 6 | NI&NP | USP1_DIN, UART2_RXD, UART1_RTSn, USIM1_UIO, USP2_LSPI_D6, KPC_C3, CSPI_RX0 | UART2 `pin_map=1` 的 RX |
| CAM_SPI_DATA1 | 56 | 22 | GPIO7 | | 7 | NI&NP | USP1_DOUT, UART2_TXD, UART1_CTSn, ONEW, USP2_LSPI_D7, KPC_C2, CSPI_RX1 | UART2 `pin_map=1` 的 TX |
| I2C1_SDA | 66 | 23 | GPIO8 | | 8 | NI&NP | SPI0_SSn0, I2C1_SDA, UART2_RTSn, UART0_RTSn | 固件 SPI0 常用软件片选（脚本 GPIO8） |
| I2C1_SCL | 67 | 24 | GPIO9 | | 9 | NI&NP | SPI0_MOSI, I2C1_SCL, UART2_CTSn, UART0_CTSn | 固件 SPI0 MOSI |
| AUX_RXD | 28 | 25 | UART2_RXD | GPIO10（指令复用） | 10 | NI&NP | SPI0_MISO, UART2_RXD | UART2 **出厂** `pin_map=2` 的 RX；亦是 SPI0 MISO |
| AUX_TXD | 29 | 26 | UART2_TXD | GPIO11（指令复用） | 11 | NI&NP | SPI0_SCLK, SPI1_SSn1, UART2_TXD | UART2 **出厂** `pin_map=2` 的 TX；亦是 SPI0 SCLK |
| USIM2_DATA | 64 | 27 | USIM2_DATA | | — | NI&NP | GPIO12, SPI1_SSn0, UART1_RTSn, UART2_RXD, USIM1_UIO, UART3_RTSn, KPC_C1, CAN_RXD | UART2 `pin_map=0` 的 RX。脚本 GPIO12 未导出 |
| USIM2_RST | 63 | 28 | USIM2_RST | | — | NI&NP | GPIO13, SPI1_MOSI, UART1_CTSn, UART2_TXD, USIM1_URSTn, UART3_CTSn, KPC_C0, CAN_TXD | UART2 `pin_map=0` 的 TX。脚本 GPIO13 未导出 |
| USIM2_CLK | 62 | 29 | USIM2_CLK | | — | NI&NP | GPIO14, SPI1_MISO, I2C0_SDA, UART3_RXD, USIM1_UCLK, PWM0, KPC_C3, CAN_STB | UART3 `pin_map=1` 的 RX。脚本 GPIO14 未导出 |
| LCD_RST | 49 | 30 | GPIO15 | | 15 | NI&NP | SPI1_SCLK, I2C0_SCL, UART3_TXD, USP2_MCLK, PWM1, KPC_C2 | UART3 `pin_map=1` 的 TX |
| DBG_RXD | 38 | 31 | UART0_RXD | | — | NI&NP | GPIO16, I2C0_SDA | 固件 UART0 RX。焊盘名 GPIO16 ≠ 脚本 GPIO16 |
| DBG_TXD | 39 | 32 | UART0_TXD | | — | NI&NP | GPIO17, I2C0_SCL | 固件 UART0 TX。焊盘名 GPIO17 ≠ 脚本 GPIO17 |
| MAIN_RXD | 17 | 33 | UART1_RXD / LPUART | | — | NI&NP | GPIO18 | 固件 UART1 RX（AT / 主串口） |
| MAIN_TXD | 18 | 34 | UART1_TXD / LPUART | | — | NI&NP | GPIO19 | 固件 UART1 TX |
| PCM_CLK | 30 | 35 | GPIO29 | | 29 | NI&NP | USP0_BCLK, PWM0 | Codec / I2S |
| PCM_SYNC | 31 | 36 | GPIO30 | | 30 | NI&NP | USP0_LRCK, PWM1 | Codec / I2S |
| PCM_DIN | 32 | 37 | GPIO31 | | 31 | NI&NP | USP0_DIN, USP1_MCLK, PWM2 | Codec / I2S |
| PCM_DOUT | 33 | 38 | GPIO32 | | 32 | NI&NP | USP0_DOUT, PWM3 | Codec / I2S |
| I2S_MCLK | 26 | 39 | GPIO33 | | 33 | NI&NP | USP0_MCLK, USP0_DCX, PWM4 | Codec / I2S |
| LCD_CLK | 53 | 40 | UART3_RXD | GPIO34（指令复用） | 34 | NI&NP | USP2_BCLK, I2C0_SDA, UART3_RXD, USP2_LSPI_WCLK | UART3 **出厂** `pin_map=0` 的 RX |
| LCD_CS | 52 | 41 | UART3_TXD | GPIO35（指令复用） | 35 | NI&NP | USP2_LRCK, I2C0_SCL, UART3_TXD | UART3 **出厂** `pin_map=0` 的 TX |
| LCD_TE | 78 | 42 | GPIO36 | | 36 | NI&NP | USP2_DIN, I2C1_SCL, UART0_RTSn, USP2_LSPI_D1 | |
| LCD_SIO | 50 | 43 | GPIO37 | | 37 | NI&NP | USP2_DOUT, I2C1_SDA, UART0_CTSn, USP2_LSPI_D0 | LSP_SDA |
| LCD_SDC | 51 | 44 | GPIO38 | | 38 | NI&NP | USP2_MCLK, USP2_DCX, USP2_LSPI_D1 | LSP_WRX |
| AGPIOWU0 | 5 | 45 | GPIO20 | WKEUP / AGPIOWU（自动） | 20 | NI&NP | PWM4n, FEM7, PWM3, KPC_C2 | 常电域 |
| AGPIOWU1 | 6 | 46 | GPIO21 | WKEUP / AGPIOWU（自动） | 21 | NI&NP | PWM3n, FEM6, PWM4, KPC_C3 | 常电域 |
| MAIN_DTR | 19 | 47 | GPIO22 | WKEUP / AGPIOWU（自动） | 22 | NI&NP | PWM4n, FEM5, PWM5, KPC_C4 | 常电域 |
| AGPIO3 | 100 | 48 | 电压域选择 | AGPIO（自动） | 23 | NI&NP | APWM0, PWM1n, FEM4, PWM0, KPC_R4 | 常电域 |
| AGPIO4 | 101 | 49 | GPIO24 | AGPIO（自动） | 24 | NI&NP | APWM1, PWM0n, FEM3, PWM1, KPC_R3 | 常电域 |
| NET_STATUS | 16 | 50 | 网络指示灯 | AGPIO（自动） | 25 | NI&NP | APWM2, PWM3n, FEM2, PWM2, KPC_R2, CAN_RXD | 默认网络灯占用 |
| STATUS | 25 | 51 | 硬件看门狗喂狗 | AGPIO（自动） | 26 | NI&NP | PWM2n, FEM1, PWM3, KPC_R1, CAN_TXD | 常电域 |
| MAIN_RI | 20 | 52 | GPIO27 | AGPIO（自动） | 27 | NI&NP | PWM5n, FEM0, PWM4, KPC_R0, CAN_STB | 常电域 |
| AGPIO8 | 74 | 53 | GPIO28 | AGPIO（自动） | — | NI&NP | PWM4n, ONEW, PWM5, CAN_STB, CAN_RXD | **仅 F6D0**。当前脚本无 GPIO28 |
| WAKEUP0 | 87 | — | WAKEUP0 | | — | | | 低功耗唤醒 |
| USB_VBUS | 61 | — | WAKEUP1（支持中） | | — | | USB_DET | |
| USIM_DET | 79 | — | WAKEUP2（支持中） | | — | | | |
| PWRKEY | 7 | — | PWRKEY（支持中） | | — | | | |
| CHG_DET | 97 | — | CHRG_DET（支持中） | | — | | | 非 GPIO，见 [charge](../api/peripherals/charge.md) |
| ADC0 | 9 | — | ADC0 | AGPIO1 | — | | AIO1 | [adc](../api/peripherals/adc.md) 的 `AIO1` / `ADC0` |
| ADC1 | 96 | — | ADC1 | AGPIO2 | — | | AIO2 | `AIO2` |
| ADC2 | 77 | — | ADC2 | AGPIO3 | — | | AIO3 | **仅 F6D0** |
| ADC3 | 76 | — | ADC3 | AGPIO4 | — | | AIO4 | **仅 F6D0** |

原稿脚名 `MIAN_DCD` 已改正为 `MAIN_DCD`。

---

## 4. 当前固件外设落盘

下面只写**当前固件已经登记并按组落地**的脚。GPIO 是脚本能 `open` 的固定绑定；UART 多组全部列出。未写进本组的焊盘即使总表里能复用，SDK 也选不到。

GPIO 当前**不能改绑**。Lua `uart.config` **改不了** `pin_map`，只能在 `rtu_config.cfg` 的 `[uart.N]` 里写，下次加载生效。I2C / SPI 没有 `pin_map`，脚固定。

### 4.1 GPIO {#41-gpio}

固件 GPIO 绑定表。`gpio.open(gpio.INPUT_GPIO, n)` 用「GPIO」列，`gpio.open(gpio.INPUT_PINNO, pin)` 用「PIN」列。表外编号 `open` 失败。F6D0 硬件上的 GPIO28（PIN 74）**不在本表**，脚本同样打不开。

| GPIO | PIN | PDDR | 常电域 | 丝印 | 说明 |
| ---: | ---: | ---: | --- | --- | --- |
| 1 | 22 | 16 | 否 | MAIN_RTS | |
| 2 | 23 | 17 | 否 | MAIN_CTS | |
| 3 | 54 | 18 | 否 | CAM_MCLK | |
| 4 | 80 | 19 | 否 | CAM_SPI_CLK | 固件表 I2C1 SDA（控制器未开） |
| 5 | 81 | 20 | 否 | CAM_PWDN | 固件表 I2C1 SCL（控制器未开） |
| 6 | 55 | 21 | 否 | CAM_SPI_DATA0 | UART2 `pin_map=1` RX |
| 7 | 56 | 22 | 否 | CAM_SPI_DATA1 | UART2 `pin_map=1` TX |
| 8 | 66 | 23 | 否 | I2C1_SDA | SPI0 常用软件片选 |
| 9 | 67 | 24 | 否 | I2C1_SCL | SPI0 MOSI |
| 10 | 28 | 25 | 否 | AUX_RXD | UART2 出厂 RX；SPI0 MISO |
| 11 | 29 | 26 | 否 | AUX_TXD | UART2 出厂 TX；SPI0 SCLK |
| 15 | 49 | 30 | 否 | LCD_RST | UART3 `pin_map=1` TX |
| 16 | 103 | 11 | 否 | CAM_RST_N | 不是 DBG_RXD |
| 17 | 21 | 12 | 否 | MAIN_DCD | 不是 DBG_TXD |
| 20 | 5 | 45 | 是 | AGPIOWU0 | |
| 21 | 6 | 46 | 是 | AGPIOWU1 | |
| 22 | 19 | 47 | 是 | MAIN_DTR | |
| 23 | 100 | 48 | 是 | AGPIO3 | |
| 24 | 101 | 49 | 是 | AGPIO4 | |
| 25 | 16 | 50 | 是 | NET_STATUS | 默认网络灯占用 |
| 26 | 25 | 51 | 是 | STATUS | |
| 27 | 20 | 52 | 是 | MAIN_RI | |
| 29 | 30 | 35 | 否 | PCM_CLK | |
| 30 | 31 | 36 | 否 | PCM_SYNC | |
| 31 | 32 | 37 | 否 | PCM_DIN | |
| 32 | 33 | 38 | 否 | PCM_DOUT | |
| 33 | 26 | 39 | 否 | I2S_MCLK | |
| 34 | 53 | 40 | 否 | LCD_CLK | UART3 出厂 RX |
| 35 | 52 | 41 | 否 | LCD_CS | UART3 出厂 TX |
| 36 | 78 | 42 | 否 | LCD_TE | |
| 37 | 50 | 43 | 否 | LCD_SIO | |
| 38 | 51 | 44 | 否 | LCD_SDC | |

未导出：GPIO 0、12～14、18、19、28。调试口 / 主串口焊盘上的 GPIO16～19 **不是**上表这几号。接口约定见 [`gpio.md`](../api/peripherals/gpio.md)。

### 4.2 UART {#41-uart}

出厂未改配置时：UART0 / UART1 / UART3 用 `pin_map=0`，UART2 用 **`pin_map=2`**。

| 口 | `pin_map` | TX PIN | TX PDDR | RX PIN | RX PDDR | 出厂 | 丝印 / 说明 |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| UART0 | 0 | 39 | 32 | 38 | 31 | 是 | DBG_TXD / DBG_RXD。日志口，脚本不当业务口 |
| UART1 | 0 | 18 | 34 | 17 | 33 | 是 | MAIN_TXD / MAIN_RXD。AT / 主串口，恒开 |
| UART2 | 0 | 63 | 28 | 64 | 27 | | USIM2_RST / USIM2_DATA |
| UART2 | 1 | 56 | 22 | 55 | 21 | | CAM_SPI_DATA1 / CAM_SPI_DATA0。外挂 Flash 常用这组，把 AUX 让给 SPI0 |
| UART2 | 2 | 29 | 26 | 28 | 25 | **是** | AUX_TXD / AUX_RXD。与 SPI0 的 SCLK / MISO **重叠** |
| UART3 | 0 | 52 | 41 | 53 | 40 | 是 | LCD_CS / LCD_CLK |
| UART3 | 1 | 49 | 30 | 62 | 29 | | LCD_RST / USIM2_CLK |

没有列出的 `pin_map` 值无效，口初始化会失败。UART0 / UART1 当前只有组 0。

同一组 TX/RX 必须成对使用，不能只改其中一脚。

### 4.3 I2C {#42-i2c}

硬件 I2C 不经 `gpio` 打开，按 PDDR 配复用。任意脚模拟见 [`soft_i2c`](../api/peripherals/soft_i2c.md)。

| 路 | SCL PIN | SCL PDDR | SDA PIN | SDA PDDR | 当前镜像 |
| --- | ---: | ---: | ---: | ---: | --- |
| I2C0 | 57 | 13 | 58 | 14 | **落地**。`i2c.new(i2c.I2C0)` |
| I2C1 | 81 | 20 | 80 | 19 | 固件已登记 PAD；**当前镜像未打开该控制器**，`i2c.I2C1` 不要当可用总线 |

I2C0 的 PIN 57 / 58 不在脚本 GPIO 表里。

### 4.4 SPI {#43-spi}

总线时钟 / MOSI / MISO 按 PDDR 固定；片选常用脚本 GPIO，不是硬件 SS 自动脚。

| 路 | 信号 | PIN | PDDR | 当前镜像 |
| --- | --- | ---: | ---: | --- |
| SPI0 | SCLK | 29 | 26 | **落地**。`spi.new(spi.SPI0)` |
| SPI0 | MOSI | 67 | 24 | 落地 |
| SPI0 | MISO | 28 | 25 | 落地（半双工可不占） |
| SPI0 | 片选（常用） | 66 | 23 | 脚本 GPIO8；demo 多用这脚做 CS |
| SPI1 | SCLK | 49 | 30 | 固件已登记 PAD；**当前镜像未打开该控制器** |
| SPI1 | MOSI | 63 | 28 | 同上 |
| SPI1 | MISO | 62 | 29 | 同上 |

SPI0 的 SCLK / MISO 就是 UART2 **出厂组**（`pin_map=2`）的 TX / RX。外挂 Flash 或自己摸 SPI0 时，把 UART2 改成 `pin_map=0` 或 `pin_map=1`，或关掉 UART2。

---

## 5. 与脚本模块的关系

| 需求 | 看哪里 |
| --- | --- |
| `gpio.open` 用 GPIO 号还是 PIN / PDDR | [gpio.md](../api/peripherals/gpio.md)；落盘以 [4.1](#41-gpio) 为准 |
| UART 口、`pin_map`、分包 | [uart](../api/peripherals/uart.md)、[rtu_config](../api/rtu_config/rtu_config.md)；脚以 [4.2](#41-uart) 为准 |
| 硬件 I2C | [i2c](../api/peripherals/i2c.md)；脚以 [4.3](#42-i2c) 为准 |
| SPI | [spi](../api/peripherals/spi.md)；脚以 [4.4](#43-spi) 为准 |
| PWM / APWM | [pwm](../api/peripherals/pwm.md)，PIN / PDDR 与总表同一套 |
| 充电检测 PIN 97 | [charge](../api/peripherals/charge.md) |
| 模拟量 | [adc](../api/peripherals/adc.md) |

同一颗 PIN 不要同时交给已占用的外设和 `gpio`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版。整理 NT26-PRO（F6E0 / F6D0）全 IO；标明仅 D 系列脚与脚本 GPIO 子集 |
| 1.1.0 | 2026-09-05 | 区分能力总表与 SDK 落盘；总表加 PDDR；写入 UART 全部 pin_map 及 I2C / SPI 实际 PIN、PDDR |
| 1.2.0 | 2026-09-05 | 落盘区补固件 GPIO 绑定（GPIO / PIN / PDDR） |
