--[=[
  rtu 指令 Demo — UART1 收指令，协程里操作透传通道

  和同目录 rtu_api 用同一套 rtu API。
  差别：本 demo 不自动发数；write / socket / mqtt / control 全由串口触发。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 wait_connect / socket_sync）
      → rt.mbox_send 投到指令协程
      → 协程里执行 rtu.*
      → 成功或失败通过 UART1 回写
    通道事件（online/offline/data）也会打到 UART1。收到数据只打印，不自动回包。

  上电会把 pass_up / pass_down 设成 false（仅本次），避免透传抢走指令。
  不写 pass_*_cfg。uart2/3_en_cfg 和 pass_*_cfg 只有你显式 rtu opt 写入才会落盘。

]=]

local rt = require("rt")
local uart = require("uart")
local rtu = require("rtu")

local UART_ID = uart.UART1
local CMD_TOPIC = "rtu_cmd"
local WAIT_DEFAULT_MS = 10000

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
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

local function rc_ok(n)
    return n == 0
end

local function on_ch(id, data, meta)
    meta = meta or {}
    hint("event ch=%s %s type=%s topic=%s host=%s:%s n=%s data=%s",
         tostring(id), tostring(meta.event), tostring(meta.type),
         tostring(meta.topic), tostring(meta.host), tostring(meta.port),
         type(data) == "string" and #data or 0, tostring(data))
end

local function cmd_opt(key, val)
    if not key or key == "" then
        reply(false, "opt：用法 rtu opt <key> [0|1|true|false]")
        return
    end
    if val == nil then
        local ok, v, e = pcall(rtu.option, key)
        if not ok then
            reply(false, "opt：%s", tostring(v))
            return
        end
        if v == nil then
            reply(false, "opt %s err=%s", key, tostring(e))
            return
        end
        reply(true, "opt %s=%s", key, tostring(v))
        if key:find("_cfg", 1, true) then
            hint("  这是落盘项；写入会改 NVM，uart*_en_cfg 还要重启才生效")
        end
        return
    end
    local okb, b = parse_bool(val)
    if not okb then
        reply(false, "opt：value 用 0/1/true/false")
        return
    end
    local ok, rc = pcall(rtu.option, key, b)
    if not ok then
        reply(false, "opt：%s", tostring(rc))
        return
    end
    reply(rc_ok(rc), "opt write %s=%s rc=%s", key, tostring(b), tostring(rc))
end

local function cmd_connect()
    for id = 1, 4 do
        hint("  ch%d is_connect=%s", id, tostring(rtu.is_connect(id)))
    end
    reply(true, "connect dumped")
end

local function cmd_wait(id, ms)
    if not id or id < 1 or id > 4 then
        reply(false, "wait：用法 rtu wait <1-4> [ms|-1]")
        return
    end
    if ms == nil then
        ms = WAIT_DEFAULT_MS
    end
    hint("wait_connect ch=%d ms=%s ...", id, tostring(ms))
    local ok = rtu.wait_connect(id, ms)
    reply(ok, "wait_connect ch=%d %s", id, ok and "online" or "timeout")
end

local function cmd_ctl(id, cmd)
    if not id or id < 1 or id > 4 or (cmd ~= 0 and cmd ~= 1) then
        reply(false, "ctl：用法 rtu ctl <1-4> <0挂起|1恢复>")
        return
    end
    local rc = rtu.control(id, cmd)
    reply(rc_ok(rc), "control ch=%d cmd=%s rc=%s", id, cmd == 0 and "suspend" or "resume", tostring(rc))
end

local function cmd_write(route, data)
    if not route or route == "" or not data or data == "" then
        reply(false, "write：用法 rtu write <route> <data>  例 rtu write 1 hello")
        return
    end
    local ok, err = pcall(rtu.write, route, data)
    if not ok then
        reply(false, "write：%s", tostring(err))
        return
    end
    reply(true, "write route=%s n=%d", route, #data)
end

local function cmd_up(uart_id, data)
    if not uart_id or uart_id < 1 or uart_id > 3 or not data or data == "" then
        reply(false, "up：用法 rtu up <1-3> <data>")
        return
    end
    local ok, err = pcall(rtu.update_write, uart_id, data)
    if not ok then
        reply(false, "up：%s", tostring(err))
        return
    end
    reply(true, "update_write uart=%d n=%d", uart_id, #data)
end

local function cmd_down(id, data)
    if not id or id < 1 or id > 4 or not data or data == "" then
        reply(false, "down：用法 rtu down <1-4> <data>")
        return
    end
    local ok, err = pcall(rtu.down_write, id, data)
    if not ok then
        reply(false, "down：%s", tostring(err))
        return
    end
    reply(true, "down_write ch=%d n=%d", id, #data)
end

local function cmd_sock(id, data, async)
    if not id or id < 1 or id > 4 or not data or data == "" then
        reply(false, "sock：用法 rtu sock[a] <1-4> <data>")
        return
    end
    local rc
    if async then
        rc = rtu.socket_async(id, data)
    else
        rc = rtu.socket_sync(id, data)
    end
    reply(rc >= 0, "%s ch=%d rc=%s", async and "socket_async" or "socket_sync", id, tostring(rc))
end

local function cmd_mqtt(id, topic, data, qos, retain, async)
    if not id or id < 1 or id > 4 or not topic or topic == "" then
        reply(false, "mqtt：用法 rtu mqtt[a] <1-4> <topic> <data> [qos 0-2] [retain 0|1]")
        return
    end
    qos = qos or 0
    retain = retain or 0
    local rc
    if async then
        rc = rtu.mqtt_async(id, topic, data, qos, retain)
    else
        rc = rtu.mqtt_sync(id, topic, data, qos, retain)
    end
    reply(rc_ok(rc) or rc >= 0, "%s ch=%d topic=%s rc=%s",
          async and "mqtt_async" or "mqtt_sync", id, topic, tostring(rc))
end

local function cmd_sub(id, topic, qos)
    if not id or id < 1 or id > 4 or not topic or topic == "" then
        reply(false, "sub：用法 rtu sub <1-4> <topic> [qos]")
        return
    end
    local rc = rtu.mqtt_sub(id, topic, qos or 0)
    reply(rc_ok(rc) or rc >= 0, "mqtt_sub ch=%d topic=%s qos=%s rc=%s",
          id, topic, tostring(qos or 0), tostring(rc))
end

local function cmd_unsub(id, topic)
    if not id or id < 1 or id > 4 or not topic or topic == "" then
        reply(false, "unsub：用法 rtu unsub <1-4> <topic>")
        return
    end
    local rc = rtu.mqtt_unsub(id, topic)
    reply(rc_ok(rc) or rc >= 0, "mqtt_unsub ch=%d topic=%s rc=%s", id, topic, tostring(rc))
end

local function cmd_reg(id, on)
    if not id or id < 1 or id > 4 then
        reply(false, "reg：用法 rtu reg|unreg <1-4>")
        return
    end
    if on then
        local ok, err = pcall(rtu.reg_chcb, id, on_ch)
        if not ok then
            reply(false, "reg：%s", tostring(err))
            return
        end
        reply(true, "reg_chcb ch=%d", id)
    else
        reply(rtu.unreg_chcb(id), "unreg_chcb ch=%d", id)
    end
end

local function print_help()
    local lines = {
        "",
        "==== RTU 指令 ====",
        "UART1 输入，回车发送。通道 1-4 须已在模组 RTU 里配置。",
        "",
        "rtu opt <key> [0|1]     pass_up/down 本次；*_cfg 会落盘",
        "rtu connect             扫 4 路 is_connect",
        "rtu wait <id> [ms|-1]   等连接，默认 10000ms",
        "rtu ctl <id> <0|1>      0 挂起 1 恢复",
        "rtu write <route> <data>  路由发  例 rtu write 1 hello",
        "rtu up <1-3> <data>     update_write 当串口上报",
        "rtu down <id> <data>    down_write 当通道下发",
        "rtu sock <id> <data>    socket 同步发（TCP/UDP）",
        "rtu socka <id> <data>   socket 异步入队",
        "rtu mqtt <id> <topic> <data> [qos] [retain]",
        "rtu mqtta ...           mqtt 异步",
        "rtu sub <id> <topic> [qos]",
        "rtu unsub <id> <topic>",
        "rtu reg <id>            注册通道回调",
        "rtu unreg <id>",
        "rtu help",
        "",
        "route: 1  1|2  6[1]=UART1  5=HTTP  7=短信",
        "sync 发送不要在回调里调；回包用 socka / mqtta",
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

local function parse_mqtt_tail(tail)
    if not tail or tail == "" then
        return "", 0, 0
    end
    local data, q, r = tail:match("^(.-)%s+([012])%s+([01])$")
    if data then
        return data, tonumber(q), tonumber(r)
    end
    return tail, 0, 0
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    local verb = lower:match("^rtu%s+(%S+)")
    if not verb then
        reply(false, "未知指令: %s", cmd)
        hint("输入 rtu help")
        return
    end

    if verb == "help" then
        print_help()
        return
    elseif verb == "connect" then
        cmd_connect()
        return
    elseif verb == "opt" then
        local key, val = lower:match("^rtu%s+opt%s+(%S+)%s+(%S+)$")
        if not key then
            key = lower:match("^rtu%s+opt%s+(%S+)$")
        end
        cmd_opt(key, val)
        return
    elseif verb == "wait" then
        local id, ms = lower:match("^rtu%s+wait%s+(%d+)%s+(%-?%d+)$")
        if id then
            cmd_wait(tonumber(id), tonumber(ms))
        else
            cmd_wait(tonumber(lower:match("^rtu%s+wait%s+(%d+)$")), nil)
        end
        return
    elseif verb == "ctl" then
        local id, c = lower:match("^rtu%s+ctl%s+(%d+)%s+([01])$")
        cmd_ctl(id and tonumber(id) or nil, c and tonumber(c) or nil)
        return
    elseif verb == "write" then
        local route, data = cmd:match("^[Rr][Tt][Uu]%s+[Ww][Rr][Ii][Tt][Ee]%s+(%S+)%s+(.-)%s*$")
        cmd_write(route, data)
        return
    elseif verb == "up" then
        local uid, data = cmd:match("^[Rr][Tt][Uu]%s+[Uu][Pp]%s+(%d+)%s+(.-)%s*$")
        cmd_up(uid and tonumber(uid) or nil, data)
        return
    elseif verb == "down" then
        local id, data = cmd:match("^[Rr][Tt][Uu]%s+[Dd][Oo][Ww][Nn]%s+(%d+)%s+(.-)%s*$")
        cmd_down(id and tonumber(id) or nil, data)
        return
    elseif verb == "sock" or verb == "socka" then
        local id, data = cmd:match("^[Rr][Tt][Uu]%s+[Ss][Oo][Cc][Kk][Aa]?%s+(%d+)%s+(.-)%s*$")
        cmd_sock(id and tonumber(id) or nil, data, verb == "socka")
        return
    elseif verb == "mqtt" or verb == "mqtta" then
        local id, topic, tail = cmd:match("^[Rr][Tt][Uu]%s+[Mm][Qq][Tt][Tt][Aa]?%s+(%d+)%s+(%S+)%s+(.-)%s*$")
        local data, qos, retain = parse_mqtt_tail(tail)
        cmd_mqtt(id and tonumber(id) or nil, topic, data, qos, retain, verb == "mqtta")
        return
    elseif verb == "sub" then
        local id, topic, qos = cmd:match("^[Rr][Tt][Uu]%s+[Ss][Uu][Bb]%s+(%d+)%s+(%S+)%s+(%d+)%s*$")
        if not id then
            id, topic = cmd:match("^[Rr][Tt][Uu]%s+[Ss][Uu][Bb]%s+(%d+)%s+(%S+)%s*$")
        end
        cmd_sub(id and tonumber(id) or nil, topic, qos and tonumber(qos) or 0)
        return
    elseif verb == "unsub" then
        local id, topic = cmd:match("^[Rr][Tt][Uu]%s+[Uu][Nn][Ss][Uu][Bb]%s+(%d+)%s+(%S+)%s*$")
        cmd_unsub(id and tonumber(id) or nil, topic)
        return
    elseif verb == "reg" then
        cmd_reg(tonumber(lower:match("^rtu%s+reg%s+(%d+)$")), true)
        return
    elseif verb == "unreg" then
        cmd_reg(tonumber(lower:match("^rtu%s+unreg%s+(%d+)$")), false)
        return
    end

    reply(false, "未知指令: %s", cmd)
    hint("输入 rtu help")
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

rtu.option("pass_up", false)
rtu.option("pass_down", false)

for id = 1, 4 do
    pcall(rtu.reg_chcb, id, on_ch)
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
hint("UART1 已注册；pass_up/down 本次=false")

while true do
    rt.delay(60000)
end

--[=[
  rtu 指令 Demo — UART1 驱动透传通道

  require("rtu")。通道 1..4 是模组 RTU 任务（TCP/UDP/MQTT），须事先配置。
  Lua id 全是 1-based，C 内部 0-based。

  ----------------------------------------------------------------------------
  串口指令
  ----------------------------------------------------------------------------
    回调只 mbox_send。wait_connect / socket_sync / mqtt_sync 只在协程里跑。
    上电把 pass_up/pass_down 设 false（本次、不落盘），免得透传吃掉指令。

  ----------------------------------------------------------------------------
  rtu.option(key [, bool])
  ----------------------------------------------------------------------------
    pass_up / pass_down           运行时透传，不落盘
    pass_up_cfg / pass_down_cfg   落盘，不立刻改运行时
    uart2_en_cfg / uart3_en_cfg   落盘，重启生效
    读：bool | nil,err   写：int（0=OK）  非法 key 抛错

  ----------------------------------------------------------------------------
  rtu.is_connect / state(id) -> bool
  rtu.wait_connect(id [, timeout_ms]) -> bool
  rtu.control(id, 0|1) -> int
  ----------------------------------------------------------------------------
    wait 已连立刻 true；否则 yield，ONLINE 唤醒。-1 一直等。
    control 0=挂起 1=恢复。返回 0=RTU_TASK_OK，-2 参数，-3 未启用。

  ----------------------------------------------------------------------------
  rtu.write(route, data) -> true   非法 route 抛错
  ----------------------------------------------------------------------------
    按路由转发。格式：
      "1" "2" "1|2"          通道 1/2（透传任务）
      "1[1:2]"               通道 1 的子通道 1 和 2
      "6[1]" "6[2]" "6[3]"   UART1/2/3
      "5"                    HTTP
      "7"                    短信
    空串表示不选任何通道。

  rtu.update_write(uart_id, data)  假装从 UART1..3 上报，走上报路由
  rtu.down_write(channel_id, data) 假装从通道 1..4 下发，走下发路由
    数据长度必须 >0。

  ----------------------------------------------------------------------------
  rtu.socket_sync(id, data) -> int     >=0 发出字节数；<0 失败
  rtu.socket_async(id, data) -> int    0 已入队；<0 失败
  ----------------------------------------------------------------------------
    仅 TCP/UDP 通道。未连接 / 类型不对会失败。
    同步不要在 chcb 里调。

  ----------------------------------------------------------------------------
  rtu.mqtt_sync(id, topic, data, qos, retain) -> int
  rtu.mqtt_async(...)
  rtu.mqtt_sub(id, topic, qos) / rtu.mqtt_unsub(id, topic)
  ----------------------------------------------------------------------------
    qos 0..2，retain 0/1。data 可以是空（发空 payload）。
    没有 auto_sub Lua API（CONNECT 后由 rtu 自己维护自动订阅）。

  ----------------------------------------------------------------------------
  rtu.reg_chcb(id, cb) / unreg_chcb(id)
  ----------------------------------------------------------------------------
    cb(id, data, meta)  meta.event=online|offline|data  type=tcp|udp|mqtt
    已连接时注册会立刻补 online。回调里禁止 sync 发送和 wait_connect。

  ============================================================================
  本 demo
  ============================================================================
    上电关本次透传、注册 4 路回调、打印帮助。
    建议：rtu connect → rtu wait 1 15000 → rtu sock 1 hello
    或 MQTT：rtu sub 1 demo/down → rtu mqtt 1 demo/up hello
    *_cfg 写入会改 NVM，不要当开关乱拧。

]=]
