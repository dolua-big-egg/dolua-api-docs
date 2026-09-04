--[=[
  flashdb_ts demo — SPI 外挂 Flash，整片挂 FlashDB TS
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
    1) flash.init：SPI0 + GPIO8(CS) → sfud 认片，offset=0、size=整片，只挂 ts
    2) ts:iter / peek_oldest：开机 dump 已有记录、看最老一条
    3) ts:append：再写 5 条（cnt = last_time+1）
    4) ts:iter：打印写入后的全部
    5) peek_oldest / del_oldest / pop_oldest：只读、只删、读并删最老
    6) 再 dump 看剩余（记录会留在 Flash 上）

]=]

local rt = require("rt")
local log = require("log")
local random = require("random")
local flash = require("flash")

local TAG = "[flashdb_ts]"
local WRITE_N = 5
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

local function print_record(cnt, val, idx)
    if type(val) ~= "table" then
        log.info("%s #%s cnt=%s type=%s", TAG, tostring(idx), tostring(cnt), type(val))
        return
    end
    log.info("%s #%s cnt=%s seq=%s rand=%s",
             TAG, tostring(idx), tostring(cnt), tostring(val.seq), tostring(val.rand))
end

local function dump_all(tag)
    local ts = flash.ts()
    local count = 0
    log.info("%s ----- %s -----", TAG, tag)
    -- ts:iter：从最老到最新；回调 return true 继续，false 提前停
    ts:iter(function(cnt, val)
        count = count + 1
        print_record(cnt, val, count)
        return true
    end)
    if count == 0 then
        log.info("%s (no records) last=%s", TAG, tostring(ts:last_time()))
    else
        log.info("%s total=%s last=%s", TAG, count, tostring(ts:last_time()))
    end
    return count
end

log.info("%s start: whole-chip TS, SPI0 + GPIO8(CS)", TAG)

-- flash.init：开 SPI0、GPIO8 作 CS，sfud.bind 认片，整片 flashdb.ts
-- 空片/脏片会 64KB 预擦再写扇区头（on_event 打进度）；合法 TS 直接 fs_ok
log.info("%s flash.init：SPI0+GPIO8(CS)，整片挂 FlashDB TS", TAG)
local ok, part_or_err = flash.init()
if not ok then
    halt("flash.init fail err=" .. tostring(part_or_err)
         .. "  check SPI wiring and rtu_config [uart.2] pin_map=1")
end

local part = part_or_err
local sfud0 = flash.sfud()
local ts = flash.ts()
-- jedec_id / capacity / erase_gran：确认芯片；ts 分区 offset=0、size=整片对齐容量
log.info("%s jedec=%s cap=%s gran=%s",
         TAG, tostring(sfud0:jedec_id()), part.capacity, part.erase_gran)
log.info("%s ts name=%s off=%s size=%s",
         TAG, part.ts.name, part.ts.offset, part.ts.size)

run_case("ts.name", function()
    assert_true(ts ~= nil, "ts nil")
    -- ts:name() 必须和 flash.lua 里 cfg.ts.name 一致
    assert_eq(ts:name(), "demo_ts", "partition name")
    assert_eq(part.ts.offset, 0, "offset")
    assert_true(part.ts.size > 0 and part.ts.size <= part.capacity, "size vs capacity")
end)

-- 开机把已有 TSL 打出来（第一次运行一般是空）
dump_all("boot dump")

run_case("ts.peek_boot", function()
    -- peek_oldest：只读最老一条，不删除；空库 ok, nil, nil
    log.info("%s ts:peek_oldest", TAG)
    local pok, cnt, val = ts:peek_oldest()
    assert_true(pok, "peek: " .. tostring(cnt))
    if cnt == nil then
        log.info("%s peek empty (first boot or cleaned)", TAG)
    else
        print_record(cnt, val, "oldest")
    end
end)

run_case("ts.append_5", function()
    -- append(value, cnt)：cnt 必须递增；省略 cnt 则用 last_time+1
    -- rollover=true 时写满会擦最老扇区再写
    local last = ts:last_time() or 0
    log.info("%s ts:append %d records, last_time=%s", TAG, WRITE_N, tostring(last))
    for i = 1, WRITE_N do
        local cnt = last + i
        local node = {
            seq = cnt,
            rand = random.randint(1, 2147483647),
            demo = "flashdb_ts",
        }
        local wok, werr = ts:append(node, cnt)
        assert_true(wok, "append cnt=" .. tostring(cnt) .. " " .. tostring(werr))
        log.info("%s appended cnt=%s seq=%s rand=%s",
                 TAG, tostring(cnt), tostring(node.seq), tostring(node.rand))
    end
    assert_eq(ts:last_time(), last + WRITE_N, "last_time")
end)

run_case("ts.iter_after_write", function()
    local n = dump_all("after append")
    assert_true(n >= WRITE_N, "iter count " .. tostring(n))
end)

run_case("ts.peek_del_pop", function()
    -- peek 只看、del 只删、pop 读并删；都针对最老一条
    log.info("%s peek_oldest -> del_oldest -> pop_oldest", TAG)
    local pok, cnt1, val1 = ts:peek_oldest()
    assert_true(pok and cnt1 ~= nil, "peek oldest")
    print_record(cnt1, val1, "peek")

    local dok, derr = ts:del_oldest()
    assert_true(dok, "del: " .. tostring(derr))

    local pok2, cnt2 = ts:peek_oldest()
    assert_true(pok2, "peek after del")
    if cnt2 ~= nil then
        assert_true(cnt2 ~= cnt1, "oldest unchanged after del")
    end

    local pop_ok, pop_cnt, pop_val = ts:pop_oldest()
    assert_true(pop_ok, "pop: " .. tostring(pop_cnt))
    if pop_cnt ~= nil then
        print_record(pop_cnt, pop_val, "pop")
    end
end)

-- del/pop 之后再扫一遍剩余记录
dump_all("after del/pop")

log.info("%s done pass=%d fail=%d", TAG, stats.pass, stats.fail)

while true do
    rt.delay(10000)
end

--[=[
  flashdb_ts demo — SPI 外挂 Flash，整片挂 FlashDB TS

  硬件见文件开头 IO 表：SPI0 固定 pin66–29，CS=GPIO8 低有效，W25Qxx。
  容量不写死：sfud:capacity() 读到多少就挂多少，offset=0。
  只挂 TS，不混用 flashdb.kv / LittleFS。
  若这颗芯片之前跑过 KV/LFS demo，第一次会 64KB 预擦再写扇区头（on_event 打 erase_progress）。
  合法 TS 再挂直接 fs_ok。

  ----------------------------------------------------------------------------
  flashdb.ts(sfud, cfg) -> ts | nil, err
  ----------------------------------------------------------------------------
    cfg.name               分区名
    cfg.offset / cfg.size  字节偏移和长度（本 demo size=整片对齐后容量）
    cfg.max_len            每条 msgpack 编码后上限，必须 > 0
    cfg.rollover           true=写满擦最老扇区再写；false=写满拒写、保留已有
    cfg.format             省略=AUTO；true=强制整区预擦；false=不预擦
    cfg.format_full_erase  AUTO 时空片/脏片是否预擦，默认 true
    cfg.format_erase_unit  "min" / "large" / "chip"，或 flashdb.ERASE_*
                           large=SFDP 最大块（常见 64KB）；chip 须 offset=0 且 size=整片
    cfg.on_event           异步进度；配它或 mount_timeout_ms 才走异步
    cfg.mount_timeout_ms   -1 一直等到完成
    时间戳默认 last_time+1；也可 cfg.get_time = function() return n end

  ----------------------------------------------------------------------------
  ts:append(value [, cnt]) -> ok, err
  ts:last_time() -> integer
  ts:iter(function(cnt, val) ... return continue end) -> ok
  ts:peek_oldest() -> ok, cnt, val     只读最老；空库 ok,nil,nil
  ts:pop_oldest()  -> ok, cnt, val     读并删除最老
  ts:del_oldest()  -> ok               只删最老，空库也 ok
  ts:clean()       -> ok               清全部 TSL（分区还在）
  ts:name()        -> string

  ============================================================================
  本 demo
  ============================================================================
    整片挂 TS；开机 dump；再写 5 条；peek / del / pop。记录会留在 Flash 上。

]=]
