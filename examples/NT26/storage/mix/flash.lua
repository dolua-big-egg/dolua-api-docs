--[[ flash — SPI 外挂 W25Qxx，同片混挂 LittleFS + FlashDB TS + FlashDB KV（mix demo）

  硬件 IO（SPI0 固定脚，CS 用 GPIO8，低有效）

    Pin     GPIO / 默认复用         接到 Flash
    66      GPIO8 / SPI0_SSn0       CS   （gpio.open 控 CS，不走硬件 SSn）
    67      GPIO9 / SPI0_MOSI       MOSI / DI
    28      UART2_RXD / SPI0_MISO   MISO / DO
    29      UART2_TXD / SPI0_SCLK   SCLK

  SPI0 目前固定在 pin66–pin29 这一组，和 UART2 默认脚重叠。
  必须在 rtu_config.cfg 里调整 UART2 引脚映射：[uart.2] pin_map=1。

  分区（读 sfud:capacity()，按 erase_gran 向下对齐后切）：
    先 ÷2 → 前一半 LittleFS
    剩下再对半 → TS、KV 各一份
    剩余扇区数若是奇数：一份拿 floor（偶数个扇区），一份拿 ceil（奇数个扇区）
    布局：[FS | TS | KV]，TS/KV 谁前谁后无所谓。
    不能 chip 整片擦：三家分区独立 AUTO 挂载。

  之前若跑过整片 KV/TS/LFS demo，各分区会各自格式化，互不共享旧数据。
]]

local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local flashdb = require("flashdb")
local lfs = require("lfs")
local log = require("log")

local M = {}

local MIN_PART = 8 * 1024

local cfg = {
    bus_hz = 24 * 1000000,
    spi_id = nil,       -- 默认 spi.SPI0
    cs_gpio = 8,
    cs_gpio_type = nil, -- 默认 gpio.INPUT_GPIO
    sfud_name = "flash0",
    timeout_ms = 5000,
    fs = {
        name = "demo_fs",
        format_full_erase = false,
        format_erase_unit = lfs.ERASE_LARGE,
        progress_step_pct = 10,
        mount_timeout_ms = -1,
    },
    ts = {
        name = "demo_ts",
        max_len = 500,
        rollover = true,
        format_full_erase = true,
        format_erase_unit = "large",
        progress_step_pct = 10,
        mount_timeout_ms = -1,
    },
    kv = {
        name = "demo_kv",
        format_full_erase = true,
        format_erase_unit = "large",
        progress_step_pct = 10,
        mount_timeout_ms = -1,
    },
}

M.cfg = cfg

local hold = { spi = nil, cs = nil, sfud = nil, fs = nil, ts = nil, kv = nil, part = nil }
M._hold = hold

local function align_dn(n, g)
    if not g or g <= 0 then
        return n
    end
    local r = n % g
    return r == 0 and n or (n - r)
end

-- cap 按 gran 对齐后：一半 FS，剩余扇区对半给 TS/KV；奇数扇区时一份偶数一份奇数
local function split_layout(cap, gran)
    local total = align_dn(cap, gran)
    local fs_size = align_dn(math.floor(total / 2), gran)
    local rest = total - fs_size
    local rest_units = math.floor(rest / gran)
    local ts_units = math.floor(rest_units / 2)
    local kv_units = rest_units - ts_units
    local ts_size = ts_units * gran
    local kv_size = kv_units * gran

    if fs_size < MIN_PART or ts_size < MIN_PART or kv_size < MIN_PART then
        return nil, string.format(
            "part too small fs=%s ts=%s kv=%s (need >=%s each)",
            fs_size, ts_size, kv_size, MIN_PART)
    end

    return {
        total = total,
        fs = { offset = 0, size = fs_size },
        ts = { offset = fs_size, size = ts_size },
        kv = { offset = fs_size + ts_size, size = kv_size },
    }
end

local function clear_hold()
    hold.spi, hold.cs, hold.sfud = nil, nil, nil
    hold.fs, hold.ts, hold.kv, hold.part = nil, nil, nil, nil
end

local function mount_on_event(tag, ev)
    if type(ev) ~= "table" then
        log.info("[%s] event %s", tag, tostring(ev))
        return
    end
    local phase = tostring(ev.phase or "?")
    if phase == "format_start" then
        log.info("[%s][格式化] 开始 kind=%s", tag, tostring(ev.kind or ""))
    elseif phase == "erase_skip" then
        log.info("[%s][格式化] 跳过整区预擦，写时再擦", tag)
    elseif phase == "erase_all" then
        log.info("[%s][预擦] 开始 total=%s", tag, tostring(ev.total))
    elseif phase == "erase_progress" then
        log.info("[%s][预擦] %s/%s (%s%%)",
                 tag, ev.index, ev.total, ev.pct)
    elseif phase == "mount_progress" then
        log.info("[%s][挂载] %s%%", tag, ev.pct)
    elseif phase == "fs_ok" then
        log.info("[%s][挂载] 分区已就绪（未格式化）", tag)
    elseif ev.index ~= nil and ev.total ~= nil then
        log.info("[%s][%s] %s/%s (%s%%)", tag, phase, ev.index, ev.total, ev.pct)
    else
        log.info("[%s][%s]", tag, phase)
    end
end

local function fs_on_event(ev)
    mount_on_event("lfs", ev)
end

local function ts_on_event(ev)
    mount_on_event("ts", ev)
end

local function kv_on_event(ev)
    mount_on_event("kv", ev)
end

local function bind_bus()
    local spi_id = cfg.spi_id or spi.SPI0
    local cs_type = cfg.cs_gpio_type or gpio.INPUT_GPIO

    local spi_dev = spi.new(spi_id, {
        bus_hz = cfg.bus_hz,
        data_bits = 8,
        frame_format = spi.CPOL0_CPHA0,
        work_mode = spi.WORK_MODE_FULL_DUPLEX,
    })

    local cs_io = gpio.open(cs_type, cfg.cs_gpio)
    if not cs_io:config(true, true, gpio.PULL_UP) then
        return nil, "cs cfg fail"
    end

    local sfud0, e = sfud.bind(spi_dev, cfg.sfud_name, cs_io, {
        cs_active_low = true,
        timeout_ms = cfg.timeout_ms,
    })
    if not sfud0 then
        return nil, "sfud: " .. tostring(e)
    end

    hold.spi, hold.cs, hold.sfud = spi_dev, cs_io, sfud0
    return sfud0
end

function M.init()
    if hold.fs and hold.ts and hold.kv then
        return true, hold.part
    end

    local sfud0, be = bind_bus()
    if not sfud0 then
        clear_hold()
        return false, be
    end

    local cap, gran = sfud0:capacity(), sfud0:erase_gran()
    if not cap or cap < (MIN_PART * 3) then
        clear_hold()
        return false, "chip capacity too small"
    end

    local layout, le = split_layout(cap, gran)
    if not layout then
        clear_hold()
        return false, le
    end

    log.info("[mix] layout cap=%s gran=%s total=%s", cap, gran, layout.total)
    log.info("[mix] fs off=%s size=%s", layout.fs.offset, layout.fs.size)
    log.info("[mix] ts off=%s size=%s", layout.ts.offset, layout.ts.size)
    log.info("[mix] kv off=%s size=%s", layout.kv.offset, layout.kv.size)

    local fs_obj, fe = lfs.mount(sfud0, {
        name = cfg.fs.name,
        offset = layout.fs.offset,
        size = layout.fs.size,
        progress_step_pct = cfg.fs.progress_step_pct,
        mount_timeout_ms = cfg.fs.mount_timeout_ms,
        format_full_erase = cfg.fs.format_full_erase,
        format_erase_unit = cfg.fs.format_erase_unit,
        on_event = fs_on_event,
    })
    if not fs_obj then
        clear_hold()
        return false, "lfs: " .. tostring(fe)
    end
    hold.fs = fs_obj

    local ts_obj, te = flashdb.ts(sfud0, {
        name = cfg.ts.name,
        offset = layout.ts.offset,
        size = layout.ts.size,
        max_len = cfg.ts.max_len,
        rollover = cfg.ts.rollover,
        format_full_erase = cfg.ts.format_full_erase,
        format_erase_unit = cfg.ts.format_erase_unit,
        progress_step_pct = cfg.ts.progress_step_pct,
        mount_timeout_ms = cfg.ts.mount_timeout_ms,
        on_event = ts_on_event,
    })
    if not ts_obj then
        clear_hold()
        return false, "ts: " .. tostring(te)
    end
    hold.ts = ts_obj

    local kv_obj, ke = flashdb.kv(sfud0, {
        name = cfg.kv.name,
        offset = layout.kv.offset,
        size = layout.kv.size,
        format_full_erase = cfg.kv.format_full_erase,
        format_erase_unit = cfg.kv.format_erase_unit,
        progress_step_pct = cfg.kv.progress_step_pct,
        mount_timeout_ms = cfg.kv.mount_timeout_ms,
        on_event = kv_on_event,
    })
    if not kv_obj then
        clear_hold()
        return false, "kv: " .. tostring(ke)
    end
    hold.kv = kv_obj

    hold.part = {
        capacity = cap,
        erase_gran = gran,
        sfud = cfg.sfud_name,
        total = layout.total,
        fs = { name = fs_obj:name(), offset = layout.fs.offset, size = layout.fs.size },
        ts = { name = ts_obj:name(), offset = layout.ts.offset, size = layout.ts.size },
        kv = { name = kv_obj:name(), offset = layout.kv.offset, size = layout.kv.size },
    }
    return true, hold.part
end

function M.sfud()
    return hold.sfud
end

function M.fs()
    return hold.fs
end

function M.ts()
    return hold.ts
end

function M.kv()
    return hold.kv
end

function M.part_info()
    return hold.part
end

return M
