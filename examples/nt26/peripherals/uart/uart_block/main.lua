--[=[
  uart_block demo — 阻塞读一整包（不是一个字节）
  ============================================================================
  本 demo
  ============================================================================
    UART1。先 write 一帧提示，再进入「发问答、block 等回包」。
    用串口助手回复任意内容，block 会拿到那一整包。
    超过 timeout 没数据就打印 timeout，然后下一轮。

]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")

local U = uart.UART1
local BAUD = 115200
local WAIT_MS = 5000

rtu.option("pass_up", false)
rtu.option("pass_down", false)

local function show_pkt(data)
    local s = data:gsub("\r", "\\r"):gsub("\n", "\\n")
    if #s > 48 then
        s = s:sub(1, 48) .. "..."
    end
    return s
end

-- 方案 B：发送 + block 等一包。RS485 轮询就是这个骨架
-- （485 方向脚在 write 前拉高、block 前拉低，按板子自己加）
local function query(req, timeout_ms)
    uart.write(U, req)
    return uart.block(U, timeout_ms)
end

local ok_cfg, msg_cfg = uart.config(U, {
    baudrate = BAUD,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("config baud=%d ok=%s msg=%s", BAUD, ok_cfg, msg_cfg)

uart.write(U, "block demo: reply within 5s\r\n")

local seq = 0
while true do
    seq = seq + 1
    local req = string.format("Q%d\r\n", seq)
    log.info("ask seq=%d wait=%dms", seq, WAIT_MS)
    -- 发送请求，等待响应，如果你在窗口内发送了数据，会进行返回，否则会打印错误信息，比如超时
    local ok, pkt = query(req, WAIT_MS)
    if ok then
        log.info("got seq=%d len=%d data=%s", seq, #pkt, show_pkt(pkt))
    else
        log.info("no reply seq=%d err=%s", seq, pkt)
    end

    rt.delay(1000)
end

--[=[
  uart_block demo — 阻塞读一整包（不是一个字节）

  ============================================================================
  block 的设计理念
  ============================================================================
  uart.block 主打「阻塞读取」。有些场景不需要一直挂着回调状态机，只想：

      发出一问 → 等到一答（或超时） → 接着往下写

  写成同步代码最清楚。Modbus / RS485 传感器轮询、一问一答协议，都是这类。

  它读的是已经按空闲超时 / 单包上限切好的「一包」，不是每次一个字节。
  分包规则和 uart.reg 回调拿到的是同一套（见 rtu_config [uart.N]）。

  ============================================================================
  会让出当前协程，不会卡死整台 Lua
  ============================================================================
  uart.block 和 rt.delay / rt.mbox_recv 同类：把当前这条任务协程挂起，
  控制权回到调度器。其它 task、定时、IO 该跑照跑。

  到期或等到一包后，从 block 的下一句接着执行，返回：

    ok, data_or_err = uart.block(id [, timeout_ms])
      等到一包   ok=true，  data_or_err 是这包的二进制字符串
      超时       ok=false， data_or_err 是 "timeout"
      已有 block 在等  ok=false， data_or_err 是 "busy"（整台脚本同时只能一个 block）

  timeout_ms 默认 1000；必须在任务协程里调用（main.lua 顶层可以）。
  不要在 uart.reg 回调里调用。

  ============================================================================
  两种正确写法（RS485 / 一问一答）
  ============================================================================

  方案 A：自己搭  发送 + 带超时的阻塞等待，回调把包转发到等待点

      发送报文
      回调里只 mbox_send，立刻返回
      业务协程里 mbox_recv(topic, timeout) 等到那一包，再继续

      适合：还要旁路处理、多路分发、和 uart.reg 长期并存。
      uart_normal 就是这个结构。

  方案 B：直接用 uart.block（本 demo）

      uart.write(id, 请求)
      local ok, pkt = uart.block(id, 超时)
      if ok then 解析 pkt else 超时重试 end

      调用后就停在这一行，协程让出；收到一包或超时后直接返回。
      用同步写法快速做一问一答，不必自己维护邮箱主题。

  两种都是「发完再等一整包」。不要边发边在回调里做 RS485 状态机，
  也不要按字节拼包（底层已经组过包了）。

  ============================================================================
  和 uart.reg 的关系
  ============================================================================
  block 等待期间，该口到来的包优先给 block，不会进 uart.reg。
  没有人在 block 时，包才进回调。

  同一时刻整台脚本只能有一个 uart.block。两个 task 同时 block 会 busy。

  ============================================================================
  接口
  ============================================================================
    uart.block(id [, timeout_ms]) -> ok, data_or_err
    uart.write(id, data) -> boolean
    uart.config(id, cfg) -> ok, msg

  ============================================================================
  本 demo
  ============================================================================
    UART1。先 write 一帧提示，再进入「发问答、block 等回包」。
    用串口助手回复任意内容，block 会拿到那一整包。
    超过 timeout 没数据就打印 timeout，然后下一轮。

]=]
