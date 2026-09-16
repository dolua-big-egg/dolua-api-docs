--[=[
  iic_ssd1306 demo — 纯 Lua SSD1306 驱动（硬件 I2C0）
  ============================================================================
  本 demo
  ============================================================================
    1) i2c.new I2C0，ssd1306 初始化
    2) 三页循环：门户 → IMEI/ICCID/CSQ 条 → 时间/LBS
    3) 读不到的字段写 loading..
    IIC_SDA: PIN 58
    IIC_SCL: PIN 57
]=]

local rt = require("rt")
local log = require("log")
local i2c = require("i2c")
local info = require("info")
local lp = require("lp")
local lbs = require("lbs")
local ssd1306 = require("ssd1306")

local ADDR = 0x3C
local TITLE = "doLua"
local SLOGAN = "一行代码，万物互联"
local LOADING = "loading.."
local PAGE_MS = 3000
local CSQ_MAX = 33
local PAGES = 3

local bus = i2c.new(i2c.I2C0, {
    bus_speed = i2c.BUS_SPEED_FAST,
    timeout_ms = 100,
})

rt.delay(50)

local oled = ssd1306.new(bus, {
    addr = ADDR,
    width = 128,
    height = 64,
})

local function or_loading(s)
    if s == nil or s == "" then
        return LOADING
    end
    return tostring(s)
end

local function center_text(y, s)
    s = tostring(s or LOADING)
    local adv = ssd1306.FONT_ADV
    local maxn = oled.width // adv
    if #s > maxn then
        s = s:sub(1, maxn)
    end
    local x = (oled.width - #s * adv) // 2
    if x < 0 then
        x = 0
    end
    oled:text(x, y, s, 1)
end

local function draw_portal()
    local title_w = #TITLE * ssd1306.FONT_ADV * 2
    local slogan_w = 9 * ssd1306.FONT_CJK_W
    oled:text((oled.width - title_w) // 2, 16, TITLE, 1, 2)
    oled:text((oled.width - slogan_w) // 2, 36, SLOGAN, 1)
end

local function draw_csq_bar(x, y, w, h, csq)
    oled:rect(x, y, w, h, 1)
    local unknown = (csq == nil) or (csq == 99) or (csq < 0)
    if unknown then
        center_text(y + (h - 8) // 2, LOADING)
        return
    end
    if csq > CSQ_MAX then
        csq = CSQ_MAX
    end
    local inner_w = w - 4
    local inner_h = h - 4
    if inner_w < 1 or inner_h < 1 then
        return
    end
    local fill = (csq * inner_w) // CSQ_MAX
    if fill > 0 then
        oled:fill_rect(x + 2, y + 2, fill, inner_h, 1)
    end
end

local function draw_id()
    local imei = info.imei()
    local iccid = info.iccid()
    local csq = info.csq()
    if imei and #imei + 5 <= (oled.width // ssd1306.FONT_ADV) then
        center_text(6, "IMEI " .. imei)
    else
        center_text(6, or_loading(imei))
    end
    center_text(24, or_loading(iccid))
    draw_csq_bar(4, 42, oled.width - 8, 16, csq)
end

local function draw_loc()
    if info.time_ready() then
        center_text(6, or_loading(info.times("%Y-%m-%d %H:%M:%S")))
    else
        center_text(6, LOADING)
    end

    local loc = lbs.cache()
    if loc and loc.latitude and loc.longitude then
        center_text(24, "LAT " .. loc.latitude)
        center_text(42, "LON " .. loc.longitude)
    else
        center_text(24, LOADING)
        center_text(42, LOADING)
    end
end

local function draw_page(page)
    oled:fill(0)
    if page == 1 then
        draw_portal()
    elseif page == 2 then
        draw_id()
    else
        draw_loc()
    end
    return oled:flush()
end

-- lbs.sync 会占住整台 Lua 调度，只在后台偶发刷新；界面只读 cache
rt.task_start(function()
    while true do
        local cached = lbs.cache()
        if cached then
            rt.delay(60000)
        else
            if lp.wait_link(10000) then
                local resp, err, msg = lbs.sync({
                    lbs_mode = lbs.MODE_SINGLE_CELL,
                    timeout_s = 5,
                    timeout_r = 8,
                    retry_count = 1,
                })
                if resp then
                    log.info("lbs lon=%s lat=%s", resp.longitude, resp.latitude)
                else
                    log.warn("lbs fail code=%s msg=%s", err, msg)
                end
            end
            rt.delay(5000)
        end
    end
end)

local inited = false
local page = 1

while true do
    if not inited then
        inited = oled:init()
        if inited then
            log.info("SSD1306 init ok, addr=0x%02X", ADDR)
            page = 1
        else
            log.warn("SSD1306 init fail, retry")
            local found = bus:scan()
            if found and #found > 0 then
                local t = {}
                for i = 1, #found do
                    t[i] = string.format("0x%02X", found[i])
                end
                log.info("i2c scan: %s", table.concat(t, ","))
            else
                log.warn("i2c scan empty")
            end
            rt.delay(1000)
        end
    else
        if not draw_page(page) then
            log.warn("SSD1306 flush fail, re-init")
            inited = false
            rt.delay(1000)
        else
            page = page + 1
            if page > PAGES then
                page = 1
            end
            rt.delay(PAGE_MS)
        end
    end
end

--[=[
  iic_ssd1306 demo — 纯 Lua SSD1306 三页循环

  不 require("lcd")。屏协议、1bit 帧缓冲、画图全在 ssd1306.lua。
  字库在 ssd1306_font.lua。身份/信号/时间用 info，坐标用 lbs.cache。

  ============================================================================
  接线（NT26-PRO）
  ============================================================================
    I2C0 SCL = PIN 57（PDDR 13）
    I2C0 SDA = PIN 58（PDDR 14）
    OLED VCC / GND 按模块供电（常见 3.3V）
    7bit 地址默认 0x3C

  ============================================================================
  三页
  ============================================================================
    1 门户    doLua + 「一行代码，万物互联」
    2 身份    第 1 行 IMEI；第 2 行 ICCID；第 3 行 CSQ 填充进度条（满格按 33）
    3 定位    第 1 行本地时间；第 2/3 行 LAT / LON
    读不到（nil、空串、csq=99、时钟未就绪、尚无 LBS 缓存）写 loading..
    每页停留 3 秒，然后下一页，循环。

  ============================================================================
  自定义模块
  ============================================================================
    工程 modules 登记 ssd1306.lua、ssd1306_font.lua
    :text UTF-8；缺字 '?'；新增汉字改 ssd1306_font.lua 的 CJK 表

  ============================================================================
  本 demo
  ============================================================================
    1) i2c.new I2C0，400kHz
    2) ssd1306.new + :init
    3) 后台等驻网后 lbs.sync（会卡住调度，所以不放在刷屏循环里）
    4) 前台三页循环刷屏

]=]
