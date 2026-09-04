--[=[
  ufs demo — Lua 值落盘（write / read / cmp / list / usage）
  ============================================================================
  本 demo
  ============================================================================
    先清掉本 demo 用过的文件名，再顺序跑：
    usage → 写 nil/bool/number/string/array/table → 读回 → cmp
    → stat / list → remove（含不存在）→ 非法类型 / 非法文件名。
    结束再 usage、再清文件。不扫盘、不 wipe 其它文件。

    这个适合存对象，尽量别用来写太大的文件，大的用ublob，那个有流式读取，但是那个只能存string，
    lua的string本身就是字节流 ，适合用来处理字节。
    然后如果有多个数据需要存，尽量打包成一个tabel对象去存，而不是分成多个key，合并能减少底层占用。

]=]

local rt = require("rt")
local log = require("log")
local ufs = require("ufs")

local N_NIL = "d_nil"
local N_BOOL = "d_bool"
local N_NUM = "d_num"
local N_STR = "d_str"
local N_ARR = "d_arr"
local N_TBL = "d_tbl"
local NAMES = { N_NIL, N_BOOL, N_NUM, N_STR, N_ARR, N_TBL, "d_bad" }

local CFG = {
    id = 1,
    name = "ufs-demo",
    ok = true,
    tags = { "a", "b" },
    nested = { x = 10, y = 20 },
}

ufs.remove(N_NIL)
ufs.remove(N_BOOL)
ufs.remove(N_NUM)
ufs.remove(N_STR)
ufs.remove(N_ARR)
ufs.remove(N_TBL)
ufs.remove("d_bad")

log.info("---- usage ----")
local u, uerr = ufs.usage()
if u then
    log.info("used=%s limit=%s script_used=%s shared_limit=%s",
             u.used, u.limit, u.script_used, u.shared_limit)
else
    log.info("usage fail %s", tostring(uerr))
end

log.info("---- write primitives ----")
local ok, err = ufs.write(N_NIL, nil)
log.info("write nil ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write(N_BOOL, true)
log.info("write bool ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write(N_NUM, 42)
log.info("write num ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write(N_STR, "hello ufs")
log.info("write str ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write(N_ARR, { 1, 2, 3 })
log.info("write arr ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write(N_TBL, CFG)
log.info("write tbl ok=%s err=%s", tostring(ok), tostring(err))

log.info("---- read ----")
local v, rerr = ufs.read(N_NIL)
log.info("read nil v=%s err=%s  (存 nil 成功时也是 nil,nil)", tostring(v), tostring(rerr))
v, rerr = ufs.read(N_BOOL)
log.info("read bool v=%s err=%s", tostring(v), tostring(rerr))
v, rerr = ufs.read(N_NUM)
log.info("read num v=%s err=%s", tostring(v), tostring(rerr))
v, rerr = ufs.read(N_STR)
log.info("read str v=%s err=%s", tostring(v), tostring(rerr))
v, rerr = ufs.read(N_ARR)
if type(v) == "table" then
    log.info("read arr [1]=%s [2]=%s [3]=%s n=%d err=%s",
             tostring(v[1]), tostring(v[2]), tostring(v[3]), #v, tostring(rerr))
else
    log.info("read arr v=%s err=%s", tostring(v), tostring(rerr))
end
v, rerr = ufs.read(N_TBL)
if type(v) == "table" then
    log.info("read tbl id=%s name=%s ok=%s tags[1]=%s nested.x=%s err=%s",
             tostring(v.id), tostring(v.name), tostring(v.ok),
             tostring(v.tags and v.tags[1]), tostring(v.nested and v.nested.x), tostring(rerr))
else
    log.info("read tbl v=%s err=%s", tostring(v), tostring(rerr))
end

log.info("---- cmp ----")
log.info("cmp str same=%s", tostring(ufs.cmp(N_STR, "hello ufs")))
log.info("cmp str diff=%s", tostring(ufs.cmp(N_STR, "other")))
log.info("cmp tbl same=%s", tostring(ufs.cmp(N_TBL, CFG)))
log.info("cmp tbl missing field=%s", tostring(ufs.cmp(N_TBL, { id = 1 })))
log.info("cmp not found=%s", tostring(ufs.cmp("no_such_ufs", "x")))

log.info("---- stat / list ----")
local st, serr = ufs.stat(N_STR)
if st then
    log.info("stat name=%s size=%s is_dir=%s", st.name, st.size, st.is_dir)
else
    log.info("stat fail %s", tostring(serr))
end
local items, lerr = ufs.list()
if items then
    log.info("list n=%d", #items)
    for i = 1, #items do
        log.info("  [%d] name=%s size=%s is_dir=%s",
                 i, items[i].name, items[i].size, items[i].is_dir)
    end
else
    log.info("list fail %s", tostring(lerr))
end

log.info("---- remove ----")
ok, err = ufs.remove(N_STR)
log.info("remove str ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.remove(N_STR)
log.info("remove again (not found) ok=%s err=%s", tostring(ok), tostring(err))
v, rerr = ufs.read(N_STR)
log.info("read after remove v=%s err=%s", tostring(v), tostring(rerr))

log.info("---- fail ----")
ok, err = ufs.write("d_bad", function() end)
log.info("write function ok=%s err=%s", tostring(ok), tostring(err))
ok, err = ufs.write("a/b", "x")
log.info("write bad name ok=%s err=%s", tostring(ok), tostring(err))
st, serr = ufs.stat("no_such_ufs")
log.info("stat missing v=%s err=%s", tostring(st), tostring(serr))

u, uerr = ufs.usage()
if u then
    log.info("---- usage after ---- used=%s limit=%s script_used=%s shared_limit=%s",
             u.used, u.limit, u.script_used, u.shared_limit)
end

for i = 1, #NAMES do
    ufs.remove(NAMES[i])
end
log.info("ufs demo done")

while true do
    rt.delay(10000)
end

--[=[
  ufs demo — Lua 值落盘

  require("ufs")。把可序列化 Lua 值写成受限文件，不是通用 POSIX 文件系统。
  与 lua 脚本、ublob 共用配额 FS_LUA_QUOTA_BYTES（220KiB），按压缩后落盘字节核算。
  可写空间 = 220KiB − 当前 lua 脚本真实落盘。编码 RAM 上限 80KiB（FS_LUA_UFS_ENCODE_MAX）。
  磁盘文件名由底层加前缀 lua_usr_，Lua 侧只传短名。

  ----------------------------------------------------------------------------
  文件名
  ----------------------------------------------------------------------------
    只允许文件名，禁止路径。含 '/' '\\' ':'、控制字符、".." 会 invalid param。
    空名非法。长度还要能拼进 FS_PATH_MAX（前缀 + 名 + '/'）。
    ufs 与 ublob 命名空间分开：同名可以各存一份，list/read 互不可见。

  ----------------------------------------------------------------------------
  可序列化类型
  ----------------------------------------------------------------------------
    nil / boolean / number（整数或浮点）/ string / table。
    table 键只能是 string / number / boolean。
    连续 1..n 整数键且无空洞 → MessagePack array；否则 map。
    嵌套深度上限 10；单表项数上限 4096。
    function / userdata / thread 等 → write 失败 "unsupported value type"。
    过深 → "table depth exceeded"；过大 → "table too large"。

  ----------------------------------------------------------------------------
  ufs.write(name, value) -> ok, err
  ----------------------------------------------------------------------------
    覆盖写。成功 true, nil；失败 false, 错误串（注意不是 nil, err）。
    常见 err：
      序列化失败 / 序列化失败-输出为空
      quota exceeded     共享配额不够
      invalid param      文件名非法
      io error / fs error / already exists（少见）

    例  local ok, err = ufs.write("cfg", { a = 1 })

  ----------------------------------------------------------------------------
  ufs.read(name) -> value, err
  ----------------------------------------------------------------------------
    解压并反序列化。成功 value, nil。
    失败 nil, err。文件不存在 "not found"；目标是目录 "read target is dir"；
    损坏 "not msgpack ufs data" / "bad record" / "反序列化失败"。
    注意：value 本身也可以是 nil（你写入了 nil）。这时返回 nil, nil。
    要用第二返回值区分「读失败」和「存的就是 nil」。

    例  local v, err = ufs.read("cfg")

  ----------------------------------------------------------------------------
  ufs.remove(name) -> ok | nil, err
  ----------------------------------------------------------------------------
    成功或文件本来就不存在：返回 true（幂等）。
    其它失败：nil, err。

  ----------------------------------------------------------------------------
  ufs.stat(name) -> info | nil, err
  ----------------------------------------------------------------------------
    info = { name=string, size=integer, is_dir=boolean }
    size 是解压后的逻辑长度（UMP1+msgpack），不是压缩落盘大小。
    当前 ufs 列表项 is_dir 一般为 false。

  ----------------------------------------------------------------------------
  ufs.list() -> items | nil, err
  ----------------------------------------------------------------------------
    items 是数组，每项 { name, size, is_dir }。只含 ufs 对象，不含 ublob、不含脚本。
    空仓返回 {}，不是 nil。

  ----------------------------------------------------------------------------
  ufs.usage() -> usage | nil, err
  ----------------------------------------------------------------------------
    usage = {
      used          ufs+ublob 当前压缩落盘字节
      limit         二者还能占用的上限（220KiB − lua 脚本落盘）
      script_used   lua 脚本真实落盘
      shared_limit  总配额 220KiB
    }
    和 ublob.usage() 是同一套数字。

  ----------------------------------------------------------------------------
  ufs.cmp(name, value) -> equal | nil, err
  ----------------------------------------------------------------------------
    把 value 与已存对象做深度比较（table 按键值递归，数字按 number 比）。
    文件不存在：返回 false（视为不同），不是错误。
    读/解码失败：nil, err。
    适合「配置有没有变，变了再 write」：if not ufs.cmp("cfg", newcfg) then ufs.write(...) end

  ----------------------------------------------------------------------------
  和 ublob 的差别
  ----------------------------------------------------------------------------
    ufs 存 Lua 值（配置/状态表）；ublob 存原始字节（固件块、日志、图片）。
    配额共用。不要拿 ufs 存大二进制，也不要拿 ublob 当 KV。

  ============================================================================
  本 demo
  ============================================================================
    写入六种值并读回；cmp 相同/不同/不存在；stat+list；remove 幂等；
    function 和带 '/' 的文件名失败；最后删掉本 demo 文件。

]=]
