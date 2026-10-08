#!/bin/sh
# Tests the per-user Settings cutover migration (system_files/usr/share/
# kconf_update/telamon-20261007-settings-cutover.sh) on a home with pins of
# KDE's System Settings, inside a container: with no argument, a plain Fedora
# 44 with kconf_update and this repository's kconf_update folder; with an
# image, that image (its own copy of the script, the one that ships).
#
#   tests/settings-cutover/run.sh [IMAGE]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
if [ $# -ge 1 ]; then
	exec podman run --rm --security-opt label=disable -v "$here:/t:ro" "$1" bash /t/inner.sh
fi
exec podman run --rm --security-opt label=disable \
	-v "$here:/t:ro" -v "$repo/system_files/usr/share/kconf_update:/usr/share/kconf_update:ro" \
	registry.fedoraproject.org/fedora:44 bash -c \
	'dnf -y -q install kf6-kconfig diffutils gawk >/dev/null 2>&1; bash /t/inner.sh'
