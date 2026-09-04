--[=[
  uart_normal demo — 注册 / 波特率 / 分包 / write 字符串与 hex / 回环
  ============================================================================
  本 demo
  ============================================================================
    UART1。开头 write 一帧文本、一帧 hex。
    之后客户从串口助手发什么，独立 task 就原样写回什么。

]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")

local U = uart.UART1
local TOPIC = "uart1"
local BAUD = 115200

rtu.option("pass_up", false)
rtu.option("pass_down", false)

-- 回环在独立任务：客户发什么，就 write 回去什么
local function uart_worker()
    while true do
        local ok, ev = rt.mbox_recv(TOPIC)
        if ok and type(ev) == "table" and ev.data ~= nil and #ev.data > 0 then
            uart.write(U, ev.data)
        end
    end
end

rt.task_start(uart_worker)

local ok_cfg, msg_cfg = uart.config(U, {
    baudrate = BAUD,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("config baud=%d ok=%s msg=%s", BAUD, ok_cfg, msg_cfg)

-- 回调必须短：只投递，立刻返回，如果是实在很快速的业务也可以在回调里直接就做了。
local function on_uart(id, data, meta)
    rt.mbox_send(TOPIC, {
        id = id,
        data = data,
        at_check = meta and meta.at_check or 0,
    })
end

-- 注册串口回调
local ok_reg = uart.reg(U, on_uart)
log.info("reg uart=%d ok=%s", U, ok_reg)

-- 1) 普通字符串
uart.write(U, "hello UART1\r\n")

-- 2) 字符串里直接写 hex：\x 后面两位十六进制就是一个字节
--    发出的线上内容是：01 02 AA FF 0D 0A，如果你的上位机没有切换到HEX模式，会看到一串乱码
uart.write(U, "\x01\x02\xAA\xFF\r\n")

-- 3) 同一帧也可用字节表（0x 写在表里，不是写在引号里,注意这个 tabel
--    必须是严格的每一个成员都是number且是符合一个字节定义的数据），
--    如果你的上位机没有切换到HEX模式，会看到一串乱码
uart.write(U, {0x01, 0x02, 0xAA, 0xFF, 0x0D, 0x0A})

while true do
    rt.delay(10000)
end

--[=[
  uart_normal demo — 注册 / 波特率 / 分包 / write 字符串与 hex / 回环

  ============================================================================
  这不是“串口中断里跑 Lua”
  ============================================================================
  uart.reg 看起来像注册收包回调，底层也确实在硬件收到字节后切包，
  但 Lua 函数绝不会在中断或驱动线程里执行。

  真实路径是：

    硬件收字节 → 按分包规则攒成一包（满长或空闲超时）
               → 投进 Lua 调度队列
               → 调度循环里调用你的回调

  回调跑在主脚本的调度循环里，不是独立协程。回调返回前，整台 Lua
  调度被占住：其它 task、定时、IO、网络事件全部排队。

  ============================================================================
  回调必须立刻离开
  ============================================================================
  不要在回调里逗留。不要调用会让出或阻塞的调度类接口，例如：

    rt.delay / rt.wait
    rt.mbox_recv
    uart.block

  这些要么直接报错（回调不是任务协程），要么把整台调度卡死。
  也不要在回调里打长 log、拼大包、死循环、uart.write。

  允许的极短动作：mbox_send、改几个本地变量。
  本 demo：回调只把收到的包丢给独立 task，由那个 task 原样写回。

  ============================================================================
  分包（空闲超时 + 单包上限）
  ============================================================================
  回调每次拿到的是已经切好的一包，不是每个字节一次。

    max_packet_size  单包最大字节，攒满就结算
    max_wait_ms      这包最后一个字节后再等这么久没有新数据，就结算
    max_packets      待处理包邮箱深度，满了新包会丢

  uart.config 只能热改线参数（波特率/数据位/停止位/校验/流控），立即生效，不写盘。
  分包三参数在 rtu_config.cfg 的 [uart.N] 里配，开机生效（改完需重新加载配置）。

  ============================================================================
  write：字符串 和 hex
  ============================================================================
    uart.write(id, data) -> boolean
      data  可以是字符串，也可以是连续字节表 {0x01, 0x02, ...}

    字符串里写 hex，用 Lua 转义 \xHH（两位十六进制，0x 不要写进字符串）：

      "hello\r\n"                 普通文本
      "\x01\x02\xAA\xFF"          四个字节：01 02 AA FF
      "AT+CSQ\r\n"                文本和 \r\n 混写

    常见写错：
      "0x01 0x02"     这是字符 '0' 'x' '0' '1' ...，不是二进制
      "01 02 AA"      这是 ASCII 文本，不是 hex 字节

    不想记 \x 时，用字节表同样可以：
      uart.write(id, {0x01, 0x02, 0xAA, 0xFF})

  ============================================================================
  其它接口
  ============================================================================
    uart.UART1 / UART2 / UART3

    uart.config(id, cfg) -> ok, msg
    uart.get_config(id) -> table|nil
    uart.reg(id, cb) -> true      cb(id, data, meta)  meta.at_check：0=AT 已吃掉
    uart.unreg(id) -> boolean

    rt.mbox_send(topic, value) -> true
    rt.mbox_recv(topic [, timeout_ms]) -> ok, data

  ============================================================================
  本 demo
  ============================================================================
    UART1。开头 write 一帧文本、一帧 hex。
    之后客户从串口助手发什么，独立 task 就原样写回什么。

]=]
