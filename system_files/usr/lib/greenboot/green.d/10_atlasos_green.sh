#!/usr/bin/env bash
# The boot passed its health checks. Tell Atlas Updater's helper once per
# deployment, on its first good boot, not on every boot. Never fails.
digest=$(timeout 30 bootc status --json 2>/dev/null | jq -r '.status.booted.image.imageDigest // empty' 2>/dev/null)
stamp=/var/lib/atlasos/health-passed-digest
helper=/usr/libexec/atlas-system-helper
if [ -n "$digest" ] && [ "$digest" != "$(cat "$stamp" 2>/dev/null)" ]; then
	if [ -x "$helper" ]; then
		timeout 30 "$helper" record-event health-check-passed >/dev/null 2>&1 || true
	fi
	mkdir -p /var/lib/atlasos 2>/dev/null && echo "$digest" >|"$stamp" 2>/dev/null || true
fi
exit 0
