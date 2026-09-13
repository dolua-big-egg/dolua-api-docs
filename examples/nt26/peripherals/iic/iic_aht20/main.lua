--[=[
  iic_aht20 demo — I2C0 读 AHT20 温湿度
  ============================================================================
  本 demo
  ============================================================================
    1) i2c.new I2C0
    2) 初始化 AHT20（write BE 08 00）
    3) 每 2 秒测量并打印温湿度；失败则重新初始化

]=]

local rt = require("rt")
local log = require("log")
local i2c = require("i2c")

local ADDR = 0x38
local CMD_INIT = string.char(0xBE, 0x08, 0x00)
local CMD_MEAS = string.char(0xAC, 0x33, 0x00)
local MEAS_WAIT_MS = 80

local function to_hex(s)
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02X", s:byte(i))
    end
    return table.concat(t)
end

local bus = i2c.new(i2c.I2C0, {
    bus_speed = i2c.BUS_SPEED_STANDARD,
    timeout_ms = 100,
})

rt.delay(50)

local function aht20_init()
    if not bus:write(ADDR, CMD_INIT) then
        return false
    end
    rt.delay(10)
    return true
end

-- 测量命令 → 等转换完成 → 读 7 字节 → 解析 20bit 温湿度
local function aht20_read()
    if not bus:write(ADDR, CMD_MEAS) then
        return nil, "meas"
    end
    rt.delay(MEAS_WAIT_MS)

    local raw = bus:read(ADDR, 7)
    if not raw or #raw < 7 then
        return nil, "rd"
    end
    log.info("raw n=%d hex=%s", #raw, to_hex(raw))

    if (raw:byte(1) & 0x80) ~= 0 then
        return nil, "busy"
    end

    -- 湿度 = b2b3 + b4 高 4bit；温度 = b4 低 4bit + b5b6
    -- 用乘法组数，避免位移和 & 的优先级把高 4bit 丢掉
    local b2, b3, b4, b5, b6 = raw:byte(2, 6)
    local raw_h = b2 * 4096 + b3 * 16 + (b4 >> 4)
    local raw_t = (b4 % 16) * 65536 + b5 * 256 + b6
    local humi = raw_h / 1048576.0 * 100.0
    local temp = raw_t / 1048576.0 * 200.0 - 50.0
    return {temp = temp, humi = humi}
end

local inited = false
while true do
    if not inited then
        inited = aht20_init()
        if inited then
            log.info("AHT20 init ok, addr=0x%02X", ADDR)
        else
            log.warn("AHT20 init fail, retry")
            rt.delay(1000)
        end
    else
        local d, err = aht20_read()
        if d then
            log.info("temp=%.2f C humi=%.2f %%RH", d.temp, d.humi)
            rt.delay(2000)
        else
            log.warn("AHT20 read fail %s, re-init", err)
            inited = false
            rt.delay(1000)
        end
    end
end

--[=[
  iic_aht20 demo — I2C0 读 AHT20 温湿度

  i2c 是平台扩展模块。先 new 得到总线对象，再 write / read。
  每路控制器同时只允许一个实例。本 demo 只用 write / read；其余接口见下方。

  设备地址：写 7bit（AHT20=0x38）。写成 8bit 写地址 0x70 也能用，大于 0x7F 时底层右移 1 位。

  命令/数据必须是字符串，不支持字节表：
      string.char(0xBE, 0x08, 0x00)
      "\xBE\x08\x00"            等价
      "0xBE 0x08"               错：这是 ASCII 文本
      {0xBE, 0x08, 0x00}        错：write 不收 table

  ----------------------------------------------------------------------------
  常量
  ----------------------------------------------------------------------------
    i2c.I2C0 / I2C1
    i2c.BUS_SPEED_STANDARD     100kHz（常用）
    i2c.BUS_SPEED_FAST         400kHz
    i2c.BUS_SPEED_FAST_PLUS
    i2c.BUS_SPEED_HIGH

  ----------------------------------------------------------------------------
  i2c.new(id [, cfg]) -> bus
  ----------------------------------------------------------------------------
    id   i2c.I2C0 / I2C1
    cfg  可选表，省略则用默认速率和 100ms 超时
         bus_speed    见上面常量
         timeout_ms   单次传输超时，毫秒
    返回 总线对象
    失败抛错：id 非法、该路已被占用、硬件 init 失败
    例   local bus = i2c.new(i2c.I2C0, { bus_speed = i2c.BUS_SPEED_STANDARD, timeout_ms = 100 })

  ----------------------------------------------------------------------------
  bus:write(dev_addr, data) -> boolean
  ----------------------------------------------------------------------------
    dev_addr  7bit 或 8bit 设备地址
    data      非空字符串（二进制）
    返回      true 成功，false 失败（未 init、空数据、总线 NACK/超时）
    例        bus:write(0x38, string.char(0xAC, 0x33, 0x00))

  ----------------------------------------------------------------------------
  bus:read(dev_addr, len) -> string|nil
  ----------------------------------------------------------------------------
    dev_addr  同上
    len       要读的字节数，必须 > 0
    返回      成功为长度为 len 的字符串，失败 nil
    例        local raw = bus:read(0x38, 7)

  ----------------------------------------------------------------------------
  bus:mem_write(dev_addr, mem_addr, data [, mem_addr_len]) -> boolean
  ----------------------------------------------------------------------------
    先发寄存器地址，再写 data。适合「寄存器型」芯片；AHT20 不用这个。
    mem_addr      寄存器地址
    data          非空字符串
    mem_addr_len  寄存器地址字节数，默认 1
    返回          true / false
    例            bus:mem_write(0x48, 0x00, string.char(0xAB))
                  bus:mem_write(0x50, 0x1234, "\x00\x01", 2)

  ----------------------------------------------------------------------------
  bus:mem_read(dev_addr, mem_addr, len [, mem_addr_len]) -> string|nil
  ----------------------------------------------------------------------------
    先发寄存器地址，再读 len 字节。AHT20 不用这个。
    mem_addr / mem_addr_len  同 mem_write，默认 1 字节地址
    len                      必须 > 0
    返回                     成功为字符串，失败 nil
    例                       local val = bus:mem_read(0x48, 0x00, 2)

  ----------------------------------------------------------------------------
  bus:scan() -> { addr, ... }
  ----------------------------------------------------------------------------
    扫描总线上有应答的 7bit 地址（约 0x08~0x77），调试用。
    返回 数组，可能为空表。业务请用 write/read 真实命令判断在线。
    例   local addrs = bus:scan()   -- {0x38, ...}

  ----------------------------------------------------------------------------
  bus:bus_recover() -> boolean
  ----------------------------------------------------------------------------
    总线卡死（SDA 被从机拉住）时发恢复时序。成功 true，未 init 或失败 false。
    例   bus:bus_recover()

  ----------------------------------------------------------------------------
  bus:id() -> integer
  ----------------------------------------------------------------------------
    返回这条对象对应的控制器编号（I2C0=0，I2C1=1）。

  ----------------------------------------------------------------------------
  bus:deinit() -> true
  ----------------------------------------------------------------------------
    释放该路控制器，之后才能再 i2c.new 同一路。始终返回 true。
    对象被回收时也会自动释放。

  ============================================================================
  AHT20 流程（本 demo 实际跑的）
  ============================================================================
  1) 上电后等几十毫秒
  2) write(0x38, BE 08 00)，再等 10ms
  3) 每次测量：write(0x38, AC 33 00) → 等 80ms → read(0x38, 7)
  4) 首字节 bit7=1 表示传感器还忙，丢掉这包
  5) 湿度、温度各 20bit，拼在第 2~6 字节里

  硬件 I2C0，地址 0x38。初始化成功后每 2 秒测一次。读失败会重新发初始化命令。

]=]
