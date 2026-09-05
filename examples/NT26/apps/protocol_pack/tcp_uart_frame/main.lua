--[=[
  tcp_uart_frame — Lua tcp 模块直连服务器，下行组帧后从 UART1 发出
  ============================================================================
  场景
  ============================================================================
    不用传统 RTU 四路任务，脚本自己 tcp.create / open 连服务器。
    对端发来的字节在 tcp 回调的 ev.event=="data" 里。本工程：

      1) 关掉本次 RTU 上下行透传，避免固件 DTU 和脚本抢 UART1
      2) lp.wait_link 后 create + open（对象必须长期持有，否则会被 GC）
      3) tcp 回调里禁止组帧、禁止 uart.write、禁止 delay：只 mbox_send
      4) 工作协程取出 ev.data，加上帧头 + 长度 + 尾部 XOR，再 uart.write(UART1)

    这路 TCP 和 rtu 通道 1 **不是**同一个连接。不要在本工程里再配 [sock.1]
    去连同一端口，会占掉另一条客户端。

    把 HOST / PORT 改成你的服务器。测试站：http://tcp.doiot.cn/
    网页刷新后面端口会变，要同步改 PORT。

  ============================================================================
  帧格式（与 rtu_ch1_uart_frame 相同）
  ============================================================================
    偏移    长度    内容
    0       2       帧头，固定 7E 5A
    2       2       长度，大端无符号 16 位 = payload 字节数
    4       N       payload，即 tcp data 回调里的 ev.data
    4+N     1       校验：从「长度高字节」到 payload 最后一字节逐字节 XOR

    例：payload = "AB"（41 42）
        线上 = 7E 5A 00 02 41 42 01

    串口助手请开 HEX。print / log 默认也走 UART1，会夹在二进制帧中间。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local hex = require("hex")
local tcp = require("tcp")
local uart = require("uart")
local rtu = require("rtu")

-- 改成你的 TCP 服务器。测试站 http://tcp.doiot.cn/ ，端口以网页当前值为准。
local HOST = "tcp.doiot.cn"
local PORT = 26429

local U = uart.UART1
local TOPIC = "tcp_down"
local BAUD = 115200
local LINK_WAIT_MS = 60 * 1000

local c -- 长期持有，否则托管连接会被 GC 拆掉

local function xor8(s)
    local x = 0
    for i = 1, #s do
        x = x ~ string.byte(s, i)
    end
    return x
end

local function pack_frame(payload)
    if type(payload) ~= "string" or #payload == 0 then
        return nil, "empty"
    end
    if #payload > 65535 then
        return nil, "too_long"
    end
    local n = #payload
    local body = string.char((n >> 8) & 0xFF, n & 0xFF) .. payload
    return "\x7E\x5A" .. body .. string.char(xor8(body))
end

local function down_worker()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok and type(ev) == "table" and type(ev.data) == "string" and #ev.data > 0 then
            local frame, perr = pack_frame(ev.data)
            if not frame then
                log.warn("pack skip n=%d err=%s", #ev.data, tostring(perr))
            else
                local wrok = uart.write(U, frame)
                log.info("uart1 frame n=%d ok=%s hex=%s",
                         #frame, tostring(wrok), tostring(hex.bytes2hex(frame)))
            end
        end
    end
end

rt.task_start(down_worker)

local rc_up = rtu.option("pass_up", false)
local rc_dn = rtu.option("pass_down", false)
log.info("pass_up=false rc=%s pass_down=false rc=%s (0=ok)", tostring(rc_up), tostring(rc_dn))

local ok_cfg, msg_cfg = uart.config(U, {
    baudrate = BAUD,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("uart1 config baud=%d ok=%s msg=%s", BAUD, ok_cfg, msg_cfg)

-- connected / disconnected / error 只打日志；data 只投递
local function on_tcp(ev)
    if ev.event == "connected" then
        log.info("tcp connected ip=%s port=%s", ev.ip, ev.port)
    elseif ev.event == "disconnected" then
        log.info("tcp disconnected（内部会重连，不要在这里再 open）")
    elseif ev.event == "error" then
        log.warn("tcp error code=%s", ev.code)
    elseif ev.event == "data" then
        if ev.data and #ev.data > 0 then
            rt.mbox_send(TOPIC, { data = ev.data })
        end
    end
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测 tcp")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, create tcp")

local err
c, err = tcp.create(on_tcp, {
    reconnect_interval_ms = 5000,
    poll_interval_ms = 30,
    connect_timeout_ms = 5000,
    link_wait_timeout_ms = 60000,
    recv_buffer_size = 2048,
    keepalive_enable = true,
})
if not c then
    log.error("create fail err=%s", err)
    while true do
        rt.delay(10000)
    end
end

local ok, oerr = c:open(HOST, PORT)
log.info("open %s:%d ok=%s err=%s", HOST, PORT, tostring(ok), tostring(oerr))
if not ok then
    while true do
        rt.delay(10000)
    end
end

-- 可删：只是演示同步等到连上；业务一般看 connected 回调即可
local ready = c:wait_connect(20000)
log.info("wait_connect ready=%s status=%s", tostring(ready), tostring(c:status()))

log.info("idle: 服务器下行会组帧后从 UART1 出")
while true do
    rt.delay(10000)
end

--[=[
  tcp_uart_frame — tcp.create 直连 → 组帧 → UART1

  require("tcp") / uart / hex / lp / rt / log / rtu
  连接是脚本自己的托管客户端，不是 rtu 通道 1。

  ----------------------------------------------------------------------------
  和 rtu_ch1_uart_frame 的差别
  ----------------------------------------------------------------------------
    rtu 那份：对端由 [sock.1] 决定，下行进 reg_chcb。
    本份：对端由 HOST/PORT + c:open 决定，下行进 tcp 回调 ev.data。
    组帧规则相同。两边都要关 pass_up/pass_down，避免 DTU 抢串口。

  ----------------------------------------------------------------------------
  tcp 对象生命周期
  ----------------------------------------------------------------------------
    c 必须放在 chunk 级 local（或全局）。局部变量出作用域后，
    托管线程还在，对象却可能被 GC，连接会掉。
    create 成功不等于已连上；open 成功只表示交给内部线程。
    disconnected 后内部自动重连，不要在回调里再 open。
    回调里不要 send（同步）、不要 wait_connect、不要 delay。
    本 demo 不对服务器回包。

  ----------------------------------------------------------------------------
  帧
  ----------------------------------------------------------------------------
    7E 5A | LEN_BE16 | payload | XOR(LEN..payload)
    一包超过 recv_buffer_size（本 demo 2048）会分多次 data 回调，
    每次各自成一帧，不会在脚本里拼粘包。

  ============================================================================
  本 demo
  ============================================================================
    关透传 → 配 UART1 → 等驻网 → create/open → 下行组帧出 UART1。

]=]
