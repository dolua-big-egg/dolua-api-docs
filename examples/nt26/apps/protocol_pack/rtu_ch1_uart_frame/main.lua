--[=[
  rtu_ch1_uart_frame — RTU 通道 1 下行组帧后从 UART1 发出
  ============================================================================
  场景
  ============================================================================
    模组上已经有一路传统 RTU 网络通道（本工程配置里是 [task.1] + [sock.1]，
    通道号 1）。云端 / 对端打下来的字节，默认会被 DTU 按下行路由直接吐到串口
    （透传）。本工程要自己组协议，所以：

      1) 关掉本次运行的上下行透传，避免固件把同一包再抄到 UART1
      2) 登记通道 1 的 reg_chcb，只收「这路网络下来的数据」
      3) 回调里禁止组帧、禁止 uart.write、禁止 delay：只 mbox_send
      4) 工作协程取出 payload，加上帧头 + 长度 + 尾部 XOR，再 uart.write(UART1)

    通道 1 不是 tcp.create 拉起来的连接。没配 [task.1]/[sock.1]（或没驻网）
    时 is_connect=false，等不到下行，属正常。把 rtu_config.cfg 里的
    tcp_host / tcp_port（或 host/port）改成你的服务器。

  ============================================================================
  帧格式（两份 protocol_pack demo 共用这一套，方便串口助手对照）
  ============================================================================
    偏移    长度    内容
    0       2       帧头，固定 7E 5A
    2       2       长度，大端无符号 16 位 = payload 字节数
    4       N       payload，即通道下行原始 data
    4+N     1       校验：从「长度高字节」到 payload 最后一字节逐字节 XOR

    例：payload = "AB"（41 42）
        长度 = 0002
        XOR  = 00 xor 02 xor 41 xor 42 = 01
        线上 = 7E 5A 00 02 41 42 01

    串口助手请开 HEX。print / log 默认也走 UART1，会夹在二进制帧中间，
    属演示取舍；量产把 [lua] log_route 挪到 UART2/3。

]=]

local rt = require("rt")
local log = require("log")
local hex = require("hex")
local uart = require("uart")
local rtu = require("rtu")

local U = uart.UART1
local CH = 1
local TOPIC = "rtu_down"   -- mbox topic 最长 23 字节
local BAUD = 115200
local WAIT_MS = 20000

-- 组帧：7E 5A | LEN_BE16 | payload | XOR(LEN..payload)
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

-- 先挂接收协程，再 reg_chcb，避免先到的包没人收
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

-- 只改运行时，不写 pass_*_cfg（那会落盘）
local rc_up = rtu.option("pass_up", false)
local rc_dn = rtu.option("pass_down", false)
log.info("pass_up=false rc=%s pass_down=false rc=%s (0=ok)", tostring(rc_up), tostring(rc_dn))
log.info("now pass_up=%s pass_down=%s",
         tostring(rtu.option("pass_up")), tostring(rtu.option("pass_down")))

local ok_cfg, msg_cfg = uart.config(U, {
    baudrate = BAUD,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("uart1 config baud=%d ok=%s msg=%s", BAUD, ok_cfg, msg_cfg)

-- 回调必须马上返回。event=data 时 data 才是下行字节；online/offline 的 data 为 nil
local function on_ch(id, data, meta)
    meta = meta or {}
    if meta.event == "data" then
        rt.mbox_send(TOPIC, { id = id, data = data })
        return
    end
    log.info("chcb id=%s event=%s type=%s host=%s port=%s",
             tostring(id), tostring(meta.event), tostring(meta.type),
             tostring(meta.host), tostring(meta.port))
end

log.info("reg_chcb ch=%d ok=%s", CH, tostring(rtu.reg_chcb(CH, on_ch)))
log.info("ch%d is_connect=%s (false=通道未配或未连上，属正常)",
         CH, tostring(rtu.is_connect(CH)))

-- 没配通道时不要无限等
local ready = rtu.wait_connect(CH, WAIT_MS)
log.info("wait_connect(%d,%d)=%s", CH, WAIT_MS, tostring(ready))
if not ready then
    log.warn("通道 %d 未在 %d ms 内连上：检查 [task.1]/[sock.1]、驻网、对端地址", CH, WAIT_MS)
end

log.info("idle: 对端往通道 1 发的数据会组帧后从 UART1 出")
while true do
    rt.delay(10000)
end

--[=[
  rtu_ch1_uart_frame — RTU 通道 1 下行 → 组帧 → UART1

  require("rtu") / uart / hex / rt / log
  通道 1 来自 rtu_config.cfg 的 [task.1]+[sock.1]，不是 tcp.create。

  ----------------------------------------------------------------------------
  为什么必须关透传
  ----------------------------------------------------------------------------
    pass_down=true 时，通道下行会再走任务下行路由（常见直接出串口），
    和本脚本 uart.write 的组帧包叠在一起。
    pass_up=true 时，UART1 上的日志/其它字节可能被 DTU 当上行抢走。
    option 第二参必须是 true/false，数字 0 会抛 bool expected。
    只改本次运行时，重启回到配置。

  ----------------------------------------------------------------------------
  rtu.reg_chcb(id, cb) -> true（失败抛）
  ----------------------------------------------------------------------------
    cb(channel_id, data, meta)
      meta.event  "online" / "offline" / "data"
      meta.type   "tcp" / "udp" / "mqtt"
      data        仅 data 事件有字符串；空下行不会回调
    登记时若已连接，会立刻补一次 online。
    禁止在回调里 wait_connect / socket_sync / uart.block / rt.delay。
    组帧和 uart.write 放工作协程：uart.write 虽不让出，但拼帧+打 hex 日志
    会占调度，不该堵在 chcb 里。

  ----------------------------------------------------------------------------
  uart.write(id, data) -> true | false
  ----------------------------------------------------------------------------
    入发送队列，不等发完。false 无第二返回值（空串等）。
    本 demo data 是组好的二进制 string。

  ----------------------------------------------------------------------------
  帧
  ----------------------------------------------------------------------------
    7E 5A | LEN_BE16 | payload | XOR(LEN..payload)
    payload 超过 65535 字节丢弃（LEN 只有两字节）。

  ============================================================================
  本 demo
  ============================================================================
    关透传 → 配 UART1 115200 → 登记通道 1 回调 → 最多等 20s 上线 →
    之后每包下行组帧从 UART1 发出。不向通道回包。

]=]
