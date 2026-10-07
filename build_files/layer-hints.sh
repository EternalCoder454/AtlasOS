#!/usr/bin/env bash
# What chunkah needs to know to make good layers (`just rechunk` runs this
# in a throwaway copy of the built image, before the image is split). It
# changes no file's contents: only times, and the user.component and
# user.update-interval attributes chunkah reads (see its README, "Customizing
# the layers"). A file with user.component belongs to that component instead of
# its RPM's; user.update-interval says how often the component changes, which
# decides which others it is packed with (a daily one goes with the other
# fast-moving ones, so it can't make a layer of stable packages new).
#
#     layer-hints.sh [system_files directory]
set -euo pipefail

# Times. A layer carries each file's and directory's time, and chunkah gives
# a directory the time of the newest thing it holds, so one directory with a
# time from this build (/etc, /var, /run: whatever a build step or the
# container runtime touched last, past cleanup.sh) made every layer with a
# file under it new in every build, even when its files were identical (about
# 115 MB of every update). Every time is 0, as on an installed system.
# (Not what the container runtime mounts in: /proc, /sys, /dev, /run's contents
# and this script's own mounts. /run itself and /dev are directories of the image.)
find / -xdev \( -path /proc -o -path /sys -o -path /hints -o -path '/run/*' -o -path '/dev/*' \) -prune \
	-o -newermt @1 -exec touch -h -d @0 {} +

# mark COMPONENT INTERVAL FILE...: regular files only (the kernel refuses
# user.* attributes on symlinks; a symlink stays with its RPM, which is fine:
# it is a few bytes). The interval needs to be on one file of the component.
mark() {
	local component=$1 interval=$2 f first=1
	shift 2
	for f in "$@"; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		setfattr -n user.component -v "$component" "$f"
		if [ -n "$first" ]; then
			setfattr -n user.update-interval -v "$interval" "$f"
			first=
		fi
	done
}

# The locale archive: 233 MB that is the same for every glibc build (a layer
# of its own, instead of the 52 MB glibc's every update re-sent with it).
# Both names are one file.
mark locale-archive quarterly /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.real

# The version stamps: os-release is a file of fedora-release, and
# telamon-release one of nothing, that change in every build. Alone, they
# stay out of the layer of every package that happens to share one with them.
mark telamon-version daily /usr/lib/os-release /usr/lib/telamon-release

# Telamon's own RPMs, by their source package (telamon-framework-2.0.0-1.fc44.src.rpm):
# the framework (fonts, Telamon.Ui) changes with a new version of itself, each
# app with its own releases. They are named for what changes them, apart from
# Fedora's packages (a rebuilt KIO keeps Fedora's name, and stays one of them).
declare -A files=()
while IFS=$'\t' read -r name srpm; do
	case $srpm in
	telamon-*.src.rpm) ;;
	*) continue ;;
	esac
	source=${srpm%.src.rpm}
	source=${source%-*}
	source=${source%-*}
	files[$source]+="$(rpm -ql "$name" | tr '\n' '\t')"
done < <(rpm -qa --qf '%{NAME}\t%{SOURCERPM}\n' | sort)
for source in "${!files[@]}"; do
	interval=weekly
	[ "$source" = telamon-framework ] && interval=monthly
	IFS=$'\t' read -r -a list <<<"${files[$source]}"
	mark "$source" "$interval" "${list[@]}"
done

# Telamon's own configuration, the files of system_files, which change with
# most commits.
if [ -d "${1:-}" ]; then
	list=()
	while IFS= read -r -d '' f; do
		list+=("/${f#./}")
	done < <(cd "$1" && find . -type f -print0 | sort -z)
	mark telamon-system daily "${list[@]}"
fi
