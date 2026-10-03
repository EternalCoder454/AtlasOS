#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 1 of 4: packages. Runs in the
# Containerfile's first RUN step on the base image, with the patched KIO and
# plasma-setup RPMs at /kio-rpms and /plasma-setup-rpms. Its own step, with
# nothing else from the repository bound in, so a change to system_files,
# branding or the Atlas apps doesn't reinstall every package: Podman reuses
# this step until the base image, this script or those RPMs change, or the
# day does (PACKAGES_DATE, so the repos' updates still arrive daily). Then
# apps.sh, then build.sh.
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

# Everyday names for the everyday apps, in every language (as macOS calls
# its file manager Finder everywhere): Terminal, Files, Store and Notepad.
# Only the app's own entry is renamed, not its actions; searching the old
# name still finds it. Ghostty's shortcut copy above is renamed with it.
rename_app() { # desktop file, new name
	local old
	old=$(sed -n '/^\[Desktop Entry\]$/,/^\[/ s/^Name=//p' "$1")
	[ -n "$old" ] || {
		echo "packages.sh: no Name= in $1" >&2
		exit 1
	}
	awk -v new="$2" -v old="$old" '
		/^\[/ { entry = ($0 == "[Desktop Entry]") }
		entry && /^Name\[/ { next }
		entry && /^Name=/ { $0 = "Name=" new }
		entry && /^Keywords=/ { $0 = $0 (/;$/ ? "" : ";") old ";" }
		{ print }' "$1" >"$1.new"
	mv "$1.new" "$1"
	grep -q "^Keywords=.*;$old;\$" "$1" || {
		echo "packages.sh: $1 has no Keywords= to add '$old' to" >&2
		exit 1
	}
}
rename_app /usr/share/applications/com.mitchellh.ghostty.desktop Terminal
rename_app /usr/share/kglobalaccel/com.mitchellh.ghostty.desktop Terminal
rename_app /usr/share/applications/org.kde.dolphin.desktop Files
rename_app /usr/share/applications/org.kde.discover.desktop Store
rename_app /usr/share/applications/org.kde.kate.desktop Notepad

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
	echo "packages.sh: kf6-kio-core is not AtlasOS's build" >&2
	exit 1
}
[ "$(rpm -qa --qf '%{RELEASE}\n' 'kf6-kio-*' | sort -u | wc -l)" -eq 1 ] || {
	echo "packages.sh: KIO packages from different builds:" >&2
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
	echo "packages.sh: plasma-setup is not AtlasOS's build" >&2
	exit 1
}


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
	echo "packages.sh: greenboot-default-health-checks must not be installed" >&2
	exit 1
fi
# bootupd pastes each configs.d snippet into grub.cfg and writes its "### END"
# marker right after it. This one has no final newline, so the marker would
# land on its last line (save_env boot_success### END...) and break it.
snippet=/usr/lib/bootupd/grub2-static/configs.d/08_greenboot.cfg
[ -f "$snippet" ]
[ -z "$(tail -c1 "$snippet")" ] || echo >>"$snippet"

/ctx/cleanup.sh
