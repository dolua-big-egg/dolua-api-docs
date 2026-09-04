--[=[
  ublob 指令 Demo — UART1 收指令，协程里读写字节 blob

  和同目录 ublob_api 用同一套 ublob API。
  差别：本 demo 不自动写文件，完全由串口指令驱动。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay）
      → rt.mbox_send 投到指令协程
      → 协程里执行 ublob.write / append / read / open / view:* / remove ...
      → 成功或失败通过 UART1 回写

  指令动词不区分大小写；行首行尾空白和 \r\n 会去掉。
  文件名、写入内容保留原样。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    ublob write <name> [data]
        覆盖写。data 可空（0 字节文件）。data 可以有空格。
        例：ublob write bin hello world

    ublob append <name> [data]
        追加；文件不存在则等同 write。空 data 成功且不改文件。

    ublob read <name> <offset> <len>
        解压整包后切片。越界截断。

    ublob size <name>
    ublob stat <name>
    ublob list
    ublob usage
    ublob remove <name>
        不存在也算成功。

    ublob open <name>
        打开内存视图。同时只能开 1 个，先 view close 再开下一个。

    ublob view read <offset> <len>
    ublob view size
    ublob view crc32 [offset] [len]
    ublob view md5 [offset] [len] [raw]
        raw 写成 raw / 1 / true 则返回 16 字节，本 demo 打 hex。
    ublob view close

    ublob help

]=]

local rt = require("rt")
local uart = require("uart")
local ublob = require("ublob")

local UART_ID = uart.UART1
local CMD_TOPIC = "ublob_cmd"
local view

local function tohex(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    return (s:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
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

local function printable(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    if s:find("%z") or s:find("[\1-\31]") then
        return "hex:" .. tohex(s)
    end
    return s
end

local function ensure_view()
    if view then
        return true
    end
    reply(false, "还没有视图，请先 ublob open <name>")
    return false
end

local function cmd_write(name, data)
    if not name or name == "" then
        reply(false, "write：用法 ublob write <name> [data]")
        return
    end
    local ok, err = ublob.write(name, data or "")
    if not ok then
        reply(false, "write：%s", tostring(err))
        return
    end
    reply(true, "write %s n=%d", name, data and #data or 0)
end

local function cmd_append(name, data)
    if not name or name == "" then
        reply(false, "append：用法 ublob append <name> [data]")
        return
    end
    local ok, err = ublob.append(name, data or "")
    if not ok then
        reply(false, "append：%s", tostring(err))
        return
    end
    reply(true, "append %s n=%d", name, data and #data or 0)
end

local function cmd_read(name, off, len)
    if not name or name == "" or off == nil or len == nil then
        reply(false, "read：用法 ublob read <name> <offset> <len>")
        return
    end
    local data, nread, err = ublob.read(name, off, len)
    if err ~= nil then
        reply(false, "read：%s nread=%s", tostring(err), tostring(nread))
        return
    end
    reply(true, "read nread=%s data=%s", tostring(nread), printable(data))
end

local function cmd_size(name)
    if not name or name == "" then
        reply(false, "size：用法 ublob size <name>")
        return
    end
    local n, err = ublob.size(name)
    if n == nil then
        reply(false, "size：%s", tostring(err))
        return
    end
    reply(true, "size %s=%s", name, tostring(n))
end

local function cmd_stat(name)
    if not name or name == "" then
        reply(false, "stat：用法 ublob stat <name>")
        return
    end
    local st, err = ublob.stat(name)
    if not st then
        reply(false, "stat：%s", tostring(err))
        return
    end
    reply(true, "stat name=%s size=%s", st.name, tostring(st.size))
end

local function cmd_list()
    local items, err = ublob.list()
    if not items then
        reply(false, "list：%s", tostring(err))
        return
    end
    reply(true, "list n=%d", #items)
    for i = 1, #items do
        hint("  [%d] name=%s size=%s", i, items[i].name, tostring(items[i].size))
    end
end

local function cmd_usage()
    local u, err = ublob.usage()
    if not u then
        reply(false, "usage：%s", tostring(err))
        return
    end
    reply(true, "used=%s limit=%s script_used=%s shared_limit=%s",
          tostring(u.used), tostring(u.limit), tostring(u.script_used), tostring(u.shared_limit))
end

local function cmd_remove(name)
    if not name or name == "" then
        reply(false, "remove：用法 ublob remove <name>")
        return
    end
    local ok, err = ublob.remove(name)
    if not ok then
        reply(false, "remove：%s", tostring(err))
        return
    end
    reply(true, "remove %s", name)
end

local function cmd_open(name)
    if not name or name == "" then
        reply(false, "open：用法 ublob open <name>")
        return
    end
    -- 同时只能开 1 个；先关旧的，否则 API 会 too many open views
    if view then
        view:close()
        view = nil
    end
    local v, err = ublob.open(name)
    if not v then
        reply(false, "open：%s", tostring(err))
        return
    end
    view = v
    reply(true, "open %s size=%s", name, tostring(view:size()))
end

local function cmd_vread(off, len)
    if not ensure_view() then
        return
    end
    if off == nil or len == nil then
        reply(false, "view read：用法 ublob view read <offset> <len>")
        return
    end
    local data, nread, err = view:read(off, len)
    if err ~= nil then
        reply(false, "view read：%s nread=%s", tostring(err), tostring(nread))
        return
    end
    reply(true, "view read nread=%s data=%s", tostring(nread), printable(data))
end

local function cmd_vsize()
    if not ensure_view() then
        return
    end
    local n, err = view:size()
    if n == nil then
        reply(false, "view size：%s", tostring(err))
        return
    end
    reply(true, "view size=%s", tostring(n))
end

local function cmd_vcrc32(off, len)
    if not ensure_view() then
        return
    end
    local crc, err
    if off == nil then
        crc, err = view:crc32()
    elseif len == nil then
        crc, err = view:crc32(off)
    else
        crc, err = view:crc32(off, len)
    end
    if crc == nil then
        reply(false, "view crc32：%s", tostring(err))
        return
    end
    reply(true, "view crc32=0x%08X", crc)
end

local function cmd_vmd5(off, len, raw)
    if not ensure_view() then
        return
    end
    local digest, err
    if off == nil then
        digest, err = view:md5()
    elseif len == nil then
        digest, err = view:md5(off, nil, raw)
    else
        digest, err = view:md5(off, len, raw)
    end
    if digest == nil then
        reply(false, "view md5：%s", tostring(err))
        return
    end
    if raw then
        reply(true, "view md5 raw n=%d hex=%s", #digest, tohex(digest))
    else
        reply(true, "view md5 %s", digest)
    end
end

local function cmd_vclose()
    if not ensure_view() then
        return
    end
    view:close()
    view = nil
    reply(true, "view close")
end

local function print_help()
    local lines = {
        "",
        "==== UBLOB 指令 ====",
        "UART1 输入，回车发送",
        "",
        "ublob write <name> [data]",
        "ublob append <name> [data]",
        "ublob read <name> <offset> <len>",
        "ublob size <name>",
        "ublob stat <name>",
        "ublob list",
        "ublob usage",
        "ublob remove <name>",
        "ublob open <name>",
        "ublob view read <offset> <len>",
        "ublob view size",
        "ublob view crc32 [offset] [len]",
        "ublob view md5 [offset] [len] [raw]",
        "ublob view close",
        "ublob help",
        "",
        "同时只能 open 1 个视图；用完 view close",
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

local function parse_raw_flag(s)
    return s == "raw" or s == "1" or s == "true"
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    local verb, rest = lower:match("^ublob%s+(%S+)%s*(.-)%s*$")
    if not verb then
        reply(false, "未知指令: %s", cmd)
        hint("输入 ublob help")
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
    elseif verb == "write" then
        local name, data = cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Ww][Rr][Ii][Tt][Ee]%s+(%S+)%s+(.-)%s*$")
        if not name then
            name = cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Ww][Rr][Ii][Tt][Ee]%s+(%S+)%s*$")
            data = ""
        end
        cmd_write(name, data)
        return
    elseif verb == "append" then
        local name, data = cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Aa][Pp][Pp][Ee][Nn][Dd]%s+(%S+)%s+(.-)%s*$")
        if not name then
            name = cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Aa][Pp][Pp][Ee][Nn][Dd]%s+(%S+)%s*$")
            data = ""
        end
        cmd_append(name, data)
        return
    elseif verb == "read" then
        local name, off, len = cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Rr][Ee][Aa][Dd]%s+(%S+)%s+(%-?%d+)%s+(%-?%d+)%s*$")
        cmd_read(name, name and tonumber(off) or nil, name and tonumber(len) or nil)
        return
    elseif verb == "size" then
        cmd_size(cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Ss][Ii][Zz][Ee]%s+(%S+)%s*$"))
        return
    elseif verb == "stat" then
        cmd_stat(cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Ss][Tt][Aa][Tt]%s+(%S+)%s*$"))
        return
    elseif verb == "remove" then
        cmd_remove(cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Rr][Ee][Mm][Oo][Vv][Ee]%s+(%S+)%s*$"))
        return
    elseif verb == "open" then
        cmd_open(cmd:match("^[Uu][Bb][Ll][Oo][Bb]%s+[Oo][Pp][Ee][Nn]%s+(%S+)%s*$"))
        return
    elseif verb == "view" then
        local sub, vrest = rest:match("^(%S+)%s*(.-)%s*$")
        if sub == "read" then
            local off, len = vrest:match("^(%-?%d+)%s+(%-?%d+)$")
            cmd_vread(off and tonumber(off) or nil, len and tonumber(len) or nil)
        elseif sub == "size" then
            cmd_vsize()
        elseif sub == "crc32" then
            local off, len = vrest:match("^(%-?%d+)%s+(%-?%d+)$")
            if off then
                cmd_vcrc32(tonumber(off), tonumber(len))
            else
                off = vrest:match("^(%-?%d+)$")
                cmd_vcrc32(off and tonumber(off) or nil, nil)
            end
        elseif sub == "md5" then
            local off, len, raws = vrest:match("^(%-?%d+)%s+(%-?%d+)%s+(%S+)$")
            if off then
                cmd_vmd5(tonumber(off), tonumber(len), parse_raw_flag(raws))
            else
                off, raws = vrest:match("^(%-?%d+)%s+(%S+)$")
                if off and parse_raw_flag(raws) then
                    cmd_vmd5(tonumber(off), nil, true)
                else
                    off = vrest:match("^(%-?%d+)$")
                    if off then
                        cmd_vmd5(tonumber(off), nil, false)
                    elseif parse_raw_flag(vrest) then
                        cmd_vmd5(0, nil, true)
                    else
                        cmd_vmd5(nil, nil, false)
                    end
                end
            end
        elseif sub == "close" then
            cmd_vclose()
        else
            reply(false, "未知 view 子命令，用法 ublob view read|size|crc32|md5|close")
        end
        return
    end

    reply(false, "未知指令: %s", cmd)
    hint("输入 ublob help")
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
  ublob 指令 Demo — UART1 驱动字节 blob

  require("ublob")。存原始字节。落盘 CREC(FastLZ)，前缀 lua_bin_*。
  与 lua 脚本、ufs 共用 220KiB 配额（压缩后落盘）。
  可写空间 = 220KiB − lua 脚本落盘。单文件解压明文上限 256KiB。
  文件名禁止 '/' '\\' ':' 控制字符和 ".."。与 ufs 命名空间分开。

  ----------------------------------------------------------------------------
  串口指令（本 demo）
  ----------------------------------------------------------------------------
    回调里只 mbox_send，真正 ublob.* / view:* 都在协程里做。
    write / append 的 data 从动词后第二个空格起原样保留，可含空格；省略则为空串。
    view 相关命令操作当前 open 的那一个。同时只能开 1 个（LUA_UBLOB_MAX_OPEN_VIEWS=1）。
    本 demo 再 open 时若已有视图会先 close 旧的，避免卡死名额。
    二进制/控制字符 read 结果会打成 hex:xx。

  ----------------------------------------------------------------------------
  ublob.write(name, data) -> ok, err
  ----------------------------------------------------------------------------
    覆盖写。data 为 string，允许空串和内部 \0。成功 true, nil；失败 false, err。
    "quota exceeded" / "invalid param" / "io error" / "no mem"。

  ----------------------------------------------------------------------------
  ublob.append(name, data) -> ok, err
  ----------------------------------------------------------------------------
    追加；不存在则当 write。空 data 成功无操作。
    实现是整包读出再写回，大文件会占 RAM。

  ----------------------------------------------------------------------------
  ublob.read(name, offset, len) -> data, nread, err
  ----------------------------------------------------------------------------
    三返回值。offset/len 必填且 ≥0。整包解压后切片，越界截断。
    超出末尾或 len=0："" , 0, nil。失败 nil, 0, err。

  ----------------------------------------------------------------------------
  ublob.open(name) -> view | nil, err
  ----------------------------------------------------------------------------
    解压到 C 堆。已有未关视图 → "too many open views"（API 本身；
    本 demo 会先关旧视图）。空文件可 open。

  ----------------------------------------------------------------------------
  view:read(offset, len) -> data, nread, err
  view:size() -> n | nil, err
  view:crc32([offset], [len]) -> crc | nil, err
  view:md5([offset], [len], [raw]) -> digest | nil, err
  view:close() -> true
  ----------------------------------------------------------------------------
    crc32：IEEE，与 tls.crc32 默认一致，C 缓冲计算不进 Lua 堆。
    md5：默认 hex；raw=true 为 16B。未编译 mbedtls MD5 → "md5 not enabled"。
    无参=整包；只给 offset=到末尾。已 close → "closed"。
    整包 raw：view:md5(0, nil, true) 或指令 ublob view md5 raw。

  ----------------------------------------------------------------------------
  ublob.size / stat / remove / list / usage
  ----------------------------------------------------------------------------
    size/stat 的 size 是明文长度。stat 无 is_dir。
    remove 不存在也 true。list 只含 blob。
    usage 与 ufs.usage() 相同：used/limit 为 ufs+ublob 合计，shared_limit=220KiB。

  ============================================================================
  本 demo
  ============================================================================
    上电打印帮助。建议：
    ublob write bin hello → ublob append bin  world → ublob read bin 0 16
    → ublob open bin → ublob view md5 → ublob view crc32 → ublob view close
    → ublob list → ublob remove bin。
    不要循环写大块，配额按压缩后占用。

]=]
