--[=[
  ufs 指令 Demo — UART1 收指令，协程里读写 Lua 值

  和同目录 ufs_api 用同一套 ufs API。
  差别：本 demo 不自动写文件，完全由串口指令驱动。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay）
      → rt.mbox_send 投到指令协程
      → 协程里执行 ufs.write / read / cmp / remove / stat / list / usage
      → 成功或失败通过 UART1 回写

  指令动词不区分大小写；行首行尾空白和 \r\n 会去掉。
  文件名、写入内容保留原样。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    ufs write <name> <text>
        把 text 当 string 覆盖写入。text 可以有空格。
        例：ufs write cfg hello world

    ufs write_num <name> <n>
        写入数字（整数或小数）。

    ufs write_bool <name> <true|false|0|1>
        写入布尔。

    ufs write_nil <name>
        写入 nil。之后 read 得到 nil,nil，不是 not found。

    ufs write_tbl <name>
        写入示例表 {id=1, name="demo", ok=true, tags={"a","b"}}。

    ufs read <name>
        读出并打印。

    ufs cmp <name> <text>
        与已存对象比（text 当 string）。文件不存在返回 false。

    ufs cmp_tbl <name>
        与 write_tbl 那张表示例表比较。

    ufs remove <name>
        删除。不存在也算成功。

    ufs stat <name>
    ufs list
    ufs usage
    ufs help

]=]

local rt = require("rt")
local uart = require("uart")
local ufs = require("ufs")

local UART_ID = uart.UART1
local CMD_TOPIC = "ufs_cmd"

local function sample_tbl()
    return { id = 1, name = "demo", ok = true, tags = { "a", "b" } }
end

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
end

local function fmt_val(v)
    local t = type(v)
    if t == "nil" then
        return "nil"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" or t == "number" then
        return tostring(v)
    elseif t == "table" then
        local bits = {}
        for k, x in pairs(v) do
            local xs
            if type(x) == "table" then
                xs = "{...}"
            else
                xs = fmt_val(x)
            end
            bits[#bits + 1] = tostring(k) .. "=" .. xs
        end
        return "{" .. table.concat(bits, ",") .. "}"
    end
    return t
end

local function parse_bool(s)
    if s == "1" or s == "true" then
        return true, true
    end
    if s == "0" or s == "false" then
        return true, false
    end
    return false, nil
end

local function cmd_write_str(name, text)
    if not name or name == "" then
        reply(false, "write：用法 ufs write <name> <text>")
        return
    end
    local ok, err = ufs.write(name, text or "")
    if not ok then
        reply(false, "write：%s", tostring(err))
        return
    end
    reply(true, "write %s n=%d", name, text and #text or 0)
end

local function cmd_write_num(name, n)
    if not name or name == "" or n == nil then
        reply(false, "write_num：用法 ufs write_num <name> <n>")
        return
    end
    local ok, err = ufs.write(name, n)
    if not ok then
        reply(false, "write_num：%s", tostring(err))
        return
    end
    reply(true, "write_num %s=%s", name, tostring(n))
end

local function cmd_write_bool(name, s)
    local parsed, b = parse_bool(s or "")
    if not name or name == "" or not parsed then
        reply(false, "write_bool：用法 ufs write_bool <name> <true|false|0|1>")
        return
    end
    local ok, err = ufs.write(name, b)
    if not ok then
        reply(false, "write_bool：%s", tostring(err))
        return
    end
    reply(true, "write_bool %s=%s", name, tostring(b))
end

local function cmd_write_nil(name)
    if not name or name == "" then
        reply(false, "write_nil：用法 ufs write_nil <name>")
        return
    end
    local ok, err = ufs.write(name, nil)
    if not ok then
        reply(false, "write_nil：%s", tostring(err))
        return
    end
    reply(true, "write_nil %s", name)
end

local function cmd_write_tbl(name)
    if not name or name == "" then
        reply(false, "write_tbl：用法 ufs write_tbl <name>")
        return
    end
    local ok, err = ufs.write(name, sample_tbl())
    if not ok then
        reply(false, "write_tbl：%s", tostring(err))
        return
    end
    reply(true, "write_tbl %s", name)
end

local function cmd_read(name)
    if not name or name == "" then
        reply(false, "read：用法 ufs read <name>")
        return
    end
    local v, err = ufs.read(name)
    if err ~= nil then
        reply(false, "read：%s", tostring(err))
        return
    end
    reply(true, "read %s type=%s value=%s", name, type(v), fmt_val(v))
end

local function cmd_cmp(name, text)
    if not name or name == "" then
        reply(false, "cmp：用法 ufs cmp <name> <text>")
        return
    end
    local eq, err = ufs.cmp(name, text or "")
    if eq == nil then
        reply(false, "cmp：%s", tostring(err))
        return
    end
    reply(true, "cmp %s equal=%s", name, tostring(eq))
end

local function cmd_cmp_tbl(name)
    if not name or name == "" then
        reply(false, "cmp_tbl：用法 ufs cmp_tbl <name>")
        return
    end
    local eq, err = ufs.cmp(name, sample_tbl())
    if eq == nil then
        reply(false, "cmp_tbl：%s", tostring(err))
        return
    end
    reply(true, "cmp_tbl %s equal=%s", name, tostring(eq))
end

local function cmd_remove(name)
    if not name or name == "" then
        reply(false, "remove：用法 ufs remove <name>")
        return
    end
    local ok, err = ufs.remove(name)
    if not ok then
        reply(false, "remove：%s", tostring(err))
        return
    end
    reply(true, "remove %s", name)
end

local function cmd_stat(name)
    if not name or name == "" then
        reply(false, "stat：用法 ufs stat <name>")
        return
    end
    local st, err = ufs.stat(name)
    if not st then
        reply(false, "stat：%s", tostring(err))
        return
    end
    reply(true, "stat name=%s size=%s is_dir=%s", st.name, tostring(st.size), tostring(st.is_dir))
end

local function cmd_list()
    local items, err = ufs.list()
    if not items then
        reply(false, "list：%s", tostring(err))
        return
    end
    reply(true, "list n=%d", #items)
    for i = 1, #items do
        hint("  [%d] name=%s size=%s is_dir=%s",
             i, items[i].name, tostring(items[i].size), tostring(items[i].is_dir))
    end
end

local function cmd_usage()
    local u, err = ufs.usage()
    if not u then
        reply(false, "usage：%s", tostring(err))
        return
    end
    reply(true, "used=%s limit=%s script_used=%s shared_limit=%s",
          tostring(u.used), tostring(u.limit), tostring(u.script_used), tostring(u.shared_limit))
end

local function print_help()
    local lines = {
        "",
        "==== UFS 指令 ====",
        "UART1 输入，回车发送",
        "",
        "ufs write <name> <text>",
        "ufs write_num <name> <n>",
        "ufs write_bool <name> <true|false|0|1>",
        "ufs write_nil <name>",
        "ufs write_tbl <name>",
        "ufs read <name>",
        "ufs cmp <name> <text>",
        "ufs cmp_tbl <name>",
        "ufs remove <name>",
        "ufs stat <name>",
        "ufs list",
        "ufs usage",
        "ufs help",
        "",
        "文件名不要带 / \\ : 或 ..",
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    local verb = lower:match("^ufs%s+(%S+)")
    if not verb then
        reply(false, "未知指令: %s", cmd)
        hint("输入 ufs help")
        return
    end

    if verb == "help" then
        print_help()
        return
    elseif verb == "list" then
        cmd_list()
        return
    elseif verb == "usage" then
        cmd_usage()
        return
    elseif verb == "write_num" then
        local name, ns = cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]_[Nn][Uu][Mm]%s+(%S+)%s+(%-?[%d%.]+)%s*$")
        cmd_write_num(name, name and tonumber(ns) or nil)
        return
    elseif verb == "write_bool" then
        local name, b = cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]_[Bb][Oo][Oo][Ll]%s+(%S+)%s+(%S+)%s*$")
        cmd_write_bool(name, b and b:lower() or nil)
        return
    elseif verb == "write_nil" then
        cmd_write_nil(cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]_[Nn][Ii][Ll]%s+(%S+)%s*$"))
        return
    elseif verb == "write_tbl" then
        cmd_write_tbl(cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]_[Tt][Bb][Ll]%s+(%S+)%s*$"))
        return
    elseif verb == "write" then
        local name, text = cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]%s+(%S+)%s+(.-)%s*$")
        if not name then
            name = cmd:match("^[Uu][Ff][Ss]%s+[Ww][Rr][Ii][Tt][Ee]%s+(%S+)%s*$")
            text = ""
        end
        cmd_write_str(name, text)
        return
    elseif verb == "cmp_tbl" then
        cmd_cmp_tbl(cmd:match("^[Uu][Ff][Ss]%s+[Cc][Mm][Pp]_[Tt][Bb][Ll]%s+(%S+)%s*$"))
        return
    elseif verb == "cmp" then
        local name, text = cmd:match("^[Uu][Ff][Ss]%s+[Cc][Mm][Pp]%s+(%S+)%s+(.-)%s*$")
        if not name then
            name = cmd:match("^[Uu][Ff][Ss]%s+[Cc][Mm][Pp]%s+(%S+)%s*$")
            text = ""
        end
        cmd_cmp(name, text)
        return
    elseif verb == "read" then
        cmd_read(cmd:match("^[Uu][Ff][Ss]%s+[Rr][Ee][Aa][Dd]%s+(%S+)%s*$"))
        return
    elseif verb == "remove" then
        cmd_remove(cmd:match("^[Uu][Ff][Ss]%s+[Rr][Ee][Mm][Oo][Vv][Ee]%s+(%S+)%s*$"))
        return
    elseif verb == "stat" then
        cmd_stat(cmd:match("^[Uu][Ff][Ss]%s+[Ss][Tt][Aa][Tt]%s+(%S+)%s*$"))
        return
    end

    reply(false, "未知指令: %s", cmd)
    hint("输入 ufs help")
end

local function uart_cb(id, data, meta)
    if data == nil or data == "" then
        return
    end
    if meta and meta.at_check == 0 then
        return
    end
    rt.mbox_send(CMD_TOPIC, data)
end

print_help()

rt.task_start(function()
    while true do
        local ok, data = rt.mbox_recv(CMD_TOPIC)
        if ok and data and data ~= "" then
            for line in (tostring(data) .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
                local pok, perr = pcall(handle_line, line)
                if not pok then
                    reply(false, "执行异常: %s", tostring(perr))
                end
            end
        end
    end
end)

uart.reg(UART_ID, uart_cb)
hint("UART1 回调已注册，等待指令")

while true do
    rt.delay(60000)
end

--[=[
  ufs 指令 Demo — UART1 驱动 Lua 值落盘

  require("ufs")。把可序列化 Lua 值写成受限文件。
  逻辑格式：魔数 "UMP1" + MessagePack；落盘 CREC(FastLZ)。
  与 lua 脚本、ublob 共用 220KiB 配额（按压缩后落盘）。
  可写空间 = 220KiB − lua 脚本落盘。编码 RAM 上限 80KiB。
  底层文件前缀 lua_usr_，Lua 只传短名。不兼容旧 JSON / 裸 UMP1。

  ----------------------------------------------------------------------------
  串口指令（本 demo）
  ----------------------------------------------------------------------------
    回调里只 mbox_send，真正 ufs.* 都在协程里做。
    write / write_num / write_bool / write_nil / write_tbl 都落到 ufs.write。
    cmp / cmp_tbl 落到 ufs.cmp。read / remove / stat / list / usage 一对一。
    文件名禁止 '/' '\\' ':' 控制字符和 ".."。
    ufs 与 ublob 命名空间分开，同名互不可见。

  ----------------------------------------------------------------------------
  ufs.write(name, value) -> ok, err
  ----------------------------------------------------------------------------
    覆盖写。成功 true, nil；失败 false, 错误串（不是 nil, err）。
    value：nil / boolean / number / string / table。
    table 键限 string/number/boolean；1..n 无空洞 → array，否则 map。
    嵌套 ≤10，单表 ≤4096 项。function 等 → "unsupported value type"。
    配额满 → "quota exceeded"；文件名非法 → "invalid param"。

  ----------------------------------------------------------------------------
  ufs.read(name) -> value, err
  ----------------------------------------------------------------------------
    成功 value, nil。失败 nil, err（"not found" / "read target is dir" /
    "not msgpack ufs data" / "bad record" / "反序列化失败"）。
    写入过 nil 时成功返回 nil, nil，要用第二返回值区分「没有文件」。

  ----------------------------------------------------------------------------
  ufs.remove(name) -> ok | nil, err
  ----------------------------------------------------------------------------
    成功或不存在：true。其它失败：nil, err。

  ----------------------------------------------------------------------------
  ufs.stat(name) -> {name, size, is_dir} | nil, err
  ----------------------------------------------------------------------------
    size 是解压后逻辑长度，不是压缩落盘大小。

  ----------------------------------------------------------------------------
  ufs.list() -> items | nil, err
  ----------------------------------------------------------------------------
    只列 ufs 对象。空仓 {}。

  ----------------------------------------------------------------------------
  ufs.usage() -> {used, limit, script_used, shared_limit} | nil, err
  ----------------------------------------------------------------------------
    used/limit：ufs+ublob 占用与可写上限。shared_limit=220KiB。
    与 ublob.usage() 同一套数字。

  ----------------------------------------------------------------------------
  ufs.cmp(name, value) -> equal | nil, err
  ----------------------------------------------------------------------------
    深度比较。文件不存在返回 false。读失败 nil, err。
    适合配置没变就跳过 write。

  ============================================================================
  本 demo
  ============================================================================
    上电打印帮助；UART1 一行一条。建议顺序：
    ufs write_tbl cfg → ufs read cfg → ufs cmp_tbl cfg → ufs list → ufs usage
    → ufs remove cfg。不要循环狂写，配额是压缩后的真实占用。

]=]
