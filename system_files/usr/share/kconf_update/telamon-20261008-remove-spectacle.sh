#!/bin/sh
# Telamon Screenshot replaced KDE Spectacle: the shortcuts a user changed for
# Spectacle move to Telamon Screenshot, once, under the same names (its desktop
# actions have Spectacle's ids on purpose).
#
#   [org.kde.spectacle.desktop]  ->  [net.eterneon.telamon.screenshot.desktop]
#   _launch (Print), FullScreenScreenShot, CurrentMonitorScreenShot,
#   ActiveWindowScreenShot, RectangularRegionScreenShot,
#   WindowUnderCursorScreenShot, OpenWithoutScreenshot
#
# in kglobalshortcutsrc, in both forms kglobalaccel writes: the component's own
# group, and the [services][...] one a launcher shortcut from a .desktop file
# is kept in. The recording shortcuts (RecordRegion, RecordScreen, RecordWindow)
# stay where they are: Telamon Screenshot does not record.
#
#   - Only shortcuts the user changed move (a different key, or none). One
#     that is still Spectacle's own default is dropped: kglobalaccel keeps what
#     it stored over a new default, so moving it would hide Telamon
#     Screenshot's own (Meta+Shift+S also takes a region).
#   - A shortcut the user already set for Telamon Screenshot wins; the
#     Spectacle one is dropped. The exception is the launch shortcut still at
#     the value an earlier Telamon Screenshot gave it (Meta+Shift+S, now an
#     action's): that one is not a choice, and goes, so Print is the launch
#     shortcut again.
#
# Runs as the user, before KWin and the shell read their settings (see
# atlasos-kconf-update.service). Safe to run twice. The file is copied first to
# ~/.local/state/telamon/migrated-from-atlasos/ (once, never over an earlier
# copy), as the rename migration does.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}/telamon/migrated-from-atlasos
ks=$cfg/kglobalshortcutsrc

[ -f "$ks" ] || exit 0

new=$(mktemp "$(dirname "$ks")/.telamon-spectacle.XXXXXX") || exit 0
trap 'rm -f "$new"' EXIT

awk '
	# One config line a field at a time: commas split, a backslash keeps the
	# next character (an escaped comma or tab belongs to the shortcut).
	function fields(s, out,    n, i, c, cur) {
		n = 0; cur = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\\") { cur = cur c substr(s, i + 1, 1); i++ }
			else if (c == ",") { out[++n] = cur; cur = "" }
			else cur = cur c
		}
		out[++n] = cur
		return n
	}
	BEGIN {
		nk = split("_launch FullScreenScreenShot CurrentMonitorScreenShot ActiveWindowScreenShot RectangularRegionScreenShot WindowUnderCursorScreenShot OpenWithoutScreenshot", K, " ")
		# The defaults of Spectacle 6.7: a key still at one was not changed.
		sdef["_launch"] = "Print"
		sdef["FullScreenScreenShot"] = "Shift+Print"
		sdef["CurrentMonitorScreenShot"] = "none"
		sdef["ActiveWindowScreenShot"] = "Meta+Print"
		sdef["RectangularRegionScreenShot"] = "Meta+Shift+Print"
		sdef["WindowUnderCursorScreenShot"] = "Meta+Ctrl+Print"
		sdef["OpenWithoutScreenshot"] = "none"
		# Telamon Screenshot defaults and action names (its .desktop file).
		ndef["_launch"] = "Print"
		ndef["FullScreenScreenShot"] = "Shift+Print"
		ndef["CurrentMonitorScreenShot"] = "none"
		ndef["ActiveWindowScreenShot"] = "Meta+Print"
		ndef["RectangularRegionScreenShot"] = "Meta+Shift+Print\\tMeta+Shift+S"
		ndef["WindowUnderCursorScreenShot"] = "Meta+Ctrl+Print"
		ndef["OpenWithoutScreenshot"] = "none"
		nfn["_launch"] = "Telamon Screenshot"
		nfn["FullScreenScreenShot"] = "Capture Entire Desktop"
		nfn["CurrentMonitorScreenShot"] = "Capture Current Monitor"
		nfn["ActiveWindowScreenShot"] = "Capture Active Window"
		nfn["RectangularRegionScreenShot"] = "Capture Rectangular Region"
		nfn["WindowUnderCursorScreenShot"] = "Capture Window Under Cursor"
		nfn["OpenWithoutScreenshot"] = "Open the Editor"
		src[1] = "[org.kde.spectacle.desktop]"
		dst[1] = "[net.eterneon.telamon.screenshot.desktop]"
		src[2] = "[services][org.kde.spectacle.desktop]"
		dst[2] = "[services][net.eterneon.telamon.screenshot.desktop]"
	}
	# First pass: what the file has.
	FNR == NR {
		if ($0 ~ /^\[.*\]$/) { grp = $0; next }
		i = index($0, "=")
		if (i > 1 && grp != "") { have[grp, substr($0, 1, i - 1)] = 1; val[grp, substr($0, 1, i - 1)] = substr($0, i + 1) }
		next
	}
	# Second pass: decide once, then copy the file with the changes.
	!decided {
		decided = 1
		for (f = 1; f <= 2; f++) {
			# The launch shortcut an earlier Telamon Screenshot set by default is
			# not a choice: it goes, and does not count as the user having set one.
			legacy = 0
			if (f == 1 && have[dst[f], "_launch"]) {
				fields(val[dst[f], "_launch"], a)
				if (a[1] == "Meta+Shift+S" && a[2] == "Meta+Shift+S") { legacy = 1; gone[dst[f], "_launch"] = 1 }
			}
			for (j = 1; j <= nk; j++) {
				k = K[j]
				if (!have[src[f], k]) continue
				gone[src[f], k] = 1
				v = val[src[f], k]
				if (f == 1) { fields(v, a); act = a[1] } else act = v
				if (act == sdef[k]) continue
				if (have[dst[f], k] && !(legacy && k == "_launch")) continue
				add[f] = add[f] k "=" (f == 1 ? act "," ndef[k] "," nfn[k] : act) "\n"
			}
		}
	}
	{
		if ($0 ~ /^\[.*\]$/) {
			grp = $0
			print
			for (f = 1; f <= 2; f++) if (grp == dst[f] && add[f] != "" && !done[f]) { printf "%s", add[f]; done[f] = 1 }
			next
		}
		i = index($0, "=")
		if (i > 1 && ((grp, substr($0, 1, i - 1)) in gone)) next
		print
	}
	END {
		for (f = 1; f <= 2; f++) if (add[f] != "" && !done[f]) {
			print ""
			print dst[f]
			if (f == 1) print "_k_friendly_name=Telamon Screenshot"
			printf "%s", add[f]
		}
	}
' "$ks" "$ks" >"$new" 2>/dev/null || exit 0

if [ -s "$new" ] && ! cmp -s "$ks" "$new"; then
	rel=${ks#"$cfg"/}
	if [ ! -e "$state/$rel" ]; then
		mkdir -p "$(dirname "$state/$rel")"
		cp -p "$ks" "$state/$rel"
	fi
	if [ -L "$ks" ]; then
		cat "$new" >"$ks"
	else
		chmod --reference="$ks" "$new" 2>/dev/null || chmod 0644 "$new"
		mv -f "$new" "$ks"
	fi
fi
