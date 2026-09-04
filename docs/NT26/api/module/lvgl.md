# lvgl

**文档版本** `1.0.0`

把已经 `lcd.new` 好的彩屏交给图形栈：控件、主题、脏区刷新都走本模块。刷屏在独立任务里跑，脚本只要建树、改字、改样式，然后 `rt.delay` 让出即可。

```lua
local lvgl = require("lvgl")
```

平台预加载模块，无需额外 `.lua` 文件。须先 [`lcd.new`](lcd.md) 得到面板，再 `lvgl.create(panel, opts)`。

本绑定是 LVGL 的 **子集**：标签、按钮、空白容器、样式覆盖。没有触摸输入、没有点击回调、没有官方 LVGL 全量控件表。默认字体由固件编入（例程按 Montserrat 14，ASCII + FontAwesome 子集）；不要假设能显示完整中文。

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
3. `ui:scr_act` / `ui:label` / `ui:btn` / `ui:obj` 建树；外观用默认主题，再用 `ui:style` + `add_style` 或 `ui:set_style` 覆盖。
4. 改文字、改位置只记脏。脚本让出后，独立任务才画、才往屏上刷。
5. 不要循环 `ui:handler()`。长期脚本用 `rt.delay(-1)` 或自己的业务循环。
6. 不用时 `ui:deinit()`，才能再 `create` 一次。

| 能做 | 不能做 |
| --- | --- |
| 标签、按钮、空白容器 | 官方 LVGL 其它控件（slider、list、img…）未挂 |
| 默认 light/dark 主题 + 样式覆盖 | 换官方主题引擎、自定义字体文件 |
| 独立任务刷脏区 | 触摸、按键、点击回调 |
| RGB565 屏（GRAM）；内部也可选 RGB888 再转 565 | 用本模块当 `lcd:fill` 的替代去打点 |

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  lcd.new → lvgl.create → label/btn/style → rt.delay     │
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
│  定时器到期或被叫醒   │          │  连续块可异步 DMA    │
│  再画脏区、flush     │          │  非整行仍同步逐行    │
└─────────────────────┘          └─────────────────────┘
```

| 路径 | 谁在跑 | 是否占用 Lua 调度 | 典型用途 |
| --- | --- | --- | --- |
| `create` / 建控件 / 改 style | 当前 Lua 协程 | 是（同步，一般很快） | 组界面 |
| 脏区绘制 + 刷屏 | **独立任务** | 否（Lua 让出之后才跑） | 出图 |
| `refr_pause` … `refr_resume` | 脚本暂停任务刷屏 | 否 | 中间有 `rt.delay` 时避免刷到半成品 |
| `ui:handler` | 只叫醒任务一脚 | 否 | 兼容旧写法；不要循环 |
| `lcd:full` 等（create 之后） | — | 立刻失败 | 不要再用 |

一次 `rt.delay` / 邮箱等待 / 事件回调返回之前，图形任务看到「Lua 还在跑」就不会 `handler`。控件创建、改文字都只记脏，本次让出后再画。任意业务自然写即可，不必手动 `invalidate`，也不靠固定延时。

若中间必须 `delay`/`wait`、又不想让半棵树先上屏：`ui:refr_pause()` → 建完 / 改完 → `ui:refr_resume()`。可嵌套，成对使用。

---

## 3. 对象模型

三种 userdata，职责不同：

| 对象 | 怎么来 | 有没有方法 | 必须持有 |
| --- | --- | --- | --- |
| **ui** | `lvgl.create` | 有，见 [第 7 节](#7-对象方法) | 是，丢掉会被回收并 `deinit` |
| **控件** | `scr_act` / `label` / `btn` / `obj` | **没有。** 不能 `lab:set_pos` | 建议拿着方便传给 `ui:set_*`；GC 掉句柄 **不会** 删掉树上的控件 |
| **样式** | `ui:style({...})` | 只有 `style:set` | **是。** 丢掉引用会被回收并重置；已 `add_style` 的控件会丢这份样式 |

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

`luaopen` 只导出两个不透明度符号。主题名、色深、缓冲模式都是 **字符串**，没有对应整数常量。

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `lvgl.OPA_TRANSP` | `0` | 全透明 | 样式 `bg_opa`，或 `0` |
| `lvgl.OPA_COVER` | `255` | 不透明 | 样式 `bg_opa`，或 `255` |

`bg_opa` 还可以直接写字符串 `"cover"` / `"COVER"` / `"transp"` / `"transparent"` / `"TRANSP"`，或 boolean（`true` = COVER，`false` = TRANSP；数字 `0` 当 boolean 时为真）。整数 `0`～`255` 按不透明度用。

未挂到模块的官方 LVGL 枚举（部件选择器、调色板名、对齐常量等）不要当可用 API。`add_style` 的 `selector` 若要传，请传整数；省略即 `0`（主部件）。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `panel` | lcd 对象 | 必须已经 `lcd.new` 成功 |
| `ui` | userdata | `create` 的返回值 |
| `obj` / `parent` / `lab` / `btn` | userdata | 控件句柄，元表无方法 |
| `style` | userdata | `ui:style` 的返回值 |
| `opts` / 样式表 | table | 见 [第 9 节](#9-create-配置表)、[第 10 节](#10-样式表字段) |
| `color` | integer | 见 [第 11 节](#11-颜色怎么写) |
| `text` | string | Lua 会把 number 转成字面 |
| `selector` | integer | 样式选择器，省略为 `0` |
| `opa` | integer / string / boolean | 见第 4 节 |
| `x` `y` `w` `h` `r` | integer | 像素 |

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
| `opts` | table | 否 | 见 [第 9 节](#9-create-配置表) | 省略则 RGB565、双缓冲、整屏 DIRECT、浅色主题、`mem_max` 128 KiB |

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
| `draw buf2 alloc failed (check mem_max)` | 第二块缓冲不够（双缓冲） |
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

当前活动屏幕。省略 `parent` 的 `label`/`btn`/`obj` 都挂在这上面。

**调用模式**

```lua
scr = ui:scr_act()
```

**返回** 控件句柄；没有屏幕时 `nil`。

每次调用都 **新包一层** 句柄，指向同一块屏。丢掉旧句柄不影响树上的对象。

---

### 7.4 `ui:label([parent,] [text])` {#7-4-label}

建一个标签。

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

本绑定 **没有** 点击回调。按钮只是一块可看的控件。

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

宽高，像素。

**调用模式**

```lua
ok = ui:set_size(obj, w, h)
```

**返回** `true`。

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
| `double_buf` | boolean / integer | `true` | 两块绘图缓冲。boolean 请写 `true`/`false`；number 时 `0` 为关 |
| `full_buf` | boolean / integer | `true` | `true` / 非 0 → 整屏 DIRECT；`false` / `0` → 条带 PARTIAL。随后若写了 `buf_mode` 会被覆盖 |
| `buf_mode` | string | （跟 `full_buf`） | `"partial"` / `"part"` 条带；`"direct"` 整屏脏区；`"full"` 整屏全刷 |
| `theme` | string / boolean | 浅色 | `"dark"` / `"night"` 深色；其它字符串浅色。boolean：`true` 深色 |
| `dark` | boolean / integer | 跟 `theme` | 写了则覆盖 `theme`。number 时 `0` 浅色 |

缓冲怎么选：

| 模式 | 绘图缓冲 | 适用 |
| --- | --- | --- |
| DIRECT（默认 `full_buf=true` / `buf_mode="direct"`） | 整屏 × 1 或 2 | 内存够时更顺 |
| FULL（`buf_mode="full"`） | 同样整屏 | 每次全刷 |
| PARTIAL | `buf_lines` 行 × 1 或 2 | 省 RAM |

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

连续整块 RGB565 走面板异步 DMA；带 stride 的非整行仍同步逐行。脚本侧无感知，不必自己等 DMA。

---

## 13. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `create` | `ui` | **抛错** |
| `label` / `btn` / `obj` | 句柄 | **抛错** |
| `scr_act` | 句柄或 `nil` | 未 create 抛错 |
| `set_text` | `true` | 非标签：`false, "not a label"`；缺参抛错 |
| `handler` | 整数 `0` | 未 create 抛错 |
| `mem` | 三整数 | 未 create 抛错 |
| 其余 `ui:*` / `style:set` | `true` | 未 create / 非法 userdata：**抛错** |
| `deinit`（无 ui） | `true` | — |

用 `pcall(lvgl.create, panel, opts)` 接住工厂失败。控件句柄类型不对时多半是 `invalid lvgl object`，不是 `nil`。

---

## 14. 资源上限与生命周期

| 项 | 对外数字 |
| --- | --- |
| 同时 `create` | **1** |
| 默认 `mem_max` | 128 KiB；不够容纳缓冲时自动抬升（另留约 64 KiB 给控件） |
| 默认条带行数 | 20 |
| `deinit` 等刷写 | 最多约 3 秒 |
| 控件 / 样式数量 | 吃同一块 `mem_max`，没有另外的「最多 N 个控件」接口 |

`create` 会把 lcd 对象钉在注册表里，脚本丢掉 `panel` 局部变量也不会先拆屏。`ui` 被 GC 或 `deinit` 后面板解除占用。

样式对象被 GC 时样式会被重置：仍 `add_style` 在控件上等于挂了一份空样式。务必：

```lua
local style_icon = ui:style({ bg_opa = lvgl.OPA_TRANSP })
-- 放到模块级 / upvalue，不要建完就让它出作用域
```

控件句柄只是包装：GC 句柄不删树。整棵树在 `deinit` 时一起拆。

VM 退出会回收还活着的 `ui`。

---

## 15. 选型对照

| 需求 | 用 |
| --- | --- |
| 先确认 SPI 和屏能出纯色 | [`lcd`](lcd.md) 的 `full` / `fill`，**尚未** `lvgl.create` |
| 标签、按钮、顶栏、主题 | 本模块 |
| create 之后再填色 | `ui:set_bg` / 样式，不要 `panel:full` |
| 点阵/字库自己画 | 不是本模块；也不是 `lcd:pixel` 循环 |
| 触摸 GUI | 本绑定没有输入设备 |

---

## 16. 完整示例

可烧录工程：[examples/NT26/module/lvgl/lvgl_demo](../../../examples/NT26/module/lvgl/lvgl_demo)（含 `statusbar.lua` 顶栏）。下面是同一条路径的最小脚本。脚号按板子改；SPI0 与 UART2 默认脚重叠时需要配置里 `[uart.2] pin_map=1`。

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

rt.delay(-1)
```

`create` 之后再 `panel:full(lcd.RED)` 会得到 `false, "lcd bound to lvgl"`。

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-05 | 首版 |
