#!/usr/bin/python3
"""A stand-in for the PIN verifier that says "ok" to everything and logs each
request line to /tmp/fake-verifier.log. If a PAM service other than the
lock and login screens reaches it, the log shows it."""
import os
import socket

path = "/run/atlasos/pin.sock"
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    os.unlink(path)
except FileNotFoundError:
    pass
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
os.chmod(path, 0o666)
srv.listen(8)
while True:
    conn, _ = srv.accept()
    with conn:
        data = conn.recv(256)
        with open("/tmp/fake-verifier.log", "a") as log:
            log.write(data.decode(errors="replace").split(" ")[0].strip() + "\n")
        conn.sendall(b"ok\n")
