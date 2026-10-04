#!/usr/bin/env bash
# Prints the newest brave-origin version in Brave's RPM repo (x86_64), e.g.
# 1.96.61, for the build's Decide step. It is only a trigger for "is there a
# newer Brave than the published image has": the build itself installs the
# package through dnf, which verifies the repo and package signatures. The
# metadata is still checked against its published checksum, and everything
# it reads is bounded. Exits non-zero (printing nothing) on any failure.
set -euo pipefail

base="${BRAVE_RPM_BASE:-https://brave-browser-rpm-release.s3.brave.com/x86_64}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { # url, output, size limit in bytes
  curl -fsS --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --retry-all-errors \
    --connect-timeout 15 --max-time 60 --max-filesize "$3" -o "$2" "$1"
}

fetch "${base}/repodata/repomd.xml" "$tmp/repomd.xml" 1000000
python3 - "$tmp/repomd.xml" "$base" "$tmp" <<'PY'
import hashlib, re, subprocess, sys, zlib
import xml.etree.ElementTree as ET

repomd, base, tmp = sys.argv[1:4]
ns = {"r": "http://linux.duke.edu/metadata/repo"}
for d in ET.parse(repomd).getroot().findall("r:data", ns):
    if d.get("type") == "primary":
        href = d.find("r:location", ns).get("href")
        want = d.find("r:checksum", ns).text.strip().lower()
        break
else:
    sys.exit("no primary metadata in repomd.xml")
if not re.fullmatch(r"repodata/[A-Za-z0-9._-]+\.xml\.gz", href) or not re.fullmatch(r"[0-9a-f]{64}", want):
    sys.exit("unexpected primary location or checksum")
out = f"{tmp}/primary.xml.gz"
subprocess.run(["curl", "-fsS", "--proto", "=https", "--tlsv1.2", "--retry", "3", "--retry-delay", "2",
                "--retry-all-errors", "--connect-timeout", "15", "--max-time", "120",
                "--max-filesize", "20000000", "-o", out, f"{base}/{href}"], check=True)
raw = open(out, "rb").read()
if hashlib.sha256(raw).hexdigest() != want:
    sys.exit("primary.xml.gz does not match the checksum in repomd.xml")
# Bounded while decompressing, so a small bomb can't take the runner's memory.
z = zlib.decompressobj(16 + zlib.MAX_WBITS)
xml = z.decompress(raw, 100_000_000)
if z.unconsumed_tail or not z.eof:
    sys.exit("primary.xml is unexpectedly large or truncated")
common = "{http://linux.duke.edu/metadata/common}"
versions = []
for p in ET.fromstring(xml).iter(common + "package"):
    if p.findtext(common + "name") == "brave-origin":
        v = p.find(common + "version").get("ver", "")
        if re.fullmatch(r"[0-9]+(\.[0-9]+)*", v):
            versions.append(tuple(int(x) for x in v.split(".")))
if not versions:
    sys.exit("no brave-origin package in the repo")
print(".".join(map(str, max(versions))))
PY
