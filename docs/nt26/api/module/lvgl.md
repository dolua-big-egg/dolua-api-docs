# lvgl

**文档版本** `1.15.0`

把已经 `lcd.new` 好的彩屏交给图形栈：控件、主题、脏区刷新都走本模块。刷屏在独立任务里跑，脚本只要建树、改字、改样式，然后 `rt.delay` 让出即可。

```lua
local lvgl = require("lvgl")
```

平台预加载模块，无需额外 `.lua` 文件。须先 [`lcd.new`](lcd.md) 得到面板，再 `lvgl.create(panel, opts)`。

本绑定是 LVGL 的 **子集**：标签、弧标签、按钮、空白容器、进度条、弧进度、复选框、下拉框、文本框、软键盘、开关、转圈、图片、消息框、样式覆盖。按钮点击已挂上；触摸输入设备尚未接入，真机点按要等输入，脚本可用 `ui:click` 走同一条回调。软键盘的键同样要等触摸；没有输入时用 [`set_mode`](#7-43-set-mode) 看布局，用 [`add_text`](#7-59-add-text) 改已绑定的文本框。消息框脚注按钮同样要等触摸或 `ui:click`；关掉框请 [`ui:close`](#7-56-close)。没有官方 LVGL 全量控件表。默认字体由固件编入（Montserrat 14，ASCII + FontAwesome 子集）。要显示中文请用 [`ui:font`](#7-30-font) 加载自己的子集字库（LVGL 点阵 `.bin` 或 TTF），不要假设默认字含汉字。图片只认 **JPEG** 和 **LVGL 图像 `.bin`**（靠文件头，不靠扩展名）；BMP 不支持。字库 `.bin` 和图像 `.bin` 不是同一种文件。

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
  - [7.32 `ui:arclabel`](#7-32-arclabel)
  - [7.33 `ui:bar`](#7-33-bar)
  - [7.34 `ui:align`](#7-34-align)
  - [7.35 `ui:set_text_align`](#7-35-set-text-align)
  - [7.36 `ui:set_dir`](#7-36-set-dir)
  - [7.37 `ui:set_range`](#7-37-set-range)
  - [7.38 `ui:set_value`](#7-38-set-value)
  - [7.39 `ui:set_start_value`](#7-39-set-start-value)
  - [7.40 `ui:get_value`](#7-40-get-value)
  - [7.41 `ui:get_range`](#7-41-get-range)
  - [7.42 `ui:get_dir`](#7-42-get-dir)
  - [7.43 `ui:set_mode`](#7-43-set-mode)
  - [7.44 `ui:set_angle`](#7-44-set-angle)
  - [7.45 `ui:set_offset`](#7-45-set-offset)
  - [7.46 `ui:set_center_offset`](#7-46-set-center-offset)
  - [7.47 `ui:set_recolor`](#7-47-set-recolor)
  - [7.48 `ui:set_overflow`](#7-48-set-overflow)
  - [7.49 `ui:arc`](#7-49-arc)
  - [7.50 `ui:set_bg_angle`](#7-50-set-bg-angle)
  - [7.51 `ui:set_rotation`](#7-51-set-rotation)
  - [7.52 `ui:checkbox`](#7-52-checkbox)
  - [7.53 `ui:dropdown`](#7-53-dropdown)
  - [7.54 `ui:set_options`](#7-54-set-options)
  - [7.55 `ui:open`](#7-55-open)
  - [7.56 `ui:close`](#7-56-close)
  - [7.57 `ui:textarea`](#7-57-textarea)
  - [7.58 `ui:get_text`](#7-58-get-text)
  - [7.59 `ui:add_text`](#7-59-add-text)
  - [7.60 `ui:set_placeholder`](#7-60-set-placeholder)
  - [7.61 `ui:set_password`](#7-61-set-password)
  - [7.62 `ui:set_one_line`](#7-62-set-one-line)
  - [7.63 `ui:switch`](#7-63-switch)
  - [7.64 `ui:spinner`](#7-64-spinner)
  - [7.65 `ui:set_anim`](#7-65-set-anim)
  - [7.66 `ui:get_anim`](#7-66-get-anim)
  - [7.67 `ui:keyboard`](#7-67-keyboard)
  - [7.68 `ui:set_textarea`](#7-68-set-textarea)
  - [7.69 `ui:set_popovers`](#7-69-set-popovers)
  - [7.70 `ui:add_state`](#7-70-add-state)
  - [7.71 `ui:remove_state`](#7-71-remove-state)
  - [7.72 `ui:msgbox`](#7-72-msgbox)
  - [7.73 `ui:add_footer_btn`](#7-73-add-footer-btn)
  - [7.74 `ui:add_close_btn`](#7-74-add-close-btn)
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
3. `ui:scr_act` / `ui:label` / `ui:arclabel` / `ui:btn` / `ui:obj` / `ui:bar` / `ui:arc` / `ui:checkbox` / `ui:dropdown` / `ui:textarea` / `ui:keyboard` / `ui:switch` / `ui:spinner` / `ui:img` / `ui:msgbox` 建树；外观用默认主题，再用 `ui:style` + `add_style` 或 `ui:set_style` 覆盖。图片源见 [7.27](#7-27-set-src)。
4. 改文字、改位置只记脏。脚本让出后，独立任务才画、才往屏上刷。
5. 不要循环 `ui:handler()`。长期脚本用 `rt.delay(-1)` 或自己的业务循环。
6. 不用时 `ui:deinit()`，才能再 `create` 一次。

| 能做 | 不能做 |
| --- | --- |
| 标签、弧标签、按钮、空白容器、进度条、弧进度、复选框、下拉框、文本框、软键盘、开关、转圈、图片、消息框 | 官方 LVGL 其它控件（slider、list…）未挂 |
| JPEG、LVGL 图像 `.bin`（RAM / ublob / lfs）；`set_scale` 缩放像素 | BMP、PNG、GIF；不认盘符路径；`set_size` 只改外框不缩放 |
| 子集字库：LVGL 点阵 `.bin`（含压缩）/ TTF（RAM / ublob / lfs） | 运行时 OTF(CFF)、WOFF、WOFF2；FreeType |
| 默认 light/dark 主题 + 样式覆盖 | 换官方主题引擎 |
| 独立任务刷脏区 | 触摸、按键输入设备（点按要等输入，或用 `ui:click`） |
| 按钮点击：回调按 **任务** 跑，可 `rt.delay` | 不要当 gpio 那种「立刻返回」的短回调 |
| RGB565 屏（ST7789 GRAM）；内部也可选 RGB888 再转 565。SSD1306 先用 [`lcd`](lcd.md) 的 1 bit 画布，不要 `lvgl.create` | 用本模块当 `lcd:fill` 的替代去打点 |

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  lcd.new → lvgl.create → label/arclabel/bar/arc/checkbox/dropdown/textarea/keyboard/switch/spinner/btn/img/msgbox/style → rt.delay │
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
| **控件** | `scr_act` / `label` / `arclabel` / `btn` / `obj` / `bar` / `arc` / `checkbox` / `dropdown` / `textarea` / `keyboard` / `switch` / `spinner` / `img` | **没有。** 不能 `lab:set_pos` | 建议拿着方便传给 `ui:set_*`；GC 掉句柄 **不会** 删掉树上的控件 |
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
| `set_value` / `set_start_value` 的 `anim`、`set_recolor` | boolean 走 Lua 布尔；number 走 `~= 0` | boolean 路径下 **`0` 为真**。请写 `true`/`false`；整数请写 `0`/`1` |

推荐：开关一律 `true`/`false`，主题用 `"light"` / `"dark"`。

---

## 4. 常量与枚举

`luaopen` 导出不透明度、缩放基准，以及对齐 / 方向 / 进度条与弧进度模式 / 下拉展开方向 / 开关方向 / 软键盘模式 / 部件与状态 / 弧标签溢出。主题名、色深、缓冲模式仍是 **字符串**。

### 4.1 不透明度与缩放

| 符号 | 值 | 含义 | 用在哪个参数 |
| --- | --- | --- | --- |
| `lvgl.OPA_TRANSP` | `0` | 全透明 | 样式 `bg_opa`，或 `0` |
| `lvgl.OPA_COVER` | `255` | 不透明 | 样式 `bg_opa`，或 `255` |
| `lvgl.SCALE_NONE` | `256` | 图片 1:1，不缩放 | `ui:set_scale` |

`bg_opa` 还可以直接写字符串 `"cover"` / `"COVER"` / `"transp"` / `"transparent"` / `"TRANSP"`，或 boolean（`true` = COVER，`false` = TRANSP；数字 `0` 当 boolean 时为真）。整数 `0`～`255` 按不透明度用。

### 4.2 控件对齐 `ui:align`

相对父亲（或另一控件）摆位置。`ALIGN_OUT_*` 只适合 `align(obj, base, …)` 那种「对齐到另一控件」；相对父亲时不要用 `OUT_`。

| 符号 | 值 | 含义 | 字符串写法 |
| --- | --- | --- | --- |
| `lvgl.ALIGN_DEFAULT` | `0` | 默认（LTR 左上） | `"default"` |
| `lvgl.ALIGN_TOP_LEFT` | `1` | 上左 | `"top_left"` |
| `lvgl.ALIGN_TOP_MID` | `2` | 上中 | `"top_mid"` |
| `lvgl.ALIGN_TOP_RIGHT` | `3` | 上右 | `"top_right"` |
| `lvgl.ALIGN_BOTTOM_LEFT` | `4` | 下左 | `"bottom_left"` |
| `lvgl.ALIGN_BOTTOM_MID` | `5` | 下中 | `"bottom_mid"` |
| `lvgl.ALIGN_BOTTOM_RIGHT` | `6` | 下右 | `"bottom_right"` |
| `lvgl.ALIGN_LEFT_MID` | `7` | 左中 | `"left_mid"` |
| `lvgl.ALIGN_RIGHT_MID` | `8` | 右中 | `"right_mid"` |
| `lvgl.ALIGN_CENTER` | `9` | 居中 | `"center"` |
| `lvgl.ALIGN_OUT_TOP_LEFT` | `10` | 外侧上左 | `"out_top_left"` |
| `lvgl.ALIGN_OUT_TOP_MID` | `11` | 外侧上中 | `"out_top_mid"` |
| `lvgl.ALIGN_OUT_TOP_RIGHT` | `12` | 外侧上右 | `"out_top_right"` |
| `lvgl.ALIGN_OUT_BOTTOM_LEFT` | `13` | 外侧下左 | `"out_bottom_left"` |
| `lvgl.ALIGN_OUT_BOTTOM_MID` | `14` | 外侧下中 | `"out_bottom_mid"` |
| `lvgl.ALIGN_OUT_BOTTOM_RIGHT` | `15` | 外侧下右 | `"out_bottom_right"` |
| `lvgl.ALIGN_OUT_LEFT_TOP` | `16` | 外侧左上 | `"out_left_top"` |
| `lvgl.ALIGN_OUT_LEFT_MID` | `17` | 外侧左中 | `"out_left_mid"` |
| `lvgl.ALIGN_OUT_LEFT_BOTTOM` | `18` | 外侧左下 | `"out_left_bottom"` |
| `lvgl.ALIGN_OUT_RIGHT_TOP` | `19` | 外侧右上 | `"out_right_top"` |
| `lvgl.ALIGN_OUT_RIGHT_MID` | `20` | 外侧右中 | `"out_right_mid"` |
| `lvgl.ALIGN_OUT_RIGHT_BOTTOM` | `21` | 外侧右下 | `"out_right_bottom"` |

### 4.3 文字对齐 `ui:set_text_align`

直线标签与弧标签共用这组整数。弧标签的 leading/trailing 对应 left/right。

| 符号 | 值 | 含义 | 字符串写法 |
| --- | --- | --- | --- |
| `lvgl.TEXT_ALIGN_AUTO` / `TEXT_ALIGN_DEFAULT` | `0` | 自动 / 默认 | `"auto"` / `"default"` |
| `lvgl.TEXT_ALIGN_LEFT` / `TEXT_ALIGN_LEADING` | `1` | 左 / 起点 | `"left"` / `"leading"` |
| `lvgl.TEXT_ALIGN_CENTER` | `2` | 居中 | `"center"` |
| `lvgl.TEXT_ALIGN_RIGHT` / `TEXT_ALIGN_TRAILING` | `3` | 右 / 终点 | `"right"` / `"trailing"` |

### 4.4 方向 `ui:set_dir`

弧标签、进度条、下拉框、开关的方向枚举数值有重叠，**按控件选带前缀的符号**。下拉框的 `LEFT`/`RIGHT` 是 1/2，和进度条 / 开关的水平/垂直不是同一套。开关的 `AUTO`/`HORIZONTAL`/`VERTICAL` 与进度条同值，请写 `SWITCH_DIR_*`。

| 符号 | 值 | 用在 | 字符串写法 |
| --- | --- | --- | --- |
| `lvgl.ARCLABEL_DIR_CLOCKWISE` / `DIR_CLOCKWISE` | `0` | 弧标签顺时针 | `"cw"` / `"clockwise"` |
| `lvgl.ARCLABEL_DIR_COUNTER_CLOCKWISE` / `DIR_COUNTER_CLOCKWISE` | `1` | 弧标签逆时针 | `"ccw"` / `"counterclockwise"` / `"counter_clockwise"` |
| `lvgl.BAR_DIR_AUTO` / `DIR_AUTO` | `0` | 进度条随宽高自动 | `"auto"` |
| `lvgl.BAR_DIR_HORIZONTAL` / `DIR_HORIZONTAL` | `1` | 进度条水平 | `"h"` / `"hor"` / `"horizontal"` |
| `lvgl.BAR_DIR_VERTICAL` / `DIR_VERTICAL` | `2` | 进度条垂直 | `"v"` / `"ver"` / `"vertical"` |
| `lvgl.DROPDOWN_DIR_LEFT` | `1` | 下拉列表向左展开 | `"left"` |
| `lvgl.DROPDOWN_DIR_RIGHT` | `2` | 下拉列表向右展开 | `"right"` |
| `lvgl.DROPDOWN_DIR_TOP` | `4` | 下拉列表向上展开 | `"top"` |
| `lvgl.DROPDOWN_DIR_BOTTOM` | `8` | 下拉列表向下展开（创建时默认） | `"bottom"` |
| `lvgl.SWITCH_DIR_AUTO` | `0` | 开关随宽高自动 | `"auto"` |
| `lvgl.SWITCH_DIR_HORIZONTAL` | `1` | 开关水平 | `"h"` / `"hor"` / `"horizontal"` |
| `lvgl.SWITCH_DIR_VERTICAL` | `2` | 开关垂直 | `"v"` / `"ver"` / `"vertical"` |

### 4.5 进度条 / 弧进度 / 键盘模式与弧标签溢出 {#45-进度条模式与弧标签溢出}

进度条、弧进度、软键盘的模式枚举数值有重叠，**按控件选带前缀的符号**。整数 `2` 在进度条是 `RANGE`，在弧进度是 `REVERSE`，在软键盘是 `SPECIAL`。

| 符号 | 值 | 用在 | 字符串写法 |
| --- | --- | --- | --- |
| `lvgl.BAR_MODE_NORMAL` | `0` | 进度条：从最小值长到当前值 | `"normal"` |
| `lvgl.BAR_MODE_SYMMETRICAL` | `1` | 进度条：以 0 为中心向两侧 | `"symmetrical"` / `"sym"` |
| `lvgl.BAR_MODE_RANGE` | `2` | 进度条：用起始值 + 当前值画一段 | `"range"` |
| `lvgl.ARC_MODE_NORMAL` | `0` | 弧进度：指示条顺时针从背景起点长 | `"normal"` |
| `lvgl.ARC_MODE_SYMMETRICAL` | `1` | 弧进度：以背景中点向两侧 | `"symmetrical"` / `"sym"` |
| `lvgl.ARC_MODE_REVERSE` | `2` | 弧进度：指示条逆时针从背景终点长 | `"reverse"` / `"rev"` |
| `lvgl.KEYBOARD_MODE_TEXT_LOWER` | `0` | 软键盘：小写字母（创建时默认） | `"lower"` / `"abc"` / `"text_lower"` |
| `lvgl.KEYBOARD_MODE_TEXT_UPPER` | `1` | 软键盘：大写字母 | `"upper"` / `"ABC"` / `"caps"` / `"text_upper"` |
| `lvgl.KEYBOARD_MODE_SPECIAL` | `2` | 软键盘：符号 | `"special"` / `"spec"` / `"1#"` |
| `lvgl.KEYBOARD_MODE_NUMBER` | `3` | 软键盘：数字 | `"number"` / `"num"` / `"numeric"` |
| `lvgl.OVERFLOW_VISIBLE` | `0` | 弧文字可画出控件 | `"visible"` |
| `lvgl.OVERFLOW_ELLIPSIS` | `1` | 超出画省略号 | `"ellipsis"` |
| `lvgl.OVERFLOW_CLIP` | `2` | 超出裁掉（创建时默认） | `"clip"` |

### 4.6 部件与状态 `set_style` / `add_style` 选择器 {#46-部件与状态}

`selector` 是 **部件 + 状态** 按位或。省略或 `0` 等于主部件、默认状态。开关改外观时：轨道用 `PART_MAIN`，打开后的填充用 `PART_INDICATOR | STATE_CHECKED`，滑块用 `PART_KNOB`。软键盘按键用 `PART_ITEMS`。Lua 5.5 用 `|` 组合。

| 符号 | 值 | 含义 |
| --- | --- | --- |
| `lvgl.PART_MAIN` | `0` | 主部件（开关轨道、标签本体） |
| `lvgl.PART_INDICATOR` | `131072`（`0x020000`） | 指示条：开关打开后的填充、进度条指示、复选框勾选框、转圈转动段 |
| `lvgl.PART_KNOB` | `196608`（`0x030000`） | 滑块 / 旋钮 |
| `lvgl.PART_ITEMS` | `327680`（`0x050000`） | 重复单元：软键盘按键 |
| `lvgl.STATE_DEFAULT` | `0` | 默认状态 |
| `lvgl.STATE_CHECKED` | `4`（`1 << 2`） | 已打开 / 已勾选 |
| `lvgl.STATE_PRESSED` | `128`（`1 << 7`） | 按下。主题按钮会变暗并略放大；`ui:click` **不会**自动加上，要用 [`add_state`](#7-70-add-state) |

未列出的官方部件、状态不要当已导出 API。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `panel` | lcd 对象 | 必须已经 `lcd.new` 成功 |
| `ui` | userdata | `create` 的返回值 |
| `obj` / `parent` / `lab` / `btn` / `img` / `bar` / `arc` / `checkbox` / `dropdown` / `textarea` / `keyboard` / `switch` / `spinner` / `msgbox` | userdata | 控件句柄，元表无方法 |
| `font` | userdata | `ui:font` 的返回值 |
| `src` | string 或 table | 图片见 [7.27](#7-27-set-src)；字库见 [7.30](#7-30-font)。表字段同一套：`data` / `ublob` / `lfs`+`path` |
| `style` | userdata | `ui:style` 的返回值 |
| `opts` / 样式表 | table | 见 [第 9 节](#9-create-配置表)、[第 10 节](#10-样式表字段) |
| `color` | integer | 见 [第 11 节](#11-颜色怎么写) |
| `text` | string | Lua 会把 number 转成字面 |
| `selector` | integer | 样式选择器，省略为 `0` |
| `opa` | integer / string / boolean | 见第 4 节 |
| `align` / `dir` / `mode` / `overflow` | integer 或 string | 见 [第 4 节](#4-常量与枚举) |
| `x` `y` `w` `h` `r` | integer | 像素 |
| `min` `max` `value` | integer / boolean | 进度条、弧进度、复选框勾选、开关开合、下拉选中下标 |
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

当前活动屏幕。省略 `parent` 的 `label`/`arclabel`/`btn`/`obj`/`bar`/`arc`/`checkbox`/`dropdown`/`textarea`/`keyboard`/`switch`/`spinner`/`img` 都挂在这上面。

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
| `selector` | integer | 否 | `0` | 部件+状态，见 [4.6](#46-部件与状态)；传了 number 才改 |

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

`props` 必须是 table，否则抛错。字段见 [第 10 节](#10-样式表字段)。`scrollable` / `clickable` 只在这里生效。`selector` 见 [4.6](#46-部件与状态)；省略即主部件。开关示例：`ui:set_style(sw, { bg = 0x34C759 }, lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)`。

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

普通控件：写本地圆角，等价于 `set_style` 的 `radius`（选择器 `0`）。弧标签：写沿弧排字的曲率半径（像素），不是圆角。

**调用模式**

```lua
ok = ui:set_radius(obj, r)
```

`r` 必须是 integer。弧标签创建时默认按控件较短边的一半来排字；之后若要固定半径，传像素。弧标签 `r < 0` 返回 `false, "bad radius"`。

**返回** `true`。

---

### 7.13 `ui:set_text(obj, text)` {#7-13-set-text}

改正文。目标可以是 `label`、`arclabel`、`checkbox` 旁注、`textarea` 内容、`dropdown` 按钮上的固定文案，或 `msgbox` 的标题。按钮本身不是标签。下拉框传入空串 `""` 则取消固定文案，按钮改回显示当前选中项。文本框整段替换，光标到末尾。消息框写的是标题（没有标题栏则创建）；正文请用 [`add_text`](#7-59-add-text)。

**调用模式**

```lua
ok = ui:set_text(lab, text)
```

```lua
ok = ui:set_text(cb, text)
```

```lua
ok, err = ui:set_text(obj, text)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是标签、弧标签、复选框、下拉框、文本框或消息框 | `true` |
| 都不是 | `false, "not a label"`（不抛错） |

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

**不会**给控件加上 [`STATE_PRESSED`](#46-部件与状态)。要看见主题按下动画（变暗、略放大），先 [`add_state`](#7-70-add-state)，`rt.delay` 让出画一帧，再 `click`，再 [`remove_state`](#7-71-remove-state)。

**调用模式**

```lua
ui:click(btn)
```

```lua
ui:add_state(btn, lvgl.STATE_PRESSED)
rt.delay(200)
ui:click(btn)
ui:remove_state(btn, lvgl.STATE_PRESSED)
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

把字库挂到控件的文字上。`nil`（或省略）回到默认 Montserrat 14。按钮、标签、弧标签都能设。

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

### 7.32 `ui:arclabel([parent,] [text])` {#7-32-arclabel}

建一个沿圆弧排字的标签。默认尺寸约 `dpi × dpi`（默认 130×130），曲率半径按较短边的一半。0° 在正右，90° 在正下，顺时针。中文同样要先 [`ui:font`](#7-30-font)。

**调用模式**

```lua
arc = ui:arclabel()
```

```lua
arc = ui:arclabel(text)
```

```lua
arc = ui:arclabel(parent)
```

```lua
arc = ui:arclabel(parent, text)
```

参数规则与 `label` 相同。省略 `text` 则为空串。

**返回** 控件句柄。失败抛错：`invalid parent` / `arclabel create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local arc = ui:arclabel("HELLO")
ui:set_size(arc, 180, 180)
ui:align(arc, lvgl.ALIGN_CENTER)
ui:set_dir(arc, lvgl.ARCLABEL_DIR_CLOCKWISE)
ui:set_text_align(arc, lvgl.TEXT_ALIGN_CENTER, lvgl.TEXT_ALIGN_CENTER)
ui:set_angle(arc, 0, 270)
ui:set_text_color(arc, 0xFFFFFF)
```

---

### 7.33 `ui:bar([parent,] [value])` {#7-33-bar}

建一个进度条。默认范围 `0`～`100`，方向 `BAR_DIR_AUTO`（宽大于高则水平），模式 `BAR_MODE_NORMAL`。指示条走主题色；要改外观对主部件和指示条分别 `set_style`（指示条选择器常用 `256`）。

**调用模式**

```lua
bar = ui:bar()
```

```lua
bar = ui:bar(parent)
```

```lua
bar = ui:bar(value)
```

```lua
bar = ui:bar(parent, value)
```

第 1 个额外参数若是控件句柄，当作父亲；若是 number 当作初始 `value`，父亲用当前屏幕。省略 `value` 则为 `0`。

**返回** 控件句柄。失败抛错：`invalid parent` / `bar create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local bar = ui:bar(40)
ui:set_size(bar, 200, 12)
ui:align(bar, lvgl.ALIGN_TOP_MID, 0, 80)
ui:set_range(bar, 0, 100)
ui:set_dir(bar, lvgl.BAR_DIR_HORIZONTAL)
ui:set_value(bar, 75)
```

---

### 7.34 `ui:align(obj, align [, x_ofs, y_ofs])` {#7-34-align}

把控件对齐到父亲，或对齐到另一控件。所有控件都能用，包括弧标签、进度条和弧进度。`ui:center(obj)` 等价于 `ui:align(obj, lvgl.ALIGN_CENTER)`。

**调用模式**

```lua
ok = ui:align(obj, align)
```

```lua
ok = ui:align(obj, align, x_ofs, y_ofs)
```

```lua
ok = ui:align(obj, base, align)
```

```lua
ok = ui:align(obj, base, align, x_ofs, y_ofs)
```

第 2 个额外参数若是控件句柄，当作 `base`（对齐到它）；否则第 2 参是 `align`。`align` 可以是 [4.2](#42-控件对齐-uialign) 的整数常量或小写字符串。`x_ofs` / `y_ofs` 省略为 `0`；只给 `x_ofs` 时 `y_ofs` 仍为 `0`。

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `true` |
| 对齐值非法 | `false, "bad align"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

非法句柄抛错。

---

### 7.35 `ui:set_text_align(obj, h_align [, v_align])` {#7-35-set-text-align}

改文字在控件里的对齐。直线标签和文本框只看 `h_align`（走文字样式）。弧标签：`h_align` 是沿弧方向，`v_align` 是径向（靠内/居中/靠外）；省略 `v_align` 则不改径向。

**调用模式**

```lua
ok = ui:set_text_align(lab, h_align)
```

```lua
ok = ui:set_text_align(arc, h_align, v_align)
```

`h_align` / `v_align` 可以是 [4.3](#43-文字对齐-uiset_text_align) 的整数常量或字符串。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是标签、弧标签或文本框 | `true` |
| 对齐值非法 | `false, "bad align"` |
| 不是这三种 | `false, "not a label"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.36 `ui:set_dir(obj, dir)` {#7-36-set-dir}

改方向。弧标签：顺时针 / 逆时针。进度条、开关：自动 / 水平 / 垂直。下拉框：列表往哪边展开。其它控件失败。

**调用模式**

```lua
ok = ui:set_dir(arc, lvgl.ARCLABEL_DIR_CLOCKWISE)
```

```lua
ok = ui:set_dir(arc, "ccw")
```

```lua
ok = ui:set_dir(bar, lvgl.BAR_DIR_VERTICAL)
```

```lua
ok = ui:set_dir(bar, "horizontal")
```

```lua
ok = ui:set_dir(dd, lvgl.DROPDOWN_DIR_BOTTOM)
```

```lua
ok = ui:set_dir(dd, "top")
```

```lua
ok = ui:set_dir(sw, lvgl.SWITCH_DIR_VERTICAL)
```

`dir` 可以是 [4.4](#44-方向-uiset_dir) 的整数常量或字符串。取值必须匹配当前控件种类。

**返回**

| 结果 | 返回 |
| --- | --- |
| 成功 | `true` |
| 不是弧标签、进度条、下拉框、开关 | `false, "unsupported"` |
| 取值对当前控件不合法 | `false, "bad dir"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.37 `ui:set_range(obj, min, max)` {#7-37-set-range}

进度条或弧进度的最小、最大值。若 `min > max`，绘制方向反过来。

**调用模式**

```lua
ok = ui:set_range(bar, min, max)
```

```lua
ok = ui:set_range(arc, min, max)
```

`min` / `max` 必须是 integer。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是进度条或弧进度 | `true` |
| 都不是 | `false, "not a bar"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.38 `ui:set_value(obj, value [, anim])` {#7-38-set-value}

按控件种类写当前值：

| 控件 | `value` | 说明 |
| --- | --- | --- |
| 进度条 / 弧进度 | integer | 超出范围夹到 `min`～`max`。进度条可带 `anim`；弧进度忽略 `anim` |
| 复选框 / 开关 | boolean 或 integer | `true` / 非 0 打开（勾选），`false` / `0` 关闭。integer 路径下 **`0` 就是关**，请写 `true`/`false` 或 `0`/`1` |
| 下拉框 | integer ≥ 0 | 选中项下标，从 `0` 起。超出会被夹到最后一项 |

弧进度上改当前值会按范围和模式重算指示条起止角，覆盖之前 `set_angle` 写的指示条角度。扫进度请用本接口，不要循环 `set_angle`。

**调用模式**

```lua
ok = ui:set_value(bar, value)
```

```lua
ok = ui:set_value(bar, value, anim)
```

```lua
ok = ui:set_value(arc, value)
```

```lua
ok = ui:set_value(cb, true)
```

```lua
ok = ui:set_value(sw, true)
```

```lua
ok = ui:set_value(dd, 2)
```

进度条 `anim`：boolean 为 `true` 开动画；number `~= 0` 开动画。boolean 路径下数字 `0` 为真，请写 `true`/`false`。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是进度条、弧进度、复选框、开关或下拉框 | `true` |
| 下拉框下标 `< 0` | `false, "bad value"` |
| 都不是 | `false, "not a bar"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.39 `ui:set_start_value(obj, value [, anim])` {#7-39-set-start-value}

进度条起始值，主要给 `BAR_MODE_RANGE` 用。参数与 `set_value` 相同。只对进度条有效，弧进度没有起始值。

**调用模式**

```lua
ok = ui:set_start_value(bar, value)
```

```lua
ok = ui:set_start_value(bar, value, anim)
```

**返回** 同 [7.37](#7-37-set-range)。

---

### 7.40 `ui:get_value(obj)` {#7-40-get-value}

读当前值。进度条 / 弧进度：范围内整数。复选框 / 开关：`0` 关、`1` 开。下拉框：选中项下标（从 `0` 起）。

**调用模式**

```lua
value = ui:get_value(bar)
```

```lua
value = ui:get_value(arc)
```

```lua
value = ui:get_value(cb)
```

```lua
value = ui:get_value(dd)
```

```lua
ok, err = ui:get_value(obj)
```

**返回** 成功：整数。都不是：`false, "not a bar"`。刷屏占锁超时：`false, "lvgl busy"`。

---

### 7.41 `ui:get_range(obj)` {#7-41-get-range}

读进度条或弧进度的最小、最大值。

**调用模式**

```lua
min, max = ui:get_range(bar)
```

```lua
min, max = ui:get_range(arc)
```

**返回** 成功：两个整数。都不是：`false, "not a bar"`。刷屏占锁超时：`false, "lvgl busy"`。

---

### 7.42 `ui:get_dir(obj)` {#7-42-get-dir}

读方向。弧标签返回 `ARCLABEL_DIR_*`；进度条返回 `BAR_DIR_*`；下拉框返回 `DROPDOWN_DIR_*`；开关返回 `SWITCH_DIR_*`。

**调用模式**

```lua
dir = ui:get_dir(obj)
```

**返回** 成功：整数。不是这四种：`false, "unsupported"`。刷屏占锁超时：`false, "lvgl busy"`。

---

### 7.43 `ui:set_mode(obj, mode)` {#7-43-set-mode}

进度条或弧进度的模式。取值必须匹配当前控件种类：进度条用 `BAR_MODE_*`，弧进度用 `ARC_MODE_*`。整数 `2` 两边含义不同，请用带前缀的符号。

**调用模式**

```lua
ok = ui:set_mode(bar, lvgl.BAR_MODE_NORMAL)
```

```lua
ok = ui:set_mode(bar, "range")
```

```lua
ok = ui:set_mode(bar, "symmetrical")
```

```lua
ok = ui:set_mode(arc, lvgl.ARC_MODE_REVERSE)
```

```lua
ok = ui:set_mode(arc, "reverse")
```

```lua
ok = ui:set_mode(kb, lvgl.KEYBOARD_MODE_NUMBER)
```

```lua
ok = ui:set_mode(kb, "lower")
```

```lua
ok = ui:set_mode(kb, "special")
```

`mode` 可以是 [4.5](#45-进度条模式与弧标签溢出) 的整数常量或字符串。取值必须匹配当前控件种类。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是进度条、弧进度或软键盘 | `true` |
| 模式对当前控件不合法 | `false, "bad mode"` |
| 都不是（且模式字符串对进度条合法） | `false, "not a bar"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

对称模式需要范围跨过 `0`（例如 `-50`～`50`）。

---

### 7.44 `ui:set_angle(obj, start [, extra])` {#7-44-set-angle}

单位度。0° 正右（3 点），90° 正下。本平台无浮点角度，传 integer。

- **弧标签**：`start` 加到每个字上（转圈请改 `start`）；`extra` 是可见弧长 `size`。省略 `extra` 只改起始角。创建时默认起始 `0`、弧长 `360`。`OVERFLOW_CLIP` 时超出 `size` 的字不画。
- **弧进度**：`start` / `extra` 是**指示条**起止角。省略 `extra` 只改起点。`set_value` 会按范围重算指示条角度并覆盖这里；扫进度请用 [`set_value`](#7-38-set-value)。背景轨道用 [`set_bg_angle`](#7-50-set-bg-angle)，整圈转动用 [`set_rotation`](#7-51-set-rotation)。

**调用模式**

```lua
ok = ui:set_angle(arclabel, start)
```

```lua
ok = ui:set_angle(arclabel, start, size)
```

```lua
ok = ui:set_angle(arc, start)
```

```lua
ok = ui:set_angle(arc, start, end)
```

`start` / `extra` 必须是 integer。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是弧标签或弧进度 | `true` |
| 都不是 | `false, "not an arclabel"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.45 `ui:set_offset(obj, offset)` {#7-45-set-offset}

把文字在可见弧窗口里沿弧平移，单位是弧长像素，不是 `set_pos`，也不是绕圆心转圈。只对弧标签有效。

和 `OVERFLOW_CLIP` 一起用时：偏出 `size` 的字会从弧的尽头裁掉（常见是 3 点钟位置一个个消失），**不会绕回**。`TEXT_ALIGN_TRAILING` 不吃这份偏移。要让字绕圈，请改 [`set_angle`](#7-44-set-angle) 的 `start`。

**调用模式**

```lua
ok = ui:set_offset(arc, offset)
```

`offset` 必须是 integer。

**返回** 同 [7.44](#7-44-set-angle)。

---

### 7.46 `ui:set_center_offset(obj, x [, y])` {#7-46-set-center-offset}

弧标签圆心相对控件中心的偏移，像素。省略 `y` 为 `0`。`x` / `y` 不能为负。

**调用模式**

```lua
ok = ui:set_center_offset(arc, x)
```

```lua
ok = ui:set_center_offset(arc, x, y)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是弧标签 | `true` |
| `x` 或 `y` 小于 0 | `false, "bad offset"` |
| 不是弧标签 | `false, "not an arclabel"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.47 `ui:set_recolor(obj, en)` {#7-47-set-recolor}

弧标签行内着色。打开后，正文里 `"#ff0000 red#"` 这种片段会变色。

**调用模式**

```lua
ok = ui:set_recolor(arc, true)
```

```lua
ok = ui:set_recolor(arc, false)
```

```lua
ok = ui:set_recolor(arc, 1)
```

`en`：boolean 走 Lua 布尔；number 走 `~= 0`。boolean 路径下数字 `0` 为真。

**返回** 同 [7.44](#7-44-set-angle)。

---

### 7.48 `ui:set_overflow(obj, overflow)` {#7-48-set-overflow}

弧标签文字超出弧长时怎么处理。创建时默认 `OVERFLOW_CLIP`。

**调用模式**

```lua
ok = ui:set_overflow(arc, lvgl.OVERFLOW_CLIP)
```

```lua
ok = ui:set_overflow(arc, "ellipsis")
```

```lua
ok = ui:set_overflow(arc, "visible")
```

`overflow` 可以是 [4.5](#45-进度条模式与弧标签溢出) 的整数常量或字符串。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是弧标签 | `true` |
| 取值非法 | `false, "bad overflow"` |
| 不是弧标签 | `false, "not an arclabel"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.49 `ui:arc([parent,] [value])` {#7-49-arc}

建一个弧进度（背景轨道 + 指示条）。和 [`arclabel`](#7-32-arclabel) 不是同一种控件：这里画的是弧线进度，不是沿弧排字。默认范围 `0`～`100`，模式 `ARC_MODE_NORMAL`。默认背景角约 `135`～`45`（开口朝右下的马蹄）。0° 正右，90° 正下。触摸未接入，不能用手拖；脚本改 [`set_value`](#7-38-set-value)。

指示条走主题色；弧线颜色和线宽用样式表的 `arc_color` / `arc_width`，选择器见 [4.6](#46-部件与状态)。

**调用模式**

```lua
arc = ui:arc()
```

```lua
arc = ui:arc(parent)
```

```lua
arc = ui:arc(value)
```

```lua
arc = ui:arc(parent, value)
```

第 1 个额外参数若是控件句柄，当作父亲；若是 number 当作初始 `value`，父亲用当前屏幕。省略 `value` 则保持创建时的未设定状态，直到第一次 `set_value`。

**返回** 控件句柄。失败抛错：`invalid parent` / `arc create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local arc = ui:arc(40)
ui:set_size(arc, 176, 176)
ui:align(arc, lvgl.ALIGN_CENTER)
ui:set_rotation(arc, 135)
ui:set_bg_angle(arc, 0, 270)
ui:set_range(arc, 0, 100)
ui:set_mode(arc, lvgl.ARC_MODE_NORMAL)
ui:set_value(arc, 75)
```

---

### 7.50 `ui:set_bg_angle(obj, start [, end])` {#7-50-set-bg-angle}

弧进度的背景轨道起止角，单位度。0° 正右，90° 正下。省略 `end` 只改起点。改背景角后，若已有当前值，指示条会按范围重算。

**调用模式**

```lua
ok = ui:set_bg_angle(arc, start)
```

```lua
ok = ui:set_bg_angle(arc, start, end)
```

`start` / `end` 必须是 integer。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是弧进度 | `true` |
| 不是弧进度 | `false, "not an arc"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.51 `ui:set_rotation(obj, deg)` {#7-51-set-rotation}

把整条弧进度绕圆心转，单位度。背景角和指示条都跟着转。传入值会归到 `[0, 360)`。只对弧进度有效。

**调用模式**

```lua
ok = ui:set_rotation(arc, deg)
```

`deg` 必须是 integer。

**返回** 同 [7.50](#7-50-set-bg-angle)。

---

### 7.52 `ui:checkbox([parent,] [text])` {#7-52-checkbox}

建一个复选框。旁注走 [`set_text`](#7-13-set-text)；勾选走 [`set_value`](#7-38-set-value)（`true`/`false` 或 `0`/`1`）。创建时未勾选。默认旁注可能是固件里的 `"Check box"`，请自己 `set_text`。中文旁注要先 [`ui:font`](#7-30-font)。

没有触摸时，`ui:click` **不会**拨动勾选状态，只投递已登记的 `on_click`；脚本请用 `set_value`。

**调用模式**

```lua
cb = ui:checkbox()
```

```lua
cb = ui:checkbox(text)
```

```lua
cb = ui:checkbox(parent)
```

```lua
cb = ui:checkbox(parent, text)
```

参数规则与 `label` 相同。省略 `text` 则保留创建时的默认旁注。

**返回** 控件句柄。失败抛错：`invalid parent` / `checkbox create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local cb = ui:checkbox("LED")
ui:align(cb, lvgl.ALIGN_CENTER)
ui:set_value(cb, true)
local on = ui:get_value(cb)   -- 1
```

---

### 7.53 `ui:dropdown([parent,] [options])` {#7-53-dropdown}

建一个下拉框。选项是 `\n` 分隔的字符串，或字符串数组表。省略 `options` 时固件带三条默认项。当前选中项用 [`set_value`](#7-38-set-value)（下标从 `0` 起）。列表展开方向用 [`set_dir`](#7-36-set-dir) 的 `DROPDOWN_DIR_*`。

没有触摸时用 [`open`](#7-55-open) / [`close`](#7-56-close) 展开、收起；`ui:click` 同样不会去点开列表。

**调用模式**

```lua
dd = ui:dropdown()
```

```lua
dd = ui:dropdown(parent)
```

```lua
dd = ui:dropdown(options)
```

```lua
dd = ui:dropdown(parent, options)
```

`options`：string（`"Red\nGreen\nBlue"`）或 array table（`{ "Red", "Green", "Blue" }`）。非法类型：`false, "bad options"`。

**返回** 控件句柄。失败抛错：`invalid parent` / `dropdown create failed`。刷屏占锁超时：`false, "lvgl busy"`。选项非法：`false, "bad options"`。

```lua
local dd = ui:dropdown({ "Red", "Green", "Blue" })
ui:set_size(dd, 160, 36)
ui:align(dd, lvgl.ALIGN_TOP_MID, 0, 72)
ui:set_dir(dd, lvgl.DROPDOWN_DIR_BOTTOM)
ui:set_value(dd, 1)
```

---

### 7.54 `ui:set_options(obj, options)` {#7-54-set-options}

替换下拉框全部选项。空串或空表会清空列表。只对下拉框有效。

**调用模式**

```lua
ok = ui:set_options(dd, "A\nB\nC")
```

```lua
ok = ui:set_options(dd, { "A", "B", "C" })
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是下拉框 | `true` |
| 选项不是 string / array table | `false, "bad options"` |
| 不是下拉框 | `false, "not a dropdown"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.55 `ui:open(obj)` {#7-55-open}

展开下拉列表。只对下拉框有效。没有触摸时用它代替点按。

**调用模式**

```lua
ok = ui:open(dd)
```

**返回** 同 [7.54](#7-54-set-options) 的「不是下拉框 / 锁超时」两行（无 `bad options`）。

---

### 7.56 `ui:close(obj)` {#7-56-close}

两用：

- 下拉框：收起列表，控件还在。
- 消息框：拆掉整框。省略父亲创建的模态框会连顶层遮罩一起删。之后该句柄以及脚注/关闭按钮句柄都失效，再调用抛 `invalid lvgl object`。框上登记过的 [`on_click`](#7-24-on-click) 槽会一并释放。

**调用模式**

```lua
ok = ui:close(dd)
```

```lua
ok = ui:close(mbox)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是下拉框或消息框 | `true` |
| 都不是 | `false, "not a dropdown"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.57 `ui:textarea([parent,] [text])` {#7-57-textarea}

建一个文本框。没有触摸输入时，用 [`set_text`](#7-13-set-text) / [`add_text`](#7-59-add-text) 改内容，用 [`get_text`](#7-58-get-text) 读明文。要弹出软键盘，把本控件交给 [`ui:keyboard`](#7-67-keyboard) / [`set_textarea`](#7-68-set-textarea)。占位符、密码模式、单行见后面几条。默认多行；默认字体是 ASCII。

**调用模式**

```lua
ta = ui:textarea()
```

```lua
ta = ui:textarea(parent)
```

```lua
ta = ui:textarea(text)
```

```lua
ta = ui:textarea(parent, text)
```

参数规则与 `label` 相同。省略 `text` 则内容为空。

**返回** 控件句柄。失败抛错：`invalid parent` / `textarea create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local ta = ui:textarea()
ui:set_one_line(ta, true)
ui:set_size(ta, 200, 36)
ui:align(ta, lvgl.ALIGN_TOP_MID, 0, 64)
ui:set_placeholder(ta, "name")
ui:add_text(ta, "A")
local s = ui:get_text(ta)   -- "A"
```

先 `set_one_line` 再 `set_size`：打开单行会改高度。

---

### 7.58 `ui:get_text(obj)` {#7-58-get-text}

读当前文字。标签 / 复选框旁注 / 文本框返回正文。文本框在密码模式下仍返回明文，不是圆点。下拉框返回当前选中项字符串（最长约 127 字节，超长截断）。消息框返回标题；还没加标题则空串。弧标签没有这条。

**调用模式**

```lua
text = ui:get_text(obj)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是标签、复选框、文本框、下拉框或消息框 | string |
| 都不是 | `false, "not a label"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.59 `ui:add_text(obj, text)` {#7-59-add-text}

两用：

- 文本框：在光标处追加。没有触摸、或不想点软键盘时用它模拟逐字输入。
- 消息框：在内容区新起一段正文。可连调多次，每次一段；不能拿它改标题。

**调用模式**

```lua
ok = ui:add_text(ta, "A")
```

```lua
ok = ui:add_text(mbox, "Overwrite file?")
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是文本框或消息框 | `true` |
| 都不是 | `false, "not a textarea"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

`text` 不是 string/number 时抛错。

---

### 7.60 `ui:set_placeholder(obj, text)` {#7-60-set-placeholder}

空内容时显示的占位符。只对文本框有效。

**调用模式**

```lua
ok = ui:set_placeholder(ta, "name")
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是文本框 | `true` |
| 不是文本框 | `false, "not a textarea"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

`text` 不是 string/number 时抛错。

---

### 7.61 `ui:set_password(obj, en)` {#7-61-set-password}

密码模式：屏上显示圆点，[`get_text`](#7-58-get-text) 仍是明文。只对文本框有效。

**调用模式**

```lua
ok = ui:set_password(ta, true)
```

`en`：boolean 或 integer。integer 路径下 **`0` 就是关闭**，请写 `true`/`false` 或 `0`/`1`。

**返回** 同 [7.60](#7-60-set-placeholder)。缺参抛错。

---

### 7.62 `ui:set_one_line(obj, en)` {#7-62-set-one-line}

单行 / 多行。打开单行后高度会变，需要的话再 [`set_size`](#7-19-set-size)。只对文本框有效。

**调用模式**

```lua
ok = ui:set_one_line(ta, true)
```

`en` 语义同 [7.61](#7-61-set-password)。

**返回** 同 [7.60](#7-60-set-placeholder)。缺参抛错。

---

### 7.63 `ui:switch([parent])` {#7-63-switch}

建一个开关。开合走 [`set_value`](#7-38-set-value)（`true`/`false` 或 `0`/`1`），[`get_value`](#7-40-get-value) 读 `0`/`1`。方向走 [`set_dir`](#7-36-set-dir) 的 `SWITCH_DIR_*`。创建时关闭、水平（宽大于高则自动水平）。

没有触摸时用 `set_value`，不要指望 `ui:click` 去拨状态。外观用 [`set_style`](#7-10-set-style) 分别改轨道、打开填充、滑块，选择器见 [4.6](#46-部件与状态)。

**调用模式**

```lua
sw = ui:switch()
```

```lua
sw = ui:switch(parent)
```

**返回** 控件句柄。失败抛错：`invalid parent` / `switch create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local sw = ui:switch()
ui:set_size(sw, 56, 28)
ui:align(sw, lvgl.ALIGN_TOP_RIGHT, -16, 52)
ui:set_style(sw, { bg = 0x3A3A48, radius = 99, pad = 3 }, lvgl.PART_MAIN)
ui:set_style(sw, { bg = 0x34C759, radius = 99 },
             lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)
ui:set_style(sw, { bg = 0xF5F5F7, radius = 99 }, lvgl.PART_KNOB)
ui:set_value(sw, true)
```

---

### 7.64 `ui:spinner([parent,] [t [, angle]])` {#7-64-spinner}

建一个转圈（无限旋转的弧）。动画在图形任务里跑，脚本只要 `rt.delay` 让出，不要循环 `ui:handler()`，也不要用 [`set_value`](#7-38-set-value) / [`set_angle`](#7-44-set-angle) 去拨它。周期和弧长用 [`set_anim`](#7-65-set-anim)。创建时默认周期 `1000` ms、弧长 `200`°。

外观用 [`set_style`](#7-10-set-style) 的 `arc_color` / `arc_width`：轨道 `PART_MAIN`，转动段 `PART_INDICATOR`。和 [`arc`](#7-49-arc) 不是同一种控件。

**调用模式**

```lua
sp = ui:spinner()
```

```lua
sp = ui:spinner(parent)
```

```lua
sp = ui:spinner(t)
```

```lua
sp = ui:spinner(parent, t)
```

```lua
sp = ui:spinner(t, angle)
```

```lua
sp = ui:spinner(parent, t, angle)
```

第 1 个额外参数若是控件句柄，当作父亲；若是 number 当作周期 `t`（毫秒）。`angle` 是转动段弧长，单位度，合法 `1`～`360`，推荐 `180`～`360`。`t < 1`：`false, "bad anim"`。`angle` 非法：`false, "bad angle"`。

**返回** 控件句柄。失败抛错：`invalid parent` / `spinner create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local sp = ui:spinner(800, 240)
ui:set_size(sp, 72, 72)
ui:align(sp, lvgl.ALIGN_CENTER)
ui:set_style(sp, { arc_color = 0x2A2A38, arc_width = 8 }, lvgl.PART_MAIN)
ui:set_style(sp, { arc_color = 0x34C759, arc_width = 8 }, lvgl.PART_INDICATOR)
```

---

### 7.65 `ui:set_anim(obj, t [, angle])` {#7-65-set-anim}

改转圈的周期和弧长。只对转圈有效。省略 `angle` 只改周期，弧长保持原值。

**调用模式**

```lua
ok = ui:set_anim(sp, t)
```

```lua
ok = ui:set_anim(sp, t, angle)
```

`t` / `angle` 必须是 integer。`t >= 1`（毫秒）。`angle` 若写了须在 `1`～`360`。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是转圈 | `true` |
| `t < 1` | `false, "bad anim"` |
| `angle` 非法 | `false, "bad angle"` |
| 不是转圈 | `false, "not a spinner"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

---

### 7.66 `ui:get_anim(obj)` {#7-66-get-anim}

读转圈当前周期（毫秒）和弧长（度）。

**调用模式**

```lua
t, angle = ui:get_anim(sp)
```

**返回** 成功：两个整数。不是转圈：`false, "not a spinner"`。刷屏占锁超时：`false, "lvgl busy"`。

---

### 7.67 `ui:keyboard([parent,] [textarea])` {#7-67-keyboard}

建一个软键盘。创建时默认贴父对象底边，宽 `100%`、高 `50%`，布局是小写字母。把文本框绑上之后，按键会往该框里插字；没有触摸输入时按键点不了，用 [`set_mode`](#7-43-set-mode) 看四种布局，用 [`add_text`](#7-59-add-text) 改已绑定的文本框。

第 1 个额外参数若是控件句柄，当作父亲；第 2 个若也是控件句柄，当作要绑定的文本框。只传一个文本框句柄会被当成父亲（键盘会嵌进文本框里），请写成 `ui:keyboard(parent, ta)` 或创建后再 [`set_textarea`](#7-68-set-textarea)。

**调用模式**

```lua
kb = ui:keyboard()
```

```lua
kb = ui:keyboard(parent)
```

```lua
kb = ui:keyboard(parent, ta)
```

**返回** 控件句柄。失败抛错：`invalid parent` / `keyboard create failed`。刷屏占锁超时：`false, "lvgl busy"`。第 2 参不是文本框：`false, "not a textarea"`。

```lua
local ta = ui:textarea()
ui:set_one_line(ta, true)
ui:set_size(ta, 216, 32)
ui:align(ta, lvgl.ALIGN_TOP_MID, 0, 48)
ui:set_placeholder(ta, "name")

local kb = ui:keyboard()
ui:set_textarea(kb, ta)
ui:set_mode(kb, lvgl.KEYBOARD_MODE_TEXT_LOWER)
ui:set_popovers(kb, true)
```

创建时绑文本框要显式带父亲，不要只传文本框句柄（那会被当成父亲，键盘会嵌进去）：

```lua
local kb = ui:keyboard(ui:scr_act(), ta)
```

---

### 7.68 `ui:set_textarea(obj, textarea)` {#7-68-set-textarea}

把软键盘绑到一个文本框。之后按键写入该框。`textarea` 省略或 `nil` 则解开。只对软键盘有效。

**调用模式**

```lua
ok = ui:set_textarea(kb, ta)
```

```lua
ok = ui:set_textarea(kb)
```

```lua
ok = ui:set_textarea(kb, nil)
```

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是软键盘，且第 2 参是文本框 / 省略 / `nil` | `true` |
| 第 1 参不是软键盘 | `false, "not a keyboard"` |
| 第 2 参不是文本框 | `false, "not a textarea"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

第 2 参若写了但不是控件句柄，抛错 `invalid lvgl object`。

---

### 7.69 `ui:set_popovers(obj, en)` {#7-69-set-popovers}

按住键时是否弹出键帽标题。只对软键盘有效。没有触摸时看不见效果。

**调用模式**

```lua
ok = ui:set_popovers(kb, true)
```

`en`：boolean 或 integer。integer 路径下 **`0` 就是关闭**，请写 `true`/`false` 或 `0`/`1`。

**返回**

| 结果 | 返回 |
| --- | --- |
| 目标是软键盘 | `true` |
| 不是软键盘 | `false, "not a keyboard"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

缺参抛错。

---

### 7.70 `ui:add_state(obj, state)` {#7-70-add-state}

给控件加上状态位。按钮按下请加 [`STATE_PRESSED`](#46-部件与状态)，主题会走按下样式（变暗、略放大）。改完必须 `rt.delay` 让出，独立任务才会把这一帧画出来。

**调用模式**

```lua
ok = ui:add_state(btn, lvgl.STATE_PRESSED)
```

`state` 必须是正整数，常用 `STATE_PRESSED` / `STATE_CHECKED`，也可以按位或。`0`（`STATE_DEFAULT`）非法。

**返回**

| 结果 | 返回 |
| --- | --- |
| 已加上 | `true` |
| `state` 不是 `1`～`65535` | `false, "bad state"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

缺参抛错。

---

### 7.71 `ui:remove_state(obj, state)` {#7-71-remove-state}

清掉控件上的状态位。模拟松手时清 `STATE_PRESSED`。

**调用模式**

```lua
ok = ui:remove_state(btn, lvgl.STATE_PRESSED)
```

`state` 规则同 [7.70](#7-70-add-state)。

**返回** 同 [7.70](#7-70-add-state)。

---

### 7.72 `ui:msgbox([parent,] [title [, text]])` {#7-72-msgbox}

建一个消息框。省略 `parent`（或第一个额外参数不是控件句柄）时是 **模态**：挂到顶层，带半透明遮罩，点不透后面的界面。传入父亲则作为普通子控件，不建遮罩。

创建时可带标题和第一段正文；以后标题用 [`set_text`](#7-13-set-text)，正文用 [`add_text`](#7-59-add-text)。脚注按钮、右上角关闭钮要另调。关掉框用 [`ui:close`](#7-56-close)。默认字体是 ASCII。

宽度默认约 `2 ×` 固件 DPI（130 时约 260）。屏比这窄时会夹到屏宽减 24，避免 240 宽屏溢出。高度随内容。

**调用模式**

```lua
mbox = ui:msgbox()
```

```lua
mbox = ui:msgbox(title)
```

```lua
mbox = ui:msgbox(title, text)
```

```lua
mbox = ui:msgbox(parent)
```

```lua
mbox = ui:msgbox(parent, title)
```

```lua
mbox = ui:msgbox(parent, title, text)
```

第 1 个额外参数若是控件句柄，当作父亲；若是 string（或 number，会转成字面）当作 `title`，此时为模态。省略 `title` / `text` 则先空着，之后再 `set_text` / `add_text`。

**返回** 控件句柄。失败抛错：`msgbox create failed`。刷屏占锁超时：`false, "lvgl busy"`。

```lua
local mbox = ui:msgbox("Save?", "Overwrite file?")
local no = ui:add_footer_btn(mbox, "No")
local yes = ui:add_footer_btn(mbox, "Yes")
ui:add_close_btn(mbox)
ui:on_click(yes, function()
    ui:close(mbox)
end)
```

没有触摸时不要指望点到脚注按钮；用 [`add_state`](#7-70-add-state) 看按下，再 [`ui:click`](#7-25-click)，在回调里 `close`。可烧录工程：[lvgl_msgbox](../../../examples/nt26/module/lvgl/lvgl_msgbox)。

---

### 7.73 `ui:add_footer_btn(obj, text)` {#7-73-add-footer-btn}

在消息框底部加一颗按钮，返回该按钮句柄，可 [`on_click`](#7-24-on-click)。只对消息框有效。按钮自己不会关框，要在回调里 [`close`](#7-56-close)。

**调用模式**

```lua
btn = ui:add_footer_btn(mbox, "OK")
```

**返回** 按钮句柄。失败：

| 结果 | 返回 |
| --- | --- |
| 目标不是消息框 | `false, "not a msgbox"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

建不出按钮时抛错 `footer btn failed`。`text` 不是 string/number 时抛错。

---

### 7.74 `ui:add_close_btn(obj)` {#7-74-add-close-btn}

在消息框标题栏右侧加关闭钮（X）。只对消息框有效。

有真实点击事件时，底层会自己拆框。[`ui:click`](#7-25-click) **不会**走到那条底层点击，所以没有触摸时请在 [`on_click`](#7-24-on-click) 里 [`close`](#7-56-close)，或脚本直接 `ui:close(mbox)`。

**调用模式**

```lua
x = ui:add_close_btn(mbox)
```

**返回** 按钮句柄。失败：

| 结果 | 返回 |
| --- | --- |
| 目标不是消息框 | `false, "not a msgbox"` |
| 刷屏占锁超时 | `false, "lvgl busy"` |

建不出按钮时抛错 `close btn failed`。缺参抛错。

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
| `arc_color` | integer | 弧线色（弧进度 / 转圈） | |
| `arc_width` | integer | 弧线宽，像素；负数当 `0` | |
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
| `label` / `arclabel` / `btn` / `obj` / `bar` / `arc` / `checkbox` / `dropdown` / `textarea` / `keyboard` / `switch` / `spinner` / `img` / `msgbox` / `font` | 句柄 | 刷屏占锁超时：`false, "lvgl busy"`；`img(src)` / `font(src)` 解码失败：**抛错**（不建对象）；`dropdown(options)` 非法：`false, "bad options"`；`spinner` 的 `t`/`angle` 非法：`false, "bad anim"` / `"bad angle"`；`keyboard` 第 2 参不是文本框：`false, "not a textarea"`；其余 **抛错** |
| `set_src` | `true` | 非图片：`false, "not an image"`；源失败：`false, 文案`（原图还在）；锁超时：`false, "lvgl busy"` |
| `set_font` | `true` | 锁超时：`false, "lvgl busy"`；非法字库句柄：**抛错** `invalid lvgl font` |
| `set_scale` | `true` | 非图片：`false, "not an image"`；`scale < 0`：`false, "bad scale"`；锁超时：`false, "lvgl busy"` |
| `get_scale` | 整数 | 非图片：`false, "not an image"`；锁超时：`false, "lvgl busy"` |
| `scr_act` | 句柄或 `nil` | 未 create 抛错 |
| `on_click` / `click` | `true` | `click` 队列满：`false, "click post failed"`；其余 **抛错** |
| `set_text` / `set_text_align` | `true` | 非标签/弧标签/复选框/下拉框/文本框/消息框（`set_text`）或非标签/弧标签/文本框（`set_text_align`）：`false, "not a label"`；对齐非法：`false, "bad align"`；刷屏占锁超时：`false, "lvgl busy"`；缺参抛错 |
| `get_text` | string | 非标签/复选框/文本框/下拉框/消息框：`false, "not a label"`；锁超时：`false, "lvgl busy"` |
| `align` | `true` | 对齐非法：`false, "bad align"`；锁超时：`false, "lvgl busy"` |
| `set_dir` / `get_dir` | `true` / 整数 | 非弧标签、进度条、下拉框、开关：`false, "unsupported"`；方向非法：`false, "bad dir"`；锁超时：`false, "lvgl busy"` |
| `set_range` / `set_mode` | `true` | 非进度条且非弧进度且非软键盘：`false, "not a bar"`；模式对当前控件不合法：`false, "bad mode"`；锁超时：`false, "lvgl busy"` |
| `set_value` | `true` | 非进度条/弧进度/复选框/开关/下拉框：`false, "not a bar"`；下拉框下标 `< 0`：`false, "bad value"`；锁超时：`false, "lvgl busy"` |
| `set_start_value` | `true` | 非进度条：`false, "not a bar"`；锁超时：`false, "lvgl busy"` |
| `get_value` | 整数 | 非进度条/弧进度/复选框/开关/下拉框：`false, "not a bar"`；锁超时：`false, "lvgl busy"` |
| `get_range` | 两整数 | 非进度条且非弧进度：`false, "not a bar"`；锁超时：`false, "lvgl busy"` |
| `set_angle` / `set_offset` / `set_center_offset` / `set_recolor` / `set_overflow` | `true` | `set_angle` 非弧标签且非弧进度，其余非弧标签：`false, "not an arclabel"`；溢出非法：`false, "bad overflow"`；圆心偏移为负：`false, "bad offset"`；锁超时：`false, "lvgl busy"` |
| `set_bg_angle` / `set_rotation` | `true` | 非弧进度：`false, "not an arc"`；锁超时：`false, "lvgl busy"` |
| `set_options` / `open` / `close` | `true` | 非下拉框（`set_options` / `open`）；非下拉框且非消息框（`close`）：`false, "not a dropdown"`；选项非法：`false, "bad options"`；锁超时：`false, "lvgl busy"` |
| `add_text` / `set_placeholder` / `set_password` / `set_one_line` | `true` | 非文本框（后三条）；非文本框且非消息框（`add_text`）：`false, "not a textarea"`；锁超时：`false, "lvgl busy"` |
| `set_anim` | `true` | 非转圈：`false, "not a spinner"`；`t < 1`：`false, "bad anim"`；弧长非法：`false, "bad angle"`；锁超时：`false, "lvgl busy"` |
| `get_anim` | 两整数 | 非转圈：`false, "not a spinner"`；锁超时：`false, "lvgl busy"` |
| `set_textarea` | `true` | 非软键盘：`false, "not a keyboard"`；第 2 参不是文本框：`false, "not a textarea"`；锁超时：`false, "lvgl busy"` |
| `set_popovers` | `true` | 非软键盘：`false, "not a keyboard"`；锁超时：`false, "lvgl busy"` |
| `add_state` / `remove_state` | `true` | `state` 非法：`false, "bad state"`；锁超时：`false, "lvgl busy"` |
| `add_footer_btn` / `add_close_btn` | 按钮句柄 | 非消息框：`false, "not a msgbox"`；锁超时：`false, "lvgl busy"`；建不出按钮：**抛错** |
| `set_radius` | `true` | 弧标签 `r < 0`：`false, "bad radius"`；锁超时：`false, "lvgl busy"` |
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
| `label create failed` / `arclabel create failed` / `btn create failed` / `obj create failed` / `bar create failed` / `arc create failed` / `checkbox create failed` / `dropdown create failed` / `textarea create failed` / `keyboard create failed` / `switch create failed` / `spinner create failed` / `img create failed` / `msgbox create failed` / `footer btn failed` / `close btn failed` | 控件堆不够，看 `ui:mem()`，加大 `mem_max` 或少建控件 |
| `unsupported image format` | `ui:img(src)` 文件头不是 JPEG / LVGL `.bin` |
| `bad src` / `not found` / `fs not mounted` / `decode failed` / `no mem` | `ui:img(src)` / `ui:font(src)` 源无效、找不到、解不开或缓冲不够；`set_src` 同一批文案走返回值 |
| `rt vm context missing` | 脚本还没进 rt 调度（极少见） |
| `lvgl callback full` | 同时挂了超过 32 个点击；先 `on_click(obj, nil)` 或 `deinit` |
| `lvgl event hook failed` | 控件堆不够，钩不上事件 |

**返回值失败**

| 摘要 | 可能原因 |
| --- | --- |
| `false, "not a label"` | `set_text` 的目标不是标签 / 弧标签 / 复选框 / 下拉框 / 文本框 / 消息框；`get_text` 的目标不是标签 / 复选框 / 文本框 / 下拉框 / 消息框；`set_text_align` 的目标不是 `ui:label` / `ui:arclabel` / `ui:textarea` |
| `false, "not an arclabel"` | `set_angle` 打在既非弧标签也非弧进度上；`set_offset` / `set_center_offset` / `set_recolor` / `set_overflow` 打在非弧标签上 |
| `false, "not a bar"` | `set_range` / `set_mode` / `get_range` 打在既非进度条也非弧进度也非软键盘（仅 `set_mode`）上；`set_value` / `get_value` 打在进度条、弧进度、复选框、开关、下拉框之外；`set_start_value` 打在非进度条上 |
| `false, "not an arc"` | `set_bg_angle` / `set_rotation` 打在非弧进度上 |
| `false, "not a dropdown"` | `set_options` / `open` 打在非下拉框上；`close` 打在既非下拉框也非消息框上 |
| `false, "not a textarea"` | `add_text` 打在既非文本框也非消息框上；`set_placeholder` / `set_password` / `set_one_line` 打在非文本框上；`keyboard` / `set_textarea` 的绑定目标不是文本框 |
| `false, "not a msgbox"` | `add_footer_btn` / `add_close_btn` 打在非消息框上 |
| `false, "not a keyboard"` | `set_textarea` / `set_popovers` 打在非软键盘上 |
| `false, "not a spinner"` | `set_anim` / `get_anim` 打在非转圈上 |
| `false, "bad anim"` | 转圈周期 `t < 1` |
| `false, "unsupported"` | `set_dir` / `get_dir` 的目标不是弧标签、进度条、下拉框或开关 |
| `false, "bad align"` | `align` / `set_text_align` 的对齐值不在导出枚举 / 字符串表里 |
| `false, "bad dir"` | `set_dir` 的取值对当前控件不合法（例如把 `"vertical"` 传给弧标签，或把 `"cw"` 传给下拉框） |
| `false, "bad value"` | 下拉框 `set_value` 的下标小于 0 |
| `false, "bad options"` | `dropdown` / `set_options` 的选项既不是 string 也不是数组表 |
| `false, "bad mode"` | `set_mode` 的取值对当前控件不合法（进度条：`normal` / `symmetrical` / `range`；弧进度：`normal` / `symmetrical` / `reverse`；软键盘：`lower` / `upper` / `special` / `number`） |
| `false, "bad overflow"` | `set_overflow` 不是 `visible` / `ellipsis` / `clip` 或其整数 |
| `false, "bad radius"` | 弧标签 `set_radius` 传了负数 |
| `false, "bad state"` | `add_state` / `remove_state` 的 `state` 不是 `1`～`65535` |
| `false, "bad angle"` | 转圈弧长不在 `1`～`360` |
| `false, "bad offset"` | `set_center_offset` 的 x 或 y 小于 0 |
| `false, "not an image"` | `set_src` / `set_scale` / `get_scale` 打在非 `ui:img` 的句柄上 |
| `false, "bad scale"` | `set_scale` 的因子小于 0 |
| `false, "click post failed"` | 内部事件队列满，稍后重试 |
| `false, "lvgl busy"` | 图形任务正在画/持锁，Lua 等锁超过约 200ms。可稍后重试；不要当致命错误 |
| `false, "bad src"` 等 | `set_src` 源失败，文案同 [7.27](#7-27-set-src) 表；原图还在 |

诊断：create 抛错看 `mem_max` 和是否已 create；`bound to lvgl` 出现在 **lcd** 侧；`not a label` 对按钮要用内部 label 或改 `set_style` 文字色而不是 `set_text(btn)`。弧标签/进度条/弧进度/下拉框/文本框/软键盘/消息框用错控件会看到 `not an arclabel` / `not a bar` / `not an arc` / `not a dropdown` / `not a textarea` / `not a keyboard` / `not a msgbox`。开关方向不合法是 `unsupported` / `bad dir`。图片失败先看文件头和 `ui:mem()`。

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

控件句柄只是包装：GC 句柄不删树。整棵树在 `deinit` 时一起拆。例外：[`ui:close`](#7-56-close) 打在消息框上会立刻拆掉该框（模态连遮罩）；之后句柄失效。字库要自己持有到不再给任何控件用为止。

VM 退出会回收还活着的 `ui`。

---

## 15. 选型对照

| 需求 | 用 |
| --- | --- |
| 先确认 SPI 和屏能出纯色 | [`lcd`](lcd.md) 的 `full` / `fill`，**尚未** `lvgl.create` |
| 标签、弧标签、按钮、进度条、弧进度、复选框、下拉框、文本框、软键盘、开关、转圈、消息框、顶栏、主题 | 本模块 |
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
| [lvgl_btn](../../../examples/nt26/module/lvgl/lvgl_btn) | 按钮：`on_click`；没有触摸时 `add_state(PRESSED)` 看按下动画，再 `ui:click` |
| [lvgl_arclabel](../../../examples/nt26/module/lvgl/lvgl_arclabel) | 弧标签：整圈居中，用 `set_angle` 起始角绕圈，再切换顺/逆时针 |
| [lvgl_bar](../../../examples/nt26/module/lvgl/lvgl_bar) | 进度条：水平/垂直、范围、当前值、RANGE 起始值 |
| [lvgl_arc](../../../examples/nt26/module/lvgl/lvgl_arc) | 弧进度：270° 表盘、`set_value` 扫进度，切换 NORMAL / REVERSE / SYMMETRICAL |
| [lvgl_checkbox](../../../examples/nt26/module/lvgl/lvgl_checkbox) | 复选框：旁注、`set_value` 勾选 |
| [lvgl_dropdown](../../../examples/nt26/module/lvgl/lvgl_dropdown) | 下拉框：选项表、当前项、`open`/`close` |
| [lvgl_textarea](../../../examples/nt26/module/lvgl/lvgl_textarea) | 文本框：占位符、单行、`add_text` 逐字、密码模式 |
| [lvgl_keyboard](../../../examples/nt26/module/lvgl/lvgl_keyboard) | 软键盘：绑文本框，模拟打 `HELLO` 再逐字删掉 |
| [lvgl_switch](../../../examples/nt26/module/lvgl/lvgl_switch) | 开关：主题默认、绿/红/大号、垂直；`set_style` 改轨道和滑块 |
| [lvgl_spinner](../../../examples/nt26/module/lvgl/lvgl_spinner) | 转圈：不同周期、弧长、`arc_color` / `arc_width` |
| [lvgl_msgbox](../../../examples/nt26/module/lvgl/lvgl_msgbox) | 消息框：模态标题/正文、脚注 No/Yes、关闭钮；没有触摸时 `add_state(PRESSED)` 再 `ui:click`，回调里 `close` |
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
ui:set_text_align(hint, lvgl.TEXT_ALIGN_LEFT)

-- 弧标签：沿圆弧排字。set_radius 在弧标签上是曲率半径。
-- local arc = ui:arclabel("HELLO")
-- ui:set_size(arc, 160, 160)
-- ui:align(arc, lvgl.ALIGN_CENTER, 0, 20)
-- ui:set_dir(arc, lvgl.ARCLABEL_DIR_CLOCKWISE)
-- ui:set_text_align(arc, "center", "center")
-- ui:set_angle(arc, 0, 270)

-- 进度条：范围、方向、当前值。
-- local bar = ui:bar(40)
-- ui:set_size(bar, 200, 12)
-- ui:align(bar, lvgl.ALIGN_TOP_MID, 0, 48)
-- ui:set_range(bar, 0, 100)
-- ui:set_dir(bar, lvgl.BAR_DIR_HORIZONTAL)
-- ui:set_value(bar, 75)

-- 弧进度：背景弧 + 当前值。扫进度用 set_value，不要循环 set_angle。
-- local gauge = ui:arc(40)
-- ui:set_size(gauge, 176, 176)
-- ui:align(gauge, lvgl.ALIGN_CENTER)
-- ui:set_rotation(gauge, 135)
-- ui:set_bg_angle(gauge, 0, 270)
-- ui:set_range(gauge, 0, 100)
-- ui:set_mode(gauge, lvgl.ARC_MODE_NORMAL)
-- ui:set_value(gauge, 75)

-- 复选框：旁注 + 勾选。没有触摸时用 set_value，不要指望 ui:click 拨状态。
-- local cb = ui:checkbox("LED")
-- ui:align(cb, lvgl.ALIGN_CENTER, 0, -20)
-- ui:set_value(cb, true)

-- 下拉框：选项表，下标从 0。展开用 open/close。
-- local dd = ui:dropdown({ "Red", "Green", "Blue" })
-- ui:set_size(dd, 160, 36)
-- ui:align(dd, lvgl.ALIGN_TOP_MID, 0, 80)
-- ui:set_dir(dd, lvgl.DROPDOWN_DIR_BOTTOM)
-- ui:set_value(dd, 1)

-- 文本框：没有触摸时用 add_text / set_text。密码模式 get_text 仍是明文。
-- local ta = ui:textarea()
-- ui:set_one_line(ta, true)
-- ui:set_size(ta, 200, 36)
-- ui:align(ta, lvgl.ALIGN_TOP_MID, 0, 48)
-- ui:set_placeholder(ta, "name")
-- ui:add_text(ta, "A")

-- 软键盘：默认贴底。没有触摸时用 set_mode 看布局。
-- local kb = ui:keyboard()
-- ui:set_textarea(kb, ta)
-- ui:set_mode(kb, lvgl.KEYBOARD_MODE_TEXT_LOWER)
-- ui:set_popovers(kb, true)

-- 开关：set_value 开合。外观用 PART_MAIN / INDICATOR / KNOB。
-- local sw = ui:switch()
-- ui:set_size(sw, 56, 28)
-- ui:set_style(sw, { bg = 0x34C759, radius = 99 },
--              lvgl.PART_INDICATOR | lvgl.STATE_CHECKED)
-- ui:set_value(sw, true)

-- 转圈：动画自己跑。改周期/弧长用 set_anim，不要 set_value。
-- local sp = ui:spinner(800, 240)
-- ui:set_size(sp, 72, 72)
-- ui:set_style(sp, { arc_color = 0x34C759, arc_width = 8 }, lvgl.PART_INDICATOR)

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
| 1.6.2 | 2026-09-15 | 标明 SSD1306 先走 `lcd` 1 bit 画布，暂不要 `lvgl.create` |
| 1.7.0 | 2026-09-18 | 增加弧标签 `ui:arclabel` 与进度条 `ui:bar`；`set_text` / `set_radius` / 文字对齐适配弧标签；新增 `align`、`set_dir`、`set_range`、`set_value` 及弧标签角度/溢出接口；导出对齐与方向常量 |
| 1.7.1 | 2026-09-18 | 可烧录工程增加 [lvgl_arclabel](../../../examples/nt26/module/lvgl/lvgl_arclabel)、[lvgl_bar](../../../examples/nt26/module/lvgl/lvgl_bar) |
| 1.7.2 | 2026-09-18 | 弧标签转圈改走 `set_angle` 起始角；标明 `set_offset` 是弧长平移，CLIP 下不会绕回 |
| 1.8.0 | 2026-09-18 | 增加弧进度 `ui:arc`；`set_range` / `set_value` / `get_value` / `get_range` / `set_mode` / `set_angle` 适配弧进度；新增 `set_bg_angle` / `set_rotation` 与 `ARC_MODE_*`；可烧录工程 [lvgl_arc](../../../examples/nt26/module/lvgl/lvgl_arc) |
| 1.9.0 | 2026-09-18 | 增加复选框 `ui:checkbox`、下拉框 `ui:dropdown`；`set_text` / `set_value` / `get_value` / `set_dir` 适配；新增 `set_options` / `open` / `close` 与 `DROPDOWN_DIR_*`；可烧录工程 [lvgl_checkbox](../../../examples/nt26/module/lvgl/lvgl_checkbox)、[lvgl_dropdown](../../../examples/nt26/module/lvgl/lvgl_dropdown) |
| 1.10.0 | 2026-09-18 | 增加文本框 `ui:textarea`；`set_text` / `set_text_align` 适配；新增 `get_text` / `add_text` / `set_placeholder` / `set_password` / `set_one_line`；可烧录工程 [lvgl_textarea](../../../examples/nt26/module/lvgl/lvgl_textarea) |
| 1.11.0 | 2026-09-18 | 增加开关 `ui:switch`；`set_value` / `get_value` / `set_dir` / `get_dir` 适配；导出 `SWITCH_DIR_*`、`PART_*`、`STATE_CHECKED`；可烧录工程 [lvgl_switch](../../../examples/nt26/module/lvgl/lvgl_switch) |
| 1.12.0 | 2026-09-18 | 增加转圈 `ui:spinner`；新增 `set_anim` / `get_anim`；样式表增加 `arc_color` / `arc_width`；可烧录工程 [lvgl_spinner](../../../examples/nt26/module/lvgl/lvgl_spinner) |
| 1.13.0 | 2026-09-18 | 增加软键盘 `ui:keyboard`；`set_mode` 适配键盘布局；新增 `set_textarea` / `set_popovers` 与 `KEYBOARD_MODE_*`、`PART_ITEMS`；可烧录工程 [lvgl_keyboard](../../../examples/nt26/module/lvgl/lvgl_keyboard) |
| 1.13.1 | 2026-09-18 | 可烧录工程增加 [lvgl_btn](../../../examples/nt26/module/lvgl/lvgl_btn)：`on_click` + `ui:click` 模拟点按 |
| 1.14.0 | 2026-09-18 | 增加 `ui:add_state` / `ui:remove_state` 与 `STATE_PRESSED`；`ui:click` 不置按下态。例程 [lvgl_btn](../../../examples/nt26/module/lvgl/lvgl_btn) 先按下再点 |
| 1.15.0 | 2026-09-18 | 增加消息框 `ui:msgbox`；`set_text` / `get_text` / `add_text` / `close` 适配；新增 `add_footer_btn` / `add_close_btn`；可烧录工程 [lvgl_msgbox](../../../examples/nt26/module/lvgl/lvgl_msgbox) |
