# 低功耗

投票休眠、cron 唤醒、驻网后再干活。日常等待用 `rt.delay`，不要用 `sys.delay_ms` 堵整台引擎。

对照 [lowpower_vote](../../module/lp/lowpower_vote)、[lowpower_cron](../../module/lp/lowpower_cron)。
