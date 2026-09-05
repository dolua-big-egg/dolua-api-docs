# AT 定位（LBS / Wi-Fi）

**文档版本** `1.0.0`

基站定位、LBS 持久化配置、同步 Wi-Fi 扫描、Wi-Fi 云端定位。行格式见 [convention.md](convention.md)。失败走 `+CME ERROR`（`LBSCFG` 用短 reason）。

Lua 对照：[`require("lbs")`](../api/network/lbs.md)、[`require("wifiscan")`](../api/network/wifiscan.md)。配置文件同一套 key 在 [`[lbs]`](../api/rtu_config/rtu_config.md#26-lbs)。

`AT+LBS` / `AT+WIFILOC` **必须已经能上网**（`AT+ISLINK=1`）。`AT+WIFISCAN` 只要射频能扫。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+LBS](#3-atlbs)
- [4. AT+LBSCFG](#4-atlbscfg)
- [5. AT+WIFISCAN](#5-atwifiscan)
- [6. AT+WIFILOC](#6-atwifiloc)
- [7. 错误一览](#7-错误一览)
- [8. 联调顺序](#8-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| 阻塞 | `LBS` / `WIFISCAN` / `WIFILOC` 等到本次结束才回。扫描默认十几秒，AT 口会停一阵 |
| 无参查询 | `AT+LBS` / `AT+LBS?` **立刻做一次在线定位**（不是只读缓存） |
| 缓存 | 只有 `AT+LBS="cache"` 读上次成功结果，不上网 |
| 地址字段 | 在线定位仅当 `lbs_mode=3` 才回第三段地址；缓存里有地址也会带回 |
| `LBSCFG` | 短 reason。全量查询**不**打出 `tmr_rpt_data` 原文，只报长度 |
| `WIFISCAN` | 无参用默认扫描参数；扫不到 AP 仍 `OK`（没有 `+WIFISCAN` 行） |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+LBS` | `=?` | 无参=在线定位 | `"cache"` 读缓存 | 基站定位 |
| `AT+LBSCFG` | `=?` | `?` 全量；`"<key>"` 单项 | `"<key>",<value>` | 与 `[lbs]` 同一套 key |
| `AT+WIFISCAN` | `=?` | 无参=默认参数扫一圈 | 最多 7 个扫描参数 | 同步扫 AP |
| `AT+WIFILOC` | `=?` | 无参=默认最少 5 个 AP | `<min_ap>` | 先扫再问云端 |

---

## 3. AT+LBS {#3-atlbs}

按当前运行配置做一次基站定位（`lbs_mode` 决定单站 / 多站 / 是否带地址）。全系统同时只跑一路；和 Lua `lbs.sync` 抢同一条。

### 3.1 测试

```lua
AT+LBS=?
```

```lua
+LBS: query location with built-in config
AT+LBS / AT+LBS?           : live query
AT+LBS="cache"            : read last cached result

OK
```

### 3.2 在线定位

```lua
AT+LBS
```

或 `AT+LBS?`。超时、重试用 `LBSCFG` 里已生效的值。

**成功（`lbs_mode` 为 1 或 2）**

```lua
+LBS: "<longitude>","<latitude>"

OK
```

**成功（`lbs_mode` 为 3，地理反编码）**

```lua
+LBS: "<longitude>","<latitude>","<address>"

OK
```

经纬度是文本，不是浮点格式约定。地址可能为空串。

经纬度任一为空 → CME **130**。

### 3.3 读缓存

```lua
AT+LBS="cache"
```

只认这一词（大小写不敏感）。其它字符串 → CME **105**。缺参 / 不是字符串 → **105**。

缓存里经纬度齐全才成功。从未成功过、或缓存空 → **130**。缓存带地址时回三段，否则两段。

### 3.4 示例

```lua
AT+ISLINK
+ISLINK: 1

OK

AT+LBS
+LBS: "121.4737","31.2304"

OK

AT+LBS="cache"
+LBS: "121.4737","31.2304"

OK
```

### 3.5 失败 CME

| 码 | 可能原因 |
| --- | --- |
| 105 | `"cache"` 拼错；设置形态缺参 |
| 112 | 内存不足 |
| 130 | 未驻网、HTTP/DNS 失败、服务器错误、超时、PID 失败、结果无经纬度 |
| 140 | 小区信息未就绪 |
| 150 | 读 IMEI 失败 |
| 151 | 本条基站定位一般不会到；Wi-Fi 扫描失败码见 WIFILOC |

`+CME ERROR` 之后**没有** `OK`。

---

## 4. AT+LBSCFG {#4-atlbscfg}

按 key 读写 LBS 持久化配置，与 [`[lbs]`](../api/rtu_config/rtu_config.md#26-lbs) 同名。key 大小写不敏感（内部折成小写）。

出厂默认：

| key | 默认 |
| --- | --- |
| `lbs_mode` | 1 |
| `timeout_s` / `timeout_r` | 3 / 3（`0` 表示用内置默认） |
| `retry_count` | 1（`0` 表示用内置默认） |
| `tmr_en` | 0 |
| `tmr_period_s` | 60 |
| `tmr_rpt_type` | 0 |
| `tmr_rpt_data` | 空（长度 0） |
| `tmr_rpt_route` | 空 |

写配置**不**打断正在进行的那一次定位。定时任务按落盘后的值跑。

### 4.1 测试

```lua
AT+LBSCFG=?
```

```lua
+LBSCFG: ("lbs_mode|timeout_s|timeout_r|retry_count|tmr_en|tmr_period_s|tmr_rpt_type|tmr_rpt_data|tmr_rpt_route|reset",<value>)
query : AT+LBSCFG="key"
query all: AT+LBSCFG?
set   : AT+LBSCFG="lbs_mode",1|2|3 / AT+LBSCFG="timeout_s",30 / AT+LBSCFG="tmr_rpt_data",<TAILRAW> / AT+LBSCFG="reset",1

OK
```

### 4.2 查询全部

```lua
AT+LBSCFG?
```

或 `AT+LBSCFG`。顺序固定（**没有** `tmr_rpt_data` 原文，只有长度）：

```lua
+LBSCFG: "lbs_mode",1
+LBSCFG: "timeout_s",3
+LBSCFG: "timeout_r",3
+LBSCFG: "retry_count",1
+LBSCFG: "tmr_en",0
+LBSCFG: "tmr_period_s",60
+LBSCFG: "tmr_rpt_type",0
+LBSCFG: "tmr_rpt_data_len",0
+LBSCFG: "tmr_rpt_route",""

OK
```

读失败 → `"error read"`。申请失败 → `malloc`。拼包 → `format` / `overflow`。

### 4.3 查询单项

第二参不出现或长度为 0：

```lua
AT+LBSCFG="lbs_mode"
+LBSCFG: "lbs_mode",1

OK
```

`tmr_rpt_route` 回带引号的文本。`tmr_rpt_data` 单项查询：

```lua
+LBSCFG: "tmr_rpt_data",<len>
<原始字节>

OK
```

长度为 0 时没有中间那行裸数据。`reset` 当查询会读当前配置（数字 0），不是执行恢复。

### 4.4 设置

```lua
AT+LBSCFG="<key>",<value>
```

| key | value | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `lbs_mode` | 整数 | **1 / 2 / 3** | 1=单基站；2=多基站（AT 不带地址）；3=反编码（带地址） |
| `timeout_s` | 整数 | 任意 u32，`0`=内置默认 | 秒 |
| `timeout_r` | 整数 | 同上 | 另一路超时 |
| `retry_count` | 整数 | 0～255，`0`=内置默认 | 重试 |
| `tmr_en` | 整数 | 0 或 1 | 定时采集 |
| `tmr_period_s` | 整数 | **≥1** | 周期秒；写 0 失败 |
| `tmr_rpt_type` | 整数 | 0 / 1 / 2 | 0=只采集；1=AT URC；2=自定义文本 |
| `tmr_rpt_data` | TAILRAW | 最长 **256** 字节 | 类型 2 的载荷，可含占位符 |
| `tmr_rpt_route` | 文本 | 最长 127；空或合法路由串 | 例如 `6[1]`。非空且路由非法则失败 |
| `reset` | 整数 | **必须是 1** | 整份回到出厂并落盘 |

`tmr_rpt_type=2` 且要展开占位符：还要 [`map.all`](sys.md#11-atdevicecfg) 与 `map.lbs_timer` 为 1。

设置成功：数字/文本 key 回显写入后的值。`tmr_rpt_data` 写成功后回的是 **`"tmr_rpt_data_len",<len>`**（不再打原文）。`reset` 成功：

```lua
+LBSCFG: "reset",1

OK
```

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 第一参不是字符串 |
| `key` | key 空、过长、不是上表名字 |
| `lbs_mode` / `timeout_s` / … | 该 key 的值解析失败或越界（reason **就是 key 名**） |
| `save` | 落盘失败 |
| `config` | 写完后回读失败 |
| `read` / `malloc` / `format` / `overflow` | 全量查询 |

### 4.5 示例

```lua
AT+LBSCFG="lbs_mode",3
+LBSCFG: "lbs_mode",3

OK

AT+LBSCFG="tmr_en",1
+LBSCFG: "tmr_en",1

OK

AT+LBSCFG="tmr_period_s",120
+LBSCFG: "tmr_period_s",120

OK

AT+LBSCFG="reset",1
+LBSCFG: "reset",1

OK
```

---

## 5. AT+WIFISCAN {#5-atwifiscan}

同步扫周围 AP。模组没有独立 Wi-Fi 网卡，走蜂窝侧嗅探。格式：

```lua
+WIFISCAN:(-,"<ssid>",<rssi>,"<bssid>",<channel>)
```

无 SSID 时第二段为空：`+WIFISCAN:(-,,<rssi>,"<bssid>",<channel>)`。最多 **40** 条。

### 5.1 测试

```lua
AT+WIFISCAN=?
```

```lua
+WIFISCAN: sync wifi scan (format same as ECWIFISCAN)
AT+WIFISCAN
AT+WIFISCAN=<time>,<round>,<maxbssid>,<scantimeout>,<priority>,<channelRecLen>,<channelCount>
+WIFISCAN:(-,"<ssid>",<rssi>,"<bssid>",<channel>)

OK
```

### 5.2 默认参数（查询形态）

```lua
AT+WIFISCAN
```

或 `AT+WIFISCAN?`。内部默认：

| 参数 | 默认 |
| --- | --- |
| `<time>` | 12000 ms（总超时） |
| `<round>` | 1 |
| `<maxbssid>` | 5 |
| `<scantimeout>` | 5 s（每轮） |
| `<priority>` | 0 |
| `<channelRecLen>` | 280 ms |
| `<channelCount>` | 1 |

扫完后每 AP 一行 `+WIFISCAN`，最后 `OK`。一个都没有也 `OK`。

### 5.3 指定参数

```lua
AT+WIFISCAN=<time>,<round>,<maxbssid>,<scantimeout>,<priority>,<channelRecLen>,<channelCount>
```

引擎按规则收参（均可选，从左填）。范围：

| 参数 | 范围 | 说明 |
| --- | --- | --- |
| `<time>` | 4000～255000 | 总超时 ms |
| `<round>` | 1～3 | 轮数 |
| `<maxbssid>` | 4～40 | 最多报多少个 AP |
| `<scantimeout>` | 1～255 | 每轮秒 |
| `<priority>` | 0 或 1 | 与蜂窝的优先级 |
| `<channelRecLen>` | 100～280 | 每信道停留 ms |
| `<channelCount>` | 1～14 | 信道数 |

额外约束：**`<time>` ≥ `<round>` × `<scantimeout>` × 1000**，否则 CME **105**。

### 5.4 示例

```lua
AT+WIFISCAN
+WIFISCAN:(-,"Office",-62,"AA:BB:CC:DD:EE:FF",6)
+WIFISCAN:(-,"Guest",-80,"11:22:33:44:55:66",1)

OK
```

### 5.5 失败 CME

| 码 | 可能原因 |
| --- | --- |
| 105 | 总超时小于「轮数×每轮秒×1000」；或底层参数非法 |
| 139 | 扫描超时 |
| 151 | 其它扫描失败 |

---

## 6. AT+WIFILOC {#6-atwifiloc}

先扫 AP，数量够了再向云端要经纬度和地址。必须已驻网。最少 AP 数默认 **5**，可改 1～40。

成功**永远三段**（地址可能为空串）：

```lua
+WIFILOC: "<longitude>","<latitude>","<address>"

OK
```

### 6.1 测试

```lua
AT+WIFILOC=?
```

```lua
+WIFILOC: sync wifi scan + doiot wifi location
AT+WIFILOC / AT+WIFILOC?              : query with defaults
AT+WIFILOC=<min_ap>                   : optional min AP count
+WIFILOC: "<lon>","<lat>","<address>"

OK
```

### 6.2 默认最少 AP

```lua
AT+WIFILOC
```

或 `AT+WIFILOC?`。`min_ap=5`。

### 6.3 指定最少 AP

```lua
AT+WIFILOC=8
```

`<min_ap>` 必须是数字，**1～40**。扫到的 AP 少于该数会失败（归到超时/定位失败一类 CME）。

### 6.4 示例

```lua
AT+WIFILOC=5
+WIFILOC: "121.4737","31.2304","上海市黄浦区"

OK
```

### 6.5 失败 CME

| 码 | 可能原因 |
| --- | --- |
| 105 | 设置形态不是数字；`min_ap` 不是 1～40 |
| 112 | 内存不足 |
| 130 | 结果无经纬度；未驻网 / HTTP 失败（未单独归到其它码时） |
| 139 | 超时（本条超时类默认归 139，不是 130） |
| 140 | 小区未就绪（少见，本路径主要靠 Wi-Fi） |
| 150 | IMEI 失败 |
| 151 | Wi-Fi 扫描失败；AP 数量不够也会走到扫描/定位失败 |

---

## 7. 错误一览

`LBS` / `WIFISCAN` / `WIFILOC`：只有 `+CME ERROR: <n>`，后面没有 `OK`。

| 码 | 指令 | 含义 |
| --- | --- | --- |
| 105 | 全部 | 参数非法 |
| 112 | LBS / WIFILOC | 内存不足 |
| 130 | LBS；WIFILOC 无经纬度等 | 定位失败 / 未驻网 / HTTP |
| 139 | WIFISCAN；WIFILOC 超时 | 扫描或定位超时 |
| 140 | LBS | 小区未就绪 |
| 150 | LBS / WIFILOC | IMEI 失败 |
| 151 | WIFISCAN / WIFILOC | 扫描失败 |

`LBSCFG` 短 reason：`param`、`key`、各 key 名、`save`、`config`、`read`、`malloc`、`format`、`overflow`。

---

## 8. 联调顺序

1. `CFUN=1` → `ISLINK=1`。
2. `AT+LBSCFG="lbs_mode",1`（只要经纬度）或 `3`（还要地址）。
3. `AT+LBS` 看两段或三段；再 `AT+LBS="cache"` 对照。
4. 定时上报：`tmr_en=1`、`tmr_period_s`、`tmr_rpt_type`；类型 2 再写 `tmr_rpt_data` / `tmr_rpt_route`。
5. Wi-Fi：先 `AT+WIFISCAN` 确认能扫到 AP，再 `AT+WIFILOC`。
6. 脚本侧同一套能力：`lbs.sync` / `lbs.cache`、`wifiscan.scan` / `wifiscan.location`。不要在 UART/MQTT 回调里调同步定位。

完整 key 也可用 `AT+LBSCFG?` 与 `rtu_config.cfg` 的 `[lbs]` 对照。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：LBS / LBSCFG / WIFISCAN / WIFILOC，链 Lua lbs / wifiscan 与 `[lbs]` |
