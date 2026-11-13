# AGPIO 休眠供电功耗对比

需要包含 `lp.io_hold()`、`lp.agpio_sleep_power()` 和 RTU 模块总开关的新版固件。

配套配置通过 `[mqtt] enable=0`、`[sock] enable=0`、`[task] enable=0` 关闭整组 RTU 业务。
下次启动会删除 `/rtu_mqtt_cfg.bin`、`/rtu_sock_cfg`、`/rtu_task_cfg.bin`，跳过相应初始化；Task 心跳线程也不会创建。
总开关关闭期间，AT/Lua 对这些 RTU 模块的配置读写会返回禁用错误，不会重新生成文件。
保留 `/rtu_config.cfg` 中的总开关才能在以后每次启动继续禁用；恢复时写 `enable=1`，补回所需通道配置并重启，已删除的参数不会自动恢复。

## 两个开关

```lua
lp.io_hold(false)            -- 停止自动 AGPIO 输出钉住及 AON latch
lp.agpio_sleep_power(false)  -- 进睡回调最后关闭 AGPIO LDO

lp.agpio_sleep_power(true)   -- 后续休眠恢复 AGPIO 供电策略
lp.io_hold(true)             -- 恢复自动输出保持/锁存
```

不传参数或传 `nil` 查询当前策略；写入接受 boolean 或整数 0/1，返回设置后的 boolean。
两项默认都是 `true`，均为本次开机的全局策略，不写 Flash。

`agpio_sleep_power(false)` 不在 Lua 调用当场断电，只在真正进入 Sleep1/Sleep2/Hibernate 的准备阶段最后断电。即使 `io_hold=true`，断电策略仍优先，AGPIO 不会保持原输出电平。Sleep1 唤醒和任何档位入睡失败时，底层在业务线程恢复前重新上电、撤销本次 PAD 改动；成功进入 Sleep2/Hibernate 后走正常开机初始化，两个策略恢复默认，脚本需再次设置。

关闭自动保持只停用 AGPIO 输出保持/latch 和 NET 灯的 `sleep_keep` 写入；Sleep1 数字 GPIO 的方向、电平、中断备份恢复，以及软 I2C 的休眠释放/恢复仍保留。

## 测试步骤

1. 此配置面向没有外置看门狗、AGPIO 不承担必需外设供电/使能的测试板。断电影响整组 AGPIO；APWM 和复用 AGPIO 的唤醒脚需另外验证。唤醒检测和 RTC 不作为本例的关断目标。
2. 备份设备原 `/rtu_config.cfg` 及所需业务参数。下载本工程，选择配套 `rtu_config.conf`。它关闭外置喂狗、NET 灯、整组 RTU 网络业务及复位监控，并删除 MQTT、Socket、Task 的本地配置；结束后需重新写入原配置和业务参数。这部分配置不会被脚本自动还原。
3. 使用独立板级电源测电流。开头留出 15 秒拔掉 USB/VBUS。串口接收日志需避免调试器通过信号线反向供电。
4. `main.lua` 默认 `TEST_CASE=0`，自动执行下表，每组 120 秒。改成 1、2、3 可只测对应一组；`WINDOW_MS` 可延长测量窗口。

| 组 | 自动保持/锁存 | AGPIO 休眠供电 | 比较目的 |
| --- | --- | --- | --- |
| A | 开 | 开 | 基线 |
| B | 关 | 开 | 比较保持/锁存路径的影响 |
| C | 关 | 关 | 比较关闭 AGPIO LDO 的额外收益 |

脚本窗口内不打印唤醒日志，仅开头和结尾各打印一次。电源表记录打印结束、系统稳定后的底电流，忽略切组/唤醒的尖峰。结尾输出 `last_slp`、`sleep_ms` 和唤醒计数；`last_slp` 是上次实际成功进入的深度，`sleep_ms` 可能是上次成功睡眠的数据，不能仅凭设定模式认定已经睡成。

**本例使用 `MODE_LOW_POWER_2`，当前 SDK 映射为 `CFUN=0 + Sleep1`，不是硬件 Sleep2。** 因为 RAM 保持，三个窗口可以在同一次脚本执行中比较。真正 Sleep2/Hibernate 成功后会重启脚本，应使用固定单组策略、深睡定时器或独立唤醒脚另行测试。

全部完成或脚本报错时，恢复启动本例前的两个策略及目标模式，然后无限让出。若原模式为 `MODE_NORMAL`，结束后会恢复常电/网络，这是预期行为。

API 详见 [lp 文档](../../../../../docs/dolua-api/nt26/api/module/lp.md#7-23-io-hold)。
