--[=[
  lbs demo — 先等网络，再测内置基站定位
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 lbs」后空转
    2) 测内置：读缓存 → 单基站 → 多基站 → 带地址

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local lbs = require("lbs")

local LINK_WAIT_MS = 60 * 1000

local function dump_loc(tag, resp, err_code, err_msg)
    if resp then
        log.info("%s lon=%s lat=%s addr=%s prec=%s",
                 tag, resp.longitude, resp.latitude, resp.address, resp.precision)
        return true
    end
    log.warn("%s fail code=%s msg=%s", tag, err_code, err_msg)
    return false
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 lbs")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start lbs")

-- 内置的度云LBS服务器，能同时提供地理反编码
log.info("---- builtin cache ----")
local cache, c_err, c_msg = lbs.cache()
if cache then
    log.info("cache lon=%s lat=%s", cache.longitude, cache.latitude)
else
    log.info("cache empty code=%s msg=%s", c_err, c_msg)
end

log.info("---- builtin server ----")
dump_loc("single", lbs.sync({ lbs_mode = lbs.MODE_SINGLE_CELL }))
dump_loc("multi", lbs.sync({ lbs_mode = lbs.MODE_MULTI_CELL }))
dump_loc("geocode", lbs.sync({ lbs_mode = lbs.MODE_GEOCODE }))

while true do
    rt.delay(10000)
end

--[=[
  lbs demo — 先等网络，再测内置基站定位

  require("lbs") 内置定位服务，不需要 pid。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停，不测定位。

  ----------------------------------------------------------------------------
  lp.wait_link([timeout_ms]) -> boolean     别名 wait_attach
  ----------------------------------------------------------------------------
    timeout_ms  可选，毫秒；省略或 -1 表示一直等
    返回        true 已驻网/PDP 激活；false 超时仍没网
    会让出当前协程。已驻网则立刻 true。

  ----------------------------------------------------------------------------
  lbs.sync([cfg]) -> resp | nil, err_code, err_msg
  ----------------------------------------------------------------------------
    同步向模组内置定位服务要一次位置。调用返回前当前协程被占住
    （不是 uart.block 那种让出，timeout 别开得过大）。

    cfg  可选表，省略则用模块当前配置。关心的字段：

      lbs_mode     lbs.MODE_SINGLE_CELL  单基站
                   lbs.MODE_MULTI_CELL   多基站（只要经纬度）
                   lbs.MODE_GEOCODE      多基站且尽量带地址
      timeout_s    发送超时，秒；省略/0 = 模块默认
      timeout_r    接收超时，秒；省略/0 = 模块默认
      retry_count  HTTP 重试次数；省略/0 = 模块默认

    成功  resp 表：
      longitude / latitude / address   字符串（GEOCODE 才常有地址）
      precision                        小数位数
      server_err_code / server_err_msg 平台侧错误，0 表示成功

    失败  nil, err_code, err_msg
      没网、超时、忙、拿不到小区信息等。常用常量：
      lbs.ERR_OK / ERR_BUSY / ERR_TIMEOUT

    例
      lbs.sync()
      lbs.sync({ lbs_mode = lbs.MODE_SINGLE_CELL })
      lbs.sync({ lbs_mode = lbs.MODE_GEOCODE, timeout_s = 5, timeout_r = 8 })

  ----------------------------------------------------------------------------
  lbs.cache() -> { longitude, latitude } | nil, err_code, err_msg
  ----------------------------------------------------------------------------
    立刻返回最近一次内置定位的缓存，不再上网。
    从没成功定位过则为 nil。设备长期不动时可以只读缓存。

  需要网络。没 SIM / 没驻网会失败。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 lbs」后空转
    2) 测内置：读缓存 → 单基站 → 多基站 → 带地址

]=]
