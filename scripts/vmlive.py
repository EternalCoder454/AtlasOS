#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pexpect>=4.9"]
# ///
"""Runs steps in a test VM that is logged in to Plasma, over its serial
console, and saves what they print and show. Used for the update tests.

    vmlive.py <domain> <out dir> <step>...

Steps:
    CMD                  a shell command as the test user, in the Plasma session's environment
    sudo CMD             as root (no single quotes in CMD: sudo wraps it in sh -c '...')
    push LOCAL REMOTE    copy a host file into the guest (as the test user)
    shot NAME            screenshot the session to <out dir>/NAME.png
    ui ARGS              scripts/guest/atspi.py ARGS in the session (press buttons by name, dump text)
    sleep SECONDS
    plasma               wait for plasmashell, after a reboot for example
    login                log in again on the console (after a reboot)
    authenticate         type the test password and Enter into the focused window (a polkit prompt)

Output goes to stdout and <out dir>/console.log.
"""

import base64
import pathlib
import subprocess
import sys
import time

import pexpect

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from vmctl import USER, Console, session_screenshot  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SESSION_ENV = (
    "export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 "
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus"
)


def attach(con: Console, password: str) -> None:
    """Reuses a shell an earlier run left logged in, or logs in. Ctrl-C first
    stops a command an interrupted run left running there."""
    # A fresh virsh console prints this once; Ctrl-C before it would stop virsh.
    try:
        con.p.expect("Escape character", timeout=10)
    except pexpect.TIMEOUT:
        pass
    con.p.sendcontrol("c")
    i = 2
    for _ in range(5):
        con.p.send("\r")
        i = con.p.expect([r"login: ?$", r"\$ ?$", pexpect.TIMEOUT], timeout=5)
        if i < 2:
            break
    if i == 0:
        con.login(password, 120)
    else:
        con.run("stty cols 400 rows 1000; export TERM=dumb SYSTEMD_PAGER= SYSTEMD_COLORS=0")
    con.run(SESSION_ENV)


def push(con: Console, local: pathlib.Path, remote: str) -> None:
    data = base64.b64encode(local.read_bytes()).decode()
    con.run(f": > {remote}.b64")
    for i in range(0, len(data), 3000):
        con.run(f"echo {data[i:i + 3000]} >> {remote}.b64")
    con.run(f"base64 -d {remote}.b64 > {remote} && rm {remote}.b64")


def type_keys(domain: str, text: str) -> None:
    """Types letters, digits, '-', '_' and '.' into the VM's keyboard, then Enter."""
    named = {"-": "KEY_MINUS", "_": "KEY_MINUS", ".": "KEY_DOT"}
    for ch in text:
        key = named.get(ch) or f"KEY_{ch.upper()}"
        keys = ["KEY_LEFTSHIFT", key] if ch.isupper() or ch == "_" else [key]
        subprocess.run(["virsh", "send-key", domain, *keys], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["virsh", "send-key", domain, "KEY_ENTER"], check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    domain, out = sys.argv[1], pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    password = (ROOT / "build/vm-password").read_text().strip()
    con = Console(domain, out / "console.log")
    attach(con, password)
    for step in sys.argv[3:]:
        word, _, rest = step.partition(" ")
        if word == "sudo":
            text = con.sudo(rest, password, timeout=1800)
        elif word == "push":
            local, remote = rest.split()
            push(con, pathlib.Path(local), remote)
            text = f"pushed {local} -> {remote}"
        elif word == "shot":
            session_screenshot(con, password, USER, out / f"{rest}.png")
            text = f"screenshot {out / rest}.png"
        elif word == "ui":
            push(con, ROOT / "scripts/guest/atspi.py", "/tmp/atspi.py")
            text = con.run(f"python3 /tmp/atspi.py {rest}", timeout=600)
        elif word == "sleep":
            time.sleep(float(rest))
            text = ""
        elif word == "plasma":
            deadline = time.time() + 600
            while "plasmashell" not in con.run(f"pgrep -u {USER} -x plasmashell -l || true"):
                if time.time() > deadline:
                    sys.exit("plasmashell never started")
                time.sleep(3)
            text = "plasmashell running"
        elif word == "authenticate":
            type_keys(domain, password)
            text = "typed the test password"
        elif word == "login":
            con.login(password, 900)
            con.run(SESSION_ENV)
            text = "logged in"
        else:
            text = con.run(step, timeout=1800)
        print(f"=== {step}\n{text.strip()}", flush=True)


if __name__ == "__main__":
    main()
