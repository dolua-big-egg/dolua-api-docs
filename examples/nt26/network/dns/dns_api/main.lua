--[=[
  dns demo - 先等网络，再读/改 DNS，再解析域名
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 dns」后空转
    2) 读 CID / 各 CID 状态
    3) 读运营商下发的 DNS，并用它解析
    4) 改成阿里 DNS，清缓存后再解析
    5) 循环：清缓存并再解析

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local dns = require("dns")

local LINK_WAIT_MS = 60 * 1000

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 dns")
    while true do rt.delay(10000) end
end
log.info("network ok, start dns")

log.info("---- cid ----")
local cid = dns.active_cid()
log.info("active_cid=%s", cid)
cid = cid or dns.DEFAULT_CID

local list = dns.cids()
if list then
    for i, item in ipairs(list) do
        log.info("cids[%d] cid=%s state=%s", i, item.cid, item.state)
    end
else
    log.warn("cids=nil")
end

log.info("---- get pco dns ----")
local servers, err = dns.get()
if not servers then
    log.error("get fail err=%s", err)
else
    log.info("DNS1=%s DNS2=%s", servers[1], servers[2])
end

log.info("---- resolve with pco dns ----")
local ip, rerr = dns.resolve("www.5giot.cn", cid)
log.info("www.5giot.cn ip=%s err=%s", ip, rerr)

log.info("---- set custom dns ----")
local ok, serr = dns.set("223.5.5.5", "223.6.6.6")
log.info("set 223.5.5.5/223.6.6.6 ok=%s err=%s", ok, serr)

log.info("---- get after set ----")
servers, err = dns.get()
if not servers then
    log.error("get fail err=%s", err)
else
    log.info("DNS1=%s DNS2=%s", servers[1], servers[2])
end

log.info("---- clear cache ----")
ok, err = dns.clear_cache(true)
log.info("clear_cache all ok=%s err=%s", ok, err)

log.info("---- resolve with custom dns ----")
ip, rerr = dns.resolve("www.baidu.com", cid)
log.info("www.baidu.com ip=%s err=%s", ip, rerr)

log.info("---- periodic resolve ----")
while true do
    dns.clear_cache(true)
    ip, rerr = dns.resolve("www.baidu.com", cid)
    log.info("www.baidu.com ip=%s err=%s", ip, rerr)
    rt.delay(10000)
end

--[=[
  dns demo — 先等网络，再读/改 DNS，再解析域名

  dns 是独立模块：require("dns")。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停，不测 DNS。

  开机默认用运营商下发的 DNS。dns.set 可临时覆盖，掉电不保存。
  CID 一般就是 1，下面接口都可以不传 cid。

  ----------------------------------------------------------------------------
  lp.wait_link([timeout_ms]) -> boolean     别名 wait_attach
  ----------------------------------------------------------------------------
    timeout_ms  可选，毫秒；省略或 -1 表示一直等
    返回        true 已驻网/PDP 激活；false 超时仍没网
    会让出当前协程。已驻网则立刻 true。

  ----------------------------------------------------------------------------
  常量
  ----------------------------------------------------------------------------
    dns.DEFAULT_CID    默认承载，通常是 1

  ----------------------------------------------------------------------------
  dns.active_cid() -> integer | nil
  ----------------------------------------------------------------------------
    当前应使用的 CID（优先 1）。未联网则为 nil。

  ----------------------------------------------------------------------------
  dns.cids() -> { {cid, state}, ... } | nil
  ----------------------------------------------------------------------------
    各 CID 激活状态。state=1 已激活，0 未激活。失败 nil。

    例  { { cid = 1, state = 1 }, { cid = 2, state = 0 } }

  ----------------------------------------------------------------------------
  dns.get([cid]) -> { "x.x.x.x", ... } | nil, err
  ----------------------------------------------------------------------------
    读当前生效的 DNS 列表（主 + 备，常见长度为 2）。
    cid 省略则用 DEFAULT_CID。
    失败：nil, 错误字符串。

    例  local servers, err = dns.get()
        local servers = dns.get(1)

  ----------------------------------------------------------------------------
  dns.set(primary[, secondary[, cid]]) -> boolean [, err]
  dns.set({ "x.x.x.x", ... }[, cid]) -> boolean [, err]
  ----------------------------------------------------------------------------
    临时覆盖当前生效的 DNS。掉电不保存；重拨后仍优先于运营商下发。
    至少要有一个服务器地址；最多 4 个。
    末尾整数当作 cid；省略则用 DEFAULT_CID。
    非法地址会抛错。失败：false, 错误字符串。

    例  dns.set("223.5.5.5", "223.6.6.6")
        dns.set({ "8.8.8.8", "8.8.4.4" })
        dns.set("223.5.5.5", "223.6.6.6", 1)

  ----------------------------------------------------------------------------
  dns.resolve(host[, cid]) -> string | nil, err
  ----------------------------------------------------------------------------
    同步解析域名，返回第一个 IPv4 字符串。
    调用返回前当前协程被占住（不是 uart.block 那种让出）。
    cid 省略则用 DEFAULT_CID。失败：nil, 错误字符串。

    例  local ip, err = dns.resolve("www.baidu.com")
        local ip = dns.resolve("www.5giot.cn", 1)

  ----------------------------------------------------------------------------
  dns.clear_cache([all[, host]]) -> boolean [, err]
  dns.clear_cache(host) -> boolean [, err]
  ----------------------------------------------------------------------------
    清 DNS 缓存。改完服务器后要清缓存，否则 resolve 可能仍用旧结果。

    省略 / true     清全部
    false, host     只清该域名
    只传 host 字符串  只清该域名

    例  dns.clear_cache()
        dns.clear_cache(true)
        dns.clear_cache("www.baidu.com")
        dns.clear_cache(false, "www.baidu.com")

  需要网络。没 SIM / 没驻网会失败。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 dns」后空转
    2) 读 CID / 各 CID 状态
    3) 读运营商下发的 DNS，并用它解析
    4) 改成阿里 DNS，清缓存后再解析
    5) 循环：清缓存并再解析

]=]
