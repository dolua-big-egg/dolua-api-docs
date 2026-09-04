--[=[
  tcp demo — 先等网络，再托管连接（自带自动重连）
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 tcp」后空转
    2) create：带回调和重连相关参数
    3) open 指定服务器，wait_connect
    4) send 一串文本
    5) update 拉长低频重连间隔（已连接时只进缓存，断线重连才用上）
    6) 循环打 status；收到数据在回调里 send_async 原样写回

    把 HOST / PORT 改成你的服务器。对端关掉连接后，日志会看到 disconnected，
    然后内部自己再连，脚本不用再 open。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local tcp = require("tcp")

-- 改成你的 TCP 服务器，或者去访问我们的测试服务器 
-- http://tcp.doiot.cn/ 可以访问我们的测试服务器，他是一个网页端的测试服务器。
local HOST = "tcp.doiot.cn"
-- 如果使用我们的测试服务器，记得把网页端的端口填写到这里，还有就是网页刷新时端口会边，这边
-- 记得同步改一下。
local PORT = 26429 

local LINK_WAIT_MS = 60 * 1000
local c -- 长期持有的客户端对象，我要提一嘴的是，如果你是长期链接，一定要有全局位置，就是让他保持被引用
-- 否则他可能在某个时刻被自动gc掉。

local function on_tcp(ev)
    if ev.event == "connected" then
        log.info("event connected ip=%s port=%s", ev.ip, ev.port)
    elseif ev.event == "disconnected" then
        log.info("event disconnected")
    elseif ev.event == "error" then
        log.warn("event error code=%s", ev.code)
    elseif ev.event == "data" then
        log.info("event data recv n=%d data=%s", ev.data and #ev.data or 0, ev.data)
        if ev.data and c then
            c:send_async(ev.data)
        end
    end
end


-- 本DEMO是演示的等驻网后在建立tcp，其实也可以完全不管驻网，直接创建和open，内部会自动重连。
log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 tcp")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start tcp")

log.info("---- create ----")
local err
c, err = tcp.create(on_tcp, {
    -- 低频重连间隔（毫秒）。open 后前 5 秒连不上会改低频，之后按这个间隔再试。
    -- 默认 5000，范围 1000~60000。已连接时 update 只进缓存，断线重连才用上。
    reconnect_interval_ms = 5000,
    -- 高频重连 / 线程空转间隔（毫秒）。刚 open 的前 5 秒按这个间隔猛试。
    -- 默认 30，范围 20~10000。对端没配好时也按这个空转等配置。
    poll_interval_ms = 30,
    -- 单次 TCP connect 超时（毫秒）。每次尝试连对端最多等这么久。
    -- 默认 5000，范围 1000~5000。下次建连前生效。
    connect_timeout_ms = 5000,
    -- 等驻网上限（毫秒）。还没 PDP 时内部先等网，等到或超时后再进重连循环。
    -- 默认 60000，范围 1000~600000。不会因为超时就停掉托管。
    link_wait_timeout_ms = 60000,
    -- 接收缓冲（字节）。只在 create 时分配，update 改不了。
    -- 默认 2048，范围 2048~16384。一包超过这个长度会分多次 data 回调。
    recv_buffer_size = 2048,
    -- 是否开 TCP keepalive。用来发现死连接，发现后仍走自动重连，不改重连间隔。
    -- 默认 true。套在下次创建 socket 时，当前已连接的那条不热改。
    keepalive_enable = true,
    -- keepalive 空闲时间（秒）：连上后多久没数据才开始探活。默认 60，范围 1~7200。
    keepalive_idle = 60,
    -- keepalive 探测间隔（秒）：两次探活之间隔多久。默认 10，范围 1~300。
    keepalive_interval = 10,
    -- keepalive 探测次数：连续几次没响应就当连接死了。默认 3，范围 1~10。
    keepalive_count = 3,
})
if not c then
    log.error("create fail err=%s", err)
    while true do
        rt.delay(10000)
    end
end
log.info("create ok")

log.info("---- open ----")
-- create 和 open 不是一回事。
--   create  建实例 + 拉起托管线程（线程先挂起，这时还不连网）
--   open    只把目标设成「要连上」，叫醒线程去连。成功返回只表示交给内部了，不等于已经连上。
--
-- create 的 config 里也可以写 host/port（或 ip/port），之后 c:open() 无参就能连。
-- 本 demo 是 create 时不写对端，open(HOST, PORT) 时再带上。
--
-- 已经 open 过，再调会怎样（不会再占一路、不会再拉线程、不会把现有 socket 拆掉重建）：
--   已连接 + open()           空操作，当前连接不动
--   已连接 + open(新ip, 新port)  新对端只进缓存；当前这条还是旧服务器
--                               要等断线内部重连，或先 close 再 open，新地址才用上
--   正在连 / 正在重连 + open    再确认一次「继续连」，不会叠两路
--   close 之后再 open          这才是第二次连接：线程从挂起醒来，重新开始托管
--
-- disconnected 回调里不要再 open，内部已经在重连。
-- 只有自己 close 过才需要再 open。想立刻换服务器：先 close，再 open(新ip, 新port)。
--
-- 重要的事说两边，注意这个tcp库是纯托管的，只要目标是open，就会全自动重连，不需要重复open。
local ok, oerr = c:open(HOST, PORT)
log.info("open %s:%d ok=%s err=%s", HOST, PORT, ok, oerr)
if not ok then
    while true do
        rt.delay(10000)
    end
end

-- 这只是一个阻塞的演示，比如你一定要写一个等连接的同步应用，则可以用wait_connect来阻塞等待连接成功。
-- 但是正常业务几乎不可能用这个，都是关注回调事件，用事件来推送业务。
log.info("---- wait_connect ----")
local ready = c:wait_connect(20000)
log.info("wait_connect ready=%s status=%s", ready, c:status())

log.info("---- send ----")
if c:status() then
    local n, serr = c:send("hello tcp\r\n")
    log.info("send n=%s err=%s", n, serr)
else
    log.warn("skip send, not connected")
end

log.info("---- update reconnect ----")
-- 已连接：只写入待生效缓存。当前连接不变；对端断开后的低频重连才用 10 秒。
ok, oerr = c:update({ reconnect_interval_ms = 10000 })
log.info("update reconnect_interval_ms=10000 ok=%s err=%s", ok, oerr)

log.info("---- status loop ----")
while true do
    -- 循环打印链接状态，仅展示获取状态的api，正常使用可以只关注回调事件。
    log.info("status connected=%s", c:status())
    rt.delay(10000)
end

--[=[
  tcp demo — 先等网络，再托管连接（自带自动重连）

  tcp 是独立模块：require("tcp")。全系统最多 tcp.MAX_CLIENTS 路（当前 4）。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停。

  ============================================================================
  托管 / 自动重连（不用自己在 disconnected 里再 open）
  ============================================================================
  create 会立刻拉起一条工作线程并挂起，还不连网。
  open 把目标设成「要连上」，线程醒来后自己去连。
  只要不 close / delete，断线、连不上、掉网都会由内部继续连，脚本不用管。

  close 把目标设成「挂起」：主动断开，停掉重连，线程再挂起。
  之后要再连，必须再 open。
  delete 销毁实例（含线程），对象作废。

  ----------------------------------------------------------------------------
  重连策略（open 之后、close 之前一直有效）
  ----------------------------------------------------------------------------
  1) 还没驻网
     先等驻网，最长 link_wait_timeout_ms（默认 60000，范围 1000~600000）。
     等到或超时后回到主循环再判断，不会自己停掉托管。
     就是没驻网时托管线程会阻塞等待事件，进入挂起状态，直到驻网成功才会激活。

  2) 对端还没配好（host/port 空或端口 0）
     只按 poll_interval_ms 空转，等你 update / open(ip, port) 配上。

  3) 正在连、连失败（从 close 后的第一次 open 算起）
     前 5 秒：高频，每隔 poll_interval_ms 再试一次
               （默认 30，范围 20~10000）
     满 5 秒还没连上：改低频，每隔 reconnect_interval_ms 再试
               （默认 5000，范围 1000~60000）
     这 5 秒是固定的，改不了。
     连上后两档都清掉；你 close 再 open，会重新从高频开始。

  4) 已经连上又断了（对端关、收发出错、驻网丢失）
     上报 disconnected 或 error，状态回到「连接中」，目标仍是「要连」。
     内部立刻再试；再失败则走上面的间隔。
     不要在回调里自己 open。

  5) 建 socket 失败
     固定等 1 秒再试，跟 reconnect_interval_ms 无关。

  影响重连的参数
    poll_interval_ms         高频间隔；也是线程空转间隔
    reconnect_interval_ms    低频间隔
    connect_timeout_ms       单次 TCP connect 超时（默认 5000，范围 1000~5000）
    link_wait_timeout_ms     等驻网上限
    host / port              下次建连的对端
    close / open             close 停止托管；open 才开始

  keepalive_* 用来发现死连接（断了之后仍走上面的自动重连），
  不改变重连间隔。

  ----------------------------------------------------------------------------
  动态改参：update / create 的 config
  ----------------------------------------------------------------------------
  填了的 key 覆盖，没填的保持原值。
  update 和 create 里除 recv_buffer_size 以外的项，都是先写进「待生效缓存」。

  真正合并进运行配置的时机：
    当前不是已连接，并且马上要去等驻网 / 建 socket / connect 之前。
    也就是：第一次 open 前、close 后再 open 前、断线后下一次重连前。

  已连接时 update：
    当前这条连接完全不改（对端、keepalive、超时、Nagle 都不热改）。
    等这条断了、内部重连时才用上新值。
    想立刻换服务器：先 close，再 update 或 open(新 ip, 新 port)。

  各参数何时用上

    recv_buffer_size     只在 create 时分配接收缓冲（默认 2048，范围 2048~16384）
                         update 传入会被忽略，改不了

    host / ip / port     下次建连前合并
                         open(ip, port) 等价于先写入这两项再 open
                         open() 无参：不改对端，用当前已配置的

    reconnect_interval_ms / poll_interval_ms / connect_timeout_ms
    link_wait_timeout_ms
                         下次进入「未连接、准备建连」时合并，随即用于重连节奏

    recv_timeout_ms      下次创建 socket 时作为接收超时
    send_buffer_size     下次创建 socket 时作为发送缓冲（0=不改系统默认）
    tcp_nodelay          下次创建 socket 时
    keepalive_enable / keepalive_idle / keepalive_interval / keepalive_count
                         下次创建 socket 时套上 keepalive
                         idle/interval 单位秒；默认开，60 / 10 / 3

  ----------------------------------------------------------------------------
  tcp.create(cb[, cfg]) -> client | nil, err
  ----------------------------------------------------------------------------
    cb   必填。事件回调，跑在 Lua 调度循环里，不是 TCP 工作线程。
         必须马上返回。不要 rt.delay / wait_connect / 同步 send。
         回数据用 send_async。
    cfg  可选表，见上面各 key。未出现的项用默认。
    失败  nil, 错误字符串（没回调、超过 tcp.MAX_CLIENTS 路等）

  回调参数 ev
    event   "connected" / "disconnected" / "data" / "error"
    data    仅 data 事件：收到的二进制字符串
    code    整数；error 时有意义
    ip/port 当前已生效对端（不含尚未合并的 update）
    client  这个客户端对象

  ----------------------------------------------------------------------------
  client:open([ip, port]) -> true, "ok" | nil, err
  ----------------------------------------------------------------------------
    有参：写入对端再开始托管连接。port 不能为 0。
    无参：用已配置的对端开始托管。create/update 里已经写了 host/port 时用这个。
    成功只表示「已交给内部去连」，不等于已经连上。连上靠回调或 wait_connect。

  client:wait_connect([timeout_ms]) -> boolean
    等到 connected。会让出当前协程。省略或 -1 = 一直等。已连接则立刻 true。

  client:status() -> boolean     true=已连接

  client:send(data) -> n | nil, err
    同步发送，已连接才能成功。不要在回调里用。

  client:send_async(data) -> true | false[, err]
    只入队，回调里用这个。未连接或队列满会失败。

  client:update(cfg) -> true, "ok" | nil, err
    动态改参，生效时机见上。

  client:close([timeout_ms]) -> true | false[, err]
    停止托管并断开。默认最多等 30 秒线程挂起；0 = 用内部默认约 15 秒。实际上要不了这么多时间，
    只是比如有回调被占用，被业务阻塞等问题，会导致这个时间延长。

  client:delete() -> true
    销毁，且之后不能再用，这个过程会把线程都清理掉，正常业务来说完全没必要用delete，因为如果业务正常，这个连接会一直存在，不需要销毁。
    如果你需要定时断开，则用close让链接断开，托管线程会自动休眠。需要链接时再open，速度最快也避免反复创建资源。

  需要网络。没 SIM / 没驻网会一直连不上，但 open 之后内部会一直等网重试。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 tcp」后空转
    2) create：带回调和重连相关参数
    3) open 指定服务器，wait_connect
    4) send 一串文本
    5) update 拉长低频重连间隔（已连接时只进缓存，断线重连才用上）
    6) 循环打 status；收到数据在回调里 send_async 原样写回

    把 HOST / PORT 改成你的服务器。对端关掉连接后，日志会看到 disconnected，
    然后内部自己再连，脚本不用再 open。

]=]
