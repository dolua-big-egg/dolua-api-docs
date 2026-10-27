"""电脑上的简易 TLS 客户端，用来确认服务器通不通。不要烧进设备。

用法：
  python pc_tls_client.py                 不校验证书，连脚本里写的地址
  python pc_tls_client.py --auth 1        用系统信任库做单向认证
  python pc_tls_client.py --host 1.2.3.4 --port 443 --send "hello\r\n"
"""

import argparse
import socket
import ssl
import sys

DEFAULT_HOST = "115.120.239.161"
DEFAULT_PORT = 22882


def main():
    parser = argparse.ArgumentParser(description="简易 TLS socket 客户端")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--auth", type=int, choices=(0, 1), default=0,
                        help="0 不校验证书，1 用系统 CA 做单向认证")
    parser.add_argument("--sni", default="",
                        help="SNI / 校验证书用的主机名。省略时用 --host")
    parser.add_argument("--ca", default="",
                        help="额外信任的 CA 文件（PEM）。--auth 1 时才会用")
    parser.add_argument("--send", default="hello tls\r\n",
                        help="握手成功后发出的字节。空字符串表示只握手")
    parser.add_argument("--timeout", type=float, default=8)
    args = parser.parse_args()

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    if args.auth == 0:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    else:
        ctx.check_hostname = True
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.load_default_certs()
        if args.ca:
            ctx.load_verify_locations(args.ca)

    sni = args.sni or args.host
    print("connect %s:%d auth=%d sni=%s" % (args.host, args.port, args.auth, sni))

    raw = socket.create_connection((args.host, args.port), timeout=args.timeout)
    try:
        ssock = ctx.wrap_socket(raw, server_hostname=sni)
    except ssl.SSLError as exc:
        print("handshake fail: %s" % exc)
        raw.close()
        return 1
    except Exception as exc:
        print("handshake fail: %s" % exc)
        raw.close()
        return 1

    try:
        print("handshake ok cipher=%s version=%s" % (ssock.cipher(), ssock.version()))
        cert = ssock.getpeercert()
        if cert:
            print("peer subject=%s" % (cert.get("subject"),))
        elif args.auth == 0:
            der = ssock.getpeercert(binary_form=True)
            print("peer cert bytes=%s (未校验，不解析主题)" % (len(der) if der else 0))
        if args.send:
            ssock.sendall(args.send.encode("utf-8"))
            print("sent %d bytes" % len(args.send.encode("utf-8")))
        ssock.settimeout(args.timeout)
        chunks = []
        while True:
            try:
                data = ssock.recv(4096)
            except socket.timeout:
                break
            if not data:
                break
            chunks.append(data)
            if sum(len(c) for c in chunks) >= 8192:
                break
        body = b"".join(chunks)
        print("recv %d bytes" % len(body))
        if body:
            text = body.decode("utf-8", errors="replace")
            if len(text) > 800:
                text = text[:800] + "..."
            print(text)
        return 0
    finally:
        ssock.close()


if __name__ == "__main__":
    sys.exit(main())
