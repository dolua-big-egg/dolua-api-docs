#  GPIO 与 ADC

**文档版本** `1.0.1`

脚号、方向、电平、模板上报、脉冲、波形，以及五路 ADC。AT 的 GPIO id 是 **0～38**。配置文件 `[io.N]` 是 **1-based**：`[io.1]` = 本篇 id `0`。能 `gpio.open` 的脚不是 0～38 全集，见 [硬件 GPIO 落盘](../hardware/pro.md#41-gpio) 与 [gpio API](../api/peripherals/gpio.md)。

通用约定见 [convention.md](convention.md)。本篇失败多为 `+CME ERROR`（125～138）。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+IOCFG / AT+IOINIT](#3-atiocfg--atioinit)
- [4. AT+IOSET / AT+IOGET / AT+IOTOG](#4-atioset--atioget--atiotog)
- [5. AT+IOVTGCFG / AT+IOVTGINIT](#5-atiovtgcfg--atiovtginit)
- [6. AT+IOTMPLH / AT+IOLR / AT+IOCR](#6-atiotmplh--atiolr--atiocr)
- [7. AT+IOPUL / AT+IOSEQ](#7-atiopul--atioseq)
- [8. AT+ADC](#8-atadc)
- [9. 错误一览](#9-错误一览)
- [10. 联调顺序](#10-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| `IOCFG` | **只写盘**，不立刻重配硬件 |
| `IOINIT` | **立刻**改 runtime，不写盘。IOSEQ 跑着会忙 |
| 查询 IOCFG | `AT+IOCFG=<id>` 或 `AT+IOCFG=<id>?` |
| 设置 IOCFG | **必须四段都显式给出**，禁止只写前两段靠补零 |

未初始化就 SET/GET → **125**。方向不对 → **126**。脚不支持 → **127**。

---

## 2. 指令一览

| 指令 | 作用 |
| --- | --- |
| `AT+IOCFG` | 查/写方向、上下拉、初始电平（落盘） |
| `AT+IOINIT` | 同参数，立刻作用硬件 |
| `AT+IOSET` / `IOGET` / `IOTOG` | 输出置位、读电平、翻转 |
| `AT+IOVTGCFG` / `IOVTGINIT` | IO 域电压（配置 / 仅 runtime） |
| `AT+IOTMPLH` | 上报模板 hex（1～5） |
| `AT+IOLR` / `IOCR` | 电平保持上报 / 变化上报 |
| `AT+IOPUL` | 单脉冲 |
| `AT+IOSEQ` | CSV 波形 |
| `AT+ADC` | 读电压（mV） |

---

## 3. AT+IOCFG / AT+IOINIT {#3-atiocfg--atioinit}

```lua
AT+IOCFG=3,2,0,1
+IOCFG: 3,2,0,1

OK

AT+IOCFG=3?
+IOCFG: 3,2,0,1

OK
```

| 参数 | 含义 |
| --- | --- |
| id | 0～38 |
| method | `0` 关，`1` 输入，`2` 输出 |
| pull | `0` 无，`1` 下拉，`2` 上拉 |
| init_state | 0 / 1 |

`IOINIT` 应答头是 `+IOINIT`，参数相同。IOSEQ 活动中 INIT 会 **136**。

---

## 4. AT+IOSET / AT+IOGET / AT+IOTOG {#4-atioset--atioget--atiotog}

```lua
AT+IOSET=3,1
+IOSET: 3,1

OK

AT+IOGET=3
+IOGET: 3,1

OK

AT+IOTOG=3
+IOTOG: 3,<新电平>

OK
```

输出才能 SET/TOG。CME：**105** 参数，**135** 非法，以及 125/126/127/137。

---

## 5. AT+IOVTGCFG / AT+IOVTGINIT {#5-atiovtgcfg--atiovtginit}

```lua
AT+IOVTGCFG="aon_io"
AT+IOVTGCFG="aon_io",3.3
AT+IOVTGINIT="normal_io",1.8
```

key：`aon_io` / `normal_io` / `io_volt_sel`。CFG 写盘不改 runtime；INIT 只改 runtime。电压为浮点。单项查询省略第二参。

---

## 6. AT+IOTMPLH / AT+IOLR / AT+IOCR {#6-atiotmplh--atiolr--atiocr}

模板 1～5。第三段是**引号内 hex**，解码后最长 256 字节，规则与短信模板相同。

```lua
AT+IOTMPLH=1,"6[1]","AABB"
AT+IOTMPLH=1?
```

第二参是 [路由串](route.md)，决定模板上报打到哪。非法 → **109**。

`IOLR`：`<id>[,<秒>[,<tmpl>]]` 电平保持上报。`IOCR`：`<id>[,<0|1>[,<tmpl>]]` 变化上报。查询 `=<id>?`。

与 `[io.N]` / `[io.template.N]` 同一套。

---

## 7. AT+IOPUL / AT+IOSEQ {#7-atiopul--atioseq}

脉冲：

```lua
AT+IOPUL=<id>,<mode>,<keep_ms>[,<exec>]
```

`mode`：`1` 先拉高保持再恢复；`2` 先拉低。`exec` 预留。

波形 `IOSEQ` 捕获整段参数（CSV）。形如：id、起始电平、若干保持毫秒、结束电平。保持时间按内部节拍量化成字节，整段载荷最长 **256**。测试 `AT+IOSEQ=?` 看帮助。跑着时不要 IOINIT。

---

## 8. AT+ADC {#8-atadc}

```lua
AT+ADC=1
+ADC: 1,<mV>

OK
```

| 通道 | 含义 |
| --- | --- |
| 1 | VBAT |
| 2 | AIO4 |
| 3 | AIO3 |
| 4 | AIO2 |
| 5 | AIO1 |

失败 **105** / **138**。无查询形态。

---

## 9. 错误一览

| 码 | 含义 |
| --- | --- |
| 105 / 135 | 参数 |
| 125 | 未初始化 |
| 126 | 方向不匹配 |
| 127 / 128 / 134 | 脚/状态/模式不支持 |
| 136 | IO 任务（波形）正在跑 |
| 137 | 操作失败 |
| 138 | ADC 读失败 |

---

## 10. 联调顺序

```lua
AT+IOCFG=3,2,0,0
AT+IOINIT=3,2,0,0
AT+IOSET=3,1
AT+IOGET=3
+IOGET: 3,1

OK
```

先确认该 id 在硬件落盘表里。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：IO 配置/运行时、模板、脉冲、波形、ADC |
| 1.0.1 | 2026-09-07 | `IOTMPLH` 第二参链到 [route.md](route.md) |
