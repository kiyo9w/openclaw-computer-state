#!/usr/bin/env python3
import socket
import sys
import os


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 17891
    timeout = float(os.environ.get("MACCONTROL_SOCKET_TIMEOUT", "30"))
    payload = sys.stdin.buffer.read()
    with socket.create_connection(("127.0.0.1", port), timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    sys.stdout.write(b"".join(chunks).decode("utf-8", errors="replace"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
