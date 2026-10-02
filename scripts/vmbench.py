#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pexpect>=4.9"]
# ///
"""Measures or checks one boot of a prepared AtlasOS test VM.

    vmbench.py <boot|mem|check|all> <domain> <out dir> <password file>

The disk must be one `vm.sh update ... settle` made: it logs in to Plasma by
itself (test VMs only) and has already booted the image once, so first-boot
work doesn't count. Writes <out dir>/report.txt and, for boot and mem,
<out dir>/result.json.

  boot   systemd-analyze, blame (top 15), critical-chain, and when Plasma's
         shell started
  mem    120 s after Plasma's shell starts: free -h and ps_mem
  check  Plasma, network, audio, Bluetooth, printing, Flatpak, the security
         services, Brave Origin, Ghostty and Dolphin opening, a notification,
         and stability (no failed units, crashes or KWin/Plasma restarts),
         with screenshots
  all    boot and mem from the same boot
"""

import argparse
import base64
import json
import pathlib
import re
import subprocess
import sys
import time

from vmctl import URI, USER, Console, session_screenshot

PS_MEM = pathlib.Path(__file__).resolve().parent.parent / "build/tools/usr/bin/ps_mem"
SESSION_ENV = (
    "export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 "
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus"
)


def plasma_started(con: Console, timeout: int = 300) -> float:
    """Seconds after boot (kernel start) at which plasmashell started."""
    deadline = time.time() + timeout
    while True:
        out = con.run(f"pgrep -u {USER} -x plasmashell || true").split()
        if out and out[0].isdigit():
            ticks = con.run(f"getconf CLK_TCK; awk '{{print $22}}' /proc/{out[0]}/stat").split()
            return int(ticks[1]) / int(ticks[0])
        if time.time() > deadline:
            sys.exit("plasmashell never started")
        time.sleep(2)


def uptime(con: Console) -> float:
    return float(con.run("cut -d' ' -f1 /proc/uptime").split()[0])


def boot(con: Console, report: list, result: dict) -> None:
    con.run("systemctl is-system-running --wait || true", timeout=300)
    analyze = con.run("systemd-analyze")
    report += ["### systemd-analyze", analyze.strip(), ""]
    # systemd prints "1min 2.345s", "2.345s" or "673ms".
    span = r"(?:([\d.]+)min )?([\d.]+)(ms|s)"

    def seconds(m: re.Match) -> float:
        return round(float(m.group(1) or 0) * 60 + float(m.group(2)) / (1000 if m.group(3) == "ms" else 1), 3)

    for part in ("firmware", "loader", "kernel", "initrd", "userspace"):
        if m := re.search(span + r" \(" + part + r"\)", analyze):
            result[f"boot_{part}_s"] = seconds(m)
    if m := re.search(r"graphical.target reached after " + span, analyze):
        result["graphical_target_s"] = seconds(m)
    report += ["### systemd-analyze blame (top 15)", con.run("systemd-analyze blame --no-pager | head -n 15").rstrip(), ""]
    report += ["### systemd-analyze critical-chain", con.run("systemd-analyze critical-chain --no-pager").rstrip(), ""]
    # Kernel start to plasmashell: the part of "boot" a user waits through
    # after the firmware.
    result["plasmashell_start_s"] = round(plasma_started(con), 2)
    report += [f"### plasmashell started {result['plasmashell_start_s']} s after the kernel", ""]


def install_ps_mem(con: Console, password: str) -> None:
    """Copies ps_mem (from Fedora's ps_mem RPM, unpacked on the host) into
    /tmp over the console, so the image doesn't have to ship it."""
    data = base64.b64encode(PS_MEM.read_bytes()).decode()
    con.run(": > /tmp/ps_mem.b64")
    for i in range(0, len(data), 3000):
        con.run(f"echo {data[i:i + 3000]} >> /tmp/ps_mem.b64")
    con.run("base64 -d /tmp/ps_mem.b64 > /tmp/ps_mem && chmod +x /tmp/ps_mem")


def mem(con: Console, password: str, report: list, result: dict) -> None:
    started = plasma_started(con)
    wait = started + 120 - uptime(con)
    if wait > 0:
        time.sleep(wait)
    install_ps_mem(con, password)
    free_m = con.run("free -m")
    m = re.search(r"Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)", free_m)
    result.update(mem_used_mib=int(m.group(2)), mem_available_mib=int(m.group(6)))
    result["inotify_max_user_watches"] = int(con.run("cat /proc/sys/fs/inotify/max_user_watches").split()[-1])
    psm = con.sudo("python3 /tmp/ps_mem", password, timeout=120)
    m = re.search(r"^\s+([\d.]+) (KiB|MiB|GiB)\s*$", psm, re.M)
    if m:
        scale = {"KiB": 1 / 1024, "MiB": 1, "GiB": 1024}[m.group(2)]
        result["ps_mem_total_mib"] = round(float(m.group(1)) * scale, 1)
    result["running_system_services"] = int(
        con.run("systemctl list-units --type=service --state=running --no-legend | wc -l").split()[0])
    result["running_user_services"] = int(con.sudo(
        f"systemctl --user -M {USER}@ list-units --type=service --state=running --no-legend | wc -l",
        password).split()[-1])
    report += [f"measured {uptime(con) - started:.0f} s after plasmashell started", ""]
    report += ["### free -h", con.run("free -h").strip(), ""]
    report += ["### free -m", free_m.strip(), ""]
    report += ["### ps_mem", psm.strip(), ""]
    report += ["### running system services",
               con.run("systemctl list-units --type=service --state=running --no-legend --plain | sort").strip(), ""]
    report += ["### running user services", con.sudo(
        f"systemctl --user -M {USER}@ list-units --type=service --state=running --no-legend --plain | sort",
        password).strip(), ""]


def key(domain: str, *keys: str) -> None:
    subprocess.run(["virsh", "-c", URI, "send-key", domain, *keys], capture_output=True)


def check(con: Console, password: str, out: pathlib.Path, report: list, result: dict) -> bool:
    plasma_started(con)
    time.sleep(30)
    con.run(SESSION_ENV)
    results = []

    def ok(name: str, cmd: str, expect: str, sudo: bool = False) -> None:
        text = con.sudo(cmd, password, timeout=120) if sudo else con.run(cmd, timeout=120)
        passed = re.search(expect, text, re.M) is not None
        results.append((name, passed))
        report.extend([f"### {'PASS' if passed else 'FAIL'}: {name}", f"$ {cmd}", text.strip(), ""])

    ok("Plasma shell running", f"pgrep -u {USER} -x plasmashell -l", r"plasmashell")
    ok("KWin running", f"pgrep -u {USER} -x kwin_wayland -l", r"kwin_wayland")
    ok("network up", "nmcli -t -f STATE,CONNECTIVITY general; "
       "curl -s -o /dev/null -w 'http %{http_code}\\n' https://fedoraproject.org/", r"^http 200")
    ok("audio (PipeWire, WirePlumber, a sink)",
       "systemctl --user is-active pipewire.socket pipewire wireplumber pipewire-pulse.socket; "
       "wpctl status | sed -n '/Sinks:/,/Sources:/p' | head -n 4",
       r"(?s)^active\nactive\nactive\nactive\n.*Sinks:\n.*\d+\.")
    # The VM has no Bluetooth adapter, so bluetoothd is skipped by its own
    # condition; the check is that it is installed, enabled and would start.
    ok("Bluetooth service ready", "systemctl is-enabled bluetooth.service; "
       "systemctl show -p ConditionResult -p ActiveState bluetooth.service; bluetoothctl --version",
       r"(?s)^enabled\n.*bluetoothctl: \d")
    ok("printing (CUPS)", "systemctl is-active cups.socket; lpstat -r", r"(?s)^active\n.*scheduler is running")
    # Fedora's own Flatpak registry; Flathub is opt-in, as on stock Kinoite.
    ok("Flatpak runs", "flatpak --version; flatpak remotes --system --columns=name",
       r"(?s)Flatpak \d.*^fedora$")
    ok("SELinux enforcing", "getenforce", r"^Enforcing")
    ok("firewalld active", "systemctl is-active firewalld", r"^active")
    ok("zram swap active", "swapon --show=NAME,TYPE --noheadings", r"zram")
    ok("systemd-oomd active", "systemctl is-active systemd-oomd", r"^active")
    ok("zram uses zstd, swappiness 180", "cat /sys/block/zram0/comp_algorithm; sysctl -n vm.swappiness",
       r"(?s)\[zstd\].*\n180\s*$")
    ok("power profiles (power-profiles-daemon)", "systemctl is-active power-profiles-daemon; powerprofilesctl get",
       r"(?s)^active\n(balanced|performance|power-saver)")
    # Plasma's session reads ~/.config/kdedefaults (the Global Theme's
    # defaults, written at login) before /etc/xdg; so must these reads.
    ok("cursor theme (Bibata, no Breeze cursors)",
       "XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme; "
       "ls -d -1 --color=never /usr/share/icons/Bibata-Modern-*/cursors /usr/share/icons/breeze_cursors 2>&1",
       r"(?s)\ABibata-Modern-(Ice|Classic)\n(?=.*^/usr/share/icons/Bibata-Modern-Classic/cursors$)"
       r"(?=.*^/usr/share/icons/Bibata-Modern-Ice/cursors$)(?=.*breeze_cursors.*No such file)")
    ok("icons (Dracula) and Plasma style (AtlasOS)",
       "XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg kreadconfig6 --file kdeglobals --group Icons --key Theme; "
       "XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg kreadconfig6 --file plasmarc --group Theme --key name; "
       "ls -d -1 --color=never /usr/share/icons/Dracula/index.theme /usr/share/plasma/desktoptheme/atlasos/widgets/tasks.svg",
       r"\ADracula\natlasos\n/usr/share/icons/Dracula/index.theme\n/usr/share/plasma/desktoptheme/atlasos/widgets/tasks.svg$")

    apps = [
        ("Ghostty", "ghostty", "(^|/)ghostty( |$)"),
        ("Dolphin", "dolphin", "(^|/)dolphin( |$)"),
        ("Brave Origin", "brave-origin-stable --password-store=basic", "brave.com/brave-origin/brave( |$)"),
    ]
    for i, (name, cmd, pattern) in enumerate(apps):
        unit = f"check-app-{i}"
        con.run(f"systemd-run --user --quiet --unit={unit} {cmd}")
        time.sleep(15)
        ok(f"{name} opens", f"systemctl --user is-active {unit}; pgrep -u {USER} -f '{pattern}' | head -n 3",
           r"(?s)^active\n\d+")
        session_screenshot(con, password, USER, out / f"check-{i + 1}-{cmd.split()[0]}.png")
        # Close it as a user would: SIGTERM to the app's own first process
        # (not a launcher script), then wait for it to exit. Stopping the
        # unit signals every process at once, which Brave (Chromium) answers
        # with a crash dump.
        con.run(f"p=$(pgrep -o -u {USER} -f '{pattern}'); [ -n \"$p\" ] && kill -TERM $p; "
                f"for i in $(seq 30); do pgrep -u {USER} -f '{pattern}' >/dev/null || break; sleep 1; done; "
                f"systemctl --user stop {unit}; true", timeout=90)
    session_screenshot(con, password, USER, out / "check-0-desktop.png")

    # A notification, as an app sends one (D-Bus, so nothing extra needed).
    con.run(
        "gdbus call --session --dest org.freedesktop.Notifications "
        "--object-path /org/freedesktop/Notifications "
        "--method org.freedesktop.Notifications.Notify 'AtlasOS check' 0 "
        "'dialog-information' 'Update ready' "
        "'AtlasOS 44 will finish installing the next time you restart.' "
        "\"['restart', 'Restart Now']\" '{}' 10000"
    )
    time.sleep(2)
    session_screenshot(con, password, USER, out / "check-5-notification.png")

    # Stability: nothing failed or crashed during the boot and the app launches.
    ok("no failed system units", "systemctl --failed --no-legend --plain | wc -l", r"^0$")
    ok("no failed user units", "systemctl --user --failed --no-legend --plain | wc -l", r"^0$")
    # Any crash fails the gate. (Closing Dolphin used to crash its thumbnail
    # kioworkers; AtlasOS's KIO build fixes that, see build_files/kio.)
    dumps = con.sudo("coredumpctl list --no-legend --no-pager --since=\"$(uptime -s)\" 2>&1 | grep -v 'No coredumps' || true",
                     password)
    crashes = [line for line in dumps.splitlines() if line.strip()]
    results.append(("no crashes (coredumps) this boot", not crashes))
    report += ["### coredumps this boot", dumps.strip() or "(none)", ""]
    result["crashes"] = len(crashes)
    ok("KWin and plasmashell never restarted",
       f"journalctl -b --no-pager -o cat _UID=$(id -u {USER}) | grep -cE 'KCrash|kwin_wayland_wrapper.*(crash|restart)|plasmashell.*crash' || true",
       r"^0$")

    passed = all(p for _, p in results)
    summary = [f"{'PASS' if p else 'FAIL'}  {n}" for n, p in results]
    report[:0] = ["### summary", *summary, f"=> {'ALL PASSED' if passed else 'FAILED'}", ""]
    return passed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["boot", "mem", "check", "all"])
    ap.add_argument("domain")
    ap.add_argument("outdir", type=pathlib.Path)
    ap.add_argument("password_file", type=pathlib.Path)
    a = ap.parse_args()

    a.outdir.mkdir(parents=True, exist_ok=True)
    password = a.password_file.read_text().strip()
    con = Console(a.domain, a.outdir / "console.log")
    con.login(password, timeout=900)
    con.sudo("dmesg -n 1", password)

    report = [f"domain: {a.domain}", f"mode: {a.mode}", con.run("rpm-ostree status --booted | grep -E 'Version|Digest' | head -n 2").strip(), ""]
    result: dict = {}
    passed = True
    if a.mode in ("boot", "all"):
        boot(con, report, result)
    if a.mode in ("mem", "all"):
        mem(con, password, report, result)
    if a.mode == "check":
        passed = check(con, password, a.outdir, report, result)
    (a.outdir / "report.txt").write_text("\n".join(report) + "\n")
    if result:
        (a.outdir / "result.json").write_text(json.dumps(result, indent=1) + "\n")
        print(json.dumps(result))
    if a.mode == "check":
        print("\n".join(report[: report.index("") + 1]))
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
