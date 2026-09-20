# 短信

短信相关场景：收发、转发、推送到 IM / 手机，不限于告警。必须用手机卡。

当前可烧录工程是 **转发到钉钉 / 飞书 / Bark**，不是 `rtu_config` 里的通道透传。

| 工程 | 说明 |
| --- | --- |
| [sms_forward](sms_forward) | 收到短信后推到钉钉 / 飞书 / Bark 等，配置只改 `config.lua` |

收发接口对照 [sms_api](../../network/sms/sms_api)。
