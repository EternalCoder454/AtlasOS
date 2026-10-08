#!/bin/bash
# Runs inside a Telamon OS image (or anything with kconf_update and the
# kconf_update folder of this repository): migrates a copy of the home in
# /t/home with the real kconf_update, then checks the result.
set -euo pipefail
export HOME=/tmp/home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
rm -rf "$HOME" /tmp/before
cp -a /t/home "$HOME"
cp -a "$HOME" /tmp/before
upd=${UPD:-/usr/share/kconf_update/atlasos.upd}
run() { /usr/libexec/kf6/kconf_update "$upd" 2>&1 | sed 's/^/  kconf_update: /' || true; }

echo "== first run"
run
echo "== what changed (before -> after)"
diff -ru --exclude=kconf_updaterc --exclude=.local /tmp/before "$HOME" | grep -v '^Only in' || true

fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
has() { if grep -qxF -- "$2" "$HOME/$1"; then ok "$1: $2"; else bad "$1 lacks: $2"; fi; }
echo "== checks"
ap=.config/plasma-org.kde.plasma.desktop-appletsrc
n=net.eterneon.telamon.settings.desktop
has $ap "launchers=preferred://filemanager,preferred://browser,applications:com.mitchellh.ghostty.desktop,applications:$n,applications:net.eterneon.telamon.store.desktop"
has $ap "launchers=applications:$n,applications:org.kde.discover.desktop,file:///usr/share/applications/$n"
# the new name was there already: one pin, in the first place; a longer name that only ends alike is left alone
has $ap "launchers=applications:$n,applications:mysystemsettings.desktop,applications:org.kde.systemsettings.desktop.bak"
has $ap "ImportPins=$n,org.kde.dolphin.desktop"
has $ap "favoriteApps=$n"
has $ap "launchers=applications:$n,applications:org.kde.discover.desktop"
has .config/kactivitymanagerd-statsrc "ordering=applications:$n,applications:org.kde.discover.desktop"
pl=.config/telamon-launcher/pinned.list
has $pl "# my pins"
has $pl "# done"
has $pl "org.kde.discover.desktop"
if [ "$(grep -c -x "$n" "$HOME/$pl")" = 1 ]; then ok "pinned.list: Settings once"; else bad "pinned.list: Settings not once"; fi
[ "$(sed -n 2,3p "$HOME/$pl" | tr '\n' ' ')" = "preferred://browser $n " ] && ok "pinned.list keeps the order" || bad "pinned.list order"
if grep -q 'systemsettings.desktop$' "$HOME/$pl"; then bad "pinned.list still names System Settings"; else ok "pinned.list names no System Settings"; fi
way=$HOME/.local/state/telamon/migrated-from-atlasos
[ -f "$way/plasma-org.kde.plasma.desktop-appletsrc" ] && cmp -s "/t/home/$ap" "$way/plasma-org.kde.plasma.desktop-appletsrc" && ok "the way back holds the old panel config" || bad "no copy of the old panel config"

echo "== a second run changes nothing"
cp -a "$HOME/.config" /tmp/after1
run
if diff -ru --exclude=kconf_updaterc /tmp/after1 "$HOME/.config" >/dev/null; then ok "idempotent"; else bad "second run changed files"; fi
sh /usr/share/kconf_update/telamon-20261007-settings-cutover.sh
if diff -ru --exclude=kconf_updaterc /tmp/after1 "$HOME/.config" >/dev/null; then ok "the script alone is idempotent"; else bad "the script alone changed files"; fi

echo "== a home with nothing in it, and one already on the new name"
rm -rf "$HOME"; mkdir -p "$HOME"
sh /usr/share/kconf_update/telamon-20261007-settings-cutover.sh && ok "empty home" || bad "empty home"
mkdir -p "$HOME/.config"
printf '[A]\nlaunchers=applications:%s\n' "$n" >"$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" /tmp/same
sh /usr/share/kconf_update/telamon-20261007-settings-cutover.sh
cmp -s /tmp/same "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" && ok "already on the new name: untouched" || bad "touched a file with nothing to change"
[ ! -e "$HOME/.local/state/telamon" ] && ok "nothing changed, nothing copied" || bad "a copy was made for nothing"
[ "$fail" = 0 ] && echo "ALL OK" || { echo "FAILED"; exit 1; }
