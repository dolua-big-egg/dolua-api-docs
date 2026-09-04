--[=[
  soft_iic_aht20 demo — 软件 I2C 读 AHT20 温湿度
  ============================================================================
  本 demo
  ============================================================================
    1) soft_i2c.new GPIO8/9
    2) 初始化 AHT20（write BE 08 00）
    3) 每 2 秒测量并打印温湿度；失败则重新初始化

]=]

local rt = require("rt")
local log = require("log")
local soft_i2c = require("soft_i2c")

-- IO8=GPIO8 SDA；IO9=GPIO9 SCL。input=INPUT_GPIO 时前两个参数是 GPIO 编号
local SDA_GPIO = 8
local SCL_GPIO = 9
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

local bus = soft_i2c.new(SDA_GPIO, SCL_GPIO, {
    input = soft_i2c.INPUT_GPIO,
    clock_speed = 10000,
})

local sda, scl = bus:pins()
log.info("soft_i2c sda=%d scl=%d", sda, scl)

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
  soft_iic_aht20 demo — 软件 I2C 读 AHT20 温湿度

  soft_i2c 用两根普通 IO 模拟主机时序，不占用硬件 I2C 控制器。
  先 new 得到总线对象，再 write / read。可同时开多路（脚不要冲突）。

  前两个参数按 cfg.input 解释：
    省略 / INPUT_PINNO  模块引脚序号（默认，兼容旧用法）
    INPUT_GPIO          内部 GPIO 编号，和 gpio.open(gpio.INPUT_GPIO, n) 同一套

  本 demo 用 IO8 / IO9：SDA=GPIO8，SCL=GPIO9（对应 pin66 / pin67）。

  设备地址：写 7bit（AHT20=0x38）。写成 8bit 写地址 0x70 也能用，
  小于等于 0x7F 时底层会左移成写地址。

  命令/数据必须是字符串，不支持字节表：
      string.char(0xBE, 0x08, 0x00)
      "\xBE\x08\x00"            等价
      "0xBE 0x08"               错：这是 ASCII 文本
      {0xBE, 0x08, 0x00}        错：write 不收 table

  没有 mem_write / mem_read。AHT20 用 write + delay + read 即可。
  read 不是读本地缓存：每次都是现问从机。delay 是等 AHT20 转换完。

  ----------------------------------------------------------------------------
  常量（new 的 cfg 里用，一般不用改）
  ----------------------------------------------------------------------------
    soft_i2c.INPUT_PINNO           前两个参数是 pinno（默认）
    soft_i2c.INPUT_GPIO            前两个参数是 GPIO 编号
    soft_i2c.ADDRESSING_MODE_7BIT / ADDRESSING_MODE_10BIT
    soft_i2c.DUAL_ADDRESS_DISABLE / DUAL_ADDRESS_ENABLE
    soft_i2c.GENERAL_CALL_DISABLE / GENERAL_CALL_ENABLE
    soft_i2c.NO_STRETCH_DISABLE / NO_STRETCH_ENABLE

  ----------------------------------------------------------------------------
  soft_i2c.new(sda, scl [, cfg]) -> bus
  ----------------------------------------------------------------------------
    sda / scl  脚编号，含义由 cfg.input 决定
    cfg  可选表，省略则按 pinno、clock_speed=10000、7bit 寻址
         input               INPUT_PINNO（默认）/ INPUT_GPIO
         clock_speed         模拟时钟 Hz，默认 10000
         addressing_mode     默认 ADDRESSING_MODE_7BIT
         dual_address_mode   默认 DUAL_ADDRESS_DISABLE
         general_call_mode   默认 GENERAL_CALL_DISABLE
         no_stretch_mode     默认 NO_STRETCH_DISABLE
    返回 总线对象
    失败抛错：脚非法、input 非法、配置失败
    例   -- 按 GPIO：IO8 SDA / IO9 SCL
         local bus = soft_i2c.new(8, 9, { input = soft_i2c.INPUT_GPIO, clock_speed = 10000 })
         -- 按 pinno：同一对脚是 66 / 67
         local bus = soft_i2c.new(66, 67, { clock_speed = 10000 })

  ----------------------------------------------------------------------------
  bus:write(dev_addr, data [, timeout_ms]) -> boolean
  ----------------------------------------------------------------------------
    dev_addr    7bit 或 8bit 设备地址
    data        非空字符串（二进制）
    timeout_ms  可选，默认 100
    返回        true 成功，false 失败（未 init、NACK/超时）
    例          bus:write(0x38, string.char(0xAC, 0x33, 0x00))
                bus:write(0x38, "\xAC\x33\x00", 100)

  ----------------------------------------------------------------------------
  bus:read(dev_addr, len [, timeout_ms]) -> string|nil
  ----------------------------------------------------------------------------
    len         要读的字节数，必须 > 0
    timeout_ms  可选，默认 100
    返回        成功为长度为 len 的字符串，失败 nil
    例          local raw = bus:read(0x38, 7)

  ----------------------------------------------------------------------------
  bus:is_ready(dev_addr [, trials [, timeout_ms]]) -> boolean
  ----------------------------------------------------------------------------
    发地址看从机是否 ACK。trials 默认 1，timeout_ms 默认 100。
    例   if bus:is_ready(0x38) then ... end

  ----------------------------------------------------------------------------
  bus:scan() -> { addr, ... }
  ----------------------------------------------------------------------------
    扫描 0x08~0x77 有应答的 7bit 地址，调试用。可能为空表。
    例   local addrs = bus:scan()

  ----------------------------------------------------------------------------
  bus:test_hardware() -> boolean
  ----------------------------------------------------------------------------
    测 SCL 能否拉高/拉低。成功 true。脚对地短路或没上拉时会 false。

  ----------------------------------------------------------------------------
  bus:state() -> integer
  ----------------------------------------------------------------------------
    当前状态码（ready/busy/error 等），调试用。

  ----------------------------------------------------------------------------
  bus:error() -> integer
  ----------------------------------------------------------------------------
    最近一次错误码，0 表示无错误。

  ----------------------------------------------------------------------------
  bus:pins() -> sda_pinno, scl_pinno
  ----------------------------------------------------------------------------
    打开时用的两根脚。
    例   local sda, scl = bus:pins()

  ----------------------------------------------------------------------------
  bus:deinit() -> true
  ----------------------------------------------------------------------------
    释放这两根脚。始终返回 true。对象回收时也会自动释放。

  ============================================================================
  AHT20 流程（本 demo 实际跑的）
  ============================================================================
  1) 上电后等几十毫秒
  2) write(0x38, BE 08 00)，再等 10ms
  3) 每次测量：write(0x38, AC 33 00) → 等 80ms → read(0x38, 7)
  4) 首字节 bit7=1 表示传感器还忙，丢掉这包
  5) 湿度、温度各 20bit，拼在第 2~6 字节里

  SDA=GPIO8，SCL=GPIO9（pin66/67）。地址 0x38。初始化成功后每 2 秒测一次。读失败会重新发初始化命令。

]=]
