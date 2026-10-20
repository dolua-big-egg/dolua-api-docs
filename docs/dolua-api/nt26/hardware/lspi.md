# LSPI 接口

NT26 的 LCD 总线是 USP2 上的 LSPI。同一组控制器可以工作在 3 线 SPI、4 线 SPI、双数据位（2 data lane）、QSPI（代码里叫 MSPI），以及 8080 并口。本文只写前四种。8080 会占到 D4～D7，这里不展开。

下面的 GPIO 号是接口参考表里的名字。模块 PIN、PDDR 以 [pro.md](pro.md) 为准。

| GPIO | 模块脚 | PIN | PDDR |
| --- | --- | ---: | ---: |
| GPIO34 | LCD_CLK | 53 | 40 |
| GPIO35 | LCD_CS | 52 | 41 |
| GPIO36 | LCD_TE | 78 | 42 |
| GPIO37 | LCD_SIO | 50 | 43 |
| GPIO38 | LCD_SDC | 51 | 44 |
| GPIO2 | MAIN_CTS | 23 | 17 |
| GPIO1 | MAIN_RTS | 22 | 16 |

Lua 当前固件只打开了 4 线、带独立 MISO 的那一种。2 data lane 和 QSPI 的脚表在板级示例里，编译期二选一，运行时不能切换。

---

## 1. 两个开关

3 线和 4 线只差一根 DC。读和写是另一项，名字里的 I / II。

| 开关 | 寄存器 | 0 | 1 |
| --- | --- | --- | --- |
| 有没有 DC 脚 | `line4` | 3 线，不用 DC | 4 线，GPIO38 当 DC |
| 读数据走哪根线 | `busType` | I：读写共用 SDA | II：另有一根 MISO |

所以四种组合是：

| 名字 | DC | 数据线 |
| --- | --- | --- |
| `SPI_3W_I` | 无 | 一根 SDA，读写都走它 |
| `SPI_3W_II` | 无 | 写走 SDA，读走 MISO |
| `SPI_4W_I` | 有 | 一根 SDA，读写都走它 |
| `SPI_4W_II` | 有 | 写走 MOSI，读走 MISO |

接口参考表里的「4-wire」列同时画了 MISO 和 DC，对应的是 `SPI_4W_II`，不是「4 线」这个词本身多带一根 MISO。`SPI_4W_I` 有 DC，没有单独的 MISO。

DC 不决定读还是写。它只说明这一拍是命令还是参数/像素。3 线没有 DC 脚时，这一位贴在 SDA 每个字节前面，变成 9 bit：第一位 0 是命令，1 是数据。

读还是写由 `wrRdn` 决定：1 写，0 读。写的时候主机驱动 SDA；读的时候先把命令号发出去，再松开 SDA 改成采样。屏自己也看命令号，写显存和读显存是两条不同的命令。

2 data lane 和 QSPI 不在这张 2×2 里。它们是加数据位宽，用来提高刷屏速度。

---

## 2. 3 线 SPI

信号只有三根：

| 信号 | GPIO | PIN | func | 方向 |
| --- | --- | ---: | ---: | --- |
| CLK | GPIO34 | 53 | 1 | 主机 → 屏 |
| CS | GPIO35 | 52 | 1 | 主机 → 屏 |
| SDA | GPIO37 | 50 | 1 | I 型双向；II 型这根只写 |

GPIO38 空着。I 型也不用 GPIO36。II 型才把 GPIO36（PIN 78）配成 MISO，func 1。

SDA 不叫 MOSI，是因为 I 型这根线两个方向都走。MOSI 的意思是主机只往外发。

命令和数据靠 9 bit 里的第一位区分，见上一节。市面上的小尺寸 TFT 模组很少把这根线真的拿来读寄存器，但协议允许读。

这是小尺寸 TFT 控制器手册里的常规接法，Sitronix、Ilitek、GalaxyCore 都叫 3-line serial。它不是 JEDEC 或 IEEE 的独立标准，是各家手册互相抄的串行屏接口。屏上的 IM 脚决定焊死 3 线还是 4 线，软件改不了已经焊死的模式。

能用的屏（硅片支持，模组是否引出要看原理图）：

| 控制器 | 说明 |
| --- | --- |
| ST7789 / ST7735 | 手册有 3-line。成品模组多数焊成 4 线 |
| ILI9341 / ILI9163 | 同上 |
| GC9307 / GC9A01 | 手册有 3-line 和 4-line |
| 本仓库 AXS15231 板级驱动 | 源码选的是 `SPI_3W_I`。手表模组上这颗也常见 QSPI 接法，以该批次手册和 IM 脚为准 |

---

## 3. 4 线 SPI

在 3 线的 CLK、CS、数据线之外，加一根 DC。II 型再加 MISO。

| 信号 | GPIO | PIN | func | `SPI_4W_I` | `SPI_4W_II` |
| --- | --- | ---: | ---: | --- | --- |
| CLK | GPIO34 | 53 | 1 | 要 | 要 |
| CS | GPIO35 | 52 | 1 | 要 | 要 |
| SDA / MOSI | GPIO37 | 50 | 1 | 双向 SDA | 只写，叫 MOSI |
| MISO | GPIO36 | 78 | 1 | 不接 | 只读 |
| DC | GPIO38 | 51 | 2 | 要 | 要 |

DC 为 0 时这一拍是命令，为 1 时是参数或像素。数据线上仍是普通 8 bit，不再多那一位。

这是 ST7789 一类模组最常见的接法：CLK、MOSI、CS、DC、RST，背光另说。MISO 经常不焊，因为刷屏只写不读；模式仍然可以是 4 线 II，只是读命令没有回路。

同样是控制器手册里的 4-line serial，不是闪存那种 QSPI。本仓库：

| 驱动 | 源码选择 |
| --- | --- |
| ST7789 | `SPI_4W_II` |
| GC9307 | `SPI_4W_I` |
| Lua `hal_lspi` | `line4=1` 且 `busType=1`，即 4 线 II |

ST7789、ST7735、ILI9341、ILI9488（SPI 版）、GC9A01、GC9307 的成品模块默认都按这个接。这些芯片的手册里没有 2 data lane，也没有 QSPI。

---

## 4. 2 data lane

仍是 SPI 时序，像素同时从两根线推出去，带宽大约是单线的两倍。本仓库用宏 `SPI_2_DATA_LANE`，置 1 后控制器 `data2Lane=1`。

| 信号 | GPIO | PIN | func | 作用 |
| --- | --- | ---: | ---: | --- |
| CLK | GPIO34 | 53 | 1 | 时钟 |
| CS | GPIO35 | 52 | 1 | 片选 |
| D0 | GPIO37 | 50 | 1 | 第一根数据，原来的 MOSI |
| D1 | GPIO38 | 51 | 2 | 第二根数据 |
| READ | GPIO36 | 78 | 1 | 读回路，对应表上的 SPI_READ |

D1 和 4 线的 DC 是同一只脚、同一个 func 2。打开双数据位之后，这只脚不再做 DC，改出第二路像素。命令/数据怎么区分要看该控制器的双线手册，不能再假设有独立 DC。

这不是 ST7789 的标准接口。它是部分较新控制器为了加刷新率做的扩展，各家帧格式不一定相同。经典 ST7789、ILI9341、ST7735 接上这两根线也不会进入这个模式。

要用的话，先看该芯片手册是否写了 dual SPI / 2 data lane / DSPI，并且模组把第二根数据接到了 PIN 51。本仓库板级驱动没有默认打开这个宏（`SPI_2_DATA_LANE` 为 0）。

---

## 5. QSPI（MSPI）

四根数据线同时传像素。代码里的开关是 `LCD_INTERFACE_MSPI`，接口名常写成 `MSPI_4W_II`。它和上面的 4 线 SPI 不是一回事：4 线 SPI 仍然只有一根写数据，QSPI 有 D0～D3。

本仓库 `driver_example` 的脚表：

| 信号 | GPIO | PIN | PDDR | func |
| --- | --- | ---: | ---: | ---: |
| SCL | GPIO34 | 53 | 40 | 1 |
| CS | GPIO35 | 52 | 41 | 1 |
| SDI / READ | GPIO36 | 78 | 42 | 1 |
| D0 | GPIO37 | 50 | 43 | 4 |
| D1 | GPIO38 | 51 | 44 | 4 |
| D2 | GPIO2 | 23 | 17 | 1 |
| D3 | GPIO1 | 22 | 16 | 1 |

和单线 SPI 比，PIN 50、PIN 51 的 func 从 1 和 2 改成 4，另外占用 PIN 23、PIN 22。接口参考表把 QSPI 的 CLK、CS、READ 也标成 func 4；本仓库源码对这三根用的是 func 1，只有 D0、D1 是 func 4。做板以源码这张表为准。

显示器用的 QSPI 也不是 JEDEC 串行闪存的 QSPI。命令阶段经常仍是单线，像素阶段才切到四线，命令字宽每家不同（SH8601 和 CO5300 就不能混用初始化表）。

常见能用的屏是手表 AMOLED，不是模块市场的 ST7789：

| 控制器 | 本仓库板级驱动 | 市场上的常见接法 |
| --- | --- | --- |
| SH8601 | `MSPI_4W_II` | QSPI |
| CO5300 | `MSPI_4W_II` | QSPI |
| ST77903 | `MSPI_4W_II` | QSPI。它不是 ST7789 |
| ICNA3311、RM690B0 | 本仓库无驱动 | 成品多为 QSPI，初始化各自一套 |

Lua 工程里 `LCD_INTERFACE_MSPI` 是 0，这组脚没有编进当前固件。

---

## 6. 对照

| 模式 | 写数据几根 | DC | 是不是常规屏接口 | 典型屏 |
| --- | ---: | --- | --- | --- |
| 3 线 SPI | 1（SDA，可双向） | 无，改走 9 bit 的第一位 | 是，手册里的 3-line | ST7789 等能配，模组少用 |
| 4 线 SPI | 1 | 有，GPIO38 func 2 | 是，手册里的 4-line，模组最常见 | ST7789、ILI9341、GC9A01、GC9307 |
| 2 data lane | 2 | 这只脚改成 D1 | 厂商扩展，看具体手册 | 较新的双线 TFT / 部分 AMOLED，不是 ST7789 |
| QSPI | 4 | 无独立 DC，格式看厂家 | 厂商扩展，和闪存 QSPI 不同 | SH8601、CO5300、ST77903 |

当前 Lua 刷 ST7789，用第 2 行。
