--[=[
  rt mbox demo — UART1 收数据，协程里处理
  ============================================================================
  本 demo
  ============================================================================
    UART1 收到一行
      → uart.reg 回调（必须马上返回，不能 delay）
      → rt.mbox_send 投到工作协程
      → 协程 mbox_recv 后原样写回 UART1

]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")

local U = uart.UART1
local TOPIC = "uart1"

rtu.option("pass_up", false)
rtu.option("pass_down", false)

local function worker()
    while true do
        local ok, data = rt.mbox_recv(TOPIC)
        if ok and data ~= nil and data ~= "" then
            log.info("mbox recv n=%s data=%s", type(data) == "string" and #data or "-", tostring(data))
            uart.write(U, data)
        end
    end
end

rt.task_start(worker)

local function on_uart(id, data, meta)
    if data == nil or data == "" then
        return
    end
    if meta and meta.at_check == 0 then
        return
    end
    rt.mbox_send(TOPIC, data)
end

uart.reg(U, on_uart)
uart.write(U, "mbox uart ready, type and enter\r\n")
log.info("UART1 -> mbox topic=%s", TOPIC)

while true do
    rt.delay(10000)
end

--[=[
  rt mbox demo — UART1 收数据，协程里处理

  mbox 是广播信箱：同一 topic 上，mbox_recv 等待的协程和 mbox_reg 回调都能收到。
  值支持 nil / boolean / number / string / table。
  回调里只能 send，不要 recv / delay。

  ----------------------------------------------------------------------------
  rt.mbox_send(topic[, value]) -> true
  ----------------------------------------------------------------------------
    投递到事件队列。缺省 value=nil。编码失败或队列满会抛错。
    topic 最长 24 字节。

  ----------------------------------------------------------------------------
  rt.mbox_recv(topic[, timeout_ms]) -> ok, data
  ----------------------------------------------------------------------------
    当前协程等待。默认 timeout=-1 一直等。
    收到 true, data；超时 false, nil。必须在任务协程里调用。

  ----------------------------------------------------------------------------
  rt.mbox_reg(topic, callback) -> true
  ----------------------------------------------------------------------------
    callback(data)，跑在调度循环里，必须马上返回。
    本 demo 用 recv，不用 reg。

  ============================================================================
  本 demo
  ============================================================================
    串口助手往 UART1 发什么，工作协程就写回什么。

]=]
