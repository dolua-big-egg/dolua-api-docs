
--[=[
  rndis demo — USB 当 4G 网卡
  ============================================================================
  本 demo
  ============================================================================
    1) 读本次状态 get、开机策略 saved
    2) set(true) 仅本次打开，再 get
    3) set(false) 仅本次关闭，再 get
    4) 把本次开关还原成进入脚本前的值
    不调用 save，避免改 NVM 开机策略。

    注意流量消耗。
]=]

local rt = require("rt")
local log = require("log")
local rndis = require("rndis")

local function dump(tag)
    local enable, bound = rndis.get()
    log.info("%s enable=%s bound=%s saved=%s", tag, enable, bound, rndis.saved())
end

log.info("---- query ----")
local orig_enable, orig_bound = rndis.get()
log.info("get enable=%s bound=%s", orig_enable, orig_bound)
log.info("saved=%s", rndis.saved())

log.info("---- set on (this session) ----")
local ok, err = rndis.set(true)
log.info("set on ok=%s err=%s", ok, tostring(err))
dump("after on")

log.info("---- set off (this session) ----")
ok, err = rndis.set(false)
log.info("set off ok=%s err=%s", ok, tostring(err))
dump("after off")

log.info("---- restore ----")
ok, err = rndis.set(orig_enable ~= 0)
log.info("restore enable=%s ok=%s err=%s", orig_enable, ok, tostring(err))
dump("final")

while true do
    rt.delay(10000)
end

--[=[
  rndis demo — USB 当 4G 网卡

  require("rndis")。USB 接到电脑后，打开即可当 4G 网卡。
  参数可用 boolean 或 0/1。set/save 失败返回 false, "fail"。

  ----------------------------------------------------------------------------
  rndis.get() -> enable, bound
  ----------------------------------------------------------------------------
    enable  1=本次已请求打开；0=未打开
    bound   1=已绑定成功（电脑侧网卡可用）；0=尚未绑上

  ----------------------------------------------------------------------------
  rndis.saved() -> saved
  ----------------------------------------------------------------------------
    1=开机自动打开（NVM）；0=开机不自动

  ----------------------------------------------------------------------------
  rndis.set(enable) -> true | false, "fail"
  ----------------------------------------------------------------------------
    仅本次，不改开机策略。重启后仍看 saved。

    例  rndis.set(true)   rndis.set(1)
        rndis.set(false)  rndis.set(0)

  ----------------------------------------------------------------------------
  rndis.save(enable) -> true | false, "fail"
  ----------------------------------------------------------------------------
    本次立刻生效，并写入 NVM：1=开机自动开，0=开机不再自动。
    本 demo 不调用，避免改设备开机配置。

  bound 为 1 时电脑才能上网。没插 SIM / 没驻网时 enable 可能已是 1，bound 仍为 0。

  ============================================================================
  本 demo
  ============================================================================
    先查询，再本次开/关各一次，最后还原进入脚本前的 enable。不写 NVM。

]=]
