--[=[
  ublob demo — 字节 blob（write / append / read / open 视图）
  ============================================================================
  本 demo
  ============================================================================
    清掉本 demo 文件名后顺序跑：
    usage → write/size/stat/read 切片 → append → 含 \0 的二进制
    → 空文件 → open 视图（read/size/crc32/md5/raw）→ 同时只允许 1 个视图
    → close 后再 open → 已 close 的调用 → list/usage/remove/不存在。
    结束删文件。不 wipe 其它 blob。

]=]

local rt = require("rt")
local log = require("log")
local ublob = require("ublob")

local NAME = "b_demo"
local N_EMPTY = "b_empty"
local N_BIN = "b_bin"

local function tohex(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    return (s:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

ublob.remove(NAME)
ublob.remove(N_EMPTY)
ublob.remove(N_BIN)

log.info("---- usage ----")
local u, uerr = ublob.usage()
if u then
    log.info("used=%s limit=%s script_used=%s shared_limit=%s",
             u.used, u.limit, u.script_used, u.shared_limit)
else
    log.info("usage fail %s", tostring(uerr))
end

log.info("---- write / size / stat / read ----")
local ok, err = ublob.write(NAME, "hello")
log.info("write hello ok=%s err=%s", tostring(ok), tostring(err))
local n, nerr = ublob.size(NAME)
log.info("size=%s err=%s", tostring(n), tostring(nerr))
local st, serr = ublob.stat(NAME)
if st then
    log.info("stat name=%s size=%s", st.name, st.size)
else
    log.info("stat fail %s", tostring(serr))
end
local data, nread, rerr = ublob.read(NAME, 0, 5)
log.info("read 0,5 data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
data, nread, rerr = ublob.read(NAME, 1, 3)
log.info("read 1,3 data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
data, nread, rerr = ublob.read(NAME, 100, 10)
log.info("read past end data=%q nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))

log.info("---- append ----")
ok, err = ublob.append(NAME, " world")
log.info("append ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ublob.append(NAME, "")
log.info("append empty ok=%s err=%s", tostring(ok), tostring(err))
data, nread, rerr = ublob.read(NAME, 0, 32)
log.info("after append data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))

log.info("---- binary with NUL ----")
ok, err = ublob.write(N_BIN, "A\x00B")
log.info("write bin ok=%s err=%s", tostring(ok), tostring(err))
data, nread, rerr = ublob.read(N_BIN, 0, 8)
log.info("read bin nread=%s hex=%s match=%s err=%s",
         tostring(nread), tohex(data), tostring(data == "A\x00B"), tostring(rerr))

log.info("---- empty file ----")
ok, err = ublob.write(N_EMPTY, "")
log.info("write empty ok=%s err=%s", tostring(ok), tostring(err))
n, nerr = ublob.size(N_EMPTY)
log.info("empty size=%s err=%s", tostring(n), tostring(nerr))
data, nread, rerr = ublob.read(N_EMPTY, 0, 8)
log.info("empty read nread=%s err=%s", tostring(nread), tostring(rerr))

log.info("---- open view ----")
ok, err = ublob.write(NAME, "0123456789abcdef")
log.info("rewrite for view ok=%s err=%s", tostring(ok), tostring(err))
local view, verr = ublob.open(NAME)
if not view then
    log.info("open fail %s", tostring(verr))
else
    log.info("view size=%s", tostring(view:size()))
    data, nread, rerr = view:read(0, 4)
    log.info("view read 0,4 data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
    local crc, cerr = view:crc32()
    log.info("view crc32 whole=%s err=%s", crc and string.format("0x%08X", crc) or "nil", tostring(cerr))
    crc, cerr = view:crc32(0, 4)
    log.info("view crc32 0,4=%s err=%s", crc and string.format("0x%08X", crc) or "nil", tostring(cerr))
    local dig, derr = view:md5()
    log.info("view md5 %s err=%s", tostring(dig), tostring(derr))
    dig, derr = view:md5(0, 4)
    log.info("view md5 0,4 %s err=%s", tostring(dig), tostring(derr))
    local raw, merr = view:md5(0, nil, true)
    log.info("view md5 raw n=%s hex=%s err=%s",
             tostring(type(raw) == "string" and #raw or "-"), tohex(raw), tostring(merr))

    local v2, e2 = ublob.open(NAME)
    log.info("open 2nd (max 1) v=%s err=%s", tostring(v2), tostring(e2))

    log.info("view close=%s", tostring(view:close()))
    local view2, e3 = ublob.open(NAME)
    log.info("open after close ok=%s err=%s", tostring(view2 ~= nil), tostring(e3))
    if view2 then
        view2:close()
    end

    data, nread, rerr = view:read(0, 1)
    log.info("closed read data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
    n, nerr = view:size()
    log.info("closed size n=%s err=%s", tostring(n), tostring(nerr))
end

log.info("---- list ----")
local items, lerr = ublob.list()
if items then
    log.info("list n=%d", #items)
    for i = 1, #items do
        log.info("  [%d] name=%s size=%s", i, items[i].name, items[i].size)
    end
else
    log.info("list fail %s", tostring(lerr))
end

log.info("---- fail ----")
data, nread, rerr = ublob.read("no_such_blob", 0, 4)
log.info("read missing data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
data, nread, rerr = ublob.read(NAME, -1, 4)
log.info("read neg offset data=%s nread=%s err=%s", tostring(data), tostring(nread), tostring(rerr))
n, nerr = ublob.size("no_such_blob")
log.info("size missing n=%s err=%s", tostring(n), tostring(nerr))

u, uerr = ublob.usage()
if u then
    log.info("---- usage after ---- used=%s limit=%s script_used=%s shared_limit=%s",
             u.used, u.limit, u.script_used, u.shared_limit)
end

ok, err = ublob.remove(NAME)
log.info("remove ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ublob.remove(NAME)
log.info("remove again ok=%s err=%s", tostring(ok), tostring(err))
ublob.remove(N_EMPTY)
ublob.remove(N_BIN)
log.info("ublob demo done")

while true do
    rt.delay(10000)
end

--[=[
  ublob demo — 字节 blob 存储

  require("ublob")。存原始字节，不是 Lua 值。落盘 CREC(FastLZ)，前缀 lua_bin_*。
  与 lua 脚本、ufs 共用 FS_LUA_QUOTA_BYTES（220KiB），按压缩后落盘核算。
  可写空间 = 220KiB − lua 脚本落盘。单文件解压明文上限 256KiB（FS_LUA_BLOB_MAX_UNCOMPRESSED）。
  Lua 只传短名。文件名规则与 ufs 相同：禁止 '/' '\\' ':' 控制字符和 ".."。
  和 ufs 命名空间分开，同名互不可见，list 也互不包含。

  ----------------------------------------------------------------------------
  ublob.write(name, data) -> ok, err
  ----------------------------------------------------------------------------
    覆盖写。data 必须是 string（可含 \0，按长度不是 C 字符串）。
    允许空串，得到 0 字节文件。成功 true, nil；失败 false, 错误串。
    配额满 "quota exceeded"；非法名 "invalid param"。

  ----------------------------------------------------------------------------
  ublob.append(name, data) -> ok, err
  ----------------------------------------------------------------------------
    追加。文件不存在则等同 write。data 空串：成功且不改文件。
    实现是读出整包、拼上、再覆盖写，大文件会占 RAM 和配额峰值。

  ----------------------------------------------------------------------------
  ublob.read(name, offset, len) -> data, nread, err
  ----------------------------------------------------------------------------
    三个返回值。offset/len 必填，必须 ≥0。
    整包解压到 RAM 再切片；越界截断。offset 超出末尾或 len=0：空串, 0, nil。
    失败：nil, 0, err（"not found" / "invalid param" / "read target is dir" 等）。
    适合偶尔读一小段；反复从头读大文件请改用 open 视图。

  ----------------------------------------------------------------------------
  ublob.open(name) -> view | nil, err
  ----------------------------------------------------------------------------
    整包解压到 C 堆，挂到 userdata。同时打开数默认 1（LUA_UBLOB_MAX_OPEN_VIEWS）。
    已有未 close 的视图再 open → "too many open views"。
    用完必须 view:close()（或等 userdata GC）。空文件也可以 open，size=0。

  ----------------------------------------------------------------------------
  view:read(offset, len) -> data, nread, err
  ----------------------------------------------------------------------------
    与 ublob.read 切片规则相同，但从内存视图取，不再解压。
    offset/len 必填。已 close → nil, 0, "closed"。

  ----------------------------------------------------------------------------
  view:size() -> n | nil, err
  ----------------------------------------------------------------------------
    明文长度。已 close → nil, "closed"。

  ----------------------------------------------------------------------------
  view:crc32([offset], [len]) -> crc | nil, err
  ----------------------------------------------------------------------------
    IEEE CRC-32（以太网/zip），与 tls.crc32(data) 默认一致。
    直接在 C 缓冲算，不把数据拷进 Lua 堆。
    无参：整包。只给 offset：从该处到末尾。offset/len 越界截断。
    已 close → nil, "closed"。非法参数 nil, "invalid param"。

  ----------------------------------------------------------------------------
  view:md5([offset], [len], [raw]) -> digest | nil, err
  ----------------------------------------------------------------------------
    默认 32 字符小写 hex；raw=true 返回 16 字节 binary。
    区间规则同 crc32。mbedtls 流式 update，不拷贝输入。
    固件未开 MD5 → "md5 not enabled"。
    整包 raw：view:md5(0, nil, true)。已 close → nil, "closed"。

  ----------------------------------------------------------------------------
  view:close() -> true
  ----------------------------------------------------------------------------
    释放 C 缓冲，占一个 open 名额。重复 close 仍返回 true。
    关闭后再 read/size/crc32/md5 都会失败。

  ----------------------------------------------------------------------------
  ublob.size(name) -> n | nil, err
  ublob.stat(name) -> {name, size} | nil, err
  ----------------------------------------------------------------------------
    size 是解压后明文长度。stat 没有 is_dir 字段。

  ----------------------------------------------------------------------------
  ublob.remove(name) -> ok | nil, err
  ----------------------------------------------------------------------------
    成功或不存在：true。其它失败 nil, err。

  ----------------------------------------------------------------------------
  ublob.list() -> items | nil, err
  ----------------------------------------------------------------------------
    每项 {name, size}，只含 blob。空仓 {}。

  ----------------------------------------------------------------------------
  ublob.usage() -> {used, limit, script_used, shared_limit} | nil, err
  ----------------------------------------------------------------------------
    与 ufs.usage() 同一套：used/limit 是 ufs+ublob 合计。shared_limit=220KiB。

  ============================================================================
  本 demo
  ============================================================================
    write/read/append、含 NUL 的二进制、空文件、视图 crc32/md5（含 raw）、
    第二个 open 应失败、close 后再 open、对已 close 的 view 调用、remove 幂等。

]=]
