--[=[
  spi_api demo — SPI0 读外挂 NOR Flash 的 JEDEC ID
  ============================================================================
  硬件 IO（必看）
  ============================================================================
    Pin     GPIO / 默认复用         接到 Flash
    66      GPIO8 / SPI0_SSn0       CS   （本 demo 用 spi.cs_gpio，低有效）
    67      GPIO9 / SPI0_MOSI       MOSI / DI
    28      UART2_RXD / SPI0_MISO   MISO / DO
    29      UART2_TXD / SPI0_SCLK   SCLK

    SPI0 目前固定在 pin66–pin29 这一组，和 UART2 默认脚重叠。
    必须在 rtu_config.cfg 里把 UART2 挪走，否则 SPI 和串口抢脚：
      [uart.2] pin_map=1
    日志若仍走 UART2，再配 [lua] print_route=uart2  log_route=uart2。

  ============================================================================
  本 demo
  ============================================================================
    1) spi.new(SPI0)：配时钟、模式、GPIO8 作 CS
    2) id / get_bus_hz / get_status：看控制器和实际 SCLK
    3) set_cs + transfer：发 JEDEC 命令 0x9F，读 3 字节芯片 ID
    4) 每 2 秒再读一次（W25Q64 常见 EF 40 17）

]=]

local rt = require("rt")
local log = require("log")
local spi = require("spi")

local CS_GPIO = 8
local CMD_JEDEC = 0x9F
local TAG = "[spi_api]"

local function to_hex(s)
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02X", s:byte(i))
    end
    return table.concat(t, " ")
end

local function halt(msg)
    log.error("%s %s", TAG, msg)
    while true do
        rt.delay(10000)
    end
end

-- 全双工：MOSI 发 0x9F + 3 个 dummy，MISO 第 2~4 字节才是厂商/类型/容量
local function read_jedec(dev)
    local ok, e = dev:set_cs(true)
    if not ok then
        return nil, "set_cs on: " .. tostring(e)
    end
    local rx, te = dev:transfer(string.char(CMD_JEDEC, 0x00, 0x00, 0x00))
    local off_ok, off_e = dev:set_cs(false)
    if not off_ok then
        return nil, "set_cs off: " .. tostring(off_e)
    end
    if not rx or #rx < 4 then
        return nil, "transfer: " .. tostring(te)
    end
    return {
        raw = rx,
        mfr = rx:byte(2),
        mem = rx:byte(3),
        cap = rx:byte(4),
    }
end

log.info("%s start: SPI0 + GPIO8(CS), read Flash JEDEC ID", TAG)

local dev, nerr = spi.new(spi.SPI0, {
    bus_hz = 1 * 1000000, -- 杜邦线先用 1M；稳定后可改 24*1000000
    data_bits = 8,
    frame_format = spi.CPOL0_CPHA0,
    work_mode = spi.WORK_MODE_FULL_DUPLEX,
    cs_gpio = {
        enabled = true,
        gpio = CS_GPIO,
        active_low = true,
        pull_mode = spi.PULL_UP,
    },
})
if not dev then
    halt("spi.new fail: " .. tostring(nerr)
         .. "  check rtu_config [uart.2] pin_map=1")
end

log.info("%s new ok id=%s bus_hz=%s (requested 1M, actual may snap to a divider)",
         TAG, tostring(dev:id()), tostring(dev:get_bus_hz()))

local st = dev:get_status()
if st then
    log.info("%s status busy=%s data_lost=%s mode_fault=%s spi_id=%s",
             TAG, tostring(st.busy), tostring(st.data_lost),
             tostring(st.mode_fault), tostring(st.spi_id))
end

while true do
    local id, err = read_jedec(dev)
    if not id then
        log.error("%s JEDEC fail: %s", TAG, tostring(err))
    elseif id.mfr == 0x00 or id.mfr == 0xFF then
        log.error("%s JEDEC looks empty hex=%s  check CS/MOSI/MISO/SCLK wiring",
                  TAG, to_hex(id.raw))
    else
        log.info("%s JEDEC %02X %02X %02X  (tx/rx=%s)",
                 TAG, id.mfr, id.mem, id.cap, to_hex(id.raw))
    end
    rt.delay(2000)
end

--[=[
  spi_api demo — SPI0 读外挂 NOR Flash JEDEC ID

  spi 是平台扩展模块。每路控制器同时只允许一个实例。
  命令/数据必须是字符串，不支持字节表：
      string.char(0x9F, 0x00, 0x00, 0x00)
      "\x9F\x00\x00\x00"        等价
      {0x9F, 0x00}              错：transfer 不收 table

  NOR Flash JEDEC：CS 拉低 → 全双工发 9F 00 00 00 → CS 拉高。
  回包第 1 字节是时钟空位，第 2~4 字节才是 ID。W25Q64 常见 EF 40 17。

  ----------------------------------------------------------------------------
  常量
  ----------------------------------------------------------------------------
    spi.SPI0 / SPI1
    spi.WORK_MODE_FULL_DUPLEX / WORK_MODE_TX_ONLY
    spi.CPOL0_CPHA0 / CPOL0_CPHA1 / CPOL1_CPHA0 / CPOL1_CPHA1
    spi.PULL_AUTO / PULL_UP / PULL_DOWN     （给 cs_gpio.pull_mode）
    spi.TIMEOUT_FOREVER

  ----------------------------------------------------------------------------
  spi.new(id [, cfg]) -> dev | nil, err
  ----------------------------------------------------------------------------
    id   spi.SPI0 / SPI1
    cfg  可选表
         bus_hz        请求 SCLK（Hz），会落到偶数分频档；用 get_bus_hz 看实际值
         data_bits     默认 8
         frame_format  默认 spi.CPOL0_CPHA0（NOR Flash 常用）
         lsb_first     默认 false
         work_mode     默认 FULL_DUPLEX
         cs_gpio       可选，交给 spi:set_cs 管片选
                       enabled / gpio / pin_no / active_low / pull_mode
    失败返回 nil, err：id 非法、该路已被占用、硬件 init 失败

  ----------------------------------------------------------------------------
  dev:transfer(tx [, timeout_ms]) -> rx | nil, err
  ----------------------------------------------------------------------------
    全双工，tx/rx 等长。tx 非空字符串。timeout_ms 默认 1000。
    TX_ONLY 模式不能用。

  ----------------------------------------------------------------------------
  dev:send(tx [, timeout_ms]) -> boolean[, err]
  dev:recv(len [, timeout_ms]) -> string|nil[, err]
  ----------------------------------------------------------------------------
    只发 / 只收。片选要自己用 set_cs 包住整段事务。
    读 JEDEC 也可用：set_cs(true) → send("\x9F") → recv(3) → set_cs(false)

  ----------------------------------------------------------------------------
  dev:set_cs(active) -> boolean[, err]
  ----------------------------------------------------------------------------
    active=true 表示片选有效（本 demo 低有效 → 脚拉低）。
    必须在 new() 里配了 cs_gpio.enabled=true。

  ----------------------------------------------------------------------------
  dev:get_bus_hz() -> hz | nil, err
  dev:get_status() -> { busy, data_lost, mode_fault, spi_id } | nil, err
  dev:id() -> integer
  dev:deinit() -> boolean[, err]
  ----------------------------------------------------------------------------
    get_bus_hz 是分频后的实际 SCLK，不是 new 时的请求值。
    对象回收时会自动 deinit。

  ============================================================================
  本 demo
  ============================================================================
    SPI0 + GPIO8(CS) 读 JEDEC。不走 sfud / LittleFS / FlashDB。
    通讯通了再去跑 storage 下的文件系统 demo。

]=]
