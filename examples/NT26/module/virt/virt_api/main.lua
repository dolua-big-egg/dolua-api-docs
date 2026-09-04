--[=[
  virat demo — 虚拟 AT：App 引擎 / EC平台引擎
  ============================================================================
  本 demo
  ============================================================================
    1) virat.exec：走 App 已注册 AT（ATI / VERSION / IMEI 等只读查询）
    2) 同一条 EC平台引擎指令用 exec：预期失败（指令未注册）
    3) virat.ril_exec：把同一条转给 EC平台引擎
    能用 Lua API 拿到的参数（info.imei / info.csq / sys.version 等）不要走虚拟 AT。
    除非官方指导，否则不要往 EC平台引擎发指令。

]=]

local rt = require("rt")
local log = require("log")
local virat = require("virat")

local function oneline(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    return (s:gsub("\r", "\\r"):gsub("\n", "\\n"))
end

local function show(tag, cmd, ok, resp)
    local text = resp or ""
    log.info("[%s] cmd=%s ok=%s len=%d", tag, cmd, tostring(ok), #text)
    log.info("[%s] resp=%s", tag, oneline(text))
end

-- App 引擎已注册的只读查询。本身有 Lua API 的，这里只为对照 AT 回显。
local app_cmds = {
    "AT\r\n",
    "ATI\r\n",
    "AT+VERSION\r\n",  -- sys.version()
    "AT+IMEI\r\n",     -- info.imei()
    "AT+ICCID\r\n",    -- info.iccid()
    "AT+IMSI\r\n",     -- info.imsi()
    "AT+CSQ\r\n",      -- info.csq()
    "AT+CEREG\r\n",    -- info.cereg()
    "AT+UTC\r\n",      -- info.timestamp()
}

log.info("---- virat.exec (App AT) ----")
for i = 1, #app_cmds do
    local cmd = app_cmds[i]
    local ok, resp = virat.exec(cmd)
    show("exec", cmd, ok, resp)
    rt.delay(300)
end


log.info("---- virat.ril_exec (EC平台引擎；非官方指导勿发) ----")
do
    local ok, resp = virat.ril_exec("AT+CGSN=1\r\n")
    show("ril", "AT+CGSN=1\r\n", ok, resp)
end

log.info("virat demo done")
while true do
    rt.delay(10000)
end

--[=[
  virat demo — 虚拟 AT（App 引擎 / EC平台引擎）

  require("virat")。两条路不是同一个解析器，命令集也不通：
    exec      App 自定义 AT（g_cmd_list），如 AT+VERSION / AT+IMEI
    ril_exec  EC平台引擎（atRilAtCmdReq），如 AT+ECDNSCFG?

  能用 Lua API 拿到的，不要用虚拟 AT。本 demo 只查询，不写 NVM、不切 CFUN。
  除非官方指导，否则不要往 EC平台引擎（ril_exec）发指令。

  ----------------------------------------------------------------------------
  virat.exec(at_cmd [, route_id]) -> ok, resp
  ----------------------------------------------------------------------------
    走 at_cmd_center_parse_for_lua，同步等完整回显。
    at_cmd    完整 AT 行，建议以 \r\n 结尾
    route_id  可选，默认 0。AT 若还要往某路串口回写才用得上；
              Lua 这条路径的响应已经在第二个返回值里
    ok        解析流程成功（boolean）。未注册指令也可能 ok=true，
              回显里是 +CME ERROR: 1（指令未注册）
    resp      完整响应文本，可能含 \r\n；空串表示没收到正文

  ----------------------------------------------------------------------------
  virat.ril_exec(at_cmd [, timeout_ms]) -> ok, resp
  ----------------------------------------------------------------------------
    走 EC平台引擎（virt_at_send_wait → atRilAtCmdReq），等 OK / ERROR。
    除非官方指导，否则不要调用本接口、不要往里面发指令。
    at_cmd      完整 AT 行，必须以 \r 结尾（\r\n 也可以）
    timeout_ms  可选，默认 10000
    ok          发送成功且响应里含 "OK"
    resp        累积到的响应，上限约 4096 字节
    未开 FEATURE_RIL_AT_API_ENABLE 时 ok=false，resp="FEATURE_RIL_AT_API_ENABLE off"

  ----------------------------------------------------------------------------
  怎么选
  ----------------------------------------------------------------------------
    App 已注册（VERSION / IMEI / ICCID / CSQ / CEREG / UTC …）→ exec
    EC平台引擎（ECDNSCFG / ECDNS / QIDNSCFG …）→ ril_exec
    除非官方指导，否则不要往 EC平台引擎发指令。
    不要对同一条命令两条路都试「看谁通」：未注册在 exec 里是 CME ERROR，不是自动转发。

  ============================================================================
  本 demo
  ============================================================================
    exec 跑一组 App 只读查询；再用 exec 打 ECDNSCFG? 看失败；
    最后 ril_exec 同一条，走 EC平台引擎。不改 DNS、不拨号。
    ril_exec 仅演示官方指定的 ECDNSCFG?；其它指令不要自己发。

]=]
