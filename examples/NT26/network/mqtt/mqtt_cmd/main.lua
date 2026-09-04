--[=[
  mqtt 指令 Demo — UART1 收指令，协程里执行动作

  和同目录 mqtt_client demo 用同一套 mqtt API、同一套对端：
    host        mqtts.doiot.cn:1883
    用户名/密码 doiot / web
    client_id   设备 IMEI
    发布主题    /device/<IMEI>
    订阅主题    /server/<IMEI>

  差别：本 demo 不自动 create/open，完全由串口指令驱动。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay / wait_connect / 同步 pub）
      → rt.mbox_send 投到指令协程
      → 协程 mbox_recv 后按文本执行 mqtt.create / open / sub / pub / close / delete
      → 成功或失败通过 UART1 回写提示

  指令不区分大小写；行首行尾空白和 \r\n 会去掉。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    mqtt create
        创建实例并拉起托管线程（线程先挂起，这时还不连网）。
        成功只表示对象建好了，不等于已连接。重复 create 会失败。

    mqtt open
        把目标设成「要连上」，叫醒线程去连 mqtts.doiot.cn:1883。
        返回成功只表示已交给内部；本 demo 会再 wait_connect 最多 20 秒，
        把是否真正连上打印出来。超时后内部仍会自动重连。

    mqtt sub now
        立刻订阅 /server/<IMEI>。
        now = 马上对当前会话发 SUBSCRIBE，同时写入 auto_sub，
        以后每次 connected（含掉线重连）都会自动再订。
        还没连上时：只写入 auto_sub，等连上后再订。

    mqtt pub <内容>
        把 "mqtt pub" 后面一个空格之后的全部内容，发布到 /device/<IMEI>。
        例：mqtt pub hello world  → payload 为 "hello world"
        未连接或没有内容会失败。不要在 mqtt 回调里调这条指令对应的同步 pub。

    mqtt close
        停止托管并断开。之后要再连，必须再 open。

    mqtt delete
        销毁实例（含线程），对象作废。之后必须重新 create。
        暂时断开请用 close，不要 delete。

  mqtt 事件（connected / disconnected / message / error）也会打到 UART1。
  收到 /server/<IMEI> 的下行时只打印，不自动回包。

]=]

local rt = require("rt")
local uart = require("uart")
local mqtt = require("mqtt")
local info = require("info")

-- 与 mqtt_client demo 同一测试服务器：http://mqtts.doiot.cn/
local HOST = "mqtts.doiot.cn"
local PORT = 1883
local USERNAME = "doiot"
local PASSWORD = "web"
local UART_ID = uart.UART1
local CMD_TOPIC = "mqtt_cmd"
local WAIT_CONNECT_MS = 20000

local c
local CLIENT_ID
local TOPIC_PUB
local TOPIC_SUB

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
end

local function on_mqtt(ev)
    if not ev then
        return
    end
    if ev.event == "pre_connect" then
        hint("event pre_connect")
    elseif ev.event == "connected" then
        hint("event connected")
    elseif ev.event == "disconnected" then
        hint("event disconnected")
    elseif ev.event == "error" then
        hint("event error code=%s", tostring(ev.code))
    elseif ev.event == "message" then
        hint("event message topic=%s n=%d data=%s",
             tostring(ev.mqtt_topic), ev.data and #ev.data or 0, tostring(ev.data))
    end
end

local function ensure_client()
    if c then
        return true
    end
    reply(false, "还没有实例，请先执行 mqtt create")
    return false
end

local function cmd_create()
    if c then
        reply(false, "create：实例已存在，先 mqtt delete 再创建")
        return
    end
    local err
    c, err = mqtt.create(on_mqtt, {
        reconnect_interval_ms = 5000,
        poll_interval_ms = 30,
        connect_timeout_ms = 5000,
        keepalive_interval = 60,
        clean_session = true,
        send_buffer_size = 4096,
        recv_buffer_size = 4096,
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
    local ok, err = c:open(HOST, PORT, CLIENT_ID, USERNAME, PASSWORD)
    if not ok then
        reply(false, "open：%s", tostring(err))
        return
    end
    hint("open：已交给内部去连 %s:%d id=%s，等待 connected ...",
         HOST, PORT, tostring(CLIENT_ID))
    local ready = c:wait_connect(WAIT_CONNECT_MS)
    if ready then
        reply(true, "open：已连接 status=%s", tostring(c:status()))
    else
        reply(false, "open：%d ms 内未连上，内部仍会自动重连 status=%s",
              WAIT_CONNECT_MS, tostring(c:status()))
    end
end

local function cmd_sub_now()
    if not ensure_client() then
        return
    end
    local ok, err = c:auto_sub({
        { topic = TOPIC_SUB, qos = 0 },
    })
    if not ok then
        reply(false, "sub now：auto_sub 失败 %s", tostring(err))
        return
    end
    if c:status() then
        local sok, serr = c:sub(TOPIC_SUB, 0)
        if not sok then
            reply(false, "sub now：当前会话订阅失败 %s（auto_sub 已写入）", tostring(serr))
            return
        end
        reply(true, "sub now：已订阅 %s qos=0（含 auto_sub）", TOPIC_SUB)
        return
    end
    reply(true, "sub now：已写入 auto_sub %s，连上后会自动订阅", TOPIC_SUB)
end

local function cmd_pub(payload)
    if not ensure_client() then
        return
    end
    if not payload or payload == "" then
        reply(false, "pub：缺少内容，用法 mqtt pub <内容>")
        return
    end
    if not c:status() then
        reply(false, "pub：未连接，请先 mqtt open")
        return
    end
    local ok, err = c:pub(TOPIC_PUB, payload, 0, 0)
    if not ok then
        reply(false, "pub：%s", tostring(err))
        return
    end
    reply(true, "pub：topic=%s payload=%s", TOPIC_PUB, payload)
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

    if lower == "mqtt create" then
        cmd_create()
    elseif lower == "mqtt open" then
        cmd_open()
    elseif lower == "mqtt sub now" then
        cmd_sub_now()
    elseif lower == "mqtt close" then
        cmd_close()
    elseif lower == "mqtt delete" then
        cmd_delete()
    else
        local payload = cmd:match("^[Mm][Qq][Tt][Tt]%s+[Pp][Uu][Bb]%s(.*)$")
        if payload ~= nil then
            cmd_pub(payload)
        else
            reply(false, "未知指令: %s", cmd)
            hint("可用: mqtt create | mqtt open | mqtt sub now | mqtt pub <内容> | mqtt close | mqtt delete")
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
        "==== MQTT 指令 ====",
        "UART1 输入，回车发送",
        "",
        "mqtt create",
        "  创建实例",
        "mqtt open",
        "  连接服务器",
        "mqtt sub now",
        "  立即订阅",
        "mqtt pub <内容>",
        "  发布内容",
        "mqtt close",
        "  断开连接",
        "mqtt delete",
        "  销毁实例",
        "",
        "broker: " .. HOST .. ":" .. tostring(PORT),
        "id: " .. tostring(CLIENT_ID),
        "pub: " .. tostring(TOPIC_PUB),
        "sub: " .. tostring(TOPIC_SUB),
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

CLIENT_ID = info.imei()
if not CLIENT_ID or CLIENT_ID == "" then
    CLIENT_ID = "lua-mqtt-cmd"
end
TOPIC_PUB = "/device/" .. CLIENT_ID
TOPIC_SUB = "/server/" .. CLIENT_ID

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
