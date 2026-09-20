# 短信告警

短信相关场景工程。当前这一份是 **转发到钉钉 / 飞书 / Bark**，不是 `rtu_config` 里的通道透传。必须用手机卡。

| 工程 | 说明 |
| --- | --- |
| [sms_forward](sms_forward) | 收到短信后推到钉钉 / 飞书 / Bark 等，配置只改 `config.lua` |

收发接口对照 [sms_api](../../network/sms/sms_api)。
