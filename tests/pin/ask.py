#!/usr/bin/python3
"""ask.py [--raw] LINE: send one request to the verifier socket as the current
user and print its one-line answer ("(none)" when it gave none). With --raw
the line is sent as it is, with no newline added."""
import socket
import sys

raw = sys.argv[1] == "--raw"
line = sys.argv[2 if raw else 1].encode()
if not raw:
    line += b"\n"
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(8)
s.connect("/run/atlasos/pin.sock")
try:
    s.sendall(line)
except BrokenPipeError:
    pass
s.shutdown(socket.SHUT_WR)
data = b""
try:
    while len(data) < 256:
        chunk = s.recv(256)
        if not chunk:
            break
        data += chunk
except ConnectionResetError:
    pass
print(data.decode().strip() or "(none)")
