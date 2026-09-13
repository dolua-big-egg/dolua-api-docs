--[[ download — HTTP 落到 LittleFS，再按 100 字节流式读

  和 ublob 下载的差别：
    ublob  系统内置小文件系统，配额约 80KB，只适合几十 KB
    lfs    外挂 W25Qxx 上的 LittleFS，本 demo 分区 2MB，能放下更大的包

  save = http.save.lfs(fs, path) 之后：
    resp.body 是空串（整包不进 Lua 字符串）
    resp.body_len / resp.saved.path / resp.saved.kind 有效

  读文件不要整包 load 进 Lua。fs:open + f:read(n) 每次从 Flash 抽一片，
  适合流式处理。用完 close。
]]

local log = require("log")
local http = require("http")

local M = {}

M.URL = "https://www.baidu.com/"
M.PATH = "/demo.bin"
M.CHUNK_SIZE = 100

local function stream_print(fs, path, chunk_size)
    local f, e = fs:open(path, "r")
    if not f then
        return false, "open r: " .. tostring(e)
    end

    local total = 0
    while true do
        local chunk, rerr = f:read(chunk_size)
        if chunk == nil then
            f:close()
            return false, "read: " .. tostring(rerr)
        end
        if chunk == "" then
            break
        end
        -- 用 [] 包起来，方便看每一片的边界
        log.info("[%s]", chunk)
        total = total + #chunk
    end
    f:close()
    return true, total
end

function M.run(fs)
    if fs == nil then
        return false, "fs nil"
    end

    pcall(function()
        fs:remove(M.PATH)
    end)

    log.info("GET %s -> lfs:%s", M.URL, M.PATH)
    -- https 要带 tls_mode。save 必须是 http.save.lfs(已挂载的 fs, 路径)
    local resp, err, msg = http.get(M.URL, {
        tls_mode = http.TLS_INSECURE,
        save = http.save.lfs(fs, M.PATH),
        max_response_size = 512 * 1024,
    })
    if not resp then
        return false, string.format("http fail err=%s msg=%s", err, msg)
    end

    log.info("status=%s %s body_len=%s lua_body_len=%s",
             resp.status_code, resp.status_desc, resp.body_len,
             resp.body and #resp.body or 0)
    if resp.saved then
        log.info("saved.kind=%s path=%s", resp.saved.kind, resp.saved.path)
    end
    if resp.status_code ~= 200 then
        return false, "http status not 200"
    end

    local st, serr = fs:stat(M.PATH)
    if not st then
        return false, "stat: " .. tostring(serr)
    end
    log.info("lfs.stat size=%s type=%s http.body_len=%s", st.size, st.type, resp.body_len)
    if st.size ~= (resp.body_len or 0) then
        return false, "size mismatch"
    end

    log.info("---- stream 100B ----")
    local ok, total = stream_print(fs, M.PATH, M.CHUNK_SIZE)
    if not ok then
        return false, total
    end
    log.info("stream done total_read=%s expect=%s", total, st.size)
    if total ~= st.size then
        return false, "read total mismatch"
    end
    return true
end

return M
