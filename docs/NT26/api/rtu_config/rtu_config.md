# rtu_config

**文档版本** `1.0.0`

这不是 `require("…")` 模块。它是模组开机时解析的 **声明式配置文件** `rtu_config.cfg`：只改文件里写到的段和 key，没写到的字段保持机内当前值。Lua 的 [`rtu`](../module/rtu.md)、[`uart`](../peripherals/uart.md)、[`sms`](../module/sms.md)、[`lbs`](../network/lbs.md) 等运行时模块 **读的是这份文件落盘后的业务配置**，不是另起一套通道。

文件落在内置文件系统根路径 **`/rtu_config.cfg`**。工程里把它放进 luaproj 的 **config** 分区（`configs` / `selectedConfig`）。

---

## 目录

- [1. 定位与生效时机](#1-定位与生效时机)
- [2. 框架结构](#2-框架结构)
- [3. 文件语法](#3-文件语法)
- [4. 段名规则](#4-段名规则)
- [5. 值类型](#5-值类型)
- [6. 总覆盖权与覆盖顺序](#6-总覆盖权与覆盖顺序)
- [7. 通道编号对照](#7-通道编号对照)
- [8. 模块一览](#8-模块一览)
- [9. `[sock.N]` / `[socket.N]`](#9-sockn--socketn)
- [10. `[mqtt.N]`](#10-mqttn)
- [11. `[mqtt.N.subscribe.M]` / `[mqtt.N.publish.M]`](#11-mqttnsubscribem--mqttnpublishm)
- [12. `[http.N]`](#12-httpn)
- [13. `[ssl.N]`](#13-ssln)
- [14. `[uart]` / `[uart.N]`](#14-uart--uartn)
- [15. `[lua]`](#15-lua)
- [16. `[log]`](#16-log)
- [17. `[task]` / `[task.N]` / `[task.N.heart]` / `[task.N.reg]`](#17-task--taskn--tasknheart--tasknreg)
- [18. `[maping]`](#18-maping)
- [19. `[io]` / `[io.N]` / `[io.template.N]`](#19-io--ion--iotemplaten)
- [20. `[event_out]`](#20-event_out)
- [21. `[netio.N]`](#21-netion)
- [22. `[net_led]`](#22-net_led)
- [23. `[wtg]`](#23-wtg)
- [24. `[monitor]`](#24-monitor)
- [25. `[loader]`](#25-loader)
- [26. `[lbs]`](#26-lbs)
- [27. `[sms]` / `[sms.N]`](#27-sms--smsn)
- [28. `[dbg]`](#28-dbg)
- [29. 占位符映射](#29-占位符映射)
- [30. 未接入的段](#30-未接入的段)
- [31. 错误与返回约定](#31-错误与返回约定)
- [32. 资源上限](#32-资源上限)
- [33. 选型对照](#33-选型对照)
- [34. 完整示例](#34-完整示例)
- [修订记录](#修订记录)

---

## 1. 定位与生效时机

`rtu_config.cfg` 是 **开机声明式补丁**，不是运行时 API，也不是整机出厂快照。

| 事实 | 含义 |
| --- | --- |
| 路径 | `/rtu_config.cfg`（大小写敏感） |
| 缺失 | 跳过，沿用机内已有 KV / 出厂默认 |
| 空文件 | 视为成功，什么都不改 |
| 只写出现的 key | 未出现的字段 **保持当前机内值** |
| 解析时刻 | 开机很早：在 UART2/3、短信、SSL、HTTP、映射、IO 上报、脚本、RTU 任务、监控、云配置拉取 **之前** |
| 运行时改 AT / Lua | 改的是业务 KV 或 RAM，**不会回写** 本文件 |
| 热改本文件 | YMODEM `_rtu_config_.cmd`、云下发、工具重烧只更新文件；**下次开机**才再解析 |

来源（任选其一，后到的文件覆盖盘上旧文件）：

1. DoLua 工程 config 分区：`doiot_lua_project.luaproj` 的 `configs` / `selectedConfig`。
2. YMODEM 文件名 `_rtu_config_.cmd`：只写入 `/rtu_config.cfg`，不当场套用。`_rtu_config_erase_.cmd` 删除该文件。
3. LUAPK / 云配置包里的同名文件。

和脚本的边界：

- 脚本自己 `tcp.create` / `mqtt.create` **不读** 本文件。
- 脚本 `require("rtu")` 用的 1～4 路通道、心跳、注册包、串口透传，**读** 本文件落到的 `[task]` / `[sock]` / `[mqtt]`。
- `uart` 模块的脚、分包三参数 **只能** 写 `[uart.N]`，`uart.config` 只改 RAM。
- `print` / `log` 默认串口写 `[lua]`；系统日志输出口写 `[log]`。两套独立。

---

## 2. 框架结构

```
工程 config 分区 / YMODEM / 云包
        │
        ▼
  /rtu_config.cfg          ← 文本，最大 32 KB
        │
        ▼
  按行切段 → 每段最多 64 个 key
        │
        ▼
  按段名选模块 → 读出该模块当前配置
        │
        ▼
  只覆盖本段出现的 key → 写回该模块存储
        │
        ▼
  后续开机初始化（UART / MQTT / 任务 / 监控…）读新值
```

同一段内的 key **按文件出现顺序**依次写入。同一字段写两次，后写的赢。不同段改同一套存储时，也是后解析的段赢。

某一段套用失败时：记下第一个失败码，**继续解析后面的段**。某一行语法坏掉（缺 `=`、段名非法、单段超过 64 个 key）则 **整文件立即停**，后面的段不会套用。

---

## 3. 文件语法

行结束支持 `\n` 与 `\r\n`。空白行忽略。

### 3.1 注释

行内、不在引号里的 `#`、`;`、`--` 起，直到行尾，全部丢掉。

```ini
[lua]
print_route=1    -- Lua print 走 UART1
log_route=1      # 与 print 独立
; 整行注释
```

引号只保护注释切割，**不会**从值里剥掉。`topic="/a # b"` 的值是 `"/a # b"`（含引号）。`topic=/a # b` 的值是 `/a`。

### 3.2 段

```
[模块]
[模块.N]
[模块.N.组]
[模块.N.组.M]
[模块.组]          # 仅 io.template 这种「第二段是名字」的形态
[模块.组.M]
```

方括号必须成对。段名两端空白会去掉。段名总长（不含方括号）须能放进 79 字节。

### 3.3 键值

```
key=value
```

`=` 左边是 key、右边是 value，两端空白去掉。key 区分大小写。必须先出现某个 `[段]`，段外的 `key=value` 直接判解析失败。

同一段重复 key：两个都会套用，后者覆盖前者。

### 3.4 禁止

| 写法 | 结果 |
| --- | --- |
| `key value`（无 `=`） | 整文件停，解析失败 |
| `[uart.]` / `[mqtt.0]` | 段名失败（索引必须是 ≥1 的十进制） |
| `[mqtt.1.subscribe]` 不写 `.M` | 主题下标为 0，套用失败 |
| 一行两个段 | 不会被识别成两个段 |
| JSON / TOML / Lua table | 不是这种语法 |

---

## 4. 段名规则

段名按 `.` 最多拆成 4 段：

| 形态 | `module` | `index`（1-based） | `group` | `group_index`（1-based） | 例子 |
| --- | --- | --- | --- | --- | --- |
| `[lua]` | `lua` | 无（0） | 无 | 无 | 全局 |
| `[sock.1]` | `sock` | 1 | 无 | 无 | 通道 1 |
| `[mqtt.1.subscribe.2]` | `mqtt` | 1 | `subscribe` | 2 | 通道 1 的第 2 条订阅 |
| `[io.template.1]` | `io` | 无 | `template` | 1 | 第 1 份 IO 模板 |
| `[task.1.heart]` | `task` | 1 | `heart` | 无 | 通道 1 心跳 |

索引 token 必须是纯十进制、且 **≥ 1**。`0`、`01a`、负数都不合法。

别名：段模块名 `socket` 与 `sock` 相同。其它模块名没有别名。

---

## 5. 值类型

| 类型 | 合法写法 | 说明 |
| --- | --- | --- |
| 布尔 | `0` / `1` / `true` / `false` / `on` / `off` / `yes` / `no` | 大小写敏感：`TRUE` 不行 |
| 整数 | 十进制，或 `0x` 前缀十六进制 | `strtoul` 进制 0；须落在该 key 的 min～max |
| 字符串 | 原文 | 不含终止符的最大长度见各 key；超长解析失败 |
| 二进制 | **必须** `hex:` + 偶数位十六进制 | `hex:6869` → `hi`；无前缀、奇数位、非 hex 字符都失败 |

**例外（不用布尔词、不用 `0x`）：**

| 段 | key | 只认 |
| --- | --- | --- |
| `[maping]` | 全部 | 十进制 `0` 或 `1`。`true` / `on` 会失败 |
| `[monitor]` | 分钟类 | 十进制 `0`～`1440` |
| `[lbs]` | 数字类 | 十进制文本；`reset` 必须是 `1` |

空字符串：字符串 key 可以 `auth4=`；布尔/整数空值失败；二进制必须有 `hex:`（`hex:` 本身表示 0 字节）。

---

## 6. 总覆盖权与覆盖顺序

先看这一节，再写具体 key。下面这些 key **不是**普通字段：它们会一次改掉一组目标，或在运行时一票否决其它开关。

### 6.1 拥有总覆盖权的 key

| 级别 | 段 | key | 覆盖范围 | 谁能再改回来 |
| --- | --- | --- | --- | --- |
| **机级总开关** | `[maping]` | `all` | `all=0` 时 **所有** 占位符映射都不做（含短信转发模板）。`all=1` 才看各路由分开关 | 只能再写 `all=1` |
| **批量覆盖** | `[monitor]` | `u_ndata` | UART1～3 的无数据复位分钟，一次写成同一个值 | 本段后面的 `u1_ndata` / `u2_ndata` / `u3_ndata` |
| **批量覆盖** | `[monitor]` | `ch_ndata` | 网络通道 1～4 的无下行复位分钟 | 后面的 `ch1_ndata`…`ch4_ndata` |
| **批量覆盖** | `[monitor]` | `ch_conn` | 网络通道 1～4 的未连接复位分钟 | 后面的 `ch1_conn`…`ch4_conn` |
| **双栈覆盖** | `[sock.N]` | `host` | **同时**写 TCP 主机和 UDP 主机 | 后面的 `tcp_host` / `udp_host` |
| **双栈覆盖** | `[sock.N]` | `port` | **同时**写 TCP 端口和 UDP 端口 | 后面的 `tcp_port` / `udp_port` |
| **别名覆盖** | `[mqtt.N]` | `host` | 覆盖 `server_host` | 后面的 `server_host` |
| **别名覆盖** | `[mqtt.N]` | `port` | 覆盖 `server_port` | 后面的 `server_port` |
| **整模块复位** | `[lbs]` | `reset=1` | 该段执行到此 key 时，LBS 配置回到出厂，**本段此前写过的 lbs key 作废** | 本段里 `reset` **之后**再写的 lbs key |

`[event_out]` 的 `uart1_enable` **不是**总开关。三路串口输出各自独立；事件类型开关（`network_status` 等）决定「这条事件出不出」，串口开关决定「出到哪几路」。

`[uart]` 没有 UART1 使能位：UART1 永远初始化。`uart2_enable` / `uart3_enable` 只关 2/3。

### 6.2 推荐写法（避免被总覆盖权打脸）

```ini
# 先批量，再单路微调
[monitor]
u_ndata=30
u1_ndata=0          -- UART1 关闭无数据复位，2/3 仍是 30

# 先别名，再分开改 UDP
[sock.1]
host=example.com
port=1883
udp_port=1884       -- 只改 UDP；TCP 仍 1883

# 不要先写 tcp_host 再写 host：host 会把 UDP 也改掉
```

```ini
# LBS：reset 必须在最前，否则前面的 key 白写
[lbs]
reset=1
lbs_mode=2
timeout_s=30
```

### 6.3 覆盖顺序（处处适用）

1. 机内当前 KV / 出厂默认。
2. 本文件从上到下的段。
3. 段内从上到下的 key。
4. 总覆盖 key 在它被执行的那一刻生效；它后面的更细 key 可以再改子集。

### 6.4 联合才能生效的组合

| 组合 | 独立写会怎样 | 必须一起满足 |
| --- | --- | --- |
| `[task.N] en` + `[sock.N] enable` + `task_id=1` | 只开任务或只开 socket，通道起不来 | 任务使能、协议使能、`task_id` 对上 |
| `[task.N] en` + `[mqtt.N] enable` + `task_id=2` | 同上 | 同上 |
| `[mqtt.N] will_enable` + `will_topic` / `will_message` | 遗嘱关着时主题仍入库，连上不用 | 打开 `will_enable` 才发遗嘱 |
| `[mqtt.N] ssl_level` + `[ssl.K]` | `ssl_level=0` 不走 TLS | `ssl_level≥1` 且 `ssl_id` 指向已配证书组 |
| `[http.N] ssl_type` + `ssl_id` + `[ssl.K]` | `ssl_type=0` 或不配证书则 HTTPS 材料不齐 | `ssl_type` 1/2/3 与证书组模式一致 |
| `[log] private` + `password` | 只写 `password` **什么都不改**；`private` 会在本段里查找 `password`（顺序无关） | 要加密日志必须同段写 `private`，需要口令时同写 `password` |
| `[io.N] bind_template` + `[io.template.M]` | 绑到空模板就发出空载荷 | 模板下标对上（见第 19 节，**0-based**） |
| `[io.N] change_report` / `loop_report_time` + `[maping] io_change` | 上报仍会走，但不做 `<#…>` 替换 | 要占位符时 `maping.all=1` 且 `io_change=1` |
| `[sms] forward_en` + `[sms.N] number` | 无号码通道不转发 | 至少一路号码；`forward_msg_mode=3` 还要模板 |
| `[sms] forward_msg_mode=3` + `[maping] all` | `all=0` 时模板里的 `<#SENDER>` 不会展开 | `all=1`（短信路由没有单独 map 开关） |
| `[lbs] tmr_en` + `tmr_period_s` + `tmr_rpt_type` | `tmr_en=0` 只配周期无效 | 打开定时；类型 2 还要 `tmr_rpt_data` |
| `[net_led] enable` + `bind_io` | `enable=0` 不碰该脚 | 打开才占用 GPIO |
| `[wtg] enable` + `bind_io` | 同上 | 打开才占用 GPIO、启动喂狗 |
| `[loader] timer_get_config_enable` + `timer_get_config_hour` | 关定时则小时无意义 | 打开才按小时拉云配置 |

---

## 7. 通道编号对照

下面这些 **N 是同一路业务通道**（1～4）：

| 段 | N 的含义 |
| --- | --- |
| `[sock.N]` | Socket 通道 N |
| `[mqtt.N]` | MQTT 通道 N |
| `[task.N]` | RTU 任务 N（选 SOCK 或 MQTT） |
| `[netio.N]` | 该通道在线/离线绑 IO |
| `[monitor]` 的 `chN_*` | 该通道无数据 / 未连接复位 |
| `[event_out]` 的 `chN_status` | 该通道状态 URC 是否输出 |

HTTP 是另一套：`[http.1]`～`[http.5]`，**不要**和上面的 N 当成一路。

SSL 组是第三套：`[ssl.1]`～`[ssl.3]`，被 MQTT / HTTP 的 `ssl_id` 引用。

UART：`[uart.1]`～`[uart.3]` 对应硬件 UART1～3。`[uart.0]` **禁止**，套用失败。

IO：`[io.N]` 的 N 是 GPIO 编号 **1～39**，对应内部脚 0～38。`[io.1]` = GPIO0。写文档和 AT 时按 1-based 脚号。

---

## 8. 模块一览

| 段模块 | 允许的段 | 作用 |
| --- | --- | --- |
| `sock` / `socket` | `[sock.N]` N=1..4 | TCP/UDP 通道 |
| `mqtt` | `[mqtt.N]`、`[mqtt.N.subscribe.M]`、`[mqtt.N.publish.M]` | MQTT 通道与主题槽 |
| `http` | `[http.N]` N=1..5 | HTTP 通道 |
| `ssl` | `[ssl.N]` N=1..3 | 证书组 |
| `uart` | `[uart]`、`[uart.N]` N=1..3 | 系统使能 + 线参数/分包 |
| `lua` | `[lua]` | `print` / `log` 模块串口 |
| `log` | `[log]` | 系统日志输出口与加密 |
| `task` | `[task]`、`[task.N]`、`[task.N.heart]`、`[task.N.reg]` | 透传任务、心跳、注册包 |
| `maping` | `[maping]` | 占位符映射总开关与分开关 |
| `io` | `[io]`、`[io.N]`、`[io.template.N]` | IO 上报与模板 |
| `event_out` | `[event_out]` | 状态 URC 往哪些串口、哪些事件 |
| `netio` | `[netio.N]` N=1..4 | 通道在线指示 IO |
| `net_led` | `[net_led]` | 驻网/联网指示灯 |
| `wtg` | `[wtg]` | 外置看门狗喂狗 |
| `monitor` | `[monitor]` | 无数据/未连接/未驻网/cron 复位 |
| `loader` | `[loader]` | 云配置定时拉取、脚本 OTA 回滚 |
| `lbs` | `[lbs]` | 基站定位与定时上报 |
| `sms` | `[sms]`、`[sms.N]` N=1..10 | 短信转发 |
| `dbg` | `[dbg]` | 远程调试 MQTT（独立链路） |

未列出的模块名（例如 `[script.1]`）整段失败，错误见第 31 节。

---

## 9. `[sock.N]` / `[socket.N]`

N = 1..4。读出该通道当前配置，只改出现的 key，写回。

`protocol` **独立**决定实际用 TCP 还是 UDP 那一套参数。另一套参数仍会入库，只是这条通道连上时不用。

### 9.1 key

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | 协议通道使能。任务要再靠 `[task.N]` |
| `protocol` | 整数 | 0=TCP，1=UDP | 选哪套参数去连 |
| `host` | 字符串 | 最长 127 | **总覆盖**：同时写 `tcp_host` 与 `udp_host` |
| `port` | 整数 | 0～65535 | **总覆盖**：同时写 `tcp_port` 与 `udp_port` |
| `tcp_host` | 字符串 | 最长 127 | 只改 TCP 主机 |
| `tcp_port` | 整数 | 0～65535 | 只改 TCP 端口 |
| `tcp_connect_timeout` | 整数 ms | 0～4294967295 | 连接超时 |
| `tcp_reconnect_interval` | 整数 ms | 同上 | 断线重连间隔 |
| `tcp_recv_timeout` | 整数 ms | 同上 | 接收超时 |
| `tcp_recv_buffer_size` | 整数 | 同上 | 收缓冲 |
| `tcp_send_buffer_size` | 整数 | 同上 | 发缓冲 |
| `tcp_keepalive_enable` | 布尔 | 0/1 | TCP keepalive |
| `tcp_keepalive_idle` | 整数 秒 | 0～4294967295 | 空闲多久开始探活 |
| `tcp_keepalive_interval` | 整数 秒 | 同上 | 探活间隔 |
| `tcp_keepalive_count` | 整数 | 同上 | 探活次数 |
| `tcp_poll_interval` | 整数 ms | 同上 | 轮询间隔 |
| `tcp_nodelay` | 布尔 | 0/1 | TCP_NODELAY |
| `tcp_link_wait_timeout` | 整数 ms | 同上 | 等链路超时 |
| `udp_host` | 字符串 | 最长 127 | 只改 UDP 主机 |
| `udp_port` | 整数 | 0～65535 | 只改 UDP 端口 |
| `udp_retry_interval` | 整数 ms | 0～4294967295 | UDP 重试间隔 |
| `udp_recv_buffer_size` | 整数 | 同上 | 收缓冲 |
| `udp_send_buffer_size` | 整数 | 同上 | 发缓冲 |
| `udp_poll_interval` | 整数 ms | 同上 | 轮询间隔 |
| `udp_link_wait_timeout` | 整数 ms | 同上 | 等链路超时 |

### 9.2 联合影响

- `enable=1` 但 `[task.N] en=0` 或 `task_id≠1`：socket 配置在，RTU 任务不跑这条 SOCK。
- `protocol=0` 时只使用 `tcp_*`；`host`/`port` 仍会改 UDP 字段，只是当前连不上 UDP。
- 占位符：发到 SOCK 的载荷是否展开 `<#IMEI>` 等，看 `[maping] all` + `sock`（普通收发）、`sock_reg` / `sock_heart`（注册/心跳）。

未知 key → 该段失败。

---

## 10. `[mqtt.N]`

N = 1..4。主题槽见第 11 节，不要写在本段。

### 10.1 key

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | MQTT 通道使能 |
| `host` | 字符串 | 最长 127 | **别名**，写入 `server_host` |
| `port` | 整数 | 0～65535 | **别名**，写入 `server_port` |
| `server_host` | 字符串 | 最长 127 | broker 主机 |
| `server_port` | 整数 | 0～65535 | broker 端口 |
| `platform` | 整数 | 0=普通，1=OneNET，2=DoIoT | 决定 `auth1`～`auth4` 怎么拼三元组 |
| `auth1` | 字符串 | 最长 127 | 见下表 |
| `auth2` | 字符串 | 最长 127 | 见下表 |
| `auth3` | 字符串 | 最长 127 | 见下表 |
| `auth4` | 字符串 | 最长 127 | 仅 DoIoT 平台参与 clientId |
| `keepalive_interval` | 整数 秒 | 0～4294967295 | MQTT keepalive |
| `clean_session` | 布尔 | 0/1 | 清会话 |
| `connect_timeout_ms` | 整数 | 0～4294967295 | 连接超时 |
| `command_timeout_ms` | 整数 | 同上 | 命令超时 |
| `reconnect_interval_ms` | 整数 | 同上 | 重连间隔 |
| `send_buffer_size` | 整数 | 同上 | 发缓冲 |
| `recv_buffer_size` | 整数 | 同上 | 收缓冲 |
| `callback_queue_mem_max` | 整数 | 同上 | 回调队列内存上限 |
| `poll_interval_ms` | 整数 | 同上 | 轮询间隔（运行时另有 20～10000 的常用窗） |
| `yield_timeout_normal_ms` | 整数 | 同上 | 正常模式 yield |
| `yield_timeout_low_power_ms` | 整数 | 同上 | 低功耗 yield |
| `yield_timeout_ultra_low_power_ms` | 整数 | 同上 | 超低功耗 yield |
| `yield_timeout_psm_plus_ms` | 整数 | 同上 | PSM+ yield |
| `will_enable` | 布尔 | 0/1 | 是否带遗嘱 |
| `will_topic` | 字符串 | 最长 127 | 遗嘱主题 |
| `will_message` | 字符串 | 最长 255 | 遗嘱消息 |
| `will_qos` | 整数 | 0～2 | 遗嘱 QoS |
| `will_retain` | 布尔 | 0/1 | 遗嘱 retain |
| `ssl_id` | 整数 | 0～255 | 引用 `[ssl.K]`；`0` 表示不引用组 |
| `ssl_level` | 整数 | 0～3 | `0` 关 TLS；`1` 不校验；`2` 校验服务端；`3` 双向 |

### 10.2 `platform` × `auth*`（联合）

| platform | auth1 | auth2 | auth3 | auth4 |
| --- | --- | --- | --- | --- |
| 0 普通 | ClientId（必填） | Username（可空） | Password（可空） | 不用 |
| 1 OneNET | ClientId（必填） | 产品/用户名（必填，并参与算密） | 算密用的 key | 不用 |
| 2 DoIoT | 参与生成 ClientId | Username（必填） | Password（必填） | 与 auth1 一起生成 ClientId |

`auth*` 独立看只是字符串入库。连上时按 `platform` 解释；填错平台会连上失败或算错密码。

三元组、遗嘱、主题、发布/订阅载荷要不要做 `<#…>`，分别看 `[maping]` 的 `mqtt_triplet` / `mqtt_will` / `mqtt_topic` / `mqtt_publish` / `mqtt_subscribe`，且先过 `all`。

---

## 11. `[mqtt.N.subscribe.M]` / `[mqtt.N.publish.M]`

N = 1..4，M = 1..10（与路由槽位数相同）。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `topic` | 字符串 | 最长 127 | 主题；空槽视为不用 |
| `qos` | 整数 | 0～2 | QoS |
| `retain` | 布尔 | 0/1 | retain（订阅槽也会存，发布时才有业务含义） |

组名只能是 `subscribe` 或 `publish`。其它组名整段失败。

与 `[mqtt.N]` 的联合：通道 `enable=0` 时主题仍入库，连上后才订阅/发布。`maping.mqtt_topic` 控制主题字符串里的占位符；`mqtt_subscribe` / `mqtt_publish` 控制订阅匹配与发布载荷。

---

## 12. `[http.N]`

N = 1..5。与 RTU 1～4 通道 **不是**同一编号。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | 通道使能 |
| `method` | 整数 | 0=NONE，1=GET，2=POST，3=PUT，4=DELETE，5=HEAD | 请求方法 |
| `url` | 字符串 | 最长 511 | URL；可含占位符，受 `map.http_url_header` 管 |
| `header` | 字符串 | 最长 511 | 额外头；同样可映射 |
| `timeout_s` | 整数 秒 | 0～65535 | 超时 |
| `url_encode` | 布尔 | 0/1 | 是否 URL 编码 |
| `ssl_id` | 整数 | 0～3 | `1`～`3` 引用 `[ssl.1]`～`[ssl.3]`；`0` 不引用 |
| `ssl_type` | 整数 | 0～3 | `0` 不用这套 TLS 模式；`1` 不校验证书；`2` 单向；`3` 双向 |
| `resp_status_line` | 布尔 | 0/1 | 响应是否带状态行 |
| `resp_header` | 布尔 | 0/1 | 是否带响应头 |
| `resp_content` | 布尔 | 0/1 | 是否带响应体 |
| `resp_at_mode` | 整数 | 0=都回，1=仅失败回，2=不回 | AT/事件回包策略 |

联合：HTTPS 需要 `ssl_type` 与 `[ssl.K].mode`、证书内容一致。透传型 HTTP 走的是 `[maping] update`，不是 `http`。响应体映射看 `map.http`；URL/头映射看 `map.http_url_header`。

---

## 13. `[ssl.N]`

N = 1..3。证书组，供 MQTT / HTTP 的 `ssl_id` 引用。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `mode` | 整数 | 解析允许 0～3 | 运行时有效值是 **1～3**（与 HTTP TLS 模式相同）。`0` 会在套用时失败 |
| `ca_cert` | 文本或 `hex:` | CA 最长 6144 字节 | 值以 `hex:` 开头则按二进制写入，否则按原文（可一行 PEM） |
| `client_cert` | 同上 | 最长 4096 | 客户端证书 |
| `client_key` | 同上 | 最长 4096 | 客户端私钥 |

`mode`：`1` 不校验，`2` 校验服务端（要 CA），`3` 双向（CA + 客户端证书 + 私钥）。只改 `mode` 不改证书：旧证书仍在。只写证书不改 `mode`：模式保持机内原值。

未知 key 失败。不要把 PEM 折成多行——本文件一行一个 key。

---

## 14. `[uart]` / `[uart.N]`

两套完全不同的存储，靠段名区分：

- `[uart]`（段名等于模块名、无 `.N`）：系统使能。
- `[uart.N]`：N 必须是 1、2、3，对应 UART1～3。`[uart.0]` 被拒绝。

### 14.1 `[uart]`

| key | 类型 | 独立作用 |
| --- | --- | --- |
| `uart2_enable` | 布尔 | 关则 UART2 不初始化，脚可给 SPI 等 |
| `uart3_enable` | 布尔 | 关则 UART3 不初始化 |

没有 `uart1_enable`。UART1 恒开。开机时本文件在 UART2/3 初始化 **之前** 解析，故这两位 **本次开机生效**。

### 14.2 `[uart.N]`

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `baudrate` | 整数 | 1200～3000000 | 波特率 |
| `data_bits` | 整数 | 7 或 8 | 数据位 |
| `stop_bits` | 整数 | 1 或 2 | 停止位 |
| `parity` | 整数 | 0 无，1 奇，2 偶 | 校验 |
| `flow_control` | 整数 | 0 无，1 RTS/CTS | 流控 |
| `pin_map` | 整数 | 0～255 | 引脚组，`0` 默认。F6E0：UART2 常见 0/1/2，UART3 常见 0/1。UART2 默认组常与 SPI0 重叠，外挂 Flash 写 `pin_map=1` |
| `max_packet_size` | 整数 | 0～12288 | 单包上限；`0` 表示不按这套分包（产品常用 1～12288） |
| `max_wait_ms` | 整数 | 0～60000 | 空闲断包 ms |
| `max_packets` | 整数 | 0～64 | 待处理包深度 |

联合：`uart.config` 只改 RAM 线参数，改不了 `pin_map` 与分包三参数。`[lua] print_route` / `[log] output` 指向的口必须已使能，否则 print/日志看不到。

Lua `uart` 模块文档：[uart.md](../peripherals/uart.md)。

---

## 15. `[lua]`

只允许全局段，不能写 `[lua.1]`。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `print_route` | 整数 | 1～3 | Lua `print()` 打到 UART1/2/3 |
| `log_route` | 整数 | 1～3 | Lua `log` 模块打到哪路。**不是** `[log] output` |

两 key 互相独立。脚本启动时会把这两项应用到运行时。`sys.option("print_route")` 可热改，不回写本文件。

---

## 16. `[log]`

系统日志（`HAL` / `app_log`），与 Lua `log` 模块不是同一条管子。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `output` | 整数 | 0=无，1=UART1，2=UART2，3=UART3，4=USB AT 口 | 立刻切输出口并落盘 |
| `private` | 布尔 | 0/1 | 是否加密日志。会在 **本段全部 key** 里查找 `password`（前后顺序无关） |
| `password` | 字符串 | 随口令接口 | **单独出现是空操作**，必须配合 `private` |

联合：`private=1` 且同段无 `password`：按空口令交给底层，失败则本段失败。`output=4` 与 AT 共用 VCOM，调试 AT 时日志会挤在一起。

开机时日志子系统先于本文件初始化：`output` 在套用时会再切一次，**本次开机就能变**。

---

## 17. `[task]` / `[task.N]` / `[task.N.heart]` / `[task.N.reg]`

这是传统 DTU 的总控：哪路任务跑 SOCK 还是 MQTT、心跳/注册包、串口上下行总闸。

### 17.1 `[task]` 全局

| key | 类型 | 独立作用 |
| --- | --- | --- |
| `config_id` | 整数 0～4294967295 | 云端配置编号，给配置管理用 |
| `is_recv_header` | 布尔 | 接收数据头 |
| `channel_down_en` | 布尔 | 通道下行透传总闸（Lua `rtu.option("pass_down")` 是运行时覆盖，不落盘） |
| `channel_update_en` | 布尔 | 通道上行透传总闸（对应 `pass_up`） |

`channel_*_en=0`：四路都不走串口↔通道透传，但 `rtu.update_write` / `down_write` / `write` 仍按文档工作。

### 17.2 `[task.N]` N=1..4

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `task_id` | 整数 | **只能 1 或 2** | `1`=SOCK，`2`=MQTT |
| `en` | 布尔 | 0/1 | 该路 RTU 任务使能 |
| `io_state_id` | 整数 | 0～255 | 旧式状态 IO 编号（新方案优先 `[netio.N]`） |
| `io_state_en` | 布尔 | 0/1 | 是否用上面这个 IO |

`task_id` 越界（含 0、3）整段失败。`en=1` 且 `task_id=1` 时去读 `[sock.N]`；`task_id=2` 时读 `[mqtt.N]`。

### 17.3 `[task.N.heart]`

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `en` | 布尔 | 0/1 | 心跳使能 |
| `interval` | 整数 秒 | 0～4294967295 | `0` 视为不按间隔跳；仍受 `en` 管 |
| `heartpack` | 二进制 | `hex:`，最长 128 字节 | 心跳载荷 |

映射路由：SOCK 任务走 `map.sock_heart`，MQTT 走 `map.mqtt_heart`。

### 17.4 `[task.N.reg]`

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `en` | 布尔 | 0/1 | 上线发注册包 |
| `regpack` | 二进制 | `hex:`，最长 128 字节 | 注册载荷 |

映射：`map.sock_reg` / `map.mqtt_reg`。

其它 group 名（例如 `[task.1.foo]`）失败。本段 **不能** 配串口上行路由表（那是 AT / 其它接口），文件只动上述字段。

---

## 18. `[maping]`

占位符映射：把载荷里的 `<#IMEI>` 等换成真值。写 key 时 **可以省略 `map.` 前缀**（`all` 与 `map.all` 等价）。

值 **只能是十进制 `0` 或 `1`**。`true` / `on` / `0x1` 都会失败。

### 18.1 总覆盖

| key | 作用 |
| --- | --- |
| `all` | **总开关**。`0`：任何路由都不做映射（含短信模板、未知路由）。`1`：再看下面分开关 |

运行时判断顺序：先 `all`，再按路由看分开关。分开关为 1 而 `all=0`，仍然不映射。

### 18.2 分开关（独立，但先过 `all`）

| key | 管哪条路径 |
| --- | --- |
| `sock` | AT SOCK 同步/异步、普通 socket 载荷 |
| `http` | HTTP 响应体输出 |
| `http_url_header` | HTTP URL / Header 请求参数 |
| `at_http` | `AT+HTTPREQ` body |
| `mqtt_publish` | MQTT 发布 payload |
| `mqtt_subscribe` | 订阅主题映射 |
| `mqtt_triplet` | ClientId / Username / Password |
| `mqtt_will` | 遗嘱消息 |
| `mqtt_topic` | 发布主题、遗嘱主题 |
| `lua_write` | Lua `rtu.write` |
| `sock_reg` | SOCK 注册包 |
| `mqtt_reg` | MQTT 注册包 |
| `sock_heart` | SOCK 心跳 |
| `mqtt_heart` | MQTT 心跳 |
| `dtu_log` | DTU 日志路径（预留） |
| `io_change` | IO 变化/定时上报 |
| `update` | 透传上行（含走透传的 HTTP） |
| `down` | 透传下行 |
| `lbs_timer` | LBS 定时上报自定义文本 |
| `rtu_write` | `AT+RTUWRITE` / 同类输出 |

**没有 `sms` 分开关。** 短信模板只受 `all` 约束：`all=1` 就映射，`all=0` 就不映射。

未知 key（例如 `map.foo` 或 `foo`）整段失败。

可用占位符见第 29 节。

---

## 19. `[io]` / `[io.N]` / `[io.template.N]`

### 19.1 `[io]` 全局

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `io_volt_sel_enable` | 布尔 | 0/1 | `1`：用 IO17 采样决定电压域 |
| `aon_io_voltage` | 整数 | 0～255 | AON IO 电压档（枚举原值） |
| `normal_io_voltage` | 整数 | 0～255 | 普通 IO 电压档 |

电压档与 `io_volt_sel_enable` 联合：使能后以 IO17 采样为准，两个 voltage 字段仍入库。

### 19.2 `[io.N]` N=1..39

N 是 **1-based 脚号**，对应内部 GPIO 0～38。`[io.1]` 配 GPIO0。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `method` | 整数 | 0=不使能，1=输入，2=输出 | `0` 不初始化该脚、注销变化上报 |
| `pull` | 整数 | 0=自动，1=上拉，2=下拉 | 初始化上下拉 |
| `init_level` | 布尔 | 0/1 | 初始电平（输出时有意义） |
| `bind_template` | 整数 | **0～4，0-based** | 绑哪份模板。`0` = `[io.template.1]`，`1` = `[io.template.2]` |
| `change_report` | 布尔 | 0/1 | 电平变化上报 |
| `loop_report_time` | 整数 秒 | 0～4294967295 | `0` 关闭循环上报；`>0` 周期秒 |

`method=0` 时其它字段仍入库，只是脚不按上报逻辑初始化。`bind_template` 越界（≥5）失败。

**易错：** 示例若写 `bind_template=1` 又只定义 `[io.template.1]`，实际绑的是 **第二份** 模板（可能为空）。要绑第一份写 `bind_template=0`。

和脚本 `gpio.open` 抢脚：同一脚不要两边开。`[net_led]` / `[wtg]` / `[netio]` 占用的脚同样不要再开上报。

### 19.3 `[io.template.N]` N=1..5

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `tpl_bytes` | 二进制 | `hex:`，最长 256 字节 | 上报载荷模板，可含 `<#IMEI>`、`<#IO1>` 等 |

映射受 `map.all` + `map.io_change` 管。

---

## 20. `[event_out]`

状态 URC 往串口打。每个事件开关 **独立**；每个串口开关 **独立**。先过事件开关，再按串口开关扇出。

| key | 独立作用 |
| --- | --- |
| `uart1_enable` | 事件文本到 UART1。**不是**总开关 |
| `uart2_enable` | 文本到 UART2 |
| `uart3_enable` | 文本到 UART3 |
| `network_status` | 驻网/掉网 `+NET` |
| `sim_card_status` | SIM 插拔 `+SIM` |
| `script_status` | 脚本信息 |
| `ch1_status`～`ch4_status` | 通道 1～4 状态行 |
| `config_loader_status` | 云配置拉取 `+WEBCONFIG` |
| `config_update_reset_status` | 配置更新计划复位通知 |
| `monitor_reset_status` | 监控复位原因通知 |

全是布尔。事件开着但三路串口都关：事件被判定要出，但写不到口。三路都开、事件关：完全不出。

---

## 21. `[netio.N]`

N = 1..4，对应 RTU 通道 N 的在线指示脚。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | 关则不驱动该脚 |
| `active_mode` | 整数 | 0=低电平有效（在线=0），1=高电平有效（在线=1） | 只改极性 |
| `bind_io` | 整数 | 0～38 | GPIO 编号（与 `[io.N]` 的 N-1 同一套脚） |

联合：通道从未上线时脚保持初始；只改 `bind_io` 不改 `enable`，使能位保持机内原值。与 `[task.N] io_state_*` 不要绑同一脚两套逻辑。

---

## 22. `[net_led]`

驻网/联网指示，独立线程闪灯。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | `0` 不占用脚。脚本要用该脚做 PWM/GPIO 时必须写 0 |
| `bind_io` | 整数 | 0～38 | 绑脚。F6E0 默认常见 25，F6B0 常见 27 |
| `sleep_keep` | 整数 | 0=休眠拉低，1=休眠拉高 | 仅 `enable=1` 时，进休眠前写该电平 |

未驻网快闪、驻网未联网慢闪、已联网常亮（具体亮灭时间是固件常量，本文件改不了）。

---

## 23. `[wtg]`

外置看门狗喂狗。无外置 WDT 的板子可以 `enable=0`。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | 关则不启动喂狗线程、不占脚 |
| `bind_io` | 整数 | 0～38 | 喂狗脚，默认常见 26 |
| `pulse_mode` | 整数 | 0=下降脉冲（空闲高、喂狗拉低），1=上升脉冲 | 极性 |
| `pulse_duration_sec` | 整数 秒 | 0～4294967295 | 脉冲宽度，默认常见 1 |
| `feed_interval_sec` | 整数 秒 | 同上 | 喂狗间隔，默认常见 280 |

`enable=1` 但间隔过长：外置 WDT 可能先复位。本模块写回时若喂狗已在跑，会同步运行态。

---

## 24. `[monitor]`

设备监控复位。分钟类：`0`=该条件关闭，`1`～`1440`=超时分钟。非法分钟失败。

key 可带或不带 `mrst.` 前缀（`u_ndata` ≡ `mrst.u_ndata`）。

| key | 覆盖范围 | 独立作用 |
| --- | --- | --- |
| `u_ndata` | **总覆盖** UART1～3 | 三路无 RX 复位分钟写成同一个值 |
| `u1_ndata` / `u2_ndata` / `u3_ndata` | 单路 | 覆盖对应 UART |
| `ch_ndata` | **总覆盖** 通道 1～4 | 无下行 MSG 复位 |
| `ch1_ndata`…`ch4_ndata` | 单通道 | 对应 `[sock.N]`/`[mqtt.N]`/`[task.N]` 的 N |
| `ch_conn` | **总覆盖** 通道 1～4 | 到期仍未连接则复位；ONLINE 刷新计时 |
| `ch1_conn`…`ch4_conn` | 单通道 | 同上，单路 |
| `reg` | 全局 | 到期未驻网则复位；已驻网刷新计时 |
| `cron` | 全局 | cron 表达式定时复位。空串=关。非法表达式本 key 失败。最长 191 字节。可带一层首尾 `"` |

`chN_ndata` 只看 **下行业务 MSG**，已连接但一直无下行也会到点复位。`chN_conn` 看连接本身。两套独立，可同时开。

`cron` 语法与 Lua [`cron`](../module/cron.md) 相同。解析失败视为本 key 失败（与运行时「非法当关闭」不是同一层：写入阶段就会拒）。

通知串口看 `[event_out] monitor_reset_status`。

---

## 25. `[loader]`

云端拉 DTU 配置 / LUAPK。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `timer_get_config_enable` | 布尔 | 0/1 | 是否按小时定时拉配置 |
| `timer_get_config_hour` | 整数 | 0～23 | 每天的这个整点拉 |
| `first_boot_get_config` | 布尔 | 0/1 | 首次开机第一次驻网时拉一次 |
| `script_rollback_enable` | 布尔 | 0/1 | `0`（默认）：脚本 OTA 覆盖当前槽并直接提交。`1`：写对侧槽 + trial，需 `script.confirm` / AT 确认，否则回滚 |

联合：`timer_get_config_enable=0` 时小时字段仍入库但不跑定时。回滚开关不影响本文件解析，只影响之后的脚本包部署。写 KV 后，运行态要等重启由加载器再读。

---

## 26. `[lbs]`

基站定位。数字按十进制文本解析。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `lbs_mode` | 整数 | 1=单基站，2=多基站（无地址），3=地理反编码（含地址） | 定位方式 |
| `timeout_s` | 整数 | 任意 u32，`0`=用内置默认 | 秒超时 |
| `timeout_r` | 整数 | 同上 | 另一路超时（客户端内部） |
| `retry_count` | 整数 | 0～255，`0`=内置默认 | 重试 |
| `tmr_en` | 整数 | 0/1 | 定时采集 |
| `tmr_period_s` | 整数 | **≥1** | 周期秒；写 0 失败 |
| `tmr_rpt_type` | 整数 | 0=只采集，1=AT URC，2=自定义文本 | 定时结果怎么出 |
| `tmr_rpt_data` | 二进制 | `hex:`，最长 256 | 类型 2 的载荷，可含占位符 |
| `tmr_rpt_route` | 字符串 | 最长 127，须是合法路由串或空 | 例如 `6[1]`；空=默认路径。非法路由失败 |
| `reset` | 整数 | **必须是 1** | **总覆盖**：整份 LBS 回到出厂，然后继续本段后面的 key |

`tmr_rpt_type=2` 且要占位符：`map.all=1` 且 `map.lbs_timer=1`。Lua `require("lbs")` 的一次性请求用自己的参数，默认值来自这里。

---

## 27. `[sms]` / `[sms.N]`

### 27.1 `[sms]` 全局

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `forward_en` | 布尔 | 0/1 | 收到短信是否转发到 RTU 输出 |
| `forward_msg_mode` | 整数 | **1～3**（写 0 失败） | `1`=JSON，`2`=AT 行，`3`=模板 + 占位符 |
| `forward_msg_template` | 字符串 | 最长 255 | 仅 mode=3 使用 |

mode=3 的占位符：`<#SENDER>`（号码）、`<#SMS_MSG>`（正文）。**没有 `<#TEXT>`。** 模板映射只受 `map.all` 管。

### 27.2 `[sms.N]` N=1..10

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `number` | 字符串 | 最长 31 | 该通道号码；空=该路不用 |

`forward_en=1` 但十路号码都空：没有可转发目标。Lua `sms` 收发 API 不读这些转发通道，只读模组短信能力。

---

## 28. `[dbg]`

独立的调试 MQTT（连固定调试服务器，主串口双向透传）。**不是** `[mqtt.N]`。

| key | 类型 | 范围 | 独立作用 |
| --- | --- | --- | --- |
| `enable` | 布尔 | 0/1 | 开则在任务初始化后拉起调试链路 |
| `id` | 字符串 | 最长 20 | 出现在调试主题路径里的设备标识 |

写回只落盘，调试链路要等这次开机的调试初始化（本文件在它之前解析，故 **本次开机** 能用新值）。`id` 超长失败。

---

## 29. 占位符映射

在被 `[maping]` 放行的载荷里，`<#NAME>` 会被替换。展开后额外增长超过 4096 字节的部分丢掉。

| 名字 | 展开成 |
| --- | --- |
| `IMEI` | 本机 IMEI |
| `ICCID` | SIM ICCID |
| `IMSI` | IMSI |
| `CSQ` | 信号 |
| `LBS` | 最近一次定位摘要 |
| `LBS_LAT` / `LBS_LON` | 纬度 / 经度 |
| `VBAT` | 电池电压 |
| `LAC` / `CELL` | 小区 |
| `TIME` / `UTC` | 本地时间 / UTC |
| `ENTER` | `\r\n` |
| `COMMA` | `,` |
| `QUOTE` | `"` |
| `IO~` | `<#IO1>`、`<#IO2>`、`<#IOALL>` 等 IO 电平 |
| `SENDER` | 仅短信路由：发送号码 |
| `SMS_MSG` | 仅短信路由：短信正文 |

`SENDER` / `SMS_MSG` 在非短信路径上展开为空。

---

## 30. 未接入的段

下列名字会出现在旧示例或其它工具里，**当前解析器没有对应模块**，整段返回未知模块（见第 31 节），**不会**写任何业务配置：

| 段 | 说明 |
| --- | --- |
| `[script]` / `[script.N]` | 脚本使能/延时/源码 **不** 走本文件。用工程 main、LUAPK、`script` 模块 |
| 其它未列模块名 | 同样未知 |

写了未知段时：该段失败被记下，**后面的合法段仍会套用**。不要以为整文件被回滚。

---

## 31. 错误与返回约定

脚本侧看不到这些返回码（没有 `require("rtu_config")`）。诊断靠开机日志 `[config_apply]` 行号，以及「某段套用失败后后面的段是否仍生效」。

### 31.1 文件级

| 码 | 含义 | 可能原因 |
| --- | --- | --- |
| `0` | 成功或文件为空 | 正常 |
| `-1` | 参数非法 | 内部调用异常；布尔/整数空值 |
| `-2` | 文件不存在 | 没烧 config 分区、已被 erase。属跳过，不是故障 |
| `-3` | IO | 读盘失败 |
| `-4` | 解析 | 文件 > 32 KB；缺 `=`；段外 key；段名非法；索引为 0；单段 > 64 key；整数越界；字符串超长；`hex:` 奇数位/非法字符 |
| `-5` | 无内存 | 堆不够读文件 |
| `-6` | 未知 | 段模块名不在第 8 节表中（含 `[script]`） |
| `-7` | 不支持 | 未知 key；`[uart.0]`；错误的 group；索引超出该模块上限 |

语法错误（`-4` 且发生在切行阶段）**停整文件**。某段套用失败（未知模块、未知 key、越界）记下首个错误并 **继续下一段**。

### 31.2 各段典型失败

| 现象 | 可能原因 |
| --- | --- |
| `unsupported key …` | key 拼错、大小写错、在错误的段 |
| `[uart.0] ignored` | 写了 UART0 |
| `maping` 失败且值是 `true` | 只认 `0`/`1` |
| `ssl` `mode=0` | 解析过了，写入模式校验失败 |
| `lbs` `reset=0` | reset 必须是 `1` |
| `lbs` `tmr_period_s=0` | 周期必须 ≥1 |
| `monitor` cron 失败 | 表达式非法或 ≥192 字节 |
| `mqtt` / `sock` 索引 5 | 只有 1～4 |
| `http` 索引 6 | 只有 1～5 |
| `io.40` | 只有 1～39 |
| `io.template.6` | 只有 1～5 |
| `sms.11` | 只有 1～10 |
| `task_id=3` | 只能 1 或 2 |
| 二进制没写 `hex:` | 心跳/注册/模板/LBS 自定义文本必须带前缀 |
| 段内第 65 个 key | 拆成两段，或删掉多余项 |

### 31.3 日志

成功套用一段会打 `section [名字] items=个数` 以及每个 `key=value (line 行号)`。失败打 `section [名字] apply failed ret=码` 或 `bad kv line=行` / `bad section line=行` / `too many keys`。

---

## 32. 资源上限

| 项 | 上限 |
| --- | --- |
| 文件大小 | 32 KB |
| 单段 key 数 | 64 |
| 段名 | 79 字节 |
| 模块名 / 组名 | 各 23 字节 |
| SOCK / MQTT / TASK / NETIO | 4 路 |
| HTTP | 5 路 |
| SSL 组 | 3 |
| MQTT 主题槽（每通道每方向） | 10 |
| UART 可配 | 1～3 |
| IO 上报脚 | 39（`[io.1]`～`[io.39]`） |
| IO 模板 | 5 |
| 模板 / 心跳 / 注册包 | 256 / 128 / 128 字节 |
| SMS 通道 | 10 |
| 映射展开额外长度 | 4096 |
| 监控 cron | 191 字节 |
| 监控分钟 | 0～1440 |

---

## 33. 选型对照

| 需求 | 写本文件 | 不要 |
| --- | --- | --- |
| 配 DTU 四路 TCP/MQTT | `[task]` + `[sock]` / `[mqtt]` | 在 `main.lua` 里 `tcp.create` 当 DTU |
| 脚本自己连云 | Lua `tcp` / `mqtt` | 指望本文件给脚本连接对象 |
| 改 UART 脚、分包 | `[uart.N]` | `uart.config` |
| 关掉 NET 灯抢脚 | `[net_led] enable=0` | 只 `gpio.open` 硬抢 |
| 占位符总闸 | `[maping] all` | 只关某一个分开关却指望全部消失 |
| 脚本 print 口 | `[lua] print_route` | `[log] output` |
| 系统日志口 | `[log] output` | `[lua] log_route` |
| 一次性定位 | Lua `lbs` | 只改本文件却不调用 |
| 定时定位上报 | `[lbs] tmr_*` | 脚本里空转 `delay` 冒充 |
| 脚本内容 | 工程 `main.lua` / LUAPK | `[script.1]`（不生效） |

---

## 34. 完整示例

只演示「声明要改的字段」。没写的保持机内原值。

```ini
# /rtu_config.cfg
# 注释：#  ;  --

[lua]
print_route=1
log_route=1

[log]
output=0
private=0

[uart]
uart2_enable=1
uart3_enable=1

[uart.1]
baudrate=115200
data_bits=8
stop_bits=1
parity=0
max_packet_size=2048
max_wait_ms=100
max_packets=8

[uart.2]
pin_map=1          -- 给 SPI0 让脚

[maping]
all=1              -- 总覆盖：先开总闸
sock=1
mqtt_publish=1
mqtt_triplet=1
io_change=1

[task]
channel_down_en=1
channel_update_en=1

[task.1]
task_id=2
en=1

[mqtt.1]
enable=1
host=mqtt.example.com    -- 别名，等价 server_host
port=1883
platform=0
auth1=device
auth2=user
auth3=password
keepalive_interval=60
clean_session=1
ssl_level=0

[mqtt.1.subscribe.1]
topic=/device/down
qos=0

[mqtt.1.publish.1]
topic=/device/<#IMEI>/up
qos=0

[task.1.heart]
en=1
interval=60
heartpack=hex:6865617274

[net_led]
enable=0           -- 避免和脚本 PWM 抢脚

[monitor]
u_ndata=0
ch_ndata=0
ch_conn=0
reg=0
cron=

[loader]
script_rollback_enable=0
first_boot_get_config=0
```

最小 Lua 工程只需：

```ini
[lua]
print_route=1
log_route=1
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：`rtu_config.cfg` 语法、全部已接入段与 key、总覆盖权、联合/独立影响、错误码与未接入段 |
