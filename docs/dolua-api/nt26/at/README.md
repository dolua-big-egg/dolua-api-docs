# AT 指令

应用侧 AT 引擎（UART / USB 上的 `AT+…`），**不是** `require("…")`。和 Lua API、[`rtu_config.cfg`](../api/rtu_config/rtu_config.md) 操作的是同一套业务配置，换入口不换通道编号。

本目录分成两块：

| 分区 | 路径 | 读什么 |
| --- | --- | --- |
| **专栏** | [topics/](topics/README.md) | 场景：Socket / MQTT / HTTP(S) / 路由怎么跑起来 |
| **指令手册** | [manual/](manual/README.md) | 逐条指令：测试/查询/设置、参数、应答、错误码 |

先读 [通用约定](manual/convention.md)（行格式、测试/查询/设置、两种失败风格、CME 码）。指令参数里的 `1|6[1]` 一类出口写法见 [路由串](manual/route.md)，那不是一条指令。演示代码块一律标 `lua`。

产测指令、解析自测指令不写。

## 专栏

| 篇 | 说明 |
| --- | --- |
| [Socket](topics/socket.md) | 四路 TCP/UDP：单通道 / 多通道 / 与 MQTT 混合、串口透传、`SOCKSYNC` / `SOCKASYNC` |
| [MQTT 连接](topics/mqtt.md) | 四路 MQTT：单通道 / 多通道 / 与 Socket 混合、串口透传、`MQTTSYNC` / `MQTTASYNC` |
| [HTTP / HTTPS](topics/http.md) | 五路按需 HTTP(S)：自由请求、通道、证书组、响应路由、`HTTPREQ` / `HTTPFREE` |
| [路由](topics/route.md) | 上行（串口输入）/ 下行（四路通道输入）：`DTUPSUP` / `DTUPSDN` |

## 指令手册

完整篇章表见 [manual/README.md](manual/README.md)。网络相关常看：

| 篇 | 指令 | 说明 |
| --- | --- | --- |
| [convention.md](manual/convention.md) | — | 通用约定与自定义 `+CME ERROR` |
| [route.md](manual/route.md) | — | 路由串语法（不是指令） |
| [sock.md](manual/sock.md) | `SOCK` `SOCKCFG` `SOCKKEEP` `SOCKSYNC` `SOCKASYNC` | 四路 TCP/UDP |
| [mqtt.md](manual/mqtt.md) | `MQTT` `MQTTCFG` `MQTTAUTH` `MQTTPLATFORM` `MQTTSUB` `MQTTPUB` `MQTTSYNC` `MQTTASYNC` `MQTTCLRRET` `MQTTWILL` | 四路 MQTT |
| [http.md](manual/http.md) | `HTTPURL` `HTTPCFG` `HTTPREQ` `HTTPFREE` | 五路 HTTP 与自由请求 |
| [ssl.md](manual/ssl.md) | `SSL` | 三组证书（HTTPS / MQTTS） |
| [rtu.md](manual/rtu.md) | `DTUTASK` `DTUPSUP` `DTUPSDN` `RTUWRITE` … | 透传任务、路由、云配置策略 |
