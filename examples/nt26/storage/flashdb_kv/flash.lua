--[[ flash — SPI 外挂 W25Qxx，整片挂 FlashDB KV（flashdb_kv demo）

  硬件 IO（SPI0 固定脚，CS 用 GPIO8，低有效）

    Pin     GPIO / 默认复用         接到 Flash
    66      GPIO8 / SPI0_SSn0       CS   （gpio.open 控 CS，不走硬件 SSn）
    67      GPIO9 / SPI0_MOSI       MOSI / DI
    28      UART2_RXD / SPI0_MISO   MISO / DO
    29      UART2_TXD / SPI0_SCLK   SCLK

  SPI0 目前固定在 pin66–pin29 这一组，和 UART2 默认脚重叠。
  必须在 rtu_config.cfg 里调整 UART2 引脚映射：[uart.2] pin_map=1。

  不固定 16MB：sfud 读到容量后，offset=0、size=整片（按擦除粒度向下对齐），全部交给 kv。
  本 demo 只挂 KV，不混用 TS / LittleFS。

  配 on_event + mount_timeout_ms=-1：挂载 API 仍阻塞到完成，阻塞期间回调进度。
  空片/脏片：format_full_erase + format_erase_unit=large → 先按 SFDP 最大块（常见 64KB）预擦，
  再只写扇区头。合法 KV 再挂直接 fs_ok。
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
    cs_gpio_type = nil, -- 默认 gpio.BY_GPIO（旧名 gpio.INPUT_GPIO 仍可用）
    sfud_name = "flash0",
    timeout_ms = 5000,
    kv = {
        name = "demo_kv",
        -- format 省略 = AUTO。空片/脏片先按 large（64KB）预擦，再写扇区头。
        format_full_erase = true,
        format_erase_unit = "large",
        progress_step_pct = 10,
        mount_timeout_ms = -1,
    },
}

M.cfg = cfg

local hold = { spi = nil, cs = nil, sfud = nil, kv = nil, part = nil }
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
    hold.kv, hold.part = nil, nil
end

-- flashdb.kv 异步进度：phase / index / total / pct（挂载 API 仍阻塞到完成）
local function kv_on_event(ev)
    if type(ev) ~= "table" then
        log.info("[kv] event %s", tostring(ev))
        return
    end
    local phase = tostring(ev.phase or "?")
    if phase == "format_start" then
        log.info("[kv][格式化] 开始 kind=%s", tostring(ev.kind or ""))
    elseif phase == "erase_all" then
        log.info("[kv][预擦] 开始 total=%s", tostring(ev.total))
    elseif phase == "erase_progress" then
        log.info("[kv][预擦] %s/%s (%s%%)",
                 ev.index, ev.total, ev.pct)
    elseif phase == "mount_progress" then
        log.info("[kv][挂载] %s%%", ev.pct)
    elseif phase == "fs_ok" then
        log.info("[kv][挂载] 分区已就绪（未格式化）")
    elseif ev.index ~= nil and ev.total ~= nil then
        log.info("[kv][%s] %s/%s (%s%%)", phase, ev.index, ev.total, ev.pct)
    else
        log.info("[kv][%s]", phase)
    end
end

local function bind_bus()
    local spi_id = cfg.spi_id or spi.SPI0
    local cs_type = cfg.cs_gpio_type or gpio.BY_GPIO

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
    if hold.kv then
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

    log.info("[kv] mount whole chip off=0 size=%s cap=%s gran=%s",
             size, cap, gran)

    -- flashdb.kv：offset=0、size=整片；空片/脏片先 large 预擦再写扇区头
    local kv_obj, ke = flashdb.kv(sfud0, {
        name = cfg.kv.name,
        offset = off,
        size = size,
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
        kv = { name = kv_obj:name(), offset = off, size = size },
    }
    return true, hold.part
end

function M.sfud()
    return hold.sfud
end

function M.kv()
    return hold.kv
end

function M.part_info()
    return hold.part
end

return M
