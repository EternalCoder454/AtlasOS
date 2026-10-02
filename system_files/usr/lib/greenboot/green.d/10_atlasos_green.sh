#!/usr/bin/env bash
# The boot passed its health checks. Never fails.
#  - Tells Atlas Updater's helper once per deployment, on its first good boot,
#    not on every boot. The digest goes in the list of passed ones only when the
#    helper call worked, so a failed call is tried again at the next boot.
#  - A digest that boots healthy is no longer a bad one: it comes off
#    bad-image-digests (a user may have switched back to it on purpose).
state=/var/lib/atlasos
passed=$state/health-passed-digests
bad=$state/bad-image-digests
helper=/usr/libexec/atlas-system-helper
digest=$(timeout 30 bootc status --json 2>/dev/null | jq -r '.status.booted.image.imageDigest // empty' 2>/dev/null)
[ -n "$digest" ] || exit 0
mkdir -p "$state" 2>/dev/null || exit 0

if [ -f "$bad" ] && grep -qxF "$digest" "$bad"; then
	grep -vxF "$digest" "$bad" >|"$bad.new" 2>/dev/null
	mv -f "$bad.new" "$bad" 2>/dev/null || true
fi

if ! grep -qxF "$digest" "$passed" 2>/dev/null; then
	ok=1
	if [ -x "$helper" ]; then
		timeout 30 "$helper" record-event health-check-passed >/dev/null 2>&1 || ok=0
	fi
	if [ "$ok" = 1 ]; then
		# Newest last, at most 20.
		{ cat "$passed" 2>/dev/null; echo "$digest"; } | tail -n 20 >|"$passed.new" 2>/dev/null &&
			mv -f "$passed.new" "$passed" 2>/dev/null || true
	fi
fi
exit 0
