--[=[
  hex demo — 字节与十六进制互转
  ============================================================================
  本 demo
  ============================================================================
    1) bytes2hex：string / 字节表 → 小写 hex 串
    2) hex2bytes：hex 串 → 字节表（mode=1）或二进制 string（mode=2）
    3) 往返一次，确认能还原

]=]

local rt = require("rt")
local log = require("log")
local hex = require("hex")

log.info("---- bytes2hex ----")
log.info("string ABC -> %s", tostring(hex.bytes2hex("ABC")))
log.info("table {01 02 AB CD} -> %s", tostring(hex.bytes2hex({0x01, 0x02, 0xAB, 0xCD})))

log.info("---- hex2bytes ----")
local t = hex.hex2bytes("0102abcd", 1)
if t then
    log.info("mode=1 table n=%d  %02X %02X %02X %02X", #t, t[1], t[2], t[3], t[4])
else
    log.warn("mode=1 fail")
end

local s = hex.hex2bytes("414243", 2)
log.info("mode=2 string -> %s  bytes2hex=%s", tostring(s), tostring(hex.bytes2hex(s)))

log.info("---- roundtrip ----")
local raw = "\xDE\xAD\xBE\xEF"
local h = hex.bytes2hex(raw)
local back = hex.hex2bytes(h, 2)
log.info("raw -> %s -> %s  match=%s", tostring(h), tostring(hex.bytes2hex(back)),
         tostring(back == raw))

while true do
    rt.delay(10000)
end

--[=[
  hex demo — 字节与十六进制互转

  require("hex") 两个接口，失败一律返回 nil。

  ----------------------------------------------------------------------------
  hex.bytes2hex(data) -> string | nil
  ----------------------------------------------------------------------------
    data  二进制 string，或连续字节表（元素 0~255 的整数）
    成功  小写 hex 串，每字节两位，无空格、无 0x
    失败  nil（空、类型不对、表里不是 0~255）

    例  hex.bytes2hex("ABC")                 → "414243"
        hex.bytes2hex({0x01, 0x02, 0xAB})    → "0102ab"

  ----------------------------------------------------------------------------
  hex.hex2bytes(hex_str, mode) -> table | string | nil
  ----------------------------------------------------------------------------
    hex_str  十六进制字符串，长度必须偶数，不区分大小写
    mode     1=返回字节表   2=返回二进制 string
    失败     nil（缺参、奇数长度、非法字符、mode 不是 1/2）

    例  hex.hex2bytes("0102ab", 1)   → {1, 2, 171}
        hex.hex2bytes("414243", 2)   → "ABC"

  ============================================================================
  本 demo
  ============================================================================
    string/table 各转一次 hex；hex 再按 table / string 转回；最后做一次往返比对。

]=]
