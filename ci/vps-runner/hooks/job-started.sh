#!/bin/bash
# Runs before every job on the VPS runner (ACTIONS_RUNNER_HOOK_JOB_STARTED); a
# non-zero exit fails the job before any of its steps run. It lives in the
# runner image, not in the repository, so a pull request can't change it.
#
# The repository is public. A pull request from a fork runs the workflow from
# the pull request, which could ask for this runner, so only jobs for trusted
# events on trusted refs may run here.
set -euo pipefail

refuse() {
    echo "::error::This runner only builds ${ATLAS_RUNNER_REPO:-?} for pushes, schedules and manual runs on: ${refs}. Refused: $1"
    exit 1
}

# Space-separated shell patterns, matched against GITHUB_REF.
refs=${ATLAS_RUNNER_REFS:-refs/heads/main refs/tags/*}

[ -n "${ATLAS_RUNNER_REPO:-}" ] || refuse "ATLAS_RUNNER_REPO is not set on the runner"
[ "${GITHUB_REPOSITORY:-}" = "$ATLAS_RUNNER_REPO" ] || refuse "repository '${GITHUB_REPOSITORY:-}'"

case ${GITHUB_EVENT_NAME:-} in
push | schedule | workflow_dispatch) ;;
*) refuse "event '${GITHUB_EVENT_NAME:-}'" ;;
esac

ok=false
set -f # the patterns are for GITHUB_REF, not for files
for pattern in $refs; do
    # shellcheck disable=SC2254 # the patterns are meant to match
    case ${GITHUB_REF:-} in $pattern) ok=true ;; esac
done
set +f
[ "$ok" = true ] || refuse "ref '${GITHUB_REF:-}'"

# Clear what an interrupted job left behind and make room for the build
# (atlas-runner-cleanup gives up caches until ATLAS_RUNNER_MIN_FREE_GB is free).
min=${ATLAS_RUNNER_MIN_FREE_GB:-26}
free_gb() { df -P --block-size=1G /home/podman/.local/share/containers | awk 'NR == 2 { print $4 }'; }
atlas-runner-cleanup after-job || true
if [ "$(free_gb)" -lt "$min" ]; then
    echo "::error::Only $(free_gb) GB free on the VPS runner's disk, even with every cache cleared (a build needs ${min} GB)."
    exit 1
fi

echo "VPS runner: ${GITHUB_EVENT_NAME} on ${GITHUB_REF}, $(free_gb) GB free."
