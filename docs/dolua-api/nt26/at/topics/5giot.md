# MQTT 连接度云物联（玄武）

**文档版本** `1.0.1`

场景专题：用应用 AT 把一路 MQTT 接到 **度云物联平台**（也称 **玄武平台**）。这是度云公司推出的 **物联网云平台**，和 OneNET 同类：要在控制台建产品、抄鉴权、按平台规则拼 ClientId。控制台 [https://5giot.cn](https://5giot.cn/)，Broker **`5giot.cn:1883`**，`AT+MQTTPLATFORM` 必须写成 **`"doiot"`**。

**不要和普通 MQTT 测试服务器搞混。** `mqtts.doiot.cn` 只是通用 MQTT 测试口，用来联调普通 MQTT（平台 `"normal"`、账号 `doiot` / 密码 `web`），**不是**度云物联平台，也进不了本篇控制台。普通 MQTT 见 [MQTT 连接专栏](mqtt.md)。

指令逐条的测试/查询/设置、参数表、错误码见 [MQTT 指令手册](../manual/mqtt.md)、[透传任务](../manual/rtu.md)、[路由串](../manual/route.md)。

这不是 Lua `require("mqtt")`。通道号与 `[mqtt.N]` / `AT+DTUTASK=<N>` **同一路 1～4**。

---

## 目录

- [1. 先建立图景](#1-先建立图景)
- [2. 控制台：产品、物模型、四元组](#2-控制台产品物模型四元组)
- [3. 联调前：版本与驻网](#3-联调前版本与驻网)
- [4. AT 接入](#4-at-接入)
- [5. 透传](#5-透传)
- [6. 上报与下发](#6-上报与下发)
- [7. io* 与 GPIO](#7-io-与-gpio)
- [8. 网页远程配参（可选）](#8-网页远程配参可选)
- [9. 常见失败](#9-常见失败)
- [10. 对照手册](#10-对照手册)
- [修订记录](#修订记录)

---

## 1. 先建立图景

度云物联（玄武）是度云公司的 **云平台**，不是一台随便连的公共 MQTT。要先在 [https://5giot.cn](https://5giot.cn/) 建产品、物模型，再把四元组写进模组。官方 NT26 RTU **主推 AT**：平台类型写成 `"doiot"` 后，固件按平台规则拼 ClientId，并处理 `io*` 物模型。

和 OneNET 一样：`"onenet"` / `"doiot"` 都是云平台类型；`"normal"` 才是普通 MQTT。`mqtts.doiot.cn` 属于后者。

| | 普通 MQTT 测试 | 度云物联 / 玄武（本篇） | OneNET |
| --- | --- | --- | --- |
| 是什么 | 通用 MQTT **测试服务器** | 度云公司推出的 **物联网云平台**（和 OneNET 同类） | 中国移动物联网云平台 |
| 主机 | `mqtts.doiot.cn` | **`5giot.cn`** | OneNET 文档里的 broker |
| `MQTTPLATFORM` | `"normal"` | **`"doiot"`** | `"onenet"` |
| 鉴权 | ClientId=`<#IMEI>`，用户名 `doiot`，密码 `web` | 控制台产品四元组 | OneNET 产品三元组 |
| 专栏 | [MQTT 连接](mqtt.md) | 本篇 | [MQTT 连接第 9 节](mqtt.md#9-平台鉴权tls遗嘱) |

主机写成 `mqtts.doiot.cn`、平台写成 `"doiot"`，或拿测试账 `doiot` / `web` 去连 `5giot.cn`，都连不上。

```lua
控制台建产品 ──抄四元组──► AT+MQTTPLATFORM="doiot" + MQTTAUTH + 主题
UART 数据口 ──AT+DTUPSUP──► 任务 N（MQTT）发布槽 ──► 5giot.cn:1883
平台下发（已订阅）──AT+DTUPSDN──► UART（`io*` 由固件截走，不透传）
```

| | 值 |
| --- | --- |
| 控制台 | [https://5giot.cn](https://5giot.cn/) |
| Broker | `5giot.cn`（**不是** `mqtts.doiot.cn`） |
| 端口 | `1883`（明文，`ssl_level` 保持 0） |
| 平台 | `"doiot"`（网页里叫 **度云**；和 `"onenet"` 一样是云平台类型） |
| 用户名 | 产品「认证账号」 |
| 密码 | 产品「认证密码」 |
| ClientId | 固件拼 `S&<IMEI>&<产品编号>&<用户ID>`，**不要**把 auth1 当成 ClientId 手填 |

`AT+MQTTAUTH` 四段与控制台字段一一对应：

| 控制台 | 出现位置 | `MQTTAUTH` | 用途 |
| --- | --- | --- | --- |
| 产品编号 | 产品详情 · 基本信息 | **auth1** | 主题前缀；参与拼 ClientId |
| 认证账号 | 同上 | **auth2** | MQTT Username |
| 认证密码 | 同上 | **auth3** | MQTT Password |
| 用户 ID | 顶栏「用户 ID:」，不是产品页 | **auth4** | 参与拼 ClientId |

主题里的设备名用 IMEI。配置里写 `"<#IMEI>"`，连上时按 `[maping]` 展开成本机 IMEI。

```text
订阅（平台 → 设备）  /<产品编号>/<#IMEI>/function/get
发布（设备 → 平台）  /<产品编号>/<#IMEI>/function/post
```

载荷是 **JSON 数组**（TAILRAW）。连上后串口常见 `+MQTT-CONNECT:1,"5giot.cn",1883`。设备信息会上到 `/{产品编号}/{IMEI}/info/post`，`io*` 状态会上到 `/{产品编号}/{IMEI}/property/post`——这两路主题由固件在 `"doiot"` 平台下自动发，不必手配订阅/发布槽。

---

## 2. 控制台：产品、物模型、四元组

1. 打开 [https://5giot.cn](https://5giot.cn/)，未注册先注册。登录后顶栏记下 **用户 ID**。
2. **设备管理 → 产品管理 → 新增**。建议：设备类型 **直连设备**，通讯协议 **JSON解析协议**，传输协议 **MQTT**，定位方式 **设备定位**。
3. **查看详情 → 基本信息**，抄下 **产品编号、认证账号、认证密码**。这三项之后每台设备都要用。
4. **产品模型** 里加物模型。JSON 的 `"id"` 必须等于 **模型标识**（不是中文名称）。标识符不能重复。
5. 点 **发布产品**。未发布的产品不要拿去连。

开发板常见五条（名称可自定，**标识符**建议对齐）：

| 名称 | 标识符 | 类别 | 类型 | 说明 |
| --- | --- | --- | --- | --- |
| 调速 | `speed` | 功能 | 枚举 | 如 0% / 30% / 60% / 100% |
| LED | `io2` | 功能 | 布尔 | `io*` → 固件直接改 GPIO2，不透传 |
| 按键 | `io0` | 功能 | 布尔 | → GPIO0 |
| 温度 | `temp` | 属性 | 小数 | 上报用 |
| 数据 | `data` | 功能 | 字符串 | 上报 / 下发透传 |

`io*` 的脚位以当前产品硬件表为准，见 [hardware](../../hardware/README.md)。标识是 `io` + **GPIO 号**，不是焊盘名。

**不要**在「设备管理 → 设备管理」里手工加边缘网关那类设备。IMEI 走第 8 节分组添加，或 AT 连上后平台自动出现。

下面 AT 示例里的 `<产品编号>` `<认证账号>` `<认证密码>` `<用户ID>` **一律换成你控制台里的值**，不要抄别人教程截图里的账号。

---

## 3. 联调前：版本与驻网

要的是度云 **RTU** 应用，不是裸芯片 AT。`ATI` 第二行应是 `NT26-…-RTU-…` 一类版本名。

```lua
AT
OK

ATI
doiot
<应用版本名>
<编译时间>

OK

AT+IMEI
+IMEI: "<15位数字>"

OK

AT+ICCID
+ICCID: "<20位左右数字>"

OK

AT+CEREG
+CEREG: 1

OK

AT+ISLINK
+ISLINK: 1

OK
```

`CEREG` 为 `1` 或 `5` 表示已注册；`3` 通常是卡欠费或锁卡。`ISLINK` 为 `1` 再配 MQTT。IMEI / ICCID 建议记下来，和平台设备列表对照。

---

## 4. AT 接入

目标：通道 1 连 `5giot.cn`，平台 `"doiot"`，UART1 与通道 1 互透。写完配置**默认不拆已经建立的连接**，按产品流程 `AT+RESET` 后再生效。

把尖括号段换成自己的四元组后再发：

```lua
AT+DTUPSUP=1,"1"
+DTUPSUP: 1,"1"

OK

AT+DTUPSDN=1,"6[1]"
+DTUPSDN: 1,"6[1]"

OK

AT+MQTTPLATFORM=1,"doiot"
+MQTTPLATFORM: 1,"doiot"

OK

AT+MQTT=1,"5giot.cn",1883
+MQTT: 1,"5giot.cn",1883

OK

AT+MQTTAUTH=1,"<产品编号>","<认证账号>","<认证密码>","<用户ID>"
+MQTTAUTH: 1,"<产品编号>","<认证账号>","<认证密码>","<用户ID>"

OK

AT+MQTTSUB=1,1,"/<产品编号>/<#IMEI>/function/get",0
+MQTTSUB: 1,1,"/<产品编号>/<#IMEI>/function/get",0

OK

AT+MQTTPUB=1,1,"/<产品编号>/<#IMEI>/function/post",0,0
+MQTTPUB: 1,1,"/<产品编号>/<#IMEI>/function/post",0,0

OK

AT+DTUTASK=1,1,"MQTT"
+DTUTASK: 1,1,"MQTT"

OK

AT+RESET
+RESET

OK
```

`MQTTAUTH` 四个字符串都会入库；只写 auth1 会把 2～4 清成空串。主题里的产品编号必须和 auth1 **同一个数**。`<#IMEI>` 不要改成本机数字（除非你故意不用映射）。

复位后查一眼：

```lua
AT+MQTTPLATFORM=1?
AT+MQTTAUTH=1?
AT+MQTTSUB=1?
AT+MQTTPUB=1?
AT+DTUTASK=1?
AT+DTUSTATE=1
```

通道起来后应看到类似 `+MQTT-CONNECT:1,"5giot.cn",1883`。

TLS 默认关。若以后要 MQTTS，先按 [ssl.md](../manual/ssl.md) 写入证书组，再 `AT+MQTTCFG` 的 `ssl_id` / `ssl_level`，然后复位。当前官方接入走明文 1883。

---

## 5. 透传

路由 `1` 默认子通道 1：UART1 的每一包发到 **通道 1 的发布槽 1**（主题即 `/<产品编号>/<#IMEI>/function/post`）。平台推到已订阅 `…/function/get` 的消息，送到 UART1（`6[1]`）。

MCU 只要往数据口写 JSON 数组即可，不必每包套 `AT+MQTTSYNC`。**AT 口和透传数据口尽量分开。** 配置走 USB AT / 主串口；业务数据走另一路 UART。同一口既当 AT 又当透传时，以 `AT` 开头的行会被当指令。

查询：

```lua
AT+DTUPSUP=1?
AT+DTUPSDN=1?
```

网页方案若勾了「下发串口通道」1 和 2，相当于下行还可到 UART2。纯 AT 最小集只接到 UART1。路由写法见 [路由专栏](route.md)。

---

## 6. 上报与下发

控制台：**设备管理 → 数据采集**。上下行都是 JSON **数组**，不是单个对象：

```json
[{"id":"<物模型标识符>","value":<值>}]
```

`id` 必须等于物模型标识。字符串 `value` 加引号；数值型不要加引号。多属性可拼在同一个数组里。

```json
[{"id":"temp","value":35.8}]
[{"id":"data","value":"<#IMEI>->度云物联平台测试"}]
[{"id":"temp","value":35.8},{"id":"data","value":"<#IMEI>->度云物联平台测试"}]
```

载荷里的 `<#IMEI>` 同样按映射展开。

串口透传：MCU 直接发上面这种数组。AT 口主动发一包（主题当场指定，不写进发布槽）：

```lua
AT+MQTTSYNC=1,"/<产品编号>/<#IMEI>/function/post",0,0,1,[{"id":"temp","value":35.8}]
+MQTTSYNC: 1,"/<产品编号>/<#IMEI>/function/post",0,0,1,<len>

OK
```

最后一个逗号之后是 **TAILRAW**，JSON 里的逗号算载荷，不会再被拆成参数。连续上报、不能堵 AT 口用 `AT+MQTTASYNC`，语义见 [MQTT 连接专栏第 8 节](mqtt.md#8-同步与异步)。

平台在数据采集里点下发，设备应在已订阅的 `…/function/get` 上收到同样形状的数组。非 `io*` 的项按 `DTUPSDN` 出串口。

---

## 7. io* 与 GPIO

标识符匹配 `io` + 数字（如 `io2`、`io0`）时，**RTU 在平台类型为 `"doiot"` 时解析后直接改 GPIO**，**不再往 UART 透传**。第三方自己写的 MQTT 客户端没有这套固件约定，要自己解析 JSON。

- 例：`io2` → GPIO2，`io0` → GPIO0
- 下行 `value` 用字符串 `"0"` / `"1"`（关 / 开）
- 解析成功后，模组把当前 IO 状态发到 `/{产品编号}/{IMEI}/property/post`
- Lua 工程里的 `require("gpio")` **不会**自动吃 `io*`；那是 RTU MQTT 平台类型 = 度云时的行为

下发了 `io2` 却从串口漏出 JSON：标识不是 `io`+数字，或平台不是 `"doiot"`，或任务还没按新配置复位生效。

---

## 8. 网页远程配参（可选）

和 AT 写的是**同一套** MQTT / 路由参数。适合量产、批量改参。单台接入仍以 [第 4 节](#4-at-接入) 为主。

1. **边缘网关 → 分组管理 → 新建分组**（型号选 NT26）。
2. 该行 **设备管理 → 添加设备**：贴 IMEI（少量）或上传 Excel（批量）。**不要**在「设备管理 → 设备管理」里手工加。
3. 返回分组行 **参数配置**：
   - **基本参数**：打开 **自动更新**。SIM 建议自动（先 SIM1，注册不上再 SIM2）。在线调试默认关（另占一路 MQTT，费流量）。
   - **SOCKET/MQTT → 网络通道一**：启动、协议 **MQTT**、TLS 关、平台类型 **度云**，填用户 ID / 产品编号 / MQTT 账号 / MQTT 密码。
4. 点 **确定**（平台配置版本号会加）。模块只在**开机过程**拉配置，改完要 **重新上电并驻网**。
5. 若模块内部版本号已经等于平台版本号，**不会再拉**。再进参数配置点一次确定（版本自增），再重启模组。

串口成功顺序（版本名随镜像变）：

1. 底层开机日志（`ECRDY` 一类，关不掉）
2. `+VERSION: "NT26-…-RTU-…"`
3. `+SIM: 1,"READY"`
4. `+WEBCONFIG: "START"` → 驻网 → `+WEBCONFIG: "END"`
5. 更新成功后自动重启，再一次 SIM / 驻网
6. `+MQTT-CONNECT:1,"5giot.cn",1883`

云配置策略指令见 [AT+CLDCFG](../manual/rtu.md#9-atcldcfg)。拉配置依赖分组里已添加本机 IMEI，且「自动更新」已开。

---

## 9. 常见失败

| 现象 | 先查 |
| --- | --- |
| 连的不是 5giot / 鉴权失败 | 平台必须 `"doiot"`，主机 `5giot.cn` 端口 `1883`；四元组是否从**当前登录账号**抄的 |
| 把 auth1 写成 IMEI 或 ClientId | `"doiot"` 下 auth1 是**产品编号**；ClientId 由固件拼 |
| 主题对不上 | `…/<产品编号>/<#IMEI>/function/get|post`，产品编号与 auth1 一致 |
| 写完 AT 不连 | 是否 `AT+RESET`；`DTUTASK` 是否 MQTT 且使能 |
| `CEREG=3` / 不驻网 | 物联网卡欠费、锁卡、机卡分离；4G 天线 |
| USB 供电乱重启 | 供电要稳；PC USB 建议加 **470μF 以上** 电容 |
| 网页改了参模块没变 | 「自动更新」；点确定抬版本号；重启；看 `WEBCONFIG` 再 `MQTT-CONNECT` |
| 下发 IO 没动作、串口漏 JSON | 标识必须是 `io`+数字；`value` 用 `"0"`/`"1"`；平台是 `"doiot"` |
| 数据采集没有设备 | 边缘网关里加过 IMEI，或 AT 已 CONNECT；开机后再看列表 |
| 当成 `mqtts.doiot.cn` 去配 | 那是普通 MQTT **测试服务器**，不是本平台。本篇主机必须 `5giot.cn`，平台 `"doiot"`，账密来自控制台。测试口见 [MQTT 连接专栏](mqtt.md) |
| 测试账 `doiot` / `web` 去连 5giot | 度云物联要产品编号 / 认证账号 / 认证密码 / 用户 ID |

脚本里自己 `mqtt.open` **不会**按 `"doiot"` 拼 ClientId，必须手写 `S&` + IMEI + `&` + 产品编号 + `&` + 用户 ID。官方模组接入以本篇 AT 为准。Lua API 见 [mqtt](../../api/network/mqtt.md)。

---

## 10. 对照手册

| 要查 | 去 |
| --- | --- |
| `MQTT` / `MQTTAUTH` / `MQTTPLATFORM` / `MQTTSUB` / `MQTTPUB` / `MQTTSYNC` | [mqtt.md](../manual/mqtt.md) |
| `DTUTASK` / `DTUPSUP` / `DTUPSDN` / `CLDCFG` | [rtu.md](../manual/rtu.md) |
| `1` / `6[1]` 怎么写 | [route.md](../manual/route.md) / [路由专栏](route.md) |
| `ATI` / `IMEI` / `ICCID` | [info.md](../manual/info.md) |
| `CEREG` / `ISLINK` / `RESET` | [netstat.md](../manual/netstat.md) |
| GPIO 脚 | [hardware](../../hardware/README.md) |
| `[mqtt.N]` 的 `platform` × `auth*` | [rtu_config 第 10.2 节](../../api/rtu_config/rtu_config.md#102-platform--auth联合) |
| 普通 MQTT / 演示口 | [MQTT 连接专栏](mqtt.md) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-20 | 首版：度云物联（玄武）`5giot.cn` + 平台 `"doiot"`；控制台四元组、AT 接入、透传、JSON、`io*`、网页远程配参 |
| 1.0.1 | 2026-09-20 | 对照普通 MQTT 测试口 `mqtts.doiot.cn`：本篇是云平台（与 OneNET 同类），不是那台通用测试服务器 |
