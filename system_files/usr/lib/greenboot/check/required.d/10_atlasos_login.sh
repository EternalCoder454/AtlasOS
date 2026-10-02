#!/usr/bin/env bash
# Login works: within 180 s of boot plasmalogin.service is active, and the
# greeter (or, with autologin, a Plasma session) has been running for 10 s.
# Runs for up to 190 s of boot time; limit 240 s.
export hc_name=login
# shellcheck source=/dev/null
. /usr/libexec/atlasos/health-lib
hc_guard 240
hc_skip_unless_plasmalogin
hc_set_deadline 190

state=unknown
while :; do
	state=$(systemctl is-active plasmalogin.service 2>/dev/null)
	if [ "$state" = active ]; then
		# shellcheck disable=SC2046
		if pid=$(hc_first_stable $(hc_greeter_pids)); then
			hc_pass "plasmalogin.service active, greeter running (pid $pid)"
		fi
		# shellcheck disable=SC2046
		if pid=$(hc_first_stable $(hc_plasmashell_pids)); then
			hc_pass "plasmalogin.service active, Plasma session running (plasmashell pid $pid)"
		fi
	fi
	hc_expired && break
	sleep 2
done
hc_fail "no login screen or Plasma session within 180 s of boot (plasmalogin.service is ${state:-unknown}; a greeter that keeps exiting does not count)"
