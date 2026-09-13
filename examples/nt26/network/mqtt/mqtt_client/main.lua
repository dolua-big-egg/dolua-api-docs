--[=[
  mqtt demo — 等待网络后启动长链接
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 mqtt」后空转
    2) 读 IMEI，拼出 /device/<IMEI>、/server/<IMEI>
    3) create：带回调和重连相关参数
    4) auto_sub 订 /server/<IMEI>，这样每次上线（含重连）都会自动订
    5) open 指定 mqtt.doiot.cn:1883，client_id=IMEI
    6) wait_connect
    7) pub 一条文本到 /device/<IMEI>
    8) update 拉长低频重连间隔（已连接时只进缓存，断线重连才用上）
    9) 循环打 status；收到 /server/<IMEI> 的报文在回调里打印

    对端关掉连接后，日志会看到 disconnected，然后内部自己再连，
    脚本不用再 open；auto_sub 会在再次 connected 后自动订回。

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local mqtt = require("mqtt")
local info = require("info")

-- 这是我们的测试服务器，http://mqtts.doiot.cn/ 打开链接可以看到网页端的服务器，可以辅助测试。
-- 也可以改成你自己的服务器，注意目前clientid是在下面使用设备IMEI生成的，需要修改clientid请在下面修改。
local HOST = "mqtts.doiot.cn"
local PORT = 1883
local USERNAME = "doiot"
local PASSWORD = "web" -- 这个测试服务器的密码是固定的web

local LINK_WAIT_MS = 60 * 1000
local c -- 长期持有。长期连接必须放在不会被回收的位置，否则可能被 GC 掉。

local TOPIC_PUB
local TOPIC_SUB
local CLIENT_ID

local function on_mqtt(ev)
    if not ev then
        return
    end
    if ev.event == "pre_connect" then
      -- 这个"预连接"回调的 log 暂时屏蔽了，如果你的服务器连不上，这儿就会一直回调，因为他是每次尝试重连前都会回调一次
      -- 这个回调设计的意思是提供一个可以动态修改server和订阅的能力，比如有的服务器，他的server参数是
      -- 动态生成的，你可以在这个回调中计算并更新server参数，然后立刻更新，而且是立刻生效。
      --log.info("event pre_connect")
      --
      -- 演示：在即将 CONNECT 前改三元组。auth(client_id, username, password)
      --   nil 的项不改；传字符串（含 ""）就写入。这次建连会用上新值。
      --   不要在这里 rt.delay / wait_connect / 同步 pub。
      -- if c then
      --     c:auth(CLIENT_ID, USERNAME, PASSWORD)
      --     -- 只换密码：c:auth(nil, nil, "newpass")
      -- end

    elseif ev.event == "connected" then
        log.info("event connected")
    elseif ev.event == "disconnected" then
        log.info("event disconnected")
    elseif ev.event == "error" then
        log.warn("event error code=%s", ev.code)
    elseif ev.event == "message" then
        log.info("event message topic=%s n=%d data=%s",
                 ev.mqtt_topic, ev.data and #ev.data or 0, ev.data)
        -- 收到下行后回一条到发布主题。回调里只能 pub_async，不要 pub / wait_connect / rt.delay。
        if c and TOPIC_PUB then
            c:pub_async(TOPIC_PUB, "ack " .. tostring(ev.data), 0, 0)
        end
    end
end

-- 本 DEMO 是演示等驻网后再建 mqtt。也可以不管驻网，直接 create 和 open，内部会自动等网重连。
log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 mqtt")
    while true do
        rt.delay(10000)
    end
end
log.info("network ok, start mqtt")

CLIENT_ID = info.imei()
if not CLIENT_ID or CLIENT_ID == "" then
    log.error("imei empty, cannot build mqtt topics")
    while true do
        rt.delay(10000)
    end
end
TOPIC_PUB = "/device/" .. CLIENT_ID
TOPIC_SUB = "/server/" .. CLIENT_ID
log.info("imei=%s pub=%s sub=%s", CLIENT_ID, TOPIC_PUB, TOPIC_SUB)

log.info("---- create ----")
local err
c, err = mqtt.create(on_mqtt, {
    -- 低频重连间隔（毫秒）。open 后前 5 秒连不上会改低频，之后按这个间隔再试。
    -- 默认 5000，范围 1000~60000。已连接时 update 只进缓存，断线重连才用上。
    reconnect_interval_ms = 5000,
    -- 高频重连 / 线程空转间隔（毫秒）。刚 open 的前 5 秒按这个间隔猛试。
    -- 默认 30，范围 20~10000。改了马上用上。对端没配好时也按这个空转等配置。
    poll_interval_ms = 30,
    -- 单次建连超时（毫秒）。每次尝试连 broker 最多等这么久。
    -- 默认 5000，范围 1000~5000。下次建连前生效。
    connect_timeout_ms = 5000,
    -- MQTT 协议心跳（秒）。连上后按这个间隔发 PING。默认 60，范围 10~65535。
    -- 用来发现死连接，发现后仍走自动重连，不改重连间隔。
    keepalive_interval = 60,
    -- Clean Session。默认 true。下次 CONNECT 时带上。
    clean_session = true,
    -- 发送 / 接收缓冲（字节）。下次重连时重新分配。
    -- 默认 4096，范围 2048~16384。
    send_buffer_size = 4096,
    recv_buffer_size = 4096,
})
if not c then
    log.error("create fail err=%s", err)
    while true do
        rt.delay(10000)
    end
end
log.info("create ok")

log.info("---- auto_sub ----")
-- 必须在第一次 open 之前设好。connected 之后内部才会按列表订阅。
-- 只调 sub 不会写入这份列表，断线重连后不会自动再订。
local ok, oerr = c:auto_sub({
    { topic = TOPIC_SUB, qos = 0 },
})
log.info("auto_sub %s qos=0 ok=%s err=%s", TOPIC_SUB, ok, oerr)

log.info("---- open ----")
-- create 和 open 不是一回事。
--   create  建实例 + 拉起托管线程（线程先挂起，这时还不连网）
--   open    只把目标设成「要连上」，叫醒线程去连。成功返回只表示交给内部了，不等于已经连上。
--
-- create 的 config 里也可以写 host/port/client_id，之后 c:open() 无参就能连。
-- 本 demo 是 create 时不写对端，open(HOST, PORT, CLIENT_ID, USERNAME, PASSWORD) 时再带上。
--
-- 已经 open 过，再调会怎样（不会再占一路、不会再拉线程、不会把现有连接拆掉重建）：
--   已连接 + open()                         空操作，当前连接不动
--   已连接 + open(新host, 新port, ...)      新对端只进缓存；当前这条还是旧 broker
--                                           要等断线内部重连，或先 close 再 open，新地址才用上
--   正在连 / 正在重连 + open                再确认一次「继续连」，不会叠两路
--   close 之后再 open                      这才是第二次连接：线程从挂起醒来，重新开始托管
--
-- disconnected 回调里不要再 open，内部已经在重连。
-- 只有自己 close 过才需要再 open。想立刻换服务器：先 close，再 open(新 host, 新 port, ...)。
--
-- 重要的事说两边：这个 mqtt 库是纯托管的，只要目标是 open，就会全自动重连，不需要重复 open。
ok, oerr = c:open(HOST, PORT, CLIENT_ID, USERNAME, PASSWORD)
log.info("open %s:%d id=%s ok=%s err=%s", HOST, PORT, CLIENT_ID, ok, oerr)
if not ok then
    while true do
        rt.delay(10000)
    end
end

-- 这只是一个阻塞的演示。正常业务几乎不用 wait_connect，关注回调事件即可。
log.info("---- wait_connect ----")
local ready = c:wait_connect(20000)
log.info("wait_connect ready=%s status=%s", ready, c:status())

log.info("---- pub ----")
if c:status() then
    ok, oerr = c:pub(TOPIC_PUB, "hello mqtt", 0, 0)
    log.info("pub %s ok=%s err=%s", TOPIC_PUB, ok, oerr)
else
    log.warn("skip pub, not connected")
end

log.info("---- update reconnect ----")
-- 已连接：只写入待生效缓存。当前连接不变；对端断开后的低频重连才用 10 秒。
ok, oerr = c:update({ reconnect_interval_ms = 10000 })
log.info("update reconnect_interval_ms=10000 ok=%s err=%s", ok, oerr)

log.info("---- status loop ----")
while true do
    -- 循环打印连接状态，仅展示获取状态的 api，正常使用可以只关注回调事件。
    log.info("status connected=%s", c:status())
    rt.delay(600000)
end

--[=[
  mqtt demo — 先等网络，再托管连接（自带自动重连）

  mqtt 是独立模块：require("mqtt")。全系统最多 2 路。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停。

  本 demo 连 mqtt.doiot.cn:1883，无用户名/密码。
  client_id 用设备 IMEI。
  发布主题：/device/<IMEI>
  订阅主题：/server/<IMEI>
  上线后向 /device/<IMEI> 发一条文本；收到 /server/<IMEI> 的报文会打日志。
  可用 mqtt.doiot.cn 网页或其它客户端往 /server/<IMEI> 发，模组就能收到。

  ============================================================================
  托管 / 自动重连（不用自己在 disconnected 里再 open）
  ============================================================================
  create 会立刻拉起一条工作线程并挂起，还不连网。
  open 把目标设成「要连上」，线程醒来后自己去连 broker。
  只要不 close / delete，断线、连不上、掉网都会由内部继续连，脚本不用管。

  close 把目标设成「挂起」：主动断开 MQTT，停掉重连，线程再挂起。
  之后要再连，必须再 open。
  delete 销毁实例（含线程），对象作废。

  ----------------------------------------------------------------------------
  重连策略（open 之后、close 之前一直有效）
  ----------------------------------------------------------------------------
  1) 还没驻网
     先等驻网，最长约 60 秒；等到或超时后回到主循环再判断，不会自己停掉托管。
     没驻网时托管线程会阻塞等待，直到驻网成功才会继续连。

  2) 对端还没配好（host 空或端口 0）
     只按 poll_interval_ms 空转，等你 update / open(host, port, ...) 配上。

  3) 正在连、连失败（从 close 后的第一次 open 算起）
     前 5 秒：高频，每隔 poll_interval_ms 再试一次
               （默认 30，范围 20~10000）
     满 5 秒还没连上：改低频，每隔 reconnect_interval_ms 再试
               （默认 5000，范围 1000~60000）
     这 5 秒是固定的，改不了。
     连上后两档都清掉；你 close 再 open，会重新从高频开始。

  4) 已经连上又断了（broker 关、收发出错、心跳失败、驻网丢失）
     上报 disconnected 或 error，状态回到「连接中」，目标仍是「要连」。
     内部立刻再试；再失败则走上面的间隔。
     不要在回调里自己 open。

  影响重连的参数
    poll_interval_ms         高频间隔；也是线程空转间隔（改了马上用上）
    reconnect_interval_ms    低频间隔（下次重连前合并）
    connect_timeout_ms       单次建连超时（默认 5000，范围 1000~5000）
    host / port / client_id / username / password
                             下次建连的对端和鉴权
    close / open             close 停止托管；open 才开始

  keepalive_interval 是 MQTT 协议心跳（秒），用来发现死连接。
  断了之后仍走上面的自动重连，不改变重连间隔。

  ----------------------------------------------------------------------------
  动态改参：update / create 的 config
  ----------------------------------------------------------------------------
  填了的 key 覆盖，没填的保持原值。
  update 和 create 里的项，多数是先写进「待生效缓存」。

  真正合并进运行配置的时机：
    当前不是已连接，并且马上要去等驻网 / 建 TCP / 发 MQTT CONNECT 之前。
    也就是：第一次 open 前、close 后再 open 前、断线后下一次重连前。

  例外：poll_interval_ms 改了马上用上，不用等重连。

  已连接时 update：
    当前这条连接完全不改（对端、鉴权、心跳、缓冲都不热改）。
    等这条断了、内部重连时才用上新值。
    想立刻换 broker：先 close，再 update 或 open(新 host, 新 port, ...)。

  各参数何时用上

    host / server_host / ip
    port / server_port
                         下次建连前合并
                         open(host, port, client_id[, username[, password]])
                         等价于先写入这几项再 open
                         open() 无参：不改对端，用当前已配置的

    client_id / username / password
                         下次 CONNECT 前合并。本 demo 无账密，传空字符串即可

    reconnect_interval_ms / connect_timeout_ms / command_timeout_ms
                         下次进入「未连接、准备建连」时合并

    poll_interval_ms     立刻生效；也是高频重连间隔

    keepalive_interval   下次 CONNECT 时带上（秒；默认 60，范围 10~65535）
    clean_session        下次 CONNECT 时带上（默认 true）

    send_buffer_size / recv_buffer_size
                         下次重连时重新分配（默认 4096，范围 2048~16384）

    will_enable / will_topic / will_message / will_qos / will_retain
                         下次 CONNECT 时带上遗嘱。本 demo 不用

  ----------------------------------------------------------------------------
  mqtt.create(cb[, cfg]) -> client | nil, err
  ----------------------------------------------------------------------------
    cb   必填。事件回调，跑在 Lua 调度循环里，不是 MQTT 工作线程。
         必须马上返回。不要 rt.delay / wait_connect / 同步 pub。
         回数据用 pub_async。
    cfg  可选表，见上面各 key。未出现的项用默认。
    失败  nil, 错误字符串（没回调、超过 2 路等）

  回调参数 ev
    event        "pre_connect" / "connected" / "disconnected" / "message" / "error"
    mqtt_topic   仅 message：收到的主题
    data         仅 message：收到的 payload（二进制字符串）
    code         整数；error 时有意义。同一次断线里相同 code 只报一次，
                 直到再次 connected 才清掉
    client       这个客户端对象

    pre_connect  即将建 TCP/MQTT 连接前会来一次。不要在这里阻塞。
    connected    MQTT CONNACK 成功。auto_sub 列表会在这次之后由内部自动订阅。
    disconnected 连接断开。不要在这里再 open。
    message      订阅到的报文。
    error        建连失败、心跳失败等。内部仍会重连。

  ----------------------------------------------------------------------------
  client:open([host, port, client_id[, username[, password]]]) -> true, "ok" | nil, err
  ----------------------------------------------------------------------------
    有参：写入对端和鉴权再开始托管。port 必须在 1~65535。
         username / password 可省略，默认空字符串。
    无参：用已配置的对端开始托管。create/update 里已经写了 host/port 时用这个。
    成功只表示「已交给内部去连」，不等于已经连上。连上靠回调或 wait_connect。

  client:wait_connect([timeout_ms]) -> boolean
    等到 connected。会让出当前协程。省略或 -1 = 一直等。已连接则立刻 true。

  client:status() -> boolean     true=MQTT 已连接

  client:auto_sub({ { topic=..., qos=0~2 }, ... }) -> true | false[, err]
    全量覆盖自动订阅列表，最多 20 条。
    每次 connected（含掉线重连）后内部会按这份列表再订一遍。
    只改列表、不立刻对当前会话发 SUBSCRIBE；要当前立刻订，再调 sub。
    建议在第一次 open 之前就设好，这样首次上线就能订上。

  client:sub(topic, qos) -> true | false[, err]
    对当前已连接会话立刻订阅。未连接会失败。
    不会写入 auto_sub 列表，断线重连后不会自动再订。
    长期主题请用 auto_sub。

  client:unsub(topic) -> true | false[, err]
    对当前会话取消订阅。不改 auto_sub 列表。

  client:unsub_auto() -> true | false[, err]
    清空自动订阅列表。已经订上的当前会话不会自动退订，需要的话再 unsub。

  client:pub(topic, payload, qos, retain) -> true | false[, err]
    同步发布。已连接才能成功。不要在回调里用。
    qos 0/1/2；retain 用 0/1 或 false/true。

  client:pub_async(topic, payload, qos, retain) -> true | false[, err]
    只入队，回调里用这个。未连接或队列满会失败。

  client:update(cfg) -> true, "ok" | nil, err
    动态改参，生效时机见上。

  client:auth({ client_id=..., username=..., password=... }) -> true | false[, err]
    只改鉴权三项，下次 CONNECT 才用上。本 demo 不用。

  client:close() -> true | false[, err]
    停止托管并断开。线程随后挂起。

  client:delete() -> true
    销毁，且之后不能再用。正常业务完全没必要 delete：长期连接应一直持有对象。
    需要暂时断开用 close，托管线程休眠；再连时 open，比反复 create 快。

  需要网络。没 SIM / 没驻网会一直连不上，但 open 之后内部会一直等网重试。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 mqtt」后空转
    2) 读 IMEI，拼出 /device/<IMEI>、/server/<IMEI>
    3) create：带回调和重连相关参数
    4) auto_sub 订 /server/<IMEI>，这样每次上线（含重连）都会自动订
    5) open 指定 mqtt.doiot.cn:1883，client_id=IMEI
    6) wait_connect
    7) pub 一条文本到 /device/<IMEI>
    8) update 拉长低频重连间隔（已连接时只进缓存，断线重连才用上）
    9) 循环打 status；收到 /server/<IMEI> 的报文在回调里打印

    对端关掉连接后，日志会看到 disconnected，然后内部自己再连，
    脚本不用再 open；auto_sub 会在再次 connected 后自动订回。

]=]
