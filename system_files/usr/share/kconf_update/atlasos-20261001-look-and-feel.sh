#!/bin/sh
# Gives existing users the look-and-feel settings of the AtlasOS Global Theme
# they use, for the keys they have never set. A Global Theme's "defaults" file
# is applied by Plasma only when a user is first set up, so users who were set
# up on an older image never got settings added to it since.
#
# A key the user's own file already has is left alone, whatever its value.
# Users on a theme that is not AtlasOS's are left alone entirely.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
unset_marker=__atlasos_unset__

# Reads one key from the user's own file only (an absolute path skips
# /etc/xdg and the other defaults).
user_value() { # file group key
	kreadconfig6 --file "$cfg/$1" --group "$2" --key "$3" --default "$unset_marker"
}

pkg=$(user_value kdeglobals KDE LookAndFeelPackage)
[ "$pkg" != "$unset_marker" ] || pkg=org.atlasos.desktop
case $pkg in
org.atlasos.desktop | org.atlasos.dark.desktop) ;;
*) exit 0 ;;
esac

defaults=/usr/share/plasma/look-and-feel/$pkg/contents/defaults
[ -r "$defaults" ] || exit 0

# "[kdeglobals][General]" headers start a group of file+group keys; headers
# with one bracket pair (the wallpaper) aren't config files and are skipped.
awk '
	/^\[[^]]+\]\[[^]]+\]$/ {
		split($0, h, /\]\[/); file = substr(h[1], 2); group = substr(h[2], 1, length(h[2]) - 1); next
	}
	/^\[/ { file = ""; next }
	file != "" && /^[^#=][^=]*=/ {
		i = index($0, "="); printf "%s\t%s\t%s\t%s\n", file, group, substr($0, 1, i - 1), substr($0, i + 1)
	}
' "$defaults" |
	while IFS="$(printf '\t')" read -r file group key value; do
		[ "$(user_value "$file" "$group" "$key")" = "$unset_marker" ] || continue
		kwriteconfig6 --file "$cfg/$file" --group "$group" --key "$key" "$value"
	done
