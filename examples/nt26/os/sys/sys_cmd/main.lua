--[=[
  sys 指令 Demo — UART1 收指令，协程里执行

  和同目录 sys_api 用同一套 sys API。
  本 demo 可由串口触发 reset / poweroff。

  ============================================================================
  数据路径
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 rt.delay / delay_us / reset）
      → rt.mbox_send 投到指令协程
      → 协程里执行 version / option / delay / reset / poweroff
      → 成功或失败通过 UART1 回写

  指令不区分大小写；行首行尾空白和 \r\n 会去掉。
  不是 AT 的数据才当指令（meta.at_check ~= 0）。

  ----------------------------------------------------------------------------
  指令一览
  ----------------------------------------------------------------------------
    sys version
        打印固件版本表。

    sys reset_reason
        打印上次复位原因。模组有两套核：AP（跑 Lua/应用）和 CP（协议栈）。
        返回 ap / ap_name、cp / cp_name。码值与 sys.RST_* 一致：

          0  CLEAR      深睡唤醒，不是真正掉电复位
          1  POR        上电复位（第一次接电 / 掉电再上电）
          2  PAD        复位脚被拉低（按了 RESET 键）
          3  SWRESET    软件复位（含 sys.reset）
          4  HARDFAULT  AP 硬故障
          5  ASSERT     断言失败
          6  WDTSW      软件看门狗
          7  WDTHW      硬件看门狗（delay_us 堵太久也可能走到这类）
          8  LOCKUP     CPU lockup
          9  AONWDT     Always-On 看门狗
          10 BATLOW     电压过低
          11 TEMPHI     温度过高
          12 FOTA       FOTA 升级复位
          13 EXTRST     外部复位（本芯片有）
             UNKNOWN    未能识别

    sys option <key>
    sys option <key> <value>
        key = print_route / log_route，value = uart1/uart2/uart3/usb_at。
        改路由后日志可能跑到另一路串口或 USB AT。

    sys delay_ms <毫秒>
        OS 线程休眠。Lua 协程全部停。

    sys delay_until <毫秒>
        本平台 osDelayUntil：相对当前 tick 再睡。Lua 协程全部停。

    sys delay_us <微秒>
        忙等，不进调度。API 不限制数值；本 demo 拒绝 >= 10000us，
        以免看门狗复位。到毫秒请用 delay_ms 或 rt.delay。

    sys wdt_kick
        主动喂 AP/AON 硬件看门狗，不让出调度。

    sys reset
        约 1 秒后软件复位。

    sys poweroff
        约 1 秒后关机。

]=]

local rt = require("rt")
local uart = require("uart")
local sys = require("sys")

local UART_ID = uart.UART1
local CMD_TOPIC = "sys_cmd"
local DELAY_US_DEMO_MAX = 10000

local function out(s)
    uart.write(UART_ID, s .. "\r\n")
end

local function reply(ok, fmt, ...)
    out(string.format("%s  %s", ok and "OK" or "FAIL", string.format(fmt, ...)))
end

local function hint(fmt, ...)
    out(string.format("%s", string.format(fmt, ...)))
end

local function dump_version()
    local v = sys.version()
    reply(true, "version sdk=%s app=%s ver=%s build=%s",
          tostring(v.sdk), tostring(v.app), tostring(v.ver), tostring(v.build))
    hint("  evb=%s ver_f=%s cmp=%s btime=%s",
         tostring(v.evb), tostring(v.ver_f), tostring(v.cmp), tostring(v.btime))
end

local RST_CN = {
    CLEAR = "深睡唤醒，不是真正掉电复位",
    POR = "上电复位",
    PAD = "复位脚拉低",
    SWRESET = "软件复位",
    HARDFAULT = "硬故障",
    ASSERT = "断言失败",
    WDTSW = "软件看门狗",
    WDTHW = "硬件看门狗",
    LOCKUP = "CPU lockup",
    AONWDT = "Always-On 看门狗",
    BATLOW = "电压过低",
    TEMPHI = "温度过高",
    FOTA = "FOTA 升级复位",
    EXTRST = "外部复位",
    UNKNOWN = "未能识别",
}

local function dump_reset_reason()
    local r = sys.reset_reason()
    local ap_cn = RST_CN[r.ap_name] or ""
    local cp_cn = RST_CN[r.cp_name] or ""
    reply(true, "reset_reason ap=%s %s (%s)  cp=%s %s (%s)",
          tostring(r.ap), tostring(r.ap_name), ap_cn,
          tostring(r.cp), tostring(r.cp_name), cp_cn)
end

local function cmd_option(key, val)
    if not key or key == "" then
        reply(false, "option：用法 sys option <print_route|log_route> [uart1|uart2|uart3|usb_at]")
        return
    end
    if val == nil then
        local n = sys.option(key)
        reply(true, "option %s=%s", key, tostring(n))
        return
    end
    local n = sys.option(key, val)
    reply(true, "option %s=%s", key, tostring(n))
end

local function cmd_delay_ms(ms)
    if not ms or ms < 0 then
        reply(false, "delay_ms：用法 sys delay_ms <毫秒>")
        return
    end
    hint("delay_ms %d ...", ms)
    sys.delay_ms(ms)
    reply(true, "delay_ms %d done", ms)
end

local function cmd_delay_until(ms)
    if not ms or ms < 0 then
        reply(false, "delay_until：用法 sys delay_until <毫秒>")
        return
    end
    hint("delay_until %d ...", ms)
    sys.delay_until(ms)
    reply(true, "delay_until %d done", ms)
end

local function cmd_delay_us(us)
    if not us or us < 0 then
        reply(false, "delay_us：用法 sys delay_us <微秒>")
        return
    end
    if us >= DELAY_US_DEMO_MAX then
        reply(false, "delay_us：本 demo 拒绝 >= %d us（API 本身不限制）。忙等过长会看门狗复位，请用 delay_ms 或 rt.delay",
              DELAY_US_DEMO_MAX)
        return
    end
    if us >= 1000 then
        hint("warn: delay_us 是忙等，已到毫秒，建议改用 delay_ms / rt.delay")
    end
    sys.delay_us(us)
    reply(true, "delay_us %d done", us)
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    if lower == "sys version" then
        dump_version()
    elseif lower == "sys reset_reason" then
        dump_reset_reason()
    elseif lower == "sys wdt_kick" then
        sys.wdt_kick()
        reply(true, "wdt_kick")
    elseif lower == "sys reset" then
        hint("reset：约 1 秒后复位")
        reply(true, "reset")
        sys.reset()
    elseif lower == "sys poweroff" then
        hint("poweroff：约 1 秒后关机")
        reply(true, "poweroff")
        sys.poweroff()
    else
        local key, val = lower:match("^sys%s+option%s+(%S+)%s+(%S+)$")
        if key then
            cmd_option(key, val)
            return
        end
        key = lower:match("^sys%s+option%s+(%S+)$")
        if key then
            cmd_option(key)
            return
        end
        local ms = lower:match("^sys%s+delay_ms%s+(%-?%d+)$")
        if ms then
            cmd_delay_ms(tonumber(ms))
            return
        end
        ms = lower:match("^sys%s+delay_until%s+(%-?%d+)$")
        if ms then
            cmd_delay_until(tonumber(ms))
            return
        end
        local us = lower:match("^sys%s+delay_us%s+(%-?%d+)$")
        if us then
            cmd_delay_us(tonumber(us))
            return
        end
        reply(false, "未知指令: %s", cmd)
        hint("可用: sys version | reset_reason | option <key> [uart1|uart2|uart3|usb_at] | delay_ms <n> | delay_until <n> | delay_us <n> | wdt_kick | reset | poweroff")
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
        "==== SYS 指令 ====",
        "UART1 输入，回车发送",
        "",
        "sys version",
        "sys reset_reason   上次 AP/CP 复位原因（码+名称）",
        "sys option print_route [uart1|uart2|uart3|usb_at]",
        "sys option log_route [uart1|uart2|uart3|usb_at]",
        "sys delay_ms <毫秒>",
        "sys delay_until <毫秒>  相对当前 tick 再睡",
        "sys delay_us <微秒>   忙等，demo 上限 9999us",
        "sys wdt_kick          喂 AP/AON 硬件看门狗",
        "sys reset",
        "sys poweroff",
        "",
        "delay_us 无调度，到 ms 请用 delay_ms / rt.delay",
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
