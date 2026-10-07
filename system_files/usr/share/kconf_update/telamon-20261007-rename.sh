#!/bin/sh
# AtlasOS became Telamon OS: moves what a user's settings name from the old
# names to the new ones, once, so the desktop looks the way it did.
#
#   Global Themes          org.atlasos.desktop, org.atlasos.dark.desktop
#                          -> org.telamon.desktop, org.telamon.dark.desktop
#   colour schemes         AtlasOSLight, AtlasOSDark -> TelamonLight, TelamonDark
#   window decoration      __aurorae__svg__AtlasOS-Light/-Dark -> ...Telamon-...
#   Plasma style           plasmarc [Theme] name=atlasos -> telamon
#   Kvantum themes         AtlasOS, AtlasOSDark, AtlasOSSolid, AtlasOSDarkSolid
#                          -> Telamon, TelamonDark, ...
#   wallpapers             wallpapers/AtlasOS[-Login] -> wallpapers/Telamon[-Login]
#   Plasma applets         org.atlasos.menu, .appmenu, .dockseparator
#                          -> org.telamon.*; the Launcher's dock button
#                          net.eterneon.atlas.launcher.button -> ...telamon...
#   apps                   net.eterneon.atlas.<app>.desktop -> ...telamon...: the
#                          dock's pinned apps (launchers=), default apps
#                          (mimeapps.list), autostart overrides, and the
#                          shortcuts a user changed (kglobalshortcutsrc)
#   Ghostty                its theme line, "AtlasOS Light" -> "Telamon Light"
#
# What this does not touch: the colour schemes AtlasOSHighContrast* (made by
# Telamon Settings and Telamon Setup, not by the image) and what the apps keep
# in their own files (they move those themselves).
#
# Runs as the user, before KWin and the shell read their settings (see
# atlasos-kconf-update.service), so Plasma only ever sees the new names. Safe to
# run twice. Every file it changes is copied first to
# ~/.local/state/telamon/migrated-from-atlasos/ (once, never over an earlier
# copy), so an image of before the rename can be given its files back.
set -eu

cfg=${XDG_CONFIG_HOME:-$HOME/.config}
state=${XDG_STATE_HOME:-$HOME/.local/state}/telamon/migrated-from-atlasos
apps='updater|monitor|notepad|settings|wizard|store|explorer|archive|launcher|screenshot|installer'

# The values, as one sed script: whole names only, so a name that merely starts
# like one of ours is left alone.
names=$(mktemp)
trap 'rm -f "$names"' EXIT
cat >"$names" <<EOF
s/org\.atlasos\.dark\.desktop/org.telamon.dark.desktop/g
s/org\.atlasos\.desktop/org.telamon.desktop/g
s/org\.atlasos\.(menu|appmenu|dockseparator|menubar-toggle)/org.telamon.\1/g
s/AtlasOS(Light|Dark)(Solid)?([^A-Za-z]|\$)/Telamon\1\2\3/g
s/__aurorae__svg__AtlasOS-(Light|Dark)/__aurorae__svg__Telamon-\1/g
s#wallpapers/AtlasOS-Login#wallpapers/Telamon-Login#g
s#wallpapers/AtlasOS([^A-Za-z0-9-]|\$)#wallpapers/Telamon\1#g
s/net\.eterneon\.atlas\.($apps)([^A-Za-z0-9]|\$)/net.eterneon.telamon.\1\2/g
EOF

# Copies a file for the way back, once.
keep() { # file
	case $1 in
	"$cfg"/*) rel=${1#"$cfg"/} ;;
	*) rel=data/${1##*/} ;;
	esac
	[ ! -e "$state/$rel" ] || return 0
	mkdir -p "$(dirname "$state/$rel")"
	cp -p "$1" "$state/$rel"
}

# Puts new content in a file: replaced by rename, or written through when the
# file is a link (a dotfiles manager's).
put() { # file new-content-file
	keep "$1"
	if [ -L "$1" ]; then
		cat "$2" >"$1"
		rm -f "$2"
	else
		chmod --reference="$1" "$2" 2>/dev/null || chmod 0644 "$2"
		mv -f "$2" "$1"
	fi
}

# Applies the values to a file, when anything in it changes.
rewrite() { # file [sed expression to add]
	[ -f "$1" ] || return 0
	new=$(mktemp "$(dirname "$1")/.telamon-rename.XXXXXX") || return 0
	if sed -E -f "$names" ${2:+-e "$2"} "$1" >"$new" 2>/dev/null && ! cmp -s "$1" "$new"; then
		put "$1" "$new"
	else
		rm -f "$new"
	fi
}

for f in kdeglobals kwinrc ksplashrc plasmarc plasmashellrc kscreenlockerrc \
	plasma-org.kde.plasma.desktop-appletsrc mimeapps.list \
	kdedefaults/kdeglobals kdedefaults/package kdedefaults/kwinrc \
	kdedefaults/ksplashrc kdedefaults/plasmarc kdedefaults/kcminputrc; do
	rewrite "$cfg/$f"
done
rewrite "${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list"

# The Plasma style: plasmarc [Theme] name=atlasos (a key's value, not a name
# that can stand anywhere, so only that key).
for f in plasmarc kdedefaults/plasmarc; do
	[ -f "$cfg/$f" ] || continue
	if [ "$(kreadconfig6 --file "$cfg/$f" --group Theme --key name --default x)" = atlasos ]; then
		keep "$cfg/$f"
		kwriteconfig6 --file "$cfg/$f" --group Theme --key name telamon
	fi
done

# Kvantum's own name for the light theme was the bare "AtlasOS".
kv=$cfg/Kvantum/kvantum.kvconfig
if [ -f "$kv" ]; then
	rewrite "$kv" 's/^(theme *= *)AtlasOS *$/\1Telamon/;s/^(theme *= *)AtlasOSSolid *$/\1TelamonSolid/'
fi

# Ghostty: only its theme line.
for g in config config.ghostty; do
	rewrite "$cfg/ghostty/$g" '/^[[:space:]]*theme[[:space:]]*=/ s/AtlasOS (Light|Dark)/Telamon \1/g'
done

# A user's autostart choice for a renamed app (a file of Hidden=true that
# turned it off) is the same file under the new id.
for old in "$cfg"/autostart/net.eterneon.atlas.*.desktop; do
	[ -f "$old" ] || continue
	new=$(printf '%s' "$old" | sed -E "s/net\\.eterneon\\.atlas\\.($apps)([^A-Za-z0-9])/net.eterneon.telamon.\\1\\2/")
	[ "$new" != "$old" ] && [ ! -e "$new" ] || continue
	keep "$old"
	cp -p "$old" "$new"
	rewrite "$new"
done

# Shortcuts a user changed: kglobalaccel keeps each app's under a group named
# for its desktop file. The old group becomes the new one, unless the new one
# already exists (then the user has already set it up there). kglobalacceld
# rewrites the file from what it knows, which is why this runs before it asks.
ks=$cfg/kglobalshortcutsrc
if [ -f "$ks" ]; then
	new=$(mktemp "$cfg/.telamon-rename.XXXXXX")
	awk -v apps="$apps" '
		BEGIN { split(apps, a, "|"); for (i in a) ok[a[i]] = 1 }
		FNR == NR { if ($0 ~ /^\[.*\]$/) have[$0] = 1; next }
		/^\[.*\]$/ {
			h = $0; n = h
			if (match(h, /^\[(services\]\[)?net\.eterneon\.atlas\.[a-z]+\.desktop\]$/)) {
				pre = (h ~ /^\[services\]/) ? "[services][" : "["
				name = h
				sub(/^\[(services\]\[)?net\.eterneon\.atlas\./, "", name)
				sub(/\.desktop\]$/, "", name)
				if (name in ok) n = pre "net.eterneon.telamon." name ".desktop]"
			} else if (h == "[org.atlasos.menubar-toggle.desktop]") {
				n = "[org.telamon.menubar-toggle.desktop]"
			}
			if (n != h && !(n in have)) { $0 = n; have[n] = 1 }
		}
		{ print }
	' "$ks" "$ks" >"$new" 2>/dev/null || :
	if [ -s "$new" ] && ! cmp -s "$ks" "$new"; then
		put "$ks" "$new"
	else
		rm -f "$new"
	fi
fi
