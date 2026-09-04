--[=[
  http request demo — 先等网络，再用 http.request 发 GET / POST
  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 http」后空转
    2) http.request GET  https://httpbin.org/get，tls_mode=TLS_INSECURE
    3) http.request POST https://httpbin.org/post，body 为 "hello doiot "，同样不校验证书
    4) http.get / http.post 再各打一枪，opts 里同样带 TLS_INSECURE
    5) 打印 status 和 body；然后空转

]=]

local rt = require("rt")
local log = require("log")
local lp = require("lp")
local http = require("http")

local GET_URL = "https://httpbin.org/get" -- 这个网站响应比较慢，是正常的，桌面端可以用postman试试，先天就是慢。
local POST_URL = "https://httpbin.org/post" -- 这个网站响应比较慢，是正常的。
local POST_BODY = "hello doiot~"

local LINK_WAIT_MS = 60 * 1000

local function dump_resp(tag, resp)
    local body = resp.body or ""
    local preview = body
    if #preview > 256 then preview = string.sub(preview, 1, 256) .. "..." end
    log.info("%s protocol=%s status=%s %s", tag, resp.protocol_version,
             resp.status_code, resp.status_desc)
    log.info("%s header_len=%s body_len=%s", tag, resp.header_len, resp.body_len)
    log.info("%s body=\n%s", tag, preview)
end

log.info("wait_link %d ms", LINK_WAIT_MS)
local linked = lp.wait_link(LINK_WAIT_MS)
if not linked then
    log.warn("网络超时，没有网络无法测试 http")
    while true do rt.delay(10000) end
end
log.info("network ok, start http request")

log.info("---- GET ----")
-- 一次 request 会阻塞到收完。成功是 resp 表，失败是 nil, err, msg。
-- method 不写也是 GET；这里写清楚，避免和后面的 POST 搞混。
-- https 要带 tls_mode。TLS_INSECURE = 加密但不校验证书，不用 CA。
local resp, err, msg = http.request({
    url = GET_URL,
    method = http.METHOD_GET,
    tls_mode = http.TLS_INSECURE,
})
if not resp then
    log.error("GET fail err=%s msg=%s", err, msg)
else
    dump_resp("GET", resp)
end

log.info("---- POST ----")
-- body / data / post_data 三选一即可。不写 method 时，有 body 会自动当 POST。
-- 这里仍然显式写 METHOD_POST。content_type 不写底层不会自动补，需要时自己带。
resp, err, msg = http.request({
    url = POST_URL,
    method = http.METHOD_POST,
    body = POST_BODY,
    content_type = "text/plain",
    tls_mode = http.TLS_INSECURE,-- 不访问https的话可以不填这个参数
})
if not resp then
    log.error("POST fail err=%s msg=%s", err, msg)
else
    -- 打印响应结果
    dump_resp("POST", resp)
end

log.info("---- http.get ----")
-- 快捷 GET：url 用位置参数，opts 和 request 一样，https 照样能设 tls_mode。
resp, err, msg = http.get(GET_URL, {
    tls_mode = http.TLS_INSECURE,
})
if not resp then
    log.error("http.get fail err=%s msg=%s", err, msg)
else
    dump_resp("http.get", resp)
end

log.info("---- http.post ----")
-- 快捷 POST：url、body 用位置参数；content_type / tls_mode 放 opts。
resp, err, msg = http.post(POST_URL, POST_BODY, {
    content_type = "text/plain",
    tls_mode = http.TLS_INSECURE,
})
if not resp then
    log.error("http.post fail err=%s msg=%s", err, msg)
else
    dump_resp("http.post", resp)
end

log.info("---- done ----")
while true do rt.delay(10000) end

--[=[
  http request demo — 先等网络，再用 http.request 发 GET / POST

  http 是独立模块：require("http")。
  必须先有 PDP（能上网）。本 demo 用 lp.wait_link 等驻网，超时就停。

  本 demo 先用通用入口 http.request(opts)，再追加 http.get / http.post 快捷方法。
  http.sync(opts) 和 request 是同一个函数，行为完全一样。
  get / post 只是帮你填 url、method（post 再填 body），其余 opts 原样交给 request。
  所以 https 照样能设 tls_mode，写法跟 request 一样。

  和 mqtt/tcp 不同：http 没有托管线程、没有自动重连。
  一次 request 从发到收完都占着当前协程，返回了才算结束。
  失败不会自己再试，要再发就再调一次。

  测试地址用 httpbin：
    GET  https://httpbin.org/get
    POST https://httpbin.org/post   body = "hello doiot "
  成功时 httpbin 会把收到的 method / headers / body 原样折进 JSON 返回。

  ----------------------------------------------------------------------------
  http.request(opts) -> resp | nil, err, msg
  ----------------------------------------------------------------------------
    opts 必填
      url                 完整 URL，http 或 https 都行

    opts 常用（没写就用默认）
      method              字符串，或 http.METHOD_GET / METHOD_POST /
                          METHOD_PUT / METHOD_DELETE / METHOD_HEAD
                          不写且没 body → GET
                          不写但带了 body / data / post_data → POST
      body                请求体。data、post_data 是它的别名，三选一
      content_type        POST/PUT 的 Content-Type。不写底层不会自动补
      headers             自定义头，最多 32 对。写法见下
      timeout_s           发送超时（秒），默认 30
      timeout_r           接收超时（秒），默认 30
      max_response_size   响应体上限（字节），0=不限制。超出失败
      require_content_length  true 时响应没有 Content-Length 就失败

    HTTPS（https:// 必须配 tls_mode）
      本 demo 用 http.TLS_INSECURE：加密传输，不校验服务端证书，不用带 CA。
      要校验服务端：tls_mode = http.TLS_SERVER_AUTH，并带 ca_cert。
      双向校验：tls_mode = http.TLS_MUTUAL_AUTH，并带 ca_cert / client_cert / client_key。
      TLS_INSECURE=不校验  TLS_SERVER_AUTH=单向  TLS_MUTUAL_AUTH=双向

    本 demo 不用的项（以后文件/鉴权 demo 再讲）
      save / save_file / filename     把 body 落到 ublob/lfs/kv，不进 Lua 字符串
      basic_auth_user / basic_auth_password   要成对才生效

    headers 三种写法，本 demo 用第一种：
      { ["User-Agent"] = "doiot" }
      { "User-Agent", "doiot" }
      { { "User-Agent", "doiot" } }

    成功  resp 表
      protocol_version    如 "HTTP/1.1"
      status_code         如 200
      status_desc         如 "OK"
      header              响应头原文（不含状态行）
      header_len
      body                响应体。用了 save 时是空串
      body_len            响应体实际长度（save 时仍有效）

    失败  nil, 整数错误码, 错误字符串
      常见：-4 DNS  -6 连不上  -7 TLS  -8 超时  -15 响应太大

    调用返回前当前协程被占住。不要在 mqtt/tcp 的事件回调里调它。

  ----------------------------------------------------------------------------
  http.get(url[, opts]) -> resp | nil, err, msg
  http.get(url, filename[, opts])   -- filename 是落盘，本 demo 不用
  ----------------------------------------------------------------------------
    强制 method=GET，url 用第一个参数。
    opts 和 request 相同，包括 tls_mode / headers / timeout_*。
    https 同样要带 tls_mode；不写就不会按 TLS_INSECURE 配。

  ----------------------------------------------------------------------------
  http.post(url, body[, opts]) -> resp | nil, err, msg
  ----------------------------------------------------------------------------
    强制 method=POST，url / body 用前两个参数。
    opts 里再写 content_type、tls_mode 等。body 以位置参数为准，opts.body 会被盖掉。

  需要网络。没 SIM / 没驻网会失败。

  ============================================================================
  本 demo
  ============================================================================
    1) lp.wait_link 最多 60 秒；超时打印「网络超时，没有网络无法测试 http」后空转
    2) http.request GET  https://httpbin.org/get，tls_mode=TLS_INSECURE
    3) http.request POST https://httpbin.org/post，body 为 "hello doiot "，同样不校验证书
    4) http.get / http.post 再各打一枪，opts 里同样带 TLS_INSECURE
    5) 打印 status 和 body；然后空转

]=]
