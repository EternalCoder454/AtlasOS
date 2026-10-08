#!/usr/bin/env python3
"""The changelog of one testing build, as Markdown on stdout.

    build-notes.py <version> <revision> [<download-size file>]

Run in a full clone of this repository (history and tags), with `gh` signed
in. It compares <revision> with the newest earlier release (stable or
testing; each is tagged with its version) and lists:

- Apps: every pin in the lock file that moved, with the changes it brings
  (pull request titles and commit subjects from the app's repository);
- System: this repository's own commits, without the pin moves;
- Fedora's updates, which every build takes.

The optional file holds the line scripts/update-size.py --line printed ("Download
size: 364 MB from the previous build."), which goes under the title; it is left
out when the file is missing or empty (the size is a courtesy, never a reason
to fail a changelog).

Telamon Updater shows this text as the build's "What's New". A release that
already exists (hand-written notes) is never touched: build.yml only calls
this when there is none.
"""

import json
import re
import subprocess
import sys

LOCKS = ("telamon-apps.lock", "atlas-apps.lock")
NAMES = {
    "framework": "Telamon framework",
    "updater": "Telamon Updater",
    "monitor": "Telamon Monitor",
    "notepad": "Notepad",
    "settings": "Telamon Settings",
    "wizard": "Telamon Setup",
    "store": "Telamon Store",
    "explorer": "Files",
    "archive": "Telamon Archive",
    "launcher": "Telamon Launcher",
    "screenshot": "Telamon Screenshot",
    "installer": "Telamon Installer",
}
MAX_APP_CHANGES = 12
MAX_SYSTEM_CHANGES = 30
VERSION = re.compile(r"^44\.\d{8}(-\d+)?$")


def run(*args: str, check: bool = True) -> str:
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"build-notes: {' '.join(args[:3])}: {r.stderr.strip()}")
    return r.stdout


def version_key(v: str) -> tuple[int, int]:
    day, _, n = v.partition("-")
    return int(day.split(".")[1]), int(n or 0)


def previous_release(version: str) -> str | None:
    """The newest release tag older than `version` that this clone has."""
    out = run("gh", "release", "list", "--limit", "1000", "--exclude-drafts",
              "--json", "tagName", "--jq", ".[].tagName")
    older = [t for t in out.split() if VERSION.match(t)
             and version_key(t) < version_key(version)]
    for tag in sorted(older, key=version_key, reverse=True):
        if run("git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}", check=False).strip():
            return tag
    return None


def pins(rev: str) -> dict[str, tuple[str, str, str]]:
    """name -> (repository, commit, release) in the lock file at `rev`."""
    for lock in LOCKS:
        text = run("git", "show", f"{rev}:{lock}", check=False)
        if text:
            break
    else:
        return {}
    out = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 3 and not line.startswith("#") and re.fullmatch(r"[0-9a-f]{40}", f[2]):
            out[f[0]] = (f[1], f[2], f[3] if len(f) > 3 else "")
    return out


def app_changes(repo: str, old: str, new: str) -> list[str]:
    """What moved between two commits of an app: PR titles, else subjects."""
    raw = run("gh", "api", f"repos/{repo}/compare/{old}...{new}", "--jq",
              "[.commits[] | {m: .commit.message, p: (.parents | length)}]", check=False)
    try:
        commits = json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []
    merged_prs = [c for c in commits if c["p"] > 1 and c["m"].startswith("Merge pull request")]
    lines = []
    if merged_prs:
        # A merge commit's message is "Merge pull request #N from ...", a
        # blank line, then the pull request's title.
        for c in merged_prs:
            parts = c["m"].split("\n")
            title = next((p.strip() for p in parts[1:] if p.strip()), "")
            if title and not title.startswith("Release "):
                lines.append(title)
    else:
        for c in commits:
            subject = c["m"].split("\n", 1)[0].strip()
            if c["p"] == 1 and not subject.startswith(("Merge ", "Release ")):
                lines.append(subject)
    seen, unique = set(), []
    for line in reversed(lines):  # newest first
        if line not in seen:
            seen.add(line)
            unique.append(line)
    return unique


def system_changes(prev: str | None, rev: str) -> list[str]:
    rng = f"{prev}..{rev}" if prev else rev
    out = run("git", "log", "--no-merges", "--format=%s", f"-{MAX_SYSTEM_CHANGES * 3}", rng)
    keep = []
    for s in out.splitlines():
        if re.match(r"^(Pin|Move .* pin|Release )", s):
            continue
        keep.append(s)
    return keep[:MAX_SYSTEM_CHANGES]


def short(release: str, commit: str) -> str:
    return release or commit[:7]


def download_size(path: str) -> str:
    """The "Download size: ..." line in the file, or nothing."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
    except OSError:
        return ""
    return text if re.fullmatch(r"Download size: [^\n]+", text) else ""


def main() -> None:
    if len(sys.argv) not in (3, 4) or not VERSION.match(sys.argv[1]):
        sys.exit("usage: build-notes.py <44.YYYYMMDD-N> <revision> [<download-size file>]")
    version, rev = sys.argv[1], sys.argv[2]
    size = download_size(sys.argv[3]) if len(sys.argv) == 4 else ""
    prev = previous_release(version)
    before = pins(prev) if prev else {}
    now = pins(rev)

    out = [f"A testing build of Telamon OS, from `{rev[:12]}`."]
    out.append(f"Changes since `{prev}`." if prev else "")
    if size:
        out += ["", size]

    apps = []
    for name, (repo, commit, release) in now.items():
        old = before.get(name)
        if old and old[1] == commit:
            continue
        label = NAMES.get(name, name)
        if not old:
            apps.append(f"- **{label}** {short(release, commit)} (new in the image)")
            continue
        apps.append(f"- **{label}** {short(old[2], old[1])} → {short(release, commit)}")
        changes = app_changes(repo, old[1], commit)
        for c in changes[:MAX_APP_CHANGES]:
            apps.append(f"  - {c}")
        if len(changes) > MAX_APP_CHANGES:
            apps.append(f"  - and {len(changes) - MAX_APP_CHANGES} more")
    if apps:
        out += ["", "## Apps", "", *apps]

    system = system_changes(prev, rev)
    if system:
        out += ["", "## System", "", *[f"- {s}" for s in system]]

    out += ["", "## Fedora", "", "- The latest Fedora 44 updates of the day."]
    print("\n".join(line for line in out if line is not None).replace("\n\n\n", "\n\n").strip())


if __name__ == "__main__":
    main()
