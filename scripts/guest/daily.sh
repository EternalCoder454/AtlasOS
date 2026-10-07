#!/bin/sh
# Day-to-day use of a Telamon OS test VM, timed. Run inside the Plasma session
# (scripts/vmlive.py's environment) after scripts/guest/trace.js is loaded
# into KWin, which logs windows opening and panels resizing to the journal.
#
#   daily.sh apps | panel | launcher | theme | idle | all
#
# Times are from the command to KWin mapping the window, so they include the
# app's own start-up but not the first frame's paint.
set -u

now() { date +%s%3N; }

trace_since() { # ms
	journalctl --user -b --no-pager -o cat --since "@$(($1 / 1000 - 1))" |
		awk -v t="$1" '$1 == "ATLASTRACE" && $2 >= t'
}

# Waits up to $3 s for a window whose class matches $2 to open after $1 ms.
# Prints its open time in ms.
wait_window() {
	start=$1 class=$2 limit=$3 i=0
	while [ "$i" -lt $((limit * 10)) ]; do
		t=$(trace_since "$start" | awk -v c="$class" '$3 == "added" && $4 ~ c { print $2; exit }')
		[ -n "$t" ] && {
			echo $((t - start))
			return 0
		}
		sleep 0.1
		i=$((i + 1))
	done
	echo timeout
	return 1
}

cpu_ticks() { awk '/^cpu / { print $2 + $3 + $4 + $7 + $8, $5 + $6 }' /proc/stat; }

# Busy % of all CPUs over $1 s, and the processes that used the most.
busy() {
	set -- "$1" "$(cpu_ticks)"
	ps -eo pid=,comm=,cputimes= | awk '{ print $1, $2, $NF }' | LC_ALL=C sort -k1,1 >/tmp/daily-ps0
	sleep "$1"
	ps -eo pid=,comm=,cputimes= | awk '{ print $1, $2, $NF }' | LC_ALL=C sort -k1,1 >/tmp/daily-ps1
	echo "$2 $(cpu_ticks)" | awk '{ b = $3 - $1; i = $4 - $2; printf "busy %.0f%% of 4 CPUs\n", 100 * b / (b + i) }'
	LC_ALL=C join /tmp/daily-ps0 /tmp/daily-ps1 | awk -v s="$1" '{ d = $5 - $3; if (d > 0) printf "  %-24s %5.2f s CPU\n", $2, d }' |
		sort -k2 -rn | head -6
}

app() { # name, class pattern, command...
	name=$1 class=$2
	shift 2
	for run in cold warm; do
		start=$(now)
		"$@" >/dev/null 2>&1 &
		pid=$!
		ms=$(wait_window "$start" "$class" 60)
		echo "open $name ($run): $ms ms"
		sleep 3
		kill "$pid" 2>/dev/null
		pkill -f "$class" 2>/dev/null
		sleep 2
	done
}

apps() {
	app Files 'dolphin' dolphin
	app Terminal 'ghostty' ghostty
	app Notepad 'notepad' telamon-notepad
	app Settings 'telamon.settings' telamon-settings
	app Store 'discover' plasma-discover
	app Brave 'brave' brave-origin-stable
}

# Restarts plasmashell as a login would start it, and reports how the panels
# came up: when each appeared and every width the dock went through.
panel() {
	start=$(now)
	systemctl --user restart plasma-plasmashell.service
	sleep 12
	trace_since "$start" | awk -v s="$start" '
		$4 == "plasmashell" && ($3 == "added" || $3 == "geom") {
			split($6, wh, "x"); split($5, xy, ",")
			if (xy[2] > 100 && wh[2] < 200) {
				dock = $6
				if (dock != last) printf "  +%5d ms dock %s %s at %s\n", $2 - s, $3, $6, $5
				last = dock; n++; end = $2
			} else if ($3 == "added" && wh[2] < 60)
				printf "  +%5d ms menu bar %s\n", $2 - s, $6
		}
		END { printf "dock size changes: %d, settled at +%d ms\n", n, end - s }'
}

launcher() {
	sleep 2
	start=$(now)
	gdbus call --session -d org.kde.plasmashell -o /PlasmaShell \
		-m org.kde.PlasmaShell.activateLauncherMenu >/dev/null
	sleep 3
	trace_since "$start" | awk -v s="$start" '$3 == "added" { printf "  +%d ms %s %s at %s\n", $2 - s, $4, $6, $5 }'
	echo "dock: $(trace_since 0 | awk '$4 == "plasmashell" { split($5, xy, ","); split($6, wh, "x"); if (xy[2] > 100 && wh[2] < 200) d = $5 " " $6 } END { print d }')"
}

theme() {
	for t in org.telamon.dark.desktop org.telamon.desktop; do
		start=$(now)
		plasma-apply-lookandfeel -a "$t" >/dev/null 2>&1
		echo "apply $t: $(($(now) - start)) ms, then over 8 s:"
		busy 8 | sed 's/^/  /'
	done
}

idle() {
	echo "idle, 30 s:"
	busy 30 | sed 's/^/  /'
	free -m | awk '/^Mem/ { print "  memory used " $3 " MiB, available " $7 " MiB" }'
}

case ${1:-all} in
apps) apps ;;
panel) panel ;;
launcher) launcher ;;
theme) theme ;;
idle) idle ;;
all)
	idle
	panel
	launcher
	apps
	theme
	;;
esac
