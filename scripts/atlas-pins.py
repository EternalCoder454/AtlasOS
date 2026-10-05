#!/usr/bin/env python3
"""The Atlas app pins in atlas-apps.lock: which commit of atlas-framework and
of each Atlas app goes in the image.

  atlas-pins.py list                 name, repository, commit and release, checked
  atlas-pins.py get <name>           the pinned commit
  atlas-pins.py repo <name>          the repository
  atlas-pins.py verify               each pin is on its repository's default
                                     branch, and its release tag (if any) names it
  atlas-pins.py latest <name>        "<commit> <release or ->": the newest release,
                                     or the default branch's head with none; the
                                     pin itself when that doesn't come after it
  atlas-pins.py log <name> <commit>  the commits from the pin to <commit>
  atlas-pins.py set [--force] <name> <commit> [release]
                                     move a pin forward (never back or sideways;
                                     --force only when the app rewrote history)
  atlas-pins.py fetch <name> <dir>   <dir>, under build/pinned/, holds the pinned
                                     commit (local builds)

The file is checked line by line against the one shape it may have, so a bad
edit fails loudly instead of building something else. GitHub's API is asked
over HTTPS (with GH_TOKEN when set) with time and size limits; nothing it returns is trusted
until it matches the same patterns. Exit 1 on any problem, with the reason.
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = ROOT / "atlas-apps.lock"
NAMES = ("framework", "updater", "monitor", "notepad", "settings", "wizard", "store", "explorer", "archive", "launcher", "installer")
REPO = re.compile(r"EternalCoder454/[A-Za-z0-9][A-Za-z0-9._-]{0,99}(?<!\.git)")
SHA = re.compile(r"[0-9a-f]{40}")
TAG = re.compile(r"v[0-9]{1,4}(?:\.[0-9]{1,4}){1,3}(?:-[0-9A-Za-z.]{1,40})?")
MAX_BODY = 20_000_000  # a compare's first page carries the changed files too
DEADLINE = 60  # seconds for one whole answer, however slowly it trickles in
LOG_PAGES = 1  # 100 commits: six apps stay inside a pull request body's 65536 characters
# compare()'s word for a commit that doesn't come after another, in a sentence.
RELATION = {"behind": "older than", "diverged": "on a different branch from", "identical": "the same as"}
LINE = re.compile(
    r"(?P<name>[a-z]+) +(?P<repo>\S+) +(?P<sha>\S+)(?: +(?P<tag>\S+))? *"
)


def die(msg: str) -> None:
    sys.exit(f"atlas-pins: {msg}")


def read() -> tuple[list[str], dict[str, dict]]:
    """The file's lines (kept for `set`) and its pins, checked."""
    try:
        lines = LOCK.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeDecodeError) as e:
        die(f"can't read {LOCK.name}: {e}")
    pins: dict[str, dict] = {}
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.startswith("#"):
            continue
        m = LINE.fullmatch(line)
        if not m:
            die(f"{LOCK.name}:{n}: not 'name repository commit [release]'")
        p = m.groupdict()
        if p["name"] not in NAMES:
            die(f"{LOCK.name}:{n}: unknown name '{p['name']}' (one of {', '.join(NAMES)})")
        if p["name"] in pins:
            die(f"{LOCK.name}:{n}: '{p['name']}' is pinned twice")
        if not REPO.fullmatch(p["repo"]):
            die(f"{LOCK.name}:{n}: '{p['repo']}' isn't an EternalCoder454 repository")
        if not SHA.fullmatch(p["sha"]):
            die(f"{LOCK.name}:{n}: the commit must be 40 lowercase hex characters")
        if p["tag"] is not None and not TAG.fullmatch(p["tag"]):
            die(f"{LOCK.name}:{n}: '{p['tag']}' isn't a release tag like v1.3.0")
        p["line"] = n - 1
        pins[p["name"]] = p
    missing = [x for x in NAMES if x not in pins]
    if missing:
        die(f"{LOCK.name}: no pin for {', '.join(missing)}")
    return lines, pins


def api(path: str, allow_404: bool = False):
    """One GitHub API read (JSON), bounded in time and size. GH_TOKEN, when
    set, raises the rate limit; the repositories are public without it."""
    req = urllib.request.Request(
        f"https://api.github.com/{path}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "atlasos-pins"},
    )
    if os.environ.get("GH_TOKEN"):
        # Unredirected: a redirect, wherever it leads, goes without the token.
        req.add_unredirected_header("Authorization", f"Bearer {os.environ['GH_TOKEN']}")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                end, body = time.monotonic() + DEADLINE, b""
                while chunk := r.read(65536):
                    body += chunk
                    if len(body) > MAX_BODY:
                        die(f"GitHub's answer for {path} is too large")
                    if time.monotonic() > end:
                        raise TimeoutError(f"no whole answer in {DEADLINE} s")
            return json.loads(body)
        except urllib.error.HTTPError as e:
            # 422: GitHub's compare for a commit the repository doesn't have.
            if e.code in (404, 422) and allow_404:
                return None
            if e.code == 401:
                die("GitHub refused GH_TOKEN (HTTP 401): it's wrong or has expired")
            if e.code in (403, 429):
                wait = e.headers.get("Retry-After", "")
                if re.fullmatch(r"[0-9]{1,3}", wait) and int(wait) <= 60 and attempt < 2:
                    time.sleep(int(wait))
                    continue
                if e.headers.get("X-RateLimit-Remaining") == "0":
                    reset = e.headers.get("X-RateLimit-Reset", "")
                    try:
                        at = time.strftime("%H:%M", time.localtime(int(reset)))
                    except (ValueError, OverflowError, OSError):
                        at = "later"
                    die(f"GitHub's rate limit is used up; try again at {at}, or set GH_TOKEN")
            if e.code == 404:
                die(f"GitHub has no {path} (HTTP 404: not there, or private)")
            if e.code < 500 or attempt == 2:
                die(f"GitHub refused {path}: HTTP {e.code}")
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            if attempt == 2:
                die(f"GitHub didn't answer for {path}: {e}")
        time.sleep(2 * (attempt + 1))


def field(obj, *keys) -> str:
    for k in keys:
        obj = obj.get(k) if isinstance(obj, dict) else None
    return obj if isinstance(obj, str) else ""


def default_branch(repo: str) -> str:
    b = field(api(f"repos/{repo}"), "default_branch")
    if (not b or not re.fullmatch(r"[A-Za-z0-9._/-]{1,100}", b)
            or ".." in b or b.startswith("/") or b.endswith("/")):
        die(f"{repo}: unexpected default branch '{b}'")
    return b


def tag_commit(repo: str, tag: str) -> str:
    c = api(f"repos/{repo}/commits/refs/tags/{tag}", allow_404=True)
    if c is None:
        die(f"{repo} has no tag {tag}")
    sha = field(c, "sha")
    if not SHA.fullmatch(sha):
        die(f"{repo}: unexpected commit for {tag}")
    return sha


def compare(repo: str, base: str, head: str) -> str:
    """GitHub's word for head against base: ahead, behind, identical or diverged."""
    c = api(f"repos/{repo}/compare/{base}...{head}?per_page=1", allow_404=True)
    s = None if c is None else field(c, "status")
    if s is None:
        die(f"{repo}: {base[:12]} or {head[:12]} isn't in the repository (or it's private)")
    if s not in ("ahead", "behind", "identical", "diverged"):
        die(f"{repo}: unexpected comparison '{s}'")
    return s


def verify(p: dict) -> None:
    repo, sha = p["repo"], p["sha"]
    branch = default_branch(repo)
    # The branch must contain the pin. A commit that only exists in a fork is
    # still readable through the parent repository by its hash, so "it's
    # there" isn't enough: it has to be on the branch the project publishes.
    if compare(repo, sha, branch) not in ("ahead", "identical"):
        die(f"{p['name']}: {sha[:12]} isn't on {repo}'s {branch} branch")
    if p["tag"] and tag_commit(repo, p["tag"]) != sha:
        die(f"{p['name']}: {repo}'s tag {p['tag']} isn't {sha[:12]}")


def newest(p: dict) -> tuple[str, str | None]:
    """The newest release, or the default branch's head with none."""
    repo = p["repo"]
    rel = api(f"repos/{repo}/releases/latest", allow_404=True)
    if rel is not None:
        tag = field(rel, "tag_name")
        if not TAG.fullmatch(tag):
            die(f"{repo}: its newest release '{tag[:60]}' isn't a tag like v1.3.0")
        return tag_commit(repo, tag), tag
    branch = default_branch(repo)
    sha = field(api(f"repos/{repo}/commits/{branch}"), "sha")
    if not SHA.fullmatch(sha):
        die(f"{repo}: unexpected head of {branch}")
    return sha, None


def latest(p: dict) -> tuple[str, str | None]:
    """newest(), or the pin itself when that doesn't come after it: an app
    pinned to its branch head that then tags an older commit keeps its pin
    until a release passes it, rather than failing every daily run."""
    sha, tag = newest(p)
    if sha == p["sha"]:
        return sha, tag if tag else p["tag"]
    s = compare(p["repo"], p["sha"], sha)
    if s != "ahead":
        what = tag or f"{sha[:12]}"
        print(f"{p['name']}: {what} is {RELATION[s]} the pin {p['sha'][:12]}; keeping the pin", file=sys.stderr)
        return p["sha"], p["tag"]
    return sha, tag


def log(p: dict, new: str) -> list[str]:
    """One line per commit from the pin to `new`, oldest first. GitHub pages
    a comparison's commits, so every page is read up to LOG_PAGES of them,
    and a list that still isn't whole says so on its last line."""
    lines: list[str] = []
    total = None
    for page in range(1, LOG_PAGES + 1):
        c = api(f"repos/{p['repo']}/compare/{p['sha']}...{new}?per_page=100&page={page}")
        commits = c.get("commits") if isinstance(c, dict) else None
        if total is None:
            total = c.get("total_commits") if isinstance(c, dict) else None
        if not isinstance(commits, list) or not commits:
            break
        for x in commits:
            subject = field(x, "commit", "message").split("\n")[0]
            # Commit subjects are other people's text: printable ASCII only,
            # bounded, and no backticks, so a list shown in a code block stays
            # one (no mentions, links or HTML in a pull request).
            line = re.sub(r"[^ -~]", "?", f"{field(x, 'sha')[:7]} {subject}").replace("`", "'")
            lines.append(line[:120])
        if not isinstance(total, int) or len(lines) >= total:
            break
    if not isinstance(total, int):
        die(f"{p['repo']}: GitHub's comparison has no commit count")
    if len(lines) < total:
        lines.append(f"... and {total - len(lines)} more commits: see the comparison on GitHub")
    return lines


def write(lines: list[str]) -> None:
    """Atomically: a crash leaves the old file or the new one, never half."""
    fd, tmp = tempfile.mkstemp(dir=LOCK.parent, prefix=".atlas-apps.lock.")
    try:
        with os.fdopen(fd, "w", encoding="ascii") as f:
            f.write("\n".join(lines) + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, LOCK)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def set_pin(lines: list[str], p: dict, sha: str, tag: str | None, force: bool = False) -> None:
    if not SHA.fullmatch(sha):
        die("the new commit must be 40 lowercase hex characters")
    if tag is not None and not TAG.fullmatch(tag):
        die(f"'{tag}' isn't a release tag like v1.3.0")
    if sha == p["sha"] and tag == p["tag"]:
        print(f"{p['name']} is already at {sha[:12]}")
        return
    # Pins only move forward, so a bad bump can't quietly take the image back
    # to an older app or onto a side branch.
    # --force skips only this, for an app whose history was rewritten so the
    # old pin is gone; the new pin is still verified.
    if not force and sha != p["sha"]:
        s = compare(p["repo"], p["sha"], sha)
        if s != "ahead":
            die(f"{p['name']}: {sha[:12]} is {RELATION[s]} the pinned {p['sha'][:12]}, not after it"
                " (if the app rewrote its history, `set --force`)")
    new = dict(p, sha=sha, tag=tag)
    verify(new)
    # The columns the file's header lays out.
    line = f"{p['name']:<11}  {p['repo']:<32}  {sha}" + (f"  {tag}" if tag else "")
    lines[p["line"]] = line
    write(lines)
    print(f"{p['name']}: {p['sha'][:12]} -> {sha[:12]}" + (f" ({tag})" if tag else ""))


def fetch(p: dict, dest: str) -> None:
    """A checkout of exactly the pinned commit, reused while it still is one."""
    d = pathlib.Path(dest).resolve()
    if d.parent != ROOT / "build" / "pinned":
        die(f"fetch goes into build/pinned/, not {dest}")
    git = ["git", "-C", str(d), "-c", "advice.detachedHead=false"]
    if (d / ".git").is_dir():
        head = subprocess.run(git + ["rev-parse", "HEAD"], capture_output=True, text=True)
        clean = subprocess.run(git + ["status", "--porcelain"], capture_output=True, text=True)
        if head.stdout.strip() == p["sha"] and clean.returncode == 0 and not clean.stdout:
            return
    # Like CI, build only a pin that checks out.
    verify(p)
    tmp = d.with_name(d.name + ".new")
    subprocess.run(["rm", "-rf", "--", str(tmp)], check=True)
    tmp.mkdir(parents=True)
    g = ["git", "-C", str(tmp), "-c", "advice.detachedHead=false"]
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    done = False
    try:
        subprocess.run(g + ["init", "-q"], check=True, timeout=30)
        subprocess.run(
            g + ["fetch", "-q", "--depth", "1", f"https://github.com/{p['repo']}.git", p["sha"]],
            check=True, timeout=600, env=env,
        )
        subprocess.run(g + ["checkout", "-q", "FETCH_HEAD"], check=True, timeout=120)
        got = subprocess.run(g + ["rev-parse", "HEAD"], capture_output=True, text=True, check=True)
        if got.stdout.strip() != p["sha"]:
            die(f"{p['repo']}: fetched {got.stdout.strip()[:12]}, not the pinned {p['sha'][:12]}")
        subprocess.run(["rm", "-rf", "--", str(d)], check=True)
        tmp.rename(d)
        done = True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        die(f"couldn't fetch {p['repo']} at {p['sha'][:12]}: {e}")
    finally:
        if not done:
            subprocess.run(["rm", "-rf", "--", str(tmp)])


def main(argv: list[str]) -> None:
    if not argv:
        die("usage: list | get NAME | repo NAME | verify | latest NAME | log NAME COMMIT | set [--force] NAME COMMIT [RELEASE] | fetch NAME DIR")
    cmd, args = argv[0], argv[1:]
    lines, pins = read()

    def pin(name: str) -> dict:
        if name not in pins:
            die(f"unknown name '{name}' (one of {', '.join(NAMES)})")
        return pins[name]

    if cmd == "list" and not args:
        for n in NAMES:
            p = pins[n]
            print(n, p["repo"], p["sha"], p["tag"] or "-")
    elif cmd == "get" and len(args) == 1:
        print(pin(args[0])["sha"])
    elif cmd == "repo" and len(args) == 1:
        print(pin(args[0])["repo"])
    elif cmd == "verify" and not args:
        for n in NAMES:
            verify(pins[n])
            print(f"{n}: {pins[n]['sha'][:12]} ok")
    elif cmd == "latest" and len(args) == 1:
        sha, tag = latest(pin(args[0]))
        print(sha, tag or "-")
    elif cmd == "log" and len(args) == 2:
        if not SHA.fullmatch(args[1]):
            die("the commit must be 40 lowercase hex characters")
        print("\n".join(log(pin(args[0]), args[1])))
    elif cmd == "set" and len(args) in (2, 3, 4):
        force = args[0] == "--force"
        if force:
            args = args[1:]
        if len(args) not in (2, 3):
            die("usage: set [--force] NAME COMMIT [RELEASE]")
        set_pin(lines, pin(args[0]), args[1], args[2] if len(args) == 3 and args[2] != "-" else None, force)
    elif cmd == "fetch" and len(args) == 2:
        fetch(pin(args[0]), args[1])
    else:
        die(f"bad command '{' '.join(argv)[:100]}'")


if __name__ == "__main__":
    main(sys.argv[1:])
