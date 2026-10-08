#!/bin/bash
# Runs inside a Telamon OS image (or anything with kconf_update and the
# kconf_update folder of this repository): runs the Spectacle migration with the
# real kconf_update on sample kglobalshortcutsrc files and checks the result.
set -euo pipefail
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

# Only the one Id, so what runs is this migration (the whole atlasos.upd is
# checked at the end).
only=$(mktemp)
printf 'Version=6\nId=telamon-20261008-remove-spectacle\nScript=telamon-20261008-remove-spectacle.sh,sh\n' >"$only"

# home NAME: a new home whose kglobalshortcutsrc is stdin.
home() {
	export HOME=/tmp/h-$1
	rm -rf "$HOME"
	mkdir -p "$HOME/.config"
	cat >"$HOME/.config/kglobalshortcutsrc"
	cp "$HOME/.config/kglobalshortcutsrc" "$HOME/before"
}
run() { /usr/libexec/kf6/kconf_update "${UPD:-$only}" 2>&1 | sed 's/^/  kconf_update: /' || true; }
ks() { echo "$HOME/.config/kglobalshortcutsrc"; }
has() { if grep -qxF -- "$1" "$(ks)"; then ok "$1"; else bad "missing: $1"; fi; }
hasnt() { if grep -qF -- "$1" "$(ks)"; then bad "still has: $1"; else ok "no $1"; fi; }
count() { # line count
	n=$(grep -cxF -- "$1" "$(ks)" || true)
	[ "$n" = "$2" ] && ok "$2x $1" || bad "$n x $1 (wanted $2)"
}
# The group's lines, in order: group header, then its keys until the next group.
group() { awk -v g="$1" '/^\[/ { on = ($0 == g); if (on) print; next } on && NF' "$(ks)"; }
again() { # a second run changes nothing
	cp "$(ks)" "$HOME/after1"
	rm -f "$HOME/.config/kconf_updaterc"
	run
	cmp -s "$HOME/after1" "$(ks)" && ok "second run changes nothing" || bad "second run changed the file"
}

echo "== stock: Spectacle as Plasma 6.7 writes it, nothing changed"
home stock <<'X'
[kwin]
Window Close=Alt+F4,Alt+F4,Close Window

[org.kde.spectacle.desktop]
RecordRegion=Meta+Shift+R,Meta+Shift+R,Start/Stop Region Recording
_k_friendly_name=Spectacle

[services][org.kde.spectacle.desktop]
_launch=Print
FullScreenScreenShot=Shift+Print
ActiveWindowScreenShot=Meta+Print
RectangularRegionScreenShot=Meta+Shift+Print
WindowUnderCursorScreenShot=Meta+Ctrl+Print
OpenWithoutScreenshot=none
X
run
has 'Window Close=Alt+F4,Alt+F4,Close Window'
has 'RecordRegion=Meta+Shift+R,Meta+Shift+R,Start/Stop Region Recording'
hasnt 'RectangularRegionScreenShot'
hasnt '[net.eterneon.telamon.screenshot.desktop]'
hasnt '_launch'
[ -e "$HOME/.local/state/telamon/migrated-from-atlasos/kglobalshortcutsrc" ] && ok "original kept for the way back" || bad "no copy of the original"
again

echo "== stock, the plain-group form (Plain default,default,name)"
home plainstock <<'X'
[org.kde.spectacle.desktop]
ActiveWindowScreenShot=Meta+Print,Meta+Print,Capture Active Window
FullScreenScreenShot=Shift+Print,Shift+Print,Capture Entire Desktop
RectangularRegionScreenShot=Meta+Shift+Print,Meta+Shift+Print,Capture Rectangular Region
RecordScreen=Meta+Alt+R,Meta+Alt+R,Start/Stop Screen Recording
_k_friendly_name=Spectacle
_launch=Print,Print,Spectacle
X
run
hasnt 'ActiveWindowScreenShot'
hasnt '_launch'
has 'RecordScreen=Meta+Alt+R,Meta+Alt+R,Start/Stop Screen Recording'
hasnt '[net.eterneon.telamon.screenshot.desktop]'
again

echo "== changed: the user's own keys move, the recording ones stay"
home changed <<'X'
[org.kde.spectacle.desktop]
FullScreenScreenShot=Ctrl+Shift+F,Shift+Print,Capture Entire Desktop
RectangularRegionScreenShot=none,Meta+Shift+Print,Capture Rectangular Region
RecordRegion=Meta+Alt+9,Meta+Shift+R,Start/Stop Region Recording
WindowUnderCursorScreenShot=Meta+Ctrl+Print,Meta+Ctrl+Print,Capture Window Under Cursor
_k_friendly_name=Spectacle
_launch=Ctrl+Alt+P\tPrint,Print,Spectacle

[services][org.kde.spectacle.desktop]
ActiveWindowScreenShot=Meta+W
_launch=Meta+Print

[kwin]
Window Close=Alt+F4,Alt+F4,Close Window
X
run
group '[net.eterneon.telamon.screenshot.desktop]'
group '[services][net.eterneon.telamon.screenshot.desktop]'
has 'FullScreenScreenShot=Ctrl+Shift+F,Shift+Print,Capture Entire Desktop'
has 'RectangularRegionScreenShot=none,Meta+Shift+Print\tMeta+Shift+S,Capture Rectangular Region'
has '_launch=Ctrl+Alt+P\tPrint,Print,Telamon Screenshot'
has 'ActiveWindowScreenShot=Meta+W'
has '_launch=Meta+Print'
has '_k_friendly_name=Telamon Screenshot'
has 'RecordRegion=Meta+Alt+9,Meta+Shift+R,Start/Stop Region Recording'
has 'Window Close=Alt+F4,Alt+F4,Close Window'
hasnt 'WindowUnderCursorScreenShot'
# Spectacle's groups keep no screenshot key
[ "$(group '[org.kde.spectacle.desktop]' | grep -c 'ScreenShot\|_launch')" = 0 ] && ok "[org.kde.spectacle.desktop] has no screenshot key left" || bad "Spectacle's group still has screenshot keys"
[ "$(group '[services][org.kde.spectacle.desktop]' | wc -l)" = 1 ] && ok "[services][org.kde.spectacle.desktop] is empty" || bad "Spectacle's services group not empty"
again

echo "== already moved: Telamon Screenshot's entries win, Spectacle's are dropped"
home moved <<'X'
[net.eterneon.telamon.screenshot.desktop]
FullScreenScreenShot=Meta+F9,Shift+Print,Capture Entire Desktop
_k_friendly_name=Telamon Screenshot
_launch=Meta+Alt+S,Print,Telamon Screenshot

[org.kde.spectacle.desktop]
FullScreenScreenShot=Ctrl+Shift+F,Shift+Print,Capture Entire Desktop
ActiveWindowScreenShot=Meta+Y,Meta+Print,Capture Active Window
_launch=Ctrl+Alt+P,Print,Spectacle
X
run
has 'FullScreenScreenShot=Meta+F9,Shift+Print,Capture Entire Desktop'
has '_launch=Meta+Alt+S,Print,Telamon Screenshot'
has 'ActiveWindowScreenShot=Meta+Y,Meta+Print,Capture Active Window'
hasnt 'Ctrl+Shift+F'
hasnt 'Ctrl+Alt+P'
count '[net.eterneon.telamon.screenshot.desktop]' 1
again

echo "== an earlier Telamon Screenshot's default Meta+Shift+S launch shortcut is not a choice"
home legacy <<'X'
[net.eterneon.telamon.screenshot.desktop]
_k_friendly_name=Telamon Screenshot
_launch=Meta+Shift+S,Meta+Shift+S,Telamon Screenshot
X
run
hasnt '_launch'
has '[net.eterneon.telamon.screenshot.desktop]'
again

echo "== ... and goes when Spectacle's launch shortcut was changed, which takes its place"
home legacy2 <<'X'
[net.eterneon.telamon.screenshot.desktop]
_k_friendly_name=Telamon Screenshot
_launch=Meta+Shift+S,Meta+Shift+S,Telamon Screenshot

[org.kde.spectacle.desktop]
_launch=Ctrl+Alt+P,Print,Spectacle
X
run
has '_launch=Ctrl+Alt+P,Print,Telamon Screenshot'
count '[net.eterneon.telamon.screenshot.desktop]' 1
hasnt 'Meta+Shift+S'
again

echo "== no Spectacle at all, a changed Telamon Screenshot shortcut stays"
home none <<'X'
[net.eterneon.telamon.screenshot.desktop]
_k_friendly_name=Telamon Screenshot
_launch=Meta+Alt+S,Meta+Shift+S,Telamon Screenshot
X
run
cmp -s "$HOME/before" "$(ks)" && ok "file untouched" || bad "file changed"
[ ! -e "$HOME/.local/state/telamon/migrated-from-atlasos/kglobalshortcutsrc" ] && ok "no copy made when nothing changed" || bad "copy made without a change"

echo "== no kglobalshortcutsrc at all"
export HOME=/tmp/h-empty
rm -rf "$HOME"
mkdir -p "$HOME/.config"
run
[ ! -e "$HOME/.config/kglobalshortcutsrc" ] && ok "no file made" || bad "file made"

echo "== the whole atlasos.upd carries the Id and runs it"
home upd <<'X'
[org.kde.spectacle.desktop]
FullScreenScreenShot=Ctrl+Shift+F,Shift+Print,Capture Entire Desktop
X
UPD=/usr/share/kconf_update/atlasos.upd run
has 'FullScreenScreenShot=Ctrl+Shift+F,Shift+Print,Capture Entire Desktop'
grep -q 'telamon-20261008-remove-spectacle' "$HOME/.config/kconf_updaterc" && ok "Id recorded in kconf_updaterc" || bad "Id not recorded"

[ "$fail" = 0 ] && echo "all ok" || { echo "FAILED"; exit 1; }
