--[=[
  rtu demo — 透传通道查询 / 运行时开关 / 等连接 / 通道回调
  ============================================================================
  本 demo
  ============================================================================
    1) 读全部 option（含 *_cfg，只读不写 NVM）
    2) 本次改 pass_up / pass_down，再还原（不写 pass_*_cfg / uart*_en_cfg）
    3) is_connect / state 扫通道 1..4
    4) wait_connect(1, 3000)：已连立刻 true，否则最多等 3 秒
    5) reg_chcb(1..4)，事件只打日志，不回包、不在回调里 send
    通道要在模组 RTU 配置里先配好（TCP/UDP/MQTT）。本 demo 不自动发数。

]=]

local rt = require("rt")
local log = require("log")
local rtu = require("rtu")

local KEYS = {
    "pass_up", "pass_down",
    "pass_up_cfg", "pass_down_cfg",
    "uart2_en_cfg", "uart3_en_cfg",
}

log.info("---- option read ----")
for i = 1, #KEYS do
    local v, e = rtu.option(KEYS[i])
    log.info("%s=%s err=%s", KEYS[i], tostring(v), tostring(e))
end

local orig_up = rtu.option("pass_up")
local orig_down = rtu.option("pass_down")
log.info("---- option runtime flip (restore later) ----")
log.info("pass_up write false rc=%s", tostring(rtu.option("pass_up", false)))
log.info("pass_down write false rc=%s", tostring(rtu.option("pass_down", false)))
log.info("now pass_up=%s pass_down=%s", tostring(rtu.option("pass_up")), tostring(rtu.option("pass_down")))
if orig_up == true or orig_up == false then
    log.info("pass_up restore rc=%s", tostring(rtu.option("pass_up", orig_up)))
end
if orig_down == true or orig_down == false then
    log.info("pass_down restore rc=%s", tostring(rtu.option("pass_down", orig_down)))
end
log.info("restored pass_up=%s pass_down=%s", tostring(rtu.option("pass_up")), tostring(rtu.option("pass_down")))

log.info("---- is_connect / state ----")
for id = 1, 4 do
    log.info("ch%d is_connect=%s state=%s", id, tostring(rtu.is_connect(id)), tostring(rtu.state(id)))
end

log.info("---- wait_connect ch1 3000ms ----")
log.info("wait_connect(1,3000)=%s", tostring(rtu.wait_connect(1, 3000)))

log.info("---- reg_chcb 1..4 ----")
local function on_ch(id, data, meta)
    meta = meta or {}
    log.info("chcb id=%s event=%s type=%s topic=%s host=%s port=%s n=%s data=%s",
             tostring(id), tostring(meta.event), tostring(meta.type),
             tostring(meta.topic), tostring(meta.host), tostring(meta.port),
             type(data) == "string" and #data or 0, tostring(data))
end

for id = 1, 4 do
    log.info("reg_chcb %d ok=%s", id, tostring(rtu.reg_chcb(id, on_ch)))
end

log.info("rtu demo idle; channel events will log here")
while true do
    rt.delay(10000)
end

--[=[
  rtu demo — 透传通道（查询 / 运行时开关 / 等待 / 回调）

  require("rtu")。通道 1..4 对应模组里配好的 TCP/UDP/MQTT 任务，不是 lua tcp.create
  自己拉起来的连接。没配通道时 is_connect=false，send 会失败，属正常。

  ----------------------------------------------------------------------------
  rtu.option(key) -> bool | nil, err
  rtu.option(key, bool) -> int
  ----------------------------------------------------------------------------
    读：成功 bool；失败 nil, 底层错误码。
    写：返回 RTU_TASK 状态码，0=OK。

    pass_up / pass_down
        运行时串口上报 / 通道下发透传开关，不落盘。重启后回到配置值。
        其它 UART demo 常把这两项设 false，避免透传抢走 Lua 串口数据。

    pass_up_cfg / pass_down_cfg
        本地 RTU 配置，落盘。写了不立刻改运行时，下次按配置生效。
        本 demo 只读不写。

    uart2_en_cfg / uart3_en_cfg
        UART2/3 使能，KV 落盘，重启后生效。本 demo 只读不写。

    不支持的 key 会抛错。

  ----------------------------------------------------------------------------
  rtu.is_connect(id) / rtu.state(id) -> bool
  ----------------------------------------------------------------------------
    id 为 1..4。state 是 is_connect 别名。
    只问「现在连上没有」，不管通道有没有启用。

  ----------------------------------------------------------------------------
  rtu.wait_connect(id [, timeout_ms]) -> bool
  ----------------------------------------------------------------------------
    已连接立刻 true。否则当前协程挂起，通道 ONLINE 时被内部 topic 唤醒。
    timeout_ms 缺省 -1=一直等；超时 false。
    必须在协程里调，禁止在 uart / chcb 回调里调。
    本 demo 用 3000ms，避免没配通道时卡死。

  ----------------------------------------------------------------------------
  rtu.reg_chcb(id, cb) -> true
  rtu.unreg_chcb(id) -> bool
  ----------------------------------------------------------------------------
    cb(channel_id, data, meta)
      meta.event  "online" / "offline" / "data"
      meta.type   "tcp" / "udp" / "mqtt"
      meta.topic  MQTT 下行主题
      meta.host / meta.port  上下线时的对端
      data        下行数据；online/offline 为 nil
    注册时若已连接，会立刻补一次 online。
    回调必须马上返回：不要 wait_connect、不要 socket_sync / mqtt_sync、不要 delay。
    要回包请 mbox 到协程，或用 socket_async / mqtt_async。
    最多 16 个注册槽。

  ----------------------------------------------------------------------------
  本 demo 不调用（请用同目录 rtu_cmd）
  ----------------------------------------------------------------------------
    write / update_write / down_write
    socket_sync / socket_async
    mqtt_sync / mqtt_async / mqtt_sub / mqtt_unsub
    control（挂起/恢复通道）
    option 写入 *_cfg（会改 NVM）

    rtu.write(route, data)  route 如 "1" "1|2" "6[1]"（1-4 通道，6=UART，5=HTTP，7=短信）
    非法 route 会抛错。

  ============================================================================
  本 demo
  ============================================================================
    读 option；本次翻转 pass_up/down 再还原；扫 4 路连接；等 ch1 最多 3 秒；
    注册 4 路回调后空转打事件。不改 NVM，不自动向通道发数。

]=]
