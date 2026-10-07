#!/usr/bin/env bash
# Plasma works. With a user's graphical session up (logind's word: see
# hc_graphical_uids), that user's plasmashell and kwin_wayland are running for
# 10 s and neither has restarted twice or more (one restart is tolerated: a
# single crash is not a bad update); one healthy session is enough. Without
# one, the greeter, a Plasma/QML app on its own kwin, counts if it and that
# kwin have run for 10 s and plasmalogin.service has not restarted twice.
# Limit: a greeter that runs does not prove a session would start.
# Waits until 240 s after boot at most; limit 300 s.
export hc_name=plasma
# shellcheck source=/dev/null
. /usr/libexec/telamon/health-lib
hc_guard 300
hc_skip_unless_plasmalogin
hc_set_deadline 240

# Restart count of a unit in user $1's systemd; empty when it can't be read.
restarts() { # uid, unit
	timeout 10 systemctl --user -M "$1@.host" show -p NRestarts --value "$2" 2>/dev/null
}

why="Plasma is not up"
while :; do
	uids=$(hc_graphical_uids)
	if [ -n "$uids" ]; then
		why=
		for uid in $uids; do
			# shellcheck disable=SC2046
			shell=$(hc_first_stable $(hc_pids_of /usr/bin/plasmashell "$uid")) || {
				why="${why:+$why; }no plasmashell of uid $uid running for 10 s"
				continue
			}
			# shellcheck disable=SC2046
			kwin=$(hc_first_stable $(hc_pids_of /usr/bin/kwin_wayland "$uid")) || {
				why="${why:+$why; }plasmashell runs but kwin_wayland of uid $uid is missing or too young"
				continue
			}
			r1=$(restarts "$uid" plasma-plasmashell.service)
			r2=$(restarts "$uid" plasma-kwin_wayland.service)
			if [ "${r1:-0}" -ge 2 ] || [ "${r2:-0}" -ge 2 ]; then
				why="${why:+$why; }Plasma of uid $uid keeps restarting (plasmashell ${r1:-?}, kwin_wayland ${r2:-?} restarts)"
				continue
			fi
			hc_pass "uid $uid: plasmashell (pid $shell) and kwin_wayland (pid $kwin) running, restarts ${r1:-?}/${r2:-?}"
		done
	else
		# No user session: the greeter and the greeter's own kwin, both
		# running for 10 s, and plasmalogin.service not restarting.
		# shellcheck disable=SC2046
		pid=$(hc_first_stable $(hc_greeter_pids)) || pid=
		# shellcheck disable=SC2046
		gk=$(hc_first_stable $(hc_pids_of /usr/bin/kwin_wayland plasmalogin) $(hc_pids_of /usr/bin/kwin_wayland_wrapper plasmalogin)) || gk=
		if [ -n "$pid" ] && [ -n "$gk" ]; then
			r=$(systemctl show -p NRestarts --value plasmalogin.service 2>/dev/null)
			if [ "${r:-0}" -ge 2 ]; then
				hc_fail "plasmalogin.service keeps restarting ($r restarts)"
			fi
			hc_pass "no user session; greeter (pid $pid) and its kwin_wayland running, plasmalogin restarts ${r:-?}"
		fi
		why="no stable greeter or greeter kwin_wayland"
	fi
	hc_expired && break
	hc_sleep 2
done
hc_fail_graphical "$why"
