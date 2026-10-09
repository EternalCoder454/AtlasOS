#!/bin/sh
# Tests the PIN sign-in stack (DEV.md, "PIN sign-in") in a container made from
# the published image, with this repository's PIN tools mounted over the image's
# so the tree is what runs. It uses the image's PAM stack and PAM module for
# real: a throwaway user in the container, the verifier on a socket made by
# systemd-socket-activate, and a small libpam client (pamconv.py).
#
#   tests/pin/run.sh [IMAGE]    (default: the published testing image)
#
# What it checks: no PAM service but the lock and login screens ever reaches the
# verifier; the 5-try lockout, the lifetime cap and its decay; who may ask
# about whom (SO_PEERCRED); malformed and incomplete requests; the store (modes,
# yescrypt, salt, nothing in the clear, nothing left behind); that the tools
# refuse weak or unprivileged use; and that a changed or locked password kills
# the PIN. SELinux and the real greeters are not covered.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
tools=$repo/system_files/usr/libexec/telamon
exec timeout 600 podman run --rm --ulimit core=0 --security-opt label=disable \
	-v "$here:/t:ro" \
	-v "$tools/pinlib.py:/usr/libexec/telamon/pinlib.py:ro" \
	-v "$tools/pin-daemon:/usr/libexec/telamon/pin-daemon:ro" \
	-v "$tools/pin-admin:/usr/libexec/telamon/pin-admin:ro" \
	"$image" bash /t/inner.sh
