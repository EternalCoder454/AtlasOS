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
	# Left behind by the removals above, with nothing else using them:
	# Akonadi's MariaDB server and Qt driver, DrKonqi's helpers, KJournald's
	# and Partition Manager's libraries, and help pages without KHelpCenter.
	mariadb-server
	mariadb-backup
	mariadb-cracklib-password-check
	mariadb-gssapi-server
	qt6-qtbase-mysql
	python3-sentry-sdk
	python3-pygdbmi
	xapian-core-libs
	kjournald-libs
	kpmcore
	plasma-desktop-doc
	# Unused: Konqueror's bookmark editor, Python's Qt bindings, and sos
	# (Red Hat's support-case report tool).
	keditbookmarks
	keditbookmarks-libs
	python3-pyside6
	sos
	# Xwayland Video Bridge (30 MiB, running all the time) lets X11 apps
	# share Wayland windows; apps share the screen through the portal now.
	xwaylandvideobridge
	# KDE's push-notification service starts with every session; no app here
	# uses it.
	kunifiedpush
)
"${dnf[@]}" remove "${remove[@]}"
# What only those used. rpm-ostree images don't record why a package was
# installed, so dnf can't find these by itself.
"${dnf[@]}" remove mariadb mariadb-common mariadb-errmsg mariadb-connector-c \
	mariadb-connector-c-config python3-shiboken6 python3-boto3 python3-botocore \
	python3-s3transfer python3-jmespath

# power-profiles-daemon in place of TuneD and its PPD bridge: the same power
# profiles in Plasma's battery applet and in powerdevil, for about 5 MiB
# instead of 50.
"${dnf[@]}" swap tuned-ppd power-profiles-daemon
"${dnf[@]}" remove tuned
systemctl enable power-profiles-daemon.service

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
	plymouth zram-generator power-profiles-daemon xorg-x11-server-Xwayland
	podman podman-compose podman-docker toolbox distrobox git gh just mise
	kde-settings-plasma plasma-lookandfeel-fedora fedora-release-kinoite
)
rpm -q "${keep[@]}"

### KIO

# Fedora's kf6-kio rebuilt with AtlasOS's fix for a crash on closing Dolphin
# (the kio stage of the Containerfile, bound in at /kio-rpms; see
# kio/build-rpm.sh). Only the parts Kinoite has are updated, all to the
# same release.
#
# The RPMs are built in a fedora:44 container against Fedora's newest
# libraries. With every repo off, the upgrade fails if they need newer Qt or
# KDE libraries than the base image has, rather than pulling those in.
kio=()
for f in /kio-rpms/*.rpm; do
	rpm -q "$(rpm -qp --qf '%{NAME}' "$f")" >/dev/null 2>&1 && kio+=("$f")
done
[ ${#kio[@]} -gt 0 ]
"${dnf[@]}" --disablerepo='*' upgrade "${kio[@]}"
rpm -q kf6-kio-core | grep -q '\.atlas1\.' || {
	echo "build.sh: kf6-kio-core is not AtlasOS's build" >&2
	exit 1
}
[ "$(rpm -qa --qf '%{RELEASE}\n' 'kf6-kio-*' | sort -u | wc -l)" -eq 1 ] || {
	echo "build.sh: KIO packages from different builds:" >&2
	rpm -qa 'kf6-kio-*' >&2
	exit 1
}

### First-run wizard

# Fedora's plasma-setup rebuilt in AtlasOS's style (the plasma-setup stage of
# the Containerfile, bound in at /plasma-setup-rpms; see
# plasma-setup/build-rpm.sh). AtlasOS's launcher page beside it is in
# system_files (org.atlasos.plasmasetup.launcher).
# Only the parts Kinoite has, with every repo off, as for KIO.
ps=()
for f in /plasma-setup-rpms/*.rpm; do
	rpm -q "$(rpm -qp --qf '%{NAME}' "$f")" >/dev/null 2>&1 && ps+=("$f")
done
[ ${#ps[@]} -gt 0 ]
"${dnf[@]}" --disablerepo='*' upgrade "${ps[@]}"
rpm -q plasma-setup | grep -q '\.atlas1\.' || {
	echo "build.sh: plasma-setup is not AtlasOS's build" >&2
	exit 1
}

### Atlas apps

# Atlas Updater and atlas-core, built by the atlas-apps stage of the
# Containerfile (bound in at /atlas-rpms; nothing is copied into the image).
# They are required parts of the system: the build fails without them, and
# atlas-core ships /etc/dnf/protected.d/atlas.conf so dnf won't remove them.
"${dnf[@]}" install /atlas-rpms/*.rpm
rpm -q atlas-core atlas-updater
[ -f /etc/dnf/protected.d/atlas.conf ]
# The updater autostarts in the tray at login (users can turn that off in
# System Settings; the background staging timer above does not depend on it).
rpm -ql atlas-updater >/tmp/atlas-updater.files
grep -q '/autostart/' /tmp/atlas-updater.files
rm /tmp/atlas-updater.files

### Boot health checks

# greenboot (greenboot-rs, made for bootc): after an update it runs the checks
# in /usr/lib/greenboot/check, reboots on failure, and rolls the update back
# when the retries are used up. Not greenboot-default-health-checks: its
# repository DNS check fails offline and would roll back good updates on
# laptops without a network. The checks are AtlasOS's own, in system_files.
"${dnf[@]}" install greenboot
rpm -q greenboot
# The health-check hooks and update-stage-condition use these.
command -v jq bootc grub2-editenv >/dev/null
if rpm -q greenboot-default-health-checks >/dev/null 2>&1; then
	echo "build.sh: greenboot-default-health-checks must not be installed" >&2
	exit 1
fi
# bootupd pastes each configs.d snippet into grub.cfg and writes its "### END"
# marker right after it. This one has no final newline, so the marker would
# land on its last line (save_env boot_success### END...) and break it.
snippet=/usr/lib/bootupd/grub2-static/configs.d/08_greenboot.cfg
[ -f "$snippet" ]
[ -z "$(tail -c1 "$snippet")" ] || echo >>"$snippet"

### Services

# dnf can't change an image-based system, so refreshing its metadata in the
# background only costs memory, disk and bandwidth.
systemctl disable dnf-makecache.timer

# Background update checks stage an update and never apply it:
# atlasos-update-stage.timer runs `bootc upgrade` (download and stage, no
# reboot). The two timers that apply or reboot by themselves stay off.
systemctl disable bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer

# Power profiles come from power-profiles-daemon (swapped in above).
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

# Atlas Updater is the only update notifier. Discover's (plasma-discover-notifier,
# removed above) and every other background updater stay out, and Discover
# never updates on its own.
[ ! -e /usr/libexec/DiscoverNotifier ]
[ -z "$(find /etc/xdg/autostart /usr/share/applications -iname '*discover*notifier*' -print -quit)" ]
for p in plasma-discover-notifier PackageKit; do
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
grep -qx 'ExecStart=/usr/bin/bootc upgrade --quiet' /usr/lib/systemd/system/atlasos-update-stage.service

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

# Package docs (140 MB): READMEs, changelogs and KDE's handbooks, which
# nothing here opens (KHelpCenter is gone; Help buttons go to docs.kde.org).
# License texts stay, wherever a package put them; man pages stay too.
find /usr/share/doc -type f \
	! -iname '*licen[cs]e*' ! -iname '*copying*' ! -iname '*notice*' -delete
find /usr/share/doc -type l -delete
find /usr/share/doc -mindepth 1 -type d -empty -delete

# Nothing written to /var during the build belongs in the image. The dnf cache
# is left alone when it is the host's, bound in for the next build.
rm -rf /var/lib/dnf /var/log/dnf5.log* /run/dnf /var/cache/ldconfig/aux-cache \
	/var/lib/power-profiles-daemon # systemd makes it (StateDirectory=)
mountpoint -q /var/cache/libdnf5 || rm -rf /var/cache/libdnf5
