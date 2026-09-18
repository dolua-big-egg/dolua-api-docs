#  系统（日志 / 文件系统 / 诊断 / 整机配置 / 恢复出厂）

**文档版本** `1.0.0`

日志输出口、文件系统容量与根目录列表、堆与线程诊断、立刻改睡眠档、真随机数、整机 KV、云配置编号、恢复出厂、远程调试 MQTT。行格式见 [convention.md](convention.md)。

本篇**不收**产测指令。ADC 在 [io.md](io.md)。Lua / 配置对照：[`[log]`](../api/rtu_config/rtu_config.md#16-log)、[`[monitor]`](../api/rtu_config/rtu_config.md#24-monitor)、[`[loader]`](../api/rtu_config/rtu_config.md#25-loader)、[`[dbg]`](../api/rtu_config/rtu_config.md#28-dbg)。`CFGID` 与 `[task] config_id` 同一份。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+LOG](#3-atlog)
- [4. AT+PLOG](#4-atplog)
- [5. AT+FSINFO](#5-atfsinfo)
- [6. AT+FSLIST](#6-atfslist)
- [7. AT+HEAPINFO](#7-atheapinfo)
- [8. AT+THREAD](#8-atthread)
- [9. AT+PMU](#9-atpmu)
- [10. AT+TRNG](#10-attrng)
- [11. AT+DEVICECFG](#11-atdevicecfg)
- [12. AT+CFGID](#12-atcfgid)
- [13. AT+FACTORY](#13-atfactory)
- [14. AT+ONLINEDBG](#14-atonlinedbg)
- [15. 错误一览](#15-错误一览)
- [16. 联调顺序](#16-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| LOG / PLOG | 失败是 `+LOG: 0` / `+PLOG: 0` 再 `ERROR`，**不是** CME，也不是 `"error reason"` |
| FSINFO / FSLIST / TRNG | 失败 `+CME ERROR`。`FSINFO` / `FSLIST` **没有**测试命令 |
| HEAPINFO / THREAD | 查询总会 `OK`。线程细节打到系统日志，AT 只报 `DUMP DONE` |
| PMU | **只有设置和测试**，无 `AT+PMU?`。参数错时引擎回 `ERROR`（无 `+PMU`） |
| DEVICECFG | 多数短 reason；`mrst.*` 分钟越界 CME **141**，cron 非法 **142** |
| FACTORY | `AT+FACTORY`（无参）就是**全量恢复**，不是查询。没有 `AT+FACTORY?` |
| 无参查询 | `LOG` / `PLOG` / `FSINFO` / `FSLIST` / `HEAPINFO` / `THREAD` / `CFGID` / `ONLINEDBG`：`AT+XXX` 与 `AT+XXX?` 等价 |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+LOG` | `=?` | 无参 | `<0～4>` | 系统日志输出口（与 `[log] output` 同一份） |
| `AT+PLOG` | `=?` | 无参 | `<0\|1>[,password]` | 私密日志。开必须带密码 |
| `AT+FSINFO` | 无 | 无参 | 无 | LittleFS 容量 |
| `AT+FSLIST` | 无 | 无参 | 无 | 根目录普通文件 |
| `AT+HEAPINFO` | 无 | 无参 | 无 | 堆占用（KB） |
| `AT+THREAD` | 无 | 无参 | 无 | 把线程状态打到日志 |
| `AT+PMU` | `=?` | 无 | `<0～3>` | **立刻**改睡眠档 |
| `AT+TRNG` | `=?` | 无 | `<1～256>` | 真随机 HEX |
| `AT+DEVICECFG` | `=?` | `?` 全量；`"<key>"` 单项 | `"<key>",<TAILRAW>` | 整机 KV（含 `mrst.cron`） |
| `AT+CFGID` | `=?` | 无参 | `<id>` | `[task] config_id` |
| `AT+FACTORY` | `=?` | 无参=**全量恢复** | `1` 或 `"<key>"` | 全量或按模块恢复 |
| `AT+ONLINEDBG` | `=?` | 无参 | `<0\|1>,"<id>"` | `[dbg]` 远程调试 MQTT |

---

## 3. AT+LOG {#3-atlog}

系统日志口（不是 Lua `log` 模块的 `log_route`）。与 `[log] output` 同一数字。立刻切并落盘。

| 值 | 输出口 |
| --- | --- |
| 0 | 无 |
| 1 | UART0 |
| 2 | UART1 |
| 3 | UART3 |
| 4 | USB AT（与 AT 应答共用同一 VCOM，日志会挤在一起） |

### 3.1 测试

```lua
AT+LOG=?
```

```lua
+LOG: id(0:none,1:uart0,2:uart1,3:uart3,4:usb at)

OK
```

### 3.2 查询

```lua
AT+LOG
+LOG: 0

OK
```

### 3.3 设置

```lua
AT+LOG=2
+LOG: 2

OK
```

缺参、不是数字、不是 0～4、落盘失败：

```lua
+LOG: 0

ERROR
```

---

## 4. AT+PLOG {#4-atplog}

私密日志开关。与 `[log] private` / `password` 同一套：打开必须带密码；只写密码、不改 `private` 在配置文件里是空操作，本指令打开时密码是第二参。

### 4.1 测试

```lua
AT+PLOG=?
```

```lua
+PLOG: enable(0/1),password(need when enable=1)

OK
```

### 4.2 查询

```lua
AT+PLOG
+PLOG: 0

OK
```

只回 0/1，**不回密码**。

### 4.3 设置

打开必须带字符串密码：

```lua
AT+PLOG=1,"secret"
+PLOG: 1

OK
```

关闭：第二参可省略。

```lua
AT+PLOG=0
+PLOG: 0

OK
```

`enable` 不是 0/1、打开时没密码、底层拒绝：`+PLOG: 0` + `ERROR`。

---

## 5. AT+FSINFO {#5-atfsinfo}

查用户文件系统容量。无测试命令。

```lua
AT+FSINFO
```

或 `AT+FSINFO?`。

```lua
+FSINFO: total=<字节>,used=<字节>,free=<字节>,block_size=<块大小>,total_block=<块数>,block_used=<已用块>

OK
```

字节按块大小×块数折算。读盘失败 → CME **106**。

---

## 6. AT+FSLIST {#6-atfslist}

只列**根目录一层普通文件**（不含子目录）。最多 **2000** 条，超出 `truncated=1`。无测试命令。

```lua
AT+FSLIST
```

```lua
+FSLIST: "/rtu.config",1234
+FSLIST: "/other.txt",80
+FSLIST: meta,files=2,truncated=0

OK
```

没有文件时只有 `meta` 行。列目录失败 → CME **106**（可能已经打出前面的 `+FSLIST` 行）。

---

## 7. AT+HEAPINFO {#7-atheapinfo}

查堆。无测试命令。单位 KB。无失败分支，总是 `OK`。

```lua
AT+HEAPINFO
```

先打主堆 `EC` 三行（历史区间拿不到则 `hist_min_max_free_block=NA`；当前最大块拿不到则 `cur_max_free_block=NA`），再打 `CUST`（本机无第二堆则一行 `CUST,unsupported`），最后 `OK`。

```lua
+HEAPINFO: EC,total_kb=<n>,free_kb=<n>,min_ever_free_kb=<n>,max_block_kb=<n>,free_pct=<n>,alert=<0|1>
+HEAPINFO: EC,hist_min_max_free_block_kb=[<lo>,<hi>)
+HEAPINFO: EC,cur_max_free_block_kb=<n>,range_kb=[<lo>,<hi>)
+HEAPINFO: CUST,unsupported

OK
```

`alert=1` 表示空闲比例已到告警线。`free_pct` 是百分比整数。

---

## 8. AT+THREAD {#8-atthread}

把当前线程名、状态、栈用量打到**系统日志**（要 `AT+LOG` 指到能看的口）。AT 口只报结束。

```lua
AT+THREAD
```

```lua
+THREAD: DUMP DONE

OK
```

无失败分支。申请打印缓冲失败时，细节只在日志里，AT 仍可能 `DUMP DONE`。

---

## 9. AT+PMU {#9-atpmu}

**立刻**改睡眠档，数字 0～3。与 `AT+LP` 的字符串是同一套档位：

| 值 | 与 `AT+LP` 对应 | 测试帮助用名 |
| --- | --- | --- |
| 0 | `normal` | normal |
| 1 | `low_power` | low_power |
| 2 | `low_power2` | ultra_low_power |
| 3 | `psm` | psm_plus |

`LP` 走网络管理切模式；本指令立刻改睡眠深度。日常产品用 `LP` 即可。

### 9.1 测试

```lua
AT+PMU=?
```

```lua
+PMU: mode(0:normal,1:low_power,2:ultra_low_power,3:psm_plus)

OK
```

### 9.2 设置

```lua
AT+PMU=1
+PMU: 1

OK
```

缺参、不是数字、不是 0～3：只回 `ERROR`（没有 `+PMU` / 没有 CME）。**没有查询。**

---

## 10. AT+TRNG {#10-attrng}

生成 1～256 字节真随机数，大写 HEX 字符串（无空格）。无查询。

### 10.1 测试

```lua
AT+TRNG=?
```

```lua
+TRNG: len(1-256)

OK
```

### 10.2 设置

```lua
AT+TRNG=8
+TRNG: "A1B2C3D4E5F60708"

OK
```

| 码 | 可能原因 |
| --- | --- |
| 105 | 缺参、不是数字、长度不是 1～256 |
| 137 | 硬件随机数失败 |

---

## 11. AT+DEVICECFG {#11-atdevicecfg}

按 **key** 读写整机项。第二参是 **TAILRAW**（省略则查询）。`AT+DEVICECFG?` 打全部分组。

`mfg.reset` **只能写、不能带 value**。清 cron：`AT+DEVICECFG="mrst.cron",""`（第二参是空引号，两个字节 `""`）。

`uart.u2_en` / `uart.u3_en` / `netled.*` / `net_led.sleep_keep`：**重启后生效**。`rtu.down` / `rtu.up` 改的是运行时闸；`rtu.down_cfg` / `rtu.up_cfg` 才落盘。

### 11.1 测试

```lua
AT+DEVICECFG=?
```

帮助按 `[MFG]` `[EVT_OUT]` `[MRST]` `[RTU]` `[UART]` `[NETLED]` `[MAP]` 列出全部 key。用法：

```lua
set   : AT+DEVICECFG="key",<TAILRAW>
query : AT+DEVICECFG="key"
query all: AT+DEVICECFG?
clear cron: AT+DEVICECFG="mrst.cron",""
```

### 11.2 查询全部

```lua
AT+DEVICECFG?
```

或 `AT+DEVICECFG`。先分组标题，再 `+DEVICECFG: "<key>",<value>`。`mfg.reset` 全量里显示 `"write-only"`。`mfg.ati` / `mfg.boot_msg` / `mrst.cron` 的 value 带引号。任一组读失败 → `"error read"`。缓冲不够 → `overflow`。申请失败 → `malloc`。

### 11.3 查询 / 设置单项

```lua
AT+DEVICECFG="netled.en"
+DEVICECFG: "netled.en",1

OK
```

`mfg.ati` / `mfg.boot_msg` 查询：先打 `"key",<len>`，再跟原始字节，再 `OK`。`mrst.cron` 查询：先打长度，再单独一行带引号的表达式。

### 11.4 key 一览（按源码，不要用别名）

#### [MFG]

| key | 值 | 说明 |
| --- | --- | --- |
| `mfg.reset` | 无 | 恢复出厂厂商串并落盘。带第二参 → `"mfg.reset needs no value"` |
| `mfg.ati` | 原始字节，**&lt; 128** | `ATI` 第一行厂商串 |
| `mfg.boot_msg` | 同上 | 开机横幅 |
| `mfg.boot_u1_en` | 0/1 | 开机信息打到 UART1 |
| `mfg.boot_u2_en` | 0/1 | UART2 |
| `mfg.boot_u3_en` | 0/1 | UART3 |

#### [EVT_OUT]

全是 0/1。对应事件是否往串口打状态。

| key |
| --- |
| `evt_out.u1_en` / `evt_out.u2_en` / `evt_out.u3_en` |
| `evt_out.net_en` / `evt_out.sim_en` / `evt_out.script_en` |
| `evt_out.ch1_en` / `evt_out.ch2_en` / `evt_out.ch3_en` / `evt_out.ch4_en` |
| `evt_out.cfg_loader_en` / `evt_out.cfg_update_reset_en` / `evt_out.monitor_reset_en` |

`u1_en` 等是串口总闸：关掉后，后面那些独立开关也不会从该口出。

#### [MRST]（与 `[monitor]` 同一套）

分钟类：**0=关**，**1～1440=超时分钟**。越界 CME **141**。`mrst.u_ndata` 写时覆盖 UART1～3 同一值；查询 `u_ndata` 回的是 UART1 那一格。`ch_ndata` / `ch_conn` 同理（通道 1 的值）。

| key | 说明 |
| --- | --- |
| `mrst.u_ndata` | 三路 UART 无 RX 复位（总覆盖） |
| `mrst.u1_ndata` / `u2_ndata` / `u3_ndata` | 单路 |
| `mrst.ch_ndata` | 四路网络通道无下行复位（总覆盖） |
| `mrst.ch1_ndata` … `ch4_ndata` | 单通道 |
| `mrst.ch_conn` | 四路未连接复位（总覆盖） |
| `mrst.ch1_conn` … `ch4_conn` | 单通道 |
| `mrst.reg` | 未驻网复位 |
| `mrst.cron` | cron 表达式。空=关。非法 → CME **142**。最长约 191 字节 |

`chN_ndata` 看下行业务；`chN_conn` 看连接本身。两套可同时开。写成功后会重新加载监控运行态。

#### [RTU]

| key | 说明 |
| --- | --- |
| `rtu.down` | 通道下行透传**运行时**闸（0/1） |
| `rtu.up` | 通道上行透传运行时闸 |
| `rtu.down_cfg` | 同上，**落盘**（`[task] channel_down_en`） |
| `rtu.up_cfg` | 落盘（`channel_update_en`） |

#### [UART]

| key | 说明 |
| --- | --- |
| `uart.u2_en` | UART2 使能，0/1，**重启生效** |
| `uart.u3_en` | UART3 使能，重启生效 |

没有 `uart.u1_en`。

#### [NETLED]

| key | 说明 |
| --- | --- |
| `netled.en` | 驻网灯使能，0/1，重启生效 |
| `netled.bind_io` | GPIO **0～38**，重启生效 |
| `net_led.sleep_keep` | 休眠保持电平 0/1（注意 key 是 `net_led` 不是 `netled`），重启生效 |

#### [MAP]（占位符展开总闸与分项，0/1）

| key |
| --- |
| `map.all` |
| `map.sock` / `map.http` / `map.http_url_header` / `map.at_http` |
| `map.mqtt_publish` / `map.mqtt_subscribe` / `map.mqtt_triplet` / `map.mqtt_will` / `map.mqtt_topic` |
| `map.lua_write` / `map.sock_reg` / `map.mqtt_reg` / `map.sock_heart` / `map.mqtt_heart` |
| `map.dtu_log` / `map.io_change` / `map.update` / `map.down` / `map.lbs_timer` / `map.rtu_write` |

`map.all=0` 时各分项不会展开。LBS 定时自定义文本要 `map.all` 与 `map.lbs_timer` 都为 1。

### 11.5 示例

```lua
AT+DEVICECFG="mrst.reg",30
+DEVICECFG: "mrst.reg",30

OK

AT+DEVICECFG="mrst.cron","0 3 * * *"
+DEVICECFG: "mrst.cron",9
"0 3 * * *"

OK

AT+DEVICECFG="mrst.cron",""
+DEVICECFG: "mrst.cron",0
""

OK

AT+DEVICECFG="mfg.reset"
+DEVICECFG: "mfg.reset"

OK

AT+DEVICECFG="map.all",1
+DEVICECFG: "map.all",1

OK
```

### 11.6 失败

短 reason：`param`、`key`、`read`、`save`、`malloc`、`overflow`、`length`、`key or value`、`mfg.reset needs no value`。

CME：**141**（分钟不是 0 且不是 1～1440）、**142**（cron 非法）。这两种**没有** `+DEVICECFG` 行。

---

## 12. AT+CFGID {#12-atcfgid}

云端配置编号，与 `[task] config_id`、配置加载器比对用的是同一个数。范围 0～4294967295。

### 12.1 测试

```lua
AT+CFGID=?
```

```lua
+CFGID: (config_id)
config_id:0-4294967295
set: AT+CFGID=<config_id>
query: AT+CFGID?

OK
```

### 12.2 查询 / 设置

```lua
AT+CFGID?
+CFGID: 0

OK

AT+CFGID=1001
+CFGID: 1001

OK
```

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参或不是数字 |
| `config_id` | 负数 |
| `read` | 读任务配置失败 |
| `save` | 落盘失败 |

---

## 13. AT+FACTORY {#13-atfactory}

把业务配置恢复出厂。**全量**会按模块表逐个恢复（APN、MQTT、Socket、HTTP、LBS、日志、监控、脚本、调试等）。

**`AT+FACTORY`（什么参数都没有）就是全量恢复**，不是查询。不要随手发。没有 `AT+FACTORY?`。

产测管脚/射频指令不在本手册。

### 13.1 测试

```lua
AT+FACTORY=?
```

```lua
+FACTORY: (param)
full reset: AT+FACTORY or AT+FACTORY=1
module reset: AT+FACTORY="key" (e.g. apn, mqtt, sock, http, ...)
help: AT+FACTORY=?

OK
```

### 13.2 全量

下面三种等价，成功都回 `"all"`：

```lua
AT+FACTORY
+FACTORY: "all"

OK
```

```lua
AT+FACTORY=1
```

失败 → `"error reset"`。

### 13.3 按模块

```lua
AT+FACTORY="lbs"
+FACTORY: "lbs"

OK
```

key 可带或不带引号（`AT+FACTORY=apn` 与 `"apn"` 都行）。`socket` 当作 `sock`。

**已登记的 key（按恢复顺序）**

| key | 恢复什么 |
| --- | --- |
| `apn` | 默认 APN（空 APN、无鉴权） |
| `mqtt` | 四路 MQTT |
| `dbg` | 远程调试 MQTT（`[dbg]`） |
| `sock` | 四路 Socket（别名 `socket`） |
| `http` | 五路 HTTP |
| `event_out` | 事件输出口 |
| `netio` | 通道状态 IO |
| `net_led` | 驻网灯 |
| `lp` | 网络管理 / 切卡策略（`SIMCFG` 那套） |
| `wtg` | 看门狗相关 |
| `uart` | 三路 UART |
| `script` | 脚本包存储 |
| `log` | 日志口与私密开关 |
| `task` | RTU 任务（含 `CFGID`） |
| `maping` | 占位符映射开关 |
| `io` | GPIO 配置 |
| `loader` | 云配置拉取（`[loader]`） |
| `lbs` | `[lbs]` |
| `ssl` | 三组证书 |
| `monitor` | `[monitor]` / `mrst.*` |
| `sms` | 短信通道 |

未知 key → `"error unknown_key"`。空串 → `empty`。超过 127 字节 → `too_long`。剥引号后仍过长 → `key_len`。形态不对 → `param`。该模块恢复失败 → `reset`。

### 13.4 示例

```lua
AT+FACTORY="log"
+FACTORY: "log"

OK

AT+FACTORY="monitor"
+FACTORY: "monitor"

OK
```

全量后建议复位或按产品流程重新加载，正在跑的连接不会全部立刻拆掉。

---

## 14. AT+ONLINEDBG {#14-atonlinedbg}

独立的调试 MQTT（固定调试服务器，主串口双向透传）。**不是** `[mqtt.N]`。与 [`[dbg]`](../api/rtu_config/rtu_config.md#28-dbg) 同一份：`enable` + `id`（最长 **20** 字节）。

写的是落盘。链路要等本次开机的调试初始化；本文件若在调试任务之前套用，**本次开机**就能用新值。

### 14.1 测试

```lua
AT+ONLINEDBG=?
```

```lua
+ONLINEDBG: (enable,id)
enable:0-1, id:max 20 bytes string
set: AT+ONLINEDBG=<enable>,"<id>"
query: AT+ONLINEDBG?

OK
```

### 14.2 查询

```lua
AT+ONLINEDBG?
+ONLINEDBG: 0,""

OK
```

读失败 → `"error read"`。

### 14.3 设置

必须两个参数：数字 + 字符串。

```lua
AT+ONLINEDBG=1,"device01"
+ONLINEDBG: 1,"device01"

OK
```

关调试时 `id` 可以是空串。`enable=1` 时 `id` **不能为空**。

| reason | 可能原因 |
| --- | --- |
| `param` | 少参、类型不对 |
| `enable` | 不是 0/1 |
| `id` | 超过 20 字节；或 `enable=1` 且空串 |
| `save` | 落盘失败 |

---

## 15. 错误一览

### 15.1 `+CME ERROR`

| 码 | 指令 | 含义 |
| --- | --- | --- |
| 105 | TRNG | 长度非法 |
| 106 | FSINFO / FSLIST | 读文件系统失败 |
| 137 | TRNG | 随机数硬件失败 |
| 141 | DEVICECFG `mrst.*` 分钟 | 不是 0 且不是 1～1440 |
| 142 | DEVICECFG `mrst.cron` | 表达式非法 |

### 15.2 短 reason / 特殊形态

| 形态 | 指令 | 含义 |
| --- | --- | --- |
| `+LOG: 0` + `ERROR` | LOG | 参数或设置失败 |
| `+PLOG: 0` + `ERROR` | PLOG | 参数、缺密码或设置失败 |
| `param` / `key` / `read` / `save` / `malloc` / `overflow` / `length` / `key or value` | DEVICECFG | 见 11.6 |
| `mfg.reset needs no value` | DEVICECFG | `mfg.reset` 带了第二参 |
| `param` / `config_id` / `read` / `save` | CFGID | |
| `param` / `empty` / `too_long` / `key_len` / `unknown_key` / `reset` | FACTORY | |
| `param` / `enable` / `id` / `read` / `save` | ONLINEDBG | |
| 引擎 `ERROR`（无 `+PMU`） | PMU | 参数不是 0～3 |

---

## 16. 联调顺序

1. 看系统日志：`AT+LOG=2`（或 4 走 USB AT，注意和 AT 抢同一口）。
2. 要加密日志：`AT+PLOG=1,"<密码>"`。
3. 空间不够先 `AT+FSINFO` / `AT+FSLIST`。
4. 卡死或泄漏：`AT+HEAPINFO`、`AT+THREAD`（先把 LOG 指到能抓的口）。
5. 整机策略：`AT+DEVICECFG?` 对照 `[monitor]` / `[maping]`；改 cron 用 `mrst.cron`。
6. 云配置编号：`AT+CFGID` 与平台下发的 `AT+CFGID=` 对齐（`[loader]` 定时拉配置）。
7. 远程调试：`AT+ONLINEDBG=1,"<设备id>"`，重启或等调试任务起来。
8. 恢复某一类：`AT+FACTORY="lbs"`；全量只在明确要清空时发 `AT+FACTORY=1`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：LOG / PLOG / FSINFO / FSLIST / HEAPINFO / THREAD / PMU / TRNG / DEVICECFG 全 key / CFGID / FACTORY 模块表 / ONLINEDBG |
