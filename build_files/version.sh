#!/usr/bin/env bash
# The image's version (IMAGE_VERSION, such as 44.20261003) into os-release, in
# the Containerfile's last step: the version changes every day, and anything
# after the step that takes it is rebuilt whenever it does. build.sh wrote
# "dev" in its place.
set -euxo pipefail

v=${IMAGE_VERSION:?}
f=/usr/lib/os-release
if ! grep -qx 'VERSION="44 (dev)"' "$f" || ! grep -qx 'IMAGE_VERSION="dev"' "$f"; then
	echo "version.sh: $f has no \"dev\" version to replace" >&2
	exit 1
fi
sed -i -e "s/^VERSION=\"44 (dev)\"\$/VERSION=\"44 ($v)\"/" \
	-e "s/^IMAGE_VERSION=\"dev\"\$/IMAGE_VERSION=\"$v\"/" "$f"
grep -qx "IMAGE_VERSION=\"$v\"" "$f"
