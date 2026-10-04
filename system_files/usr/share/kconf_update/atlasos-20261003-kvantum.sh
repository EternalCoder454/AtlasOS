#!/bin/sh
# Moves existing users from the Breeze application style to Kvantum (the
# AtlasOS themes). Only when the style is still Breeze (or unset, which
# already gets the image default); any other choice is left alone.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
cur=$(kreadconfig6 --file "$cfg/kdeglobals" --group KDE --key widgetStyle --default __unset__)
case $cur in
# Unset already follows the image default (Kvantum): leave it unset, so a later
# default reaches this user too.
__unset__) ;;
Breeze | breeze) kwriteconfig6 --file "$cfg/kdeglobals" --group KDE --key widgetStyle kvantum ;;
*) exit 0 ;;
esac
/usr/libexec/atlasos/kvantum-sync || true
