--[=[
  littlefs demo — SPI 外挂 Flash，整片挂 LittleFS
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
    日志若仍走 UART2，再配 [lua] print_route=uart2  log_route=uart2。
    杜邦线尽量短、新、绑紧；调不通就把 bus_hz 降下来，用示波器看 CLK/MOSI。

  ============================================================================
  本 demo
  ============================================================================
    1) flash.init：SPI0 + GPIO8(CS) → sfud 认片，offset=0、size=整片，只挂 lfs
    2) fs:info：核对分区名 / 偏移 / 容量
    3) open/write/read/stat：写 /demo.txt 再读回
    4) mkdir + dir:read：建 /dir，写 a.txt，列目录
    5) write 8KB + seek：写 /blob.bin，校验头尾
    6) rename / remove：改名删除，确认文件已没

]=]

local rt = require("rt")
local log = require("log")
local flash = require("flash")

local TAG = "[littlefs]"
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

log.info("%s start: whole-chip LittleFS, SPI0 + GPIO8(CS)", TAG)

-- flash.init：开 SPI0、GPIO8 作 CS，sfud.bind 认片，整片 lfs.mount
-- 空片/坏超级块会格式化（on_event 打进度）；合法 LittleFS 直接挂上
log.info("%s flash.init：SPI0+GPIO8(CS)，整片挂 LittleFS", TAG)
local ok, part_or_err = flash.init()
if not ok then
    halt("flash.init fail err=" .. tostring(part_or_err)
         .. "  check SPI wiring and rtu_config [uart.2] pin_map=1")
end

local part = part_or_err
local sfud0 = flash.sfud()
-- jedec_id / capacity / erase_gran：确认芯片型号和擦除粒度（挂载 size 按 gran 向下对齐）
log.info("%s jedec=%s cap=%s gran=%s",
         TAG, tostring(sfud0:jedec_id()), part.capacity, part.erase_gran)
log.info("%s fs name=%s off=%s size=%s",
         TAG, part.fs.name, part.fs.offset, part.fs.size)

run_case("lfs.info", function()
    local fs = flash.fs()
    assert_true(fs ~= nil, "fs nil")
    -- fs:info() 读已挂分区：name / offset / size / block_size
    local info = fs:info()
    assert_true(info ~= nil, "info nil")
    assert_eq(info.name, "demo_fs", "fs name")
    assert_eq(info.offset, 0, "fs offset")
    assert_eq(info.size, part.fs.size, "fs size")
    assert_true(info.size > 0 and info.size <= part.capacity, "size vs capacity")
    log.info("%s info name=%s off=%s size=%s block=%s",
             TAG, info.name, info.offset, info.size, info.block_size)
end)

run_case("lfs.write_read_file", function()
    local fs = flash.fs()
    local path = "/demo.txt"
    local payload = "hello-littlefs-" .. tostring(part.capacity)

    -- open("w") 没有则创建；write 写字符串；close 落盘
    log.info("%s open/write %s", TAG, path)
    local f, e = fs:open(path, "w")
    assert_true(f ~= nil, "open w: " .. tostring(e))
    local n, we = f:write(payload)
    assert_true(n ~= nil and n == #payload, "write: " .. tostring(we))
    assert_true(f:close(), "close w")

    -- open("r") + read() 省略长度 = 读到 EOF
    log.info("%s open/read %s", TAG, path)
    local fr, re = fs:open(path, "r")
    assert_true(fr ~= nil, "open r: " .. tostring(re))
    local data, rerr = fr:read()
    assert_true(data ~= nil, "read: " .. tostring(rerr))
    assert_eq(data, payload, "payload mismatch")
    assert_true(fr:close(), "close r")

    -- stat：type=file/dir，size=字节数
    local st, serr = fs:stat(path)
    assert_true(st ~= nil, "stat: " .. tostring(serr))
    assert_eq(st.type, "file", "stat type")
    assert_eq(st.size, #payload, "stat size")
    log.info("%s file ok path=%s size=%s", TAG, path, st.size)
end)

run_case("lfs.mkdir_dir", function()
    local fs = flash.fs()
    -- mkdir：已存在时本平台可能返回 exist，不算失败
    log.info("%s mkdir /dir", TAG)
    local mok, merr = fs:mkdir("/dir")
    assert_true(mok or tostring(merr) == "exist", "mkdir: " .. tostring(merr))

    local f, e = fs:open("/dir/a.txt", "w")
    assert_true(f ~= nil, "open dir file: " .. tostring(e))
    assert_true(f:write("abc") == 3, "write dir file")
    assert_true(f:close(), "close dir file")

    -- dir:read() 一次一项，读到 nil 结束；用完 dir:close()
    log.info("%s dir /dir", TAG)
    local d, derr = fs:dir("/dir")
    assert_true(d ~= nil, "dir: " .. tostring(derr))
    local nfile = 0
    while true do
        local ent = d:read()
        if ent == nil then
            break
        end
        log.info("%s dir ent name=%s type=%s size=%s",
                 TAG, ent.name, ent.type, ent.size)
        if ent.name == "a.txt" then
            nfile = nfile + 1
            assert_eq(ent.type, "file", "ent type")
            assert_eq(ent.size, 3, "ent size")
        end
    end
    assert_true(d:close(), "dir close")
    assert_true(nfile == 1, "a.txt not listed")
end)

run_case("lfs.chunk_8kb", function()
    local fs = flash.fs()
    local path = "/blob.bin"
    local chunk = string.rep("A", 8 * 1024)
    -- 写 8KB 后 sync，再 seek 校验头 16 字节和尾 16 字节
    log.info("%s write 8KB %s", TAG, path)
    local f, e = fs:open(path, "w")
    assert_true(f ~= nil, "open: " .. tostring(e))
    local n, we = f:write(chunk)
    assert_true(n == #chunk, "write: " .. tostring(we))
    assert_true(f:sync(), "sync")
    assert_true(f:close(), "close w")

    local st = fs:stat(path)
    assert_true(st ~= nil and st.size == #chunk, "size expect " .. #chunk)

    local fr = assert(fs:open(path, "r"))
    local head = fr:read(16)
    assert_eq(head, string.rep("A", 16), "head")
    -- seek("end", -16)：相对文件尾回退 16 字节再读尾
    fr:seek("end", -16)
    local tail = fr:read(16)
    assert_eq(tail, string.rep("A", 16), "tail")
    fr:close()
    log.info("%s chunk ok size=%s", TAG, st.size)
end)

run_case("lfs.rename_remove", function()
    local fs = flash.fs()
    -- rename 后旧路径 stat 应为 nil；remove 文件后再 remove 空目录
    log.info("%s rename /demo.txt -> /demo2.txt, then remove", TAG)
    assert_true(fs:rename("/demo.txt", "/demo2.txt"), "rename")
    local st = fs:stat("/demo2.txt")
    assert_true(st ~= nil and st.type == "file", "renamed missing")
    assert_true(fs:stat("/demo.txt") == nil, "old name still exists")

    assert_true(fs:remove("/demo2.txt"), "remove demo2.txt")
    assert_true(fs:remove("/blob.bin"), "remove blob.bin")
    assert_true(fs:remove("/dir/a.txt"), "remove dir/a.txt")
    assert_true(fs:remove("/dir"), "remove dir")
    assert_true(fs:stat("/demo2.txt") == nil, "demo2.txt still exists")
end)

log.info("%s done pass=%d fail=%d", TAG, stats.pass, stats.fail)

while true do
    rt.delay(10000)
end

--[=[
  littlefs demo — SPI 外挂 Flash，整片挂 LittleFS

  硬件见文件开头 IO 表：SPI0 固定 pin66–29，CS=GPIO8 低有效，W25Qxx。
  容量不写死：sfud:capacity() 读到多少就挂多少，offset=0。
  只挂 LittleFS，不混用 flashdb.kv / flashdb.ts。
  若这颗芯片之前跑过 KV/TS demo，第一次会格式化成 LittleFS。

  ----------------------------------------------------------------------------
  lfs.mount(sfud, cfg) -> fs | nil, err
  ----------------------------------------------------------------------------
    cfg.name               分区名
    cfg.offset / cfg.size  字节偏移和长度（本 demo size=整片对齐后容量）
    cfg.format             省略=AUTO（能挂就挂，坏了才格式化）
                           true=强制格式化  false=损坏也不格式化
    cfg.format_full_erase  格式化前是否整区预擦，默认 true
    cfg.format_erase_unit  "min" / "large" / "chip"，或 lfs.ERASE_*
    cfg.on_event           异步进度回调；配了它或 mount_timeout_ms 才走异步
    cfg.mount_timeout_ms   -1 一直等到完成
    返回 已挂载 fs 对象

  ----------------------------------------------------------------------------
  fs:info() -> { name, offset, size, block_size }
  fs:name() -> string
  fs:open(path, mode) -> file | nil, err
  ----------------------------------------------------------------------------
    mode  "r" / "w" / "a" / "r+" / "w+" / "a+"
    写：file:write(str) -> n | nil, err
        file:sync() / file:close()
    读：file:read([n])  省略 n 读到 EOF
        file:seek("set"|"cur"|"end", off)
        file:tell() / file:size()
        file:crc8 / crc16 / crc32 / md5()

  ----------------------------------------------------------------------------
  fs:mkdir(path) / fs:remove(path) / fs:rename(old, new)
  fs:stat(path) -> { name, type="file"|"dir", size } | nil, err
  fs:dir([path]) -> dir；dir:read() 得一项或 nil；dir:close()

  ============================================================================
  本 demo
  ============================================================================
    整片挂 LittleFS；写小文件、建目录、写 8KB、改名删除。不依赖网络。

]=]
