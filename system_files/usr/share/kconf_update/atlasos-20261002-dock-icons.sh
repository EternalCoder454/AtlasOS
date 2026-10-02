#!/bin/sh
# Moves existing AtlasOS users to the AtlasOS Plasma style (Breeze with the
# dock's rounded highlights and underlines) and the Dracula icons. Only users
# still on what AtlasOS set before (Breeze, or nothing set) are moved; a
# Plasma style or icon theme the user chose is left alone, and so are users
# on a theme that is not AtlasOS's.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
unset_marker=__atlasos_unset__

user_value() { # file group key
	kreadconfig6 --file "$cfg/$1" --group "$2" --key "$3" --default "$unset_marker"
}

pkg=$(user_value kdeglobals KDE LookAndFeelPackage)
case $pkg in
"$unset_marker" | org.atlasos.desktop | org.atlasos.dark.desktop) ;;
*) exit 0 ;;
esac

case $(user_value plasmarc Theme name) in
"$unset_marker" | default)
	kwriteconfig6 --file "$cfg/plasmarc" --group Theme --key name atlasos
	;;
esac

case $(user_value kdeglobals Icons Theme) in
"$unset_marker" | breeze | breeze-dark)
	kwriteconfig6 --file "$cfg/kdeglobals" --group Icons --key Theme Dracula
	;;
esac
