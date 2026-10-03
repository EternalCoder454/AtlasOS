#!/bin/bash
# Runs a build (its arguments), then removes every package the build
# installed: a builder stage's layer then holds what it built (in /out), not
# its gigabytes of build dependencies. Podman keeps these layers as the build
# cache, and the VPS runner's disk is small (see ci/vps-runner/README.md).
set -euo pipefail

before=$(mktemp)
after=$(mktemp)
rpm -qa --qf '%{NAME}\n' | sort -u >"$before"
"$@"
# Into a file, so a failing rpm fails the build instead of removing nothing.
rpm -qa --qf '%{NAME}\n' | sort -u >"$after"
mapfile -t added < <(comm -13 "$before" "$after")
rm -f "$before" "$after"
# Without their scriptlets: nothing runs in this stage after the build.
if [ ${#added[@]} -gt 0 ]; then
	rpm -e --nodeps --noscripts --notriggers --allmatches "${added[@]}"
fi
