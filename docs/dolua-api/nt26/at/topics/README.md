# 专栏

场景专题，按「要把哪件事跑通」写，不按指令名拆条。参数范围、测试应答、错误码仍以 [指令手册](../manual/README.md) 为准。

Socket / MQTT 覆盖：单通道、多通道、混合（SOCK + MQTT）、串口透传、指令主动发送、同步与异步。`mqtts.doiot.cn` 只用于普通 MQTT 测试；度云物联（玄武）是和 OneNET 同类的云平台，单独成篇。HTTP / HTTPS 覆盖：自由请求与五路通道、明文/TLS、多通道、与 SOCK/MQTT 混合、响应路由、主动发送、同步与异步。路由覆盖：串口上行、四路通道下行、双向配对。

| 篇 | 说明 |
| --- | --- |
| [Socket](socket.md) | 常驻 TCP/UDP 通道怎么配、怎么透传、怎么从 AT 口发 |
| [MQTT 连接](mqtt.md) | 普通 MQTT：通用测试服务器 `mqtts.doiot.cn`（**不是**云平台），平台 `"normal"` |
| [MQTT 连接度云物联（玄武）](5giot.md) | 度云公司物联网云平台（与 OneNET 同类）：`5giot.cn` + 平台 `"doiot"` |
| [HTTP / HTTPS](http.md) | 按需 HTTP(S)：自由请求、五路通道、证书组、响应打到哪 |
| [路由](route.md) | 上行（输入是串口）和下行（输入是四路通道）怎么配出口 |

行格式、通道编号先看 [通用约定](../manual/convention.md)。
