# 本地记录

把采样或报文落到 `ufs` / `ublob` / 外挂 FlashDB，稍后回放或上云。配置表用 `ufs`，二进制/日志用 `ublob`，二者与脚本区共用配额。

对照 [ufs_api](../../storage/ufs/ufs_api)、[ublob_api](../../storage/ublob/ublob_api)、[flashdb_kv](../../storage/flashdb_kv)。
