--[=[
  sms 指令 Demo — UART1 收指令，协程里发短信

  和同目录 sms_api 用同一套 sms API。
  差别：本 demo 不自动发，完全由串口指令驱动。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay / 同步 sms.send）
      → rt.mbox_send 投到指令协程
      → 协程 mbox_recv 后执行 sms.send_async
      → 入队成功或失败通过 UART1 回写；真正发出去看 SEND_DONE / SEND_FAILED 

  指令不区分大小写；行首行尾空白和 \r\n 会去掉。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    sms send <号码> <内容>
        异步发一条短信。号码和正文之间一个空格，正文可以有空格。
        例：sms send 13800138000 hello world
        返回成功只表示已入队，不等于对方已收到。
        必须用手机卡，物联网卡一般发不了。不要写循环一直发。

  短信事件（NEW_SMS / SEND_DONE / SEND_FAILED）也会打到 UART1。
  收到短信时只打印，不自动回信。

]=]

local rt = require("rt")
local uart = require("uart")
local sms = require("sms")

local UART_ID = uart.UART1
local CMD_TOPIC = "sms_cmd"
local tag_seq = 0

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
end

local function ev_name(id)
    if id == sms.EVENT_NEW_SMS then
        return "NEW_SMS"
    elseif id == sms.EVENT_SEND_DONE then
        return "SEND_DONE"
    elseif id == sms.EVENT_SEND_FAILED then
        return "SEND_FAILED" --发送失败
    end
    return tostring(id)
end

local function ret_name(ret)
    if ret == sms.ERR_OK then
        return "OK"
    elseif ret == sms.ERR_NET_NOT_ATTACHED then
        return "NET_NOT_ATTACHED"
    end
    return tostring(ret)
end

local function on_sms(ev)
    if not ev then
        return
    end
    hint("event %s sms_id=%s sender=%s tag=%s text=%s",
         ev_name(ev.event_id), tostring(ev.sms_id),
         tostring(ev.sender), tostring(ev.user_tag), tostring(ev.text))
end

local function cmd_send(da, text)
    if not da or da == "" then
        reply(false, "send：缺少号码，用法 sms send <号码> <内容>")
        return
    end
    if not text or text == "" then
        reply(false, "send：缺少内容，用法 sms send <号码> <内容>")
        return
    end
    tag_seq = tag_seq + 1
    local ret = sms.send_async(da, text, 30, tag_seq)
    if ret ~= sms.ERR_OK then
        reply(false, "send_async：%s da=%s", ret_name(ret), da)
        return
    end
    reply(true, "send_async：已入队 da=%s tag=%d text=%s", da, tag_seq, text)
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    hint("recv: %s", cmd)

    local da, text = cmd:match("^[Ss][Mm][Ss]%s+[Ss][Ee][Nn][Dd]%s+(%S+)%s+(.-)%s*$")
    if da ~= nil then
        cmd_send(da, text)
        return
    end
    if cmd:lower():match("^sms%s+send") then
        reply(false, "send：缺少号码或内容，用法 sms send <号码> <内容>")
        return
    end
    reply(false, "未知指令: %s", cmd)
    hint("可用: sms send <号码> <内容>")
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
        "==== SMS 指令 ====",
        "UART1 输入，回车发送",
        "",
        "sms send <号码> <内容>",
        "  异步发短信，结果看 SEND_DONE / SEND_FAILED",
        "",
        "例: sms send 13800138000 hello",
        "须手机卡；不要循环连发",
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

print_help()

sms.reg(on_sms)

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
