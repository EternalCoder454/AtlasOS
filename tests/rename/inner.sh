#!/bin/bash
# Runs inside a Telamon OS image (or anything with kconf_update and the
# kconf_update folder of this repository): migrates a copy of the AtlasOS-era
# home in /t/home with the real kconf_update, then checks the result.
set -euo pipefail
export HOME=/tmp/home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
rm -rf "$HOME" /tmp/before /tmp/hc
cp -a /t/home "$HOME"
cp -a "$HOME" /tmp/before
upd=${UPD:-/usr/share/kconf_update/atlasos.upd}
run() { /usr/libexec/kf6/kconf_update "$upd" 2>&1 | sed 's/^/  kconf_update: /' || true; }

echo "== first run"
run
echo "== what changed (before -> after)"
diff -ru --exclude=kconf_updaterc --exclude=.local /tmp/before "$HOME" | grep -v '^Only in' || true
echo "== the way back, copied first:"
(cd "$HOME/.local/state/telamon/migrated-from-atlasos" && find . -type f | sort | sed 's/^/  /')

fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
has() { if grep -qxF -- "$2" "$HOME/$1"; then ok "$1: $2"; else bad "$1 lacks: $2"; fi; }
hasnt() { if grep -qF -- "$2" "$HOME/$1"; then bad "$1 still has: $2"; else ok "$1 has no $2"; fi; }
echo "== checks"
has .config/kdeglobals 'ColorScheme=TelamonDark'
has .config/kdeglobals 'LookAndFeelPackage=org.telamon.dark.desktop'
has .config/kdeglobals 'TerminalApplication=ghostty --gtk-single-instance=false'
has .config/kdeglobals 'Theme=Papirus-Dark'
has .config/kdedefaults/kdeglobals 'ColorScheme=TelamonDark'
[ "$(cat "$HOME/.config/kdedefaults/package")" = org.telamon.dark.desktop ] && ok "kdedefaults/package" || bad "kdedefaults/package"
has .config/kdedefaults/plasmarc 'name=telamon'
has .config/kdedefaults/kwinrc 'theme=__aurorae__svg__Telamon-Dark'
has .config/kdedefaults/ksplashrc 'Theme=org.telamon.dark.desktop'
has .config/kwinrc 'theme=__aurorae__svg__Telamon-Dark'
has .config/kwinrc 'ButtonsOnRight=IAX'
has .config/plasmarc 'name=telamon'
has .config/plasmarc 'usersWallpapers=/home/user/Pictures/mine.jpg'
has .config/Kvantum/kvantum.kvconfig 'theme=TelamonDarkSolid'
has .config/kscreenlockerrc 'Image=file:///usr/share/wallpapers/Telamon-Login/'
ap=.config/plasma-org.kde.plasma.desktop-appletsrc
has $ap 'plugin=net.eterneon.telamon.launcher.button'
has $ap 'KeepMe=yes'
has $ap 'plugin=org.telamon.dockseparator'
has $ap 'plugin=org.telamon.menu'
has $ap 'plugin=org.telamon.appmenu'
has $ap 'plugin=org.kde.plasma.appmenu'
has $ap 'AppletOrder=3;4;5'
has $ap 'AppletOrder=7;8;9'
has $ap 'launchers=preferred://filemanager,preferred://browser,applications:com.mitchellh.ghostty.desktop,applications:net.eterneon.telamon.store.desktop,applications:org.kde.discover.desktop,applications:net.eterneon.telamon.notepad.desktop,applications:systemsettings.desktop'
has $ap 'Image=file:///usr/share/wallpapers/Telamon/contents/images/1920x1200.jpg'
hasnt $ap atlas
has .config/mimeapps.list 'inode/directory=net.eterneon.telamon.explorer.desktop;'
has .config/mimeapps.list 'text/plain=net.eterneon.telamon.notepad.desktop;'
has .config/mimeapps.list 'x-scheme-handler/https=com.brave.Browser.desktop;'
has .config/mimeapps.list 'application/zip=net.eterneon.telamon.archive.desktop;'
has .local/share/applications/mimeapps.list 'application/x-tar=net.eterneon.telamon.archive.desktop;'
ks=.config/kglobalshortcutsrc
has $ks '[net.eterneon.telamon.monitor.desktop]'
has $ks '_launch=Ctrl+Alt+M,Ctrl+Shift+Esc,Atlas Monitor'
has $ks '[net.eterneon.telamon.screenshot.desktop]'
has $ks '[org.telamon.menubar-toggle.desktop]'
has $ks '_launch=Meta+N,Meta+M,Show menu bar'
has $ks 'Window Close=Alt+F4,Alt+F4,Close Window'
has $ks '[services][org.kde.dolphin.desktop]'
has $ks '[services][net.eterneon.telamon.launcher.desktop]'
has $ks '_launch=Alt+Space'
# the new group existed already: it wins, and the old one stays where it was
has $ks '_launch=Ctrl+Alt+N,none,Telamon Notepad'
has $ks '[net.eterneon.atlas.notepad.desktop]'
hasnt $ks '[net.eterneon.atlas.monitor.desktop]'
hasnt $ks '[org.atlasos.menubar-toggle.desktop]'
has .config/ghostty/config 'theme = light:Telamon Light,dark:Telamon Dark'
has .config/ghostty/config '# keep: AtlasOS Dark stays in a comment about the font'
[ -f "$HOME/.config/autostart/net.eterneon.telamon.updater-tray.desktop" ] && ok "autostart override carried over" || bad "autostart override"
[ -f "$HOME/.config/autostart/net.eterneon.atlas.updater-tray.desktop" ] && ok "old autostart file kept for the way back" || bad "old autostart file"

echo "== a second run changes nothing, the Ids are not run again"
cp -a "$HOME/.config" /tmp/after1
run
if diff -ru --exclude=kconf_updaterc /tmp/after1 "$HOME/.config" >/dev/null; then ok "idempotent"; else bad "second run changed files"; diff -ru --exclude=kconf_updaterc /tmp/after1 "$HOME/.config" | head -20; fi
# the script by itself, run twice more: also a no-op
sh /usr/share/kconf_update/telamon-20261007-rename.sh
if diff -ru --exclude=kconf_updaterc /tmp/after1 "$HOME/.config" >/dev/null; then ok "the script alone is idempotent"; else bad "the script alone changed files"; fi

echo "== high-contrast schemes (made by the apps) and a user already on the new names are left alone"
rm -rf "$HOME"; mkdir -p "$HOME/.config"
printf '[General]\nColorScheme=AtlasOSHighContrastDark\n\n[KDE]\nLookAndFeelPackage=org.telamon.dark.desktop\n' >"$HOME/.config/kdeglobals"
cp "$HOME/.config/kdeglobals" /tmp/hc
sh /usr/share/kconf_update/telamon-20261007-rename.sh
cmp -s /tmp/hc "$HOME/.config/kdeglobals" && ok "AtlasOSHighContrastDark and org.telamon.dark.desktop untouched" || bad "high contrast changed"
[ ! -e "$HOME/.local/state/telamon/migrated-from-atlasos" ] && ok "nothing changed, nothing copied" || bad "a copy was made for nothing"
echo "== a home with nothing in it"
rm -rf "$HOME"; mkdir -p "$HOME"
sh /usr/share/kconf_update/telamon-20261007-rename.sh && ok "empty home" || bad "empty home"
[ "$fail" = 0 ] && echo "ALL OK" || { echo "FAILED"; exit 1; }
