#!/usr/bin/env bash
# The boot failed its health checks: log which ones, and tell Atlas Updater's
# helper (crash reporting). Never fails: greenboot's reboot and rollback
# must go ahead whatever this does.
failed=
for f in /run/atlasos/health/*; do
	[ -f "$f" ] || continue
	line=$(head -n1 "$f" 2>/dev/null)
	case $line in
	FAILED*) failed="${failed:+$failed; }${f##*/} (${line#FAILED: })" ;;
	esac
done
msg="boot health check failed: ${failed:-no AtlasOS check reported}"
echo "atlasos-health: $msg"
logger -t atlasos-health -p daemon.crit "$msg" 2>/dev/null || true
helper=/usr/libexec/atlas-system-helper
if [ -x "$helper" ]; then
	timeout 30 "$helper" record-event health-check-failed >/dev/null 2>&1 || true
fi
exit 0
