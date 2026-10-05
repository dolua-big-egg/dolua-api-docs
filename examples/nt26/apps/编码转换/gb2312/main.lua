--[=[
  gb2312 demo — UTF-8 与 GB2312 互转
  ============================================================================
  工程自带的 gb2312.bin 是常用表：1 区符号、3 区全角、16–55 区一级汉字，3943 字。
  换表用同目录的 gb2312.html（其他文件，不下载到设备）。全量表这里也能跑过。

  串口按阶段打。每段先说明在测什么，再打 PASS / FAIL。
  第 5 段会打出一整段 GB2312 正文，上位机要把串口编码改成 GB2312 或 GBK 才能看清楚。

  https://dolua.cn/codec 是官方提供的码表转换工具，可以用来生成gb2312.bin文件
  使用方法：
  1. 下载gb2312.bin文件
  2. 将gb2312.bin文件复制到设备中

  如果是移动到自己的工程，则把gb2312.lua 和gb2312.bin一起挪到新工程去，如果存储空间告急，且不需要使用全量表，
  则在网页工具中生成自己需要的码表【常用表/全量表/自定义表】，然后保存为gb2312.bin文件，再挪到设备中。

  该demo使用的全量双向表，支持全部7445字，带双向转换，占地46kb
]=]

local rt = require("rt")
local log = require("log")
local buf = require("buf")
local gb = require("gb2312")

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

local function hex(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02X", string.byte(s, i))
    end
    return table.concat(t)
end

local function stage(n, title)
    log.info("======== %d. %s ========", n, title)
end

local NIHAO = string.char(0xC4, 0xE3, 0xBA, 0xC3)
local JU = string.char(0xA1, 0xA3)
local RARE_GB = string.char(0xD8, 0xA1)
local RARE = utf8.char(0x4E8D)

local LONG = "各位同事：明天下午三点在三楼会议室开会，讨论本月的发货安排。请准时参加，并带上上周的记录。联系人是小王，分机 8021。如有变动，请提前说明。"

local used0 = buf.used()

stage(1, "脚本里的中文")
log.info("确认 main.lua 按 UTF-8 保存，「你」「好」这些字没有写坏。这一段不动码表。")
check("literal ni", utf8.codepoint("你") == 0x4F60)
check("literal hao", utf8.codepoint("好") == 0x597D)
check("literal zhong", utf8.codepoint("中") == 0x4E2D)
check("literal juhao", utf8.codepoint("。") == 0x3002)
check("literal douhao", utf8.codepoint("，") == 0xFF0C)

stage(2, "不先 open，转一次就放开")
log.info("不调用 open。to_gb2312 自己装上码表，转完马上卸掉。")
log.info("看两件事：模块是关的，buf 已用额度回到调用前。")
log.info("这里只打十六进制，串口保持 UTF-8 就能对。中文正文放到第 5 段。")
check("start closed", gb.is_open() == false)
local g, gerr = gb.to_gb2312("你好")
log.info("你好 -> %s err=%s", hex(g), tostring(gerr))
check("nihao gb", g == NIHAO)
check("implicit closed", gb.is_open() == false)
check("implicit used", buf.used() == used0)

stage(3, "打开码表，占住内存")
log.info("open 之后码表留在 buf 里，额度应增加文件那么大，直到 close。")
log.info("常用表是 3943 字。表外的二级字变成问号。换成全量表则会转出原字。")
local ok, oerr = gb.open()
ok = ok == true
check("open", ok)
if not ok then
    log.info("open err=%s", tostring(oerr))
end
local info, ierr = gb.info()
if info then
    log.info("count=%s kind=%s size=%s", tostring(info.count), tostring(info.kind), tostring(info.size))
    check("used is file", buf.used() == used0 + info.size)
    check("name", info.name == "gb2312.bin")
else
    log.info("info err=%s", tostring(ierr))
    check("info", false)
    check("used is file", false)
    check("name", false)
end
if info and info.count == 3943 and info.kind == 2 then
    check("common size", info.size == 32 + 3943 * 8)
    check("rare is question", gb.to_gb2312(RARE) == "?")
elseif info and info.count == 7445 and info.kind == 1 then
    check("full size", info.size == 32 + 8178 * 2 + 7445 * 4)
    check("rare gb", gb.to_gb2312(RARE) == RARE_GB)
else
    log.info("自定义码表，跳过预设字数检查")
    check("kind known", info and (info.kind == 0 or info.kind == 1 or info.kind == 2))
    check("count", info and info.count > 0)
end

stage(4, "短句往返")
log.info("码表还开着。中文、标点、英文、空串、坏字节各转一次，确认能还原。")
log.info("再连续转两次，额度不应再涨。")
local back = gb.to_utf8(NIHAO)
check("nihao utf8", back == "你好")
check("juhao", gb.to_gb2312("。") == JU)
local mix = "你好中。，A"
local mix_gb = gb.to_gb2312(mix)
check("mix round", gb.to_utf8(mix_gb) == mix)
check("ascii gb", gb.to_gb2312("Hello") == "Hello")
check("ascii utf", gb.to_utf8("Hello") == "Hello")
check("empty", gb.to_gb2312("") == "" and gb.to_utf8("") == "")
check("bad utf8", gb.to_gb2312(string.char(0xFF)) == "?")
check("lone lead", gb.to_utf8(string.char(0xC4)) == "?")
check("one han", gb.to_utf8(string.char(0xC4, 0xE3)) == "你")
local bad, berr = gb.to_gb2312(1)
check("reject number", bad == nil and berr == "invalid param")
local used_open = buf.used()
gb.to_gb2312("你好")
gb.to_utf8(NIHAO)
check("batch keeps map", gb.is_open() == true and buf.used() == used_open)

stage(5, "长文本")
log.info("把一整段话从 UTF-8 转成 GB2312，再转回来。常用表里的字应该一致。")
log.info("下面先打原文，串口保持 UTF-8 就能看。")
log.info("%s", LONG)
local long_gb, lerr = gb.to_gb2312(LONG)
log.info("gb bytes=%s err=%s", long_gb and tostring(#long_gb) or "nil", tostring(lerr))
log.info("下一行是 GB2312 正文。上位机请把串口编码改成 GB2312 或 GBK 再看。")
log.info("[gb2312] >>> host encoding = GB2312/GBK")
if long_gb then
    log.info("%s", long_gb)
else
    log.info("(转换失败，没有正文)")
end
log.info("[gb2312] >>> host encoding = UTF-8")
log.info("看完把串口编码改回 UTF-8，下一行是还原结果。")
local long_back = long_gb and gb.to_utf8(long_gb) or nil
log.info("%s", tostring(long_back))
check("long round", long_back == LONG)

stage(6, "关掉，并试一个没有的文件")
log.info("close 之后额度回到开头。打开不存在的文件应该得到 not found。")
check("close", gb.close() == true)
check("closed", gb.is_open() == false)
check("info after close", gb.info() == nil)
check("used restored", buf.used() == used0)
local miss, merr = gb.open("no_such_gb.bin")
log.info("missing err=%s", tostring(merr))
check("missing", miss == nil and merr == "not found")
check("still closed", gb.is_open() == false)
check("reopen", gb.open() == true and gb.close() == true)
check("used final", buf.used() == used0)

log.info("======== 结束 pass=%d fail=%d ========", pass, fail)

while true do
    rt.delay(10000)
end
