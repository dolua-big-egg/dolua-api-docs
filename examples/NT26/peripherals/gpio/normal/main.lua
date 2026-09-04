--[=[
  gpio demo — 初始化 / 输入 / 输出 / 翻转 / pins / seq
  ============================================================================
  本 demo
  ============================================================================
    1) open GPIO 9 输出（板载灯）、GPIO 1 输入
    2) pins / set / get / tog
    3) seq 播一段时序
    4) 循环 tog 灯并读输入

]=]

local rt = require("rt")
local log = require("log")
local gpio = require("gpio")

local OUT_GPIO = 9 -- 板载指示灯
local IN_GPIO = 1  -- 输入脚

-- 打开：按 GPIO 编号拿到对象
local led = gpio.open(gpio.INPUT_GPIO, OUT_GPIO)
local din = gpio.open(gpio.INPUT_GPIO, IN_GPIO)

-- 输出：初始灭；输入：内部上拉，避免悬空乱跳
local ok_led = led:config(true, false, gpio.PULL_AUTO)
local ok_din = din:config(false, false, gpio.PULL_UP)
log.info("config led=%s din=%s", ok_led, ok_din)

-- pins：看编号和引脚的对应关系
local g, pin, typ, id = led:pins()
log.info("led pins gpio=%d pin_no=%d type=%d id=%d", g, pin, typ, id)
g, pin, typ, id = din:pins()
log.info("din pins gpio=%d pin_no=%d type=%d id=%d", g, pin, typ, id)

-- 输出：置高、读回、翻转
led:set(true)
log.info("led set high get=%s", led:get())
local after = led:tog()
log.info("led tog -> %s get=%s", after, led:get())

-- 输入：读一次当前电平
log.info("din get=%s", din:get())

-- seq：高 200ms、低 200ms、高 200ms，结束保持（最后一次 keep 后已翻到低）
local ok_seq = led:seq(gpio.TIME_MS, {1, 200, 200, 200, 0})
log.info("seq done=%s get=%s", ok_seq, led:get())

while true do
    local lv = led:tog()
    log.info("loop led=%s din=%s", lv, din:get())
    rt.delay(1000)
end

--[=[
  gpio demo — 初始化 / 输入 / 输出 / 翻转 / pins / seq

  gpio 是平台扩展模块。先 open 得到对象，再 config，然后 set/get/tog/seq。
  本 demo：GPIO 9 做输出（板载灯），GPIO 1 做输入。

  ----------------------------------------------------------------------------
  gpio.open(type, id) -> obj
  ----------------------------------------------------------------------------
    type  gpio.INPUT_GPIO   按 GPIO 编号（本 demo 用这个）
          gpio.INPUT_PINNO  按模块引脚序号
    id    对应的编号
    返回  GPIO 对象；编号非法或打开失败会抛错

  ----------------------------------------------------------------------------
  obj:config(is_output, init_level [, pull]) -> boolean
  ----------------------------------------------------------------------------
    is_output   true=输出，false=输入
    init_level  输出时的初始电平，true=高 / false=低（输入时可写 false）
    pull        可选，默认 gpio.PULL_AUTO
                gpio.PULL_AUTO / PULL_UP / PULL_DOWN
    返回        true 成功，false 失败

  ----------------------------------------------------------------------------
  obj:set(level) -> boolean
  ----------------------------------------------------------------------------
    level  true=高，false=低（只对输出有意义）
    返回   true 成功，false 失败

  ----------------------------------------------------------------------------
  obj:get() -> 0|1|nil
  ----------------------------------------------------------------------------
    读当前电平。成功 0 或 1，失败 nil。输入、输出都可以读。

  ----------------------------------------------------------------------------
  obj:tog() -> 0|1|nil
  ----------------------------------------------------------------------------
    把当前电平翻转后写出。成功返回翻转后的电平 0/1，失败 nil。
    一般用于输出脚。

  ----------------------------------------------------------------------------
  obj:pins() -> gpio, pin_no, type, id
  ----------------------------------------------------------------------------
    一次返回四个数，查看这个对象实际绑到哪：
      gpio     内部 GPIO 编号
      pin_no   模块引脚序号
      type     打开时用的类型（INPUT_GPIO / INPUT_PINNO）
      id       打开时传入的 id
    打开失败不会走到这里；四个值都是 number。

  ----------------------------------------------------------------------------
  obj:seq(unit, payload) -> true
  ----------------------------------------------------------------------------
    按数组播一段电平时序，调用会阻塞到播完（这段时间其它协程也跑不了）。

    unit     gpio.TIME_MS / TIME_SEC / TIME_US
    payload  { 起始电平, 维持1, 维持2, ..., 结束动作 }
             起始电平、结束动作只能是 0 或 1
             中间每一段是“保持当前电平 unit 这么久，然后翻转”
             结束动作 1=整段结束后再翻转一次，0=保持最后电平
    返回     成功 true；参数/硬件失败会抛错
    例       {1, 200, 200, 0} + TIME_MS
             先拉高 → 高 200ms → 低 200ms → 结束不再翻

  本 demo 不涉及中断、wave，那些见其它 gpio 工程。

  ============================================================================
  本 demo
  ============================================================================
    1) open GPIO 9 输出（板载灯）、GPIO 1 输入
    2) pins / set / get / tog
    3) seq 播一段时序
    4) 循环 tog 灯并读输入

]=]
