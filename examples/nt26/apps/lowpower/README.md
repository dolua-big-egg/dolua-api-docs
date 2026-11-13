# 低功耗

投票休眠、cron 唤醒、驻网后再干活。日常等待用 `rt.delay`，不要用 `sys.delay_ms` 堵整台引擎。

对照 [lowpower_vote](../../module/lp/lowpower_vote)、[lowpower_cron](../../module/lp/lowpower_cron)。

[AGPIO 休眠供电功耗对比](agpio_power_compare) 提供自动保持、取消保持、休眠断电三组对比，并演示恢复原策略。
