--[=[
  dream 【梦想模块】 demo — 双色球 / 大乐透
  ============================================================================
  本 demo
  ============================================================================
    1) 双色球：真随机 1 注、再 3 注
    2) 大乐透：真随机 1 注、再 3 注
    3) 生日种子 + 混入 TRNG（stable=false，默认）：连抽两次，号码应不同
    4) 生日种子 + 可复现（stable=true）：连抽两次，号码应相同
    5) 生日拼接当天日期：seed = 生日 + 当天，stable=true 则同一天结果固定

    TRNG 是物理随机数发生器，每次调用都是真正的随机数，绝对的随机，天命所在。

    等我中了我就跟老板说上二修五，嘿嘿嘿。👈(⌒▽⌒)👉
]=]

local rt = require("rt")
local log = require("log")
local info = require("info")
local dream = require("dream")

local BIRTHDAY = "2000-08-15"

log.info("dream ssq %d/%d + %d/%d  dlt %d/%d + %d/%d  count_max=%d",
         dream.SSQ_FRONT_COUNT, dream.SSQ_FRONT_MAX,
         dream.SSQ_BACK_COUNT, dream.SSQ_BACK_MAX,
         dream.DLT_FRONT_COUNT, dream.DLT_FRONT_MAX,
         dream.DLT_BACK_COUNT, dream.DLT_BACK_MAX,
         dream.COUNT_MAX)

log.info("---- 双色球 真随机 ----")
local s1 = dream.ssq()
log.info("ssq x1 %s", s1[1].text)
local s3 = dream.ssq(3)
log.info("ssq x3 %s | %s | %s", s3[1].text, s3[2].text, s3[3].text)

log.info("---- 大乐透 真随机 ----")
local d1 = dream.dlt()
log.info("dlt x1 %s", d1[1].text)
local d3 = dream.dlt(3)
log.info("dlt x3 %s | %s | %s", d3[1].text, d3[2].text, d3[3].text)

log.info("---- 生日 %s 混入真随机（每次不同）----", BIRTHDAY)
local mix1 = dream.ssq(3, BIRTHDAY)
local mix2 = dream.ssq({ count = 3, seed = BIRTHDAY, stable = false })
log.info("ssq mix#1 %s | %s | %s", mix1[1].text, mix1[2].text, mix1[3].text)
log.info("ssq mix#2 %s | %s | %s", mix2[1].text, mix2[2].text, mix2[3].text)
log.info("ssq mix same=%s", tostring(
    mix1[1].text == mix2[1].text and mix1[2].text == mix2[2].text and mix1[3].text == mix2[3].text))

local dmix1 = dream.dlt(2, BIRTHDAY)
local dmix2 = dream.dlt({ count = 2, seed = BIRTHDAY })
log.info("dlt mix#1 %s | %s", dmix1[1].text, dmix1[2].text)
log.info("dlt mix#2 %s | %s", dmix2[1].text, dmix2[2].text)
log.info("dlt mix same=%s", tostring(dmix1[1].text == dmix2[1].text and dmix1[2].text == dmix2[2].text))

log.info("---- 生日 %s 可复现（stable=true，结果固定）----", BIRTHDAY)
local st1 = dream.ssq(3, BIRTHDAY, true)
local st2 = dream.ssq({ count = 3, seed = BIRTHDAY, stable = true })
log.info("ssq stable#1 %s | %s | %s", st1[1].text, st1[2].text, st1[3].text)
log.info("ssq stable#2 %s | %s | %s", st2[1].text, st2[2].text, st2[3].text)
log.info("ssq stable same=%s", tostring(
    st1[1].text == st2[1].text and st1[2].text == st2[2].text and st1[3].text == st2[3].text))

local dst1 = dream.dlt(BIRTHDAY, 2, true)
local dst2 = dream.dlt({ count = 2, seed = BIRTHDAY, stable = true })
log.info("dlt stable#1 %s | %s", dst1[1].text, dst1[2].text)
log.info("dlt stable#2 %s | %s", dst2[1].text, dst2[2].text)
log.info("dlt stable same=%s", tostring(dst1[1].text == dst2[1].text and dst1[2].text == dst2[2].text))

local today = info.times("%Y-%m-%d")
log.info("---- 生日拼接当天 %s + %s ----", BIRTHDAY, tostring(today))
if not today or today == "" then
    log.warn("no local date, skip birthday+today")
else
    local day_seed = BIRTHDAY .. "+" .. today
    log.info("day_seed=%s", day_seed)

    local ds1 = dream.ssq(3, day_seed, true)
    local ds2 = dream.ssq({ count = 3, seed = day_seed, stable = true })
    log.info("ssq day stable#1 %s | %s | %s", ds1[1].text, ds1[2].text, ds1[3].text)
    log.info("ssq day stable#2 %s | %s | %s", ds2[1].text, ds2[2].text, ds2[3].text)
    log.info("ssq day stable same=%s", tostring(
        ds1[1].text == ds2[1].text and ds1[2].text == ds2[2].text and ds1[3].text == ds2[3].text))

    local dd1 = dream.dlt(2, day_seed, true)
    local dd2 = dream.dlt({ count = 2, seed = day_seed, stable = true })
    log.info("dlt day stable#1 %s | %s", dd1[1].text, dd1[2].text)
    log.info("dlt day stable#2 %s | %s", dd2[1].text, dd2[2].text)
    log.info("dlt day stable same=%s", tostring(dd1[1].text == dd2[1].text and dd1[2].text == dd2[2].text))

    local sm = dream.ssq(3, day_seed)
    local dm = dream.dlt(2, day_seed)
    log.info("ssq day mix %s | %s | %s", sm[1].text, sm[2].text, sm[3].text)
    log.info("dlt day mix %s | %s", dm[1].text, dm[2].text)
end

log.info("dream demo done")

while true do
    rt.delay(10000)
end

--[=[
  dream demo — 双色球 / 大乐透

  require("dream")。娱乐开号，失败返回 nil, err_msg。
  不依赖网络 / 外设。

  ----------------------------------------------------------------------------
  dream.ssq([count_or_seed_or_opt[, seed_or_count[, stable]]]) -> tickets | nil, err
  dream.dlt(...)     -- 参数相同
  dream.shuangseqiu / dream.daletou  -- 别名
  ----------------------------------------------------------------------------
    双色球：前区 6 个（1~33）+ 后区 1 个（1~16）
    大乐透：前区 5 个（1~35）+ 后区 2 个（1~12）
    前区、后区均不重复、已升序。

    count   注数，默认 1，范围 1~dream.COUNT_MAX（100）
    seed    字符串或整数，可选。省略则纯 TRNG。
            常见用法是生日，如 "1990-08-15"
    stable  仅在有 seed 时生效，默认 false
            false — 种子再混入 TRNG，每次号码不同
            true  — 只用种子，同一 seed+count 结果固定

    调用形式
      dream.ssq()
      dream.ssq(5)
      dream.ssq("1990-08-15")
      dream.ssq(5, "1990-08-15")
      dream.ssq("1990-08-15", 5)
      dream.ssq("1990-08-15", true)
      dream.ssq(5, "1990-08-15", true)
      dream.ssq({ count = 5, seed = "1990-08-15", stable = true })
      dream.ssq(3, "1990-08-15+" .. info.times("%Y-%m-%d"), true)

    成功返回 table（即使 1 注也是数组），每注：
      front  table   前区
      back   table   后区（双色球长度为 1）
      text   string  如 "01 08 15 22 27 33 + 07"

    常量
      dream.COUNT_MAX
      dream.SSQ_FRONT_COUNT / SSQ_FRONT_MAX / SSQ_BACK_COUNT / SSQ_BACK_MAX
      dream.DLT_FRONT_COUNT / DLT_FRONT_MAX / DLT_BACK_COUNT / DLT_BACK_MAX

  ============================================================================
  本 demo
  ============================================================================
    真随机各开双色球、大乐透；再用生日演示「混随机」和「可复现」；
    最后把生日与 info.times("%Y-%m-%d") 拼成当天种子。

]=]
