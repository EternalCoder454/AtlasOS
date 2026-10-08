#!/bin/sh
# Gives a user whose kdeglobals has colours but no [General] ColorScheme that
# key, from the Global Theme's defaults (~/.config/kdedefaults/kdeglobals).
# Applying a Global Theme puts the scheme's name only there; the colours go to
# kdeglobals. Plasma resolves the name through XDG_CONFIG_DIRS (kdedefaults
# first once the session runs), but anything that reads kdeglobals alone does
# not: a Flatpak app sees only that file, and kvantum-sync read /etc/xdg's
# Light name ahead of kdedefaults at login (fixed there too), so Qt apps, GTK
# and the portal's colour-scheme came up Light on a Dark desktop.
#
# Only a missing key is filled in; a user's own ColorScheme is never touched.
# Safe to run twice.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
user=$cfg/kdeglobals
defaults=$cfg/kdedefaults/kdeglobals

# [General] ColorScheme of one file, only that file (kreadconfig6 also looks in
# XDG_CONFIG_DIRS, which is what this script has to avoid).
scheme_of() { # file
	[ -f "$1" ] || return 0
	awk '/^\[/ { g = ($0 == "[General]"); next } g && /^ColorScheme=/ { v = substr($0, 13) } END { if (v != "") print v }' "$1"
}

[ -f "$user" ] || exit 0
# No colours of its own: Plasma takes the scheme's file, nothing to line up.
grep -q '^\[Colors:Window\]' "$user" || exit 0
[ -z "$(scheme_of "$user")" ] || exit 0
name=$(scheme_of "$defaults")
[ -n "$name" ] || exit 0

kwriteconfig6 --file "$user" --group General --key ColorScheme "$name"
/usr/libexec/telamon/kvantum-sync || true
