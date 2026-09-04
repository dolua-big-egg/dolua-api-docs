--[=[
  flashdb_kv demo — SPI 外挂 Flash，整片挂 FlashDB KV
  ============================================================================
  硬件 IO（必看）
  ============================================================================
    Pin     GPIO / 默认复用         接到 Flash
    66      GPIO8 / SPI0_SSn0       CS   （本 demo 用 gpio 控 CS，低有效）
    67      GPIO9 / SPI0_MOSI       MOSI / DI
    28      UART2_RXD / SPI0_MISO   MISO / DO
    29      UART2_TXD / SPI0_SCLK   SCLK

    SPI0 目前固定在 pin66–pin29 这一组，和 UART2 默认脚重叠。
    必须在 rtu_config.cfg 里把 UART2 挪走，否则 SPI 和串口抢脚：
      [uart.2] pin_map=1
    日志若仍走 UART2，再配 [lua] print_route=2  log_route=2。
    杜邦线尽量短、新、绑紧；调不通就把 bus_hz 降下来，用示波器看 CLK/MOSI。

  ============================================================================
  本 demo
  ============================================================================
    1) flash.init：SPI0 + GPIO8(CS) → sfud 认片，offset=0、size=整片，只挂 kv
    2) kv:get("node")：开机先读已有 node（重启可看到上次 seq）
    3) kv:set / kv:get：string / number / bool / table
    4) kv:set("node")：seq+1 写回，再 get 核对
    5) kv:del 临时键；node 留下给下次开机

]=]

local rt = require("rt")
local log = require("log")
local random = require("random")
local flash = require("flash")

local TAG = "[flashdb_kv]"
local NODE_KEY = "node"
local TMP_STR = "tmp_str"
local TMP_NUM = "tmp_num"
local TMP_BOOL = "tmp_bool"
local TMP_TBL = "tmp_tbl"
local stats = { pass = 0, fail = 0 }

local function run_case(name, fn)
    local ok, err = pcall(fn)
    if ok then
        stats.pass = stats.pass + 1
        log.info("%s[PASS] %s", TAG, name)
        return true
    end
    stats.fail = stats.fail + 1
    log.error("%s[FAIL] %s: %s", TAG, name, tostring(err))
    return false
end

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assertion failed", 2)
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s (got %q expect %q)",
              msg or "not equal", tostring(a), tostring(b)), 2)
    end
end

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

local function print_node(val)
    if val == nil then
        log.info("%s node=(empty)", TAG)
        return
    end
    if type(val) ~= "table" then
        log.info("%s node type=%s", TAG, type(val))
        return
    end
    log.info("%s node seq=%s rand=%s", TAG, tostring(val.seq), tostring(val.rand))
end

log.info("%s start: whole-chip KV, SPI0 + GPIO8(CS)", TAG)

-- flash.init：开 SPI0、GPIO8 作 CS，sfud.bind 认片，整片 flashdb.kv
-- 空片/脏片会 64KB 预擦再写扇区头（on_event 打进度）；合法 KV 直接 fs_ok
log.info("%s flash.init：SPI0+GPIO8(CS)，整片挂 FlashDB KV", TAG)
local ok, part_or_err = flash.init()
if not ok then
    halt("flash.init fail err=" .. tostring(part_or_err)
         .. "  check SPI wiring and rtu_config [uart.2] pin_map=1")
end

local part = part_or_err
local sfud0 = flash.sfud()
local kv = flash.kv()
-- jedec_id / capacity / erase_gran：确认芯片；kv 分区 offset=0、size=整片对齐容量
log.info("%s jedec=%s cap=%s gran=%s",
         TAG, tostring(sfud0:jedec_id()), part.capacity, part.erase_gran)
log.info("%s kv name=%s off=%s size=%s",
         TAG, part.kv.name, part.kv.offset, part.kv.size)

run_case("kv.name", function()
    assert_true(kv ~= nil, "kv nil")
    -- kv:name() 必须和 flash.lua 里 cfg.kv.name 一致
    assert_eq(kv:name(), "demo_kv", "partition name")
    assert_eq(part.kv.offset, 0, "offset")
    assert_true(part.kv.size > 0 and part.kv.size <= part.capacity, "size vs capacity")
end)

log.info("%s ----- read node on boot -----", TAG)
-- kv:get：找不到键返回 nil（没有第二返回值）；table 会按 msgpack 解出来
local boot_node = kv:get(NODE_KEY)
print_node(boot_node)

run_case("kv.set_get_types", function()
    -- set/get 四种类型：string / number / bool / table（值走 msgpack，单条上限 4096）
    log.info("%s kv:set/get string/number/bool/table", TAG)
    local wok, werr = kv:set(TMP_STR, "hello-kv")
    assert_true(wok, "set str: " .. tostring(werr))
    assert_eq(kv:get(TMP_STR), "hello-kv", "get str")

    wok, werr = kv:set(TMP_NUM, 42)
    assert_true(wok, "set num: " .. tostring(werr))
    assert_eq(kv:get(TMP_NUM), 42, "get num")

    wok, werr = kv:set(TMP_BOOL, true)
    assert_true(wok, "set bool: " .. tostring(werr))
    assert_eq(kv:get(TMP_BOOL), true, "get bool")

    local tbl = { id = 1, name = "kv-demo", tags = { "a", "b" } }
    wok, werr = kv:set(TMP_TBL, tbl)
    assert_true(wok, "set tbl: " .. tostring(werr))
    local got = kv:get(TMP_TBL)
    assert_true(type(got) == "table", "get tbl type")
    assert_eq(got.id, 1, "tbl.id")
    assert_eq(got.name, "kv-demo", "tbl.name")
    assert_eq(got.tags[1], "a", "tbl.tags[1]")
end)

run_case("kv.set_node", function()
    -- node 跨重启保留：seq 在上次基础上 +1，rand 每次新抽
    log.info("%s kv:set node seq+1", TAG)
    local new_node = {
        rand = random.randint(1, 2147483647),
        seq = (boot_node and boot_node.seq or 0) + 1,
    }
    local wok, werr = kv:set(NODE_KEY, new_node)
    assert_true(wok, "set node: " .. tostring(werr))
    local saved = kv:get(NODE_KEY)
    assert_true(type(saved) == "table", "saved type")
    assert_eq(saved.seq, new_node.seq, "seq")
    assert_eq(saved.rand, new_node.rand, "rand")
    print_node(saved)
end)

run_case("kv.del", function()
    -- del 找不到键返回 false，不算异常；node 故意不删，留给下次开机
    log.info("%s kv:del tmp keys (keep node)", TAG)
    assert_true(kv:del(TMP_STR), "del str")
    assert_true(kv:get(TMP_STR) == nil, "str still there")
    assert_true(kv:del(TMP_NUM), "del num")
    assert_true(kv:del(TMP_BOOL), "del bool")
    assert_true(kv:del(TMP_TBL), "del tbl")
    -- 不存在的键：del 返回 false，不算异常
    local missing = kv:del("no_such_key")
    log.info("%s del missing -> %s", TAG, tostring(missing))
end)

log.info("%s done pass=%d fail=%d  (node kept for next boot)", TAG, stats.pass, stats.fail)

while true do
    rt.delay(10000)
end

--[=[
  flashdb_kv demo — SPI 外挂 Flash，整片挂 FlashDB KV

  硬件见文件开头 IO 表：SPI0 固定 pin66–29，CS=GPIO8 低有效，W25Qxx。
  容量不写死：sfud:capacity() 读到多少就挂多少，offset=0。
  只挂 KV，不混用 flashdb.ts / LittleFS。
  若这颗芯片之前跑过 TS/LFS demo，第一次会 64KB 预擦再写 KV 扇区头（on_event 打 erase_progress）。
  合法 KV 再挂直接 fs_ok。

  ----------------------------------------------------------------------------
  flashdb.kv(sfud, cfg) -> kv | nil, err
  ----------------------------------------------------------------------------
    cfg.name               分区名
    cfg.offset / cfg.size  字节偏移和长度（本 demo size=整片对齐后容量）
    cfg.format             省略=AUTO；true=强制整区擦再 init；false=不预擦
    cfg.format_full_erase  AUTO 时空片/脏片是否预擦，默认 true
    cfg.format_erase_unit  "min" / "large" / "chip"，或 flashdb.ERASE_*
                           large=SFDP 最大块（常见 64KB）；chip 须 offset=0 且 size=整片
    cfg.sec_size           省略则用芯片 erase_gran
    cfg.on_event           进度回调；配它或 mount_timeout_ms 则挂载期间 yield，API 仍阻塞到完成
    cfg.mount_timeout_ms   -1 一直等到完成
    cfg.progress_step_pct  预擦进度步进，默认 10
    cfg.default            可选默认 KV 表 { key = value, ... }，最多 32 条
    值走 msgpack，单条上限 4096 字节。

  ----------------------------------------------------------------------------
  kv:set(key, value) -> ok, err
  kv:get(key) -> value | nil [, err]
  kv:del(key) -> boolean
  kv:name() -> string
  ----------------------------------------------------------------------------
    value 可以是 nil / bool / number / string / table（可序列化，同 ufs）。
    get 找不到键：返回 nil（没有第二返回值）。
    del 找不到键：返回 false。

  ============================================================================
  本 demo
  ============================================================================
    整片挂 KV；set/get 四种类型；node.seq 跨重启递增。临时键会删，node 留下。

]=]
