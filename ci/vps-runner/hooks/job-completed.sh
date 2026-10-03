#!/bin/bash
# Runs after every job on the VPS runner (ACTIONS_RUNNER_HOOK_JOB_COMPLETED).
# Podman's images and layers stay between builds; that is the cache.
# atlas-runner-cleanup (cleanup.sh here) removes what the next build can't use.
atlas-runner-cleanup after-job
exit 0
