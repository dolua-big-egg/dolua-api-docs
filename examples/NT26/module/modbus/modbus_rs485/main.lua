--[=[
  modbus_rs485 demo — UART1 模拟 485：发请求，block 等应答，再解析
  ============================================================================
  本 demo
  ============================================================================
    打开 UART1，周期发送一帧「读 3 个保持寄存器」，然后 uart.block 等到
    一整包应答，用 modbus.analyze 抽出整数和浮点。

    请用串口助手 HEX 模式接到 UART1，看到请求后按下面示例回一帧。
    真实 485 芯片的 DE/RE 方向脚要自己在 write 前拉高、block 前拉低。

  ----------------------------------------------------------------------------
  模块发出的请求（HEX，功能码 03，从站 1，起始地址 0，数量 3）
  ----------------------------------------------------------------------------
      01 03 00 00 00 03 05 CB

  ----------------------------------------------------------------------------
  请在 timeout 内按 HEX 回复下面这一帧（或同布局的真实仪表应答）
  ----------------------------------------------------------------------------
      01 03 06 00 7B 41 CC 00 00 11 7C

      01          从站地址
      03          功能码（读保持寄存器）
      06          后续数据字节数 = 3 个寄存器 × 2
      00 7B       第 1 个寄存器，UINT16 大端 = 123
      41 CC 00 00 第 2~3 个寄存器，FLOAT32 大端 = 25.5
      11 7C       CRC（低字节在前；本 demo 不校验 CRC，可随便填，但长度要够）

    串口助手务必开 HEX 发送。发 ASCII 文本 "01 03 06 ..." 解析会全错。
    整帧一次发出，不要拆成多个包（分包空闲超时见 rtu_config [uart.1] max_wait_ms）。

]=]

local rt = require("rt")
local log = require("log")
local uart = require("uart")
local rtu = require("rtu")
local modbus = require("modbus")

local U = uart.UART1
local BAUD = 115200 --注意这个demo把波特率设置为了115200，如果你要9600下测就改一下。
local WAIT_MS = 3000

-- 不要把这路串口当 AT 透传，否则请求/应答可能被 AT 解析吃掉
rtu.option("pass_up", false)
rtu.option("pass_down", false)

local function to_hex(s)
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02X", s:byte(i))
    end
    return table.concat(t, " ")
end

-- 读保持寄存器：从站 1，起始 0，数量 3（2 字节整数 + 4 字节浮点）
-- CRC 已按 Modbus RTU 算好：05 CB
local REQ = {0x01, 0x03, 0x00, 0x00, 0x00, 0x03, 0x05, 0xCB}

-- 应答布局和 modbus_api 那帧相同：从第 4 字节抠 UINT16，从第 6 字节抠 FLOAT32
-- 完整示例：01 03 06 00 7B 41 CC 00 00 11 7C
local RULES = {
    {4, 2, 3, 1}, -- UINT16 大端
    {6, 4, 9, 1}, -- FLOAT32 大端
}

local ok_cfg, msg_cfg = uart.config(U, {
    baudrate = BAUD,
    data_bits = 8,
    stop_bits = 1,
    parity = 0,
    flow_control = 0,
})
log.info("uart1 %d 8N1 ok=%s msg=%s", BAUD, ok_cfg, msg_cfg)
log.info("HEX reply example: 01 03 06 00 7B 41 CC 00 00 11 7C")

local seq = 0
while true do
    seq = seq + 1
    log.info("tx seq=%d req=01 03 00 00 00 03 05 CB  wait=%dms", seq, WAIT_MS)
    -- 真实 485：这里先把 DE 拉高，再 write，稍等发送完成再拉低
    uart.write(U, REQ)

    -- block 让出当前协程，等到一整包或超时。不要在 uart.reg 回调里调
    local ok, pkt = uart.block(U, WAIT_MS)
    if not ok then
        log.warn("rx seq=%d err=%s  (no HEX reply in time?)", seq, pkt)
    elseif type(pkt) ~= "string" or #pkt < 9 then
        -- 01 03 06 + 6 字节数据，至少 9 字节；CRC 2 字节可有可无
        log.warn("rx seq=%d short len=%d hex=%s", seq, pkt and #pkt or 0, pkt and to_hex(pkt) or "")
    else
        log.info("rx seq=%d len=%d hex=%s", seq, #pkt, to_hex(pkt))
        local vals = modbus.analyze(pkt, RULES)
        if vals == nil then
            log.error("analyze fail, check start/len and frame length")
        else
            log.info("parsed seq=%d uint16=%.0f float=%f", seq, vals[1], vals[2])
        end
    end

    rt.delay(2000)
end

--[=[
  modbus_rs485 demo — UART1 模拟 485

  ============================================================================
  收发骨架
  ============================================================================
    uart.write(id, 请求)
    local ok, pkt = uart.block(id, timeout_ms)
    if ok then modbus.analyze(pkt, rules) else 超时重试 end

  uart.block 读的是按空闲超时切好的一整包，不是一个字节。
  会让出当前协程，不卡死整台 Lua。全脚本同一时刻只能有一个 block。

  ============================================================================
  应答从哪几个字节解
  ============================================================================
    标准 03 应答： [从站][03][字节数][数据...][CRC_L][CRC_H]
    本例数据从第 4 字节开始：2 字节整数 + 4 字节浮点。

    analyze 规则 {start, len, mode, endian}：
      mode    3=UINT16  9=FLOAT32（其它见 modbus_api）
      endian  1=大端（Modbus 默认）；float 若是乱值，再试 3=CDAB

    本 demo 不校验从站地址、功能码、CRC。接到真实仪表后按手册改
    REQ 的地址/寄存器，并确认应答长度够规则去抠。

  ============================================================================
  串口助手怎么配合
  ============================================================================
    波特率 9600 8N1，HEX 显示 + HEX 发送。
    看到 01 03 00 00 00 03 05 CB 后，回：
      01 03 06 00 7B 41 CC 00 00 11 7C
    成功时应打出 uint16=123  float=25.5

  ============================================================================
  本 demo
  ============================================================================
    UART1。循环：发 03 请求 → block 等应答 → 解析整数和浮点。

]=]
