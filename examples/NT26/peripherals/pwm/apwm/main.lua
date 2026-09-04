--[=[
  apwm demo — AON 常电 PWM 慢闪
  ============================================================================
  本 demo
  ============================================================================
    F6E0 PIN101 可出 APWM1。
    周期 1024ms，30% 处拉高、80% 处拉低（高电平约 512ms）。
    给休眠状态灯用，不是 kHz 调光。示波器时基放到 200ms/div 左右。

    注：这玩意儿频率极低，比较适合做休眠状态灯。

]=]

local rt = require("rt")
local log = require("log")
local pwm = require("pwm")

local PIN = 100 -- F6E0 PIN100-GPIO23 = APWM0

local ch = pwm.open(pwm.INPUT_PINNO, PIN)
ch:start({
    mode = pwm.MODE_APWM,
    period = pwm.APWM_1024MS,-- 周期1024ms,约1HZ
    high = 30,
    low = 80,
})

local info = ch:info()
log.info("apwm pddr=%s pin=%s idx=%s",
         tostring(info.pddr), tostring(info.pin_no), tostring(info.apwm))

while true do
    log.info("apwm running=%s", tostring(ch:info().running))
    rt.delay(5000)
end

--[=[
  apwm demo — Always-On PWM

  APWM 挂在 AON/PMU，周期是 32ms~4096ms，sleep 时仍可继续出波。
  只有 PIN100/101/16 能出 APWM0/1/2。默认 open 正相 PWM 走 TIMER，
  必须显式 mode = pwm.MODE_APWM。

  ----------------------------------------------------------------------------
  obj:start({ mode = pwm.MODE_APWM, ... })
  ----------------------------------------------------------------------------
    写法 1（推荐，和芯片一致）：
      period  只能从下面 8 档里选，芯片没有连续 freq
      high    周期内百分之几处拉高（0~100）
      low     周期内百分之几处拉低，必须 > high
      例      1024ms, high=30, low=80 → 约 307ms 拉高，819ms 拉低

      period 可选值：
        pwm.APWM_32MS     32ms    ~31.25Hz
        pwm.APWM_64MS     64ms    ~15.63Hz
        pwm.APWM_128MS    128ms   ~7.81Hz
        pwm.APWM_256MS    256ms   ~3.91Hz
        pwm.APWM_512MS    512ms   ~1.95Hz
        pwm.APWM_1024MS   1024ms  ~0.98Hz
        pwm.APWM_2048MS   2048ms  ~0.49Hz
        pwm.APWM_4096MS   4096ms  ~0.24Hz

    写法 2（简写）：
      freq    约 Hz，内部选最接近的 period 枚举
      duty    0~100，等价 high=0、low=duty

  set_duty 会按 high=0、low=duty 重配。不要拿 APWM 做蜂鸣器或电机。

]=]
