#  链路（APN / 低功耗 / 切卡 / 原厂通道 / USB 网卡）

**文档版本** `1.1.0`

配默认上网 APN、低功耗模式、唤醒脚、深睡定时器、双卡槽、经 UART 转发一行原厂 AT，以及 USB 4G 网卡。行格式、两种失败风格见 [convention.md](convention.md)。驻网状态见 [netstat.md](netstat.md)。

APN 写入默认数据承载 **CID=1**，掉电保留。`SIMCFG` 的 `sim.*` 是开机默认；`SIMSLOT` 是运行时切卡。`WKPAD` / `DSTMR` 只改本次运行，不写 Flash。Lua 对照：`require("lp")` / `rndis`。

---

## 目录

- [1. 本篇差异](#1-本篇差异)
- [2. 指令一览](#2-指令一览)
- [3. AT+APN](#3-atapn)
- [4. AT+APNAUTH](#4-atapnauth)
- [5. AT+LP](#5-atlp)
- [6. AT+WKPAD](#6-atwkpad)
- [7. AT+DSTMR](#7-atdstmr)
- [8. AT+SIMCFG](#8-atsimcfg)
- [9. AT+SIMSLOT](#9-atsimslot)
- [10. AT+DOSIMSLOT](#10-atdosimslot)
- [11. AT+RILAT](#11-atrilat)
- [12. AT+RNDIS](#12-atrndis)
- [13. AT+RNDISSAVE](#13-atrndissave)
- [14. 错误一览](#14-错误一览)
- [15. 联调顺序](#15-联调顺序)
- [修订记录](#修订记录)

---

## 1. 本篇差异

| 项 | 约定 |
| --- | --- |
| APN / APNAUTH | 失败走 `+CME ERROR`。参数错是 **105**。读/写协议栈失败时，有时回 **底层数字**（常见负数，**不是** convention 101～156） |
| LP / WKPAD / DSTMR / RNDIS / RNDISSAVE | 短 reason：`+CMD: "error <reason>"` + `ERROR` |
| SIMCFG | 混用：缺参 / 值非法 / 未知 key 走 CME **105** / **104**；读盘失败走短 reason |
| SIMSLOT / DOSIMSLOT | 失败走 CME。外部卡槽编号 **1 / 2** |
| RILAT | **只在 UART AT 口**。`mode=1` 后先打 `>`，再按 [UARTQUE](uart.md#4-atuartque) 读一包原厂 AT。失败是整句 reason，不是短词 |
| 无参查询 | `APN` / `APNAUTH` / `LP` / `WKPAD` / `DSTMR` / `RNDIS` / `RNDISSAVE` / `SIMSLOT` / `DOSIMSLOT`：`AT+XXX` 与 `AT+XXX?` 等价。`WKPAD` / `DSTMR` 的无参查询打出全部编号；带编号的 `AT+WKPAD=<pad>`、`AT+DSTMR=<id>` 与 `AT+XXX=<n>?` 等价，只查一路 |

---

## 2. 指令一览

| 指令 | 测试 | 查询 | 设置 | 作用 |
| --- | --- | --- | --- | --- |
| `AT+APN` | `=?` | 无参 | `"<apn>"` 或带鉴权；`"factory"` 恢复空 APN | 默认 CID=1 的 APN（NVM） |
| `AT+APNAUTH` | `=?` | 无参 | `"<user>","<pass>","<auth>"` | 只改 CID=1 的 PAP/CHAP |
| `AT+LP` | `=?` | 无参 | `"<mode>"` | 低功耗模式字符串 |
| `AT+WKPAD` | `=?` | 无参为全部；`<pad>` 或 `<pad>?` 为单路 | `<pad>,<en>,<pos>,<neg>,<pu>,<pd>` | 唤醒脚，仅本次运行 |
| `AT+DSTMR` | `=?` | 无参为全部；`<id>` 或 `<id>?` 为单路 | `<id>,<ms>`，`ms=0` 停止 | 深睡定时器，单位毫秒 |
| `AT+SIMCFG` | `=?` | `?` 全量；`"<key>"` 单项 | `"<key>",<TAILRAW>` | 开机默认切卡策略 |
| `AT+SIMSLOT` | `=?` | 无参 | `<1\|2>` | **运行时**切卡 |
| `AT+DOSIMSLOT` | `=?` | 无参 | `<1\|2>` | 立刻选外部卡槽 |
| `AT+RILAT` | `=?` | 无 | `1` 然后 `>` 后再发一包 | 转发一行原厂 AT |
| `AT+RNDIS` | `=?` | 无参 | `<0\|1>` | USB 网卡**本次**开关 |
| `AT+RNDISSAVE` | `=?` | 无参 | `<0\|1>` | 本次并写入 NVM |

没有「执行命令」形态的空 `AT+APN=`。`AT+FACTORY` 的 APN 恢复见 [sys.md](sys.md#13-atfactory)；本篇用 `AT+APN="factory"`。

---

## 3. AT+APN {#3-atapn}

读写默认上网 APN（CID=1），写入协议栈 NVM，掉电保留。APN 最长 **99** 字符。用户名 / 密码最长 **64** 字符。

### 3.1 测试

```lua
AT+APN=?
```

```lua
+APN: query/set default APN (cid=1, saved in NVM)
AT+APN / AT+APN?
  +APN: "<apn>","<user>","<pass>","<auth>"
AT+APN="<apn>"
  set APN only, keep current auth
AT+APN="<apn>","<user>","<pass>"[,"<auth>"]
  set APN+auth; auth omitted: PAP if user/pass else NONE
AT+APN="factory"
  restore factory: empty APN, no user/pass, auth=NONE
auth: NONE, PAP, CHAP, CHAP_PAP

OK
```

### 3.2 查询

```lua
AT+APN
```

或 `AT+APN?`。

**成功**

```lua
+APN: "<apn>","<user>","<pass>","<auth>"

OK
```

未配时 APN / 用户 / 密码可能是空串 `""`，鉴权为 `"NONE"`。

读失败：`+CME ERROR: <n>`（底层数字，见 [第 14 节](#14-错误一览)）。**没有**随后的 `OK`。

### 3.3 只改 APN（保留当前鉴权）

```lua
AT+APN="<apn>"
```

`<apn>` 必须是字符串。长度 0～99。成功回显四字段（鉴权仍是原来的）。

### 3.4 恢复空 APN

```lua
AT+APN="factory"
```

大小写不敏感。恢复为：空 APN、无用户/密码、`auth=NONE`。成功仍回四字段。

### 3.5 同时写 APN 与鉴权

```lua
AT+APN="<apn>","<user>","<pass>"[,"<auth>"]
```

| 参数 | 说明 |
| --- | --- |
| `<apn>` | 字符串，0～99 |
| `<user>` / `<pass>` | 字符串，0～64 |
| `<auth>` | 可省略。省略时：用户或密码非空 → `PAP`，否则 `NONE` |

`<auth>` 大小写不敏感，合法值：

| 写入 | 回显 |
| --- | --- |
| `NONE` 或 `NULL` 或空串 | `NONE` |
| `PAP` | `PAP` |
| `CHAP` | `CHAP` |
| `CHAP_PAP` 或 `CHAP+PAP` | `CHAP_PAP` |

**正好 2 个参数非法**（例如只写了 APN 和用户）→ CME **105**。

### 3.6 示例

```lua
AT+APN="cmiot"
+APN: "cmiot","","","NONE"

OK

AT+APN="cmiot","user","pass","PAP"
+APN: "cmiot","user","pass","PAP"

OK

AT+APN="factory"
+APN: "","","","NONE"

OK
```

### 3.7 失败

| 码 | 可能原因 |
| --- | --- |
| **105** | 缺参；APN 不是文本或超过 99；用户/密码解析失败；正好 2 个参数；鉴权不是上表那些词 |
| **底层数字** | 读/写协议栈失败。常见 `-1` 通用失败、`-2` 底层参数非法、`-7` 超时、`-8` SIM 未插、`-11` 未上电（如 `CFUN=0`）、`-12` SIM 忙。**不要**按 convention 101～156 猜本条 |

---

## 4. AT+APNAUTH {#4-atapnauth}

只改 CID=1 的用户名、密码和鉴权类型，**不改 APN 名**。同样写入 NVM。

### 4.1 测试

```lua
AT+APNAUTH=?
```

```lua
+APNAUTH: query/set default APN auth (cid=1, saved in NVM)
AT+APNAUTH / AT+APNAUTH?                              : query auth
AT+APNAUTH="<user>","<pass>","<auth>"            : set auth
auth: NONE, PAP, CHAP, CHAP_PAP

OK
```

### 4.2 查询

```lua
AT+APNAUTH
```

```lua
+APNAUTH: "<user>","<pass>","<auth>"

OK
```

### 4.3 设置

必须 **正好 3 个参数**：

```lua
AT+APNAUTH="<user>","<pass>","<auth>"
```

`<auth>` 取值与 `AT+APN` 相同。成功回显刚写入的三字段。

少参、鉴权非法、用户/密码解析失败 → CME **105**。协议栈失败 → 底层数字。

### 4.4 示例

```lua
AT+APNAUTH="user","pass","CHAP"
+APNAUTH: "user","pass","CHAP"

OK
```

---

## 5. AT+LP {#5-atlp}

设置 / 查询低功耗模式。模式是**字符串**，不是数字（数字入口是 [AT+PMU](sys.md#9-atpmu)）。

| 字符串 | 含义 |
| --- | --- |
| `normal` | 常规，CPU 满功率 |
| `low_power` | 低功耗，CPU 降频 |
| `low_power2` | 超低功耗（无网络侧更省） |
| `psm` | PSM+，唤醒即复位 |

大小写不敏感。写入后立刻按该模式管理睡眠深度。

### 5.1 测试

```lua
AT+LP=?
```

```lua
+LP: ("normal"|"low_power"|"low_power2"|"psm")
set: AT+LP="mode"
query: AT+LP or AT+LP?

OK
```

### 5.2 查询

```lua
AT+LP
```

```lua
+LP: "normal"

OK
```

查询无失败分支。

### 5.3 设置

```lua
AT+LP="low_power"
```

第一参必须是字符串。

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参或不是字符串 |
| `mode` | 不是上表四个词 |

### 5.4 示例

```lua
AT+LP="psm"
+LP: "psm"

OK
```

---

## 6. AT+WKPAD {#6-atwkpad}

设置 / 查询一根唤醒脚。参数顺序与 `lp.wkpad` 相同。只改本次运行，掉电或冷启动后回到固件默认。

| 参数 | 取值 | 含义 |
| --- | --- | --- |
| `pad` | `0`～`5` | 唤醒脚编号，与 [lp 的唤醒脚](../../api/module/lp.md#5-5-wkpad) 同一套 |
| `en` | `0` / `1` | 是否当作唤醒脚。`0`～`2` 不能设成 `0` |
| `pos` | `0` / `1` | 上升沿 |
| `neg` | `0` / `1` | 下降沿 |
| `pu` | `0` / `1` | 内部上拉 |
| `pd` | `0` / `1` | 内部下拉 |

上拉和下拉不能同时为 `1`。`pos` 和 `neg` 都是 `0` 时，这只脚不会唤醒，跟 `en` 是否为 `1` 无关。成功应答是写完之后的回读，六个数字依次是 `pad,en,pos,neg,pu,pd`。

### 6.1 测试

```lua
AT+WKPAD=?
```

```lua
+WKPAD: (0-5),(0-1),(0-1),(0-1),(0-1),(0-1)
pad,en,pos,neg,pull_up,pull_down
set: AT+WKPAD=<pad>,<en>,<pos>,<neg>,<pu>,<pd>
query one: AT+WKPAD=<pad> or AT+WKPAD=<pad>?
query all: AT+WKPAD or AT+WKPAD?
pad 0-2 cannot set en=0; pull_up and pull_down cannot both be 1
pos=0 and neg=0 will not wake; runtime only, not saved

OK
```

### 6.2 查询

无参打出 `0`～`5` 各一行。`AT+WKPAD` 与 `AT+WKPAD?` 相同。

```lua
AT+WKPAD
```

```lua
+WKPAD: 0,1,0,1,1,0
+WKPAD: 1,0,0,0,0,0
+WKPAD: 2,0,0,0,0,0
+WKPAD: 3,0,0,0,0,0
+WKPAD: 4,0,0,0,0,0
+WKPAD: 5,0,0,0,0,0

OK
```

只查一路：`AT+WKPAD=0` 与 `AT+WKPAD=0?` 相同。

```lua
AT+WKPAD=0
```

```lua
+WKPAD: 0,1,0,1,1,0

OK
```

### 6.3 设置

六个参数都要给。下面把 WAKEUP0 配成唤醒、上下沿都开、内部下拉。

```lua
AT+WKPAD=0,1,1,1,0,1
```

```lua
+WKPAD: 0,1,1,1,0,1

OK
```

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参、个数不对，或开关不是 `0`/`1` |
| `pad` | 编号不在 `0`～`5` |
| `disable` | 对 `0`～`2` 传入 `en=0` |
| `pull` | 上拉和下拉同时为 `1` |

---

## 7. AT+DSTMR {#7-atdstmr}

启动、停止或查询深睡定时器。对应 `lp.dstmr`、`lp.dstmr_stop`、`lp.dstmr_on`、`lp.dstmr_left`。时间单位是毫秒。

| 参数 | 取值 | 含义 |
| --- | --- | --- |
| `id` | `0`～`6` | `0` 和 `1` 不写 Flash，最长约 2.5 小时。`2`～`6` 启停写入 Flash，最长约 740 小时。`7`～`9` 不开放 |
| `ms` | `0`～`2147483647` | 大于 `0` 为启动。`0` 为停止。解析器是有符号整数，比 Lua 的 `4294967295` 上限小 |

查询和设置成功都回读：`+DSTMR: <id>,<on>,<left_ms>`。`on` 为 `1` 表示还在走，`0` 表示已停。已停时 `left_ms` 打 `0`，不要把它当成剩余时间。没有单独的到期上报；Hibernate 醒来后用 `lp.wake_src` / `lp.last_slp` 看是不是定时器复位。

`0`/`1` 和 `2`～`6` 都能在 PSM（Hibernate）里走时并唤醒。差别只是存不存 Flash、最长能定多久。

### 7.1 测试

```lua
AT+DSTMR=?
```

```lua
+DSTMR: (0-6),(0-2147483647)
id,ms  unit ms; ms=0 stops
set: AT+DSTMR=<id>,<ms>
query one: AT+DSTMR=<id> or AT+DSTMR=<id>?
query all: AT+DSTMR or AT+DSTMR?
reply: +DSTMR: <id>,<on>,<left_ms>
id 0-1 no flash, about 2.5h; id 2-6 write flash, about 740h

OK
```

### 7.2 查询

无参打出 `0`～`6`。`AT+DSTMR` 与 `AT+DSTMR?` 相同。

```lua
AT+DSTMR=2
```

```lua
+DSTMR: 2,1,179998

OK
```

`AT+DSTMR=2?` 与上面相同。

### 7.3 设置

启动 2 号定时器，3 分钟：

```lua
AT+DSTMR=2,180000
```

```lua
+DSTMR: 2,1,180000

OK
```

停掉 2 号：

```lua
AT+DSTMR=2,0
```

```lua
+DSTMR: 2,0,0

OK
```

**失败 reason**

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参，或类型不是数字 |
| `id` | 不是 `0`～`6` |
| `ms` | 小于 `0` |

---

## 8. AT+SIMCFG {#8-atsimcfg}

读写**开机默认**的双卡策略，落盘。**不是**当前正在用的卡槽（当前槽用 `SIMSLOT` / `DOSIMSLOT`）。

外部卡槽编号 **1 / 2**（查询 `sim.slot` 也按 1/2 回）。

出厂常用默认：

| key | 默认 | 说明 |
| --- | --- | --- |
| `sim.slot` | 1 | 开机默认外部卡槽 |
| `sim.sw_auto` | 1 | 自动切卡（仅 `normal` / `low_power` 监测） |
| `sim.ready_time` | 3 | 卡就绪超时（秒）。ICCID 一直拿不到则切另一张。**不能写 0** |
| `sim.attach_time` | 60 | 驻网超时（秒）。已就绪但未驻网则切卡。**不能写 0** |
| `sim.sw_num` | 8 | 连续自动切卡上限（1～255，**不能写 0**） |
| `sim.sw_silent` | 600 | 达到上限后的静默秒数。**不能写 0** |
| `sim.remember` | 0 | 是否记住上次驻网成功的卡槽 |
| `sim.slot2_disable` | 0 | `1`：禁用外部卡槽 2，调度不再切过去 |

值用 **TAILRAW**（最后一个逗号后的原文），会去掉首尾空白再解析成十进制。

### 8.1 测试

```lua
AT+SIMCFG=?
```

```lua
+SIMCFG: ("key"[,<TAILRAW>])
sim.slot(1|2) sim.sw_auto(0|1)
sim.ready_time sim.attach_time
sim.sw_num sim.sw_silent
sim.remember(0|1) sim.slot2_disable(0|1)
query all: AT+SIMCFG?

OK
```

### 8.2 查询全部

```lua
AT+SIMCFG?
```

或 `AT+SIMCFG`。连续八行，顺序固定：

```lua
+SIMCFG: "sim.slot",1
+SIMCFG: "sim.sw_auto",1
+SIMCFG: "sim.ready_time",3
+SIMCFG: "sim.attach_time",60
+SIMCFG: "sim.sw_num",8
+SIMCFG: "sim.sw_silent",600
+SIMCFG: "sim.remember",0
+SIMCFG: "sim.slot2_disable",0

OK
```

读盘失败 → `+SIMCFG: "error read"`。申请失败 → `malloc`。拼包失败 → `format` / `overflow`。

### 8.3 查询单项 / 设置

无第二参（或 TAILRAW 长度为 0）当查询：

```lua
AT+SIMCFG="sim.slot"
+SIMCFG: "sim.slot",1

OK
```

有 TAILRAW 当设置：

```lua
AT+SIMCFG="sim.slot",2
+SIMCFG: "sim.slot",2

OK
```

| key | 合法值 | 失败 |
| --- | --- | --- |
| `sim.slot` | 1 或 2 | 其它 → CME **105** |
| `sim.sw_auto` | 0 或 1 | CME **105** |
| `sim.ready_time` | ≥1 的十进制秒 | 0 / 非数字 → CME **105** |
| `sim.attach_time` | ≥1 | 同上 |
| `sim.sw_num` | 1～255 | 0 或超过 255 → CME **105** |
| `sim.sw_silent` | ≥1 秒 | 0 / 非数字 → CME **105** |
| `sim.remember` | 0 或 1 | CME **105** |
| `sim.slot2_disable` | 0 或 1 | CME **105**。`1` 时调度不再切到外部卡槽 2 |

未知 key → CME **104**。第一参不是字符串 → CME **105**。落盘失败 → `"error write"`。

写的是开机默认。已经跑着的卡不会因为本指令立刻换槽；要当场切用 `AT+SIMSLOT`。

### 8.4 示例

```lua
AT+SIMCFG="sim.sw_auto",1
+SIMCFG: "sim.sw_auto",1

OK

AT+SIMCFG="sim.ready_time",5
+SIMCFG: "sim.ready_time",5

OK
```

---

## 9. AT+SIMSLOT {#9-atsimslot}

**运行时**查 / 切当前卡槽。不改 `SIMCFG` 里的开机默认。

### 9.1 测试

```lua
AT+SIMSLOT=?
```

```lua
+SIMSLOT: <sim_id>
sim_id: 1=SIM1, 2=SIM2
set: AT+SIMSLOT=<sim_id>
query: AT+SIMSLOT?

OK
```

### 9.2 查询

```lua
AT+SIMSLOT?
```

或 `AT+SIMSLOT`。

```lua
+SIMSLOT: 1

OK
```

读失败 → CME **121**。

### 9.3 设置

```lua
AT+SIMSLOT=2
```

`<sim_id>` 必须是数字 **1 或 2**。成功：

```lua
+SIMSLOT: 2

OK
```

| 码 | 可能原因 |
| --- | --- |
| 105 | 缺参、不是数字、不是 1/2 |
| 122 | 运行时切卡请求失败（未就绪、忙等） |

---

## 10. AT+DOSIMSLOT {#10-atdosimslot}

立刻按外部卡槽 1/2 选择（会走射频开关流程）。查询形态与 `SIMSLOT` 相同，都是当前槽。

与 `SIMSLOT` 的差别：本指令直接下到卡槽选择；`SIMSLOT` 走网络管理的运行时切卡队列。开机默认仍只看 `SIMCFG`。

### 10.1 测试

```lua
AT+DOSIMSLOT=?
```

帮助一行：`sim_id(1:SIM0,2:SIM1)`，外部编号仍是 **1 / 2**。

### 10.2 查询 / 设置

```lua
AT+DOSIMSLOT?
+DOSIMSLOT: 1

OK

AT+DOSIMSLOT=2
+DOSIMSLOT: 2

OK
```

| 码 | 可能原因 |
| --- | --- |
| 105 | 缺参、不是数字、不是 1/2 |
| 121 | 查询当前槽失败 |
| 122 | 设置失败 |

---

## 11. AT+RILAT {#11-atrilat}

只在 **UART AT 口** 有效。USB AT 口会失败。

流程：`AT+RILAT=1` → 模组先打一行 `>` → 主机再发 **一包**原厂 AT（整行，含结尾）。这一包必须按当前口的 [UARTQUE](uart.md#4-atuartque) 切出来（空闲断包 / 单包上限），不要拆成半行。模组把这包转给原厂引擎，再把原厂文本贴在 `+RILAT:<tx_len>` 后面。

阻塞：等主机这包最多约 **10 s**；等原厂应答最多约 **60 s**（看到 `OK` / `ERROR` / `CME ERROR` 才算完）。

**仅设置，无查询。** `mode` 只能是 **1**。

### 11.1 测试

```lua
AT+RILAT=?
```

帮助说明：`mode(1 only)`，先 `>`，再按 UARTQUE 读一包并转发。

### 11.2 设置

```lua
AT+RILAT=1
>
AT+CGSN
+RILAT:8
<原厂应答文本>

OK
```

`+RILAT:` 后的数字是**交给原厂的字节数**（你刚发的那包长度），不是原厂回包长度。原厂文本原样写出，再跟应用侧 `OK`。

主机侧建议：先把该 UART 的 `max_wait_ms` 配成能收下一整行 AT（见 `AT+UARTQUE`），再发 `AT+RILAT=1`，看到 `>` 后立刻写一行原厂命令并以行结束符收尾。

### 11.3 失败 reason

形态：`+RILAT: "error <…>"` + `ERROR`。

| reason（原文） | 可能原因 |
| --- | --- |
| `need uart channel` | 当前口不是 UART AT（例如 USB AT） |
| `param use 1` | `mode` 不是 1 |
| `FEATURE_RIL_AT_API_ENABLE off` | 本镜像未打开原厂转发 |
| `block_read (need UARTQUE)` | 10 s 内没收到一包，或分包没配好、半行被切开 |
| `atRilAtCmdReq <n>` | 转发给原厂失败，`<n>` 为底层返回码 |
| `timeout or empty rsp` | 60 s 内没有完整原厂应答，或回包为空 |

缺参 / 不是数字：本指令不回 `+RILAT`（引擎当形态不支持）。

---

## 12. AT+RNDIS {#12-atrndis}

USB 当 4G 网卡的**本次**开关。**不写**开机策略。开机策略用 `RNDISSAVE`。

### 12.1 测试

```lua
AT+RNDIS=?
```

```lua
+RNDIS: (enable)
enable:0-1, USB 4G NIC this session only (not NVM)
set: AT+RNDIS=<enable>
query: AT+RNDIS? -> +RNDIS: enable,bound
persist: AT+RNDISSAVE=<enable>

OK
```

### 12.2 查询

```lua
AT+RNDIS?
```

```lua
+RNDIS: <enable>,<bound>

OK
```

| 字段 | 含义 |
| --- | --- |
| `<enable>` | 当前是否打开 |
| `<bound>` | 是否已绑到默认 CID（1=已绑） |

读失败 → `"error read"`。

### 12.3 设置

```lua
AT+RNDIS=1
+RNDIS: 1,1

OK
```

`<enable>` 只能 0/1。成功回显当前 `enable,bound`。

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参或不是数字 |
| `enable` | 不是 0/1 |
| `set` | 本次开关失败 |

### 12.4 示例

```lua
AT+RNDIS=0
+RNDIS: 0,0

OK
```

---

## 13. AT+RNDISSAVE {#13-atrndissave}

立刻按 `<enable>` 开关，并写入 NVM（下次开机跟这个策略）。

### 13.1 测试

```lua
AT+RNDISSAVE=?
```

```lua
+RNDISSAVE: (enable)
enable:0-1, apply now and save boot policy to NVM
set: AT+RNDISSAVE=<enable>
query: AT+RNDISSAVE? -> +RNDISSAVE: saved

OK
```

### 13.2 查询

```lua
AT+RNDISSAVE?
+RNDISSAVE: 1

OK
```

只有一个数：NVM 里保存的开机策略。读失败 → `"error read"`。

### 13.3 设置

```lua
AT+RNDISSAVE=1
+RNDISSAVE: 1

OK
```

| reason | 可能原因 |
| --- | --- |
| `param` | 缺参或不是数字 |
| `enable` | 不是 0/1 |
| `save` | 写 NVM 或当场生效失败 |

---

## 14. 错误一览

### 14.1 `+CME ERROR`

| 码 | 指令 | 含义 |
| --- | --- | --- |
| 104 | SIMCFG | 未知 key |
| 105 | APN / APNAUTH / SIMCFG / SIMSLOT / DOSIMSLOT | 无效参数 |
| 121 | SIMSLOT / DOSIMSLOT 查询 | 读当前槽失败 |
| 122 | SIMSLOT / DOSIMSLOT 设置 | 切卡 / 设槽失败 |
| 底层数字（常为负数） | APN / APNAUTH | 协议栈返回码，**不是** 101～156。常见 `-1`～`-15`、`-127` |

现场可用 `AT+CMEERR` 对照 101～156；APN 的负数**不会**出现在那张表里。

### 14.2 短 reason

| reason | 指令 | 含义 |
| --- | --- | --- |
| `param` | LP / WKPAD / DSTMR / SIMCFG（短 reason 分支）/ RNDIS / RNDISSAVE | 形态不对 |
| `mode` | LP | 不是四个模式串 |
| `pad` | WKPAD | 编号不在 0～5 |
| `disable` | WKPAD | 对唤醒脚 0～2 传入关闭 |
| `pull` | WKPAD | 上拉和下拉同时为 1 |
| `id` | DSTMR | 编号不是 0～6 |
| `ms` | DSTMR | 毫秒小于 0 |
| `read` | SIMCFG / RNDIS / RNDISSAVE | 读配置失败 |
| `write` | SIMCFG | 落盘失败 |
| `malloc` / `format` / `overflow` | SIMCFG 全量查询 | 内存 / 拼包 |
| `enable` | RNDIS / RNDISSAVE | 不是 0/1 |
| `set` | RNDIS | 本次开关失败 |
| `save` | RNDISSAVE | 写 NVM 失败 |
| RILAT 整句 | 见 [第 11.3 节](#113-失败-reason) | |

---

## 15. 联调顺序

1. `AT+CFUN=1`，等 `AT+ISLINK` 为 1。
2. 专网卡：`AT+APN="<apn>"` 或带用户密码；要恢复空 APN：`AT+APN="factory"`。
3. 双卡：开机默认用 `AT+SIMCFG="sim.slot",1`；已经在跑要换槽用 `AT+SIMSLOT=2`。
4. 省电：`AT+LP="low_power"`（或 `AT+PMU=1`，见 sys 篇）。要定时从 Hibernate 醒来：`AT+DSTMR=2,180000` 再 `AT+LP="psm"`。唤醒脚用 `AT+WKPAD`，只对本次运行有效。
5. USB 上网：只要本次 `AT+RNDIS=1`；要开机也开 `AT+RNDISSAVE=1`。
6. 必须发原厂 AT：在 UART 口配好 `UARTQUE`，再 `AT+RILAT=1`，见 `>` 后发一行。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版：APN / APNAUTH / LP / SIMCFG / SIMSLOT / DOSIMSLOT / RILAT / RNDIS / RNDISSAVE |
| 1.1.0 | 2026-10-27 | 增加 `WKPAD`、`DSTMR` |
