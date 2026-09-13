# lcd

**文档版本** `1.1.1`

对象化 SPI 彩屏。`lcd.new(cfg)` 打开一路总线并初始化面板，之后在对象上填色、打点、刷一块 RGB565。

```lua
local lcd = require("lcd")
```

平台预加载模块，无需额外 `.lua` 文件。

**当前处于测试阶段。** 本模块用来验证 SPI 接到彩屏这条路径是否通，不是完整显示栈，也不是量产 GUI。现阶段 **只内置 ST7789** 一种面板库；其它控制器（ILI、GC、SSD 等）未挂。有客户需求时再按型号增加。接口、默认分辨率、脚位写法都可能随测试调整，不要当长期稳定契约依赖。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `lcd.new`](#6-1-new)
- [7. 对象方法](#7-对象方法)
  - [7.1 `obj:deinit`](#7-1-deinit)
  - [7.2 `obj:full`](#7-2-full)
  - [7.3 `obj:fill`](#7-3-fill)
  - [7.4 `obj:flush`](#7-4-flush)
  - [7.5 `obj:pixel`](#7-5-pixel)
  - [7.6 `obj:size`](#7-6-size)
  - [7.7 `obj:rotate`](#7-7-rotate)
  - [7.8 `obj:backlight`](#7-8-backlight)
  - [7.9 `obj:info`](#7-9-info)
- [8. `new` 配置表](#8-new-配置表)
- [9. 控制脚怎么写](#9-控制脚怎么写)
- [10. 颜色与像素缓冲](#10-颜色与像素缓冲)
- [11. 错误与返回约定](#11-错误与返回约定)
- [12. 资源上限与生命周期](#12-资源上限与生命周期)
- [13. 选型对照](#13-选型对照)
- [14. 完整示例](#14-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本侧流程：

1. `lcd.new(cfg)` 选定总线（`spi0` / `spi1` / `lspi0`）、面板驱动、分辨率和 DC/CS/RST/BL 脚，得到对象。
2. `obj:full` / `obj:fill` / `obj:pixel` 验证总线和屏能否出图。
3. 不用时 `obj:deinit`，整机才能再 `new` 一次。

测试阶段约定：

| 项 | 现状 |
| --- | --- |
| 用途 | 验证 SPI（含 LCD 专用 SPI）能否把像素送到屏 |
| 面板 | **仅 ST7789**。`driver` 省略即 `"st7789"`；写成别的名字会初始化失败 |
| 其它屏 | 未内置。有客户需求再加对应库 |
| GUI | 本模块只做同步填色/刷块。若后续把同一块屏交给图形栈占用，Lua 侧 `fill`/`full` 等会失败，文案为 `lcd bound to lvgl` |

不要用本模块当字体、窗口、图层引擎。整屏 `pixel` 循环会极慢，只适合打几个点确认坐标。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  lcd.new(cfg) → full / fill / pixel / rotate             │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  lcd 对象                                                │
│  · 整机同一时刻一块屏                                    │
│  · 配置表 → 总线名 + 面板名 + 控制脚                     │
│  · 绘图同步等到发完再返回                                │
└────────────────────────────┬────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼                             ▼
┌─────────────────────┐          ┌─────────────────────┐
│  SPI 总线            │          │  面板驱动            │
│  spi0 / spi1         │          │  目前仅 ST7789       │
│  或 lspi0（LCD 专用）│          │  开窗 / 旋转 / 偏移  │
│  DC·CS·RST·背光      │          │                      │
└─────────────────────┘          └─────────────────────┘
```

| 路径 | 调用当场做什么 | 是否让出协程 |
| --- | --- | --- |
| `new` | 开总线、复位、发面板初始化表 | **否**（含延时，可能数百毫秒） |
| `full` / `fill` / `flush` | 开窗并送像素，等到发完 | **否**（大块会占住调度） |
| `pixel` | 写一个点 | **否** |
| `rotate` / `backlight` / `info` / `size` | 改方向、背光或读状态 | **否** |
| `deinit` | 等未完成的刷写（最多约 3 秒）再关总线 | **否** |

`new` 会占用所选 SPI 控制器。同一路不要再给别的脚本当普通 SPI 用。

---

## 3. 对象模型

```lua
local panel = lcd.new({
    driver = lcd.ST7789,
    bus    = lcd.SPI0,
    width  = 240,
    height = 280,
    dc = 10,
    cs = 8,
})
```

`new` 返回带元表的 userdata。方法必须通过该对象调用。

### 3.1 两种调用写法

冒号是推荐写法：

```lua
panel:full(lcd.RED)
```

点号且自己传入对象，与冒号等价：

```lua
panel.full(panel, lcd.RED)
```

方法也挂在模块表上，下面同样合法：

```lua
lcd.full(panel, lcd.RED)
```

错误：

```lua
panel.full(lcd.RED)       -- 缺对象
lcd.full(lcd.RED)         -- 把颜色当成了对象
```

### 3.2 整机一份

底层只有一块屏的槽位。第一个对象还活着（未 `deinit`、未被回收）时，第二次 `new` 失败：`nil, "lcd already in use"`。

请在脚本里持有 `panel` 引用。对象被回收时会关总线；若仍要画，引用断了就会画出「lcd not initialized」。

### 3.3 布尔参数

`backlight` 的开关走 **真假语义**：`false` / `nil` 为假，**数字 `0` 为真**。请写 `true` / `false`，不要传 `0` / `1`。

配置里的 `bl_active_high` **只认布尔**。传数字会被忽略，保持默认「高电平点亮」。

---

## 4. 常量与枚举

### 4.1 面板与总线名

这些是 **字符串**，不是整数。可直接当 `driver` / `bus` 用。

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `lcd.ST7789` | `"st7789"` | 目前唯一内置的面板 | `cfg.driver` |
| `lcd.SPI0` | `"spi0"` | 通用 SPI 控制器 0 | `cfg.bus` |
| `lcd.SPI1` | `"spi1"` | 通用 SPI 控制器 1 | `cfg.bus` |
| `lcd.LSPI0` | `"lspi0"` | LCD 专用 SPI | `cfg.bus` |

`spi0` / `spi1`：命令/数据脚 **必须** 提供 `dc`；`cs` 建议提供；`rst` / `bl` 可选。

`lspi0`：DC、CS 由硬件脚承担，配置表里的 `dc` / `cs` 用不上；`rst` / `bl` 仍可按 GPIO 配。

未导出的总线名（例如随便写 `"spi2"`）初始化失败。未内置的 `driver`（非 `"st7789"`）同样失败。

### 4.2 旋转

用在 `cfg.rotate` 和 `obj:rotate(dir)`。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `lcd.ROTATE_0` | `0` | 与面板物理宽高一致 |
| `lcd.ROTATE_90` | `1` | 顺时针 90°，逻辑宽高对调 |
| `lcd.ROTATE_180` | `2` | 180° |
| `lcd.ROTATE_270` | `3` | 顺时针 270°，逻辑宽高对调 |

其它整数未定义。传入后面板侧可能失败，返回 `false` 加错误串。

### 4.3 预设颜色（RGB565）

用在 `full` / `fill` / `pixel` 的 `color`。也可用任意 `0`～`65535` 的 RGB565 整数。

| 符号 | 值 | 颜色 |
| --- | --- | --- |
| `lcd.BLACK` | `0x0000` | 黑 |
| `lcd.WHITE` | `0xFFFF` | 白 |
| `lcd.RED` | `0xF800` | 红 |
| `lcd.GREEN` | `0x07E0` | 绿 |
| `lcd.BLUE` | `0x001F` | 蓝 |
| `lcd.YELLOW` | `0xFFE0` | 黄 |
| `lcd.CYAN` | `0x07FF` | 青 |
| `lcd.MAGENTA` | `0xF81F` | 品红 |

### 4.4 控制脚编号类型

与 GPIO 模块同一套：`0` 按芯片 GPIO 号，`1` 按模块对外 pin 序号。

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `lcd.GPIO` | `0` | 芯片 GPIO 编号 | 脚描述表的 `type` |
| `lcd.PIN` | `1` | 模块 pin 序号 | 脚描述表的 `type` |

### 4.5 占用模式

`obj:info()` 的 `mode` 字段。脚本一般只看到 `MODE_DIRECT`。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `lcd.MODE_DIRECT` | `0` | Lua 可以 `fill` / `full` |
| `lcd.MODE_OWNED` | `1` | 面板已被图形栈占用，Lua 绘图失败 |

测试阶段请保持 DIRECT：只 `lcd.new`，自己画，不要同时把对象交给 GUI。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `cfg` | table | `new` 的配置，见 [第 8 节](#8-new-配置表) |
| `color` | integer | RGB565，`lcd.RED` 或 `0xF800` 这类 |
| `x` / `y` / `w` / `h` | integer | 逻辑坐标与宽高，原点在左上 |
| `buf` | string | RGB565 **大端** 二进制，长度必须是 `w * h * 2` |
| `on` | 布尔 | `backlight`；`0` 为真 |
| `dir` | integer | `ROTATE_0`～`ROTATE_270` |
| `io` | integer 或 table | 控制脚，见 [第 9 节](#9-控制脚怎么写) |

`width` / `height` / `x_off` / `y_off` / `rotate` / `hz` 只认 **整数**。写成 `240.0` 不会当 240 用，会落到默认值。

---

## 6. 模块函数

---

### 6.1 `lcd.new(cfg)` {#6-1-new}

打开总线、初始化 ST7789，返回屏对象。

**调用模式**

```lua
lcd.new(cfg)
```

`cfg` 必须是 table，否则 **抛错**（不是 `nil, err`）。

成功：userdata。失败：`nil, err`。

| 常见 `err` | 原因 |
| --- | --- |
| `"invalid lcd config"` | 表字段不合法、脚描述冲突、名字超过 15 字符、空字符串 |
| `"lcd already in use"` | 已有对象未释放 |
| `"lcd init failed: invalid parameter (…)"` | 未知 `driver` / 未知 `bus` / `spi0`·`spi1` 没配 `dc` |
| `"lcd init failed: driver error (…)"` | 总线或面板初始化失败 |
| `"mutex init failed"` | 同步资源创建失败 |

省略的字段用默认值（面向常见 240×280 ST7789 模组）：

| 键 | 默认 |
| --- | --- |
| `driver` | `"st7789"` |
| `bus` | `"spi0"` |
| `width` | `240` |
| `height` | `280` |
| `x_off` | `0` |
| `y_off` | `20` |
| `rotate` | `lcd.ROTATE_0` |
| `hz` | `0`（SPI 约 20 MHz，LSPI 约 40 MHz） |
| `bl_active_high` | `true` |
| `dc` / `cs` / `rst` / `bl` | 未用 |

`spi0` / `spi1` 至少要有 `dc`。完整字段见 [第 8 节](#8-new-配置表)。

```lua
local panel, err = lcd.new({
    driver = lcd.ST7789,
    bus    = lcd.SPI0,
    width  = 240,
    height = 280,
    y_off  = 20,
    dc = 10,
    cs = 8,
    rst = 9,
    bl = 11,
})
```

---

## 7. 对象方法

未初始化、已 `deinit`、或面板被图形栈占用时，下列方法（`size` / `info` / `rotate` 读当前值也一样）返回 `false, err`，不抛错。典型文案：

- `"lcd not initialized"`
- `"lcd bound to lvgl"`

参数类型不对（例如 `full` 的颜色不是整数）仍会 **抛错**。

---

### 7.1 `obj:deinit()` {#7-1-deinit}

关掉这块屏，释放总线。会先等待尚未完成的刷写，最多大约 **3 秒**。

**调用模式**

```lua
obj:deinit()
```

成功：`true`。失败：`false, err`。

之后同一脚本可以再次 `lcd.new`。对象被垃圾回收时也会走同样的关闭路径。

---

### 7.2 `obj:full(color)` {#7-2-full}

整屏填成一种颜色。与 `obj:fill(color)` 相同。

**调用模式**

```lua
obj:full(color)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `color` | 是 | RGB565 整数 |

成功：`true`。失败：`false, err`（例如 `"full failed: invalid parameter (-1)"`）。

```lua
obj:full(lcd.BLACK)
obj:full(lcd.RED)
obj:full(0xF800)
```

---

### 7.3 `obj:fill(...)` {#7-3-fill}

三种合法形态，参数个数必须是 1 个颜色，或 `x,y,w,h` 再加颜色/缓冲。其它个数：`false, "fill(color) or fill(x,y,w,h,color|buf)"`。

**调用模式**

```lua
obj:fill(color)
```

整屏填色，等同 `full`。

```lua
obj:fill(x, y, w, h, color)
```

矩形纯色。矩形必须落在当前逻辑宽高内，`w`/`h` 不能为 0。

```lua
obj:fill(x, y, w, h, buf)
```

矩形贴一块像素。`buf` 必须是 string，长度 **恰好** `w * h * 2`，内容为 RGB565 大端。长度不对：`false, "fill buf length must be w*h*2"`。

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `color` | 第一种、第二种 | RGB565 |
| `x` `y` | 后两种 | 左上角 |
| `w` `h` | 后两种 | 宽、高 |
| `buf` | 第三种 | 二进制 string |

成功：`true`。失败：`false, err`。

越界、零宽高会变成 `"fill failed: invalid parameter (-1)"`。

```lua
obj:fill(lcd.BLUE)
obj:fill(10, 20, 40, 30, lcd.YELLOW)
obj:fill(0, 0, 2, 1, "\xF8\x00\x07\xE0")  -- 红、绿各一像素
```

第六参若不是 string，按整数颜色解析；既不是 string 也不是整数则 **抛错**。

---

### 7.4 `obj:flush(x, y, w, h, buf)` {#7-4-flush}

向矩形刷 RGB565 缓冲。和 `fill(x,y,w,h,buf)` 同一条刷写路径，第六参 **必须是 string**（不能改传颜色）。

**调用模式**

```lua
obj:flush(x, y, w, h, buf)
```

长度必须是 `w * h * 2`，否则 `false, "flush buf length must be w*h*2"`。

留给以后图形栈对齐的同名接口；测试阶段用 `fill` 即可。

成功：`true`。失败：`false, err`。

---

### 7.5 `obj:pixel(x, y, color)` {#7-5-pixel}

画一个像素。

**调用模式**

```lua
obj:pixel(x, y, color)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `x` `y` | 是 | 逻辑坐标 |
| `color` | 是 | RGB565 |

成功：`true`。失败：`false, err`。点在屏外：`"pixel failed: invalid parameter (-1)"`。

不要用它扫整屏。每点一笔总线事务，240×280 会非常慢。

```lua
obj:pixel(0, 0, lcd.WHITE)
obj:pixel(10, 10, lcd.RED)
```

---

### 7.6 `obj:size()` {#7-6-size}

当前 **逻辑** 宽高。旋转 90°/270° 后宽高对调，与 `new` 时填的物理 `width`/`height` 可能不同。

**调用模式**

```lua
obj:size()
```

成功：`w, h` 两个整数。失败：`false, err`（此时不要把第一返回值当宽度）。

```lua
local w, h = obj:size()
```

---

### 7.7 `obj:rotate(...)` {#7-7-rotate}

读或写方向。

**调用模式**

```lua
obj:rotate()
```

成功：当前方向整数（`0`～`3`）。失败：`false, err`。

```lua
obj:rotate(dir)
```

写入方向。成功：`true`。失败：`false, err`。

```lua
obj:rotate(lcd.ROTATE_90)
local cur = obj:rotate()
```

改方向后请再 `size()` 取逻辑宽高，再 `full` 清一次屏，避免按旧宽高填矩形越界。

---

### 7.8 `obj:backlight(on)` {#7-8-backlight}

开或关背光。没配 `bl` 脚时下层可能失败。

**调用模式**

```lua
obj:backlight(on)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `on` | 是 | 真开、假关。省略当作 `nil` → **关** |

**数字 `0` 为真**，会把背光打开。请写：

```lua
obj:backlight(true)
obj:backlight(false)
```

成功：`true`。失败：`false, err`。

---

### 7.9 `obj:info()` {#7-9-info}

读一块状态表。

**调用模式**

```lua
obj:info()
```

成功：table。失败：`false, err`。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `driver` | string | 打开时的面板名，目前为 `"st7789"` |
| `bus` | string | `"spi0"` / `"spi1"` / `"lspi0"` |
| `inited` | boolean | 是否仍持有总线 |
| `mode` | integer | `MODE_DIRECT` / `MODE_OWNED` |
| `width` | integer | 逻辑宽 |
| `height` | integer | 逻辑高 |
| `rotate` | integer | 当前方向 |

`width` / `height` / `rotate` 在已初始化时才会填。

```lua
local inf = obj:info()
-- inf.driver == "st7789"
```

---

## 8. `new` 配置表

全部键可选；不写就用第 6.1 节默认值。`driver` / `bus` 最长 **15** 个字符。

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `driver` | string | `"st7789"` | 面板。测试阶段只能是 ST7789 |
| `bus` | string | `"spi0"` | `spi0` / `spi1` / `lspi0` |
| `width` | integer | `240` | 面板物理宽 |
| `height` | integer | `280` | 面板物理高 |
| `x_off` | integer | `0` | 列方向 GRAM 偏移 |
| `y_off` | integer | `20` | 行方向 GRAM 偏移。常见 240×280 模组要 20；240×240 往往是 0 |
| `rotate` | integer | `0` | 初始方向 |
| `hz` | integer | `0` | 时钟。`0` = 总线默认（SPI≈20 MHz，LSPI≈40 MHz） |
| `bl_active_high` | boolean | `true` | 背光有效电平。只认 `true`/`false` |
| `dc` | 脚 | 未用 | 命令/数据。`spi0`/`spi1` **必填** |
| `cs` | 脚 | 未用 | 片选。普通 SPI 建议填 |
| `rst` | 脚 | 未用 | 硬件复位 |
| `bl` | 脚 | 未用 | 背光 |

`driver` 可用 `lcd.ST7789` 或 `"st7789"`。其它字符串会 `lcd init failed: invalid parameter`。

`y_off` 必须和模组一致，否则图像上下缺一块或花边。以丝印/规格为准，不要假设所有 ST7789 都是 20。

---

## 9. 控制脚怎么写

`dc` / `cs` / `rst` / `bl` 四种写法。省略或 `nil` = 这块脚不用。编号范围 **0～255**。

**整数：按芯片 GPIO 号**

```lua
dc = 10          -- GPIO10
```

**表：`gpio` 键，仍是 GPIO 号**

```lua
dc = { gpio = 10 }
```

**表：`pin` 键，按模块对外 pin 序号**（与 `gpio.open(gpio.BY_PINNO, n)` 同一套编号）

```lua
dc = { pin = 23 }
```

**表：显式类型 + `id`**

```lua
dc = { type = lcd.GPIO, id = 10 }
dc = { type = lcd.PIN,  id = 23 }
```

同一张表里 **不能同时出现 `gpio` 和 `pin`**，否则整份配置失败（`invalid lcd config`）。

`type` 只认整数。可与 `id` 组合；若同时写了 `pin`，类型强制为模块 pin，不再看 `type`。

```lua
lcd.new({
    bus = lcd.SPI0,
    dc  = { gpio = 10 },
    cs  = { pin = 8 },
    rst = 9,
    bl  = { type = lcd.GPIO, id = 11 },
})
```

---

## 10. 颜色与像素缓冲

颜色参数是 **RGB565 整数**（高 5 位红、中 6 位绿、低 5 位蓝），与 `lcd.RED` 等常量一致。纯色填充由模块送到屏上。

`fill` / `flush` 的 `buf` 是已经按线上格式排好的二进制：

- 每像素 2 字节，**大端**：先高字节再低字节。
- `lcd.RED`（`0xF800`）对应 `"\xF8\x00"`。
- 总长度必须等于 `w * h * 2`，多一个、少一个都失败。

不要传字节表，只收 string。Lua 5.3 下请用整数颜色，不要传 `0xF800.0`。

坐标原点在旋转后的逻辑左上。`size()` 给出可画范围；`x + w`、`y + h` 不能超出。

---

## 11. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `lcd.new` | userdata | `nil, err`；`cfg` 不是 table 时 **抛** |
| `deinit` / `full` / `fill` / `flush` / `pixel` / `backlight` | `true` | `false, err` |
| `rotate()` 读 | 整数 0～3 | `false, err` |
| `rotate(dir)` 写 | `true` | `false, err` |
| `size` | `w, h` | `false, err` |
| `info` | table | `false, err` |

下层错误串形如 `"fill failed: invalid parameter (-1)"`，括号里的整数：

| 码 | 文案片段 | 常见原因 |
| --- | --- | --- |
| `-1` | `invalid parameter` | 未知驱动/总线、没配 DC、矩形越界、缓冲长度已在上层拦过 |
| `-2` | `invalid state` | 未初始化 |
| `-4` | `driver error` | 总线或面板硬件初始化/传输失败 |
| 其它 | `unknown error` | 未单独翻译的码 |

固定 `err` 文本（没有括号码）：

| `err` | 可能原因 |
| --- | --- |
| `mutex init failed` | `new` 时系统互斥量失败 |
| `invalid lcd config` | cfg 缺关键项或 driver/bus 无法识别 |
| `lcd already in use` | 已有一块屏未 `deinit` |
| `lcd init failed: … (N)` | 面板初始化，N 见上表 |
| `lcd not initialized` | 对象已 deinit 或从未 new 成功 |
| `lcd bound to lvgl` | 已经 `lvgl.create`，改用 lvgl 画，或先 `ui:deinit` |
| `fill buf length must be w*h*2` | RGB565 缓冲长度不对 |
| `flush buf length must be w*h*2` | 同上 |
| `fill(color) or fill(x,y,w,h,color\|buf)` | `fill` 参数组合对不上两种形态 |

类型检查失败（缺对象、颜色不是整数等）走 Lua 参数错，需要 `pcall` 才能收。诊断：`already in use` 先 deinit；`bound to lvgl` 不要混用两套画法；`invalid parameter (-1)` 查 DC/矩形/驱动名。

---

## 12. 资源上限与生命周期

| 项 | 上限 / 说明 |
| --- | --- |
| 实例 | **整机 1 块屏** |
| 面板库 | 测试阶段仅 ST7789 |
| 总线 | `spi0` / `spi1` / `lspi0` 三选一 |
| 名字 | `driver`、`bus` 各最多 15 字符 |
| 脚编号 | 0～255 |
| 像素格式 | RGB565，16 bpp |
| `new` 默认分辨率 | 240×280，`y_off=20` |
| 刷写 | 同步；大块会拆开发，调用仍等到全部发完 |
| `deinit` | 最多再等约 3 秒刷写收尾 |
| 回调 | 无 |

`__gc` 与显式 `deinit` 都会关总线。VM 退出时未释放的对象也会被回收。

不要在 UART / MQTT 这类短回调里 `full` 整屏：会占住整台 Lua。

---

## 13. 选型对照

| 需求 | 做法 |
| --- | --- |
| 验证 SPI 能否出图 | 本模块 + ST7789，`full` 几种颜色 |
| 其它 LCD 控制器 | **现在没有。** 提需求后再加库，不要改 `driver` 硬试 |
| 普通 SPI 外设（Flash、传感器） | 等 SPI 主机模块，不要占用 LCD 已 `new` 的那一路 |
| GPIO 指示灯 | [`gpio`](../peripherals/gpio.md) |
| 图形界面 / 控件 | [`lvgl`](lvgl.md)：`create` 之后本模块 `fill`/`full` 会失败 |

---

## 14. 完整示例

脚号按板子改。下面按「SPI0 + GPIO 号」验证 ST7789：

```lua
local lcd = require("lcd")
local rt  = require("rt")
local log = require("log")

local panel, err = lcd.new({
    driver = lcd.ST7789,   -- 目前只能是它
    bus    = lcd.SPI0,     -- 验证通用 SPI；LCD 专用口用 lcd.LSPI0
    width  = 240,
    height = 280,
    x_off  = 0,
    y_off  = 20,
    dc  = 10,
    cs  = 8,
    rst = 9,
    bl  = 11,
})
if not panel then
    log.warn("lcd.new %s", tostring(err))
    return
end

local w, h = panel:size()
log.info("lcd %dx%d", w, h)

panel:backlight(true)
panel:full(lcd.RED)
rt.delay(300)
panel:full(lcd.GREEN)
rt.delay(300)
panel:full(lcd.BLUE)
rt.delay(300)
panel:fill(20, 20, 80, 40, lcd.YELLOW)
panel:pixel(0, 0, lcd.WHITE)

local inf = panel:info()
log.info("driver=%s bus=%s", inf.driver, inf.bus)

-- panel:deinit()
```

换 240×240 模组时通常把 `height` 改成 `240`、`y_off` 改成 `0`，仍用 `lcd.ST7789`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
| 1.0.2 | 2026-09-05 | 选型对照补上 lvgl 文档链接 |
| 1.1.0 | 2026-09-05 | 补全固定 err 文本与可能原因 |
| 1.1.1 | 2026-09-09 | 管脚 `pin` 编号对照改为 `gpio.BY_PINNO` |
