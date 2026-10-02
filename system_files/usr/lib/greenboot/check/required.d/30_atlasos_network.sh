#!/usr/bin/env bash
# Networking works: NetworkManager.service is active and nmcli gets an answer
# from it. A network connection is not required: offline is not a failed
# boot. Waits until 90 s after boot at most; limit 120 s.
export hc_name=network
# shellcheck source=/dev/null
. /usr/libexec/atlasos/health-lib
hc_guard 120

case "$(systemctl is-enabled NetworkManager.service 2>/dev/null)" in
enabled | enabled-runtime | alias | static) ;;
*) hc_pass "skipped, NetworkManager.service is not enabled" ;;
esac
hc_set_deadline 90

state=unknown
while :; do
	state=$(systemctl is-active NetworkManager.service 2>/dev/null)
	if [ "$state" = active ] && timeout 10 nmcli general status >/dev/null 2>&1; then
		hc_pass "NetworkManager.service active, nmcli answers"
	fi
	hc_expired && break
	sleep 2
done
hc_fail "NetworkManager.service is ${state:-unknown} or nmcli does not answer"
