#!/usr/bin/env python3
"""How much an update downloads: the compressed bytes of the layers a machine
on an older build does not have yet.

    update-size.py [options] NEW [OLD ...]
    update-size.py [options] NEW --history REPO [--history REPO ...]
    update-size.py --series OLDEST ... NEWEST

An image is a registry reference (ghcr.io/org/name:tag, or docker://...), or
anything skopeo reads: oci:DIR:TAG, oci-archive:FILE, containers-storage:REF.

bootc keeps every layer it has imported and skips a layer whose digest it has
already (plain zstd layers, one digest per content), so the download for a
machine on OLD is the sum of the sizes of NEW's layers whose digest is not in
OLD. Layers are named by what chunkah put in them (the image config's history
comment: an RPM's source package, or an xattr/bigfiles component).

--history REPO picks the older builds to compare with out of REPO's tags
(testing-44.YYYYMMDD[-N] by default, see --prefix), by NEW's version: the
previous build, the newest one at least 7 days older, and the newest at least
28 days older. The option repeats (a repository renamed since some builds
were pushed); the first one that has a version wins.

Needs skopeo; registry login is whatever skopeo already uses
(REGISTRY_AUTH_FILE). Nothing is downloaded but manifests and image configs
(a few tens of KB each).
"""

import argparse
import datetime
import json
import re
import subprocess
import sys
import time

VERSION = re.compile(r"(44\.(\d{8})(?:-(\d+))?)$")
TRANSPORTS = ("docker://", "oci:", "oci-archive:", "dir:", "containers-storage:",
              "docker-archive:", "docker-daemon:")


def die(msg: str) -> "None":
    sys.exit(f"update-size: {msg}")


def skopeo(*args: str) -> str:
    """skopeo's stdout; a registry hiccup is retried."""
    err = ""
    for attempt in range(3):
        r = subprocess.run(["skopeo", *args], capture_output=True, text=True)
        if r.returncode == 0:
            return r.stdout
        err = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else f"exit {r.returncode}"
        if attempt < 2:
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"skopeo {' '.join(args[:2])}: {err}")


def ref_of(ref: str) -> str:
    return ref if ref.startswith(TRANSPORTS) else "docker://" + ref


def version_key(v: str) -> tuple[int, int]:
    m = VERSION.search(v)
    return (int(m.group(2)), int(m.group(3) or 0)) if m else (0, 0)


def version_date(v: str) -> datetime.date:
    return datetime.datetime.strptime(VERSION.search(v).group(2), "%Y%m%d").date()


class Image:
    """One image's layers: digest, compressed size, diff_id, what is in it."""

    def __init__(self, ref: str, name: str = ""):
        self.ref = ref_of(ref)
        raw = json.loads(skopeo("inspect", "--raw", self.ref))
        if "manifests" in raw:  # an index: the amd64 image
            pick = [m for m in raw["manifests"]
                    if (m.get("platform") or {}).get("architecture") in (None, "amd64")]
            if not pick:
                raise RuntimeError(f"{ref}: no amd64 image in the index")
            base = self.ref.split("@")[0]
            if base.startswith("docker://"):
                base = re.sub(r":[^:/]+$", "", base)
            raw = json.loads(skopeo("inspect", "--raw", f"{base}@{pick[0]['digest']}"))
        cfg = json.loads(skopeo("inspect", "--config", self.ref))
        diffs = cfg.get("rootfs", {}).get("diff_ids", [])
        hist = [h for h in cfg.get("history", []) if not h.get("empty_layer")]
        self.labels = (cfg.get("config") or {}).get("Labels") or {}
        self.version = self.labels.get("org.opencontainers.image.version", "")
        self.name = name or self.version or ref
        self.layers = []
        for i, layer in enumerate(raw["layers"]):
            h = hist[i] if len(hist) == len(raw["layers"]) else {}
            what = (layer.get("annotations") or {}).get("org.chunkah.component") \
                or h.get("comment") or h.get("created_by") or ""
            self.layers.append({
                "digest": layer["digest"],
                "size": layer["size"],
                "diff_id": diffs[i] if i < len(diffs) else "",
                "what": what,
            })
        self.size = sum(layer["size"] for layer in self.layers)


def compare(new: Image, old: Image) -> dict:
    """What a machine on `old` downloads for `new`."""
    have = {layer["digest"] for layer in old.layers}
    have_diffs = {layer["diff_id"] for layer in old.layers if layer["diff_id"]}
    fresh = [layer for layer in new.layers if layer["digest"] not in have]
    # Same content under a new digest (another compressor, or another
    # version of it): the download that cost nothing in content.
    recompressed = [layer for layer in fresh if layer["diff_id"] in have_diffs]
    fresh_bytes = sum(layer["size"] for layer in fresh)
    return {
        "old": old.name,
        "old_ref": old.ref,
        "bytes": fresh_bytes,
        "layers": len(fresh),
        "of_layers": len(new.layers),
        "share": fresh_bytes / new.size if new.size else 0.0,
        "recompressed_bytes": sum(layer["size"] for layer in recompressed),
        "recompressed_layers": len(recompressed),
        "top": sorted(fresh, key=lambda layer: -layer["size"]),
    }


def tags_of(repo: str, prefix: str) -> dict[str, str]:
    """version -> tag, for the repository's `prefix`44.YYYYMMDD[-N] tags."""
    out = {}
    for tag in json.loads(skopeo("list-tags", ref_of(repo)))["Tags"]:
        if tag.startswith(prefix) and not tag.startswith("sha256-"):
            m = VERSION.fullmatch(tag[len(prefix):])
            if m:
                out[m.group(1)] = tag
    return out


def pick_baselines(version: str, repos: list[str], prefix: str) -> list[tuple[str, str, str]]:
    """(label, version, reference) of the previous build and the newest ones
    at least 7 and 28 days older than `version`."""
    found: dict[str, str] = {}
    for repo in repos:
        try:
            for v, tag in tags_of(repo, prefix).items():
                found.setdefault(v, f"{repo}:{tag}")
        except (RuntimeError, KeyError, json.JSONDecodeError) as e:
            print(f"update-size: {repo}: {e}", file=sys.stderr)
    older = sorted((v for v in found if version_key(v) < version_key(version)),
                   key=version_key)
    if not older:
        return []
    today = version_date(version)
    wanted = [("the previous build", older[-1])]
    for days, label in ((7, "a week earlier"), (28, "four weeks earlier")):
        cand = [v for v in older if (today - version_date(v)).days >= days]
        if cand:
            wanted.append((label, cand[-1]))
    merged: list[list[str]] = []
    for label, v in wanted:  # one row per build: "previous build, a week earlier"
        for row in merged:
            if row[1] == v:
                row[0] += " and " + label.removeprefix("the ")
                break
        else:
            merged.append([label, v])
    return [(label, v, found[v]) for label, v in merged]


def mb(n: float) -> str:
    return f"{n / 1e6:,.1f} MB" if n < 1e9 else f"{n / 1e9:,.2f} GB"


def mb0(n: float) -> str:
    return f"{n / 1e6:,.0f} MB" if n < 1e9 else f"{n / 1e9:,.1f} GB"


def what(layer: dict, width: int = 70) -> str:
    names = layer["what"].split()
    s = " ".join(names[:3]) + (f" and {len(names) - 3} more" if len(names) > 3 else "")
    return s if len(s) <= width else s[: width - 1] + "…"


def render_text(new: Image, rows: list[dict], top: int, notes: list[str]) -> str:
    out = [f"{new.name}: {len(new.layers)} layers, {mb(new.size)}"]
    for r in rows:
        extra = ""
        if r["recompressed_layers"]:
            extra = f"; {mb(r['recompressed_bytes'])} of it is content the old image has (new digest)"
        out.append(f"  from {r['label']} ({r['old']}): {mb(r['bytes'])} in "
                   f"{r['layers']} of {r['of_layers']} layers ({r['share']:.0%}){extra}")
    for r in rows[:1] + [x for x in rows[1:] if x["label"].startswith("a week")]:
        if r["top"]:
            out.append(f"Biggest new layers from {r['label']}:")
            for layer in r["top"][:top]:
                out.append(f"  {mb(layer['size']):>10}  {what(layer)}")
    out += notes
    return "\n".join(out)


def render_markdown(new: Image, rows: list[dict], top: int, notes: list[str]) -> str:
    out = [f"### Update size: {new.name}", "",
           f"The image is {mb(new.size)} in {len(new.layers)} layers. A machine on an older build "
           "downloads the layers it does not have:", "",
           "| From | Download | New layers | Share of the image |", "|---|---:|---:|---:|"]
    for r in rows:
        out.append(f"| {r['label']} (`{r['old']}`) | {mb(r['bytes'])} | "
                   f"{r['layers']} of {r['of_layers']} | {r['share']:.0%} |")
    for r in rows:
        if r["recompressed_layers"]:
            out.append("")
            out.append(f"{mb(r['recompressed_bytes'])} of the download from {r['label']} is "
                       "content the old image has under another digest (compressed differently).")
    for r in rows[:1] + [x for x in rows[1:] if x["label"].startswith("a week")]:
        if r["top"]:
            out += ["", f"Biggest new layers from {r['label']}:", "",
                    "| Size | What is in it |", "|---:|---|"]
            out += [f"| {mb(layer['size'])} | {what(layer).replace('|', '/')} |"
                    for layer in r["top"][:top]]
    out += [""] + [f"> {n}" for n in notes] if notes else []
    return "\n".join(out)


def line(rows: list[dict]) -> str:
    if not rows:
        return ""
    s = f"Download size: {mb0(rows[0]['bytes'])} from the previous build"
    week = next((r for r in rows if "week earlier" in r["label"] and "previous" not in r["label"]), None)
    if week:
        s += f", {mb0(week['bytes'])} from the build a week earlier"
    return s + "."


def series(refs: list[str], top: int) -> str:
    imgs = [Image(r) for r in refs]
    out = [f"{'from':<24} {'to':<24} {'download':>11} {'layers':>9} {'share':>6}   image"]
    total = 0
    for a, b in zip(imgs, imgs[1:]):
        c = compare(b, a)
        total += c["bytes"]
        out.append(f"{a.name:<24} {b.name:<24} {mb(c['bytes']):>11} "
                   f"{c['layers']:>4}/{c['of_layers']:<4} {c['share']:>6.0%}   {mb(b.size)}")
    n = len(imgs) - 1
    if n:
        sizes = sorted(compare(b, a)["bytes"] for a, b in zip(imgs, imgs[1:]))
        median = sizes[n // 2] if n % 2 else (sizes[n // 2 - 1] + sizes[n // 2]) / 2
        out.append(f"{n} updates: median {mb(median)}, mean {mb(total / n)}, total {mb(total)}")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("images", nargs="+", metavar="IMAGE",
                    help="NEW then the older images to compare with (--series: oldest first)")
    ap.add_argument("--history", action="append", default=[], metavar="REPO",
                    help="pick older builds out of this repository's tags (repeatable)")
    ap.add_argument("--prefix", default="testing-",
                    help="the tag prefix of the builds to compare with (default testing-)")
    ap.add_argument("--version", help="NEW's version, when it has no version label")
    ap.add_argument("--top", type=int, default=10, help="biggest new layers to list")
    ap.add_argument("--format", choices=("text", "markdown", "json"), default="text")
    ap.add_argument("--line", action="store_true",
                    help="print only the changelog line (Download size: ...)")
    ap.add_argument("--series", action="store_true",
                    help="IMAGEs are consecutive builds, oldest first: the table of updates")
    ap.add_argument("--warn-mb", type=float, metavar="MB",
                    help="a GitHub Actions warning when the download from the previous build is larger")
    args = ap.parse_args()

    if args.series:
        print(series(args.images, args.top))
        return

    try:
        new = Image(args.images[0])
    except RuntimeError as e:
        die(str(e))
    version = args.version or new.version
    labelled = [(f"build {i + 1}", Image(r).version or r, r) for i, r in enumerate(args.images[1:])]
    notes: list[str] = []
    picks: list[tuple[str, str, str]] = []
    if args.history:
        if not VERSION.search(version):
            die(f"--history needs NEW's version (44.YYYYMMDD-N); the image has '{version}'")
        picks = pick_baselines(version, args.history, args.prefix)
        if not picks:
            notes.append(f"No earlier {args.prefix}44.* build to compare with.")
    picks = [("the previous build", v, r) for _, v, r in labelled[:1]] + \
            [(f"build {v}", v, r) for _, v, r in labelled[1:]] + picks
    rows = []
    for label, v, ref in picks:
        try:
            r = compare(new, Image(ref, name=v))
        except RuntimeError as e:
            notes.append(f"{label} ({v}): {e}")
            continue
        r["label"] = label
        rows.append(r)

    if args.warn_mb and rows and rows[0]["bytes"] > args.warn_mb * 1e6:
        print(f"::warning title=Large update::{new.name} is {mb0(rows[0]['bytes'])} to download from "
              f"{rows[0]['old']}, over the {args.warn_mb:,.0f} MB budget", file=sys.stderr)
    if args.line:
        print(line(rows))
    elif args.format == "json":
        print(json.dumps({"image": new.name, "size": new.size, "layers": len(new.layers),
                          "from": [{k: v for k, v in r.items() if k != "top"} |
                                   {"top": [{"size": x["size"], "what": x["what"]} for x in r["top"][:args.top]]}
                                   for r in rows]}, indent=1))
    elif args.format == "markdown":
        print(render_markdown(new, rows, args.top, notes))
    else:
        print(render_text(new, rows, args.top, notes))


if __name__ == "__main__":
    main()
