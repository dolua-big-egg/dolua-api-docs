--[=[
  tcp 指令 Demo — UART1 收指令，协程里执行动作

  和同目录 tcp_api demo 用同一套 tcp API、同一套对端：
    host        tcp.doiot.cn
    port        见下方 PORT（网页端测试服刷新后端口会变，记得同步改）

  差别：本 demo 不自动 create/open，完全由串口指令驱动。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay / wait_connect / 同步 send）
      → rt.mbox_send 投到指令协程
      → 协程 mbox_recv 后按文本执行 tcp.create / open / send / close / delete
      → 成功或失败通过 UART1 回写提示

  指令不区分大小写；行首行尾空白和 \r\n 会去掉。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    tcp create
        创建实例并拉起托管线程（线程先挂起，这时还不连网）。
        成功只表示对象建好了，不等于已连接。重复 create 会失败。

    tcp open
        把目标设成「要连上」，叫醒线程去连 tcp.doiot.cn:PORT。
        返回成功只表示已交给内部；本 demo 会再 wait_connect 最多 20 秒，
        把是否真正连上打印出来。超时后内部仍会自动重连。

    tcp send <内容>
        把 "tcp send" 后面一个空格之后的全部内容，同步发给对端。
        例：tcp send hello world  → 发出 "hello world"
        未连接或没有内容会失败。不要在 tcp 回调里调这条指令对应的同步 send。

    tcp close
        停止托管并断开。之后要再连，必须再 open。

    tcp delete
        销毁实例（含线程），对象作废。之后必须重新 create。
        暂时断开请用 close，不要 delete。

  tcp 事件（connected / disconnected / data / error）也会打到 UART1。
  收到对端数据时只打印，不自动回包。

]=]

local rt = require("rt")
local uart = require("uart")
local tcp = require("tcp")

-- 与 tcp_api demo 同一测试服务器：http://tcp.doiot.cn/ 注意要点了网页的【启动】按钮才能连的上喔。
-- 网页刷新时端口会变，记得同步改 PORT。
local HOST = "tcp.doiot.cn"
local PORT = 26991
local UART_ID = uart.UART1
local CMD_TOPIC = "tcp_cmd"
local WAIT_CONNECT_MS = 20000

local c

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
end

local function on_tcp(ev)
    if not ev then
        return
    end
    if ev.event == "connected" then
        hint("event connected ip=%s port=%s", tostring(ev.ip), tostring(ev.port))
    elseif ev.event == "disconnected" then
        hint("event disconnected")
    elseif ev.event == "error" then
        hint("event error code=%s", tostring(ev.code))
    elseif ev.event == "data" then
        hint("event data n=%d data=%s", ev.data and #ev.data or 0, tostring(ev.data))
    end
end

local function ensure_client()
    if c then
        return true
    end
    reply(false, "还没有实例，请先执行 tcp create")
    return false
end

local function cmd_create()
    if c then
        reply(false, "create：实例已存在，先 tcp delete 再创建")
        return
    end
    local err
    c, err = tcp.create(on_tcp, {
        reconnect_interval_ms = 5000,
        poll_interval_ms = 30,
        connect_timeout_ms = 5000,
        link_wait_timeout_ms = 60000,
        recv_buffer_size = 2048,
        keepalive_enable = true,
        keepalive_idle = 60,
        keepalive_interval = 10,
        keepalive_count = 3,
    })
    if not c then
        reply(false, "create：%s", tostring(err))
        return
    end
    reply(true, "create：实例已创建（尚未连接）")
end

local function cmd_open()
    if not ensure_client() then
        return
    end
    local ok, err = c:open(HOST, PORT)
    if not ok then
        reply(false, "open：%s", tostring(err))
        return
    end
    hint("open：已交给内部去连 %s:%d，等待 connected ...", HOST, PORT)
    local ready = c:wait_connect(WAIT_CONNECT_MS)
    if ready then
        reply(true, "open：已连接 status=%s", tostring(c:status()))
    else
        reply(false, "open：%d ms 内未连上，内部仍会自动重连 status=%s",
              WAIT_CONNECT_MS, tostring(c:status()))
    end
end

local function cmd_send(payload)
    if not ensure_client() then
        return
    end
    if not payload or payload == "" then
        reply(false, "send：缺少内容，用法 tcp send <内容>")
        return
    end
    if not c:status() then
        reply(false, "send：未连接，请先 tcp open")
        return
    end
    local n, err = c:send(payload)
    if not n then
        reply(false, "send：%s", tostring(err))
        return
    end
    reply(true, "send：n=%s payload=%s", tostring(n), payload)
end

local function cmd_close()
    if not ensure_client() then
        return
    end
    local ok, err = c:close()
    if not ok then
        reply(false, "close：%s", tostring(err))
        return
    end
    reply(true, "close：已断开，托管已停止")
end

local function cmd_delete()
    if not ensure_client() then
        return
    end
    c:delete()
    c = nil
    reply(true, "delete：实例已销毁")
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    if lower == "tcp create" then
        cmd_create()
    elseif lower == "tcp open" then
        cmd_open()
    elseif lower == "tcp close" then
        cmd_close()
    elseif lower == "tcp delete" then
        cmd_delete()
    else
        local payload = cmd:match("^[Tt][Cc][Pp]%s+[Ss][Ee][Nn][Dd]%s(.*)$")
        if payload ~= nil then
            cmd_send(payload)
        else
            reply(false, "未知指令: %s", cmd)
            hint("可用: tcp create | tcp open | tcp send <内容> | tcp close | tcp delete")
        end
    end
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

local function print_help()
    local lines = {
        "",
        "==== TCP 指令 ====",
        "UART1 输入，回车发送",
        "",
        "tcp create",
        "  创建实例",
        "tcp open",
        "  连接服务器",
        "tcp send <内容>",
        "  发送内容",
        "tcp close",
        "  断开连接",
        "tcp delete",
        "  销毁实例",
        "",
        "server: " .. HOST .. ":" .. tostring(PORT),
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
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
