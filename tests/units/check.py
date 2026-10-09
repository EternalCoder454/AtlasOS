#!/usr/bin/python3
"""The checks behind run.sh. Usage: check.py REPO. Exit 0 when all pass."""
import os
import re
import stat
import subprocess
import sys
import xml.etree.ElementTree as ET

repo = sys.argv[1]
sysfiles = [os.path.join(repo, "system_files"), os.path.join(repo, "system_files_nvidia")]
failed = 0


def ok(msg):
    print(f"  ok   {msg}")


def bad(msg):
    global failed
    failed += 1
    print(f"  FAIL {msg}")


def check(cond, msg, detail=""):
    ok(msg) if cond else bad(msg + (f" ({detail})" if detail else ""))


def files(sub, suffix=None):
    for root in sysfiles:
        base = os.path.join(root, sub)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, names in os.walk(base):
            for n in sorted(names):
                if suffix is None or n.endswith(suffix):
                    yield os.path.join(dirpath, n)


def directives(path):
    """{key: [values]} of a unit file's lines (all sections, no comments)."""
    out = {}
    for line in open(path).read().splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";", "[")) or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out.setdefault(k, []).append(v)
    return out


def rel(p):
    return os.path.relpath(p, repo)


# ---- 1. system units -------------------------------------------------------
print("== 1. system units: syntax, hardening floor, exposure ceilings")
units = sorted(files("usr/lib/systemd/system", ".service"))
ours = [u for u in units if os.path.basename(u).startswith("atlasos-")]
check(len(ours) >= 6, f"found our services ({len(ours)})")

# Every service of ours keeps this floor.
FLOOR = ["LockPersonality", "RestrictRealtime", "SystemCallArchitectures",
         "RestrictAddressFamilies", "CapabilityBoundingSet"]
# Services that may reach the network (they pull from registries).
NETWORK = {"atlasos-update-stage.service", "atlasos-flatpak-preinstall.service"}
# No NoNewPrivileges, and why: bootc, rpm-ostree and flatpak run setuid and
# SELinux-transitioning programs (docs/SECURITY.md, "Units").
NO_NNP = {"atlasos-update-stage.service": "bootc/rpm-ostree transitions",
          "atlasos-flatpak-preinstall.service": "flatpak's bubblewrap is setuid-capable"}
# Highest `systemd-analyze security --offline` exposure each may have; a
# change that raises it needs a reason in the commit and a new number here.
CEILING = {"atlasos-btrfs-compress.service": 4.5, "atlasos-flatpak-preinstall.service": 6.0,
           "atlasos-grub-greenboot.service": 4.3, "atlasos-inotify-watches.service": 1.3,
           "atlasos-pin@.service": 1.1, "atlasos-update-stage.service": 6.7}

for u in ours:
    name = os.path.basename(u)
    d = directives(u)
    for k in FLOOR:
        check(k in d, f"{name} sets {k}")
    if name not in NO_NNP:
        check(d.get("NoNewPrivileges") == ["yes"], f"{name} has NoNewPrivileges=yes")
    fam = d.get("RestrictAddressFamilies", [""])[0].split()
    if name not in NETWORK:
        check(set(fam) <= {"AF_UNIX"} or d.get("PrivateNetwork") == ["yes"],
              f"{name} gets no network", " ".join(fam))
    check(not any(v.startswith("-") or "+" == v[:1] for v in d.get("ExecStart", [])),
          f"{name}: ExecStart runs with the unit's restrictions (no +/! prefix)")
    ex = d.get("ExecStart", [""])[0].split()[0]
    check(ex.startswith(("/usr/libexec/telamon/", "/bin/sh", "/usr/libexec/telamon-")),
          f"{name}: ExecStart is an absolute path of ours", ex)
    cap = d.get("CapabilityBoundingSet", [""])[0]
    check(not (not cap.startswith("~") and "CAP_SYS_MODULE" in cap), f"{name}: never keeps CAP_SYS_MODULE")

proc = subprocess.run(["systemd-analyze", "verify", "--man=no"] + units
                      + sorted(files("usr/lib/systemd/system", ".socket"))
                      + sorted(files("usr/lib/systemd/system", ".timer")),
                      capture_output=True, text=True)
problems = [l for l in (proc.stdout + proc.stderr).splitlines()
            if re.search(r"Unknown (key|section|assignment)|Failed to parse|Invalid|not a valid|"
                         r"Unknown lvalue|Unknown unit type|bad setting|Cannot|Executable path", l)]
check(not problems, "systemd-analyze verify finds no misspelt or invalid setting", "; ".join(problems[:3]))

for u in ours:
    name = os.path.basename(u)
    if name not in CEILING:
        bad(f"{name} has no exposure ceiling in tests/units/check.py")
        continue
    out = subprocess.run(["systemd-analyze", "security", "--offline=yes", "--no-pager", u],
                         capture_output=True, text=True).stdout
    m = re.search(r"Overall exposure level for [^:]+: ([0-9.]+)", out)
    score = float(m.group(1)) if m else 99
    check(score <= CEILING[name], f"{name} exposure {score} <= {CEILING[name]}")

# The socket and the PIN service
print("== 2. the PIN verifier's socket and service")
sock = directives(os.path.join(repo, "system_files/usr/lib/systemd/system/atlasos-pin.socket"))
check(sock["ListenStream"] == ["/run/atlasos/pin.sock"], "the socket is /run/atlasos/pin.sock")
check(sock["Accept"] == ["yes"], "one service per connection")
check(sock["SocketMode"] == ["0666"], "any user may connect (the service decides who may ask what)")
check(int(sock["MaxConnectionsPerSource"][0]) <= 2, "at most 2 connections per user")
check(int(sock["MaxConnections"][0]) <= 16, "at most 16 connections")
pin = directives(os.path.join(repo, "system_files/usr/lib/systemd/system/atlasos-pin@.service"))
for k, v in {"NoNewPrivileges": "yes", "ProtectSystem": "strict", "PrivateNetwork": "yes",
             "PrivateTmp": "yes", "PrivateDevices": "yes", "ProtectHome": "yes",
             "RestrictAddressFamilies": "AF_UNIX", "CapabilityBoundingSet": "CAP_DAC_READ_SEARCH",
             "ReadWritePaths": "/var/lib/atlasos/pin", "UMask": "0077", "RuntimeMaxSec": "10",
             "RestrictNamespaces": "yes", "RestrictSUIDSGID": "yes", "ProtectProc": "invisible",
             "RefuseManualStart": "yes",
             "SELinuxContext": "system_u:system_r:atlasos_pin_t:s0"}.items():
    check(pin.get(k) == [v], f"atlasos-pin@.service has {k}={v}", str(pin.get(k)))
check("~@privileged @resources" in pin.get("SystemCallFilter", []), "the daemon's syscall filter drops @privileged @resources")
tf = open(os.path.join(repo, "system_files/usr/lib/tmpfiles.d/atlasos-pin.conf")).read()
check(re.search(r"^d /var/lib/atlasos/pin 0700 root root -$", tf, re.M), "the store is created 0700 root")

# ---- user units ------------------------------------------------------------
print("== 3. user units")
for u in sorted(files("usr/lib/systemd/user", ".service")):
    d = directives(u)
    name = os.path.basename(u)
    for k, v in {"NoNewPrivileges": "yes", "LockPersonality": "yes", "RestrictRealtime": "yes",
                 "RestrictSUIDSGID": "yes", "SystemCallArchitectures": "native"}.items():
        check(d.get(k) == [v], f"{name} has {k}={v}", str(d.get(k)))
    check(all(e.split()[0].startswith("/usr/") for e in d["ExecStart"]), f"{name} runs a program under /usr")

# ---- polkit ---------------------------------------------------------------
print("== 4. polkit")
rules = list(files("usr/share/polkit-1/rules.d")) + list(files("etc/polkit-1"))
check(not rules, "the image ships no polkit rules (a rule would need review)", str(rules))
for pol in sorted(files("usr/share/polkit-1/actions", ".policy")):
    root = ET.parse(pol).getroot()
    for a in root.findall("action"):
        aid = a.get("id")
        d = {c.tag: (c.text or "").strip() for c in a.find("defaults")}
        check(d["allow_any"] == "no" and d["allow_inactive"] == "no", f"{aid}: remote and inactive sessions are refused")
        check(d["allow_active"] in ("auth_self", "auth_admin", "auth_admin_keep"), f"{aid}: active users must authenticate", d["allow_active"])
        ann = {x.get("key"): (x.text or "").strip() for x in a.findall("annotate")}
        path = ann.get("org.freedesktop.policykit.exec.path")
        check(path is not None, f"{aid}: runs one program")
        if path:
            check(path.startswith("/usr/libexec/telamon/"), f"{aid}: {path} is one of ours")
            local = None
            for root_dir in sysfiles:
                cand = os.path.join(root_dir, path.lstrip("/"))
                if os.path.isfile(cand):
                    local = cand
            check(local is not None, f"{aid}: {path} exists in the repository")
            if local:
                mode = os.stat(local).st_mode
                check(mode & stat.S_IXUSR and not mode & (stat.S_IWGRP | stat.S_IWOTH), f"{aid}: {path} is executable and not group/other-writable")
        check("org.freedesktop.policykit.exec.argv1" not in ann, f"{aid}: no argument is pinned (the program validates its own)")

# ---- sudoers and setuid ---------------------------------------------------
print("== 5. sudoers, setuid, world-writable")
bad_files = []
for root in sysfiles:
    for dirpath, dirs, names in os.walk(root):
        for n in names:
            p = os.path.join(dirpath, n)
            m = os.lstat(p).st_mode
            if stat.S_ISLNK(m):
                if os.path.isabs(os.readlink(p)) and "/home" in os.readlink(p):
                    bad_files.append(rel(p))
                continue
            if m & (stat.S_ISUID | stat.S_ISGID | stat.S_IWOTH):
                bad_files.append(rel(p))
            if "sudoers" in p:
                bad_files.append(rel(p))
check(not bad_files, "no setuid, setgid, world-writable file, sudoers file or link into /home", str(bad_files))
grep = subprocess.run(["grep", "-rIl", "-i", "NOPASSWD", os.path.join(repo, "system_files"),
                       os.path.join(repo, "system_files_nvidia"), os.path.join(repo, "build_files")],
                      capture_output=True, text=True).stdout
check(not grep.strip(), "nothing grants NOPASSWD", grep)

# ---- scripts -------------------------------------------------------------
print("== 6. root-run and per-user scripts")
libexec = [p for p in files("usr/libexec/telamon")]
for p in libexec:
    mode = os.stat(p).st_mode
    first = open(p, errors="replace").readline().strip()
    if os.path.basename(p) != "pinlib.py":  # a module, imported by the others
        check(mode & stat.S_IXUSR, f"{rel(p)} is executable")
    check(not mode & (stat.S_IWGRP | stat.S_IWOTH), f"{rel(p)} is not group/other-writable")
    if os.path.basename(p) != "pinlib.py" and not os.path.basename(p).endswith("-lib") and os.path.basename(p) != "health-lib":
        check(first.startswith("#!/"), f"{rel(p)} has an interpreter line", first)
    text = open(p, errors="replace").read()
    code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    check(not re.search(r"(^|[;&|(`\s])eval\s", code), f"{rel(p)} never evals")
    check(not re.search(r"\|\s*(ba|z)?sh\b|source\s+<\(|\bcurl\b|\bwget\b", code), f"{rel(p)} pipes nothing into a shell and fetches nothing")
    if "/tmp/" in code:
        bad(f"{rel(p)} uses a fixed /tmp path")
for p in sorted(files("usr/share/kconf_update", ".sh")):
    mode = os.stat(p).st_mode
    text = open(p).read()
    code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    n = rel(p)
    check(mode & stat.S_IXUSR, f"{n} is executable (kconf_update needs it)")
    check(text.startswith("#!/bin/sh\n"), f"{n} is a plain sh script")
    check(re.search(r"^set -eu\b", text, re.M) is not None, f"{n} has set -eu")
    check(not re.search(r"(^|[;&|(`\s])eval\s", code), f"{n} never evals")
    check("/tmp/" not in code and "mktemp -u" not in code, f"{n} uses no fixed or predictable temporary file")
    check(not re.search(r"\bcurl\b|\bwget\b|\bsudo\b|\bpkexec\b|\bchmod [0-7]*7[0-7]{0,2}\b ", code), f"{n} fetches nothing and escalates nothing")
upd = open(os.path.join(repo, "system_files/usr/share/kconf_update/atlasos.upd")).read()
scripts = set(re.findall(r"^Script=([^,]+),sh", upd, re.M))
onfs = {os.path.basename(p) for p in files("usr/share/kconf_update", ".sh")}
check(scripts == onfs, "every kconf_update script is listed, and every listed one exists", str(scripts ^ onfs))
ids = re.findall(r"^Id=(\S+)", upd, re.M)
check(len(ids) == len(set(ids)), "no Id is used twice")

# ---- Homebrew's PATH -------------------------------------------------------
print("== 7. Homebrew's commands reach only the user who owns the prefix")
subprocess.run(["useradd", "-u", "1001", "alice"], capture_output=True)
subprocess.run(["useradd", "-u", "1002", "bob"], capture_output=True)
os.makedirs("/home/linuxbrew/.linuxbrew/bin", exist_ok=True)
open("/home/linuxbrew/.linuxbrew/bin/brew", "w").write("#!/bin/sh\n")
os.chmod("/home/linuxbrew/.linuxbrew/bin/brew", 0o755)
subprocess.run(["chown", "-R", "1001", "/home/linuxbrew"])
for uid, want in (("0", "out"), ("1001", "in"), ("1002", "out")):
    out = subprocess.run(
        ["setpriv", f"--reuid={uid}", f"--regid={uid}", "--clear-groups", "sh", "-c",
         ". " + os.path.join(repo, "system_files/etc/profile.d/atlasos-brew.sh")
         + '; case $PATH in *linuxbrew*) echo in;; *) echo out;; esac'],
        capture_output=True, text=True).stdout.strip()
    check(out == want, f"uid {uid} gets brew on PATH: {want}", out)

print()
print("PASS: tests/units" if not failed else f"FAIL: tests/units ({failed})")
sys.exit(1 if failed else 0)
