# AT 串口（UART）

**文档版本** `1.0.0`

三路业务串口的线参数、收包分包，以及「当前这条 AT 口是谁」。与 [`rtu_config.cfg` 的 `[uart.N]`](../api/rtu_config/rtu_config.md#14-uart--uartn) 同一套持久化。行格式见 [convention.md](convention.md)。

本篇改的是 **UART1～3**。没有 UART0。`pin_map` / 流控本篇改不了，写配置文件或看 [硬件 UART 落盘](../hardware/pro.md#41-uart)。

Lua `require("uart")` 的 `config` 只热改 RAM、不写盘；本篇 AT **写盘**。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+UART](#3-atuart)
- [4. AT+UARTQUE](#4-atuartque)
- [5. AT+UARTID](#5-atuartid)
- [6. 错误一览](#6-错误一览)
- [7. 联调顺序](#7-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 通道 | `<uart_id>` = 1、2、3 |
| 查询 | 必须 `AT+UART=<id>?` / `AT+UARTQUE=<id>?`，无参 `AT+UART?` **不支持** |
| 失败 | `+CMD: "error <reason>"` + `ERROR`。超范围时 reason 带 `out_of_range[min,max]` |
| 生效 | 写入持久化；线参数一般立刻作用到该口。正在作为 AT 口的那一路改波特率后，主机也要跟着改 |

UART2 出厂脚常与 SPI0 重叠，外挂 Flash 先看硬件表再改 `pin_map`（本篇改不了脚）。

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+UART` | `=?` | `<id>?` | `<id>,<baud>,<data>,<parity>,<stop>` | 线参数 |
| `AT+UARTQUE` | `=?` | `<id>?` | `<id>,<pkts>,<size>,<wait>` | 收包分包 |
| `AT+UARTID` | `=?` | `AT+UARTID` / `?` | 无 | 当前 AT 口名字 |

---

## 3. AT+UART {#3-atuart}

### 3.1 测试

```lua
AT+UART=?
```

```lua
+UART: (uart_id,baudrate,data_bits,parity,stop_bit)
uart_id: 1-3 (uart1~uart3), baudrate: 1200-3000000, data_bits: 7|8, parity: 0|1|2, stop_bit: 1|2

OK
```

### 3.2 查询

```lua
AT+UART=<uart_id>?
```

```lua
+UART: <uart_id>,<baudrate>,<data_bits>,<parity>,<stop_bit>

OK
```

### 3.3 设置

```lua
AT+UART=<uart_id>,<baudrate>,<data_bits>,<parity>,<stop_bit>
```

| 参数 | 范围 | 说明 |
| --- | --- | --- |
| `<uart_id>` | 1～3 | UART1～3 |
| `<baudrate>` | 1200～3000000 | 波特率 |
| `<data_bits>` | 7 或 8 | 数据位 |
| `<parity>` | 0 / 1 / 2 | 无 / 奇 / 偶 |
| `<stop_bit>` | 1 或 2 | 停止位 |

不改流控、不改 `pin_map`。成功回显五个字段。

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 不是 5 个整数 |
| `id` | 不是 1～3 |
| `config` | 读当前配置失败 |
| `save` | 写盘失败 |
| `baudrate=<v> out_of_range[1200,3000000]` | 波特率越界 |
| `data_bits=… out_of_range[7,8]` | 数据位 |
| `parity=… out_of_range[0,2]` | 校验 |
| `stop_bit=… out_of_range[1,2]` | 停止位 |

### 3.4 示例

```lua
AT+UART=1,115200,8,0,1
+UART: 1,115200,8,0,1

OK

AT+UART=1?
+UART: 1,115200,8,0,1

OK
```

---

## 4. AT+UARTQUE {#4-atuartque}

改收包三参数。Lua `uart.reg` / `uart.block` 拿到的就是按这三项切好的包。

AT **不能** 写成 `0` 关闭分包（配置文件里 `max_packet_size=0` 才表示不按这套切）。本指令三项下限都是 1。

### 4.1 测试

```lua
AT+UARTQUE=?
```

帮助里会带三项范围，以及 `max_packets*max_packet_size` 必须小于上限。

### 4.2 查询

```lua
AT+UARTQUE=<uart_id>?
```

```lua
+UARTQUE: <uart_id>,<max_packets>,<max_packet_size>,<max_wait_ms>

OK
```

### 4.3 设置

```lua
AT+UARTQUE=<uart_id>,<max_packets>,<max_packet_size>,<max_wait_ms>
```

| 参数 | 范围 | 说明 |
| --- | --- | --- |
| `<max_packets>` | 1～64 | 待处理包深度 |
| `<max_packet_size>` | 1～12288 | 单包上限（字节） |
| `<max_wait_ms>` | 1～60000 | 空闲断包（毫秒） |

联合约束：`max_packets * max_packet_size` 必须 **小于 61440**（60 KB）。越界时 reason 文案是 `max_packets*max_packet_size must be < 32768`（机内固定句，数字按回文认，实际门槛是 61440）。

其它 reason：`param`、`id`、`config`、`save`，以及 `max_packets=` / `max_packet_size=` / `max_wait_ms=` 的 `out_of_range[…]`。

### 4.4 示例

```lua
AT+UARTQUE=1,8,2048,100
+UARTQUE: 1,8,2048,100

OK
```

---

## 5. AT+UARTID {#5-atuartid}

查**当前这条命令是从哪口进来的**，不是改配置。

### 5.1 测试

```lua
AT+UARTID=?
```

```lua
+UARTID: query current channel name ("UART1"|"UART2"|"UART3"|"USB_AT")

OK
```

### 5.2 查询

```lua
AT+UARTID
```

或 `AT+UARTID?`。

```lua
+UARTID: "UART1"

OK
```

| 返回 | 含义 |
| --- | --- |
| `"UART1"` / `"UART2"` / `"UART3"` | 物理串口 AT |
| `"USB_AT"` | USB AT |

从 Socket / MQTT / Lua 虚拟口发会 `"error channel"`。物理口 id 异常 `"error id"`。

---

## 6. 错误一览

全部短 reason + `ERROR`。超范围带参数名和区间。联合约束见 UARTQUE。

---

## 7. 联调顺序

```lua
AT+UARTID
+UARTID: "UART1"

OK

AT+UART=1?
+UART: 1,115200,8,0,1

OK

AT+UARTQUE=1?
+UARTQUE: 1,8,2048,100

OK
```

改当前 AT 口波特率后，立刻用新波特率重开主机串口，否则后续命令会乱码。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：UART / UARTQUE / UARTID |
