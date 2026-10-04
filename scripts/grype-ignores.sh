#!/usr/bin/env bash
# Usage: grype-ignores.sh [TODAY]   (TODAY as YYYY-MM-DD, for tests)
# Prints .grype.yaml (current directory) as the CI gate uses it. The file is
# checked line by line against the one shape it may have (see its header):
# comments, blank lines, "ignore:", and one-line entries naming the
# vulnerability and the package's name, version and type, each ending in
# "# until YYYY-MM-DD: reason". An entry whose date has passed is left out, so
# the gate fails again if the fix still isn't in the image, and the log says
# which one ran out. Anything else (another layout, a missing or invalid date,
# a date more than 90 days ahead, no reason) is an error: exit 1.
set -euo pipefail
today=${1:-$(date -u +%F)}
exec python3 - "$today" .grype.yaml <<'PY'
import datetime, re, sys

today_s, path = sys.argv[1:3]
try:
    today = datetime.date.fromisoformat(today_s)
except ValueError:
    sys.exit(f"bad date '{today_s}'")
horizon = today + datetime.timedelta(days=90)

entry = re.compile(
    r"  - \{vulnerability: (?:GHSA(?:-[23456789cfghjmpqrvwx]{4}){3}|CVE-[0-9]{4}-[0-9]{4,7}|GO-[0-9]{4}-[0-9]{4,6}), "
    r"package: \{name: [A-Za-z0-9._/-]{1,200}, version: (?:[A-Za-z0-9._+~-]{1,100}|\"[A-Za-z0-9._+~-]{1,100}\"), "
    r"type: (?:go-module|python|rpm|binary|java-archive|npm|rust-crate)\}\}"
    r" # until ([0-9]{4}-[0-9]{2}-[0-9]{2}): [!-~][ -~]{0,199}"
)
out, bad, seen_ignore = [], False, False
with open(path, encoding="utf-8", errors="replace") as f:
    for n, line in enumerate(f, 1):
        line = line.rstrip("\n")
        where = f"{path}:{n}"
        # Printable ASCII only: YAML also ends a line at U+0085, U+2028 and
        # U+2029, which would let a "comment" here carry an unchecked entry.
        if not re.fullmatch(r"[ -~]*", line):
            print(f"::error::{where}: only printable ASCII is allowed (no tabs, CR, Unicode)",
                  file=sys.stderr)
            bad = True
            continue
        if re.fullmatch(r" *(#.*)?", line):
            out.append(line)
            continue
        if line == "ignore:" and not seen_ignore:
            seen_ignore = True
            out.append(line)
            continue
        m = entry.fullmatch(line) if seen_ignore else None
        if not m:
            print(f"::error::{where}: not a one-line entry with a version, type and "
                  f"\"# until YYYY-MM-DD: reason\": {line}", file=sys.stderr)
            bad = True
            continue
        try:
            until = datetime.date.fromisoformat(m.group(1))
        except ValueError:
            print(f"::error::{where}: '{m.group(1)}' is not a date: {line}", file=sys.stderr)
            bad = True
            continue
        if until > horizon:
            print(f"::error::{where}: {until} is more than 90 days ahead: {line}", file=sys.stderr)
            bad = True
            continue
        if until < today:
            print(f"::warning::{where}: this ignore ran out on {until} and no longer applies: {line}",
                  file=sys.stderr)
            continue
        out.append(line)
if bad:
    sys.exit(1)
print("\n".join(out))
PY
