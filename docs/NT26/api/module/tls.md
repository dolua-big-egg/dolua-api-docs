# tls

**文档版本** `1.0.1`

纯函数密码学工具：摘要、HMAC、Base64、CRC、对称加解密，以及 OneNET MQTT 口令。**没有对象、没有 TLS 握手、不建加密套接字。** MQTT/HTTPS 的传输层加密不在本模块。

```lua
local tls = require("tls")
```

平台预加载模块，无需额外 `.lua` 文件。

业务失败返回 `nil, err`（CRC 除外，它返回整数）。缺参、类型明显不对时会 **抛错**。

名字虽是 `tls`，不要当成 `ssl.connect`。连 OneNET 请优先用 [`mqtt`](../network/mqtt.md) 的 `platform("onenet")`；本模块的 `onenet` 只在你要自己拿 token 时用。

---

## 目录

- [1. 模块定位](#1-模块定位)
- [2. 框架结构](#2-框架结构)
- [3. 阻塞语义](#3-阻塞语义)
- [4. 常量与枚举](#4-常量与枚举)
- [5. 类型约定](#5-类型约定)
- [6. 模块函数](#6-模块函数)
  - [6.1 `tls.features`](#6-1-features)
  - [6.2 `tls.md5` / `sha1` / `sha256` / `sha512`](#6-2-md5)
  - [6.3 `tls.hash`](#6-3-hash)
  - [6.4 `tls.hmac_md5` / `hmac_sha1` / `hmac_sha256` / `hmac_sha512`](#6-4-hmac-md5)
  - [6.5 `tls.hmac`](#6-5-hmac)
  - [6.6 `tls.base64_encode`](#6-6-base64-encode)
  - [6.7 `tls.base64_decode`](#6-7-base64-decode)
  - [6.8 `tls.onenet`](#6-8-onenet)
  - [6.9 `tls.encrypt`](#6-9-encrypt)
  - [6.10 `tls.decrypt`](#6-10-decrypt)
  - [6.11 `tls.crc8`](#6-11-crc8)
  - [6.12 `tls.crc16`](#6-12-crc16)
  - [6.13 `tls.crc32`](#6-13-crc32)
- [7. `features` 表](#7-features-表)
- [8. 摘要输出：hex 还是二进制](#8-摘要输出hex-还是二进制)
- [9. 对称加解密](#9-对称加解密)
- [10. 错误与返回约定](#10-错误与返回约定)
- [11. 资源上限与生命周期](#11-资源上限与生命周期)
- [12. 选型对照](#12-选型对照)
- [13. 完整示例](#13-完整示例)
- [修订记录](#修订记录)

---

## 1. 模块定位

| 需求 | 函数 |
| --- | --- |
| 看本机构建开了哪些算法 | `features()` |
| MD5 / SHA | `md5` / `sha1` / `sha256` / `sha512` 或 `hash` |
| HMAC | `hmac_*` 或 `hmac` |
| Base64 | `base64_encode` / `base64_decode` |
| CRC-8/16/32 | `crc8` / `crc16` / `crc32` |
| AES / DES / 3DES / RC4 | `encrypt` / `decrypt` |
| OneNET token | `onenet` |

入参里的 key、明文、IV 都是 **二进制 string**（可含 `0x00`），不是 hex 文本。摘要默认打成小写 hex；加解密结果始终是二进制。

开机先 `features()`。表里为 `false` 的算法调用会失败（文案常带 `not enabled`）。

---

## 2. 框架结构

```
┌─────────────────────────────────────────────────────────┐
│  Lua 脚本                                                │
│  hash / hmac / base64 / crc / encrypt / decrypt          │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│  tls 模块                                                │
│  · 当场算完再返回，无实例、无回调                         │
│  · 算法能否用看本机构建（features）                       │
└─────────────────────────────────────────────────────────┘
```

| 路径 | 当场做什么 | 是否让出协程 |
| --- | --- | --- |
| 各接口 | CPU 上算完整段 | **否**（大包会占住调度） |

---

## 3. 阻塞语义

全部同步。短串可在回调里用；数 KB 以上的 `encrypt` / `sha512` 不要放在 UART / MQTT 短回调里。

没有后台任务。

---

## 4. 常量与枚举

模块表 **没有** 整数枚举常量。算法、模式、填充都写 **字符串**：

| 字符串 | 用在 |
| --- | --- |
| `"MD5"` `"SHA1"` `"SHA256"` `"SHA512"` | `hash` / `hmac` 的 `alg`（须大写，与快捷函数一致） |
| `"aes"` `"des"` `"3des"` `"tdea"` `"triple_des"` `"rc4"` `"arc4"` | `encrypt` / `decrypt` 的 `alg` |
| `"ecb"` `"cbc"` `"stream"` | `mode`；RC4 只能 `"stream"` |
| `"pkcs7"` `"none"` | 填充 |

`features` 里的 `blowfish` / `rc5` / `idea` / `rabbit` / `escape` **不是** `encrypt` 可用算法（后四项恒为 `false`）。

---

## 5. 类型约定

| 名称 | 实际类型 | 说明 |
| --- | --- | --- |
| `data` / `key` / `iv` | string | 二进制；空串合法（视接口） |
| `alg` / `mode` / `padding` | string | 见第 4、9 节 |
| `raw` | boolean | 摘要是否返回二进制，见第 8 节 |
| `init` / `poly` / `xorout` | integer | CRC 参数 |
| `refin` / `refout` | boolean | CRC 按位反射 |

`raw`、`refin`、`refout` 走 **真假语义**：`false`/`nil` 为假，**数字 `0` 为真**。请写 `true`/`false`，不要传 `0`/`1`。省略或 `nil` 用该参数的默认值。

---

## 6. 模块函数

---

### 6.1 `tls.features()` {#6-1-features}

**调用模式**

```lua
tls.features()
```

返回一张 boolean 表，字段见 [第 7 节](#7-features-表)。无失败路径。

```lua
local f = tls.features()
if f.aes then
    -- 再 encrypt
end
```

---

### 6.2 `tls.md5` / `sha1` / `sha256` / `sha512` {#6-2-md5}

四个快捷摘要，形态相同。

**调用模式**

```lua
tls.md5(data)
tls.md5(data, raw)
tls.sha1(data)
tls.sha1(data, raw)
tls.sha256(data)
tls.sha256(data, raw)
tls.sha512(data)
tls.sha512(data, raw)
```

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `data` | 是 |  | string |
| `raw` | 否 | 假 → 小写 hex | `true` 为二进制摘要 |

成功：string。失败：`nil, err`（该算法未编进固件等）。

输出长度（`raw=true`）：MD5 16、SHA1 20、SHA256 32、SHA512 64 字节。hex 则是两倍字符。

```lua
tls.md5("hello tls")           -- hex
tls.md5("hello tls", true)     -- 16 字节二进制
```

---

### 6.3 `tls.hash(alg, data[, raw])` {#6-3-hash}

按名字选摘要。快捷函数覆盖的四种写成 `"MD5"` / `"SHA1"` / `"SHA256"` / `"SHA512"`。

**调用模式**

```lua
tls.hash(alg, data)
tls.hash(alg, data, raw)
```

未知或未启用的 `alg`：`nil, "hash algorithm not supported or not enabled"`。

```lua
tls.hash("SHA256", "hello tls")
```

---

### 6.4 `tls.hmac_md5` / `hmac_sha1` / `hmac_sha256` / `hmac_sha512` {#6-4-hmac-md5}

四个快捷 HMAC，形态相同。

**调用模式**

```lua
tls.hmac_md5(key, data)
tls.hmac_md5(key, data, raw)
tls.hmac_sha1(key, data)
tls.hmac_sha1(key, data, raw)
tls.hmac_sha256(key, data)
tls.hmac_sha256(key, data, raw)
tls.hmac_sha512(key, data)
tls.hmac_sha512(key, data, raw)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `key` | 是 | string |
| `data` | 是 | string |
| `raw` | 否 | 同摘要 |

```lua
tls.hmac_sha1("key", "hello tls")
tls.hmac_sha256("key", "hello tls", true)
```

---

### 6.5 `tls.hmac(alg, key, data[, raw])` {#6-5-hmac}

**调用模式**

```lua
tls.hmac(alg, key, data)
tls.hmac(alg, key, data, raw)
```

`alg` 规则同 `hash`。失败常见 `hmac algorithm not supported or not enabled`。

```lua
tls.hmac("SHA1", "key", "hello tls")
```

---

### 6.6 `tls.base64_encode(data)` {#6-6-base64-encode}

**调用模式**

```lua
tls.base64_encode(data)
```

成功：ASCII Base64 string。失败：`nil, err`（未启用时 `base64 is not enabled in mbedtls`）。

---

### 6.7 `tls.base64_decode(b64)` {#6-7-base64-decode}

**调用模式**

```lua
tls.base64_decode(b64)
```

成功：二进制 string。非法字符：`nil, err`（文案含 `base64_decode failed`）。

与 [`hex`](hex.md) 不同：这里失败有第二返回值。

---

### 6.8 `tls.onenet(product_name, base64_key)` {#6-8-onenet}

按中国移动 OneNET 规则生成 MQTT password token（version=2018-10-31、method=sha1）。过期时间为本机 UTC 再加约一年。

**调用模式**

```lua
tls.onenet(product_name, base64_key)
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `product_name` | 是 | 产品 ID / 产品名 |
| `base64_key` | 是 | access key 的 Base64 |

成功：token 字符串。失败：`nil, "onenet password generation failed"` 或 Base64 未启用。

时钟未授时则 `et` 会偏。日常连云用 [`mqtt`](../network/mqtt.md) `platform("onenet")`，不必自己调本函数。

```lua
local token, err = tls.onenet("demoProduct", "MTIzNDU2Nzg5MGFiY2RlZg==")
```

---

### 6.9 `tls.encrypt(alg, mode, key, data[, iv[, padding]])` {#6-9-encrypt}

对称加密，结果 **二进制**。算法表见 [第 9 节](#9-对称加解密)。

**调用模式**

```lua
tls.encrypt(alg, mode, key, data)
tls.encrypt(alg, mode, key, data, iv)
tls.encrypt(alg, mode, key, data, iv, padding)
tls.encrypt(alg, mode, key, data, nil, padding)
```

最后一种给 ECB / 流密码指定填充：第 5 参必须是 `nil`（ECB 禁止非空 IV）。

| 参数 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `alg` | 是 |  | `"aes"` / `"des"` / `"3des"` 等 |
| `mode` | 是 |  | `"ecb"` / `"cbc"` / `"stream"` |
| `key` | 是 |  | 二进制，长度见第 9 节 |
| `data` | 是 |  | 明文 |
| `iv` | CBC 必填 | `""` | 长度等于块长 |
| `padding` | 否 | 块密码 `"pkcs7"`；流密码 `"none"` | |

成功：密文字符串。失败：`nil, err`。key/data 不是 string：`arg #3 key must be string` / `arg #4 data must be string (check previous call result)`（常因上一步 `encrypt` 失败却把 `nil` 拿去 `decrypt`）。

```lua
local enc, err = tls.encrypt("aes", "cbc", key16, "hello tls", iv16)
local enc2, err2 = tls.encrypt("aes", "ecb", key16, blk, nil, "none")
```

---

### 6.10 `tls.decrypt(alg, mode, key, data[, iv[, padding]])` {#6-10-decrypt}

参数与调用模式与 `encrypt` **完全相同**。PKCS7 解密成功后会去掉填充，得到原文。

```lua
tls.decrypt(alg, mode, key, data)
tls.decrypt(alg, mode, key, data, iv)
tls.decrypt(alg, mode, key, data, iv, padding)
tls.decrypt(alg, mode, key, data, nil, padding)
```

填充损坏：`nil, "invalid pkcs7 padding"`。

---

### 6.11 `tls.crc8(data[, init[, poly[, xorout[, refin[, refout]]]]])` {#6-11-crc8}

默认 CRC-8：`init=0x00`，`poly=0x07`，`xorout=0x00`，`refin/refout=false`。

**调用模式**（省略的参数保持默认；中间想跳过请传 `nil`）

```lua
tls.crc8(data)
tls.crc8(data, init)
tls.crc8(data, init, poly)
tls.crc8(data, init, poly, xorout)
tls.crc8(data, init, poly, xorout, refin)
tls.crc8(data, init, poly, xorout, refin, refout)
```

成功：整数（8 位宽结果）。`refin`/`refout` 必须是 boolean，不要传 `0`/`1`。

与 [`lfs`](lfs.md) 区间 CRC-8 默认算法同类。

```lua
tls.crc8("123456789")
tls.crc8("123456789", 0xFF)
```

---

### 6.12 `tls.crc16(...)` {#6-12-crc16}

调用模式与 `crc8` 相同。

默认 CRC-16/IBM：`init=0`，`poly=0x8005`，`xorout=0`，`refin/refout=true`。

```lua
tls.crc16(data)
tls.crc16(data, init)
tls.crc16(data, init, poly)
tls.crc16(data, init, poly, xorout)
tls.crc16(data, init, poly, xorout, refin)
tls.crc16(data, init, poly, xorout, refin, refout)
```

Modbus 小端 CRC 请用 [`modbus.crc`](modbus.md) / [`framekit`](framekit.md)，不要拿本默认 IBM 去当 Modbus。

```lua
tls.crc16("123456789", 0, 0x8005, 0xFFFF, true, true)  -- MAXIM 一类
```

---

### 6.13 `tls.crc32(...)` {#6-13-crc32}

调用模式与 `crc8` 相同。

默认 CRC-32/IEEE（ZIP / 以太网）：`init=0xFFFFFFFF`，`poly=0x04C11DB7`，`xorout=0xFFFFFFFF`，`refin/refout=true`。与 [`lfs`](lfs.md) 的 crc32 默认一致。

```lua
tls.crc32(data)
tls.crc32(data, init)
tls.crc32(data, init, poly)
tls.crc32(data, init, poly, xorout)
tls.crc32(data, init, poly, xorout, refin)
tls.crc32(data, init, poly, xorout, refin, refout)
```

```lua
tls.crc32("123456789", 0xFFFFFFFF, 0x04C11DB7, 0, false, false)  -- MPEG-2 一类
```

---

## 7. `features` 表

| 键 | 含义 |
| --- | --- |
| `md5` / `sha1` / `sha256` / `sha512` | 对应摘要与 HMAC 是否可用 |
| `base64` | Base64 与 `onenet` |
| `aes` / `des` / `rc4` | 能否走对应 `encrypt` |
| `crc8` / `crc16` / `crc32` | 恒 `true` |
| `blowfish` | 仅反映编译开关；**本模块 encrypt 不支持 blowfish** |
| `rc5` / `idea` / `rabbit` / `escape` | 恒 `false`，没有对应接口 |

当前量产构建通常开 MD5/SHA1/SHA256/SHA512、Base64、AES、DES；RC4 可能未开，以设备上 `features()` 为准。

---

## 8. 摘要输出：hex 还是二进制

| `raw` | 结果 |
| --- | --- |
| 省略 / `false` / `nil` | 小写 hex，无空格、无 `0x` |
| `true` | 二进制 string |

**不要** `md5(s, 0)` 指望 hex：数字 `0` 当真，会走二进制。

加解密 **没有** hex 开关，要打印用 [`hex.bytes2hex`](hex.md) 或自己 `gsub`。

---

## 9. 对称加解密

| `alg` | `mode` | key 字节数 | IV | 块长 |
| --- | --- | --- | --- | --- |
| `"aes"` | `"ecb"` / `"cbc"` | 16 / 24 / 32 | CBC 必须 16；ECB 必须空 | 16 |
| `"des"` | `"ecb"` / `"cbc"` | 8 | CBC 必须 8；ECB 必须空 | 8 |
| `"3des"` / `"tdea"` / `"triple_des"` | `"ecb"` / `"cbc"` | 16（双 DES）或 24（三 DES） | 同 DES | 8 |
| `"rc4"` / `"arc4"` | `"stream"` | 1～256 | 禁止带 IV | 流 |

不匹配：`unsupported algorithm/mode/key length`。

CBC IV 长度不对：`cbc iv length mismatch`。ECB 却传了 IV：`ecb mode does not use iv`。RC4 带 IV：`rc4 does not use iv`。

填充：

| `padding` | 加密 | 解密 |
| --- | --- | --- |
| `"pkcs7"`（块密码默认） | 补齐到整块（恰好整块再补一整块） | 校验并去掉 |
| `"none"` | 明文必须已整块对齐 | 密文必须整块 |
| 流密码 | 只能 `"none"`（默认） | 同左 |

未对齐还用 `"none"`：`data length must align to block size`。

未编进固件：`aes is not enabled in mbedtls` / `rc4 is not enabled in mbedtls` / `cipher is not enabled in mbedtls` 等。

---

## 10. 错误与返回约定

| 接口 | 成功 | 失败 |
| --- | --- | --- |
| `features` | table | — |
| `crc8` / `crc16` / `crc32` | integer | 缺参 **抛** |
| 其余 | string | `nil, err`；类型错 **抛** |

常见 `err`：

- `hash algorithm not supported or not enabled`
- `padding must be 'pkcs7' or 'none'`
- `invalid pkcs7 padding`
- `base64_decode failed (ret=…)`
- `onenet password generation failed`

---

## 11. 资源上限与生命周期

无对象、无槽位。临时缓冲随调用结束释放。

`onenet` 内部缓冲区约产品名、key、token 各一两百字节量级，过长会失败。

CRC `width` 固定为 8/16/32，不能自选宽度。

---

## 12. 选型对照

| 需求 | 做法 |
| --- | --- |
| 打摘要、HMAC、Base64 | 本模块 |
| 打印二进制 | [`hex`](hex.md) |
| Modbus CRC | [`modbus.crc`](modbus.md) |
| OneNET 连云 | [`mqtt`](../network/mqtt.md) `platform("onenet")` |
| TLS 套接字 / 证书 | **没有**。MQTT/HTTP 的加密通道在对应模块 |

demo：[examples/NT26/module/tls/tls_api](../../../../examples/NT26/module/tls/tls_api)。

---

## 13. 完整示例

```lua
local tls = require("tls")
local log = require("log")

local f = tls.features()
local text = "hello tls"
local key16 = "1234567890123456"
local iv16 = "abcdef1234567890"

log.info("md5 %s", tls.md5(text))
log.info("hmac %s", tls.hmac_sha1("key", text))

local b64 = tls.base64_encode(text)
log.info("b64 %s roundtrip=%s", b64, tls.base64_decode(b64) == text)

log.info("crc32=0x%08X", tls.crc32("123456789"))

if f.aes then
    local enc, err = tls.encrypt("aes", "cbc", key16, text, iv16)
    if enc then
        local dec = tls.decrypt("aes", "cbc", key16, enc, iv16)
        log.info("aes match=%s", dec == text)
    else
        log.error("%s", err)
    end
end
```

---

## 修订记录

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.0.0 | 2026-09-04 | 首版 |
| 1.0.1 | 2026-09-04 | 修正跨目录文档链接，demo 路径改为 examples/ |
