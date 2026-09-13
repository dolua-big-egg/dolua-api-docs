--[=[
  log demo — log.info / log.warn / log.error
  ============================================================================
  本 demo
  ============================================================================
    演示 info/warn/error 纯文本，以及 printf 式 format（含 bool 用 %s）。

]=]

local rt = require("rt")
local log = require("log")

log.info("this is log info")
log.warn("this is log warning")
log.error("this is log error")

-- log 集成了 format，用法同 printf：首参是格式串，后面是参数
-- boolean / nil 请用 %s（Lua string.format 没有 %b）
log.info("string %s, number %d, boolean %s, float %f", "hello world", 123, true,
         3.1415926)

while true do 
     rt.delay(1000) 
end

--[=[
  log demo — log.info / log.warn / log.error

  ============================================================================
  log 是什么
  ============================================================================
  log 是本平台提供的 Lua 扩展模块，用于带级别、带调用点的调试输出。
  需 require("log")，输出走模块 UART 串口（与 print 独立路由）。

      local log = require("log")
      log.info("hello")
      log.warn("low battery")
      log.error("open fail")

  ============================================================================
  接口与特性
  ============================================================================
  1) 三个级别
       log.info / log.warn / log.error，用法相同，仅级别不同

  2) printf 格式
       单参：原样输出
       多参：首参是 format，后面是参数（内部 string.format）
       例：log.info("count=%d name=%s", 3, "ec7xx")
           → count=3 name=ec7xx

  3) 占位符
       %s  字符串；boolean / nil 也用 %s（会打成 true/false/nil）
       %d  整数
       %f  浮点
       %%  字面百分号
       没有 %b；table 等其它类型会 tostring

  4) 自动附带调用点
       每条日志带函数名、源文件、行号，格式：
       [Lua][INFO][func][src:line] message

  5) 安全、无返回值
       format 失败打印 "format error: ..."，不向脚本抛错
       仅作输出，无返回值

  6) 行结束符
       \r\n（CRLF）

  ============================================================================
  本平台输出路由（默认 UART1）
  ============================================================================
  log 直出指定串口，不受 AT+LOG 输出口切换影响，也与 print 互相独立。

    默认串口 : UART1（log_route = 1）
    可选串口 : UART1 / UART2 / UART3（取值 1 / 2 / 3）

  ============================================================================
  修改输出串口
  ============================================================================

  【方式 1】rtu.config 配置文件（推荐，持久生效）
    写入 /rtu.config 的 [lua] 段，脚本启动前自动 apply：

      [lua]
      print_route=uart1    -- Lua print()：uart1/uart2/uart3/usb_at
      log_route=uart1      -- log 模块，与 print 独立

  【方式 2】Lua 运行时动态切换
    需 require("sys")，立即生效，重启后恢复为配置文件值：

      local sys = require("sys")
      sys.option("log_route", "uart2")         -- 切到 UART2
      sys.option("log_route", "usb_at")        -- 切到 USB AT
      local route = sys.option("log_route")  -- 读取当前路由名

  ============================================================================
  与 print 的区别（简要）
  ============================================================================
    print          内置、轻量、多参 \t 拼接、无源码位置、无 format
    log.info 等    扩展模块、printf 式 format、带文件名行号、可独立路由

  ============================================================================
  本 demo
  ============================================================================
    演示 info/warn/error 纯文本，以及 printf 式 format（含 bool 用 %s）。

]=]
