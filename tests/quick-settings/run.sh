#!/bin/sh
# Tests the Quick Settings migration (system_files/usr/share/plasma/shells/
# org.kde.plasma.desktop/contents/updates/telamon-20261008-quick-settings.js)
# with a real plasmashell on a private, virtual KWin, in a container: sample
# homes of an existing user, of one the update already ran for, and of one
# with a bar of their own are started with the update pending, and what
# plasmashell wrote back is checked. With no argument: the newest testing
# image plus this repository's update script, Quick Settings widget and
# (Telamon Light's) new-user layout; with an image: that image as it is.
#
#   [OUT=dir] tests/quick-settings/run.sh [IMAGE]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
share=$repo/system_files/usr/share
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
mounts="-v $here:/t:ro"
if [ $# -eq 0 ]; then
	for d in plasma/shells/org.kde.plasma.desktop/contents/updates plasma/plasmoids/org.telamon.quicksettings \
		plasma/look-and-feel/org.telamon.desktop/contents/layouts; do
		mounts="$mounts -v $share/$d:/usr/share/$d:ro"
	done
fi
# OUT=dir keeps what the container wrote (the panel configs plasmashell saved)
if [ -n "${OUT:-}" ]; then
	mkdir -p "$OUT"
	mounts="$mounts -v $OUT:/tmp/res"
fi
# core=0: a crash in the container must not land in the host's core dumps
# shellcheck disable=SC2086
exec podman run --rm --ulimit core=0 --network=none --security-opt label=disable $mounts "$image" bash /t/inner.sh
