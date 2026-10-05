--[=[
  buf_builder — 按 StringBuilder 组字符串
  ============================================================================
  预先 alloc 够用的容量，片段用 append / insert / replace / remove 改在 C 缓冲里。
  循环里不做 Lua 的 `..` 拼接。整段组完只 string() 一次。
  容量够用时 cap 不变。
]=]

local rt = require("rt")
local log = require("log")
local buf = require("buf")

local function show(sb, tag)
    log.info("%s size=%d cap=%d", tag, sb:size(), sb:cap())
end

log.info("---- 逐步改一段 ----")
local sb, err = buf.alloc(64)
if not sb then
    log.info("alloc fail %s", tostring(err))
else
    local cap0 = sb:cap()
    sb:append("hello")
    sb:append(" ")
    sb:append("world")
    show(sb, "append")
    sb:insert(0, "[")
    sb:append("]")
    show(sb, "brackets")
    sb:replace(1, 5, "hi")
    show(sb, "replace hello->hi")
    sb:remove(sb:size() - 1, 1)
    sb:append("!")
    local text = sb:string()
    log.info("step result=%s", text)
    log.info("cap stayed=%s", tostring(sb:cap() == cap0))
    sb:clear()
    show(sb, "clear")
    sb:append("reuse")
    log.info("reuse=%s cap=%d", sb:string(), sb:cap())
    sb:close()
end

log.info("---- 循环拼一行，只出一次 string ----")
local names = { "alpha", "beta", "gamma" }
local line, lerr = buf.alloc(64)
if not line then
    log.info("alloc fail %s", tostring(lerr))
else
    local cap0 = line:cap()
    local i
    for i = 1, #names do
        line:append(names[i])
        line:append(",")
    end
    if line:size() > 0 then
        line:remove(line:size() - 1, 1)
    end
    line:insert(0, "[")
    line:append("]")
    local text = line:string()
    log.info("line=%s", text)
    log.info("size=%d cap=%d stayed=%s", line:size(), line:cap(), tostring(line:cap() == cap0))
    log.info("match=%s", tostring(text == "[alpha,beta,gamma]"))
    line:close()
end

log.info("---- 整数接进去，不先做字节串 ----")
local raw, rerr = buf.alloc(16)
if not raw then
    log.info("alloc fail %s", tostring(rerr))
else
    raw:append("n=")
    raw:append_u8(0x31)
    raw:append_u16(0x3233)
    log.info("raw=%s size=%d cap=%d", raw:string(), raw:size(), raw:cap())
    raw:close()
end

while true do
    rt.delay(10000)
end
