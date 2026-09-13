--[=[
  rt mq demo — 显式队列 FIFO
  ============================================================================
  本 demo
  ============================================================================
    1) create 深度 4
    2) 先 send 3 条，再 count，再 recv 取完
    3) 塞满后第 5 条失败
    4) reset 清空
    5) 协程里 recv 等待时 delete，等待方收到 "deleted"

]=]

local rt = require("rt")
local log = require("log")

local TOPIC = "demo_mq"

local function dump_count(tag)
    local count, depth, err = rt.mq_count(TOPIC)
    log.info("%s count=%s depth=%s err=%s", tag, count, depth, tostring(err))
end

log.info("---- create ----")
local ok, err = rt.mq_create(TOPIC, 4)
log.info("create ok=%s err=%s", ok, tostring(err))
ok, err = rt.mq_create(TOPIC, 4)
log.info("create again ok=%s err=%s", ok, tostring(err))

log.info("---- send 3 then recv ----")
for i = 1, 3 do
    ok, err = rt.mq_send(TOPIC, { n = i, msg = "hi" })
    log.info("send n=%d ok=%s err=%s", i, ok, tostring(err))
end
dump_count("after send3")

for i = 1, 3 do
    local rok, data, rerr = rt.mq_recv(TOPIC, 100)
    if rok then
        log.info("recv n=%s msg=%s", data.n, data.msg)
    else
        log.warn("recv fail err=%s", tostring(rerr))
    end
end
dump_count("after recv3")

log.info("---- fill until full ----")
for i = 1, 5 do
    ok, err = rt.mq_send(TOPIC, i)
    log.info("fill %d ok=%s err=%s", i, ok, tostring(err))
end
dump_count("full")

log.info("---- reset ----")
ok, err = rt.mq_reset(TOPIC)
log.info("reset ok=%s err=%s", ok, tostring(err))
dump_count("after reset")

log.info("---- waiter + delete ----")
rt.task_start(function()
    local rok, data, rerr = rt.mq_recv(TOPIC, 5000)
    log.info("waiter ok=%s data=%s err=%s", rok, tostring(data), tostring(rerr))
end)
rt.delay(200)
ok, err = rt.mq_delete(TOPIC)
log.info("delete ok=%s err=%s", ok, tostring(err))
dump_count("after delete")

while true do
    rt.delay(10000)
end

--[=[
  rt mq demo — 显式队列 FIFO

  和 mbox 不同：必须先 mq_create；消息进队列直到 recv / reset / delete。
  一条消息只唤醒一个等待者。深度 1~128。

  ----------------------------------------------------------------------------
  rt.mq_create(topic, depth) -> ok[, err]
  rt.mq_send(topic[, value]) -> ok[, err]
  rt.mq_recv(topic[, timeout_ms]) -> ok, data, err
  rt.mq_count(topic) -> count, depth, err     不存在：-1, 0, "not found"
  rt.mq_reset(topic) -> ok[, err]             清空缓存，容器还在
  rt.mq_delete(topic) -> ok[, err]            正在 recv 的协程得到 false, nil, "deleted"

  send/recv 的 value 与 mbox 相同：nil / boolean / number / string / table。
  recv 必须在任务协程里。队列满 send 返回 false, "full"。

  ============================================================================
  本 demo
  ============================================================================
    create → 积压再取完 → 塞满失败 → reset → 等待中 delete。

]=]
