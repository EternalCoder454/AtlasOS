#!/bin/bash
# Runs a build (its arguments), then removes every package the build
# installed: a builder stage's layer then holds what it built (in /out), not
# its gigabytes of build dependencies. Podman keeps these layers as the build
# cache, and the VPS runner's disk is small (see ci/vps-runner/README.md).
set -euo pipefail

before=$(mktemp)
rpm -qa --qf '%{NAME}\n' | sort -u >"$before"
"$@"
mapfile -t added < <(rpm -qa --qf '%{NAME}\n' | sort -u | comm -13 "$before" -)
rm -f "$before"
# Without their scriptlets: nothing runs in this stage after the build.
if [ ${#added[@]} -gt 0 ]; then
	rpm -e --nodeps --noscripts --notriggers --allmatches "${added[@]}"
fi
