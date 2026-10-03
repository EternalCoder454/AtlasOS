#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 3 of 4: services, settings and
# branding, after packages.sh and apps.sh. Runs in the Containerfile's third
# RUN step, with the repo's build context at /ctx and the rendered branding at
# /branding. The image's version goes into os-release last, in a step of its
# own (version.sh), so a new date alone doesn't rerun this.
set -euxo pipefail

### Services

# dnf can't change an image-based system, so refreshing its metadata in the
# background only costs memory, disk and bandwidth.
systemctl disable dnf-makecache.timer

# Background update checks stage an update and never apply it:
# atlasos-update-stage.timer runs `bootc upgrade` (download and stage, no
# reboot). The two timers that apply or reboot by themselves stay off.
systemctl disable bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer

# Power profiles come from power-profiles-daemon (swapped in by packages.sh).
[ "$(systemctl is-enabled power-profiles-daemon.service)" = enabled ]
for p in tuned tuned-ppd xwaylandvideobridge kunifiedpush mariadb-server; do
	if rpm -q "$p" >/dev/null 2>&1; then
		echo "build.sh: $p must not be installed" >&2
		exit 1
	fi
done

### Branding

# Modes come from the checkout: a file a local checkout made private would
# ship private, so that fails the build.
unreadable=$(find /ctx/system_files ! -type l ! -perm -o=r)
[ -z "$unreadable" ] || {
	echo "build.sh: not readable by everyone: $unreadable" >&2
	exit 1
}
cp -a /ctx/system_files/. /

# Atlas Updater is the only update notifier and the only OS updater.
# Discover's notifier and OS backend (removed by packages.sh) and every other
# background updater stay out, and Discover never updates on its own.
[ ! -e /usr/libexec/DiscoverNotifier ]
[ -z "$(find /etc/xdg/autostart /usr/share/applications -iname '*discover*notifier*' -print -quit)" ]
for p in plasma-discover-notifier plasma-discover-rpm-ostree PackageKit; do
	if rpm -q "$p" >/dev/null 2>&1; then
		echo "build.sh: $p must not be installed" >&2
		exit 1
	fi
done
grep -qx 'UseUnattendedUpdates=false' /etc/xdg/PlasmaDiscoverUpdates

# The kernel sizes the inotify watch limit by RAM; this raises it to 524288
# where it is lower (IDEs and file watchers run out), and never lowers it.
systemctl enable atlasos-inotify-watches.service
systemctl enable atlasos-update-stage.timer
# Records each newly booted image in /var/lib/atlas-core/history.jsonl. The
# system helper is D-Bus activated and must stay that way: nothing runs at idle.
systemctl enable atlas-record-boot.service
[ "$(systemctl is-enabled atlas-record-boot.service)" = enabled ]
[ "$(systemctl is-enabled atlas-system-helper.service 2>&1 || true)" != enabled ]
[ -f /usr/share/dbus-1/system-services/net.eterneon.atlas.SystemHelper.service ]
# greenboot's units. The package's scriptlets enable nothing while building.
# The boot counter in GRUB reaches existing installs through
# atlasos-grub-greenboot.service (see the README).
systemctl enable greenboot-healthcheck.service greenboot-set-rollback-trigger.service
systemctl enable atlasos-grub-greenboot.service
for u in greenboot-healthcheck.service greenboot-set-rollback-trigger.service atlasos-grub-greenboot.service; do
	[ "$(systemctl is-enabled "$u")" = enabled ] || {
		echo "build.sh: $u must be enabled" >&2
		exit 1
	}
done
grep -qx 'GREENBOOT_MAX_BOOT_ATTEMPTS=3' /etc/greenboot/greenboot.conf
# Still ending in the newline packages.sh added (see there).
snippet=/usr/lib/bootupd/grub2-static/configs.d/08_greenboot.cfg
[ -f "$snippet" ]
[ -z "$(tail -c1 "$snippet")" ]
# The AtlasOS checks are image-owned, in /usr/lib/greenboot (greenboot reads it
# before /etc/greenboot); each must run, and each helper script must parse.
for f in /usr/lib/greenboot/check/required.d/*.sh /usr/lib/greenboot/red.d/*.sh /usr/lib/greenboot/green.d/*.sh; do
	[ -x "$f" ] && bash -n "$f"
done
[ "$(find /usr/lib/greenboot/check/required.d -name '*.sh' | wc -l)" -eq 3 ]
[ -f /usr/lib/systemd/system/greenboot-healthcheck.service.d/atlasos.conf ]
# Flathub as a system remote (system_files/usr/share/flatpak/remotes.d), and
# the Flatpaks in preinstall.d installed in the background after boot.
systemctl enable atlasos-flatpak-preinstall.timer
# kconf_update runs AtlasOS's settings updates at each Plasma login (kded6's
# own run skips them: ostree's mtime 0 looks unchanged).
systemctl --global enable atlasos-kconf-update.service
[ -x /usr/libexec/kf6/kconf_update ] || {
	echo "build.sh: /usr/libexec/kf6/kconf_update is missing" >&2
	exit 1
}
# kconf_update scripts and helpers must keep their execute bit.
for f in /usr/share/kconf_update/atlasos-*.sh /usr/libexec/atlasos/*; do
	[ -x "$f" ] || {
		echo "build.sh: $f is not executable" >&2
		exit 1
	}
done
# Every script in the .upd has to exist, and every Id has to be unique.
while IFS=, read -r script _; do
	[ -x "/usr/share/kconf_update/${script#Script=}" ]
done < <(grep '^Script=' /usr/share/kconf_update/atlasos.upd)
dup=$(grep '^Id=' /usr/share/kconf_update/atlasos.upd | sort | uniq -d)
[ -z "$dup" ]
[ -f /usr/share/flatpak/remotes.d/flathub.flatpakrepo ]
[ -f /usr/share/flatpak/preinstall.d/atlasos.preinstall ]
# Nothing may apply an update or reboot unattended (bootc-fetch-apply-updates
# runs `bootc upgrade --apply`; rpm-ostreed-automatic can stage and reboot).
for t in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer; do
	[ "$(systemctl is-enabled "$t")" = disabled ] || {
		echo "build.sh: $t must stay disabled" >&2
		exit 1
	}
done
[ "$(systemctl is-enabled atlasos-update-stage.timer)" = enabled ]
grep -qx 'ExecStart=/usr/libexec/atlasos/update-stage' /usr/lib/systemd/system/atlasos-update-stage.service
# rpm-ostree upgrades (and the stager checks) a system with local rpm-ostree changes
rpm -q rpm-ostree skopeo >/dev/null

# Icons and logos rendered from branding/ (see branding/render.sh)
cp -a /branding/icons/. /usr/share/icons/
cp -a /branding/pixmaps/. /usr/share/pixmaps/
cp -a /branding/wallpapers/. /usr/share/wallpapers/
# Cursors: Bibata Modern Ice (light) and Classic (dark), see
# branding/cursors/README.md. They replace Breeze's, whose files go:
# plasma-integration requires the breeze-cursor-theme package, so it stays
# installed, empty. "default" is the cursor anything without its own setting
# uses (X11 apps, the login screen before Plasma's settings load).
for c in Bibata-Modern-Ice Bibata-Modern-Classic; do
	tar -xJf "/ctx/cursors/$c.tar.xz" -C /usr/share/icons --no-same-owner --no-same-permissions
	[ -f "/usr/share/icons/$c/cursors/left_ptr" ] && [ -f "/usr/share/icons/$c/index.theme" ]
done
install -Dm644 /ctx/cursors/LICENSE /usr/share/licenses/bibata-cursor-themes/LICENSE
rm -r /usr/share/icons/breeze_cursors /usr/share/icons/Breeze_Light
grep -qx 'Inherits=Adwaita' /usr/share/icons/default/index.theme
sed -i 's/^Inherits=Adwaita$/Inherits=Bibata-Modern-Ice/' /usr/share/icons/default/index.theme
# Nothing may still point at Breeze's cursors.
if grep -rIl -e breeze_cursors -e Breeze_Light /etc/xdg /usr/share/plasma/look-and-feel/org.atlasos*; then
	echo "build.sh: settings above still name Breeze's cursors" >&2
	exit 1
fi
# Icons: Dracula, for AtlasOS Light and Dark (see
# branding/icon-theme/README.md). Breeze's stay for what Dracula lacks; its own
# fallback list names themes Fedora doesn't have.
tar -xJf /ctx/icon-theme/Dracula.tar.xz -C /usr/share/icons --no-same-owner --no-same-permissions
grep -q '^Inherits=' /usr/share/icons/Dracula/index.theme
sed -i 's/^Inherits=.*/Inherits=breeze-dark,hicolor/' /usr/share/icons/Dracula/index.theme
[ -f /usr/share/icons/Dracula/scalable/places/folder.svg ]
# Its one-colour icons follow the colour scheme, as Breeze's do, instead of
# staying Dracula's near-white on AtlasOS Light (see icon-recolor.py).
python3 /ctx/icon-recolor.py /usr/share/icons/Dracula symbolic 16 22 24 32
grep -q 'ColorScheme-Text' "$(readlink -f /usr/share/icons/Dracula/symbolic/categories/applications-graphics-symbolic.svg)"
# Apps AtlasOS ships whose own icons are in other styles (Brave's under the
# name brave-origin, Ghostty's a photo-like screen): Dracula's for them too.
for alias in brave-origin:brave-browser com.mitchellh.ghostty:utilities-terminal; do
	[ -e "/usr/share/icons/Dracula/scalable/apps/${alias#*:}.svg" ]
	ln -sfn "${alias#*:}.svg" "/usr/share/icons/Dracula/scalable/apps/${alias%%:*}.svg"
done
install -Dm644 /ctx/icon-theme/LICENSE /usr/share/licenses/dracula-icons/LICENSE
# Every user must be able to read them (tar keeps the archive's modes).
if find /usr/share/icons/Dracula /usr/share/icons/Bibata-Modern-* ! -type l ! -perm -o=r | grep .; then
	echo "build.sh: the icon or cursor files above are not readable by everyone" >&2
	exit 1
fi
# "Default" (and "Fedora", which points at it) is the wallpaper anything
# without its own setting falls back to. The first-run wizard loads two
# files from it by name; branding/render.sh makes those too.
[ -L /usr/share/wallpapers/Default ]
ln -sfn AtlasOS /usr/share/wallpapers/Default

# os-release: AtlasOS on top of Fedora 44. VERSION_ID stays Fedora's so
# anything that keys on the release (dnf, toolbox, bootc-image-builder) still
# sees 44. The image's version (VERSION and IMAGE_VERSION) is "dev" here;
# version.sh puts the real one in, in the Containerfile's last step, so the
# initramfs's copy (initrd-release) keeps "dev".
# shellcheck source=/dev/null
support_end=$(. /usr/lib/os-release && echo "${SUPPORT_END:-}")
cat >/usr/lib/os-release <<EOF
NAME="AtlasOS"
VERSION="44 (dev)"
ID=atlasos
ID_LIKE=fedora
VERSION_ID=44
VERSION_CODENAME=""
PLATFORM_ID="platform:f44"
PRETTY_NAME="AtlasOS 44"
ANSI_COLOR="0;38;2;114;98;234"
LOGO=atlasos
DEFAULT_HOSTNAME="atlasos"
HOME_URL="https://github.com/EternalCoder454/AtlasOS"
BUG_REPORT_URL="https://github.com/EternalCoder454/AtlasOS/issues"
SUPPORT_END=${support_end}
VARIANT="Desktop"
VARIANT_ID=desktop
IMAGE_ID=atlasos
IMAGE_VERSION="dev"
EOF

# Fail rather than ship half-branded when Fedora moves something these edits
# rely on: each one checks the text it replaces is still there.
replace() { # file, old, new
	grep -qF -- "$2" "$1" || {
		echo "build.sh: '$2' not found in $1" >&2
		exit 1
	}
	# Escape both texts so sed treats them literally, as grep -F did.
	local old new
	old=$(printf '%s' "$2" | sed 's/[][\\.*^$|]/\\&/g')
	new=$(printf '%s' "$3" | sed 's/[\\&|]/\\&/g')
	sed -i "s|$old|$new|g" "$1"
}

# Two Global Themes, AtlasOS Light (org.atlasos.desktop, the default in
# /etc/xdg/kdeglobals) and AtlasOS Dark (org.atlasos.dark.desktop). Each is
# our metadata, defaults and layout (menu bar and dock) from system_files,
# completed with Fedora's theme and then Breeze for every file we don't have.
# Complete, because Plasma looks up missing files in Breeze's theme, which is
# removed below.
themes=/usr/share/plasma/look-and-feel
cp -a "$themes/org.atlasos.desktop/contents/layouts" "$themes/org.atlasos.dark.desktop/contents/"
for t in org.atlasos.desktop:org.fedoraproject.fedora.desktop:org.kde.breeze.desktop \
	org.atlasos.dark.desktop:org.fedoraproject.fedoradark.desktop:org.kde.breezedark.desktop; do
	IFS=: read -r ours fedora breeze <<<"$t"
	cp -a --update=none "$themes/$fedora/." "$themes/$ours/"
	cp -a --update=none "$themes/$breeze/." "$themes/$ours/"

	# App launcher icon for Kickoff, Kicker and Dashboard added later by hand
	# (the taskbar's own start button gets it from the layout script)
	for f in "$themes/$ours"/contents/plasmoidsetupscripts/org.kde.plasma.{kickoff,kicker,kickerdash}.js; do
		replace "$f" '"icon", "start-here"' '"icon", "atlasos"'
	done

	# Plasma splash: Fedora's splash, with the AtlasOS mark in place of
	# Plasma's. The "Plasma made by KDE" credit in the corner stays.
	cp /branding/splash/atlasos.svg "$themes/$ours/contents/splash/images/atlasos.svg"
	replace "$themes/$ours/contents/splash/Splash.qml" \
		'source: "images/plasma.svgz"' 'source: "images/atlasos.svg"'
done

# The AtlasOS themes are the only ones: no other Global Themes, colour
# schemes or Plasma Styles. ("default" is the Plasma Style that follows the
# colour scheme, so it is AtlasOS Light or Dark.)
for t in "$themes"/*; do
	case ${t##*/} in
	org.atlasos.desktop | org.atlasos.dark.desktop) ;;
	*) rm -r "$t" ;;
	esac
done
find /usr/share/color-schemes -name '*.colors' ! -name 'AtlasOS*.colors' -delete
rm -r /usr/share/plasma/desktoptheme/breeze-dark /usr/share/plasma/desktoptheme/breeze-light
# The AtlasOS Plasma style (system_files) is Breeze with its own dock
# indicators (widgets/tasks.svg); everything else falls back to "default".
# Breeze's settings (blur behind panels and popups) come along.
cp /usr/share/plasma/desktoptheme/default/plasmarc /usr/share/plasma/desktoptheme/atlasos/plasmarc
# Copied symlinks that pointed into a removed theme would now break quietly.
dangling=$(find "$themes" /usr/share/plasma/desktoptheme -xtype l)
[ -z "$dangling" ] || {
	echo "build.sh: broken links after removing themes:" >&2
	echo "$dangling" >&2
	exit 1
}

# AtlasOS Light's colours for every KDE program that runs outside a Plasma
# session too, the login screen above all. A user's own theme choice is
# written to their kdeglobals and overrides these.
awk '/^\[/ { keep = /^\[(Colors:|ColorEffects:|WM\])/ } keep' \
	/usr/share/color-schemes/AtlasOSLight.colors >>/etc/xdg/kdeglobals

# Login screen, macOS style: the blurred, tinted sakura picture with the clock
# above the user's avatar and password field. (The lock screen uses the same
# picture, set in /etc/xdg/kscreenlockerrc.) New users' desktop wallpaper is
# in the themes' defaults.
replace /usr/lib/plasmalogin/defaults.conf \
	"file:///usr/share/wallpapers/Fedora/" "file:///usr/share/wallpapers/AtlasOS-Login/"
grep -qx '\[Greeter\]' /usr/lib/plasmalogin/defaults.conf
sed -i -e '/^ShowClock=/d' -e '/^\[Greeter\]$/a ShowClock=true' /usr/lib/plasmalogin/defaults.conf

# Boot splash: Fedora's spinner theme with the AtlasOS lockup as the watermark
mkdir -p /usr/share/plymouth/themes/atlasos
cp -a /usr/share/plymouth/themes/spinner/. /usr/share/plymouth/themes/atlasos/
rm /usr/share/plymouth/themes/atlasos/spinner.plymouth
cp /branding/plymouth/watermark.png /usr/share/plymouth/themes/atlasos/watermark.png
plymouth-set-default-theme atlasos

# Plymouth lives in the initramfs, so it has to be rebuilt to pick the theme up.
kver=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n')
[ -n "$kver" ] && [ "$(wc -l <<<"$kver")" -eq 1 ] || {
	echo "build.sh: expected one kernel, found: $kver" >&2
	exit 1
}
dracut --no-hostonly --kver "$kver" --reproducible --add ostree \
	-f "/usr/lib/modules/$kver/initramfs.img"

# New icons and wallpapers need the icon cache to know about them
gtk-update-icon-cache -f /usr/share/icons/hicolor
gtk-update-icon-cache -f /usr/share/icons/Dracula

### Clean up

/ctx/cleanup.sh
