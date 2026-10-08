#!/bin/sh
# Tests kvantum-sync and the colour scheme migration for a user whose
# kdeglobals has the Dark colours but no [General] ColorScheme (the name is in
# kdedefaults), inside a container. This repository's copies of the scripts
# are mounted over the image's, so the test runs what is in the tree.
#
#   tests/colorscheme/run.sh [IMAGE]    (default: the published testing image)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
exec podman run --rm --security-opt label=disable \
	-v "$here:/t:ro" \
	-v "$repo/system_files/usr/libexec/telamon/kvantum-sync:/usr/libexec/telamon/kvantum-sync:ro" \
	-v "$repo/system_files/usr/share/kconf_update:/usr/share/kconf_update:ro" \
	"$image" bash /t/inner.sh
