#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS. Runs once, inside the Containerfile's
# main RUN step, with the repo's build context at /ctx and the rendered
# branding at /branding.
set -euxo pipefail

# Every dnf call keeps its downloads, so the cache the Justfile and CI bind to
# /var/cache/libdnf5 is worth saving. It never reaches the image: a build
# volume is not part of any layer.
dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Packages

# Apps and background services a minimal desktop does without. Everything a
# user can see on a stock desktop is in "keep" below and checked afterwards.
# Not here because Kinoite never had them: LibreOffice, ABRT and KDE games.
remove=(
	# KDE PIM: the Akonadi server and the MariaDB it runs on
	akonadi-server
	akonadi-server-mysql
	# Baloo's file indexer. Its library stays: Dolphin and plasma-workspace
	# link it, and it does nothing without the indexer.
	kf6-baloo-file
	# Discover's tray notifier, which checks for and applies updates in the
	# background. Discover itself stays as the Flatpak front end.
	plasma-discover-notifier
	# KDE Connect starts a daemon in every session.
	kde-connect
	kde-connect-libs
	kdeconnectd
	# Extra KDE apps
	filelight
	kcharselect
	kfind
	khelpcenter
	kjournald
	krfb
	krfb-libs
	kwalletmanager5
	kwrite
	plasma-systemmonitor
	plasma-welcome
	plasma-welcome-fedora
	firewall-config # the Firewall app; firewalld itself stays
	kde-partitionmanager
	kdebugsettings
	# The browser is Brave Origin (below).
	firefox
	firefox-langpacks
	# The terminal is Ghostty (below). DrKonqi, KDE's crash reporter, needs
	# Konsole and goes with it; systemd-coredump still records crashes.
	konsole
	plasma-drkonqi
	# Wallpaper sets nothing depends on. The F44 set stays because
	# kde-settings requires it.
	fedora-workstation-backgrounds
	plasma-workspace-wallpapers
)
"${dnf[@]}" remove "${remove[@]}"

# Fedora's logos out, the generic ones in; the AtlasOS ones go on top below.
"${dnf[@]}" swap fedora-logos generic-logos

# IBM Plex Sans for the interface and JetBrains Mono for terminals and code
# (fontconfig and kdeglobals in system_files make them the defaults).
"${dnf[@]}" install ibm-plex-sans-fonts jetbrains-mono-fonts

# Ghostty, the terminal, in place of Konsole. Fedora doesn't package it; this
# is the COPR that Ghostty's own install guide points Fedora users to. The
# repo goes again afterwards: the image is updated by rebuilding it, not by dnf.
curl -fsSL --retry 3 -o /etc/yum.repos.d/ghostty.repo \
	"https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-$(rpm -E %fedora)/scottames-ghostty-fedora-$(rpm -E %fedora).repo"
"${dnf[@]}" install ghostty
rm /etc/yum.repos.d/ghostty.repo
# Ghostty's package brings "Open Ghostty Here" to Dolphin's right-click menu.
# Ctrl+Alt+T opens it, as it opened Konsole. Plasma takes launch shortcuts
# from the desktop files in /usr/share/kglobalaccel.
sed '/^\[Desktop Entry\]$/a X-KDE-Shortcuts=Ctrl+Alt+T' \
	/usr/share/applications/com.mitchellh.ghostty.desktop \
	>/usr/share/kglobalaccel/com.mitchellh.ghostty.desktop

# Brave Origin, the browser: Brave without its AI, crypto wallet, rewards,
# VPN and news, free on Linux. It isn't on Flathub, so it comes unmodified
# from Brave's own RPM repo, which goes again afterwards like Ghostty's.
curl -fsSL --retry 3 -o /etc/yum.repos.d/brave-browser.repo \
	https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
# It installs into /opt, which on an image-based system is /var/opt: state,
# not part of the image. So install it there, move it into /usr, and link
# it back on every boot.
mkdir -p /var/opt
"${dnf[@]}" install brave-origin
rm /etc/yum.repos.d/brave-browser.repo
mkdir -p /usr/lib/opt
mv /var/opt/brave.com /usr/lib/opt/
rmdir /var/opt
echo "L /var/opt/brave.com - - - - /usr/lib/opt/brave.com" >/usr/lib/tmpfiles.d/atlasos-brave.conf
# Its daily job puts the repo back to update it; the image does that.
rm -f /etc/cron.daily/brave-origin
# The default browser in /etc/xdg names this launcher; its scriptlets must not
# have put the repo back.
[ -f /usr/share/applications/brave-origin.desktop ]
[ ! -e /etc/yum.repos.d/brave-browser.repo ]

# Developer tools: AtlasOS is for developers. Containers (Podman with a
# `docker` command and compose; toolbox and distrobox for mutable dev
# environments), everyday command-line tools, debuggers and profilers, and
# Kate as the text editor. Docker CE stays out: podman-docker answers to
# `docker`, and Docker's daemon would run as root at all times.
"${dnf[@]}" install \
	podman-compose podman-docker toolbox distrobox \
	git gh just jq ripgrep fd-find btop curl wget2-wget gdb strace perf \
	kate
# podman-docker would print a warning on every `docker` command.
touch /etc/containers/nodocker

# mise manages language versions (Node, Python, Go...) per user and project.
# Fedora doesn't package it; this is mise's own signed RPM repo, which goes
# again afterwards. /etc/profile.d/atlasos-mise.sh turns it on in shells.
curl -fsSL --retry 3 -o /etc/yum.repos.d/mise.repo https://mise.jdx.dev/rpm/mise.repo
"${dnf[@]}" install mise
rm /etc/yum.repos.d/mise.repo

# The desktop the image promises. A removal above that took one of these with
# it fails the build here instead of shipping a broken image.
keep=(
	plasma-workspace kwin ghostty brave-origin dolphin kate plasma-systemsettings kinfocenter
	plasma-login-manager NetworkManager NetworkManager-wifi
	pipewire pipewire-pulseaudio wireplumber bluez cups
	flatpak plasma-discover plasma-discover-flatpak
	plymouth zram-generator
	podman podman-compose podman-docker toolbox distrobox git gh just mise
	kde-settings-plasma plasma-lookandfeel-fedora fedora-release-kinoite
)
rpm -q "${keep[@]}"

### Services

# dnf can't change an image-based system, so refreshing its metadata in the
# background only costs memory, disk and bandwidth.
systemctl disable dnf-makecache.timer

# Background update checks stage an update and never apply it:
# atlasos-update-stage.timer runs `bootc upgrade` (download and stage, no
# reboot). The two timers that apply or reboot by themselves stay off.
systemctl disable bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer

### Branding

cp -a /ctx/system_files/. /

# The kernel sizes the inotify watch limit by RAM; this raises it to 524288
# where it is lower (IDEs and file watchers run out), and never lowers it.
systemctl enable atlasos-inotify-watches.service
systemctl enable atlasos-update-stage.timer
# Nothing may apply an update or reboot unattended (bootc-fetch-apply-updates
# runs `bootc upgrade --apply`; rpm-ostreed-automatic can stage and reboot).
for t in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer; do
	[ "$(systemctl is-enabled "$t")" = disabled ] || {
		echo "build.sh: $t must stay disabled" >&2
		exit 1
	}
done
[ "$(systemctl is-enabled atlasos-update-stage.timer)" = enabled ]
grep -qx 'ExecStart=/usr/bin/bootc upgrade --quiet' /usr/lib/systemd/system/atlasos-update-stage.service

# Icons and logos rendered from branding/ (see branding/render.sh)
cp -a /branding/icons/. /usr/share/icons/
cp -a /branding/pixmaps/. /usr/share/pixmaps/
cp -a /branding/wallpapers/. /usr/share/wallpapers/
# "Default" (and "Fedora", which points at it) is the wallpaper anything
# without its own setting falls back to. The first-run wizard loads two
# files from it by name; branding/render.sh makes those too.
[ -L /usr/share/wallpapers/Default ]
ln -sfn AtlasOS /usr/share/wallpapers/Default

# os-release: AtlasOS on top of Fedora 44. VERSION_ID stays Fedora's so
# anything that keys on the release (dnf, toolbox, bootc-image-builder) still
# sees 44.
# shellcheck source=/dev/null
support_end=$(. /usr/lib/os-release && echo "${SUPPORT_END:-}")
cat >/usr/lib/os-release <<EOF
NAME="AtlasOS"
VERSION="44 (${IMAGE_VERSION:-dev})"
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
IMAGE_VERSION="${IMAGE_VERSION:-dev}"
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
# our metadata, defaults and Windows 11-style panel layout from system_files,
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

### Clean up

# Nothing written to /var during the build belongs in the image. The dnf cache
# is left alone when it is the host's, bound in for the next build.
rm -rf /var/lib/dnf /var/log/dnf5.log* /run/dnf /var/cache/ldconfig/aux-cache
mountpoint -q /var/cache/libdnf5 || rm -rf /var/cache/libdnf5
