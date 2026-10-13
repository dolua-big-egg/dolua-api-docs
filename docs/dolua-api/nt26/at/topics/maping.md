# 通配符（maping）

**文档版本** `1.0.0`

载荷、主题、URL、心跳包、注册包、IO 上报模板、短信转发模板里的 `<#名字>`，在真正发出去之前换成当时的值。配置段是 [`[maping]`](../../api/rtu_config/rtu_config.md#18-maping)，AT 开关是 [`AT+DEVICECFG`](../manual/sys.md#11-atdevicecfg) 的 `map.*`。

名字区分大小写。认不出的标记原样留下。认得、但这一下拿不到值时，换成四个字符 `null`。

---

## 目录

- [1. 标记怎么写](#1-标记怎么写)
- [2. 哪条路径会展开](#2-哪条路径会展开)
- [3. 匹配规则](#3-匹配规则)
- [4. 固定名字](#4-固定名字)
- [5. IO 通配](#5-io)
- [6. 短信专用](#6-短信专用)
- [7. 插入原始字节](#7-hex)
- [8. 写在哪](#8-写在哪)
- [9. 常见写错](#9-常见写错)
- [10. 对照手册](#10-对照手册)
- [修订记录](#修订记录)

---

## 1. 标记怎么写

一对尖括号，井号贴在左括号后面，右括号结束：

```lua
<#IMEI>
前缀-<#CSQ>-后缀
<#IO0><#COMMA><#IOALL>
```

从左往右扫一遍。换进去的内容里如果再出现 `<#…>`，不再展开第二轮。

`<#>` 四个字符不够构成名字，按普通文本发出。名字最长 510 字节；更长的整段 `<#…>` 保持原文。

展开后比原文多出来的字节，上限 **4096**。超出的丢掉。

---

## 2. 哪条路径会展开

先看总开关 `map.all`，再看这一条路径自己的开关。两个都是 `1` 才展开。出厂每一项都是 `1`。

开关在**开机时**读入。`rtu_config.cfg` 的 `[maping]` 和 `AT+DEVICECFG="map.*"` 只改盘上的值，这次运行仍按开机那一份。要换开关，改完重启。

值只能是十进制 `0` 或 `1`。

| key | 展开发生在 |
| --- | --- |
| `map.all` | 总闸。`0` 时下面全部不展开，标记原样发出。短信模板也看这一项 |
| `map.sock` | Socket 同步/异步发送的载荷 |
| `map.http` | HTTP 响应体 |
| `map.http_url_header` | HTTP 的 URL、Header |
| `map.at_http` | `AT+HTTPREQ` 的 body |
| `map.mqtt_publish` | MQTT 发布载荷 |
| `map.mqtt_subscribe` | MQTT 订阅主题 |
| `map.mqtt_triplet` | ClientId / 用户名 / 密码 |
| `map.mqtt_will` | 遗嘱消息 |
| `map.mqtt_topic` | 发布主题、遗嘱主题 |
| `map.lua_write` | Lua `rtu.write` |
| `map.sock_reg` | Socket 注册包 |
| `map.mqtt_reg` | MQTT 注册包 |
| `map.sock_heart` | Socket 心跳 |
| `map.mqtt_heart` | MQTT 心跳 |
| `map.dtu_log` | DTU 日志（预留，当前没有出口走到这里） |
| `map.io_change` | IO 变化上报、定时上报的模板 |
| `map.update` | 透传上行。走透传的 HTTP 也归这里，不归 `map.http` |
| `map.down` | 透传下行 |
| `map.lbs_timer` | LBS 定时上报里类型 2 的自定义文本 |
| `map.rtu_write` | `AT+RTUWRITE` / `AT+RTUWRITEQ` |

短信转发模板**没有** `map.sms`。只看 `map.all`：`1` 就展开，`0` 就原样发模板。

某一条路径的开关是 `0` 时，这一路整包不扫描，`<#IMEI>` 会原样出现在发出去的字节里。

---

## 3. 匹配规则

1. 先按整段名字精确比对。`<#IMEI>` 对上 `IMEI`，不会再去试通配。
2. 对不上，再看登记项里带 `~` 的模式。`~` 吃掉中间任意长度的一段（可以是空），`~` 左边和右边必须逐字相同。当前只有 `IO~`。
3. 仍然对不上：整段 `<#名字>` 原样留下。
4. 对上了，但这一下没有值：换成 `null`（四个 ASCII 字符，不是空，也不是 JSON 的 null 类型）。
5. 对上了，回调没有写入任何字节：标记被拿掉，左右文本接在一起。当前只有 `<#VBAT>` 是这种。

名字区分大小写。`<#imei>`、`<#Imei>` 都对不上 `IMEI`，会原样留下。

---

## 4. 固定名字

下面这些在任何被放行的路径上都能写。读不到时是 `null`，除非该行另有说明。

| 标记 | 展开成 |
| --- | --- |
| `<#IMEI>` | 15 位 IMEI |
| `<#ICCID>` | 20 位 ICCID |
| `<#IMSI>` | 15 位 IMSI |
| `<#CSQ>` | 十进制 CSQ，与 `AT+CSQ` 同一个数 |
| `<#LBS>` | `经度,纬度`。用的是最近一次定位缓存，中间一个逗号，没有空格 |
| `<#LBS_LAT>` | 纬度文本 |
| `<#LBS_LON>` | 经度文本 |
| `<#VBAT>` | 空。名字已登记，当前不输出电压，标记被删掉 |
| `<#LAC>` | 位置区，**小写十六进制**，无 `0x`，不补零 |
| `<#CELL>` | 小区号，格式同 `LAC` |
| `<#TIME>` | 模组日历时间 `年-月-日 时:分:秒`。数字不补零，例如 `2026-10-8 17:5:3`。读失败时是 `0-0-0 00:00:00` |
| `<#UTC>` | Unix 秒，十进制无符号整数 |
| `<#ENTER>` | 两个字节 `0x0D 0x0A` |
| `<#COMMA>` | 一个逗号 `,` |
| `<#QUOTE>` | 一个双引号 `"` |

`<#LBS>` 的顺序是经度在前、纬度在后。还没定位成功、缓存无效时，这三项都是 `null`。

`<#LAC>` / `<#CELL>` 的例子：小区十进制 6699 展开成 `1a2b`。

`<#ENTER>`、`<#COMMA>`、`<#QUOTE>` 用来在**已经存进配置的模板**里放进换行、逗号、引号。AT 行上的引号仍然是 AT 语法，展开发生在发出去的时候。HTTP 头要换行时写 `<#ENTER>`，不要在同一条 AT 里嵌真实换行。

```lua
AT+MQTTPUB=1,1,"/device/<#IMEI>",0,0
AT+MQTTSYNC=1,"/device/<#IMEI>",0,0,1,csq=<#CSQ><#ENTER>
```

第二条发出的载荷类似 `csq=18` 再加回车换行。主题里的 `<#IMEI>` 在连上或发布时换成 15 位数字。

---

## 5. IO 通配 {#5-io}

`IO~` 匹配所有以 `IO` 开头的名字。`<#IO0>` 里被吃掉的那段是 `0`，`<#IOALL>` 里是 `ALL`。

脚号是 **GPIO 编号 0～38**，一共 39 只。配置段 `[io.N]` 的 N 从 1 起：`<#IO0>` 就是 `[io.1]` 那只脚，`<#IO38>` 就是 `[io.39]`。

被屏蔽的脚读出来是 `0`。

| 标记 | 展开成 |
| --- | --- |
| `<#IO0>` … `<#IO38>` | 该脚当前电平，十进制 `0` 或 `1` |
| `<#IO>` | 空。`~` 没吃到脚号，标记被删掉 |
| `<#IO01>` | 与 `<#IO1>` 相同，前导 0 按十进制解析 |
| `<#IOALL>` | 39 个字符，从 `<#IO0>` 到 `<#IO38>`，每位是字符 `0` 或 `1`，没有逗号 |
| `<#IO_ID>` | 这一次 IO 上报里触发的 GPIO 编号，十进制。不在 IO 上报里是 `null` |
| `<#IO_STATE>` | 这一次触发的电平 `0` 或 `1`。不在 IO 上报里是 `null` |
| `<#IOSTATE>` | 有本次触发参数时与 `<#IO_STATE>` 相同；没有时用最近一次上报记下的电平，还没报过是 `0` |
| `<#IO39>` 以及再大的号、或夹了非数字（除上面三个名字） | `null` |

`<#IOALL>` 的例子：只有 GPIO0 为高，其余为低，结果是 `1` 后面 38 个 `0`。

`<#IO_ID>` / `<#IO_STATE>` 只在 IO 变化上报、定时上报的模板里有本次触发参数。写在 MQTT 发布、心跳、`AT+RTUWRITE` 里会变成 `null`。

模板里要带上「哪只脚、什么电平、全部脚」：

```lua
id=<#IO_ID><#COMMA>st=<#IO_STATE><#COMMA>all=<#IOALL>
```

不要写 `<#IO~>`。那会精确对上模式名本身，又没有脚号，结果是空。

---

## 6. 短信专用

只在短信转发、且 `forward_msg_mode=3` 的模板里有内容。其它路径，以及短信路径上号码或正文为空，都是 `null`。

| 标记 | 展开成 |
| --- | --- |
| `<#SENDER>` | 来信号码，最长 63 字节 |
| `<#SMS_MSG>` | 短信正文，最长 950 字节 |

模板例子：

```lua
from=<#SENDER><#ENTER><#SMS_MSG>
```

短信这一路只受 `map.all` 管，见 [第 2 节](#2-哪条路径会展开)。mode、模板长度见 [`[sms]`](../../api/rtu_config/rtu_config.md#27-sms--smsn) 和 [短信手册](../manual/sms.md)。

---

## 7. 插入原始字节 {#7-hex}

`hex:` 前缀不查名字表，直接把后面的十六进制解成字节插进去。

```lua
<#hex:0D0A>
<#hex:2C>
```

第一条是回车换行，与 `<#ENTER>` 相同。第二条是一个逗号，与 `<#COMMA>` 相同。

规则：

- 十六进制字符 `0-9`、`a-f`、`A-F` 都可以，大小写混用也行。
- 位数必须是偶数。奇数位、出现非十六进制字符、解出来超过 256 字节：整段 `<#hex:…>` 原样留下。
- 解出来的字节不再做占位符展开。`<#hex:3C23494D45493E>` 得到的就是 7 个字节 `<#IMEI>` 本身。

心跳、注册包在 AT 里本来就是十六进制文本（`3C23494D45493E` 表示配置里的 `<#IMEI>` 这 7 个字符）。那是外层编码。本节的 `<#hex:…>` 是占位符展开时再解一层。两套叠在一起时，内层不会再展开成 IMEI 数字。

---

## 8. 写在哪

| 场景 | 标记写在 | 还要打开 |
| --- | --- | --- |
| MQTT 主题、ClientId | `AT+MQTTSUB` / `AT+MQTTPUB` / `AT+MQTTAUTH` 的字符串，或 `[mqtt.N]` | `map.mqtt_topic` 或 `map.mqtt_triplet`，外加 `map.all` |
| MQTT 发出的载荷 | `AT+MQTTSYNC` / `AT+MQTTASYNC` 逗号后的原始字节 | `map.mqtt_publish` |
| Socket 发出的载荷 | `AT+SOCKSYNC` / `AT+SOCKASYNC` 的载荷 | `map.sock` |
| 心跳 / 注册 | `[task.N.heart]` / `[task.N.reg]` 的 hex 包，或 `AT+DTUHEART` / `AT+DTUREG` | `map.sock_heart` / `map.mqtt_heart` / `map.sock_reg` / `map.mqtt_reg` 里对应的那一项 |
| HTTP URL / 头 | `AT+HTTPURL` | `map.http_url_header` |
| `AT+HTTPREQ` body | 请求体 | `map.at_http`。展开失败这条会 `"error maping"` |
| 透传上行 | 串口进来、再被转出去的那一包 | `map.update` |
| `AT+RTUWRITE` | 路由后面的原始字节 | `map.rtu_write` |
| IO 上报 | `[io.template.N]` 的 `tpl_bytes` | `map.io_change` |
| LBS 定时自定义文本 | `[lbs] tmr_rpt_data`，且 `tmr_rpt_type=2` | `map.lbs_timer` |
| 短信转发模板 | `[sms] forward_msg_template` | 只看 `map.all` |

Socket 同步/异步发送如果展开失败（缓冲不够一类），改发**原始**载荷，不因此报错。MQTT 发布在主题或载荷展开失败时是 `"error send"`，不会改发原文。以各指令手册为准。

---

## 9. 常见写错

| 现象 | 原因 |
| --- | --- |
| 线上仍是 `<#IMEI>` 六个字符加括号 | 这一路开关是 0，或总闸是 0，或大小写不对 |
| 出现 `null` | 名字对了，值暂时没有：没插卡、还没定位、不在短信/IO 上报路径上 |
| `<#VBAT>` 消失且没有数字 | 当前就是空展开 |
| `<#LBS>` 纬度经度反了 | 顺序固定是经度、纬度 |
| `<#IO1>` 不是 `[io.1]` | `<#IO1>` 是 GPIO 1，`[io.1]` 是 GPIO 0 |
| `<#IOALL>` 很短或带逗号 | 实际是 39 个 `0`/`1` 字符，没有分隔符 |
| 改了 `map.all` 马上试没变化 | 开关下次开机才进运行时 |
| 心跳里写了 `<#IMEI>` 却发出这八个字符的 hex | 心跳包位是十六进制文本，要写 `3C23494D45493E`，展开发生在解码之后 |

---

## 10. 对照手册

| 内容 | 位置 |
| --- | --- |
| `[maping]` 每个开关 | [rtu_config 第 18 节](../../api/rtu_config/rtu_config.md#18-maping) |
| `AT+DEVICECFG="map.*"` | [sys.md](../manual/sys.md#11-atdevicecfg) |
| IO 模板 `tpl_bytes` | [rtu_config 第 19 节](../../api/rtu_config/rtu_config.md#19-io--ion--iotemplaten) |
| 短信模板 | [sms.md](../manual/sms.md)、[rtu_config 第 27 节](../../api/rtu_config/rtu_config.md#27-sms--smsn) |
| MQTT 主题里的 `<#IMEI>` | [MQTT 专栏](mqtt.md)、[度云物联专栏](5giot.md) |
| 心跳 hex 与占位符 | [MQTT 专栏](mqtt.md) |

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-10-08 | 首版：全部占位符、`IO~`、短信 `SENDER`/`SMS_MSG`、`<#hex:…>`、各路径开关 |
