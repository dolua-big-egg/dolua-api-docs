--[=[
  modbus_api demo — 模拟帧演示 analyze / crc
  ============================================================================
  本 demo
  ============================================================================
    不碰串口。手里准备一帧假的 Modbus RTU 应答：
      1) analyze 抽出一个整数、一个浮点（字节表 / 二进制字符串两种入参）
      2) crc("gen")  对不含 CRC 的载荷生成 2 字节 CRC
      3) crc("check") 校验整帧最后两字节；再故意改坏演示 mismatch

]=]

local rt = require("rt")
local log = require("log")
local modbus = require("modbus")

-- ============================================================================
-- analyze 规则怎么写
-- ============================================================================
-- analyze(data, rules) 按 rules 里每一条，从 data 里切一段字节，按类型/字节序
-- 解成 number，结果按规则顺序放进返回表。
--
-- 一条规则是 4 个数：{ start, len, mode, endian }
--   start   从 1 开始的字节下标（Lua 习惯，不是 C 的 0）
--   len     取几个字节，必须和 mode 匹配：UINT16=2，FLOAT32=4
--   mode    1=UINT8  2=INT8  3=UINT16  4=INT16
--           5=UINT32 6=INT32 7=UINT64  8=INT64  9=FLOAT32
--   endian  0=小端 ABCD    1=大端 DCBA
--           2=小端交换 BADC  3=大端交换 CDAB
--
-- Modbus 寄存器默认是大端（endian=1）。部分仪表 float 用 CDAB（endian=3），
-- 对不上时先改这一项，不要先怀疑数值本身。
-- 规则越界、类型和长度对不上时，analyze 返回 nil。

-- ============================================================================
-- crc 怎么用
-- ============================================================================
-- ok, result = modbus.crc(data, "gen"|"check")
--   data   二进制字符串或连续字节表（与 analyze 相同）
--   "gen"    对整段 data 算 CRC16。成功：ok=true，result 是 2 字节串（低字节在前）
--            可直接 payload .. crc 拼成完整报文。失败：ok=false，result 是原因
--   "check"  把 data 当完整报文，用前面的字节校验最后两字节。
--            符合：ok=true；不符：ok=false, result="crc mismatch"
--            太短/空/类型错：ok=false, result 是原因（too short / empty data / ...）
-- CRC 算法：Modbus RTU，初值 0xFFFF，多项式 0xA001，线上低字节在前。

-- 模拟一帧「读保持寄存器」应答（功能码 0x03，3 个寄存器 = 6 字节数据）：
--
--   下标     1    2    3  |  4    5  |  6    7    8    9  | 10   11
--   含义   从站 功能 字节数 |  UINT16  |      FLOAT32       |    CRC
--   HEX    01   03   06  |  00   7B |  41   CC   00   00 | 11   7C
--   值                    |   123    |       25.5         |
local frame = {
    0x01, 0x03, 0x06,
    0x00, 0x7B,             -- 第 4 字节起，2 字节 UINT16 大端 = 123
    0x41, 0xCC, 0x00, 0x00, -- 第 6 字节起，4 字节 FLOAT32 大端 = 25.5
    0x11, 0x7C,
}
local payload = {0x01, 0x03, 0x06, 0x00, 0x7B, 0x41, 0xCC, 0x00, 0x00}
local raw = "\x01\x03\x06\x00\x7B\x41\xCC\x00\x00\x11\x7C"
local raw_payload = "\x01\x03\x06\x00\x7B\x41\xCC\x00\x00"

-- 两条规则：先抠整数，再抠浮点。返回 vals[1]、vals[2]
local rules = {
    {4, 2, 3, 1}, -- start=4, len=2, UINT16, 大端
    {6, 4, 9, 1}, -- start=6, len=4, FLOAT32, 大端
}

local function dump_vals(tag, vals)
    if vals == nil then
        log.error("%s analyze fail (rule 越界或类型/长度不匹配)", tag)
        return
    end
    -- analyze 返回的是浮点 number，整数请用 %.0f，不要用 %d
    log.info("%s uint16=%.0f  float=%f", tag, vals[1], vals[2])
end

-- 1) analyze：字节表入参（每个元素必须是 0~255 的整数，下标连续）
dump_vals("table", modbus.analyze(frame, rules))

-- 2) analyze：二进制字符串入参（\xHH 是一个字节，不要写成 "0x01 0x03" 这种 ASCII）
dump_vals("string", modbus.analyze(raw, rules))

-- 3) crc gen：对不含 CRC 的载荷生成 2 字节（本帧应为 11 7C） CRC方法 1.2.17 版本新增，如果提示API不支持，就OTA上去。
local ok_gen, crc = modbus.crc(raw_payload, "gen")
if ok_gen then
    log.info("crc gen lo=0x%02X hi=0x%02X  built=%s",
        crc:byte(1), crc:byte(2),
        tostring(raw_payload .. crc == raw))
else
    log.error("crc gen fail: %s", crc)
end

-- 字节表同样可以 gen
local ok_gen2, crc2 = modbus.crc(payload, "gen")
if ok_gen2 then
    log.info("crc gen(table) lo=0x%02X hi=0x%02X", crc2:byte(1), crc2:byte(2))
else
    log.error("crc gen(table) fail: %s", crc2)
end

-- 4) crc check：整帧（含最后两字节）校验，符合返回 true
local ok_chk, err_chk = modbus.crc(raw, "check")
log.info("crc check good ok=%s err=%s", ok_chk, err_chk)

local ok_tbl, err_tbl = modbus.crc(frame, "check")
log.info("crc check(table) ok=%s err=%s", ok_tbl, err_tbl)

-- 故意改坏最后一字节，应返回 false, "crc mismatch"
local bad = "\x01\x03\x06\x00\x7B\x41\xCC\x00\x00\x11\x00"
local ok_bad, err_bad = modbus.crc(bad, "check")
log.info("crc check bad ok=%s err=%s", ok_bad, err_bad)

-- 用法错误示例：太短（没有 2 字节 CRC）
local ok_short, err_short = modbus.crc("\x01\x03", "check")
log.info("crc check short ok=%s err=%s", ok_short, err_short)

while true do
    rt.delay(10000)
end

--[=[
  modbus_api demo — 模拟帧演示 analyze / crc

  ============================================================================
  这个模块做什么
  ============================================================================
  require("modbus") 两个接口：

      vals = modbus.analyze(data, rules)
      ok, result = modbus.crc(data, "gen"|"check")

  不组包、不发串口。analyze 按规则抠整数/浮点；crc 生成或校验 RTU CRC16。
  真正的 485 收发见同目录 modbus_rs485。

  data 两种写法等价：
      {0x01, 0x03, 0x06, ...}          连续字节表
      "\x01\x03\x06..."                二进制字符串（\x 后两位十六进制）

  analyze：rules 每条 {start, len, mode, endian}，返回表和下标一一对应。
  任一条失败则整个返回 nil。

  crc：
      "gen"    成功 true + 2 字节串（低字节在前）；失败 false + 原因
      "check"  符合 true；不符 false+"crc mismatch"；用法错 false+原因
               用法错包括 empty data / too short / data too long / mode need gen/check

  ============================================================================
  本 demo 的模拟帧
  ============================================================================
    01 03 06 00 7B 41 CC 00 00 11 7C

    从站=1，功能码=03，后续 6 字节数据：
      00 7B          UINT16 大端 = 123
      41 CC 00 00    FLOAT32 大端 IEEE754 = 25.5
      11 7C          CRC16（低字节 11，高字节 7C）

  ============================================================================
  本 demo
  ============================================================================
    analyze 打印 123 和 25.5；crc gen 得到 11 7C；check 整帧通过、改坏则 mismatch。

]=]
