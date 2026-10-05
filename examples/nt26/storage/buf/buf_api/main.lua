--[=[
  buf demo — cust 堆字节缓冲（长度 / 容量分开，独立 200KB 额度）
  ============================================================================
  本 demo 一次跑完下列项，串口打 PASS / FAIL，最后汇总。
    limit / used
    alloc 预分配：长度 0，容量为传入值；未超容量的 append 不扩容
    超容量 append 按 2 倍扩容（起步 64）
    u8 / u16 / u32 小端读写，越过长度失败
    search_u16 二分
    insert / remove / replace / clear / reserve / string 切片
    from（含 \\0）
    load：缺省容量、容量大于文件、容量小于文件报错
    close 后再调用
    额度打满后再 alloc 失败
  结束删掉本 demo 写入的 ublob。不动其它文件。
]=]

local rt = require("rt")
local log = require("log")
local buf = require("buf")
local ublob = require("ublob")

local BLOB = "buf_demo"
local pass = 0
local fail = 0

local function check(name, cond)
    if cond then
        pass = pass + 1
        log.info("PASS %s", name)
    else
        fail = fail + 1
        log.info("FAIL %s", name)
    end
end

local used0 = buf.used()
log.info("---- limit / used ----")
log.info("limit=%s used=%s", tostring(buf.limit()), tostring(used0))
check("limit is 200KB", buf.limit() == 200 * 1024)

log.info("---- alloc / append inside cap ----")
local b, err = buf.alloc(32)
check("alloc 32", b ~= nil and err == nil)
if b then
    check("alloc size 0", b:size() == 0)
    check("alloc cap 32", b:cap() == 32)
    check("used +32", buf.used() == used0 + 32)
    local sv, se = b:set_u8(0, 1)
    check("set past length", sv == nil and se == "invalid param")
    local ok = b:append_u8(0x11)
    check("append_u8", ok == true)
    ok = b:append_u16(0x1234)
    check("append_u16", ok == true)
    check("size 3", b:size() == 3)
    check("cap stays 32", b:cap() == 32)
    check("u8 0", b:u8(0) == 0x11)
    check("u16 le", b:u16(1) == 0x1234)
    check("u8 1", b:u8(1) == 0x34)
    check("u8 2", b:u8(2) == 0x12)
    local u32v, u32e = b:u32(0)
    check("u32 needs 4 bytes", u32v == nil and u32e == "invalid param")
    ok = b:append_u8(0x56)
    check("append 4th", ok == true and b:u32(0) == 0x56123411)
    ok = b:set_u8(0, 0xAB)
    check("set_u8", ok == true and b:u8(0) == 0xAB)
    ok = b:set_u16(1, 0x00FF)
    check("set_u16", ok == true and b:u16(1) == 0x00FF)
    local whole = b:string()
    check("string len", type(whole) == "string" and #whole == 4)
    check("string slice", b:string(1, 2) == "\xFF\x00")
    local sl, serr = b:string(2, 8)
    check("string past end", sl == nil and serr == "invalid param")
    b:close()
    local sz, cerr = b:size()
    check("closed size", sz == nil and cerr == "closed")
    check("close again", b:close() == true)
    check("used back", buf.used() == used0)
end

log.info("---- grow ----")
local g = buf.alloc(8)
if g then
    local ok = g:append(string.rep("x", 20))
    check("append forces grow", ok == true and g:size() == 20)
    check("grow cap 64", g:cap() == 64)
    check("grown bytes", g:string() == string.rep("x", 20))
    g:close()
end
check("used after grow close", buf.used() == used0)

log.info("---- splice ----")
local s = buf.alloc(32)
if s then
    s:append("hello")
    check("insert tail", s:insert(5, "!") == true and s:string() == "hello!")
    check("insert head", s:insert(0, ">>") == true and s:string() == ">>hello!")
    check("remove", s:remove(0, 2) == true and s:string() == "hello!")
    check("replace", s:replace(5, 1, "?") == true and s:string() == "hello?")
    local cap = s:cap()
    check("clear keeps cap", s:clear() == true and s:size() == 0 and s:cap() == cap)
    s:close()
end

log.info("---- reserve / from ----")
local r = buf.alloc(4)
if r then
    check("reserve", r:reserve(100) == true and r:cap() >= 100 and r:size() == 0)
    r:close()
end
local f = buf.from("A\0B")
if f then
    check("from size", f:size() == 3 and f:cap() == 3)
    check("from nul", f:string() == "A\0B" and f:u8(1) == 0)
    f:close()
else
    check("from", false)
end

log.info("---- search_u16 ----")
local map = buf.alloc(16)
if map then
    map:append_u16(0x0001)
    map:append_u16(0x00AA)
    map:append_u16(0x0003)
    map:append_u16(0x00BB)
    map:append_u16(0x0010)
    map:append_u16(0x00CC)
    map:append_u16(0x0100)
    map:append_u16(0x00DD)
    local i = map:search_u16(0, 4, 4, 0x0003)
    check("search mid", i == 1 and map:u16(i * 4 + 2) == 0x00BB)
    i = map:search_u16(0, 4, 4, 0x0001)
    check("search first", i == 0)
    i = map:search_u16(0, 4, 4, 0x0100)
    check("search last", i == 3 and map:u16(i * 4 + 2) == 0x00DD)
    local miss, merr = map:search_u16(0, 4, 4, 0x0002)
    check("search miss", miss == nil and merr == "not found")
    local bad, berr = map:search_u16(0, 1, 4, 1)
    check("search stride", bad == nil and berr == "invalid param")
    map:close()
end

log.info("---- load ----")
ublob.remove(BLOB)
local wok, werr = ublob.write(BLOB, "xyz")
log.info("ublob write ok=%s err=%s", tostring(wok), tostring(werr))
local n, nerr = ublob.size(BLOB)
log.info("ublob size=%s err=%s", tostring(n), tostring(nerr))
check("blob size", n == 3)
if n == 3 then
    local small, serr = buf.load(BLOB, n - 1)
    check("load cap too small", small == nil and serr == "invalid param")
    local exact, eerr = buf.load(BLOB, n)
    check("load exact", exact ~= nil and eerr == nil and exact:size() == 3 and exact:cap() == 3)
    if exact then
        check("load bytes", exact:string() == "xyz")
        exact:close()
    end
    local big, gerr = buf.load(BLOB, n + 16)
    check("load extra", big ~= nil and gerr == nil and big:size() == 3 and big:cap() == n + 16)
    if big then
        local cap = big:cap()
        check("append in spare", big:append("!") == true and big:size() == 4 and big:cap() == cap)
        check("spare result", big:string() == "xyz!")
        big:close()
    end
    local auto = buf.load(BLOB)
    check("load default cap", auto ~= nil and auto:size() == 3 and auto:cap() == 3)
    if auto then
        auto:close()
    end
end
local missing, merr = buf.load("buf_no_such")
check("load missing", missing == nil and merr == "not found")
ublob.remove(BLOB)

log.info("---- quota ----")
local used1 = buf.used()
check("used clean before quota", used1 == used0)
if used1 == 0 then
    local full, ferr = buf.alloc(buf.limit())
    if full then
        check("full alloc cap", full:cap() == buf.limit() and full:size() == 0)
        local extra, xerr = buf.alloc(1)
        check("over quota", extra == nil and xerr == "quota exceeded")
        full:close()
    else
        log.info("SKIP full 200KB alloc err=%s", tostring(ferr))
        check("full alloc", false)
    end
else
    local extra, xerr = buf.alloc(buf.limit())
    check("quota when used>0", extra == nil and xerr == "quota exceeded")
end
check("used restored", buf.used() == used0)

log.info("---- done pass=%d fail=%d ----", pass, fail)

while true do
    rt.delay(10000)
end
