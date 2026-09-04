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
    io = gpio.open(gpio.INPUT_GPIO, M.PIN)
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
