# ============================================================================
# config_editor.py — NT26 短信转发器 配置编辑器（Windows 上位机 GUI）
# ----------------------------------------------------------------------------
# 功能：可视化编辑 config.lua，涵盖：
#   * 管理员手机号 / 转发手机号
#   * 固定 11 种推送通道，每种可独立启用（无数量上限），通用字段：
#       enabled, type, name, url, key, key2, customBody, priority
# 点击“确定保存”后自动定位并修改同项目下的 config.lua，无需手动找行号。
#
# 依赖：仅 Python 标准库（tkinter / ttk / re / os / shutil），无需第三方包。
# 打包：pyinstaller --onefile --windowed --name NT26ConfigEditor config_editor.py
# ============================================================================

import os
import re
import shutil
import tkinter as tk
from tkinter import messagebox, filedialog, ttk

# ---------------------------------------------------------------------------
# 推送类型（必须与 config.lua 的 PUSH 常量完全一致）
# ---------------------------------------------------------------------------
# 固定支持的推送通道（顺序即界面展示顺序）；不再提供"新增/删除"与数量上限。
FIXED_CHANNEL_ORDER = [
    "CUSTOM_POST", "TELEGRAM", "PUSHDEER", "BARK", "DINGTALK",
    "FEISHU", "WECOM", "PUSHOVER", "INOTIFY", "NEXT_SMTP_PROXY", "GOTIFY",
]

# 每种类型的关键字段说明（用于界面提示）
TYPE_HINT = {
    "CUSTOM_POST":     "通用自定义 POST：customBody 模板。key 填 \"form\" 走表单编码(否则 JSON)。"
                       "JSON 用 {sender}/{message}/{timestamp}；表单务必用 {sender_u}/{message_u}/{timestamp_u}(URL编码)，避免短信内 &/=/%/空格 破坏表单。",
    "TELEGRAM":        "Telegram：key=chat_id；key2=bot_token；url 默认 https://api.telegram.org。",
    "PUSHDEER":        "PushDeer：key=pushkey；url 默认 https://api2.pushdeer.com/message/push。",
    "BARK":            "Bark：key=设备Key；url 默认 https://api.day.app。",
    "DINGTALK":        "钉钉机器人：url=Webhook(含 access_token)；key2=加签 SEC 密钥(留空不加密)。",
    "FEISHU":          "飞书机器人：url=Webhook；key2=签名密钥(留空不校验)。",
    "WECOM":           "企业微信机器人：url=Webhook。",
    "PUSHOVER":        "Pushover：key=API Token；key2=User Key；url 默认 https://api.pushover.net/1/messages.json。",
    "INOTIFY":         "inotify：url 须以 .send 结尾，消息作为路径段(GET)。",
    "NEXT_SMTP_PROXY": "邮件代理：key 内以 | 分隔 6 字段 "
                       "user|password|smtp_host|smtp_port|to_email|subject；text=短信内容。",
    "GOTIFY":          "Gotify：url 为服务地址(可 http)；key=Token。",
}

# 界面展示用中文名（key 与 FIXED_CHANNEL_ORDER 对应）
TYPE_LABEL = {
    "CUSTOM_POST":     "自定义POST",
    "TELEGRAM":        "Telegram",
    "PUSHDEER":        "PushDeer",
    "BARK":            "Bark",
    "DINGTALK":        "钉钉",
    "FEISHU":          "飞书",
    "WECOM":           "企业微信",
    "PUSHOVER":        "Pushover",
    "INOTIFY":         "inotify",
    "NEXT_SMTP_PROXY": "邮件代理(SMTP)",
    "GOTIFY":          "Gotify",
}


# ---------------------------------------------------------------------------
# Lua 字符串编解码（用于 key/url/customBody 等字符串字段）
# ---------------------------------------------------------------------------

def lua_encode_str(s):
    """将 Python 字符串编码为 Lua 双引号字符串字面量。"""
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r")
    s = s.replace("\n", "\\n").replace("\t", "\\t")
    return '"' + s + '"'


def lua_decode_str(lit):
    """将 Lua 字符串字面量(单/双引号)解码为 Python 字符串。"""
    lit = lit.strip()
    if len(lit) >= 2 and lit[0] == '"' and lit[-1] == '"':
        body = lit[1:-1]
    elif len(lit) >= 2 and lit[0] == "'" and lit[-1] == "'":
        body = lit[1:-1]
    else:
        return lit
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            mp = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\",
                  '"': '"', "'": "'"}
            out.append(mp.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _skip_string(text, i, n):
    """从引号处跳到字符串结束，返回结束引号之后的下标。"""
    q = text[i]
    j = i + 1
    while j < n:
        if text[j] == "\\":            # 跳过转义序列
            j += 2
            continue
        if text[j] == q:
            return j + 1
        j += 1
    return j


def _strip_comments(text):
    """去除 Lua 行注释(--)至行尾的内容，但忽略字符串内部的 --。"""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c in ('"', "'"):
            j = _skip_string(text, i, n)
            out.append(text[i:j])
            i = j
            continue
        if c == "-" and i + 1 < n and text[i + 1] == "-":
            j = text.find("\n", i)
            if j == -1:
                break
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _find_channel_spans(text):
    """找出所有未被注释的 ch(...) 调用区间 [start, end)。"""
    spans = []
    i = 0
    n = len(text)
    while i < n:
        idx = text.find("ch(", i)
        if idx == -1:
            break
        # 跳过处于行注释中的 ch(...)
        ls = text.rfind("\n", 0, idx) + 1
        if "--" in text[ls:idx]:
            i = idx + 3
            continue
        # 跳过函数定义等：ch 前(跳过空白)若是标识符字符（如 "function ch("）则不是调用
        k = idx - 1
        while k >= 0 and text[k] in (" ", "\t"):
            k -= 1
        if k >= 0 and (text[k].isalnum() or text[k] == "_"):
            i = idx + 3
            continue
        depth = 0
        j = idx
        close = -1
        while j < n:
            c = text[j]
            if c in ('"', "'"):
                j = _skip_string(text, j, n)
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    close = j
                    break
            j += 1
        if close == -1:
            break
        spans.append((idx, close + 1))
        i = close + 1
    return spans


def _split_args(inner):
    """按顶层逗号切分 ch(...) 内部参数。"""
    args = []
    depth = 0
    cur = []
    i = 0
    n = len(inner)
    while i < n:
        c = inner[i]
        if c in ('"', "'"):
            j = _skip_string(inner, i, n)
            cur.append(inner[i:j])
            i = j
            continue
        if c in ("(", "{", "["):
            depth += 1
            cur.append(c)
        elif c in (")", "}", "]"):
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    if cur:
        args.append("".join(cur).strip())
    return args


def _eval_arg(raw):
    """将单个参数原文解析为 Python 值。"""
    raw = raw.strip()
    if raw == "true":
        return True
    if raw == "false":
        return False
    if raw == "nil":
        return ""
    if (raw.startswith('"') and raw.endswith('"')) or \
       (raw.startswith("'") and raw.endswith("'")):
        return lua_decode_str(raw)
    try:
        return int(raw)
    except ValueError:
        return raw


def _new_channel(type_code=FIXED_CHANNEL_ORDER[0]):
    return {
        "enabled": False, "type": type_code, "name": "",
        "url": "", "key": "", "key2": "", "customBody": "", "priority": 0,
    }


def parse_config(text):
    """从 config.lua 文本提取当前配置，返回 dict。"""
    data = {"admin_phone": "", "forward_phones": [], "channels": []}

    m = re.search(r'adminPhone\s*=\s*"([^"]*)"', text)
    if m:
        data["admin_phone"] = m.group(1)

    m = re.search(r'forwardPhones\s*=\s*\{([^}]*)\}', text)
    if m:
        phones = re.findall(r'"([^"]*)"|\'([^\']*)\'', m.group(1))
        data["forward_phones"] = [p[0] or p[1] for p in phones if (p[0] or p[1])]

    for (s, e) in _find_channel_spans(text):
        blk = text[s:e]
        blk = _strip_comments(blk)            # 去除行内注释，避免污染字段值
        inner = blk[blk.find("(") + 1: blk.rfind(")")]
        args = _split_args(inner)
        try:
            ch = _new_channel()
            if len(args) > 0:
                ch["enabled"] = (_eval_arg(args[0]) is True)
            if len(args) > 1:
                t = _eval_arg(args[1])
                ch["type"] = t.split(".")[-1] if isinstance(t, str) else ""
            if len(args) > 2:
                ch["name"] = _eval_arg(args[2])
            if len(args) > 3:
                ch["url"] = _eval_arg(args[3])
            if len(args) > 4:
                ch["key"] = _eval_arg(args[4])
            if len(args) > 5:
                ch["key2"] = _eval_arg(args[5])
            if len(args) > 6:
                ch["customBody"] = _eval_arg(args[6])
            if len(args) > 7:
                p = _eval_arg(args[7])
                ch["priority"] = p if isinstance(p, int) else 0
            data["channels"].append(ch)
        except Exception:
            # 解析失败的通道保留原文，避免破坏未知结构
            data["channels"].append({"_raw": blk})

    return data


def _format_channel(ch):
    """将通道 dict 渲染为规范的 ch(...) 文本块。"""
    def s(v):
        return lua_encode_str(v or "")
    return (
        '        ch(%s, PUSH.%s, %s,\n'
        '            %s,\n'        # url
        '            %s,\n'        # key
        '            %s,\n'        # key2
        '            %s,\n'        # customBody
        '            %s),'         # priority
    ) % (
        "true" if ch.get("enabled") else "false",
        ch.get("type", FIXED_CHANNEL_ORDER[0]),
        s(ch.get("name")),
        s(ch.get("url")),
        s(ch.get("key")),
        s(ch.get("key2")),
        s(ch.get("customBody")),
        int(ch.get("priority") or 0),
    )


def _replace_pushchannels(text, channels):
    """整体替换 pushChannels = { ... } 内部内容。"""
    m = re.search(r'pushChannels\s*=\s*\{', text)
    if not m:
        # 兜底：在 return DEFAULT_CFG 之前插入
        ridx = text.find("return DEFAULT_CFG")
        block = ('\nlocal DEFAULT_CFG = {\n    pushChannels = {\n' +
                 "\n".join(_format_channel(c) for c in channels) +
                 '\n    },\n}\n')
        if ridx != -1:
            return text[:ridx] + block + text[ridx:]
        raise ValueError("未找到 pushChannels 与 return DEFAULT_CFG，无法写入通道")
    start = m.end()
    depth = 1
    i = start
    n = len(text)
    close = -1
    while i < n:
        c = text[i]
        if c in ('"', "'"):
            i = _skip_string(text, i, n)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                close = i
                break
        i += 1
    if close == -1:
        raise ValueError("未找到 pushChannels 的结束 '}'")
    header = text[m.start():start]          # "pushChannels = {"
    body_lines = ["        -- 推送通道（固定 %d 种，每种一个 ch(...)）" % len(channels)]
    for c in channels:
        if "_raw" in c:
            body_lines.append("        " + c["_raw"].strip())
        else:
            body_lines.append(_format_channel(c))
    new_block = header + "\n" + "\n".join(body_lines) + "\n    }"
    return text[:m.start()] + new_block + text[close + 1:]


def apply_config(text, data):
    """把界面数据写回 config.lua 文本，返回新文本。"""
    # 1) 管理员手机号
    text = re.sub(
        r'(adminPhone\s*=\s*")[^"]*(")',
        lambda m: m.group(1) + data["admin_phone"] + m.group(2),
        text, count=1,
    )
    # 2) 转发手机号列表
    inner = ",".join('"%s"' % p for p in data["forward_phones"])
    text = re.sub(
        r'(forwardPhones\s*=\s*)\{[^}]*\}',
        lambda m: m.group(1) + "{" + inner + "}",
        text, count=1,
    )
    # 3) 推送通道块
    text = _replace_pushchannels(text, data["channels"])
    return text


# ---------------------------------------------------------------------------
# 文件定位
# ---------------------------------------------------------------------------

def find_config_lua(start_dir):
    """在 start_dir 及其子目录(深度<=3)、父目录中查找 config.lua。"""
    found = []
    for root, dirs, files in os.walk(start_dir):
        depth = root[len(os.path.commonprefix([root, start_dir])):].count(os.sep)
        if depth > 3:
            dirs[:] = []
            continue
        if "config.lua" in files:
            found.append(os.path.join(root, "config.lua"))
    p = start_dir
    for _ in range(3):
        p = os.path.dirname(p)
        cand = os.path.join(p, "config.lua")
        if os.path.isfile(cand) and cand not in found:
            found.append(cand)
    return found


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NT26 短信转发器 - 配置编辑器")
        self.resizable(True, True)
        self.config_path = None
        self.channels = []          # 通道数据(dict)列表
        self.channel_vars = []      # 与 channels 同序的 tk 变量集合
        self.channel_frames = []    # 与 channels 同序的控件集
        self._build_ui()
        self._auto_locate()

    # ---- UI 构建 ----
    def _build_ui(self):
        pad = {"padx": 8, "pady": 4}

        # 路径行
        f0 = tk.Frame(self)
        f0.grid(row=0, column=0, columnspan=2, sticky="ew", **pad)
        tk.Label(f0, text="config.lua 路径:").pack(side="left")
        self.path_var = tk.StringVar()
        tk.Entry(f0, textvariable=self.path_var, state="readonly", width=60).pack(
            side="left", fill="x", expand=True, padx=(4, 4))
        tk.Button(f0, text="浏览...", command=self._browse).pack(side="left")

        # 管理员 / 转发
        f1 = tk.LabelFrame(self, text="手机号配置")
        f1.grid(row=1, column=0, columnspan=2, sticky="ew", **pad)
        tk.Label(f1, text="管理员手机号:").grid(row=0, column=0, sticky="w")
        self.admin_var = tk.StringVar()
        tk.Entry(f1, textvariable=self.admin_var, width=40).grid(row=0, column=1, sticky="w")
        tk.Label(f1, text="转发手机号 (每行一个):").grid(row=1, column=0, sticky="nw")
        self.forward_txt = tk.Text(f1, width=40, height=3)
        self.forward_txt.grid(row=1, column=1, sticky="w")

        # 推送通道区（可滚动，固定列出全部通道，用户自行勾选启用）
        fch = tk.LabelFrame(self, text="推送通道（固定 %d 种，勾选启用）" % len(FIXED_CHANNEL_ORDER))
        fch.grid(row=2, column=0, columnspan=2, sticky="nsew", **pad)
        self.rowconfigure(2, weight=1)
        self.columnconfigure(0, weight=1)

        self.canvas = tk.Canvas(fch)
        self.canvas.pack(side="left", fill="both", expand=True)
        vsb = ttk.Scrollbar(fch, orient="vertical", command=self.canvas.yview)
        vsb.pack(side="right", fill="y")
        self.canvas.configure(yscrollcommand=vsb.set)
        self.channels_inner = tk.Frame(self.canvas)
        self.canvas.create_window((0, 0), window=self.channels_inner, anchor="nw")
        self.channels_inner.bind("<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))

        # 按钮
        fbtn = tk.Frame(self)
        fbtn.grid(row=4, column=0, columnspan=2, **pad)
        tk.Button(fbtn, text="确定保存", command=self._save, width=14,
                  bg="#2e7d32", fg="white").pack(side="left", padx=6)
        tk.Button(fbtn, text="重新读取", command=self._reload, width=14).pack(side="left", padx=6)
        tk.Button(fbtn, text="退出", command=self.destroy, width=14).pack(side="left", padx=6)

        # 状态栏
        self.status_var = tk.StringVar(value="就绪")
        tk.Label(self, textvariable=self.status_var, relief="sunken", anchor="w"
                 ).grid(row=5, column=0, columnspan=2, sticky="ew", padx=8, pady=(0, 6))

    # ---- 通道 UI 构建（固定列出全部通道，每种可独立启用）----
    def _build_channels_ui(self):
        for w in self.channels_inner.winfo_children():
            w.destroy()
        self.channel_vars = []
        self.channel_frames = []

        for idx, ch in enumerate(self.channels):
            if "_raw" in ch:
                # 解析失败/未知结构的通道：仅显示原文，禁止编辑
                lf = tk.LabelFrame(self.channels_inner,
                                   text="通道 #%d（无法解析，保留原文）" % (idx + 1))
                lf.pack(fill="x", padx=4, pady=4, anchor="nw")
                txt = tk.Text(lf, width=80, height=3)
                txt.insert("1.0", ch["_raw"])
                txt.configure(state="disabled")
                txt.pack(fill="x")
                self.channel_frames.append(lf)
                self.channel_vars.append(None)
                continue

            tname = ch.get("type", "")
            label = TYPE_LABEL.get(tname, tname)
            lf = tk.LabelFrame(self.channels_inner,
                               text="%d. %s（%s）" % (idx + 1, label, tname))
            lf.pack(fill="x", padx=4, pady=4, anchor="nw")

            vars = {}
            # 第一行：启用 / 名称 / 优先级
            r0 = tk.Frame(lf)
            r0.pack(fill="x", padx=4, pady=2)
            vars["enabled"] = tk.BooleanVar(value=bool(ch.get("enabled")))
            tk.Checkbutton(r0, text="启用", variable=vars["enabled"]).pack(side="left")
            tk.Label(r0, text="名称:").pack(side="left", padx=(10, 0))
            vars["name"] = tk.StringVar(value=ch.get("name", ""))
            tk.Entry(r0, textvariable=vars["name"], width=18).pack(side="left")
            tk.Label(r0, text="优先级:").pack(side="left", padx=(10, 0))
            vars["priority"] = tk.StringVar(value=str(ch.get("priority", 0)))
            tk.Entry(r0, textvariable=vars["priority"], width=6).pack(side="left")
            tk.Label(r0, text="(0最高, 数字越小越先发)", fg="#888").pack(side="left")
            # 类型固定（不提供下拉），仅作隐藏变量供保存使用
            vars["type"] = tk.StringVar(value=tname)

            desc = tk.Label(lf, text=TYPE_HINT.get(tname, ""), fg="#555", anchor="w",
                            wraplength=780, justify="left")
            desc.pack(fill="x", padx=4)

            # URL
            r1 = tk.Frame(lf)
            r1.pack(fill="x", padx=4, pady=2)
            tk.Label(r1, text="URL:").pack(side="left")
            vars["url"] = tk.StringVar(value=ch.get("url", ""))
            tk.Entry(r1, textvariable=vars["url"], width=90).pack(side="left", fill="x", expand=True)

            # key（主密钥）/ key2（可选第二值）
            r2 = tk.Frame(lf)
            r2.pack(fill="x", padx=4, pady=2)
            tk.Label(r2, text="key:").pack(side="left")
            vars["key"] = tk.StringVar(value=ch.get("key", ""))
            tk.Entry(r2, textvariable=vars["key"], width=42).pack(side="left")
            tk.Label(r2, text="key2(可选):").pack(side="left", padx=(10, 0))
            vars["key2"] = tk.StringVar(value=ch.get("key2", ""))
            tk.Entry(r2, textvariable=vars["key2"], width=30, show="*").pack(side="left")

            # customBody
            r5 = tk.Frame(lf)
            r5.pack(fill="x", padx=4, pady=2)
            tk.Label(r5, text="customBody:").pack(side="left")
            vars["customBody"] = tk.StringVar(value=ch.get("customBody", ""))
            tk.Entry(r5, textvariable=vars["customBody"], width=90).pack(side="left", fill="x", expand=True)

            self.channel_vars.append(vars)
            self.channel_frames.append(lf)

        self.canvas.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    # ---- 逻辑 ----
    def _auto_locate(self):
        here = os.path.dirname(os.path.abspath(__file__))
        found = find_config_lua(here)
        if found:
            self._set_path(found[0])
            if len(found) > 1:
                self.status_var.set("发现多个 config.lua，已用首个；可用“浏览”切换")
            self._reload()
        else:
            self.status_var.set("未找到 config.lua，请用“浏览”手动选择")

    def _set_path(self, path):
        self.config_path = path
        self.path_var.set(path)

    def _browse(self):
        p = filedialog.askopenfilename(
            title="选择 config.lua", filetypes=[("Lua 配置", "config.lua"), ("所有文件", "*.*")])
        if p:
            self._set_path(p)
            self._reload()

    def _reload(self):
        if not self.config_path or not os.path.isfile(self.config_path):
            self.status_var.set("config.lua 不存在，请先选择")
            return
        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                text = f.read()
        except Exception as e:
            self.status_var.set("读取失败: %s" % e)
            return
        d = parse_config(text)
        self.admin_var.set(d["admin_phone"])
        self.forward_txt.delete("1.0", "end")
        self.forward_txt.insert("1.0", "\n".join(d["forward_phones"]))
        # 将解析到的通道按类型映射到固定 11 种（缺失的用默认占位，确保全部列出）
        by_type = {}
        for c in d["channels"]:
            if "_raw" in c:
                continue
            t = c.get("type")
            if t and t not in by_type:
                by_type[t] = c
        self.channels = [dict(by_type.get(t, _new_channel(t))) for t in FIXED_CHANNEL_ORDER]
        self._build_channels_ui()
        self.status_var.set("已载入: " + os.path.basename(self.config_path))

    def _flush_channels(self):
        """把当前界面控件的值写回 self.channels。"""
        for idx, vars in enumerate(self.channel_vars):
            if vars is None:
                continue
            ch = self.channels[idx]
            if "_raw" in ch:
                continue
            ch["enabled"] = vars["enabled"].get()
            ch["type"] = vars["type"].get()
            ch["name"] = vars["name"].get()
            ch["url"] = vars["url"].get()
            ch["key"] = vars["key"].get()
            ch["key2"] = vars["key2"].get()
            ch["customBody"] = vars["customBody"].get()
            try:
                ch["priority"] = int(vars["priority"].get() or 0)
            except ValueError:
                ch["priority"] = 0

    def _add_channel(self):
        # 固定通道模式下不再提供新增/删除
        pass

    def _del_channel(self, idx):
        # 固定通道模式下不再提供新增/删除
        pass

    def _save(self):
        if not self.config_path or not os.path.isfile(self.config_path):
            messagebox.showerror("错误", "未找到 config.lua，请先“浏览”选择")
            return

        phones = [ln.strip() for ln in self.forward_txt.get("1.0", "end").splitlines()
                  if ln.strip()]
        self._flush_channels()
        # 丢弃无法解析的通道（保留其原文件内容由 replace 逻辑处理，这里不写入）
        channels_out = [c for c in self.channels if "_raw" not in c]

        data = {
            "admin_phone": self.admin_var.get().strip(),
            "forward_phones": phones,
            "channels": channels_out,
        }

        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                text = f.read()
            new_text = apply_config(text, data)
        except Exception as e:
            messagebox.showerror("错误", "读取/解析失败: %s" % e)
            return

        try:
            bak = self.config_path + ".bak"
            shutil.copy2(self.config_path, bak)
            with open(self.config_path, "w", encoding="utf-8") as f:
                f.write(new_text)
        except Exception as e:
            messagebox.showerror("错误", "写入失败: %s" % e)
            return

        self.status_var.set("已保存到 %s（备份: %s）" %
                            (os.path.basename(self.config_path), os.path.basename(bak)))
        messagebox.showinfo("完成",
            "配置已写入 config.lua。\n请重新烧录（config.lua 需与主脚本一起下载到模块）后生效。")


if __name__ == "__main__":
    App().mainloop()
