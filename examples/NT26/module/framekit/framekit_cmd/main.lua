--[=[
  framekit 指令 Demo — UART1 收指令 / 收二进制帧，演示拼包拆包

  协议与旧 RTU 工程 mcu_comm 相同：
    55 AA | len(u16 大端, 只含 payload) | payload | CRC16_Modbus(u16 小端, header→尾)

  ============================================================================
  为什么发得快也不会「黏」在回调里
  ============================================================================
    FrameKit 按完整帧格式切边界（包头 + 长度 + 校验），不是按串口空闲超时切。
    你把两帧粘成一坨一次发出去，解析器仍会找出两个完整帧，
    回调两次 frame_ok，每次 payload 都是干净的独立包。

    反过来，一帧被拆成几段、在 rx_timeout_ms 内陆续到达，会拼成一帧再回调。
    超过 rx_timeout_ms 仍不齐，或校验/格式错误：丢弃，回调 timeout / checksum / pattern。

  ============================================================================
  数据路径
  ============================================================================
    UART1
      → 行首是 "fk "：当指令，mbox 到协程执行
      → 其它字节：当二进制流，fk:input（可黏、可断）
    另有协程每 200ms fk:poll()，半包超时才能被丢掉
    帧事件在 framekit 回调里打到 UART1 / log

  串口助手请开 HEX 发送去贴下面的样例；不会 HEX 就用 fk input <hex> 或 fk demo ...

]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")
local framekit = require("framekit")

local UART_ID = uart.UART1
local CMD_TOPIC = "fk_cmd"
local RX_TIMEOUT_MS = 1500
local MAX_FRAME = 256
local POLL_MS = 200

local FK_JSON = string.format(
    '{"name":"demo_uart","rx_timeout_ms":%d,"queue_depth":8,"max_frame_size":%d,' ..
    '"header":{"value_hex":"55AA","size":2},' ..
    '"length":{"size":2,"endian":"big","includes":"payload"},' ..
    '"payload":{"mode":"variable"},' ..
    '"checksum":{"algorithm":"crc16_modbus","size":2,"endian":"little","scope":"header_to_tail"}}',
    RX_TIMEOUT_MS, MAX_FRAME)

local fk
local samples = {}

local function tohex(s, sep)
    if type(s) ~= "string" then
        return tostring(s)
    end
    sep = sep or ""
    local t = {}
    for i = 1, #s do
        t[#t + 1] = string.format("%02X", string.byte(s, i))
    end
    return table.concat(t, sep)
end

local function fromhex(s)
    if type(s) ~= "string" then
        return nil, "not string"
    end
    s = s:gsub("%s+", ""):gsub("0[xX]", "")
    if s == "" then
        return ""
    end
    if (#s % 2) ~= 0 then
        return nil, "odd hex length"
    end
    if s:find("[^0-9A-Fa-f]") then
        return nil, "bad hex"
    end
    return (s:gsub("..", function(b)
        return string.char(tonumber(b, 16))
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

local function on_fk(ev)
    if type(ev) ~= "table" then
        return
    end
    if ev.event == "frame_ok" then
        hint("FRAME_OK  payload=%s  n=%s  frame=%s",
             tostring(ev.payload), tostring(ev.payload_len), tohex(ev.frame))
        log.info("frame_ok payload=%s n=%s", tostring(ev.payload), tostring(ev.payload_len))
        return
    end
    hint("DROP  event=%s status=%s frame_len=%s payload_len=%s frame=%s",
         tostring(ev.event), tostring(ev.status),
         tostring(ev.frame_len), tostring(ev.payload_len), tohex(ev.frame or ""))
    log.warn("drop event=%s status=%s", tostring(ev.event), tostring(ev.status))
end

local function rebuild_samples()
    local ping, e1 = fk:build("PING")
    local hello, e2 = fk:build("HELLO")
    local alive, e3 = fk:build("\x02\x01\x00\x01")
    if not ping or not hello or not alive then
        hint("build fail ping=%s hello=%s alive=%s", tostring(e1), tostring(e2), tostring(e3))
        samples = {}
        return
    end
    local mid = math.floor(#ping / 2)
    if mid < 1 then
        mid = 1
    end
    local last = string.byte(ping, #ping)
    local bad = ping:sub(1, #ping - 1) .. string.char(last ~ 0xFF)
    samples = {
        ping = ping,
        hello = hello,
        alive = alive,
        sticky = ping .. hello,
        sticky3 = ping .. hello .. alive,
        part1 = ping:sub(1, mid),
        part2 = ping:sub(mid + 1),
        noise = "\x00\xFF\x11" .. ping,
        bad = bad,
        mid = mid,
    }
end

local function print_samples()
    if not samples.ping then
        rebuild_samples()
    end
    local s = samples
    local lines = {
        "",
        "==== 请用串口助手 HEX 发送（或 fk input <hex>）====",
        string.format("协议 55AA | len(BE) | payload | CRC16_Modbus(LE)   超时 %dms", RX_TIMEOUT_MS),
        "",
        "[1] 单包 PING   期望 1 次 FRAME_OK payload=PING",
        "    " .. tohex(s.ping),
        "",
        "[2] 黏包 PING+HELLO  一次发完。发得再快也不会黏在回调里",
        "    期望 2 次 FRAME_OK：PING 然后 HELLO，各是独立干净包",
        "    " .. tohex(s.sticky),
        "",
        "[3] 黏包三连 PING+HELLO+ALIVE(02 01 00 01，RTU 心跳 payload 风格)",
        "    期望 3 次 FRAME_OK",
        "    " .. tohex(s.sticky3),
        "",
        string.format("[4] 断包 PING  先发前半（%d 字节），%dms 内再发后半，会拼成 1 包",
                      s.mid, RX_TIMEOUT_MS),
        "    第1段: " .. tohex(s.part1),
        "    第2段: " .. tohex(s.part2),
        "",
        string.format("[5] 断包超时  只发第1段，然后干等 > %dms", RX_TIMEOUT_MS),
        "    " .. tohex(s.part1),
        "    期望 DROP event=timeout，残包丢掉",
        "",
        "[6] 噪声+正包  前面垃圾字节会被跳过，仍解析出 PING",
        "    " .. tohex(s.noise),
        "",
        "[7] 校验错  改了最后一个 CRC 字节",
        "    " .. tohex(s.bad),
        "    期望 DROP event=checksum",
        "",
        "不会 HEX？fk demo sticky|split|timeout|bad|noise|all",
        "================================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

local function print_help()
    local lines = {
        "",
        "==== FRAMEKIT 指令 ====",
        "UART1 文本指令以 fk 开头；HEX 二进制直接当帧流",
        "",
        "fk help",
        "fk samples          再打一遍粘包/断包/错包 HEX",
        "fk info             slot/profile/config",
        "fk reset            丢掉半包缓存",
        "fk poll             立刻检查超时",
        "fk build <文本>     组一帧并打印 HEX，不发送",
        "fk input <hex>      把 HEX 灌进解析器（可多次，模拟断包）",
        "fk demo sticky      本地灌入黏包",
        "fk demo split       本地灌入断包（中间 delay 200ms）",
        "fk demo timeout     只灌半包，等到超时",
        "fk demo bad         灌校验错帧",
        "fk demo noise       灌噪声+正包",
        "fk demo all         上面几项按序跑一遍",
        "",
        string.format("rx_timeout_ms=%d  超时内断包会合并；超时或错包丢弃", RX_TIMEOUT_MS),
        "================",
        "",
    }
    for i = 1, #lines do
        out(lines[i])
    end
end

local function cmd_info()
    local inf, err = fk:info()
    if not inf then
        reply(false, "info：%s", tostring(err))
        return
    end
    reply(true, "slot=%s topic=%s profile=%s max=%s q=%s closed=%s",
          tostring(inf.slot), tostring(inf.topic), tostring(inf.profile),
          tostring(inf.max_frame_size), tostring(inf.queue_depth), tostring(inf.closed))
    local js, jerr = fk:config_json()
    hint("config %s", js or tostring(jerr))
    local n, nerr = fk:calc_size("PING")
    hint("calc_size PING -> %s err=%s", tostring(n), tostring(nerr))
end

local function cmd_build(text)
    if not text or text == "" then
        reply(false, "build：用法 fk build <文本>")
        return
    end
    local frame, info = fk:build(text)
    if not frame then
        reply(false, "build：%s", tostring(info))
        return
    end
    reply(true, "n=%d hex=%s", #frame, tohex(frame))
    if type(info) == "table" then
        hint("  frame_len=%s payload_offset=%s payload_len=%s",
             tostring(info.frame_len), tostring(info.payload_offset), tostring(info.payload_len))
    end
end

local function cmd_input(hex)
    local bin, err = fromhex(hex or "")
    if not bin then
        reply(false, "input：%s  用法 fk input 55AA...", tostring(err))
        return
    end
    local ok, ierr = fk:input(bin)
    if not ok then
        reply(false, "input：%s n=%d", tostring(ierr), #bin)
        return
    end
    reply(true, "input n=%d hex=%s", #bin, tohex(bin))
end

local function cmd_demo(kind)
    rebuild_samples()
    local s = samples
    kind = kind or ""
    if kind == "sticky" then
        hint("demo sticky 灌入 PING+HELLO 一次")
        fk:input(s.sticky)
        reply(true, "demo sticky n=%d", #s.sticky)
    elseif kind == "split" then
        hint("demo split 先灌 %d 字节，delay 200ms 再灌剩余", s.mid)
        fk:input(s.part1)
        rt.delay(200)
        fk:input(s.part2)
        reply(true, "demo split")
    elseif kind == "timeout" then
        hint("demo timeout 只灌半包，等 %d ms", RX_TIMEOUT_MS + 400)
        fk:reset()
        fk:input(s.part1)
        rt.delay(RX_TIMEOUT_MS + 400)
        fk:poll()
        reply(true, "demo timeout（应看到 DROP timeout）")
    elseif kind == "bad" then
        hint("demo bad 灌校验错帧")
        fk:input(s.bad)
        reply(true, "demo bad")
    elseif kind == "noise" then
        hint("demo noise 灌垃圾+PING")
        fk:input(s.noise)
        reply(true, "demo noise")
    elseif kind == "all" then
        hint("---- demo all: sticky ----")
        fk:input(s.sticky)
        rt.delay(100)
        hint("---- demo all: split ----")
        fk:input(s.part1)
        rt.delay(200)
        fk:input(s.part2)
        rt.delay(100)
        hint("---- demo all: noise ----")
        fk:input(s.noise)
        rt.delay(100)
        hint("---- demo all: bad ----")
        fk:input(s.bad)
        rt.delay(100)
        hint("---- demo all: timeout ----")
        fk:reset()
        fk:input(s.part1)
        rt.delay(RX_TIMEOUT_MS + 400)
        fk:poll()
        reply(true, "demo all done")
    else
        reply(false, "demo：sticky|split|timeout|bad|noise|all")
    end
end

local function handle_line(line)
    local cmd = line:match("^%s*(.-)%s*$") or ""
    if cmd == "" then
        return
    end
    local lower = cmd:lower()
    hint("recv: %s", cmd)

    if lower == "fk" or lower == "fk help" then
        print_help()
        print_samples()
        return
    end
    if lower == "fk samples" then
        print_samples()
        return
    end
    if lower == "fk info" then
        cmd_info()
        return
    end
    if lower == "fk reset" then
        reply(fk:reset() and true or false, "reset")
        return
    end
    if lower == "fk poll" then
        local ok, err = fk:poll()
        if not ok then
            reply(false, "poll：%s", tostring(err))
            return
        end
        reply(true, "poll")
        return
    end
    local text = cmd:match("^[Ff][Kk]%s+[Bb][Uu][Ii][Ll][Dd]%s+(.-)%s*$")
    if text then
        cmd_build(text)
        return
    end
    local hex = cmd:match("^[Ff][Kk]%s+[Ii][Nn][Pp][Uu][Tt]%s+(.-)%s*$")
    if hex then
        cmd_input(hex)
        return
    end
    local kind = lower:match("^fk%s+demo%s+(%S+)$")
    if kind then
        cmd_demo(kind)
        return
    end
    if lower:match("^fk%s+demo") then
        reply(false, "demo：sticky|split|timeout|bad|noise|all")
        return
    end
    reply(false, "未知指令: %s", cmd)
    hint("输入 fk help")
end

local function looks_like_cmd(data)
    local s = data:match("^%s*(.-)%s*$") or ""
    local head = s:sub(1, 2):lower()
    if head ~= "fk" then
        return false
    end
    if #s == 2 then
        return true
    end
    local c = s:sub(3, 3)
    return c == " " or c == "\t"
end

local function uart_cb(id, data, meta)
    if data == nil or data == "" then
        return
    end
    if looks_like_cmd(data) then
        rt.mbox_send(CMD_TOPIC, data)
        return
    end
    if fk then
        fk:input(data)
    end
end

rtu.option("pass_up", false)
rtu.option("pass_down", false)

local ok_cfg, msg_cfg = uart.config(UART_ID, {
    baudrate = 115200,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("uart config ok=%s msg=%s", tostring(ok_cfg), tostring(msg_cfg))

local err
fk, err = framekit.create(FK_JSON, on_fk)
if not fk then
    log.error("framekit.create fail %s", tostring(err))
    while true do
        rt.delay(10000)
    end
end
rebuild_samples()

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

rt.task_start(function()
    while true do
        rt.delay(POLL_MS)
        if fk then
            fk:poll()
        end
    end
end)

uart.reg(UART_ID, uart_cb)
print_help()
print_samples()
hint("UART1 已就绪  MAX_INSTANCES=%s", tostring(framekit.MAX_INSTANCES))

while true do
    rt.delay(60000)
end

--[=[
  framekit 指令 Demo — 按完整协议拼包 / 拆包

  require("framekit")。JSON 描述帧格式，流式解析 UART 字节流。
  本 demo 帧格式对齐旧 RTU `mcu_comm`：
    55 AA | len(u16 大端, includes=payload) | payload | CRC16_Modbus(u16 小端, scope=header_to_tail)
  不是按串口空闲间隙切包，而是按「包头 + 长度 + 校验」识别完整帧。

  ----------------------------------------------------------------------------
  粘包、断包、丢包（必读）
  ----------------------------------------------------------------------------
    粘包：你发得很快、两帧甚至三帧连在同一段 UART 数据里，解析器仍按长度
    切出每一帧。回调是多次 frame_ok，每次 payload/frame 都是独立干净的包，
    不会把两帧粘成一次回调。

    断包：一帧被拆成几段，只要相邻两段间隔 < rx_timeout_ms（本 demo 1500ms），
    会先攒着，凑齐后再回调一次 frame_ok。

    超时：已经看到包头、但一直等不齐，超过 rx_timeout_ms → 丢弃，
    事件 timeout（FRAME_DROPPED_TIMEOUT）。Lua 绑定没有独立解析线程，
    必须周期 fk:poll()（本 demo 每 200ms），否则没新字节时超时不会发生。

    错包：长度对得上但 CRC 不对 → checksum；格式/长度非法 → pattern。
    丢弃后继续在剩余字节里找下一个 55AA，噪声不会永久卡死。

  ----------------------------------------------------------------------------
  framekit.create(json | {json=, frame_buf_size=}, [cb]) -> inst | nil, err
  framekit.new(...)  同 create
  framekit.MAX_INSTANCES  同时最多 8 个实例
  ----------------------------------------------------------------------------
    json 必填。table 时可加 frame_buf_size（不得小于 max_frame_size）。
    第二参是事件回调，也可事后 inst:on(cb) / inst:reg(cb)（reg 是 on 别名）。
    失败常见：json string required / 配置 hint / no framekit slot / no memory。

  ----------------------------------------------------------------------------
  inst:on(cb) / inst:reg(cb) -> true | nil, err
  ----------------------------------------------------------------------------
    cb(ev)。ev = {
      event        "frame_ok" | "timeout" | "pattern" | "checksum"
      status       "ok" | "timeout" | "checksum" | "pattern" | ...
      frame        完整帧二进制（含头尾校验）
      payload      载荷二进制
      frame_len / payload_len
      profile      模式名，如 M_L_Dvar_C
      topic        内部投递主题 __FK_xx
    }
    回调跑在 Lua 调度里，必须马上返回：不要 delay，不要再 create/close 自己。

  ----------------------------------------------------------------------------
  inst:input(data [, tick_ms]) -> ok | false, err
  ----------------------------------------------------------------------------
    喂任意长度二进制。可半包、整包、多包粘连、噪声+半包。
    tick 省略则用当前毫秒。成功 true（含「还没收齐」FRAMEKIT_ERR_INCOMPLETE）。
    关闭后 nil, "framekit closed"。

  ----------------------------------------------------------------------------
  inst:poll([tick_ms]) -> ok | false, err
  ----------------------------------------------------------------------------
    不喂新数据，只检查半包是否超时。本 demo 后台每 200ms 调一次。

  ----------------------------------------------------------------------------
  inst:reset() -> true | nil, err
  ----------------------------------------------------------------------------
    清空解析缓存和待投递事件。不改配置。

  ----------------------------------------------------------------------------
  inst:build(payload) -> frame, info | nil, err
  inst:calc_size(payload | n) -> frame_len | nil, err
  ----------------------------------------------------------------------------
    按当前配置组出完整帧。info = {frame_len, payload_offset, payload_len}。
    calc_size 可传字符串或整数（按 payload 长度算帧长）。

  ----------------------------------------------------------------------------
  inst:config_json() -> json | nil, err
  inst:info() -> {slot, topic, profile, max_frame_size, queue_depth, closed}
  inst:close() -> true
  ----------------------------------------------------------------------------
    close 后实例作废。GC 也会 close。

  ----------------------------------------------------------------------------
  本 demo 串口
  ----------------------------------------------------------------------------
    关 rtu pass_up/pass_down，避免 AT/透传抢走 HEX。
    行首 "fk " 当文本指令；其它一律当帧字节流（请用 HEX 发送模式）。
    若助手用 ASCII 发出 "55AA..." 那是字符 0x35 0x35，找不到包头；
    改用 HEX 模式，或 fk input 55AA...

  ============================================================================
  本 demo
  ============================================================================
    上电 create + 打印 HEX 样例（单包 / 黏包 / 断包两段 / 超时半包 / 噪声 / 错 CRC）。
    客户从串口贴 HEX 发送，或 fk demo sticky|split|timeout|bad|noise|all。
    观察 FRAME_OK 是干净独立包；超时和错包走 DROP。

]=]
