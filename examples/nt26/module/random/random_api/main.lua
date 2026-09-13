--[=[
  random demo — TRNG 随机数
  ============================================================================
  本 demo
  ============================================================================
    1) random / randint / uniform / randrange
    2) choice / shuffle / sample / choices（含权重）
    3) 字符集常量：抽密码
    4) 失败示例

]=]

local rt = require("rt")
local log = require("log")
local random = require("random")

local function join(t)
    local s = ""
    for i = 1, #t do
        if i > 1 then
            s = s .. ","
        end
        s = s .. tostring(t[i])
    end
    return s
end

log.info("---- random / randint / uniform / randrange ----")
log.info("random() %s %s", random.random(), random.random())
log.info("randint 1..6  %s %s %s", random.randint(1, 6), random.randint(1, 6), random.randint(6, 1))
log.info("uniform 1.5..3.5  %s", random.uniform(1.5, 3.5))
log.info("randrange 0,10 %s  0,10,2 %s  10,0,-3 %s",
         random.randrange(0, 10), random.randrange(0, 10, 2), random.randrange(10, 0, -3))

log.info("---- choice ----")
log.info("choice table %s", random.choice({ "red", "green", "blue" }))
log.info("choice string %s", random.choice("ABCDE"))

log.info("---- shuffle ----")
local cards = { 1, 2, 3, 4, 5, 6, 7, 8 }
log.info("before %s", join(cards))
random.shuffle(cards)
log.info("after  %s", join(cards))

log.info("---- sample ----")
log.info("sample table k=3 %s", join(random.sample({ 10, 20, 30, 40, 50 }, 3)))
log.info("sample string k=4 %s", random.sample(random.ascii_lowercase, 4))

log.info("---- choices ----")
log.info("choices table k=5 %s", join(random.choices({ "A", "B", "C" }, 5)))
log.info("choices weights C 偏多 %s", join(random.choices({ "A", "B", "C" }, { 1, 1, 8 }, 8)))
log.info("choices string k=6 %s", random.choices(random.digits, 6))

log.info("---- charset / password ----")
log.info("letters=%s digits=%s hex=%s", random.ascii_letters, random.digits, random.hexdigits)
local pool = random.ascii_letters .. random.digits
log.info("pwd8 %s", random.sample(pool, 8))
log.info("token %s", random.choices(random.hexdigits, 16))

log.info("---- fail ----")
local v, err = random.sample({ 1, 2 }, 5)
log.info("sample overflow v=%s err=%s", tostring(v), tostring(err))
v, err = random.randrange(5, 5)
log.info("empty range v=%s err=%s", tostring(v), tostring(err))
v, err = random.choice("")
log.info("choice empty v=%s err=%s", tostring(v), tostring(err))

log.info("random demo done")

while true do
    rt.delay(10000)
end

--[=[
  random demo — TRNG 随机数

  require("random")。底层 hal_trng_gen。失败返回 nil, err。
  不依赖网络 / 外设。

  ----------------------------------------------------------------------------
  random.random() -> number | nil, err          [0.0, 1.0)
  random.randint(a, b) -> integer | nil, err    [min(a,b), max(a,b)]
  random.uniform(a, b) -> number | nil, err     [a, b]
  random.randrange(start, stop[, step]) -> integer | nil, err
      半开区间，step 默认 1，不可为 0；空区间失败
  ----------------------------------------------------------------------------
  random.choice(seq) -> value | nil, err
      seq=table 返回元素；seq=string 返回 1 个字符
  random.shuffle(t) -> t | nil, err
      原地洗牌，返回同一张表
  random.sample(pop, k) -> table|string | nil, err
      不放回。table 返回表，string 返回长度为 k 的串；k 不能大于总体
  random.choices(pop [, weights] [, k]) -> table|string | nil, err
      可放回。choices(pop, k) 或 choices(pop, weights, k)；k 默认 1
      weights 与 pop 等长、非负，总和 > 0
  ----------------------------------------------------------------------------
  字符集常量（string）
    ascii_lowercase / ascii_uppercase / ascii_letters
    digits / octdigits / hexdigits / punctuation / whitespace / printable

  ============================================================================
  本 demo
  ============================================================================
    数值接口各抽几次；choice/shuffle/sample/choices 覆盖 table 和 string；
    用字符集拼一串密码；最后打三条失败路径。

]=]
