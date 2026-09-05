# NT26 AT 指令

应用侧 AT 引擎（UART / USB 上的 `AT+…`），**不是** `require("…")`。和 Lua API、[`rtu_config.cfg`](../api/rtu_config/rtu_config.md) 操作的是同一套业务配置，换入口不换通道编号。

先读 [convention.md](convention.md)（行格式、测试/查询/设置、两种失败风格、CME 码）。各专题按同一体例：约定差异 → 指令一览 → 逐条测试/查询/设置/参数/应答/错误 → 联调。演示代码块一律标 `lua`。

产测指令、解析自测指令不写。

## 篇章

| 篇章 | 指令 | 说明 |
| --- | --- | --- |
| [convention.md](convention.md) | — | 通用约定与自定义 `+CME ERROR` |
| [info.md](info.md) | `AT` `ATI` `VERSION` `CGMR` `IMEI` `ICCID` `IMSI` `SIMINFO` `CHIPID` `CMEERR` `ATMODE` | 握手、版本、标识 |
| [netstat.md](netstat.md) | `CSQ` `MCC` `MNC` `CEREG` `CGACT` `CGI` `ISLINK` `UTC` `TIMEZONE` `TIME` `NTS` `RESET` `CFUN` | 驻网状态、时间、复位、射频开关 |
| [link.md](link.md) | `APN` `APNAUTH` `LP` `SIMCFG` `SIMSLOT` `DOSIMSLOT` `RILAT` `RNDIS` `RNDISSAVE` | APN、低功耗、切卡、原厂通道、USB 网卡 |
| [dns.md](dns.md) | `DNS` `DNSG` `DNSC` `DNSCID` | DNS 服务器、解析、缓存 |
| [ntp.md](ntp.md) | `NTP` | 对时（一次执行） |
| [lbs.md](lbs.md) | `LBS` `LBSCFG` `WIFISCAN` `WIFILOC` | 基站 / Wi-Fi 定位 |
| [sock.md](sock.md) | `SOCK` `SOCKCFG` `SOCKKEEP` `SOCKSYNC` `SOCKASYNC` | 四路 TCP/UDP |
| [mqtt.md](mqtt.md) | `MQTT` `MQTTCFG` `MQTTAUTH` `MQTTPLATFORM` `MQTTSUB` `MQTTPUB` `MQTTSYNC` `MQTTASYNC` `MQTTCLRRET` `MQTTWILL` | 四路 MQTT |
| [http.md](http.md) | `HTTPURL` `HTTPCFG` `HTTPREQ` `HTTPFREE` | 五路 HTTP 与自由请求 |
| [ssl.md](ssl.md) | `SSL` | 三组证书 |
| [uart.md](uart.md) | `UART` `UARTQUE` `UARTID` | 串口线参数、分包、当前口 |
| [io.md](io.md) | `IOSET` `IOGET` `IOCFG` `IOINIT` `IOVTGCFG` `IOVTGINIT` `IOTOG` `IOTMPLH` `IOLR` `IOCR` `IOPUL` `IOSEQ` `ADC` | GPIO、模板、波形、ADC |
| [sms.md](sms.md) | `SMS` `SMSR` `SMSL` `SMSD` `SMSWRITE` `SMSSYNC` `SMSASYNC` `SMSTMPH` `SMSCFG` | 短信通道、SIM 存储、收发、转发 |
| [rtu.md](rtu.md) | `RTUCONFIG` `DTUTASK` `DTUSTATE` `NETIO` `DTUHEART` `DTUREG` `DTUPSUP` `DTUPSDN` `RTUWRITE` `RTUWRITEQ` `RTUCTL` `RTUPSD` `DTUMSGHEAD` `CLDCFG` | 透传任务、路由、云配置策略 |
| [script.md](script.md) | `SCRIPTCLEAR` `SCRIPTDEL` `SCRIPTCB` `SCRIPTBUNDLE` `SCRIPTDEPLOY` `SCRIPTFILE` `SCRIPTMANIFEST` `SCRIPTSELECT` `SCRIPTCONFIRM` `SCRIPTROLLBACK` | Lua 脚本包 AB 槽 |
| [ota.md](ota.md) | `OTA` `MCUOTA` | 模组升级、MCU 槽位分片 |
| [sys.md](sys.md) | `LOG` `PLOG` `FSINFO` `FSLIST` `HEAPINFO` `THREAD` `PMU` `TRNG` `DEVICECFG` `CFGID` `FACTORY` `ONLINEDBG` | 日志、文件系统、诊断、整机配置、恢复出厂 |
