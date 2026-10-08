#!/bin/bash
# Runs inside a Telamon OS image (or anything with kconf_update and the
# kconf_update folder of this repository): runs the Dolphin and Ark migration
# with the real kconf_update on sample homes and checks the result.
set -euo pipefail
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

files=net.eterneon.telamon.explorer.desktop
archive=net.eterneon.telamon.archive.desktop

# Only the one Id, so what runs is this migration (the whole atlasos.upd is
# checked at the end).
only=$(mktemp)
printf 'Version=6\nId=telamon-20261008-replace-dolphin-ark\nScript=telamon-20261008-replace-dolphin-ark.sh,sh\n' >"$only"

# home NAME: a new, empty home.
home() {
	export HOME=/tmp/h-$1
	rm -rf "$HOME"
	mkdir -p "$HOME/.config" "$HOME/.local/share/applications"
}
# put FILE (relative to HOME): the file is stdin.
put() { mkdir -p "$(dirname "$HOME/$1")"; cat >"$HOME/$1"; }
snap() { rm -rf "$HOME/.snap"; mkdir "$HOME/.snap"; cp -a "$HOME/.config" "$HOME/.local" "$HOME/.snap/"; }
run() { /usr/libexec/kf6/kconf_update "${UPD:-$only}" 2>&1 | sed 's/^/  kconf_update: /' || true; }
has() { if grep -qxF -- "$2" "$HOME/$1"; then ok "$1: $2"; else bad "$1 lacks: $2"; fi; }
hasnt() { if grep -qF -- "$2" "$HOME/$1"; then bad "$1 still has: $2"; else ok "$1 has no $2"; fi; }
count() { # file line n
	n=$(grep -cxF -- "$2" "$HOME/$1" || true)
	[ "$n" = "$3" ] && ok "$3x $1: $2" || bad "$1: $n x $2 (wanted $3)"
}
group() { awk -v g="$2" '/^\[/ { on = ($0 == g); if (on) print; next } on && NF' "$HOME/$1"; }
again() { # a second run (kconf_update told to forget the Id) changes nothing
	snap
	cp -a "$HOME/.snap" "$HOME/.snap1"
	rm -f "$HOME/.config/kconf_updaterc"
	run
	if diff -ru --exclude=kconf_updaterc --exclude=.snap --exclude=.snap1 "$HOME/.snap1/.config" "$HOME/.config" >/dev/null &&
		diff -ru "$HOME/.snap1/.local" "$HOME/.local" >/dev/null; then ok "second run changes nothing"; else bad "second run changed files"; fi
	sh /usr/share/kconf_update/telamon-20261008-replace-dolphin-ark.sh
	if diff -ru --exclude=kconf_updaterc --exclude=.snap --exclude=.snap1 "$HOME/.snap1/.config" "$HOME/.config" >/dev/null &&
		diff -ru "$HOME/.snap1/.local" "$HOME/.local" >/dev/null; then ok "the script alone is idempotent"; else bad "the script alone changed files"; fi
	rm -rf "$HOME/.snap" "$HOME/.snap1"
}
way() { echo "$HOME/.local/state/telamon/migrated-from-atlasos/$1"; }

ap=.config/plasma-org.kde.plasma.desktop-appletsrc
echo "== customised: pins, Open With, shortcuts"
home custom
put $ap <<X
[Containments][2][Applets][5][Configuration][General]
launchers=preferred://filemanager,preferred://browser,applications:org.kde.dolphin.desktop,applications:org.kde.ark.desktop,applications:$files

[Containments][2][Applets][6][Configuration][General]
launchers=applications:org.kde.dolphin.desktop,applications:org.kde.dolphin.desktop,file:///usr/share/applications/org.kde.dolphin.desktop

[Containments][2][Applets][7][Configuration][General]
launchers=applications:org.kde.dolphin.desktop.bak,applications:mydolphin.desktop,applications:org.kde.ark.desktop.bak

[Containments][2][Applets][8][Configuration][General]
ImportPins=systemsettings.desktop,org.kde.dolphin.desktop
favoriteApps=org.kde.dolphin.desktop,$archive
X
put .config/kactivitymanagerd-statsrc <<X
[Favorites-org.kde.plasma.favorites.applications-global]
ordering=applications:org.kde.discover.desktop,applications:org.kde.dolphin.desktop
X
put .config/telamon-launcher/pinned.list <<X
# my pins
preferred://browser
org.kde.dolphin.desktop
org.kde.ark.desktop
$files
com.mitchellh.ghostty.desktop
# done
X
put .config/mimeapps.list <<X
[Default Applications]
inode/directory=org.kde.dolphin.desktop
application/zip=org.kde.ark.desktop;
application/x-tar=org.gnome.FileRoller.desktop;org.kde.ark.desktop;
text/plain=org.kde.kate.desktop

[Added Associations]
inode/directory=org.kde.dolphin.desktop;org.kde.kate.desktop;
application/x-7z-compressed=org.kde.ark.desktop;$archive;

[Removed Associations]
application/gzip=org.kde.ark.desktop;
X
put .config/kde-mimeapps.list <<X
[Default Applications]
inode/directory=org.kde.dolphin.desktop;
X
put .local/share/applications/mimeapps.list <<X
[Default Applications]
inode/directory=org.kde.dolphin.desktop
X
put .config/kglobalshortcutsrc <<'X'
[kwin]
Window Close=Alt+F4,Alt+F4,Close Window

[org.kde.dolphin.desktop]
_k_friendly_name=Dolphin
_launch=Meta+Shift+E\tMeta+E,Meta+E,Dolphin

[services][org.kde.ark.desktop]
_launch=Ctrl+Alt+A

[services][org.kde.dolphin.desktop]
_launch=none
X
cp -a "$HOME/.config" /tmp/custom-before
run
for f in $ap; do
	has $f "launchers=preferred://filemanager,preferred://browser,applications:$files,applications:$archive"
	has $f "launchers=applications:$files,file:///usr/share/applications/$files"
	has $f "launchers=applications:org.kde.dolphin.desktop.bak,applications:mydolphin.desktop,applications:org.kde.ark.desktop.bak"
	has $f "ImportPins=systemsettings.desktop,$files"
	has $f "favoriteApps=$files,$archive"
done
has .config/kactivitymanagerd-statsrc "ordering=applications:org.kde.discover.desktop,applications:$files"
pl=.config/telamon-launcher/pinned.list
has $pl "# my pins"
has $pl "# done"
has $pl "com.mitchellh.ghostty.desktop"
count $pl "$files" 1
count $pl "$archive" 1
[ "$(sed -n 2,4p "$HOME/$pl" | tr '\n' ' ')" = "preferred://browser $files $archive " ] && ok "pinned.list keeps the order" || bad "pinned.list order"
hasnt $pl "org.kde."
m=.config/mimeapps.list
has $m "inode/directory=$files"
has $m "application/zip=$archive;"
has $m "application/x-tar=org.gnome.FileRoller.desktop;$archive;"
has $m "text/plain=org.kde.kate.desktop"
has $m "inode/directory=$files;org.kde.kate.desktop;"
has $m "application/x-7z-compressed=$archive;"
has $m "application/gzip=org.kde.ark.desktop;"
has .config/kde-mimeapps.list "inode/directory=$files;"
has .local/share/applications/mimeapps.list "inode/directory=$files"
ks=.config/kglobalshortcutsrc
has $ks 'Window Close=Alt+F4,Alt+F4,Close Window'
has $ks '[net.eterneon.telamon.explorer.desktop]'
has $ks '_launch=Meta+Shift+E\tMeta+E,Meta+E,Files'
has $ks '[services][net.eterneon.telamon.explorer.desktop]'
has $ks '_launch=none'
has $ks '_launch=Ctrl+Alt+A'
[ "$(group $ks '[org.kde.dolphin.desktop]' | grep -c _launch)" = 0 ] && ok "Dolphin's group has no launch shortcut left" || bad "Dolphin's group still has _launch"
[ "$(group $ks '[services][org.kde.dolphin.desktop]' | wc -l)" = 1 ] && ok "Dolphin's services group is empty" || bad "Dolphin's services group not empty"
[ "$(group $ks '[services][net.eterneon.telamon.explorer.desktop]' | tr '\n' ' ')" = '[services][net.eterneon.telamon.explorer.desktop] _launch=none ' ] && ok "Files' services group" || bad "Files' services group"
for rel in plasma-org.kde.plasma.desktop-appletsrc kactivitymanagerd-statsrc telamon-launcher/pinned.list mimeapps.list kde-mimeapps.list kglobalshortcutsrc; do
	if [ -f "$(way "$rel")" ] && cmp -s "/tmp/custom-before/$rel" "$(way "$rel")"; then ok "the way back holds the old $rel"; else bad "no (or a wrong) copy of the old $rel"; fi
done
[ -f "$(way data/applications/mimeapps.list)" ] && ok "the way back holds the old data mimeapps.list" || bad "no copy of the old data mimeapps.list"
grep -q telamon-20261008-replace-dolphin-ark "$HOME/.config/kconf_updaterc" && ok "Id recorded in kconf_updaterc" || bad "Id not recorded"
again

echo "== stock: Dolphin's shortcut at its default is dropped, Files' own applies"
home stock
put .config/kglobalshortcutsrc <<'X'
[kwin]
Window Close=Alt+F4,Alt+F4,Close Window

[org.kde.dolphin.desktop]
_k_friendly_name=Dolphin
_launch=Meta+E,Meta+E,Dolphin

[services][org.kde.dolphin.desktop]
_launch=Meta+E
X
run
ks=.config/kglobalshortcutsrc
hasnt $ks '_launch'
hasnt $ks 'net.eterneon'
has $ks 'Window Close=Alt+F4,Alt+F4,Close Window'
again

echo "== already moved: Files' entries win, Dolphin's are dropped; Files pinned already"
home moved
put .config/kglobalshortcutsrc <<'X'
[net.eterneon.telamon.explorer.desktop]
_k_friendly_name=Files
_launch=Meta+Alt+E,Meta+E,Files

[org.kde.dolphin.desktop]
_launch=Ctrl+Alt+D,Meta+E,Dolphin
X
put $ap <<X
[A][Configuration][General]
launchers=applications:$files,applications:org.kde.dolphin.desktop
X
run
has .config/kglobalshortcutsrc '_launch=Meta+Alt+E,Meta+E,Files'
hasnt .config/kglobalshortcutsrc 'Ctrl+Alt+D'
count .config/kglobalshortcutsrc '[net.eterneon.telamon.explorer.desktop]' 1
has $ap "launchers=applications:$files"
again

echo "== nothing to migrate: files untouched, no copies"
home none
put $ap <<X
[A][Configuration][General]
launchers=applications:$files,applications:$archive
X
put .config/mimeapps.list <<X
[Default Applications]
inode/directory=$files
X
put .config/kglobalshortcutsrc <<'X'
[net.eterneon.telamon.explorer.desktop]
_launch=Meta+Alt+E,Meta+E,Files
X
cp -a "$HOME/.config" /tmp/none-before
run
diff -ru --exclude=kconf_updaterc /tmp/none-before "$HOME/.config" >/dev/null && ok "files untouched" || bad "files changed"
[ ! -e "$HOME/.local/state/telamon" ] && ok "no copy made when nothing changed" || bad "copy made without a change"

echo "== an empty home"
home empty
run
sh /usr/share/kconf_update/telamon-20261008-replace-dolphin-ark.sh && ok "empty home" || bad "empty home"
[ -z "$(ls -A "$HOME/.local/share/applications")" ] && ok "nothing made" || bad "something made"

echo "== the whole atlasos.upd carries the Id and runs it"
home upd
put .config/mimeapps.list <<X
[Default Applications]
inode/directory=org.kde.dolphin.desktop
X
UPD=/usr/share/kconf_update/atlasos.upd run
has .config/mimeapps.list "inode/directory=$files"
grep -q 'telamon-20261008-replace-dolphin-ark' "$HOME/.config/kconf_updaterc" && ok "Id recorded in kconf_updaterc" || bad "Id not recorded"
grep -c '^Id=telamon-20261008-replace-dolphin-ark$' /usr/share/kconf_update/atlasos.upd | grep -qx 1 && ok "the Id is in atlasos.upd once" || bad "Id missing or doubled in atlasos.upd"

[ "$fail" = 0 ] && echo "all ok" || { echo "FAILED"; exit 1; }
