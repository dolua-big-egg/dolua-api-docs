--[[ flash — SPI 外挂 W25Qxx，整片挂 LittleFS（http_file_lfs）

  硬件与 lfs_flashdb 一致：SPI0 + GPIO8(CS 低有效)。
  本 demo 不分区：sfud 读到容量后，offset=0、size=整片，全部交给 lfs。

  不写 format：能挂就直接挂，空片或损坏才格式化。on_event 打格式化/挂载进度。

  lfs.mount 预擦（仅异步挂载：配了 on_event 或 mount_timeout_ms 才走）：
    format_full_erase  true=格式化前整区擦成 0xFF；false=只写超级块，用到哪块再擦哪块
    format_erase_unit  默认 "large"（SFDP 最大块，常见 64KB）；
                       "min"=最小扇区（常见 4KB）；"chip"=整片一条命令
                       （chip 必须 offset=0 且 size=整片，否则回退 large）
    也可用 lfs.ERASE_MIN / ERASE_LARGE / ERASE_CHIP。
    不写这两项：全擦 + large。

  SPI0 默认脚和 UART2 默认脚冲突。rtu_config.cfg 必须 [uart.2] pin_map=1。
]]

local gpio = require("gpio")
local spi = require("spi")
local sfud = require("sfud")
local lfs = require("lfs")
local log = require("log")

local M = {}

local cfg = {
    -- bus_hz 会就近落到偶数分频档
    bus_hz = 24 * 1000000,
    spi_id = nil,       -- 默认 spi.SPI0
    cs_gpio = 8,
    cs_gpio_type = nil, -- 默认 gpio.INPUT_GPIO
    sfud_name = "flash0",
    timeout_ms = 5000,
    fs = {
        name = "demo_fs",
        -- 空片第一次：不整区预擦，写文件时再按块擦。要干净底改 true。
        format_full_erase = false,
        -- 若打开全擦：用大块（64KB 一类），不要 4KB×4096。
        format_erase_unit = lfs.ERASE_LARGE,
        progress_step_pct = 10,
        mount_timeout_ms = -1, -- 异步挂载：-1 一直等到完成
    },
}

M.cfg = cfg

local hold = { spi = nil, cs = nil, sfud = nil, fs = nil, part = nil }
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
    hold.fs, hold.part = nil, nil
end

-- lfs.mount 异步进度：phase / index / total / pct
local function fs_on_event(ev)
    if type(ev) ~= "table" then
        log.info("[lfs] event %s", tostring(ev))
        return
    end
    local phase = tostring(ev.phase or "?")
    if phase == "format_start" then
        log.info("[lfs][格式化] 开始")
    elseif phase == "erase_skip" then
        log.info("[lfs][格式化] 跳过整区预擦，写时再擦")
    elseif phase == "erase_progress" then
        log.info("[lfs][格式化] 擦除 %s/%s (%s%%)",
                 ev.index, ev.total, ev.pct)
    elseif phase == "mount_progress" then
        log.info("[lfs][挂载] %s%%", ev.pct)
    elseif phase == "fs_ok" then
        log.info("[lfs][挂载] 分区已就绪（未格式化）")
    elseif ev.index ~= nil and ev.total ~= nil then
        log.info("[lfs][%s] %s/%s (%s%%)", phase, ev.index, ev.total, ev.pct)
    else
        log.info("[lfs][%s]", phase)
    end
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
    if hold.fs then
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

    -- 整片：从 0 挂到擦除粒度对齐后的容量
    local off = 0
    local size = align_dn(cap, gran)
    if size < 8 * 1024 then
        clear_hold()
        return false, "aligned size too small"
    end

    log.info("[lfs] mount whole chip off=0 size=%s cap=%s gran=%s",
             size, cap, gran)

    local fs_cfg = {
        name = cfg.fs.name,
        offset = off,
        size = size,
        progress_step_pct = cfg.fs.progress_step_pct,
        mount_timeout_ms = cfg.fs.mount_timeout_ms,
        format_full_erase = cfg.fs.format_full_erase,
        format_erase_unit = cfg.fs.format_erase_unit,
        on_event = fs_on_event,
    }

    local fs_obj, fe = lfs.mount(sfud0, fs_cfg)
    if not fs_obj then
        clear_hold()
        return false, "lfs: " .. tostring(fe)
    end

    hold.fs = fs_obj
    hold.part = {
        capacity = cap,
        erase_gran = gran,
        sfud = cfg.sfud_name,
        fs = { name = fs_obj:name(), offset = off, size = size },
    }
    return true, hold.part
end

function M.sfud()
    return hold.sfud
end

function M.fs()
    return hold.fs
end

function M.part_info()
    return hold.part
end

return M
