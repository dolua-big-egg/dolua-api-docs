--[=[
  GC032A 拍一张 320x240 彩色照，YUV422 原始流直接写入 ublob。
  I2C0：SCL = 模块 PIN 39 / PDDR 32，SDA = 模块 PIN 38 / PDDR 31，两根都是 map 2。
  CSPI 固定 PAD18–22，不在这里选。
  CAM_VDD 由 LDO28_EN 使能，模块 PIN20（MAIN_RI / GPIO27）。
  通讯脚走 Normal IO 域，与 C 侧摄像头例程一致设成 3.00V。
  成功后 ublob 「cam_color」的明文长度应为 153600（320*240*2）。
]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")
local camera = require("camera")
local ublob = require("ublob")

local BLOB = "cam_color"

log.info("camera_color_ublob")

local v = gpio.volt(gpio.NORMAL, 1.8)
log.info("NORMAL io volt %.2f", v)

local ldo28_en = gpio.open(gpio.BY_PINNO, 20)
local ldo_ok = ldo28_en:config(true, true, gpio.PULL_AUTO)
log.info("LDO28_EN pin20 %s", ldo_ok and "on" or "config fail")
rt.delay(20)

local ok, err = camera.init({
    model = "gc032a",
    color = true,
    i2c_id = 0,
    scl_pin_map = 2,
    sda_pin_map = 2,
})
if not ok then
    log.info("init fail: %s", tostring(err))
else
    ok, err = camera.capture({
        format = "raw",
        dest = "ublob",
        name = BLOB,
    })
    if not ok then
        log.info("capture fail: %s", tostring(err))
    else
        local n, serr = ublob.size(BLOB)
        log.info("saved %s size=%s err=%s", BLOB, tostring(n), tostring(serr))
    end
    camera.deinit()
end

while true do
    rt.delay(60 * 1000)
end
