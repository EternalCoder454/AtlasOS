#!/bin/sh
# Tests the background stager (system_files/usr/libexec/telamon/update-stage and
# update-stage-condition, run by atlasos-update-stage.service) against recorded
# `bootc status --json` shapes with bootc, rpm-ostree and skopeo replaced by
# stand-ins (tests/update-stage/bin), inside a plain Fedora 44 container with
# this repository's scripts. The question: a deployment is already staged and a
# newer image is published; does the stager fetch the newer one (bootc upgrade
# replaces the staged deployment), and does it still refuse an older one?
#
#   tests/update-stage/run.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
exec podman run --rm --security-opt label=disable --ulimit core=0 \
	-v "$here:/t:ro" \
	-v "$repo/system_files/usr/libexec/telamon:/usr/libexec/telamon:ro" \
	-v "$repo/system_files/usr/share/telamon:/usr/share/telamon:ro" \
	registry.fedoraproject.org/fedora:44 bash -c \
	'dnf -y -q install jq >/dev/null 2>&1; bash /t/inner.sh'
