--[=[
  mix demo — 同一片 SPI Flash 上同时挂 LittleFS + FlashDB TS + FlashDB KV
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

  ============================================================================
  分区
  ============================================================================
    sfud:capacity() 按 erase_gran 向下对齐后：
      先 ÷2 → 前一半 LittleFS
      剩下再对半 → TS、KV；剩余扇区数为奇数时一份偶数个扇区、一份奇数个
    布局：[FS | TS | KV]。之前跑过整片 KV/TS/LFS demo，各区会各自格式化。

  ============================================================================
  本 demo
  ============================================================================
    1) flash.init：SPI0 + GPIO8(CS) → 认片，按上面策略切三区并挂上
    2) 核对三区偏移/容量：不重叠、拼起来等于对齐后整片
    3) kv:set / kv:get
    4) ts:append / peek_oldest
    5) lfs 写读 /mix.txt
    6) 再读 kv，确认三区互不覆盖

]=]

local rt = require("rt")
local log = require("log")
local random = require("random")
local flash = require("flash")

local TAG = "[mix]"
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

log.info("%s start: mixed LittleFS + TS + KV, SPI0 + GPIO8(CS)", TAG)

log.info("%s flash.init：读容量后切三区并挂载", TAG)
local ok, part_or_err = flash.init()
if not ok then
    halt("flash.init fail err=" .. tostring(part_or_err)
         .. "  check SPI wiring and rtu_config [uart.2] pin_map=1")
end

local part = part_or_err
local sfud0 = flash.sfud()
local fs = flash.fs()
local ts = flash.ts()
local kv = flash.kv()

log.info("%s jedec=%s cap=%s gran=%s total=%s",
         TAG, tostring(sfud0:jedec_id()), part.capacity, part.erase_gran, part.total)
log.info("%s fs name=%s off=%s size=%s", TAG, part.fs.name, part.fs.offset, part.fs.size)
log.info("%s ts name=%s off=%s size=%s", TAG, part.ts.name, part.ts.offset, part.ts.size)
log.info("%s kv name=%s off=%s size=%s", TAG, part.kv.name, part.kv.offset, part.kv.size)

run_case("layout", function()
    assert_true(fs ~= nil and ts ~= nil and kv ~= nil, "mount nil")
    assert_eq(fs:name(), "demo_fs", "fs name")
    assert_eq(ts:name(), "demo_ts", "ts name")
    assert_eq(kv:name(), "demo_kv", "kv name")

    local gran = part.erase_gran
    assert_eq(part.fs.offset, 0, "fs offset")
    assert_eq(part.ts.offset, part.fs.size, "ts follows fs")
    assert_eq(part.kv.offset, part.fs.size + part.ts.size, "kv follows ts")
    assert_eq(part.fs.size + part.ts.size + part.kv.size, part.total, "cover total")

    -- 先 ÷2 归 FS：对齐后的一半
    local half = part.total - (part.total % 2)
    half = half / 2
    half = half - (half % gran)
    assert_eq(part.fs.size, half, "fs is first half")

    -- 剩余扇区对半；奇数时一份偶数个扇区、一份奇数个
    local rest_units = (part.total - part.fs.size) / gran
    local ts_units = part.ts.size / gran
    local kv_units = part.kv.size / gran
    assert_eq(ts_units + kv_units, rest_units, "ts+kv units")
    assert_true(math.abs(ts_units - kv_units) <= 1, "ts/kv split")
    if (rest_units % 2) == 1 then
        local odd_even = ((ts_units % 2) ~= (kv_units % 2))
        assert_true(odd_even, "odd rest: one odd one even")
    end

    local info = fs:info()
    assert_eq(info.offset, part.fs.offset, "fs info offset")
    assert_eq(info.size, part.fs.size, "fs info size")
    log.info("%s layout ok fs=%s ts=%s kv=%s (units ts=%s kv=%s)",
             TAG, part.fs.size, part.ts.size, part.kv.size, ts_units, kv_units)
end)

run_case("kv.set_get", function()
    local wok, werr = kv:set("mix_str", "hello-mix")
    assert_true(wok, "set str: " .. tostring(werr))
    assert_eq(kv:get("mix_str"), "hello-mix", "get str")

    local node = { seq = 1, rand = random.randint(1, 2147483647), from = "mix" }
    wok, werr = kv:set("node", node)
    assert_true(wok, "set node: " .. tostring(werr))
    local got = kv:get("node")
    assert_true(type(got) == "table", "node type")
    assert_eq(got.seq, 1, "node.seq")
    assert_eq(got.from, "mix", "node.from")
    log.info("%s kv node seq=%s rand=%s", TAG, tostring(got.seq), tostring(got.rand))
end)

run_case("ts.append_peek", function()
    local last = ts:last_time() or 0
    local cnt = last + 1
    local rec = { seq = cnt, demo = "mix", rand = random.randint(1, 2147483647) }
    local wok, werr = ts:append(rec, cnt)
    assert_true(wok, "append: " .. tostring(werr))
    assert_eq(ts:last_time(), cnt, "last_time")

    local pok, pcnt, pval = ts:peek_oldest()
    assert_true(pok and pcnt ~= nil, "peek")
    assert_true(type(pval) == "table", "peek val")
    log.info("%s ts peek cnt=%s seq=%s rand=%s last=%s",
             TAG, tostring(pcnt), tostring(pval.seq), tostring(pval.rand), tostring(ts:last_time()))
end)

run_case("lfs.write_read", function()
    local path = "/mix.txt"
    local payload = "mix-lfs-" .. tostring(part.capacity)
    local f, e = fs:open(path, "w")
    assert_true(f ~= nil, "open w: " .. tostring(e))
    local n, we = f:write(payload)
    assert_true(n == #payload, "write: " .. tostring(we))
    assert_true(f:close(), "close w")

    local fr, re = fs:open(path, "r")
    assert_true(fr ~= nil, "open r: " .. tostring(re))
    local data, rerr = fr:read()
    assert_true(data ~= nil, "read: " .. tostring(rerr))
    assert_eq(data, payload, "payload")
    assert_true(fr:close(), "close r")

    local st = fs:stat(path)
    assert_true(st ~= nil and st.type == "file", "stat")
    assert_eq(st.size, #payload, "stat size")
    log.info("%s lfs file ok path=%s size=%s", TAG, path, st.size)
end)

run_case("isolation", function()
    -- lfs / ts 写完后 KV 仍在，说明三区没有互相覆盖
    assert_eq(kv:get("mix_str"), "hello-mix", "kv overwritten")
    local node = kv:get("node")
    assert_true(type(node) == "table" and node.from == "mix", "kv node lost")

    local pok, cnt = ts:peek_oldest()
    assert_true(pok and cnt ~= nil, "ts emptied")

    local st = fs:stat("/mix.txt")
    assert_true(st ~= nil and st.type == "file", "lfs file lost")
    log.info("%s isolation ok kv/ts/lfs still intact", TAG)
end)

log.info("%s done pass=%d fail=%d", TAG, stats.pass, stats.fail)

while true do
    rt.delay(10000)
end

--[=[
  mix demo — 同一片 SPI Flash 同时挂 LittleFS + FlashDB TS + FlashDB KV

  硬件见文件开头 IO 表：SPI0 固定 pin66–29，CS=GPIO8 低有效，W25Qxx。
  容量不写死：sfud:capacity() 读到多少切多少。
  切分：对齐后先 ÷2 给 FS，剩余对半给 TS/KV；奇数扇区时一份奇数一份偶数。

  换这个工程会按新区格式化，覆盖原先整片 KV/TS/LFS demo 的数据。

  ============================================================================
  本 demo
  ============================================================================
    挂三区；核对布局；各写一条；再读确认互不覆盖。

]=]
