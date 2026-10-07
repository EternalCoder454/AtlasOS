#!/bin/sh
# Moves existing users from the Dracula icons, which Telamon OS no longer has, to
# Papirus: Papirus-Dark with Telamon Dark (or any dark colour scheme), Papirus
# otherwise. Only Dracula is replaced; any other icon theme the user chose is
# left alone, and so is a user with no icon theme set (the global theme
# supplies Papirus).
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
unset_marker=__atlasos_unset__

user_value() { # group key
	kreadconfig6 --file "$cfg/kdeglobals" --group "$1" --key "$2" --default "$unset_marker"
}

case $(user_value Icons Theme) in
Dracula*) ;;
*) exit 0 ;;
esac

pkg=$(user_value KDE LookAndFeelPackage)
scheme=$(user_value General ColorScheme)
# A Global Theme applied in Plasma 6 keeps its colour scheme in kdedefaults.
[ "$scheme" != "$unset_marker" ] ||
	scheme=$(kreadconfig6 --file "$cfg/kdedefaults/kdeglobals" --group General --key ColorScheme)
case $pkg:$scheme in
org.telamon.dark.desktop:* | *:*Dark*) icons=Papirus-Dark ;;
*) icons=Papirus ;;
esac
kwriteconfig6 --file "$cfg/kdeglobals" --group Icons --key Theme "$icons"
