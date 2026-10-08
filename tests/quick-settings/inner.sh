#!/bin/bash
# Runs inside a Telamon OS image (the folder is at /t): for each sample home,
# a private session bus, a virtual KWin and plasmashell with the update
# pending, then the files plasmashell wrote are checked.
set -uo pipefail
export XDG_RUNTIME_DIR=/tmp/rt LANG=C.UTF-8 QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software
export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true XDG_SESSION_TYPE=wayland KDE_SESSION_VERSION=6
mkdir -p "$XDG_RUNTIME_DIR" /var/lib/dbus /tmp/res
chmod 700 "$XDG_RUNTIME_DIR"
[ -s /var/lib/dbus/machine-id ] || dbus-uuidgen >/var/lib/dbus/machine-id
cp /usr/sbin/kwin_wayland /tmp/kwin_wayland
update=telamon-20261008-quick-settings.js
[ -f "/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/$update" ] || { echo "FAIL the image has no $update"; exit 1; }
[ -f /usr/share/plasma/plasmoids/org.telamon.quicksettings/metadata.json ] || { echo "FAIL the image has no Quick Settings widget"; exit 1; }

# The part that runs on the scenario's private session bus
cat >/tmp/session.sh <<'SESSION'
name=$1
/tmp/kwin_wayland --virtual --socket wl-t --width 1920 --height 1080 >/tmp/kwin.log 2>&1 &
for _ in $(seq 80); do [ -S "$XDG_RUNTIME_DIR/wl-t" ] && break; sleep 0.25; done
export WAYLAND_DISPLAY=wl-t
dbus-update-activation-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR QT_QPA_PLATFORM QT_QUICK_BACKEND XDG_CURRENT_DESKTOP KDE_FULL_SESSION XDG_SESSION_TYPE KDE_SESSION_VERSION HOME LANG
kded6 >/dev/null 2>&1 &
plasmashell --no-respawn >"/tmp/res/$name.plasmashell.log" 2>&1 &
# the update is recorded when it has run; then a few seconds for the panels
for _ in $(seq 120); do
	grep -q "$UPDATE" "$HOME/.config/plasmashellrc" 2>/dev/null && break
	sleep 0.5
done
sleep 6
qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
	'var o=[];panels().forEach(function(p){o.push(p.location+"/"+p.lengthMode+"/"+p.alignment+": "+p.widgets().map(function(w){return w.type}).join(","))});print(o.join("\n"))' \
	>"/tmp/res/$name.panels" 2>&1
qdbus-qt6 org.kde.plasmashell /MainApplication quit >/dev/null 2>&1
sleep 5
pkill -x kwin_wayland
pkill -x kded6
true
SESSION

scenario() { # name
	export HOME=/tmp/h-$1 UPDATE=$update
	mkdir -p "$HOME"
	cp -a "/t/$1/." "$HOME/"
	timeout 150 dbus-run-session -- bash /tmp/session.sh "$1" >"/tmp/res/$1.session.log" 2>&1
	cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "/tmp/res/$1.rc" 2>/dev/null
	cp "$HOME/.config/plasmashellrc" "/tmp/res/$1.shellrc" 2>/dev/null
}

fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
has() { if grep -qxF -- "$3" "/tmp/res/$1.$2"; then ok "$1: $3"; else bad "$1: $2 lacks the line: $3"; fi; }
matches() { if grep -qE -- "$3" "/tmp/res/$1.$2"; then ok "$1: $2 matches $3"; else bad "$1: $2 does not match $3"; fi; }
hasnt() { if grep -qE -- "$3" "/tmp/res/$1.$2"; then bad "$1: $2 still matches $3"; else ok "$1: $2 has no $3"; fi; }
panel() { # name wanted-line what
	if grep -qxF -- "$2" "/tmp/res/$1.panels"; then ok "$1: $3"; else bad "$1: $3 (panels: $(tr '\n' '|' <"/tmp/res/$1.panels"))"; fi
}
count() { # name file pattern expected
	n=$(grep -cE -- "$3" "/tmp/res/$1.$2" || true)
	if [ "$n" = "$4" ]; then ok "$1: $4 x $3"; else bad "$1: $n x $3, expected $4"; fi
}

for s in home-existing home-done home-fullbar home-onepiece; do
	echo "== $s"
	scenario "$s"
	[ -s "/tmp/res/$s.rc" ] || { bad "$s: plasmashell wrote no panel config"; tail -5 "/tmp/res/$s.plasmashell.log"; }
done

echo "== existing user (volume, Wi-Fi, Bluetooth, battery... in the tray, a hidden and a shown app icon, a widget of their own after the tray)"
echo "  panels: $(tr '\n' '|' </tmp/res/home-existing.panels)"
count home-existing rc '^plugin=org.telamon.quicksettings$' 1
panel home-existing 'top/fit/right: org.kde.plasma.systemtray,org.kde.plasma.showdesktop,org.telamon.quicksettings' \
	"Quick Settings is the last widget of the right island, the user's widget kept"
panel home-existing 'bottom/fit/center: net.eterneon.telamon.launcher.button,org.telamon.dockseparator,org.kde.plasma.icontasks' "the dock is as it was"
has home-existing rc 'extraItems=org.kde.plasma.notifications'
has home-existing rc 'showAllItems=true'
has home-existing rc 'shownItems=Discord'
has home-existing rc 'hiddenItems=steam'
for p in volume networkmanagement bluetooth battery brightness clipboard devicenotifier mediacontroller; do
	if grep -E '^knownItems=' /tmp/res/home-existing.rc | grep -q "org.kde.plasma.$p"; then
		ok "home-existing: $p is known (so not turned back on)"
	else
		bad "home-existing: $p not in knownItems"
	fi
	hasnt home-existing rc "^extraItems=.*org.kde.plasma.$p"
done

if grep -q "$update" /tmp/res/home-existing.shellrc; then ok "home-existing: the update is recorded as run"; else bad "home-existing: the update is not recorded"; fi

echo "== the update already applied (run again: nothing changes)"
count home-done rc '^plugin=org.telamon.quicksettings$' 1
panel home-done 'top/fit/right: org.kde.plasma.systemtray,org.kde.plasma.showdesktop,org.telamon.quicksettings' "still one Quick Settings"
has home-done rc 'extraItems=org.kde.plasma.notifications'
has home-done rc 'shownItems=Discord'
has home-done rc 'hiddenItems=steam'

echo "== the one-piece bar of an older image: the islands update runs first, then this one"
echo "  panels: $(tr '\n' '|' </tmp/res/home-onepiece.panels)"
panel home-onepiece 'top/fit/right: org.kde.plasma.systemtray,org.telamon.quicksettings' "the right island has the tray and Quick Settings"
has home-onepiece rc 'extraItems=org.kde.plasma.notifications'
has home-onepiece rc 'showAllItems=true'
has home-onepiece rc 'shownItems=Discord'
has home-onepiece rc 'hiddenItems=steam'
hasnt home-onepiece rc '^extraItems=.*org.kde.plasma.(volume|networkmanagement)'

echo "== a full-width bar of the user's own is left alone"
echo "  panels: $(tr '\n' '|' </tmp/res/home-fullbar.panels)"
count home-fullbar rc '^plugin=org.telamon.quicksettings$' 0
# Plasma itself adds the widgets it enables by default to a short list; what matters is that the volume widget stays
matches home-fullbar rc '^extraItems=.*org.kde.plasma.volume'
hasnt home-fullbar rc '^showAllItems='

if [ "$fail" = 0 ]; then echo "ALL OK"; else echo "SOME FAILED"; exit 1; fi
