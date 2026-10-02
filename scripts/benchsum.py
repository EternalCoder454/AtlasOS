#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Summarizes scripts/vmbench.py runs: the median, min and max of each number.

    benchsum.py <out dir> [<baseline out dir>]

Reads <out dir>/run*/result.json and writes <out dir>/summary.json. Given a
baseline, also prints the change in each median, and whether it is larger than
the baseline's own spread (max - min), which is what counts as measurable.
"""

import json
import pathlib
import statistics
import sys

# Lower is better for all of these except available memory.
HIGHER_IS_BETTER = {"mem_available_mib"}


def summarize(d: pathlib.Path) -> dict:
    runs = [json.loads(p.read_text()) for p in sorted(d.glob("run*/result.json"))]
    if not runs:
        sys.exit(f"no run*/result.json in {d}")
    keys = sorted({k for r in runs for k in r})
    out = {"runs": len(runs)}
    for k in keys:
        v = [r[k] for r in runs if k in r]
        out[k] = {"median": statistics.median(v), "min": min(v), "max": max(v)}
    return out


def main() -> None:
    d = pathlib.Path(sys.argv[1])
    s = summarize(d)
    (d / "summary.json").write_text(json.dumps(s, indent=1) + "\n")
    base = summarize(pathlib.Path(sys.argv[2])) if len(sys.argv) > 2 else None
    print(f"{'':28} {'median':>9} {'min':>9} {'max':>9}" + ("  vs baseline" if base else ""))
    for k, v in s.items():
        if k == "runs":
            continue
        line = f"{k:28} {v['median']:9.2f} {v['min']:9.2f} {v['max']:9.2f}"
        if base and k in base:
            b = base[k]
            delta = v["median"] - b["median"]
            better = delta > 0 if k in HIGHER_IS_BETTER else delta < 0
            noise = b["max"] - b["min"]
            verdict = ("better" if better else "worse") if abs(delta) > noise else "within noise"
            line += f"  {delta:+9.2f} ({verdict}; spread {noise:.2f})"
        print(line)
    print(f"runs: {s['runs']}")


if __name__ == "__main__":
    main()
