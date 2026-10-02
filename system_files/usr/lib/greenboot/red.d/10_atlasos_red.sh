#!/usr/bin/env bash
# The boot failed its health checks: log which ones. Never fails: greenboot's
# reboot and rollback must go ahead whatever this does.
#
# greenboot retries a failed update with a boot counter (3, 2, 1, 0). Only the
# last failure, counter 0, is the one that rolls the update back, so only that
# one is reported to Atlas Updater's helper (crash reporting), and only that one
# records the image as bad: update-stage-condition won't stage it again.
failed=
for f in /run/atlasos/health/*; do
	[ -f "$f" ] || continue
	line=$(head -n1 "$f" 2>/dev/null)
	case $line in
	FAILED*) failed="${failed:+$failed; }${f##*/} (${line#FAILED: })" ;;
	esac
done
counter=$(grub2-editenv list 2>/dev/null | sed -n 's/^boot_counter=//p')
msg="boot health check failed (boot counter ${counter:-unset}): ${failed:-no AtlasOS check reported}"
echo "atlasos-health: $msg"
logger -t atlasos-health -p daemon.crit "$msg" 2>/dev/null || true

if [ "$counter" = 0 ]; then
	digest=$(timeout 30 bootc status --json 2>/dev/null | jq -r '.status.booted.image.imageDigest // empty' 2>/dev/null)
	if [ -n "$digest" ]; then
		bad=/var/lib/atlasos/bad-image-digests
		if mkdir -p /var/lib/atlasos 2>/dev/null; then
			{ cat "$bad" 2>/dev/null; echo "$digest"; } | tail -n 20 >|"$bad.new" 2>/dev/null &&
				mv -f "$bad.new" "$bad" 2>/dev/null || true
		fi
		logger -t atlasos-health -p daemon.crit "update $digest failed its health checks for the last time; it will be rolled back" 2>/dev/null || true
	fi
	helper=/usr/libexec/atlas-system-helper
	if [ -x "$helper" ]; then
		timeout 30 "$helper" record-event health-check-failed >/dev/null 2>&1 || true
	fi
fi
exit 0
