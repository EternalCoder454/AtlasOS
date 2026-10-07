#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pexpect>=4.9"]
# ///
"""Drives a freshly started test VM through its serial console.

    vmctl.py <domain> <out dir> <password file> [--settle SECONDS]

1. Screenshots the boot every second (the Plymouth splash).
2. Waits for the serial login prompt, then screenshots the login screen.
3. Logs in as "atlas" on the console, turns on autologin for the same user
   (test VMs only, in /etc of the throwaway overlay) and restarts the login
   manager. Screenshots the Plasma splash every second while it loads.
4. Waits for plasmashell, waits --settle seconds more (default 120), then
   records memory, running services and the biggest processes into
   <out dir>/report.txt and screenshots the desktop.
"""

import argparse
import base64
import json
import os
import pathlib
import re
import subprocess
import sys
import time

import pexpect

URI = os.environ.get("LIBVIRT_DEFAULT_URI", "qemu:///system")
USER = "atlas"


def screenshot(domain: str, path: pathlib.Path) -> bool:
    ppm = path.with_suffix(".ppm")
    r = subprocess.run(
        ["virsh", "-c", URI, "screenshot", domain, str(ppm)],
        capture_output=True,
    )
    if r.returncode == 0 and ppm.exists():
        subprocess.run(["magick", str(ppm), str(path)], check=False)
    ppm.unlink(missing_ok=True)
    return path.exists()


def agent(domain: str, command: str, **args) -> dict:
    r = subprocess.run(
        ["virsh", "-c", URI, "qemu-agent-command", domain,
         json.dumps({"execute": command, "arguments": args})],
        capture_output=True, text=True, check=True,
    )
    return json.loads(r.stdout)["return"]


def session_screenshot(con: "Console", password: str, user: str, path: pathlib.Path) -> None:
    """Screenshots USER's Wayland session from inside the guest. QEMU can't
    read back a SPICE OpenGL display, so once Plasma draws with the GPU
    virsh screenshot has nothing to save. Spectacle saves the picture and the
    guest agent copies it out; the new label lets the agent's SELinux domain
    read it."""
    tmp = f"/tmp/vmctl-{path.stem}.png"
    con.sudo(
        f"u=$(id -u {user}) && runuser -u {user} -- env XDG_RUNTIME_DIR=/run/user/$u "
        f"WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$u/bus "
        f"spectacle -b -n -f -o {tmp} && chcon -t virt_qemu_ga_tmp_t {tmp}",
        password,
    )
    try:
        h = agent(con.domain, "guest-file-open", path=tmp, mode="r")
        try:
            data = b""
            while True:
                # 2 MiB: libvirt refuses a reply string over 4 MiB, and
                # base64 makes 4 MiB of picture 5.3 MiB.
                r = agent(con.domain, "guest-file-read", handle=h, count=2 << 20)
                data += base64.b64decode(r["buf-b64"])
                if r["eof"]:
                    break
        finally:
            agent(con.domain, "guest-file-close", handle=h)
        path.write_bytes(data)
    except (subprocess.CalledProcessError, ValueError, KeyError) as e:
        err = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else repr(e)
        print(f"vmctl: no screenshot {path.name}: {err}", file=sys.stderr)
    con.sudo(f"rm -f {tmp}", password)


def shot(con: "Console", password: str, user: str, path: pathlib.Path) -> None:
    if not screenshot(con.domain, path):
        session_screenshot(con, password, user, path)


def frames(domain: str, outdir: pathlib.Path, prefix: str, seconds: int) -> None:
    for i in range(seconds):
        screenshot(domain, outdir / f"{prefix}-{i:03d}.png")
        time.sleep(1)


class Console:
    def __init__(self, domain: str, log: pathlib.Path):
        self.domain = domain
        self.p = pexpect.spawn(
            "virsh",
            ["-c", URI, "console", domain, "--force"],
            encoding="utf-8",
            codec_errors="replace",
            timeout=30,
        )
        self.p.logfile_read = open(log, "a")
        self.n = 0

    def login(self, password: str, timeout: int) -> None:
        deadline = time.time() + timeout
        while True:
            self.p.send("\r")
            i = self.p.expect([r"login: ?$", pexpect.TIMEOUT], timeout=10)
            if i == 0:
                break
            if time.time() > deadline:
                sys.exit("no login prompt on the serial console")
        self.p.send(USER + "\r")
        self.p.expect("Password: ?")
        self.p.send(password + "\r")
        self.p.expect(r"[$#] ?$", timeout=60)
        # Wide, plain output: nothing wraps, pages or colours.
        self.run("stty cols 400 rows 1000; export TERM=dumb SYSTEMD_PAGER= SYSTEMD_COLORS=0")

    def run(self, cmd: str, timeout: int = 60) -> str:
        """Runs cmd and returns its output. The quotes split the markers in
        the echoed command line, so only the real output matches them."""
        self.n += 1
        b, d = f"__B{self.n}__", f"__D{self.n}_"
        self.p.send(f"echo {b[:3]}''{b[3:]}; {cmd}; echo {d[:3]}''{d[3:]}$?__\r")
        self.p.expect(re.escape(b) + r"\r?\n", timeout=timeout)
        self.p.expect(re.escape(d) + r"(\d+)__", timeout=timeout)
        out = self.p.before.replace("\r", "")
        if self.p.match.group(1) != "0":
            print(f"vmctl: '{cmd}' exited {self.p.match.group(1)}", file=sys.stderr)
        return out

    def sudo(self, cmd: str, password: str, timeout: int = 60) -> str:
        """sudo with its prompt answered over the console, echo off."""
        self.n += 1
        b, d = f"__B{self.n}__", f"__D{self.n}_"
        self.p.send(
            f"echo {b[:3]}''{b[3:]}; sudo -p 'SUDO''PW:' sh -c '{cmd}'; echo {d[:3]}''{d[3:]}$?__\r"
        )
        self.p.expect(re.escape(b) + r"\r?\n", timeout=timeout)
        i = self.p.expect(["SUDOPW:", re.escape(d) + r"(\d+)__"], timeout=timeout)
        if i == 0:
            self.p.send(password + "\r")
            self.p.expect(re.escape(d) + r"(\d+)__", timeout=timeout)
        return self.p.before.replace("\r", "")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("domain")
    ap.add_argument("outdir", type=pathlib.Path)
    ap.add_argument("password_file", type=pathlib.Path)
    ap.add_argument("--settle", type=int, default=120)
    ap.add_argument("--boot-frames", type=int, default=40)
    a = ap.parse_args()

    a.outdir.mkdir(parents=True, exist_ok=True)
    password = a.password_file.read_text().strip()
    t0 = time.time()

    frames(a.domain, a.outdir, "boot", a.boot_frames)

    con = Console(a.domain, a.outdir / "console.log")
    con.login(password, timeout=900)
    boot_s = time.time() - t0
    time.sleep(20)  # the graphical greeter comes up alongside the getty

    # Keep kernel messages off the console so they can't land in the output.
    con.sudo("dmesg -n 1", password)
    shot(con, password, "plasmalogin", a.outdir / "login-screen.png")
    first_boot = con.run(
        "systemctl is-active telamon-wizard-boot.service; ls /etc/telamon/setup-done /etc/plasma-setup-done 2>&1"
    )
    con.sudo(
        "mkdir -p /etc/plasmalogin.conf.d && "
        f"printf \"[Autologin]\\nUser={USER}\\nSession=plasma\\n\" "
        ">/etc/plasmalogin.conf.d/zz-vmtest-autologin.conf && "
        "mkdir -p /etc/telamon && touch /etc/telamon/setup-done /etc/plasma-setup-done && "
        "rm -f /etc/plasmalogin.conf.d/99-telamon-wizard.conf; systemctl restart plasmalogin.service",
        password,
    )
    frames(a.domain, a.outdir, "splash", 25)

    deadline = time.time() + 300
    while "plasmashell" not in con.run(f"pgrep -u {USER} -x plasmashell -l || true"):
        if time.time() > deadline:
            screenshot(a.domain, a.outdir / "no-plasma.png")
            sys.exit("plasmashell never started")
        time.sleep(2)
    login_at = time.time()
    time.sleep(a.settle)

    sections = {
        "os-release": "cat /etc/os-release",
        "first-run setup before login": None,
        "free -h": "free -h",
        "free -m": "free -m",
        "meminfo": "head -n 25 /proc/meminfo",
        "zram": "zramctl",
        "running system services": "systemctl list-units --type=service --state=running --no-legend --plain | sort",
        "running user services": f"systemctl --user -M {USER}@ list-units --type=service --state=running --no-legend --plain | sort",
        "top 30 processes by RSS (KiB)": "ps -eo rss=,user=,comm= --sort=-rss | head -n 30",
        "boot timing": "systemd-analyze || true",
    }
    report = [
        f"domain: {a.domain}",
        f"serial login prompt after: {boot_s:.0f} s",
        f"measured {a.settle} s after plasmashell started "
        f"({time.time() - login_at:.0f} s by the clock)",
        "",
    ]
    for title, cmd in sections.items():
        if cmd is None:
            out = first_boot
        elif "--user -M" in cmd:
            out = con.sudo(cmd.replace("'", "'\\''"), password)
        else:
            out = con.run(cmd)
        report += [f"### {title}", out.strip(), ""]
    (a.outdir / "report.txt").write_text("\n".join(report))
    shot(con, password, USER, a.outdir / "desktop.png")
    print("\n".join(report))


if __name__ == "__main__":
    main()
