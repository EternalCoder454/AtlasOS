#!/bin/bash
# Runs inside the container made by run.sh.
set -uo pipefail
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

IMG=ghcr.io/eternalcoder454/atlasos:testing
export T=/tmp/stage
export PATH=/t/bin:$PATH

# image NAME: the image of a version (its build time and digest)
declare -A TS=(
	[44.20261007-7]=2026-10-07T21:59:19Z
	[44.20261008-1]=2026-10-08T01:15:18Z
	[44.20261008-3]=2026-10-08T05:54:48Z
	[44.20261008-5]=2026-10-08T09:09:32Z
)
digest() { echo "sha256:$(printf '%s' "$1" | sha256sum | cut -c1-64)"; }
image() { # VERSION
	jq -n --arg img "$IMG" --arg v "$1" --arg t "${TS[$1]}" --arg d "$(digest "$1")" \
		'{image: {image: $img, transport: "registry", signature: "containerPolicy"},
		  version: $v, timestamp: $t, imageDigest: $d}'
}
# entry VERSION [CACHED_VERSION]: a bootc status entry; its commit is c-VERSION
entry() {
	local cached=null
	[ -n "${2:-}" ] && cached=$(image "$2")
	jq -n --argjson i "$(image "$1")" --argjson c "$cached" --arg csum "c-$1" \
		'{image: $i, cachedUpdate: $c, incompatible: false, pinned: false,
		  ostree: {checksum: $csum, deploySerial: 0, stateroot: "default"}}'
}
# status STAGED BOOTED ROLLBACK: each "VERSION[+CACHED]" or "-"
status() {
	local out=null
	for pair in "staged:$1" "booted:$2" "rollback:$3"; do
		local key=${pair%%:*} spec=${pair#*:} v c val=null
		if [ "$spec" != - ]; then
			v=${spec%%+*}
			c=""
			[ "$v" != "$spec" ] && c=${spec#*+}
			val=$(entry "$v" "$c")
		fi
		out=$(jq -n --argjson o "$([ "$out" = null ] && echo '{}' || echo "$out")" \
			--arg k "$key" --argjson v "$val" '$o + {($k): $v}')
	done
	jq -n --argjson s "$out" --arg img "$IMG" '{apiVersion: "org.containers.bootc/v1", kind: "BootcHost",
		spec: {image: {image: $img, transport: "registry", signature: "containerPolicy"}},
		status: ($s + {rollbackQueued: false, type: "bootcHost"})}'
}
# rpm STAGED BOOTED ROLLBACK: rpm-ostree status for update-stage's own check
rpm() {
	local list=() v
	for pair in "staged:$1" "booted:$2" "rollback:$3"; do
		local key=${pair%%:*} spec=${pair#*:}
		[ "$spec" = - ] && continue
		v=${spec%%+*}
		list+=("$(jq -n --arg k "$key" --arg v "$v" --arg d "$(digest "$v")" --arg img "$IMG" \
			--argjson t "$(date -u -d "${TS[$v]}" +%s)" \
			'{staged: ($k == "staged"), booted: ($k == "booted"), version: $v, timestamp: $t,
			  "container-image-reference": ("ostree-image-signed:docker://" + $img),
			  "container-image-reference-digest": $d}')")
	done
	printf '%s\n' "${list[@]}" | jq -s '{deployments: .}'
}

# scenario NAME STAGED BOOTED ROLLBACK [AFTER_STAGED]: lay out the machine
scenario() {
	rm -rf "$T" /ostree
	mkdir -p "$T" /ostree/repo/refs/heads/ostree/container/image
	status "$2" "$3" "$4" >"$T/status.json"
	rpm "$2" "$3" "$4" >"$T/rpm.json"
	# the ref of the image points to the commit pulled last: the staged one,
	# else the booted one
	head=${2%%+*}
	[ "$2" = - ] && head=${3%%+*}
	echo "c-$head" >/ostree/repo/refs/heads/ostree/container/image/ref
	if [ -n "${5:-}" ]; then
		status "$5" "$3" "$4" >"$T/status-after.json"
	fi
	echo "== $1"
}
# service: what atlasos-update-stage.service does: the condition, then the stager
service() {
	sh /usr/libexec/telamon/update-stage-condition >"$T/condition.out" 2>&1
	cond=$?
	stage=skipped
	if [ $cond -eq 0 ]; then
		sh /usr/libexec/telamon/update-stage >"$T/stage.out" 2>&1
		stage=$?
	fi
	sed 's/^/    | /' "$T/condition.out" "$T/stage.out" 2>/dev/null
}
called() { grep -qxF -- "$1" "$T/calls" 2>/dev/null; }
staged_version() { jq -r '.status.staged.image.version // "none"' "$T/status.json"; }

scenario "booted -1, -3 staged, -5 published: the newer one replaces the staged one" \
	"44.20261008-3+44.20261008-5" 44.20261008-1 44.20261007-7 44.20261008-5
service
[ "$cond" -eq 0 ] && ok "the condition goes ahead" || bad "the condition skipped (exit $cond)"
called "bootc upgrade --quiet" && ok "bootc upgrade ran" || bad "bootc upgrade did not run"
[ "$stage" = 0 ] && ok "the stager succeeded" || bad "the stager exited $stage"
[ "$(staged_version)" = 44.20261008-5 ] && ok "-5 is staged now" || bad "staged: $(staged_version)"
called "rpm-ostree cleanup -p" && bad "the new staged update was taken out" || ok "nothing taken out"

scenario "-3 staged and nothing newer: goes ahead (bootc says nothing changed), stays -3" \
	44.20261008-3 44.20261008-1 44.20261007-7
service
[ "$cond" -eq 0 ] && ok "the condition goes ahead" || bad "the condition skipped (exit $cond)"
[ "$(staged_version)" = 44.20261008-3 ] && ok "-3 stays staged" || bad "staged: $(staged_version)"
called "rpm-ostree cleanup -p" && bad "the staged update was taken out" || ok "nothing taken out"

scenario "-5 staged, the registry's tag went back to -3: not fetched" \
	"44.20261008-5+44.20261008-3" 44.20261008-1 44.20261007-7
service
[ "$cond" -eq 1 ] && ok "the condition skips" || bad "the condition did not skip (exit $cond)"
called "bootc upgrade --quiet" && bad "bootc upgrade ran" || ok "no bootc upgrade"
[ "$(staged_version)" = 44.20261008-5 ] && ok "-5 stays staged" || bad "staged: $(staged_version)"

scenario "-3 staged, the newest is the image this machine went back from: not fetched" \
	"44.20261008-3+44.20261008-1" 44.20261008-1 44.20261008-1
service
[ "$cond" -eq 1 ] && ok "the condition skips" || bad "the condition did not skip (exit $cond)"

# a system with local rpm-ostree changes: bootc can't check or upgrade it, so the
# stager asks the registry with skopeo and upgrades with rpm-ostree
scenario "local rpm-ostree changes, -3 staged, -5 published: the newer one replaces the staged one" \
	44.20261008-3 44.20261008-1 44.20261007-7 44.20261008-5
jq '.status.booted.incompatible = true | .status.staged.incompatible = true' "$T/status.json" >"$T/s" && mv "$T/s" "$T/status.json"
rpm 44.20261008-5 44.20261008-1 44.20261007-7 >"$T/rpm-after.json"
jq -n --arg v 44.20261008-5 --arg d "$(digest 44.20261008-5)" '{Digest: $d, Created: "2026-10-08T09:09:32Z",
	Labels: {"org.opencontainers.image.version": $v}}' >"$T/skopeo.json"
service
[ "$cond" -eq 0 ] && ok "the condition goes ahead" || bad "the condition skipped (exit $cond)"
called "rpm-ostree upgrade" && ok "rpm-ostree upgrade ran" || bad "rpm-ostree upgrade did not run"
[ "$stage" = 0 ] && ok "the stager succeeded" || bad "the stager exited $stage"
[ "$(jq -r '[.deployments[] | select(.staged)][0].version' "$T/rpm.json")" = 44.20261008-5 ] &&
	ok "-5 is staged now" || bad "staged: $(jq -r '[.deployments[] | select(.staged)][0].version' "$T/rpm.json")"
called "rpm-ostree cleanup -p" && bad "the new staged update was taken out" || ok "nothing taken out"

scenario "local rpm-ostree changes, -5 staged, the registry's tag went back to -3: not fetched" \
	44.20261008-5 44.20261008-1 44.20261007-7
jq '.status.booted.incompatible = true | .status.staged.incompatible = true' "$T/status.json" >"$T/s" && mv "$T/s" "$T/status.json"
jq -n --arg v 44.20261008-3 --arg d "$(digest 44.20261008-3)" '{Digest: $d, Created: "2026-10-08T05:54:48Z",
	Labels: {"org.opencontainers.image.version": $v}}' >"$T/skopeo.json"
service
[ "$cond" -eq 1 ] && ok "the condition skips" || bad "the condition did not skip (exit $cond)"
called "rpm-ostree upgrade" && bad "rpm-ostree upgrade ran" || ok "no rpm-ostree upgrade"

[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
