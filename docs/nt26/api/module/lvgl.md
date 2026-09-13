# lvgl

**文档版本** `1.6.1`

把已经 `lcd.new` 好的彩屏交给图形栈：控件、主题、脏区刷新都走本模块。刷屏在独立任务里跑，脚本只要建树、改字、改样式，然后 `rt.delay` 让出即可。

```lua
local lvgl = require("lvgl")
```

平台预加载模块，无需额外 `.lua` 文件。须先 [`lcd.new`](lcd.md) 得到面板，再 `lvgl.create(panel, opts)`。

本绑定是 LVGL 的 **子集**：标签、按钮、空白容器、图片、样式覆盖。按钮点击已挂上；触摸输入设备尚未接入，真机点按要等输入，脚本可用 `ui:click` 走同一条回调。没有官方 LVGL 全量控件表。默认字体由固件编入（Montserrat 14，ASCII + FontAwesome 子集）。要显示中文请用 [`ui:font`](#7-30-font) 加载自己的子集字库（LVGL 点阵 `.bin` 或 TTF），不要假设默认字含汉字。图片只认 **JPEG** 和 **LVGL 图像 `.bin`**（靠文件头，不靠扩展名）；BMP 不支持。字库 `.bin` 和图像 `.bin` 不是同一种文件。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 对象模型](#3-对象模型)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `lvgl.create`](#6-1-create)
- [7. 对象方法](#7-对象方法)
  - [7.1 `ui:handler`](#7-1-handler)
  - [7.2 `ui:mem`](#7-2-mem)
  - [7.3 `ui:scr_act`](#7-3-scr-act)
  - [7.4 `ui:label`](#7-4-label)
  - [7.5 `ui:btn`](#7-5-btn)
  - [7.6 `ui:obj`](#7-6-obj)
  - [7.7 `ui:style`](#7-7-style)
  - [7.8 `ui:add_style`](#7-8-add-style)
  - [7.9 `ui:remove_style`](#7-9-remove-style)
  - [7.10 `ui:set_style`](#7-10-set-style)
  - [7.11 `ui:set_parent`](#7-11-set-parent)
  - [7.12 `ui:set_radius`](#7-12-set-radius)
  - [7.13 `ui:set_text`](#7-13-set-text)
  - [7.14 `ui:set_bg`](#7-14-set-bg)
  - [7.15 `ui:set_theme`](#7-15-set-theme)
  - [7.16 `ui:set_text_color`](#7-16-set-text-color)
  - [7.17 `ui:center`](#7-17-center)
  - [7.18 `ui:set_pos`](#7-18-set-pos)
  - [7.19 `ui:set_size`](#7-19-set-size)
  - [7.20 `ui:invalidate`](#7-20-invalidate)
  - [7.21 `ui:refr_pause`](#7-21-refr-pause)
  - [7.22 `ui:refr_resume`](#7-22-refr-resume)
  - [7.23 `ui:deinit`](#7-23-deinit)
  - [7.24 `ui:on_click`](#7-24-on-click)
  - [7.25 `ui:click`](#7-25-click)
  - [7.26 `ui:img`](#7-26-img)
  - [7.27 `ui:set_src`](#7-27-set-src)
  - [7.28 `ui:set_scale`](#7-28-set-scale)
  - [7.29 `ui:get_scale`](#7-29-get-scale)
  - [7.30 `ui:font`](#7-30-font)
  - [7.31 `ui:set_font`](#7-31-set-font)
- [8. 样式对象方法](#8-样式对象方法)
  - [8.1 `style:set`](#8-1-set)
- [9. `create` 配置表](#9-create-配置表)
- [10. 样式表字段](#10-样式表字段)
- [11. 颜色怎么写](#11-颜色怎么写)
- [12. 刷屏与 Lua 时序](#12-刷屏与-lua-时序)
- [13. 错误与返回约定](#13-错误与返回约定)
- [14. 资源上限与生命周期](#14-资源上限与生命周期)
- [15. 选型对照](#15-选型对照)
- [16. 完整示例](#16-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

脚本侧流程：

1. `lcd.new(cfg)` 打开总线和面板（见 [lcd](lcd.md)）。`create` 之前可以用 `panel:full` 确认屏是通的。
2. `lvgl.create(panel, opts)` 把这块屏交给图形栈，得到 `ui`。之后再调 `panel:full` / `fill` / `flush` 会失败，文案 `lcd bound to lvgl`。屏幕背景改走 `opts.bg` 或 `ui:set_bg`。
3. `ui:scr_act` / `ui:label` / `ui:btn` / `ui:obj` / `ui:img` 建树；外观用默认主题，再用 `ui:style` + `add_style` 或 `ui:set_style` 覆盖。图片源见 [7.27](#7-27-set-src)。
4. 改文字、改位置只记脏。脚本让出后，独立任务才画、才往屏上刷。
5. 不要循环 `ui:handler()`。长期脚本用 `rt.delay(-1)` 或自己的业务循环。
6. 不用时 `ui:deinit()`，才能再 `create` 一次。

| 能做 | 不能做 |
| --- | --- |
| 标签、按钮、空白容器、图片 | 官方 LVGL 其它控件（slider、list…）未挂 |
| JPEG、LVGL 图像 `.bin`（RAM / ublob / lfs）；`set_scale` 缩放像素 | BMP、PNG、GIF；不认盘符路径；`set_size` 只改外框不缩放 |
| 子集字库：LVGL 点阵 `.bin`（含压缩）/ TTF（RAM / ublob / lfs） | 运行时 OTF(CFF)、WOFF、WOFF2；FreeType |
| 默认 light/dark 主题 + 样式覆盖 | 换官方主题引擎 |
| 独立任务刷脏区 | 触摸、按键输入设备（点按要等输入，或用 `ui:click`） |
| 按钮点击：回调按 **任务** 跑，可 `rt.delay` | 不要当 gpio 那种「立刻返回」的短回调 |
| RGB565 屏（GRAM）；内部也可选 RGB888 再转 565 | 用本模块当 `lcd:fill` 的替代去打点 |

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  lcd.new → lvgl.create → label/btn/img/style → rt.delay     │
│  一次让出结束前：只记脏，不刷屏                           │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│  ui 对象                                                 │
│  · 整机同一时刻一份                                      │
│  · 控件句柄 / 样式对象挂在这棵树上                       │
│  · 改字、改 style 只标记脏区                             │
└────────────────────────────┬────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼                             ▼
┌─────────────────────┐          ┌─────────────────────┐
│  独立图形任务         │          │  已绑定的 lcd 面板   │
│  定时器到期或被叫醒   │          │  阻塞 DMA 发像素     │
│  再画脏区、flush     │          │  单缓冲，发完再返回  │
└─────────────────────┘          └─────────────────────┘
```

| 路径 | 谁在跑 | 是否占用 Lua 调度 | 典型用途 |
| --- | --- | --- | --- |
| `create` / 建控件 / 改 style | 当前 Lua 协程 | 是（同步，一般很快） | 组界面 |
| 脏区绘制 + 刷屏 | **独立任务** | 否（Lua 让出之后才跑） | 出图 |
| `refr_pause` … `refr_resume` | 脚本暂停任务刷屏 | 否 | 中间有 `rt.delay` 时避免刷到半成品 |
| `ui:handler` | 只叫醒任务一脚 | 否 | 兼容旧写法；不要循环 |
| `ui:on_click` 回调 | **一次性 rt 任务** | 是（可 `rt.delay` / 邮箱） | 按钮业务；不要再自己 `mbox_send` 转发 |
| `lcd:full` 等（create 之后） | — | 立刻失败 | 不要再用 |

一次 `rt.delay` / 邮箱等待 / 事件回调返回之前，图形任务看到「Lua 还在跑」就不会 `handler`。控件创建、改文字都只记脏，本次让出后再画。任意业务自然写即可，不必手动 `invalidate`，也不靠固定延时。

若中间必须 `delay`/`wait`、又不想让半棵树先上屏：`ui:refr_pause()` → 建完 / 改完 → `ui:refr_resume()`。可嵌套，成对使用。

---

## 3. 对象模型

四种 userdata，职责不同：

| 对象 | 怎么来 | 有没有方法 | 必须持有 |
| --- | --- | --- | --- |
| **ui** | `lvgl.create` | 有，见 [第 7 节](#7-对象方法) | 是，丢掉会被回收并 `deinit` |
| **控件** | `scr_act` / `label` / `btn` / `obj` / `img` | **没有。** 不能 `lab:set_pos` | 建议拿着方便传给 `ui:set_*`；GC 掉句柄 **不会** 删掉树上的控件 |
| **样式** | `ui:style({...})` | 只有 `style:set` | **是。** 丢掉引用会被回收并重置；已 `add_style` 的控件会丢这份样式 |
| **字库** | `ui:font(src)` | **没有。** | **是。** 丢掉会被回收；仍 `set_font` 在控件上等于空悬指针。和样式一样放到模块级 / upvalue |

### 3.1 两种调用写法

冒号是推荐写法：

```lua
ui:label("hello")
ui:set_pos(btn, 16, 48)
```

点号且自己传入 ui，与冒号等价：

```lua
ui.label(ui, "hello")
```

`create` 之后，同名接口也挂在模块表上，会用当前这份 ui：

```lua
lvgl.label("hello")
lvgl.set_pos(btn, 16, 48)
```

错误：

```lua
btn:set_pos(16, 48)     -- 控件上没有方法
lab.set_text("x")       -- 同上
lvgl.label("x")         -- create 之前：抛错 call lvgl.create first
```

### 3.2 整机一份

底层只有一份图形栈。`ui` 还活着时第二次 `create` 抛错：`lvgl already created`。先 `deinit`（或让旧 ui 被回收）再开。

### 3.3 布尔语义

本模块里：

| 接口 / 字段 | 怎么读 | `0` 表示什么 |
| --- | --- | --- |
| `opts.double_buf` / `full_buf` 写成 **boolean** | Lua 布尔 | 与其它模块相同：数字当 boolean 传入时 **`0` 为真**。请写 `true`/`false` |
| 同上写成 **number** | `~= 0` 为真 | **`0` 为假** |
| `opts.theme` 写成 boolean | Lua 布尔 | **`0` 为真（dark）**；请写 `"light"` / `"dark"` |
| `opts.dark` 写成 number | `~= 0` | `0` = light |
| 样式 `clip_corner` | Lua 布尔（非 nil 就读） | **数字 `0` 为真**。请写 `true`/`false` |
| 样式 `scrollable` / `clickable` | **只接受 boolean 类型** | 写成 `0`/`1` 会被忽略，旗标不变 |

推荐：开关一律 `true`/`false`，主题用 `"light"` / `"dark"`。

---

## 4. 常量与枚举

`luaopen` 导出不透明度符号和图片缩放基准。主题名、色深、缓冲模式都是 **字符串**，没有对应整数常量。

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `lvgl.OPA_TRANSP` | `0` | 全透明 | 样式 `bg_opa`，或 `0` |
| `lvgl.OPA_COVER` | `255` | 不透明 | 样式 `bg_opa`，或 `255` |
| `lvgl.SCALE_NONE` | `256` | 图片 1:1，不缩放 | `ui:set_scale` |

`bg_opa` 还可以直接写字符串 `"cover"` / `"COVER"` / `"transp"` / `"transparent"` / `"TRANSP"`，或 boolean（`true` = COVER，`false` = TRANSP；数字 `0` 当 boolean 时为真）。整数 `0`～`255` 按不透明度用。

未挂到模块的官方 LVGL 枚举（部件选择器、调色板名、对齐常量等）不要当可用 API。`add_style` 的 `selector` 若要传，请传整数；省略即 `0`（主部件）。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `panel` | lcd 对象 | 必须已经 `lcd.new` 成功 |
| `ui` | userdata | `create` 的返回值 |
| `obj` / `parent` / `lab` / `btn` / `img` | userdata | 控件句柄，元表无方法 |
| `font` | userdata | `ui:font` 的返回值 |
| `src` | string 或 table | 图片见 [7.27](#7-27-set-src)；字库见 [7.30](#7-30-font)。表字段同一套：`data` / `ublob` / `lfs`+`path` |
| `style` | userdata | `ui:style` 的返回值 |
| `opts` / 样式表 | table | 见 [第 9 节](#9-create-配置表)、[第 10 节](#10-样式表字段) |
| `color` | integer | 见 [第 11 节](#11-颜色怎么写) |
| `text` | string | Lua 会把 number 转成字面 |
| `selector` | integer | 样式选择器，省略为 `0` |
| `opa` | integer / string / boolean | 见第 4 节 |
| `x` `y` `w` `h` `r` | integer | 像素 |
| `scale` | integer | 图片缩放。`256` / `lvgl.SCALE_NONE` = 原尺寸；`128` = 一半；`512` = 两倍 |

---

## 6. 模块函数

第 7 节的方法在模块表上有同名入口（`create` 之后可 `lvgl.label(...)`）。工厂只有下面这一条。

---

### 6.1 `lvgl.create(panel [, opts])` {#6-1-create}

绑定一块已初始化的 lcd 面板，启动图形任务，返回 `ui`。

**调用模式**

```lua
ui = lvgl.create(panel)
```

```lua
ui = lvgl.create(panel, opts)
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `panel` | lcd 对象 | 是 | — | 第 1 个参数必须是 lcd 对象 |
| `opts` | table | 否 | 见 [第 9 节](#9-create-配置表) | 省略则 RGB565、单缓冲、整屏 DIRECT、浅色主题、`mem_max` 128 KiB |

**返回**

成功：`ui`。失败：**抛错**，不返回 `nil, err`。典型摘要：

| 摘要 | 何时 |
| --- | --- |
| `lvgl already created` | 已有一份未 `deinit` 的 ui |
| `arg#1 must be lcd object` | 第 1 参不是 lcd |
| `lcd not initialized` | 面板未就绪 |
| `lcd size is 0` | 宽或高为 0 |
| `lv_display_create failed (check mem_max)` | 显示对象分配失败 |
| `draw buf alloc failed (check mem_max)` | 绘图缓冲不够 |
| `line buf alloc failed (check mem_max)` | 行转换缓冲不够 |
| `lcd set owned failed` | 无法把面板交给图形栈 |
| `lvgl task start failed` | 图形任务没起来 |

**示例**

```lua
local ok, ui = pcall(lvgl.create, panel, {
    mem_max = 384 * 1024,
    color = "rgb565",
    dpi = 130,
    refr_ms = 33,
    double_buf = true,
    full_buf = true,
    theme = "dark",
    bg = 0x00F5F5,
})
```

分辨率跟面板走，不能在 `opts` 里改宽高。

---

## 7. 对象方法

下列均可通过 `ui:foo(...)` 调用。未 `create` 或 ui 已 `deinit`：抛错 `call lvgl.create first` / `lvgl ui not initialized`。

---

### 7.1 `ui:handler()` {#7-1-handler}

叫醒图形任务一脚。**不要循环调用。** 刷屏由独立任务在脚本让出后自己跑。

**调用模式**

```lua
n = ui:handler()
```

**返回** 整数 `0`。

---

### 7.2 `ui:mem()` {#7-2-mem}

读图形堆用量。

**调用模式**

```lua
used, peak, limit = ui:mem()
```

**返回** 三个整数：当前已用、峰值、上限（字节）。`create` 时 `mem_max = 0` 表示脚本不设上限，`limit` 为 0。

---

### 7.3 `ui:scr_act()` {#7-3-scr-act}

当前活动屏幕。省略 `parent` 的 `label`/`btn`/`obj`/`img` 都挂在这上面。

**调用模式**

```lua
scr = ui:scr_act()
```

**返回** 控件句柄；没有屏幕时 `nil`。

每次调用都 **新包一层** 句柄，指向同一块屏。丢掉旧句柄不影响树上的对象。

---

### 7.4 `ui:label([parent,] [text])` {#7-4-label}

建一个标签。默认字是 Montserrat 14（ASCII）。要显示中文先 [`ui:font`](#7-30-font) 再 [`ui:set_font`](#7-31-set-font)。

**调用模式**

```lua
lab = ui:label()
```

```lua
lab = ui:label(text)
```

```lua
lab = ui:label(parent)
```

```lua
lab = ui:label(parent, text)
```

第 1 个额外参数若是控件句柄，当作父亲；若是 string（或 number，会转成字面）当作 `text`，父亲用当前屏幕。省略 `text` 则为空串。

**返回** 控件句柄。失败抛错：`invalid parent` / `label create failed`。

---

### 7.5 `ui:btn([parent,] [text])` {#7-5-btn}

建一个按钮。若给了 `text`，内部再放一个居中的标签。

**调用模式**

```lua
btn = ui:btn()
```

```lua
btn = ui:btn(text)
```

```lua
btn = ui:btn(parent)
```

```lua
btn = ui:btn(parent, text)
```

参数规则与 `label` 相同。省略 `text` 则只有空按钮，不建内部标签。

**返回** 控件句柄。失败抛错：`invalid parent` / `btn create failed`。

点击见 [`ui:on_click`](#7-24-on-click)。触摸输入尚未接入；脚本可用 [`ui:click`](#7-25-click) 走同一条路径。

---

### 7.6 `ui:obj([parent])` {#7-6-obj}

空白容器。浅色主题下默认像一张卡片。

**调用模式**

```lua
box = ui:obj()
```

```lua
box = ui:obj(parent)
```

省略 `parent`（或传入的不是控件句柄）则挂到当前屏幕。

**返回** 控件句柄。失败抛错：`invalid parent` / `obj create failed`。

---

### 7.7 `ui:style([props])` {#7-7-style}

新建一份样式对象，**不改主题**。返回值必须一直放在 Lua 变量里。

**调用模式**

```lua
st = ui:style()
```

```lua
st = ui:style(props)
```

`props` 见 [第 10 节](#10-样式表字段)。`scrollable` / `clickable` 写在这份表里 **无效**（它们不是样式属性，只在 `set_style` 时作用到控件）。

**返回** 样式 userdata。

---

### 7.8 `ui:add_style(obj, style [, selector])` {#7-8-add-style}

把一份样式挂到控件上。

**调用模式**

```lua
ok = ui:add_style(obj, style)
```

```lua
ok = ui:add_style(obj, style, selector)
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `obj` | 控件 | 是 | — | |
| `style` | 样式对象 | 是 | — | 须一直持有 |
| `selector` | integer | 否 | `0` | 主部件；传了 number 才改 |

**返回** `true`。`obj`/`style` 非法则抛错 `invalid lvgl object` / `invalid lvgl style`。

---

### 7.9 `ui:remove_style(obj, style [, selector])` {#7-9-remove-style}

从控件上摘掉一份样式。

**调用模式**

```lua
ok = ui:remove_style(obj, style)
```

```lua
ok = ui:remove_style(obj, style, selector)
```

省略 `selector` 时按主部件摘（数值同样是 `0`）。

**返回** `true`。非法句柄抛错，同上。

---

### 7.10 `ui:set_style(obj, props [, selector])` {#7-10-set-style}

把表写到该控件的 **本地样式**（以及可点/可滚旗标），不经过 `ui:style` 对象。

**调用模式**

```lua
ok = ui:set_style(obj, props)
```

```lua
ok = ui:set_style(obj, props, selector)
```

`props` 必须是 table，否则抛错。字段见 [第 10 节](#10-样式表字段)。`scrollable` / `clickable` 只在这里生效。

**返回** `true`。

---

### 7.11 `ui:set_parent(obj, parent)` {#7-11-set-parent}

改控件的父亲。

**调用模式**

```lua
ok = ui:set_parent(obj, parent)
```

两个参数都必须是控件句柄。

**返回** `true`。非法句柄抛错。

---

### 7.12 `ui:set_radius(obj, r)` {#7-12-set-radius}

写本地圆角，等价于 `set_style` 的 `radius`（选择器 `0`）。

**调用模式**

```lua
ok = ui:set_radius(obj, r)
```

`r` 必须是 integer。

**返回** `true`。

---

### 7.13 `ui:set_text(obj, text)` {#7-13-set-text}

改标签正文。目标必须是 `label` 建出来的那种标签；按钮本身不是标签。

**调用模式**

```lua
ok = ui:set_text(lab, text)
```

```lua
ok, err = ui:set_text(obj, text)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是标签 | `true` |
| 不是标签 | `false, "not a label"`（不抛错） |

`text` 不是 string/number 时抛错（缺参等）。

---

### 7.14 `ui:set_bg([obj,] color)` {#7-14-set-bg}

写背景色并不透明。省略 `obj` 则改当前屏幕。

**调用模式**

```lua
ok = ui:set_bg(color)
```

```lua
ok = ui:set_bg(obj, color)
```

第 1 个额外参数若是控件句柄，第二参才是颜色；否则第 1 参就是颜色。

**返回** `true`。`color` 必须是 integer。颜色编码见 [第 11 节](#11-颜色怎么写)。

---

### 7.15 `ui:set_theme(theme)` {#7-15-set-theme}

切换默认主题（蓝/红主色，固件默认字体）。随后仍可用 style 覆盖。

**调用模式**

```lua
ok = ui:set_theme("light")
```

```lua
ok = ui:set_theme("dark")
```

```lua
ok = ui:set_theme("night")
```

```lua
ok = ui:set_theme(false)
```

```lua
ok = ui:set_theme(true)
```

```lua
ok = ui:set_theme(0)
```

```lua
ok = ui:set_theme(1)
```

| 写法 | 效果 |
| --- | --- |
| `"dark"` / `"night"` | 深色 |
| 其它字符串（含 `"light"`） | 浅色 |
| boolean | `true` 深色，`false` 浅色 |
| integer | `~= 0` 深色，`0` 浅色 |

请优先用 `"light"` / `"dark"`。boolean 路径下数字 `0` 若被当成 boolean 会变成深色。

**返回** `true`。

---

### 7.16 `ui:set_text_color(obj, color)` {#7-16-set-text-color}

写本地文字色（选择器 `0`）。

**调用模式**

```lua
ok = ui:set_text_color(obj, color)
```

**返回** `true`。

---

### 7.17 `ui:center(obj)` {#7-17-center}

在父亲里居中。

**调用模式**

```lua
ok = ui:center(obj)
```

**返回** `true`。

---

### 7.18 `ui:set_pos(obj, x, y)` {#7-18-set-pos}

相对父亲的左上角，像素。

**调用模式**

```lua
ok = ui:set_pos(obj, x, y)
```

`x`、`y` 必须是 integer。

**返回** `true`。

---

### 7.19 `ui:set_size(obj, w, h)` {#7-19-set-size}

宽高，像素。只改控件外框。图片控件用这一条 **不会** 把像素等比缩放，多出来的是空白或裁切；要缩放请用 [`ui:set_scale`](#7-28-set-scale)。

**调用模式**

```lua
ok = ui:set_size(obj, w, h)
```

**返回** `true`。刷屏占锁超时：`false, "lvgl busy"`。

---

### 7.20 `ui:invalidate([obj])` {#7-20-invalidate}

更新布局并标记脏区，再叫醒图形任务。一般不必调：改字、改 style 已经会脏。省略 `obj` 则对当前屏幕做。

**调用模式**

```lua
ok = ui:invalidate()
```

```lua
ok = ui:invalidate(obj)
```

**返回** `true`。

---

### 7.21 `ui:refr_pause()` {#7-21-refr-pause}

暂停独立任务刷屏。脏区照记。内部是计数，可嵌套。

**调用模式**

```lua
ok = ui:refr_pause()
```

**返回** `true`。

典型：`pause` → 建一批控件或中间 `rt.delay` → `resume`。不成对多 `resume` 不会把计数减到负数。

---

### 7.22 `ui:refr_resume()` {#7-22-refr-resume}

与 `refr_pause` 配对。计数降到 0 后叫醒任务，下次绘制完整树。

**调用模式**

```lua
ok = ui:refr_resume()
```

**返回** `true`。计数已经是 0 时仍返回 `true`，不再减。

---

### 7.23 `ui:deinit()` {#7-23-deinit}

停图形任务、等未完成的刷写（最多约 3 秒）、释放缓冲、把面板还回 lcd（之后可以再 `panel:full`）。整机才能再次 `create`。

**调用模式**

```lua
ok = ui:deinit()
```

```lua
ok = lvgl.deinit()
```

没有当前 ui 时也返回 `true`。`__gc` 会走同一条回收。

**返回** `true`。

---

### 7.24 `ui:on_click(obj, callback)` {#7-24-on-click}

给控件登记点击。目前给 `ui:btn` 用；其它控件句柄也能登记，但没有触摸时同样要靠 `ui:click` 才会进回调。

**这不是 gpio / mqtt 那种短回调。** 图形栈只负责投递；真正执行时引擎会拉起一条 **一次性任务**。函数体里可以直接写业务，也可以 `rt.delay`、`rt.mbox_recv`。不必再 `mbox_send` 转一层。占一条 `rt.task_start` 同款任务槽（整机大约 16 条，含入口协程）。马上 `return` 的回调不占槽。

**调用模式**

```lua
ui:on_click(btn, function(obj, ev)
    -- obj 就是登记时的那个句柄
    -- ev.name == "clicked"
    ui:set_text(hint, "ok")
    rt.delay(200)
end)
```

```lua
ui:on_click(btn, nil)   -- 取消
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `obj` | 控件句柄 | 是 | `ui:btn` / `ui:obj` 等 |
| `callback` | function 或 `nil` | 是 | `nil` 取消；重复登记覆盖上一次 |

**回调签名** `callback(obj, ev)`

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `obj` | 控件句柄 | 登记时钉住的那份 userdata |
| `ev` | table | `name` 为 `"clicked"`；`code` 为整数事件码，脚本按名字用即可 |

同一控件同时只挂一份点击函数。整机最多 **32** 份点击登记。

**返回** `true`。失败抛错：`invalid lvgl object` / `rt vm context missing` / `lvgl callback full` / `lvgl event hook failed`。缺函数走 Lua 参数错。

任务槽满时这次点击被丢掉，日志可见，不抛到脚本。

---

### 7.25 `ui:click(obj)` {#7-25-click}

脚本主动点一下，走和真点击同一条投递 → 任务路径。当前没有触摸设备时，用它验证 `on_click`。

**调用模式**

```lua
ui:click(btn)
```

投递后当前协程继续跑；`on_click` 里的函数要等本次让出、调度到那条任务后才执行。不要以为 `click` 返回时回调已经跑完。不抢刷屏锁，GPIO 任务里调用也不会把调度卡死。

**返回** `true`。未登记点击函数也返回 `true`（没人听）。队列满：`false, "click post failed"`。失败抛错：`invalid lvgl object` / `rt vm context missing`。

---

### 7.26 `ui:img([parent,] [src])` {#7-26-img}

建一个图片控件。可以先建空控件，再用 [`ui:set_src`](#7-27-set-src) 填图。

只认两种格式，**靠文件头、不靠扩展名**：

| 格式 | 文件头 |
| --- | --- |
| JPEG | 前三字节 `FF D8 FF`（JFIF / EXIF 都算） |
| LVGL `.bin` | 官方图像头（首字节为图像头魔数） |

BMP、PNG、GIF 一律 `unsupported image format`。不要传盘符路径。

`src` 三种源：

| 写法 | 含义 |
| --- | --- |
| string | RAM 里的整份字节（Lua string） |
| `{ data = bytes }` | 同上，包一层表 |
| `{ ublob = name }` | 从 [`ublob`](ublob.md) 按短名读明文再解码 |
| `{ lfs = fs, path = "..." }` | 从已 [`lfs.mount`](lfs.md) 的 `fs` 上流式读 `path` |

表里字段同时出现时：**`lfs` 优先于 `ublob`，`ublob` 优先于 `data`**，与书写顺序无关。`lfs` 必须带 string 类型的 `path`。

解码在当前协程里同步做完，**不抢刷屏锁**；像素（RGB565）挂到控件上时才短暂持锁。解码一次即常驻该控件：`hide` / 挪到屏外 **仍占** 这份像素，直到 `set_src(nil)` 或 `deinit`。张数不另设上限，图形堆不够就失败。

**调用模式**

```lua
img = ui:img()
```

```lua
img = ui:img(parent)
```

```lua
img = ui:img(bytes)
```

```lua
img = ui:img({ data = bytes })
```

```lua
img = ui:img({ ublob = "logo.jpg" })
```

```lua
img = ui:img({ lfs = fs, path = "/logo.jpg" })
```

```lua
img = ui:img(parent, src)
```

第 1 个额外参数若是控件句柄，当作父亲；否则整段当作 `src`，父亲用当前屏幕。省略 `src` 则空控件，不占图片像素。

**返回** 控件句柄。刷屏占锁超时：`false, "lvgl busy"`（控件不会建出来）。带 `src` 时解码失败：**抛错**（同样不建控件），摘要见下表。其余抛错：`invalid parent` / `img create failed` / `no mem`。

```lua
local ok, img = pcall(ui.img, ui, { ublob = "logo.jpg" })
if not ok then
    log.error("img %s", tostring(img))
end
```

---

### 7.27 `ui:set_src(img, src)` {#7-27-set-src}

给已有图片控件换源，或清掉像素。`src` 形态与 [7.26](#7-26-img) 相同。`nil`（或省略）清源并释放该控件上的像素，控件还在。

解码同样不抢刷屏锁。失败时 **原来的图还在**。

**调用模式**

```lua
ok, err = ui:set_src(img, bytes)
```

```lua
ok, err = ui:set_src(img, { data = bytes })
```

```lua
ok, err = ui:set_src(img, { ublob = "logo.jpg" })
```

```lua
ok, err = ui:set_src(img, { lfs = fs, path = "/logo.bin" })
```

```lua
ok, err = ui:set_src(img, nil)   -- 清源
```

**返回** `true`。失败：`false, 摘要`，不抛错（非法控件句柄仍抛 `invalid lvgl object`）。

| 摘要 | 何时 |
| --- | --- |
| `not an image` | 目标不是 `ui:img` 建出来的控件 |
| `lvgl busy` | 挂图时等锁超过约 200ms |
| `bad src` | 不是 string/表、空字节、缺 `path`、ublob 长度非法 |
| `fs not mounted` | `lfs` 不是已挂载的文件系统对象，或本固件未编 lfs |
| `not found` | ublob / lfs 上没有这份文件 |
| `unsupported image format` | 文件头不是 JPEG / LVGL `.bin` |
| `decode failed` | 头对了但解不开（损坏、超尺寸等） |
| `no mem` | 像素缓冲或控件附属块不够，加大 `mem_max` |

`ui:img(src)` 解码失败用 **同一批摘要抛错**，不是 `false, err`。

---

### 7.28 `ui:set_scale(img, scale)` {#7-28-set-scale}

按整数因子缩放 **图片像素**（横竖同一比例）。`256` 或 `lvgl.SCALE_NONE` 为原尺寸；小于 256 缩小，大于 256 放大。`0` 画不出来。这是图片控件自己的属性，不是单独一种控件。

和 [`ui:set_size`](#7-19-set-size) 不是一回事：`set_size` 只改外框。缩放后若控件仍是内容自适应，外框会跟着变，可用 `ui:center` 重新居中。若已经 `set_size` 钉死外框，放大超出框的部分会被裁掉。

缩放不另占一份像素缓冲，仍是解码时那张 RGB565。

**调用模式**

```lua
ok, err = ui:set_scale(img, scale)
```

```lua
ok, err = ui:set_scale(img, lvgl.SCALE_NONE)
```

```lua
ok, err = ui:set_scale(img, 128)   -- 一半
```

```lua
ok, err = ui:set_scale(img, 512)   -- 两倍
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `img` | 控件句柄 | 是 | — | 必须是 `ui:img` 建出来的 |
| `scale` | integer | 是 | — | `>= 0`。`256` = 1:1 |

**返回** `true`。失败：`false, 摘要`，不抛错（非法控件句柄仍抛 `invalid lvgl object`；缺参抛错）。

| 摘要 | 何时 |
| --- | --- |
| `not an image` | 目标不是 `ui:img` 建出来的控件 |
| `bad scale` | `scale < 0` |
| `lvgl busy` | 等锁超过约 200ms |

```lua
ui:set_scale(pic, 128)
ui:center(pic)
```

---

### 7.29 `ui:get_scale(img)` {#7-29-get-scale}

读当前缩放因子，语义与 [`ui:set_scale`](#7-28-set-scale) 相同。新建图片默认 `256`。

**调用模式**

```lua
scale = ui:get_scale(img)
```

**返回** 成功：整数。失败：`false, 摘要`。

| 摘要 | 何时 |
| --- | --- |
| `not an image` | 目标不是 `ui:img` 建出来的控件 |
| `lvgl busy` | 等锁超过约 200ms |

```lua
local scale, err = ui:get_scale(pic)
if scale == false then
    log.error("get_scale %s", tostring(err))
end
```

---

### 7.30 `ui:font(src [, size])` {#7-30-font}

加载一份字库，返回字库句柄。默认主题仍是 Montserrat 14（ASCII）；中文、其它字形要自己做子集再加载。

只认两种格式，**靠文件头、不靠扩展名**：

| 格式 | 文件头 | `size` |
| --- | --- | --- |
| LVGL 点阵 `.bin` | 偏移 4 起 4 字节为 `head`（Font Converter 输出，压缩或未压缩均可） | 忽略，字号已烘焙在文件里 |
| TrueType TTF | `00 01 00 00` 或 `true` | **要**。省略为 `14` |

OTF（`OTTO`）、WOFF / WOFF2 一律 `unsupported font format`。图像用的 LVGL `.bin` 不能当字库。

`src` 三种源（与 [`ui:set_src`](#7-27-set-src) 同一套优先级）：

| 写法 | 含义 |
| --- | --- |
| string / `{ data = bytes }` | RAM 里的整份字节（Lua string） |
| `{ ublob = name }` | 从 [`ublob`](ublob.md) 按短名读明文（内部存储） |
| `{ lfs = fs, path = "..." }` | 从已 [`lfs.mount`](lfs.md) 的外挂盘读整文件 |

表里字段同时出现时：**`lfs` 优先于 `ublob`，`ublob` 优先于 `data`**。`lfs` 必须带 string 类型的 `path`。`size` 可写在表里，也可当第 2 个参数；第 2 个参数若是 number 则覆盖表里的 `size`。

加载是同步的：整份文件进图形堆。TTF 会一直占着这份原文，直到字库被回收；点阵 `.bin` 解析完后释放原文，只留展开后的点阵。ublob 明文上限 256 KB；lfs 单文件超过 512 KB 按 `no mem`。

**调用模式**

```lua
font = ui:font(bytes)
```

```lua
font = ui:font(bytes, 16)
```

```lua
font = ui:font({ data = bytes, size = 16 })
```

```lua
font = ui:font({ ublob = "zh.bin" })
```

```lua
font = ui:font({ ublob = "zh.ttf", size = 14 })
```

```lua
font = ui:font({ lfs = fs, path = "/fonts/zh.bin" })
```

```lua
font = ui:font({ lfs = fs, path = "/zh.ttf", size = 16 })
```

**参数**

| 名字 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `src` | string 或 table | 是 | — | 见上表 |
| `size` | integer | TTF 建议填 | `14` | `> 0`。只对 TTF 有效 |

**返回** 字库句柄。失败：**抛错**（不返回 `nil, err`），摘要见下表。刷屏占锁超时：`false, "lvgl busy"`（字库不会建出来）。

| 摘要 | 何时 |
| --- | --- |
| `bad src` | 不是 string/表、空字节、缺 `path`、ublob 长度非法 |
| `bad size` | `size <= 0` |
| `fs not mounted` | `lfs` 不是已挂载对象，或本固件未编 lfs |
| `not found` | ublob / lfs 上没有这份文件 |
| `unsupported font format` | 不是点阵 `.bin`、也不是 TTF |
| `decode failed` | 头对了但解不开（损坏、TTF 无效） |
| `no mem` | 图形堆或读缓冲不够，加大 `mem_max` 或换更小子集 |

```lua
local ok, font = pcall(ui.font, ui, { ublob = "zh.ttf", size = 14 })
if not ok then
    log.error("font %s", tostring(font))
end
```

必须持有返回值。用完可以让它出作用域被回收；回收前不要再 `set_font` 到还活着的控件。

---

### 7.31 `ui:set_font(obj, font)` {#7-31-set-font}

把字库挂到控件的文字上。`nil`（或省略）回到默认 Montserrat 14。按钮、标签都能设。

也可以写在样式表里：`ui:set_style(obj, { font = font })` 或 `ui:style({ font = font })`。

**调用模式**

```lua
ok = ui:set_font(label, font)
```

```lua
ok = ui:set_font(label, nil)   -- 默认字
```

**返回** `true`。刷屏占锁超时：`false, "lvgl busy"`。`font` 不是 `ui:font` 的句柄：**抛错** `invalid lvgl font`。

```lua
local font = ui:font({ lfs = fs, path = "/zh.bin" })
ui:set_font(hint, font)
ui:set_text(hint, "温度")
```

---

## 8. 样式对象方法

---

### 8.1 `style:set(props)` {#8-1-set}

改已有样式。已经 `add_style` 上去的控件会跟着刷新。

**调用模式**

```lua
ok = style:set(props)
```

`props` 必须是 table。字段与 `ui:style` 相同；`scrollable` / `clickable` 仍无效。

**返回** `true`。非法对象抛错 `invalid lvgl style`。

```lua
local st = ui:style({ bg_opa = lvgl.OPA_TRANSP, pad = 0 })
ui:add_style(lab, st)
st:set({ text_color = 0xFFFFFF })
```

---

## 9. `create` 配置表

只认下列键；其它键忽略。

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `mem_max` | integer | `131072`（128 KiB） | 图形堆上限，字节。`0` = 脚本不限制。若小于「缓冲 + 约 64 KiB 余量」会 **自动抬到够用** |
| `dpi` | integer | 不改（固件默认） | `> 0` 才写入。例程常用 `130` |
| `refr_ms` | integer | 不改 | `> 0` 才改刷新定时器周期。闲时任务会睡，有脏区/动画再醒 |
| `buf_lines` | integer | `20` | **仅** 条带缓冲（`buf_mode="partial"` 或 `full_buf=false`）。`< 1` 按 20；大于屏高则夹到屏高 |
| `color` | string / integer | RGB565 | `"rgb888"` / `"888"` 或数字 `24` → 内部 RGB888 再转屏上 565；其它（含省略）→ RGB565 |
| `bg` | integer | 无 | 有这个键则覆盖主题背景；编码见第 11 节。省略则用主题色 |
| `double_buf` | boolean / integer | `true` | **当前忽略。** Lua 仍可写，底层强制单缓冲。boolean 请写 `true`/`false`；number 时 `0` 为关 |
| `full_buf` | boolean / integer | `true` | `true` / 非 0 → 整屏 DIRECT；`false` / `0` → 条带 PARTIAL。随后若写了 `buf_mode` 会被覆盖 |
| `buf_mode` | string | （跟 `full_buf`） | `"partial"` / `"part"` 条带；`"direct"` 整屏脏区；`"full"` 整屏全刷 |
| `theme` | string / boolean | 浅色 | `"dark"` / `"night"` 深色；其它字符串浅色。boolean：`true` 深色 |
| `dark` | boolean / integer | 跟 `theme` | 写了则覆盖 `theme`。number 时 `0` 浅色 |

缓冲怎么选：

| 模式 | 绘图缓冲 | 适用 |
| --- | --- | --- |
| DIRECT（默认 `full_buf=true` / `buf_mode="direct"`） | 整屏 × 1 | 内存够时更顺 |
| FULL（`buf_mode="full"`） | 同样整屏 × 1 | 每次全刷 |
| PARTIAL | `buf_lines` 行 × 1 | 省 RAM |

屏 GRAM 是 RGB565。`color="rgb888"` 只改内部色深，flush 仍转成 565 再发给面板。

---

## 10. 样式表字段

`ui:style` / `style:set` / `ui:set_style` 认下列键。后写的同义键覆盖先写的（如 `bg` 覆盖 `bg_color`）。

| 键 | 类型 | 作用 | 同义 |
| --- | --- | --- | --- |
| `bg_color` | integer | 背景色 | |
| `bg` | integer | 背景色，覆盖 `bg_color` | |
| `bg_opa` | opa | 背景不透明度 | |
| `text_color` | integer | 文字色 | |
| `text` | integer | 文字色，覆盖 `text_color` | |
| `font` | 字库句柄 | `ui:font` 的返回值；非法 userdata 忽略 | |
| `radius` | integer | 圆角 | |
| `pad` | integer | 四边内边距 | |
| `pad_all` | integer | 同上，覆盖 `pad` | |
| `pad_top` / `pad_bottom` / `pad_left` / `pad_right` | integer | 单边，在 `pad` 之后再写可覆盖对应边 | |
| `border_width` | integer | 边框宽 | |
| `border` | integer | 边框宽，覆盖 `border_width` | |
| `border_color` | integer | 边框色 | |
| `outline_width` | integer | 轮廓宽 | |
| `shadow_width` | integer | 阴影宽 | |
| `clip_corner` | 任意非 nil | 按 Lua 布尔裁圆角。**数字 `0` 为真** | |
| `scrollable` | **boolean** | 仅 `set_style`：可滚动；`false` 时同时关掉滚动条 | 写在 `ui:style` 表里无效 |
| `clickable` | **boolean** | 仅 `set_style`：可点 | 写在 `ui:style` 表里无效 |

未出现的键保持原值。颜色必须是 number，其它类型忽略该键。

---

## 11. 颜色怎么写

整数，两种编码按数值大小区分：

| 数值 | 当作 | 例子 |
| --- | --- | --- |
| `0`～`0xFFFF` | RGB565 | `lcd.RED`、`0xF800` |
| `> 0xFFFF` | RGB888（`0xRRGGBB`） | `0x00F5F5`、`0xFF0000` |
| `< 0` | 当成 `0` | |

`lcd.RED` 一类常量是 16 位，走 RGB565。自己写 `#RRGGBB` 时请给 `0xRRGGBB`（大于 `0xFFFF`）。

---

## 12. 刷屏与 Lua 时序

不要：

```lua
while true do
    ui:handler()   -- 错误：占着 Lua 还刷不出独立任务该有的低功耗睡眠
    rt.delay(10)
end
```

要：

```lua
-- 建完控件
rt.delay(-1)   -- 或业务循环里正常 delay；让出后独立任务才画
```

`create` 当时 **不会** 立刻全屏刷一次，等本次 Lua 时序结束。所以 `create` 和第一批控件可以写在同一段里，第一次让出时一起上屏。

刷屏走阻塞 DMA（`lcd_fill` / `lua_lcd_flush`）：图形任务把一块脏区发完才 `flush_ready`。发像素时会放下刷屏锁，避免把 Lua 调度卡死。当前只挂一块绘图缓冲；`opts.double_buf` 写了也不生效。脚本侧无感知，不必自己等 DMA。改字如果正赶上绘制（不是发屏）仍可能 `false, "lvgl busy"`，GPIO 短回调不受影响。`ui:img` / `ui:set_src` 解码本身不持刷屏锁；只有把像素挂到控件（或清源）时才短暂抢锁。

`on_click` 的函数是一次性任务：第一次让出之后图形任务可以刷屏。回调里改控件不必再 `mbox` 转发；若一截业务里不想露出半成品，仍用 `refr_pause` / `refr_resume`。`ui:click` 只投递，当前协程继续跑，等这次让出后回调才开始。

---

## 13. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `create` | `ui` | **抛错** |
| `label` / `btn` / `obj` / `img` / `font` | 句柄 | 刷屏占锁超时：`false, "lvgl busy"`；`img(src)` / `font(src)` 解码失败：**抛错**（不建对象）；其余 **抛错** |
| `set_src` | `true` | 非图片：`false, "not an image"`；源失败：`false, 文案`（原图还在）；锁超时：`false, "lvgl busy"` |
| `set_font` | `true` | 锁超时：`false, "lvgl busy"`；非法字库句柄：**抛错** `invalid lvgl font` |
| `set_scale` | `true` | 非图片：`false, "not an image"`；`scale < 0`：`false, "bad scale"`；锁超时：`false, "lvgl busy"` |
| `get_scale` | 整数 | 非图片：`false, "not an image"`；锁超时：`false, "lvgl busy"` |
| `scr_act` | 句柄或 `nil` | 未 create 抛错 |
| `on_click` / `click` | `true` | `click` 队列满：`false, "click post failed"`；其余 **抛错** |
| `set_text` | `true` | 非标签：`false, "not a label"`；刷屏占锁超时：`false, "lvgl busy"`；缺参抛错 |
| `handler` | 整数 `0` | 未 create 抛错 |
| `mem` | 三整数 | 未 create 抛错 |
| 其余 `ui:*` / `style:set` | `true` | 刷屏占锁超时：`false, "lvgl busy"`；未 create / 非法 userdata：**抛错** |
| `deinit`（无 ui） | `true` | — |

用 `pcall(lvgl.create, panel, opts)` 接住工厂失败。

**抛错摘要全表**

| 摘要 | 可能原因 |
| --- | --- |
| `lvgl already created` | 已有 ui 未 `deinit` |
| `arg#1 must be lcd object` | 第 1 参不是 `lcd.new` 的对象 |
| `lcd not initialized` | 面板没 new 成功或已 deinit |
| `lcd size is 0` | 宽高为 0，查 lcd cfg |
| `lv_display_create failed (check mem_max)` | 图形堆不够，加大 `mem_max` |
| `draw buf alloc failed (check mem_max)` | 整屏/条带缓冲分配失败；改 `partial` 或加大 `mem_max` |
| `line buf alloc failed (check mem_max)` | 行转换缓冲失败 |
| `lcd set owned failed` | 面板交不出（已被占用） |
| `lvgl task start failed` | 图形任务没起来，系统线程/信号量 |
| `call lvgl.create first` | 还没 create 就调了 `lvgl.label` 等 |
| `lvgl ui not initialized` | ui 已 deinit 还在用 |
| `invalid lvgl object` | 控件句柄无效或不是本模块对象 |
| `invalid lvgl style` | 样式对象无效或已被 GC |
| `invalid lvgl font` | `set_font` 的第 2 参不是 `ui:font` 的句柄 |
| `unsupported font format` | `ui:font(src)` 文件头不是点阵 `.bin` / TTF |
| `bad size` | `ui:font` 的 TTF 字号 `<= 0` |
| `invalid parent` | 父亲句柄坏或当前没有屏幕 |
| `label create failed` / `btn create failed` / `obj create failed` / `img create failed` | 控件堆不够，看 `ui:mem()`，加大 `mem_max` 或少建控件 |
| `unsupported image format` | `ui:img(src)` 文件头不是 JPEG / LVGL `.bin` |
| `bad src` / `not found` / `fs not mounted` / `decode failed` / `no mem` | `ui:img(src)` / `ui:font(src)` 源无效、找不到、解不开或缓冲不够；`set_src` 同一批文案走返回值 |
| `rt vm context missing` | 脚本还没进 rt 调度（极少见） |
| `lvgl callback full` | 同时挂了超过 32 个点击；先 `on_click(obj, nil)` 或 `deinit` |
| `lvgl event hook failed` | 控件堆不够，钩不上事件 |

**返回值失败**

| 摘要 | 可能原因 |
| --- | --- |
| `false, "not a label"` | `set_text` 的目标是按钮/容器，不是 `ui:label` 的句柄 |
| `false, "not an image"` | `set_src` / `set_scale` / `get_scale` 打在非 `ui:img` 的句柄上 |
| `false, "bad scale"` | `set_scale` 的因子小于 0 |
| `false, "click post failed"` | 内部事件队列满，稍后重试 |
| `false, "lvgl busy"` | 图形任务正在画/持锁，Lua 等锁超过约 200ms。可稍后重试；不要当致命错误 |
| `false, "bad src"` 等 | `set_src` 源失败，文案同 [7.27](#7-27-set-src) 表；原图还在 |

诊断：create 抛错看 `mem_max` 和是否已 create；`bound to lvgl` 出现在 **lcd** 侧；`not a label` 对按钮要用内部 label 或改 `set_style` 文字色而不是 `set_text(btn)`。图片失败先看文件头和 `ui:mem()`。

---

## 14. 资源上限与生命周期

| 项 | 对外数字 |
| --- | --- |
| 同时 `create` | **1** |
| 默认 `mem_max` | 128 KiB；不够容纳缓冲时自动抬升（另留约 64 KiB 给控件） |
| 默认条带行数 | 20 |
| `deinit` 等刷写 | 最多约 3 秒 |
| 控件 / 样式数量 | 吃同一块 `mem_max`，没有另外的「最多 N 个控件」接口 |
| 点击登记 | **32** 份；同一控件覆盖，不另占一份 |
| 点击任务槽 | 与 `rt.task_start` **共用**，整机大约 **16** 条。回调里 `delay` 才会占槽 |
| 图片 | 只认 JPEG 与 LVGL 图像 `.bin`。解码后的 RGB565 走 `mem_max`；隐藏的 image **仍占** 像素，直到 `set_src(nil)` 或 `deinit`。张数不另设上限，堆不够即 `no mem`。ublob 抽出明文时另占一块临时 RAM，解完即释放；lfs 流式读，不把整文件先拷进 Lua 堆 |
| 字库 | 点阵 `.bin` 或 TTF。整文件进 `mem_max`。TTF 原文常驻到字库 GC；点阵解析后释原文。ublob 明文 ≤ 256 KB；lfs 单文件 ≤ 512 KB。默认字仍占固件，不占这份堆。必须持有字库句柄 |

`create` 会把 lcd 对象钉在注册表里，脚本丢掉 `panel` 局部变量也不会先拆屏。`ui` 被 GC 或 `deinit` 后面板解除占用。

样式对象被 GC 时样式会被重置：仍 `add_style` 在控件上等于挂了一份空样式。字库同样：丢掉句柄就回收，控件上还挂着等于空悬。务必：

```lua
local style_icon = ui:style({ bg_opa = lvgl.OPA_TRANSP })
local font = ui:font({ ublob = "zh.bin" })
-- 放到模块级 / upvalue，不要建完就让它出作用域
```

控件句柄只是包装：GC 句柄不删树。整棵树在 `deinit` 时一起拆。字库要自己持有到不再给任何控件用为止。

VM 退出会回收还活着的 `ui`。

---

## 15. 选型对照

| 需求 | 用 |
| --- | --- |
| 先确认 SPI 和屏能出纯色 | [`lcd`](lcd.md) 的 `full` / `fill`，**尚未** `lvgl.create` |
| 标签、按钮、顶栏、主题 | 本模块 |
| 显示 JPEG / LVGL `.bin` | `ui:img` / `ui:set_src`；源可以是 RAM 字节、[`ublob`](ublob.md) 短名、已挂载的 [`lfs`](lfs.md) 对象 + 路径 |
| 已上屏的图要缩小 / 放大 | [`ui:set_scale`](#7-28-set-scale)；`256` / `lvgl.SCALE_NONE` 为原尺寸。[`ui:set_size`](#7-19-set-size) 只改外框 |
| BMP / PNG / GIF | 不是本模块 |
| create 之后再填色 | `ui:set_bg` / 样式，不要 `panel:full` |
| 标签要显示中文 / 自选字形 | [`ui:font`](#7-30-font) + [`ui:set_font`](#7-31-set-font)；子集点阵 `.bin` 或 TTF，源为 RAM / ublob / lfs |
| 点阵/字库自己 `lcd:pixel` 画 | 不是本模块 |
| 触摸 GUI | 输入设备未挂；`on_click` + `ui:click` 可先跑通业务 |

---

## 16. 完整示例

可烧录工程：

| 工程 | 演示 |
| --- | --- |
| [lvgl_demo](../../../examples/nt26/module/lvgl/lvgl_demo) | 标签、按钮、顶栏（`statusbar.lua`） |
| [lvgl_img](../../../examples/nt26/module/lvgl/lvgl_img) | `ublob` JPEG → `ui:img` → `ui:set_scale` 循环缩小再放大 |

下面是 `lvgl_demo` 同路径的最小脚本。脚号按板子改；SPI0 与 UART2 默认脚重叠时需要配置里 `[uart.2] pin_map=1`。图片不要写进仓库，放到工程内置文件系统、存储选 blob 后再 `set_src`。

```lua
local rt   = require("rt")
local log  = require("log")
local lcd  = require("lcd")
local lvgl = require("lvgl")

local panel, err = lcd.new({
    driver = lcd.ST7789,
    bus    = lcd.SPI0,
    hz     = 76 * 1000000,
    width  = 240,
    height = 280,
    x_off  = 0,
    y_off  = 20,
    rotate = lcd.ROTATE_0,
    dc = 31, cs = 8, rst = 30, bl = 32,
})
if not panel then
    log.error("lcd.new %s", tostring(err))
    while true do rt.delay(10000) end
end

panel:full(lcd.WHITE)

local ok, ui = pcall(lvgl.create, panel, {
    mem_max    = 384 * 1024,
    color      = "rgb565",
    dpi        = 130,
    refr_ms    = 33,
    double_buf = true,
    full_buf   = true,
    theme      = "dark",
    bg         = 0x00F5F5,
})
if not ok then
    log.error("create %s", tostring(ui))
    while true do rt.delay(10000) end
end

local used, peak, limit = ui:mem()
log.info("lvgl mem %d/%d peak=%d", used, limit, peak)

local btn = ui:btn("NT26")
ui:set_size(btn, 72, 32)
ui:set_pos(btn, 16, 48)

local hint = ui:label("hello")
ui:set_pos(hint, 16, 100)

-- 图片：先建空控件，再 set_src。不要把大图写进仓库。
-- local pic = ui:img()
-- ui:set_src(pic, { ublob = "logo.jpg" })
-- ui:set_src(pic, { lfs = fs, path = "/logo.bin" })
-- ui:set_scale(pic, 128)          -- 一半；256 / lvgl.SCALE_NONE 为原尺寸
-- ui:center(pic)
-- ui:set_src(pic, nil)   -- 清像素

-- 字库：点阵 .bin 或 TTF。必须持有 font。不要把字库文件写进仓库。
-- local font = ui:font({ ublob = "zh.bin" })
-- local font = ui:font({ ublob = "zh.ttf", size = 14 })
-- local font = ui:font({ lfs = fs, path = "/zh.bin" })
-- local font = ui:font(bytes, 16)   -- RAM 里已是整份二进制
-- ui:set_font(hint, font)
-- ui:set_text(hint, "温度")
-- ui:set_style(hint, { font = font })
-- ui:set_font(hint, nil)            -- 回到默认字

ui:on_click(btn, function(obj, ev)
    ui:set_text(hint, ev.name)
    rt.delay(100)
end)

rt.delay(-1)
```

`create` 之后再 `panel:full(lcd.RED)` 会得到 `false, "lcd bound to lvgl"`。

图片缩放循环（完整工程见 [lvgl_img](../../../examples/nt26/module/lvgl/lvgl_img)）。`set_src` 成功后不要钉 `set_size`；每次改因子后 `center`，用 `rt.delay` 让出，不要循环 `ui:handler()`。

```lua
local pic = ui:img()
local src_ok, src_err = ui:set_src(pic, { ublob = "photo.jpg" })
if not src_ok then
    log.error("set_src %s", tostring(src_err))
    rt.delay(-1)
end

local scale = lvgl.SCALE_NONE
local dir = -4
while true do
    scale = scale + dir
    if scale <= 64 then
        scale = 64
        dir = 4
    elseif scale >= lvgl.SCALE_NONE then
        scale = lvgl.SCALE_NONE
        dir = -4
    end
    ui:set_scale(pic, scale)
    ui:center(pic)
    rt.delay(33)
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版 |
| 1.1.0 | 2026-09-05 | 补全全部抛错/返回文案与可能原因 |
| 1.2.0 | 2026-09-07 | 增加 `on_click` / `click`；图形回调按一次性任务执行，可 `rt.delay` |
| 1.2.1 | 2026-09-07 | `click` 只投内部事件、不抢刷屏锁；队列满返回 `click post failed` |
| 1.3.0 | 2026-09-07 | 刷屏改为阻塞 DMA + 单缓冲；`double_buf` 可写但不生效 |
| 1.3.1 | 2026-09-07 | 阻塞发屏时放下锁；Lua 等锁超时返回 `lvgl busy`，避免卡死 GPIO |
| 1.4.0 | 2026-09-09 | 增加 `ui:img` / `ui:set_src`：JPEG 与 LVGL `.bin`，源为 RAM / ublob / lfs；解码一次挂像素，隐藏仍占内存 |
| 1.5.0 | 2026-09-09 | 增加 `ui:set_scale` / `ui:get_scale` 与 `lvgl.SCALE_NONE`（256 = 原尺寸）；`set_size` 只改外框不缩放像素 |
| 1.5.1 | 2026-09-10 | 选型与完整示例补上 `set_scale` 循环；可烧录工程增加 [lvgl_img](../../../examples/nt26/module/lvgl/lvgl_img) |
| 1.6.0 | 2026-09-10 | 增加 `ui:font` / `ui:set_font`：LVGL 点阵 `.bin` 与 TTF；源为 RAM / ublob / lfs；样式表可写 `font` |
| 1.6.1 | 2026-09-10 | 点阵 `.bin` 支持 Font Converter 压缩输出 |
