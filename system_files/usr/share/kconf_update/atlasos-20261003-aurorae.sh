#!/bin/sh
# Moves existing users from the Breeze window decoration to Telamon OS's Windows
# 11 style Aurorae theme: Telamon-Dark with a dark colour scheme, else
# Telamon-Light. Only when the decoration is still Breeze; any other choice
# (or none, which already gets the image default) is left alone.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
unset_marker=__atlasos_unset__

lib=$(kreadconfig6 --file "$cfg/kwinrc" --group org.kde.kdecoration2 --key library --default "$unset_marker")
theme=$(kreadconfig6 --file "$cfg/kwinrc" --group org.kde.kdecoration2 --key theme --default "$unset_marker")
[ "$lib" = org.kde.breeze ] || exit 0
case $theme in Breeze | "$unset_marker") ;; *) exit 0 ;; esac

# A Global Theme applied in Plasma 6 keeps its colour scheme in kdedefaults.
scheme=$(kreadconfig6 --file "$cfg/kdeglobals" --group General --key ColorScheme)
[ -n "$scheme" ] ||
	scheme=$(kreadconfig6 --file "$cfg/kdedefaults/kdeglobals" --group General --key ColorScheme --default TelamonLight)
case $scheme in
*Dark*) name=Telamon-Dark ;;
*) name=Telamon-Light ;;
esac
kwriteconfig6 --file "$cfg/kwinrc" --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file "$cfg/kwinrc" --group org.kde.kdecoration2 --key theme "__aurorae__svg__$name"
