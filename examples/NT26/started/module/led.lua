--[[
  led — 开发板指示灯（GPIO 9）
  对外：参数 PIN / interval_ms，方法 init / on / off
]]

local gpio = require("gpio")

local M = {
    PIN = 9,
    interval_ms = 500,
}

local io = nil

function M.init()
    -- 按 GPIO 编号打开（旧名 gpio.INPUT_GPIO 同值，仍可用）
    io = gpio.open(gpio.BY_GPIO, M.PIN)
    io:config(true, false, gpio.PULL_AUTO)
    M.off()
end

function M.on()
    if io then io:set(true) end
end

function M.off()
    if io then io:set(false) end
end

return M
