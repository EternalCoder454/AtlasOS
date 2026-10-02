#!/usr/bin/env bash
# The boot passed its health checks: tell Atlas Updater's helper. Never fails.
helper=/usr/libexec/atlas-system-helper
if [ -x "$helper" ]; then
	timeout 30 "$helper" record-event health-check-passed >/dev/null 2>&1 || true
fi
exit 0
