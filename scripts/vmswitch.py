#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pexpect>=4.9"]
# ///
"""Switches a booted test VM to the image shared into it, then powers it off.

    vmswitch.py <domain> <log file> <password file> [--settle]

vm.sh update shares an OCI directory into the VM over virtiofs (tag
"atlasos-image"); this logs in on the serial console, mounts it, runs
`bootc switch` to it, and powers the VM off. The next boot runs the new image.
Its origin is then the share, which is gone: `bootc upgrade` won't work in it.

--settle readies the disk for measurements (scripts/vmbench.py): it logs in
to Plasma by itself (test disks only), and the new image boots once, through
to Plasma, before the power-off, so first-boot work isn't measured later.
"""

import argparse
import pathlib
import sys
import time

import pexpect

from vmctl import USER, Console


def power(con: Console, password: str, action: str) -> None:
    """The console can close before any end marker comes back, so send the
    command and wait for the prompt or the line to go quiet, not for output."""
    con.p.send(f"sudo -p 'SUDO''PW:' systemctl {action}\r")
    if con.p.expect(["SUDOPW:", pexpect.EOF, pexpect.TIMEOUT], timeout=15) == 0:
        con.p.send(password + "\r")
        con.p.expect([pexpect.EOF, pexpect.TIMEOUT], timeout=15)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("domain")
    ap.add_argument("log", type=pathlib.Path)
    ap.add_argument("password_file", type=pathlib.Path)
    ap.add_argument("--settle", action="store_true")
    a = ap.parse_args()

    password = a.password_file.read_text().strip()
    con = Console(a.domain, a.log)
    con.login(password, timeout=900)
    con.sudo("dmesg -n 1", password)
    out = con.sudo(
        "mkdir -p /run/atlasos-image && "
        "mount -t virtiofs atlasos-image /run/atlasos-image && "
        "bootc switch --transport oci /run/atlasos-image/image && "
        "umount /run/atlasos-image && echo switched-ok",
        password,
        timeout=1800,
    )
    print(out)
    if "switched-ok" not in out:
        sys.exit("bootc switch failed; see " + str(a.log))
    if a.settle:
        # /etc changes made now are merged into the new deployment.
        con.sudo(
            "mkdir -p /etc/plasmalogin.conf.d && "
            f"printf \"[Autologin]\\nUser={USER}\\nSession=plasma\\n\" "
            ">/etc/plasmalogin.conf.d/zz-vmtest-autologin.conf && touch /etc/plasma-setup-done",
            password,
        )
        power(con, password, "reboot")
        con.login(password, timeout=900)
        deadline = time.time() + 300
        while "plasmashell" not in con.run(f"pgrep -u {USER} -x plasmashell -l || true"):
            if time.time() > deadline:
                sys.exit("plasmashell never started on the new image")
            time.sleep(2)
        time.sleep(60)
        print(con.run("rpm-ostree status --booted | head -n 4"))
    power(con, password, "poweroff")


if __name__ == "__main__":
    main()
