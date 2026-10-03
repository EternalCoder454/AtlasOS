#!/bin/bash
# Build times on GitHub's runners and on the VPS runner, from build.yml's
# recent successful runs, as Markdown tables for CI.md.
#   scripts/ci-times.sh [runs]     (default: the last 40 runs)
# A job counts as VPS when it ran on a runner labelled atlasos-vps. Jobs that
# skipped the build (scheduled runs with nothing new) are left out.
set -euo pipefail

runs=${1:-40}
repo=${CI_TIMES_REPO:-EternalCoder454/AtlasOS}

ids=$(gh run list -R "$repo" --workflow build.yml --status success -L "$runs" \
    --json databaseId --jq '.[].databaseId')
[ -n "$ids" ] || { echo "No successful runs of build.yml in $repo." >&2; exit 1; }

# One object per image built: runner kind, image, date, run id, seconds for
# the job (or its part for that image) and its Build, Rechunk and Push steps,
# and whether it published. atlasos-nvidia is built in the same job, in the
# steps named "... NVIDIA" (in older runs, a job of its own).
rows=$(for id in $ids; do
    # shellcheck disable=SC2016 # $common is jq's
    gh api "repos/$repo/actions/runs/$id/jobs" --jq '
        def secs(a; b): if a and b then ((b | fromdateiso8601) - (a | fromdateiso8601)) else null end;
        def at(n; f): (.steps // [] | map(select(.name == n and .conclusion == "success")) | first
                       | if . then .[f] else null end);
        def step(n): secs(at(n; "started_at"); at(n; "completed_at"));
        .jobs[]
        | select(.name | startswith("Build and push"))
        | select(.conclusion == "success")
        | {
            kind: (if (.labels | index("atlasos-vps")) then "VPS" else "GitHub-hosted" end),
            run: .run_id,
            date: .started_at[0:10]
          } as $common
        | (select(step("Build") != null)
           | $common + {
               image: (if (.name | test("NVIDIA")) then "atlasos-nvidia" else "atlasos" end),
               job: secs(.started_at; (at("Build NVIDIA"; "started_at") // .completed_at)),
               build: step("Build"),
               rechunk: step("Rechunk"),
               push: step("Push"),
               # Pull requests and tags build and lint only: a shorter job.
               work: (if step("Push") then "build + publish" else "build only" end)
             }),
          (select(step("Build NVIDIA") != null)
           | $common + {
               image: "atlasos-nvidia",
               job: secs(at("Build NVIDIA"; "started_at");
                         (at("Sign NVIDIA"; "completed_at") // at("Push NVIDIA"; "completed_at"))),
               build: step("Build NVIDIA"),
               rechunk: step("Rechunk NVIDIA"),
               push: step("Push NVIDIA"),
               work: "build + publish"
             })'
done | jq -s .)

jq -r '
    def fmt: if . == null then "–" else "\((. / 60) | floor)m \(. % 60 | floor)s" end;
    def median: map(select(. != null)) | sort
        | if length == 0 then null
          elif length % 2 == 1 then .[length / 2 | floor]
          else (.[length / 2 - 1] + .[length / 2]) / 2 end;

    "| Runner | Image | Work | Jobs | Job (median) | Build step | Rechunk | Push |",
    "|---|---|---|---:|---:|---:|---:|---:|",
    (group_by([.image, .work, .kind])[]
     | "| \(.[0].kind) | \(.[0].image) | \(.[0].work) | \(length) | \(map(.job) | median | fmt) | \(map(.build) | median | fmt) | \(map(.rechunk) | median | fmt) | \(map(.push) | median | fmt) |"),
    "",
    "| Date | Run | Runner | Image | Job | Build step | Rechunk | Push |",
    "|---|---|---|---|---:|---:|---:|---:|",
    (sort_by(.run) | reverse[]
     | "| \(.date) | \(.run) | \(.kind) | \(.image) | \(.job | fmt) | \(.build | fmt) | \(.rechunk | fmt) | \(.push | fmt) |")
' <<<"$rows"
