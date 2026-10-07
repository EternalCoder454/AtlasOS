#!/bin/sh
# Moves existing users from Breeze's cursors, which Telamon OS no longer has, to
# Bibata Modern: Ice with Telamon Light, Classic with Telamon Dark. Users who
# never chose a cursor get the one of their Telamon OS theme too. A cursor theme
# the user chose that still exists is left alone.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
unset_marker=__atlasos_unset__

current=$(kreadconfig6 --file "$cfg/kcminputrc" --group Mouse --key cursorTheme --default "$unset_marker")
case $current in
"$unset_marker" | breeze_cursors | Breeze_Light) ;;
*) exit 0 ;;
esac

pkg=$(kreadconfig6 --file "$cfg/kdeglobals" --group KDE --key LookAndFeelPackage --default org.telamon.desktop)
case $pkg in
org.telamon.dark.desktop) cursor=Bibata-Modern-Classic ;;
*) cursor=Bibata-Modern-Ice ;;
esac
kwriteconfig6 --file "$cfg/kcminputrc" --group Mouse --key cursorTheme "$cursor"
