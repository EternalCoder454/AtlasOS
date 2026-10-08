#!/bin/sh
# Telamon Settings replaced KDE's System Settings: a dock pin, a launcher pin
# or a favourite that names System Settings' desktop file now names Telamon
# Settings', once, so the pin still opens Settings and its window groups with
# it.
#
#   systemsettings.desktop, kdesystemsettings.desktop,
#   org.kde.systemsettings.desktop  ->  net.eterneon.telamon.settings.desktop
#
# in the dock's pinned apps (launchers= in the Plasma panel config), the old
# launcher menus' favourites (favorites=, favoriteApps=, the Telamon
# Launcher's ImportPins=), the activity manager's favourites, and the Telamon
# Launcher's own pinned.list. Hidden stand-ins for the old names still exist
# (telamon-settings-systemsettings), so a pin this misses keeps working; it
# only does not group with the running window.
#
# A pin to the new name that is already there is kept once: no second icon.
#
# Runs as the user, before KWin and the shell read their settings (see
# atlasos-kconf-update.service). Safe to run twice. Every file it changes is
# copied first to ~/.local/state/telamon/migrated-from-atlasos/ (once, never
# over an earlier copy), as the rename migration does.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}/telamon/migrated-from-atlasos
new=net.eterneon.telamon.settings.desktop

# A desktop file ID of the old Settings, whole: not part of a longer name.
old_ids='(org\.kde\.|kde)?systemsettings\.desktop'
before='(^|[^A-Za-z0-9._-])'
after='([^A-Za-z0-9._-]|$)'

keep() { # file
	case $1 in
	"$cfg"/*) rel=${1#"$cfg"/} ;;
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

# Renames the pins in a file with comma-separated lists (the panel config and
# the activity manager's), then drops a repeat of the same item inside those
# lists.
rewrite_lists() { # file
	[ -f "$1" ] || return 0
	grep -Eq "${before}${old_ids}${after}" "$1" || return 0
	tmp=$(mktemp "$(dirname "$1")/.telamon-settings-cutover.XXXXXX") || return 0
	# The sed runs twice over a line, so two names side by side
	# (",a,a,") are both found: the pattern consumes the comma between them.
	if sed -E -e "s/${before}${old_ids}${after}/\\1$new\\3/g" -e "s/${before}${old_ids}${after}/\\1$new\\3/g" "$1" |
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
	grep -Eq "^${old_ids}\$" "$1" || return 0
	tmp=$(mktemp "$(dirname "$1")/.telamon-settings-cutover.XXXXXX") || return 0
	if sed -E "s/^${old_ids}\$/$new/" "$1" | awk '$0 == "" || $0 ~ /^#/ || !seen[$0]++' >"$tmp" 2>/dev/null &&
		! cmp -s "$1" "$tmp"; then
		put "$1" "$tmp"
	else
		rm -f "$tmp"
	fi
}

rewrite_lists "$cfg/plasma-org.kde.plasma.desktop-appletsrc"
rewrite_lists "$cfg/kactivitymanagerd-statsrc"
rewrite_pinned_list "$cfg/telamon-launcher/pinned.list"
