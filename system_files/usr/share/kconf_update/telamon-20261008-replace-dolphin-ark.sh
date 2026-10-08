#!/bin/sh
# Files (Telamon Explorer) replaced KDE Dolphin and Telamon Archive replaced KDE
# Ark: what a user has that names the old apps names the new ones, once.
#
#   org.kde.dolphin.desktop  ->  net.eterneon.telamon.explorer.desktop
#   org.kde.ark.desktop      ->  net.eterneon.telamon.archive.desktop
#
#   - Pins: the dock's pinned apps (launchers= in the Plasma panel config), the
#     old launcher menus' favourites (favorites=, favoriteApps=, the Telamon
#     Launcher's ImportPins=), the activity manager's favourites, and the
#     Telamon Launcher's own pinned.list. A pin to the new name that is
#     already there is kept once: no second icon. (preferred://filemanager
#     pins follow the default file manager and need nothing.)
#   - Default and added applications in ~/.config/mimeapps.list,
#     kde-mimeapps.list and ~/.local/share/applications/mimeapps.list (also
#     kde-mimeapps.list there): a type opened with Dolphin or Ark is opened
#     with Files or Archive. [Removed Associations] is left alone.
#   - Dolphin's global shortcut in kglobalshortcutsrc (Meta+E), in both forms
#     kglobalaccel writes: [org.kde.dolphin.desktop] and
#     [services][org.kde.dolphin.desktop] -> Files' groups. Only a shortcut
#     the user changed moves (a different key, or none); one still at Dolphin's
#     default Meta+E is dropped, and Files' own default (also Meta+E) applies.
#     A shortcut already set for Files wins.
#
# Runs as the user, before KWin and the shell read their settings (see
# atlasos-kconf-update.service). Safe to run twice. Every file it changes is
# copied first to ~/.local/state/telamon/migrated-from-atlasos/ (once, never
# over an earlier copy), as the other migrations do.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
state=${XDG_STATE_HOME:-$HOME/.local/state}/telamon/migrated-from-atlasos
files=net.eterneon.telamon.explorer.desktop
archive=net.eterneon.telamon.archive.desktop

# A desktop file ID of the old apps, whole: not part of a longer name.
before='(^|[^A-Za-z0-9._-])'
after='([^A-Za-z0-9._-]|$)'
dolphin='org\.kde\.dolphin\.desktop'
ark='org\.kde\.ark\.desktop'

keep() { # file
	case $1 in
	"$cfg"/*) rel=${1#"$cfg"/} ;;
	"$data"/*) rel=data/${1#"$data"/} ;;
	*) rel=data/${1##*/} ;;
	esac
	[ ! -e "$state/$rel" ] || return 0
	mkdir -p "$(dirname "$state/$rel")"
	cp -p "$1" "$state/$rel"
}

# Puts new content in a file: replaced by rename, or written through when the
# file is a link (a dotfiles manager's).
put() { # file new-content-file
	keep "$1"
	if [ -L "$1" ]; then
		cat "$2" >"$1"
		rm -f "$2"
	else
		chmod --reference="$1" "$2" 2>/dev/null || chmod 0644 "$2"
		mv -f "$2" "$1"
	fi
}

# The sed run twice over a line, so two names side by side (",a,a,") are both
# found: the pattern consumes the delimiter between them.
rename_ids() {
	sed -E \
		-e "s/${before}${dolphin}${after}/\\1$files\\2/g" -e "s/${before}${dolphin}${after}/\\1$files\\2/g" \
		-e "s/${before}${ark}${after}/\\1$archive\\2/g" -e "s/${before}${ark}${after}/\\1$archive\\2/g"
}

has_old() { # file
	grep -Eq "${before}(${dolphin}|${ark})${after}" "$1"
}

# Pins in a file with comma-separated lists (the panel config and the activity
# manager's), then a repeat of the same item inside those lists goes.
rewrite_lists() { # file
	[ -f "$1" ] || return 0
	has_old "$1" || return 0
	tmp=$(mktemp "$(dirname "$1")/.telamon-dolphin-ark.XXXXXX") || return 0
	if rename_ids <"$1" |
		awk -F= '
			/^[A-Za-z]*(launchers|favorites|favoriteApps|ImportPins)=/ && index($0, "=") {
				key = $1
				rest = substr($0, length(key) + 2)
				n = split(rest, items, ",")
				out = ""; delete seen
				for (i = 1; i <= n; i++) {
					if (items[i] in seen) continue
					seen[items[i]] = 1
					out = out (out == "" ? "" : ",") items[i]
				}
				print key "=" out
				next
			}
			{ print }' >"$tmp" 2>/dev/null && ! cmp -s "$1" "$tmp"; then
		put "$1" "$tmp"
	else
		rm -f "$tmp"
	fi
}

# The Telamon Launcher's list: one desktop file ID per line.
rewrite_pinned_list() { # file
	[ -f "$1" ] || return 0
	grep -Eq "^(${dolphin}|${ark})\$" "$1" || return 0
	tmp=$(mktemp "$(dirname "$1")/.telamon-dolphin-ark.XXXXXX") || return 0
	if sed -E -e "s/^${dolphin}\$/$files/" -e "s/^${ark}\$/$archive/" "$1" |
		awk '$0 == "" || $0 ~ /^#/ || !seen[$0]++' >"$tmp" 2>/dev/null &&
		! cmp -s "$1" "$tmp"; then
		put "$1" "$tmp"
	else
		rm -f "$tmp"
	fi
}

# A mimeapps.list: in [Default Applications] and [Added Associations] (lines of
# "type=a.desktop;b.desktop;"), the old IDs become the new, once each per line.
rewrite_mimeapps() { # file
	[ -f "$1" ] || return 0
	has_old "$1" || return 0
	tmp=$(mktemp "$(dirname "$1")/.telamon-dolphin-ark.XXXXXX") || return 0
	if awk -v files="$files" -v archive="$archive" '
		/^\[.*\]$/ { on = ($0 == "[Default Applications]" || $0 == "[Added Associations]"); print; next }
		on && index($0, "=") > 1 {
			i = index($0, "=")
			key = substr($0, 1, i - 1)
			val = substr($0, i + 1)
			if (val ~ /(^|;)org\.kde\.(dolphin|ark)\.desktop(;|$)/) {
				n = split(val, items, ";")
				out = ""; delete seen
				for (j = 1; j <= n; j++) {
					it = items[j]
					if (it == "") continue
					if (it == "org.kde.dolphin.desktop") it = files
					else if (it == "org.kde.ark.desktop") it = archive
					if (it in seen) continue
					seen[it] = 1
					out = out it ";"
				}
				# A [Default Applications] line is a list without a final ";" in
				# what xdg-mime writes; keep the shape the line had.
				if (val !~ /;$/) sub(/;$/, "", out)
				print key "=" out
				next
			}
		}
		{ print }' "$1" >"$tmp" 2>/dev/null && [ -s "$tmp" ] && ! cmp -s "$1" "$tmp"; then
		put "$1" "$tmp"
	else
		rm -f "$tmp"
	fi
}

# Dolphin's launch shortcut (see the top of the file).
rewrite_shortcuts() { # file
	ks=$1
	[ -f "$ks" ] || return 0
	grep -q 'org\.kde\.dolphin\.desktop' "$ks" || return 0
	new=$(mktemp "$(dirname "$ks")/.telamon-dolphin-ark.XXXXXX") || return 0
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
			def = "Meta+E"          # Dolphin 26.08 and Files
			fn = "Files"
			src[1] = "[org.kde.dolphin.desktop]"
			dst[1] = "[net.eterneon.telamon.explorer.desktop]"
			src[2] = "[services][org.kde.dolphin.desktop]"
			dst[2] = "[services][net.eterneon.telamon.explorer.desktop]"
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
				if (!have[src[f], "_launch"]) continue
				gone[src[f], "_launch"] = 1
				v = val[src[f], "_launch"]
				if (f == 1) { fields(v, a); act = a[1] } else act = v
				if (act == def) continue
				if (have[dst[f], "_launch"]) continue
				add[f] = "_launch=" (f == 1 ? act "," def "," fn : act) "\n"
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
				if (f == 1) print "_k_friendly_name=" fn
				printf "%s", add[f]
			}
		}
	' "$ks" "$ks" >"$new" 2>/dev/null || { rm -f "$new"; return 0; }
	if [ -s "$new" ] && ! cmp -s "$ks" "$new"; then
		put "$ks" "$new"
	else
		rm -f "$new"
	fi
}

rewrite_lists "$cfg/plasma-org.kde.plasma.desktop-appletsrc"
rewrite_lists "$cfg/kactivitymanagerd-statsrc"
rewrite_pinned_list "$cfg/telamon-launcher/pinned.list"
rewrite_mimeapps "$cfg/mimeapps.list"
rewrite_mimeapps "$cfg/kde-mimeapps.list"
rewrite_mimeapps "$data/applications/mimeapps.list"
rewrite_mimeapps "$data/applications/kde-mimeapps.list"
rewrite_shortcuts "$cfg/kglobalshortcutsrc"
