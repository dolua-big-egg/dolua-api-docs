--[=[
  epub_parse — 从 ublob 里的 book.epub 抽纯文字，封面图另存一份
  ============================================================================
  内置文件勾选 book.epub，存储位置 blob。下载后 ublob 里的名字就是 "book.epub"。
  这本书约 68KB，zip.open({ ublob = name }) 会把整包明文读进堆，再按成员解开。

  顺序：
    1. META-INF/container.xml 里的 full-path 指向 OPF
    2. OPF 的 manifest 是包内文件，spine 是阅读顺序
    3. 封面图（meta name="cover" 指到的 image/*，或 properties 含 cover-image）
       整份 extract 后 ublob.write。名字只取文件名，ublob 不能带路径。
    4. guide 里 type="cover" 的那一页仍然跳过，不当正文打印
    5. 剩下的 XHTML 去掉标签，用 uart.sync_write 按 1024 字节送出，每块后喂狗
]=]

local rt = require("rt")
local log = require("log")
local zip = require("zip")
local uart = require("uart")
local sys = require("sys")
local ublob = require("ublob")

local NAME = "book.epub"
local OUT_UART = uart.UART1
local WRITE_CHUNK = 1024

local function halt(msg)
    log.error("%s", msg)
    while true do
        rt.delay(10000)
    end
end

local function attr(tag, key)
    return tag:match("[%s<]" .. key .. '%s*=%s*"([^"]*)"')
        or tag:match("^" .. key .. '%s*=%s*"([^"]*)"')
end

local function dirname(path)
    return path:match("^(.*[/\\])") or ""
end

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function join_path(base, href)
    if href:find("^/") then
        return href:sub(2)
    end
    return base .. href
end

local function decode_entities(s)
    s = s:gsub("&(amp);", "&")
    s = s:gsub("&(lt);", "<")
    s = s:gsub("&(gt);", ">")
    s = s:gsub("&(quot);", '"')
    s = s:gsub("&(apos);", "'")
    s = s:gsub("&(nbsp);", " ")
    s = s:gsub("&#(%d+);", function(n)
        local cp = tonumber(n)
        if not cp or cp < 0 or cp > 0x10FFFF then
            return ""
        end
        return utf8.char(cp)
    end)
    s = s:gsub("&#x(%x+);", function(n)
        local cp = tonumber(n, 16)
        if not cp or cp < 0 or cp > 0x10FFFF then
            return ""
        end
        return utf8.char(cp)
    end)
    return s
end

-- 标签可以跨行。段落、标题、换行换成换行，其余标签直接丢掉。
local function strip_tags(s)
    local parts = {}
    local i = 1
    local n = #s
    local block = {
        p = true, div = true, br = true, h1 = true, h2 = true, h3 = true,
        h4 = true, li = true, tr = true, blockquote = true,
    }
    while i <= n do
        local lt = s:find("<", i, true)
        if not lt then
            parts[#parts + 1] = s:sub(i)
            break
        end
        if lt > i then
            parts[#parts + 1] = s:sub(i, lt - 1)
        end
        local gt = s:find(">", lt + 1, true)
        if not gt then
            break
        end
        local name = s:sub(lt + 1, gt - 1):match("^%s*/?%s*(%a[%w]*)")
        if name and block[name:lower()] then
            parts[#parts + 1] = "\n"
        end
        i = gt + 1
    end
    local text = table.concat(parts)
    text = decode_entities(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("[ \t]+\n", "\n")
    text = text:gsub("\n[ \t]+", "\n")
    text = text:gsub("\n\n+", "\n\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function write_body(s)
    local n = #s
    local i = 1
    while i <= n do
        local j = i + WRITE_CHUNK - 1
        if j > n then
            j = n
        end
        if not uart.sync_write(OUT_UART, s:sub(i, j)) then
            return false
        end
        sys.wdt_kick()
        i = j + 1
    end
    return true
end

local function must_extract(z, name)
    local body, err = z:extract(name)
    if not body then
        halt("extract " .. name .. " fail: " .. tostring(err))
    end
    return body
end

local z, zerr = zip.open({ ublob = NAME })
if not z then
    halt("zip.open fail: " .. tostring(zerr))
end

local container = must_extract(z, "META-INF/container.xml")
local opf_path = container:match('full%-path%s*=%s*"([^"]+)"')
if not opf_path then
    z:close()
    halt("no opf path")
end
log.info("opf %s", opf_path)

local opf = must_extract(z, opf_path)
local base = dirname(opf_path)
local title = opf:match("<dc:title[^>]*>(.-)</dc:title>") or ""
title = decode_entities(strip_tags(title))
log.info("title %s", title)

local cover_id = nil
local cover_href = nil
for tag in opf:gmatch("<meta%s+[^>]+") do
    if attr(tag, "name") == "cover" then
        cover_id = attr(tag, "content")
    end
end
for tag in opf:gmatch("<reference%s+[^>]+") do
    if attr(tag, "type") == "cover" then
        cover_href = attr(tag, "href")
    end
end
log.info("cover id=%s href=%s", tostring(cover_id), tostring(cover_href))

local manifest = {}
for tag in opf:gmatch("<item%s+[^>]+") do
    local id = attr(tag, "id")
    local href = attr(tag, "href")
    if id and href then
        manifest[id] = {
            href = href,
            path = join_path(base, href),
            media = attr(tag, "media%-type") or "",
            props = attr(tag, "properties") or "",
        }
    end
end

local function is_image(item)
    return item ~= nil and item.media:find("^image/") ~= nil
end

local function find_cover_image()
    local by_id = cover_id and manifest[cover_id]
    if is_image(by_id) then
        return by_id
    end
    for _, item in pairs(manifest) do
        if is_image(item) and item.props:find("cover-image", 1, true) then
            return item
        end
    end
    return nil
end

local cover_img = find_cover_image()
if not cover_img then
    log.info("no cover image")
else
    log.info("cover image %s", cover_img.path)
    local img, ierr = z:extract(cover_img.path)
    if not img then
        log.error("cover extract fail: %s", tostring(ierr))
    else
        local blob_name = basename(cover_img.href)
        local ok, werr = ublob.write(blob_name, img)
        if not ok then
            log.error("ublob.write %s fail: %s", blob_name, tostring(werr))
        else
            log.info("cover saved %s bytes=%d", blob_name, #img)
        end
        sys.wdt_kick()
    end
end

local function skip_reason(id, item)
    if not item then
        return "missing"
    end
    if item.media:find("^image/") then
        return "image"
    end
    if cover_id and id == cover_id then
        return "cover-meta"
    end
    if item.props:find("cover-image", 1, true) then
        return "cover-image"
    end
    if cover_href and item.href == cover_href then
        return "cover-page"
    end
    if item.media ~= "application/xhtml+xml" and item.media ~= "text/html" then
        return "not-html"
    end
    return nil
end

local order = 0
for tag in opf:gmatch("<itemref%s+[^>]+") do
    local id = attr(tag, "idref")
    if id then
        order = order + 1
        local item = manifest[id]
        local why = skip_reason(id, item)
        if why then
            local href = item and item.href or "?"
            log.info("skip [%d] %s %s (%s)", order, id, href, why)
        else
            log.info("text [%d] %s %s", order, id, item.path)
            local html, err = z:extract(item.path)
            if not html then
                log.error("extract %s fail: %s", item.path, tostring(err))
            else
                local text = strip_tags(html)
                log.info("----- %s begin bytes=%d -----", item.href, #text)
                if not write_body(text) then
                    log.error("sync_write fail %s", item.href)
                end
                uart.sync_write(OUT_UART, "\n")
                sys.wdt_kick()
                log.info("----- %s end -----", item.href)
            end
        end
    end
end

z:close()
log.info("epub closed")

while true do
    rt.delay(10000)
end
