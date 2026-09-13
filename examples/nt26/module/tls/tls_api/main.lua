--[=[
  tls demo — hash / hmac / base64 / crc / 对称加解密
  ============================================================================
  本 demo
  ============================================================================
    按 features 打印能力，再顺序跑：hash、hmac、base64、crc、
    AES/DES/RC4 加解密往返、onenet、几条失败路径。
    二进制结果用 tohex 打日志，不另包一层 tls 封装。

]=]

local rt = require("rt")
local log = require("log")
local tls = require("tls")

-- 只给 log 看二进制；tls 接口本身直接调用
local function tohex(s)
    if type(s) ~= "string" then
        return tostring(s)
    end
    return (s:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

local TEXT = "hello tls"
local KEY16 = "1234567890123456"
local KEY24 = "123456789012345678901234"
local KEY32 = "12345678901234567890123456789012"
local IV16 = "abcdef1234567890"
local IV8 = "12345678"
local KEY8 = "12345678"

log.info("---- features ----")
local f = tls.features()
log.info("md5=%s sha1=%s sha256=%s sha512=%s", f.md5, f.sha1, f.sha256, f.sha512)
log.info("base64=%s aes=%s des=%s rc4=%s blowfish=%s", f.base64, f.aes, f.des, f.rc4, f.blowfish)
log.info("crc8=%s crc16=%s crc32=%s rc5=%s idea=%s rabbit=%s escape=%s",
         f.crc8, f.crc16, f.crc32, f.rc5, f.idea, f.rabbit, f.escape)

log.info("---- hash (default hex) ----")
log.info("md5 %s", tostring(tls.md5(TEXT)))
log.info("sha1 %s", tostring(tls.sha1(TEXT)))
log.info("sha256 %s", tostring(tls.sha256(TEXT)))
log.info("sha512 %s", tostring(tls.sha512(TEXT)))
log.info("hash SHA256 %s  hash MD5 match shortcut=%s",
         tostring(tls.hash("SHA256", TEXT)), tostring(tls.hash("MD5", TEXT) == tls.md5(TEXT)))

log.info("---- hash raw=true ----")
local raw_md5, raw_err = tls.md5(TEXT, true)
log.info("md5 raw n=%s hex=%s err=%s",
         tostring(type(raw_md5) == "string" and #raw_md5 or "-"), tohex(raw_md5), tostring(raw_err))

log.info("---- hmac ----")
log.info("hmac_md5 %s", tostring(tls.hmac_md5("key", TEXT)))
log.info("hmac_sha1 %s", tostring(tls.hmac_sha1("key", TEXT)))
log.info("hmac_sha256 %s", tostring(tls.hmac_sha256("key", TEXT)))
log.info("hmac_sha512 %s", tostring(tls.hmac_sha512("key", TEXT)))
log.info("hmac SHA1 %s  match shortcut=%s",
         tostring(tls.hmac("SHA1", "key", TEXT)),
         tostring(tls.hmac("SHA1", "key", TEXT) == tls.hmac_sha1("key", TEXT)))
local raw_hmac, hmac_err = tls.hmac_sha256("key", TEXT, true)
log.info("hmac_sha256 raw n=%s hex=%s err=%s",
         tostring(type(raw_hmac) == "string" and #raw_hmac or "-"), tohex(raw_hmac), tostring(hmac_err))

log.info("---- base64 ----")
local b64, b64err = tls.base64_encode(TEXT)
log.info("encode %s err=%s", tostring(b64), tostring(b64err))
local plain, d64err = tls.base64_decode(b64)
log.info("decode %s match=%s err=%s", tostring(plain), tostring(plain == TEXT), tostring(d64err))

log.info("---- crc default (123456789) ----")
log.info("crc8=0x%02X crc16=0x%04X crc32=0x%08X",
         tls.crc8("123456789"), tls.crc16("123456789"), tls.crc32("123456789"))
-- crc8(data [, init, poly, xorout, refin, refout])
log.info("crc8 init=0xFF 0x%02X", tls.crc8("123456789", 0xFF))
log.info("crc16 MAXIM init=0 xorout=0xFFFF refin/refout=true 0x%04X",
         tls.crc16("123456789", 0, 0x8005, 0xFFFF, true, true))
log.info("crc32 MPEG-2 init=0xFFFFFFFF xorout=0 refin/refout=false 0x%08X",
         tls.crc32("123456789", 0xFFFFFFFF, 0x04C11DB7, 0, false, false))

local enc, eerr, dec, derr
if f.aes then
    log.info("---- aes-128-ecb pkcs7 ----")
    enc, eerr = tls.encrypt("aes", "ecb", KEY16, TEXT)
    log.info("enc hex=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("aes", "ecb", KEY16, enc)
    log.info("dec=%s match=%s err=%s", tostring(dec), tostring(dec == TEXT), tostring(derr))

    log.info("---- aes-128-cbc pkcs7 ----")
    enc, eerr = tls.encrypt("aes", "cbc", KEY16, TEXT, IV16)
    log.info("enc hex=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("aes", "cbc", KEY16, enc, IV16)
    log.info("dec=%s match=%s err=%s", tostring(dec), tostring(dec == TEXT), tostring(derr))

    log.info("---- aes-192-cbc / aes-256-cbc pkcs7 ----")
    enc, eerr = tls.encrypt("aes", "cbc", KEY24, TEXT, IV16, "pkcs7")
    log.info("aes192 enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("aes", "cbc", KEY24, enc, IV16, "pkcs7")
    log.info("aes192 match=%s err=%s", tostring(dec == TEXT), tostring(derr))
    enc, eerr = tls.encrypt("aes", "cbc", KEY32, TEXT, IV16)
    log.info("aes256 enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("aes", "cbc", KEY32, enc, IV16)
    log.info("aes256 match=%s err=%s", tostring(dec == TEXT), tostring(derr))

    log.info("---- aes-128-ecb padding=none (16B) ----")
    -- ECB 不要 iv；padding 在第 6 参，第 5 参传 nil
    local blk = "0123456789abcdef"
    enc, eerr = tls.encrypt("aes", "ecb", KEY16, blk, nil, "none")
    log.info("enc hex=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("aes", "ecb", KEY16, enc, nil, "none")
    log.info("dec match=%s err=%s", tostring(dec == blk), tostring(derr))
else
    log.info("aes not enabled, skip")
end

if f.des then
    log.info("---- des-ecb / des-cbc / 3des-cbc ----")
    enc, eerr = tls.encrypt("des", "ecb", KEY8, TEXT)
    log.info("des ecb enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("des", "ecb", KEY8, enc)
    log.info("des ecb match=%s", tostring(dec == TEXT))

    enc, eerr = tls.encrypt("des", "cbc", KEY8, TEXT, IV8)
    log.info("des cbc enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("des", "cbc", KEY8, enc, IV8)
    log.info("des cbc match=%s", tostring(dec == TEXT))

    enc, eerr = tls.encrypt("3des", "cbc", KEY24, TEXT, IV8)
    log.info("3des-24 cbc enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("3des", "cbc", KEY24, enc, IV8)
    log.info("3des-24 cbc match=%s", tostring(dec == TEXT))

    enc, eerr = tls.encrypt("tdea", "ecb", KEY16, TEXT)
    log.info("tdea-16 ecb enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("tdea", "ecb", KEY16, enc)
    log.info("tdea-16 ecb match=%s", tostring(dec == TEXT))
else
    log.info("des not enabled, skip")
end

if f.rc4 then
    log.info("---- rc4 stream ----")
    enc, eerr = tls.encrypt("rc4", "stream", KEY16, TEXT)
    log.info("rc4 enc=%s err=%s", tohex(enc), tostring(eerr))
    dec, derr = tls.decrypt("rc4", "stream", KEY16, enc)
    log.info("rc4 match=%s err=%s", tostring(dec == TEXT), tostring(derr))
else
    log.info("rc4 not enabled, skip")
end

log.info("---- onenet ----")
local token, terr = tls.onenet("demoProduct", "MTIzNDU2Nzg5MGFiY2RlZg==")
log.info("token=%s err=%s", tostring(token), tostring(terr))

log.info("---- fail ----")
local bad, berr = tls.hash("NOTALG", TEXT)
log.info("bad hash v=%s err=%s", tostring(bad), tostring(berr))
bad, berr = tls.encrypt("aes", "cbc", KEY16, TEXT, "short")
log.info("bad iv v=%s err=%s", tostring(bad), tostring(berr))
bad, berr = tls.encrypt("aes", "ecb", KEY16, "unaligned", nil, "none")
log.info("bad none align v=%s err=%s", tostring(bad), tostring(berr))
bad, berr = tls.base64_decode("!!!!")
log.info("bad b64 v=%s err=%s", tostring(bad), tostring(berr))

log.info("tls demo done")
while true do
    rt.delay(10000)
end

--[=[
  tls demo — hash / hmac / base64 / crc / 对称加解密

  require("tls")，底层 mbedtls。失败返回 nil, err。
  摘要默认小写 hex；raw=true 返回二进制。encrypt/decrypt 始终二进制。

  ----------------------------------------------------------------------------
  tls.features() -> table
  ----------------------------------------------------------------------------
    md5/sha1/sha256/sha512/base64/aes/des/rc4/crc8/crc16/crc32 等，值为 boolean

  ----------------------------------------------------------------------------
  tls.md5/sha1/sha256/sha512(data [, raw])
  tls.hash(alg, data [, raw])
  tls.hmac_md5/sha1/sha256/sha512(key, data [, raw])
  tls.hmac(alg, key, data [, raw])
  ----------------------------------------------------------------------------
    alg 如 "MD5" "SHA1" "SHA256" "SHA512"。raw 默认 false=hex。

  ----------------------------------------------------------------------------
  tls.base64_encode(data) / tls.base64_decode(b64) -> string | nil, err
  tls.onenet(product, base64_key) -> token | nil, err
  ----------------------------------------------------------------------------
    onenet 与 OneNET MQTT 密码算法一致，依赖本机 UTC。

  ----------------------------------------------------------------------------
  tls.crc8/crc16/crc32(data [, init, poly, xorout, refin, refout]) -> integer
  ----------------------------------------------------------------------------
    crc8  默认 init=0 poly=0x07 xorout=0 refin/refout=false
    crc16 默认 IBM：init=0 poly=0x8005 xorout=0 refin/refout=true
    crc32 默认 IEEE：init/xorout=0xFFFFFFFF poly=0x04C11DB7 refin/refout=true

  ----------------------------------------------------------------------------
  tls.encrypt/decrypt(alg, mode, key, data [, iv [, padding]]) -> bin | nil, err
  ----------------------------------------------------------------------------
    alg     "aes" / "des" / "3des"("tdea") / "rc4"("arc4")
    mode    "ecb" / "cbc"；rc4 必须 "stream"
    key     二进制串。aes 16/24/32；des 8；3des 16/24；rc4 1..256
    iv      cbc 必须等于块长（aes 16 / des 8）；ecb/rc4 不要带 iv
    padding "pkcs7"（块密码默认）或 "none"（长度须整块；流密码只能 none）

  ============================================================================
  本 demo
  ============================================================================
    features → hash/hmac（含 raw）→ base64 往返 → crc 默认+自定义参数
    → AES-128/192/256、DES/3DES、RC4 加解密 → onenet → 非法 alg/iv/padding/base64。

]=]
