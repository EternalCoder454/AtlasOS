#!/usr/bin/env bash
# Writes the Markdown release notes for one stable build to stdout: the commits
# since the previous stable tag, grouped by what they touched.
#
#   release-notes.sh <version> <revision> [<previous tag>] [<updater revision>] [<base image>]
#
# Run inside a full clone (the tags and <revision> must be there). With no
# previous tag (the first stable) it lists the newest commits up to <revision>.
set -euo pipefail

version=${1:?version}
revision=${2:?revision}
prev=${3:-}
updater=${4:-}
base=${5:-}
max=100

if [ -n "$prev" ]; then
	range="${prev}..${revision}"
	intro="Changes since \`${prev}\`."
else
	range="${revision}"
	intro="The first stable release. The newest ${max} commits, at most."
fi

# One group per commit: the first of these that any of its files falls under.
group_of() { # commit
	local files
	files=$(git diff-tree --no-commit-id --name-only -r --root "$1")
	if grep -q '^system_files/' <<<"$files"; then
		echo "Desktop and settings"
	elif grep -q '^build_files/' <<<"$files"; then
		echo "Packages and services"
	else
		echo "Build, CI and docs"
	fi
}

declare -A body=()
total=0
while read -r sha subject; do
	total=$((total + 1))
	[ "$total" -le "$max" ] || continue
	g=$(group_of "$sha")
	body[$g]+="- ${subject} (\`${sha:0:7}\`)"$'\n'
done < <(git log --no-merges --format='%H %s' "$range")

echo "# Telamon OS ${version}"
echo
echo "$intro"
echo
if [ "$total" -eq 0 ]; then
	echo "No changes to the Telamon OS repository; this build picked up Fedora's updates."
	echo
fi
for g in "Desktop and settings" "Packages and services" "Build, CI and docs"; do
	[ -n "${body[$g]:-}" ] || continue
	echo "## $g"
	echo
	printf '%s\n' "${body[$g]}"
done
[ "$total" -le "$max" ] || echo "And $((total - max)) older commits."$'\n'

echo "## Built from"
echo
echo "- Telamon OS \`${revision:0:7}\`"
[ -z "$updater" ] || echo "- Telamon Updater \`${updater:0:7}\`"
[ -z "$base" ] || echo "- Base image \`${base}\`"
