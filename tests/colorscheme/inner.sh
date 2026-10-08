#!/bin/bash
# Runs inside a Telamon OS image (see run.sh).
set -uo pipefail
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { # what expected actual
	if [ "$2" = "$3" ]; then ok "$1: $3"; else bad "$1: wanted [$2], got [$3]"; fi
}

# A home like the owner's: the Dark colours in kdeglobals, ColorScheme only in
# kdedefaults, Kvantum on the Dark theme, GTK dark.
home() { # [user-scheme]
	export HOME=/tmp/home
	rm -rf "$HOME"
	mkdir -p "$HOME/.config/kdedefaults" "$HOME/.config/Kvantum" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
	{
		sed '/^\[General\]/,/^$/d' /usr/share/color-schemes/TelamonDark.colors
		printf '[General]\nColorSchemeHash=abc\n'
		[ -z "${1:-}" ] || printf 'ColorScheme=%s\n' "$1"
		printf '\n[KDE]\nLookAndFeelPackage=org.telamon.dark.desktop\n'
	} >"$HOME/.config/kdeglobals"
	printf '[General]\nColorScheme=TelamonDark\n\n[KDE]\nwidgetStyle=kvantum\n' >"$HOME/.config/kdedefaults/kdeglobals"
	printf '[General]\ntheme=TelamonDark\n' >"$HOME/.config/Kvantum/kvantum.kvconfig"
	printf '[Settings]\ngtk-application-prefer-dark-theme=true\ngtk-theme-name=Breeze\ngtk-icon-theme-name=Papirus-Dark\n' |
		tee "$HOME/.config/gtk-3.0/settings.ini" >"$HOME/.config/gtk-4.0/settings.ini"
	# kvantum-sync would tell the host's session bus about GTK; there is none.
	export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
	unset XDG_CONFIG_HOME XDG_RUNTIME_DIR TRIGGER_UNIT
}
theme() { sed -n 's/^theme=//p' "$HOME/.config/Kvantum/kvantum.kvconfig"; }
key() { awk '/^\[/ { g = ($0 == "[General]"); next } g && /^ColorScheme=/ { print substr($0, 13) }' "$HOME/.config/kdeglobals"; }

echo "== kvantum-sync at login (XDG_CONFIG_DIRS without kdedefaults, as before Plasma's startup)"
home
XDG_CONFIG_DIRS=/etc/xdg /usr/libexec/telamon/kvantum-sync
check "Dark desktop keeps the Dark theme" TelamonDark "$(theme)"

echo "== kvantum-sync in the running session (kdedefaults first)"
home
XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg /usr/libexec/telamon/kvantum-sync
check "Dark desktop keeps the Dark theme" TelamonDark "$(theme)"

echo "== kvantum-sync follows the user's own ColorScheme over the defaults"
home TelamonLight
XDG_CONFIG_DIRS=/etc/xdg /usr/libexec/telamon/kvantum-sync
check "user's Light wins" Telamon "$(theme)"

echo "== kvantum-sync with nothing set anywhere reads /etc/xdg (Light)"
home
rm -f "$HOME/.config/kdedefaults/kdeglobals"
XDG_CONFIG_DIRS=/etc/xdg /usr/libexec/telamon/kvantum-sync
check "system default" Telamon "$(theme)"

echo "== migration"
upd=/usr/share/kconf_update/atlasos.upd
grep -qx 'Id=telamon-20261007-colorscheme' "$upd" && ok "listed in atlasos.upd" || bad "not in atlasos.upd"
[ -x /usr/share/kconf_update/telamon-20261007-colorscheme.sh ] && ok "executable" || bad "not executable"
home
XDG_CONFIG_DIRS=/etc/xdg /usr/share/kconf_update/telamon-20261007-colorscheme.sh
check "key filled in from kdedefaults" TelamonDark "$(key)"
check "theme" TelamonDark "$(theme)"
cp "$HOME/.config/kdeglobals" /tmp/once
XDG_CONFIG_DIRS=/etc/xdg /usr/share/kconf_update/telamon-20261007-colorscheme.sh
cmp -s /tmp/once "$HOME/.config/kdeglobals" && ok "second run changes nothing" || bad "second run changed kdeglobals"
home TelamonLight
XDG_CONFIG_DIRS=/etc/xdg /usr/share/kconf_update/telamon-20261007-colorscheme.sh
check "user's own key left alone" TelamonLight "$(key)"
home
rm -f "$HOME/.config/kdedefaults/kdeglobals"
XDG_CONFIG_DIRS=/etc/xdg /usr/share/kconf_update/telamon-20261007-colorscheme.sh
check "no defaults, nothing written" "" "$(key)"
home
sed -i '/^\[Colors:Window\]/,/^$/d' "$HOME/.config/kdeglobals"
XDG_CONFIG_DIRS=/etc/xdg /usr/share/kconf_update/telamon-20261007-colorscheme.sh
check "no colours of its own, nothing written" "" "$(key)"

exit $fail
