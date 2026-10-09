#!/bin/sh
# Static security checks of what the image ships to privileged and per-user
# places (docs/SECURITY.md): systemd units (hardening directives, exposure
# ceilings from `systemd-analyze security`), polkit actions, the sudoers and
# polkit-rules guards, tmpfiles, the kconf_update scripts and the root-run
# scripts. Runs in a container of the published image for its systemd-analyze;
# the repository is mounted read-only. Nothing is installed or started.
#
#   tests/units/run.sh [IMAGE]    (default: the published testing image)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
exec timeout 300 podman run --rm --ulimit core=0 --security-opt label=disable \
	-v "$repo:/repo:ro" "$image" python3 -I /repo/tests/units/check.py /repo
