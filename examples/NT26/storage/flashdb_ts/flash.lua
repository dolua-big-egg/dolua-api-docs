--[[ flash — SPI 外挂 W25Qxx，整片挂 FlashDB TS（flashdb_ts demo）

  硬件 IO（SPI0 固定脚，CS 用 GPIO8，低有效）

    Pin     GPIO / 默认复用         接到 Flash
    66      GPIO8 / SPI0_SSn0       CS   （gpio.open 控 CS，不走硬件 SSn）
    67      GPIO9 / SPI0_MOSI       MOSI / DI
    28      UART2_RXD / SPI0_MISO   MISO / DO
    29      UART2_TXD / SPI0_SCLK   SCLK

  SPI0 目前固定在 pin66–pin29 这一组，和 UART2 默认脚重叠。
  必须在 rtu_config.cfg 里调整 UART2 引脚映射：[uart.2] pin_map=1。

  不固定 16MB：sfud 读到容量后，offset=0、size=整片（按擦除粒度向下对齐），全部交给 ts。
  本 demo 只挂 TS，不混用 KV / LittleFS。

  配 on_event + mount_timeout_ms=-1：异步挂载。
  空片/脏片：format_full_erase + format_erase_unit=large → 先按 SFDP 最大块（常见 64KB）预擦，
  再只写扇区头，不再 4KB×N 的 repair_sector。合法 TS 再挂直接 fs_ok。
]]

local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local flashdb = require("flashdb")
local log = require("log")

local M = {}

local cfg = {
    bus_hz = 24 * 1000000,
    spi_id = nil,       -- 默认 spi.SPI0
    cs_gpio = 8,
    cs_gpio_type = nil, -- 默认 gpio.INPUT_GPIO
    sfud_name = "flash0",
    timeout_ms = 5000,
    ts = {
        name = "demo_ts",
        max_len = 500,
        rollover = true, -- 写满擦最老扇区再写；false=写满拒绝新写入、保留已有
        -- 空片/脏片预擦：large=SFDP 最大块（64KB）；min=4KB；chip=整片一条命令
        format_full_erase = true,
        format_erase_unit = "large",
        progress_step_pct = 10,
        mount_timeout_ms = -1,
    },
}

M.cfg = cfg

local hold = { spi = nil, cs = nil, sfud = nil, ts = nil, part = nil }
M._hold = hold

local function align_dn(n, g)
    if not g or g <= 0 then
        return n
    end
    local r = n % g
    return r == 0 and n or (n - r)
end

local function clear_hold()
    hold.spi, hold.cs, hold.sfud = nil, nil, nil
    hold.ts, hold.part = nil, nil
end

-- flashdb.ts 异步进度：phase / index / total / pct
local function ts_on_event(ev)
    if type(ev) ~= "table" then
        log.info("[ts] event %s", tostring(ev))
        return
    end
    local phase = tostring(ev.phase or "?")
    if phase == "format_start" then
        log.info("[ts][格式化] 开始 kind=%s", tostring(ev.kind or ""))
    elseif phase == "erase_all" then
        log.info("[ts][预擦] 开始 total=%s", tostring(ev.total))
    elseif phase == "erase_progress" then
        log.info("[ts][预擦] %s/%s (%s%%)",
                 ev.index, ev.total, ev.pct)
    elseif phase == "mount_progress" then
        log.info("[ts][挂载] %s%%", ev.pct)
    elseif phase == "fs_ok" then
        log.info("[ts][挂载] 分区已就绪（未格式化）")
    elseif ev.index ~= nil and ev.total ~= nil then
        log.info("[ts][%s] %s/%s (%s%%)", phase, ev.index, ev.total, ev.pct)
    else
        log.info("[ts][%s]", phase)
    end
end

local function bind_bus()
    local spi_id = cfg.spi_id or spi.SPI0
    local cs_type = cfg.cs_gpio_type or gpio.INPUT_GPIO

    -- SPI0：MOSI=pin67 / MISO=pin28 / SCLK=pin29（与 UART2 默认脚重叠）
    local spi_dev = spi.new(spi_id, {
        bus_hz = cfg.bus_hz,
        data_bits = 8,
        frame_format = spi.CPOL0_CPHA0,
        work_mode = spi.WORK_MODE_FULL_DUPLEX,
    })

    -- CS：GPIO8 / pin66，输出上拉，低有效
    local cs_io = gpio.open(cs_type, cfg.cs_gpio)
    if not cs_io:config(true, true, gpio.PULL_UP) then
        return nil, "cs cfg fail"
    end

    -- sfud.bind：用 SPI+CS 探测 JEDEC，得到 capacity / erase_gran
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
    if hold.ts then
        return true, hold.part
    end

    local sfud0, be = bind_bus()
    if not sfud0 then
        clear_hold()
        return false, be
    end

    local cap, gran = sfud0:capacity(), sfud0:erase_gran()
    if not cap or cap < 8 * 1024 then
        clear_hold()
        return false, "chip capacity too small"
    end

    local off = 0
    local size = align_dn(cap, gran)
    if size < 8 * 1024 then
        clear_hold()
        return false, "aligned size too small"
    end

    log.info("[ts] mount whole chip off=0 size=%s cap=%s gran=%s",
             size, cap, gran)

    -- flashdb.ts：offset=0、size=整片；空片/脏片先 large 预擦再写扇区头
    local ts_obj, te = flashdb.ts(sfud0, {
        name = cfg.ts.name,
        offset = off,
        size = size,
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
    hold.part = {
        capacity = cap,
        erase_gran = gran,
        sfud = cfg.sfud_name,
        ts = { name = ts_obj:name(), offset = off, size = size },
    }
    return true, hold.part
end

function M.sfud()
    return hold.sfud
end

function M.ts()
    return hold.ts
end

function M.part_info()
    return hold.part
end

return M
