--[=[
  json demo — encode / decode / option
  ============================================================================
  本 demo
  ============================================================================
    1) encode 对象和数组
    2) decode 再读字段
    3) 往返一次（比字段，不比 JSON 文本）
    4) option：空表 {} / []，以及大整数关科学计数法
    5) 非法 JSON 失败示例

]=]

local rt = require("rt")
local log = require("log")
local json = require("json")

local function enc(tag, value)
    local s, err = json.encode(value)
    if s then
        log.info("%s %s", tag, s)
        return s
    end
    log.warn("%s fail %s", tag, tostring(err))
    return nil
end

log.info("---- encode ----")
local obj = { name = "demo", n = 3, ok = true, tags = { "a", "b" } }
local s = enc("object", obj)
enc("array", { 1, 2, 3 })

log.info("---- decode ----")
local back, derr = json.decode(s)
if back then
    log.info("name=%s n=%s ok=%s tags[1]=%s", back.name, back.n, back.ok, back.tags[1])
else
    log.warn("decode fail %s", tostring(derr))
end

log.info("---- roundtrip ----")
local s2, e2 = json.encode(back)
if s2 then
    -- 对象用 lua_next 遍历，键顺序不保证；decode 用 lua_pushnumber，
    log.info("s2 %s", s2)
    log.info("text match=%s", tostring(s2 == s))
    local same = back.name == obj.name
        and back.n == obj.n
        and back.ok == obj.ok
        and back.tags[1] == obj.tags[1]
        and back.tags[2] == obj.tags[2]
    log.info("value match=%s  n integer? %s / %s",
        tostring(same), math.type(obj.n), math.type(back.n))
else
    log.warn("re-encode fail %s", tostring(e2))
end

log.info("---- option empty_arr ----")
enc("empty default", {})
json.option("empty_arr", true) 
enc("empty_arr on", {}) 
json.option("empty_arr", false)

log.info("---- option num_sci ----")
local big = { id = 1782873378 }
enc("num_sci default", big)
json.option("num_sci", "off") --关闭科学计数法
enc("num_sci off", big)

log.info("---- fail ----")
local bad, berr = json.decode("{bad")
log.info("bad json v=%s err=%s", tostring(bad), tostring(berr))

while true do
    rt.delay(10000)
end

--[=[
  json demo — encode / decode / option

  require("json")，底层 lua-cjson。失败返回 nil, err。

  ----------------------------------------------------------------------------
  json.encode(value) -> string | nil, err
  ----------------------------------------------------------------------------
    表 / 数字 / 字符串 / bool / nil → 紧凑 JSON。

    例  json.encode({ a = 1, b = { 2, 3 } })

  ----------------------------------------------------------------------------
  json.decode(str) -> value | nil, err
  ----------------------------------------------------------------------------
    JSON 字符串 → Lua 值。对象变表，数组变连续整数下标表。

    例  local t, err = json.decode("{\"a\":1}")

  ----------------------------------------------------------------------------
  json.option(key [, value])
  ----------------------------------------------------------------------------
    无 value 读当前值，有 value 写入。短别名：

      num_sci     科学计数法。"off" 则 1782873378 不会打成 1.78e+09
      num_dp      固定小数位，-1 关闭
      num_trim    固定小数位时去掉尾部 0
      bad_num     NaN/Infinity："off" / "on" / "null"
      empty_arr   true：空表编成 []；false（默认）编成 {}

    也可用 cjson 全名，如 encode_number_precision。

  嵌套深度上限 100。空表默认是对象 {}，需要数组时设 empty_arr。

  ============================================================================
  本 demo
  ============================================================================
    encode/decode 往返比字段（对象键顺序不稳定，字符串往往对不上）；
    empty_arr 对比 {} / []；num_sci="off" 打完整整数；
    再解一段非法 JSON 看失败返回。

]=]
