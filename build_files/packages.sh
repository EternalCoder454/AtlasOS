#!/usr/bin/env bash
# Turns stock Fedora Kinoite into Telamon OS, part 1 of 4: packages. Runs in the
# Containerfile's first RUN step on the base image, with the patched KIO
# RPMs at /kio-rpms. Its own step, with
# nothing else from the repository bound in, so a change to system_files,
# branding or the Telamon apps doesn't reinstall every package: Podman reuses
# this step until the base image, this script or those RPMs change, or the
# day does (PACKAGES_DATE, so the repos' updates still arrive daily). Then
# apps.sh, then build.sh.
set -euxo pipefail
: >/tmp/atlasos-step-start # (see cleanup.sh, "Times")

# Every dnf call keeps its downloads, so the cache the Justfile and CI bind to
# /var/cache/libdnf5 is worth saving. It never reaches the image: a build
# volume is not part of any layer.
# SOURCE_DATE_EPOCH: rpm 6 writes it, not the clock, as a package's install time
# (and transaction id) in the RPM database, a 100 MB file that was new in every
# build for nothing but those times (36 MB of every update). An installed
# system has no use for the build's clock either.
dnf=(env SOURCE_DATE_EPOCH=1 dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Third-party repos: pinned keys
# Ghostty's COPR and NVIDIA's container toolkit are outside repos. Their .repo files are in
# build_files/repos and their public keys in build_files/keys (downloaded once
# over https, fingerprints pinned below), so nothing is trusted on first use
# from the vendor's own server. vendor_repo checks the key against the pinned
# fingerprints, then puts the key and the repo file where the .repo file's
# gpgkey=file:// line expects them. Each repo goes again after its install.
vendor_repo() {
	local name=$1 key=$2 got want gnupg
	shift 2
	gnupg=$(mktemp -d)
	# The primary key's fingerprint of every key block in the file.
	got=$(GNUPGHOME=$gnupg gpg --batch --show-keys --with-colons "/ctx/keys/$key" |
		awk -F: '$1 == "pub" { p = 1; next } $1 == "sub" { p = 0 } $1 == "fpr" && p { print $10; p = 0 }' |
		sort | tr '\n' ' ')
	rm -rf "$gnupg"
	want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
	if [ -z "$got" ] || [ "$got" != "$want" ]; then
		echo "packages.sh: the $name key in build_files/keys is not the pinned one" >&2
		echo "  pinned: $want" >&2
		echo "  found:  $got" >&2
		echo "  vendor rotated its key: check and update build_files/keys and the fingerprints in packages.sh" >&2
		exit 1
	fi
	# dnf skips a repo whose key file is missing, so the paths must agree.
	grep -qx "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-atlasos-$name" "/ctx/repos/$name.repo"
	install -Dm644 "/ctx/keys/$key" "/etc/pki/rpm-gpg/RPM-GPG-KEY-atlasos-$name"
	install -Dm644 "/ctx/repos/$name.repo" "/etc/yum.repos.d/$name.repo"
}
vendor_repo_remove() {
	rm -f "/etc/yum.repos.d/$1.repo" "/etc/pki/rpm-gpg/RPM-GPG-KEY-atlasos-$1"
}

### Packages

# Apps and background services a minimal desktop does without. Everything a
# user can see on a stock desktop is in "keep" below and checked afterwards.
# Not here because Kinoite never had them: LibreOffice, ABRT and KDE games.
remove=(
	# Ark: Telamon Archive replaces it (both ship KIO service menus)
	ark
	ark-libs
	# Spectacle: Telamon Screenshot replaces it (everything but screen
	# recording). Removed before apps.sh installs telamon-screenshot-spectacle-compat,
	# which Conflicts with it and Provides spectacle for what asks for it.
	spectacle
	# KDE PIM: the Akonadi server and the MariaDB it runs on
	akonadi-server
	akonadi-server-mysql
	# Baloo's file indexer. Its library stays: Dolphin and plasma-workspace
	# link it, and it does nothing without the indexer.
	kf6-baloo-file
	# Discover's tray notifier, which checks for and applies updates in the
	# background. Discover itself stays as the Flatpak front end.
	plasma-discover-notifier
	# Discover's OS updates: a second updater beside Telamon Updater. Its check
	# (rpm-ostree's) never sees a new Telamon OS image, and its "new major
	# version" offer rewrites the image tag (telamonos:stable to telamonos:45),
	# which would take the machine off its channel. Telamon Updater handles the
	# OS; Discover keeps apps (Flatpak) and firmware (fwupd).
	plasma-discover-rpm-ostree
	# Kinoite's gdb: nothing in the image needs it, and the installer's
	# "Choose your apps" step offers it (in a toolbox, with strace and perf).
	gdb
	gdb-headless
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
	# KWrite and the Kate library only it uses: Telamon Notepad is the editor.
	kwrite
	kate-libs
	plasma-systemmonitor
	plasma-welcome
	plasma-welcome-fedora
	firewall-config # the Firewall app; firewalld itself stays
	kde-partitionmanager
	kdebugsettings
	# No browser is preinstalled: the installer's "Choose your apps" step
	# offers Brave and Firefox.
	firefox
	firefox-langpacks
	# The terminal is Ghostty (below). DrKonqi, KDE's crash reporter, needs
	# Konsole and goes with it; systemd-coredump still records crashes.
	konsole
	plasma-drkonqi
	# Wallpaper sets nothing depends on. (Fedora's own F44 set is removed at
	# the end, past the dependency that holds it.)
	fedora-workstation-backgrounds
	plasma-workspace-wallpapers
	# Fedora's bookmarks page, and the Chromium policy packages: all they
	# install is the Plasma Integration extension for Chromium and Chrome,
	# which a Chromium browser the user adds later doesn't need here. Nothing
	# requires any of them.
	fedora-bookmarks
	fedora-chromium-config
	fedora-chromium-config-kde
	# Fedora Linux's entry for Discover and other app stores (the OS itself,
	# with its release notes link): Telamon OS is not Fedora Linux 44.
	fedora-appstream-metadata
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
	# mcelog, a daemon on every Intel machine, decodes hardware error reports
	# through the old /dev/mcelog interface; the kernel already logs them to
	# the journal, and AMD machines never ran it.
	mcelog
	# KDE Info Center (and System Settings' About page, which it carries):
	# Telamon Monitor's System Info and Devices pages show the same, and the
	# menu's About This Computer opens them. (kde-cli-tools' kinfo, which
	# only prints what Info Center knows, says it isn't installed.)
	kinfocenter
)
"${dnf[@]}" remove "${remove[@]}"
# What only those used. rpm-ostree images don't record why a package was
# installed, so dnf can't find these by itself.
"${dnf[@]}" remove mariadb mariadb-common mariadb-errmsg mariadb-connector-c \
	mariadb-connector-c-config python3-shiboken6 python3-boto3 python3-botocore \
	python3-s3transfer python3-jmespath

# NVIDIA's GSP firmware (about 100 MB, already xz-compressed, so it costs the
# ISO the same) only serves nouveau on GeForce 16 / RTX 20 and newer. Telamon
# Updater moves those machines to atlasos-nvidia (the same image as
# telamonos-nvidia), whose driver brings its own
# GSP firmware, so the base image leaves it out. Older cards keep their small
# nouveau firmware.
# The gsp entries are directories or links to another chip's; a link left
# pointing into a removed one goes too.
find /usr/lib/firmware/nvidia -name gsp -prune -exec rm -rf {} +
find /usr/lib/firmware/nvidia -xtype l -delete

# power-profiles-daemon in place of TuneD and its PPD bridge: the same power
# profiles in Plasma's battery applet and in powerdevil, for about 5 MiB
# instead of 50.
"${dnf[@]}" swap tuned-ppd power-profiles-daemon
"${dnf[@]}" remove tuned
systemctl enable power-profiles-daemon.service

# Fedora's logos out, the generic ones in; the Telamon OS ones go on top below.
"${dnf[@]}" swap fedora-logos generic-logos

# IBM Plex Sans for the interface and JetBrains Mono for terminals and code
# (fontconfig and kdeglobals in system_files make them the defaults).
"${dnf[@]}" install ibm-plex-sans-fonts jetbrains-mono-fonts

# Papirus is the icon theme: Papirus for Telamon Light, Papirus-Dark (a
# separate package, mostly links into Papirus) for Telamon Dark. Not
# -light: that is a variant in Breeze's colours that Telamon OS doesn't use.
# build.sh turns its folders violet.
"${dnf[@]}" install papirus-icon-theme papirus-icon-theme-dark
[ -f /usr/share/icons/Papirus/index.theme ]
[ -f /usr/share/icons/Papirus-Dark/index.theme ]

# Ghostty, the terminal, in place of Konsole. Fedora doesn't package it; this
# is the COPR that Ghostty's own install guide points Fedora users to. The
# repo goes again afterwards: the image is updated by rebuilding it, not by dnf.
# Key: https://download.copr.fedorainfracloud.org/results/scottames/ghostty/pubkey.gpg
# (COPR doesn't sign its repodata, so repo_gpgcheck=0; the packages are signed.)
vendor_repo ghostty ghostty.gpg 2DEFB319CCC3F393B6DAEAB297C83CA0FEB5DAFB
"${dnf[@]}" install ghostty
vendor_repo_remove ghostty
# Ghostty's package adds "Open Ghostty Here" to Dolphin's right-click menu,
# beside Dolphin's own "Open Terminal Here", which opens Ghostty there too
# (/etc/xdg/kdeglobals TerminalApplication, a separate instance so it gets the
# folder even with a Ghostty window open): one entry is enough. A plain rm, so the
# build fails if the package moves it.
rm /usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop
# Started by its Exec line, not by D-Bus. The package's desktop file says
# DBusActivatable=true, so the dock, the launcher and Ctrl+Alt+T (KIO) asked
# D-Bus to start it through the systemd user unit app-com.mitchellh.ghostty
# (Type=notify-reload) and waited for its reply. When that unit never
# reported ready, nothing opened and KIO showed "Did not receive a reply"
# after 25 s. The Exec line starts Ghostty directly and still joins a running
# instance. Done before the kglobalaccel copy below so both say the same; the
# grep fails the build if the package stops setting the key.
grep -qx 'DBusActivatable=true' /usr/share/applications/com.mitchellh.ghostty.desktop
sed -i 's/^DBusActivatable=true$/DBusActivatable=false/' /usr/share/applications/com.mitchellh.ghostty.desktop
# Ctrl+Alt+T opens it, as it opened Konsole. Plasma takes launch shortcuts
# from the desktop files in /usr/share/kglobalaccel.
sed '/^\[Desktop Entry\]$/a X-KDE-Shortcuts=Ctrl+Alt+T' \
	/usr/share/applications/com.mitchellh.ghostty.desktop \
	>/usr/share/kglobalaccel/com.mitchellh.ghostty.desktop

# Developer tools: Telamon OS is for developers. Containers (Podman with a
# `docker` command and compose; toolbox and distrobox for mutable dev
# environments) and everyday command-line tools; just runs `telamon`, the
# command menu (/usr/share/telamon/telamon.just). gh, mise, gdb, strace and perf
# are not preinstalled: the installer's "Choose your apps" step
# offers them. (The text editor is Telamon Notepad, from apps.sh.) Docker CE stays out:
# podman-docker answers to `docker`, and Docker's daemon would run as root at
# all times.
"${dnf[@]}" install \
	podman-compose podman-docker toolbox distrobox \
	git jq ripgrep fd-find curl wget2-wget just
# Kvantum is the application style (Telamon OS themes in usr/share/Kvantum): the
# Qt6 style plugin and its themes, 8 MiB installed, no Qt5.
"${dnf[@]}" install kvantum
[ -f /usr/lib64/qt6/plugins/styles/libkvantum.so ]
# podman-docker would print a warning on every `docker` command.
touch /etc/containers/nodocker

# None of the outside repos may be left behind.
leftover=$(find /etc/yum.repos.d \( -iname '*ghostty*' -o -iname '*nvidia-container*' \) -print)
[ -z "$leftover" ] || {
	echo "packages.sh: outside repos still in /etc/yum.repos.d: $leftover" >&2
	exit 1
}

# Everyday apps, native RPMs so they take the Telamon OS Kvantum style and the
# Papirus icons: Gwenview (images), Okular (PDFs and documents), Qalculate!
# (the Qt calculator), Haruna (video and audio) and Camera (Plasma Camera:
# photos and videos from the webcam, for a profile picture and the like; its
# libcamera backend also drives the MIPI cameras of newer laptops, which
# plain V4L2 apps like Kamoso can't open). The image formats beyond
# JPEG and PNG (HEIC, AVIF, WebP, JXL) come from kimageformats and
# qt6-qtimageformats, and Dolphin's PDF and image previews from
# kdegraphics-thumbnailers; named here because install_weak_deps=False would
# leave out a weak dependency on them. Okular's PDF reader is its Poppler
# generator, in okular-part. No office suite.
"${dnf[@]}" install gwenview okular okular-part qalculate-qt haruna plasma-camera \
	kf6-kimageformats qt6-qtimageformats kdegraphics-thumbnailers
[ -f /usr/lib64/qt6/plugins/okular_generators/okularGenerator_poppler.so ]

# Codecs and video decoding on the GPU. Fedora's ffmpeg, GStreamer and Mesa
# leave out H.264, H.265 and the like; RPM Fusion's builds have them. Its
# release packages add the repos here, and they are removed again below: the
# image is updated by rebuilding it, not by dnf. dnf doesn't check the
# signature of a package given by URL, and those come from whichever mirror
# answers (a failed download is tried again, which picks another), so they
# are checked here against RPM Fusion's keys from Fedora's own
# distribution-gpg-keys (in the base image): the repo keys they then add are
# RPM Fusion's.
fedora=$(rpm -E %fedora)
keys=/usr/share/distribution-gpg-keys/rpmfusion
rpmfusion=$(mktemp -d)
for repo in free nonfree; do
	curl -fsSL --retry 5 --retry-all-errors --proto '=https' --tlsv1.2 -o "$rpmfusion/$repo.rpm" \
		"https://mirrors.rpmfusion.org/$repo/fedora/rpmfusion-$repo-release-$fedora.noarch.rpm"
	# A private rpm database holding only this repo's key: by now the system's
	# holds Fedora's, Ghostty's too, and a package signed
	# by any of them would pass there.
	rpmdb=$(mktemp -d)
	rpmkeys --define "_dbpath $rpmdb" --import "$keys/RPM-GPG-KEY-rpmfusion-$repo-fedora-$fedora"
	rpmkeys --define "_dbpath $rpmdb" --checksig "$rpmfusion/$repo.rpm" | grep -q ': digests signatures OK$' || {
		echo "packages.sh: rpmfusion-$repo-release is not signed by RPM Fusion's key" >&2
		rpmkeys --define "_dbpath $rpmdb" --checksig -v "$rpmfusion/$repo.rpm" >&2
		exit 1
	}
	rm -rf "$rpmdb"
	# This release's package, not an older one a mirror kept (also signed)
	[ "$(rpm -qp --qf '%{NAME} %{VERSION}' "$rpmfusion/$repo.rpm")" = "rpmfusion-$repo-release $fedora" ] || {
		echo "packages.sh: $repo.rpm is not rpmfusion-$repo-release $fedora" >&2
		exit 1
	}
done
"${dnf[@]}" install "$rpmfusion/free.rpm" "$rpmfusion/nonfree.rpm"
rm -rf "$rpmfusion"
# - ffmpeg in place of ffmpeg-free (the libav*-free libraries go with it),
#   and the GStreamer plugins Haruna's and Qt's media backends use
# - Cisco's real OpenH264 (from fedora-cisco-openh264, already configured)
#   in place of the noopenh264 stub
# - Intel's media driver with its nonfree parts (iHD, for Broadwell and newer)
"${dnf[@]}" install --allowerasing \
	ffmpeg gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld \
	gstreamer1-plugin-libav openh264 gstreamer1-plugin-openh264 \
	intel-media-driver
# Fedora's own iHD (12 MB, without those parts) is never loaded: libva looks
# in RPM Fusion's dri-nonfree first.
if rpm -q --quiet libva-intel-media-driver; then
	"${dnf[@]}" remove libva-intel-media-driver
fi
[ -f /usr/lib64/dri-nonfree/iHD_drv_video.so ]
# AMD's video decoding with H.264 and H.265, replacing the parts of
# mesa-dri-drivers that leave them out. It must match Fedora's Mesa to the
# exact version (it requires Mesa's libgallium of that version), and RPM Fusion
# can be a few days late with a new Mesa. Then the build goes on without it:
# Fedora's own radeonsi VA-API driver stays, and decodes only the free codecs
# (VP9, AV1) on the GPU. Fedora 44 has no separate mesa-va-drivers package
# to fall back to, and no freeworld VDPAU one.
# Only a failure to find a matching package is let through; a signature or
# download failure fails the build.
if ! mesa_out=$("${dnf[@]}" install mesa-va-drivers-freeworld 2>&1); then
	printf '%s\n' "$mesa_out" >&2
	if ! grep -q 'Failed to resolve the transaction' <<<"$mesa_out" ||
		! grep -qE 'Problem|nothing provides|cannot install|none of the providers' <<<"$mesa_out" ||
		grep -qiE 'gpg|pgp|signature|checksum|digest|public key|key import' <<<"$mesa_out"; then
		echo "packages.sh: installing mesa-va-drivers-freeworld failed for a reason other than a version mismatch" >&2
		exit 1
	fi
	echo "packages.sh: WARNING: mesa-va-drivers-freeworld does not match Fedora's" \
		"$(rpm -q mesa-dri-drivers) (RPM Fusion is behind); AMD GPUs decode" \
		"H.264 and H.265 in software until it catches up" >&2
else
	printf '%s\n' "$mesa_out"
fi
# Every RPM Fusion repo goes again; the disabled steam and nvidia-driver files
# Fedora ships (fedora-workstation-repositories) stay, as the NVIDIA image
# uses the second.
"${dnf[@]}" remove rpmfusion-free-release rpmfusion-nonfree-release
if grep -q '^enabled=1' /etc/yum.repos.d/rpmfusion*.repo 2>/dev/null; then
	echo "packages.sh: an RPM Fusion repo is still enabled" >&2
	exit 1
fi
# Controller udev rules for Steam and the many pads that follow its rules.
# From Fedora's own repos: installed after RPM Fusion is gone, which proves it.
"${dnf[@]}" install steam-devices
# The result: real ffmpeg and OpenH264, and a VA-API driver for AMD (radeonsi)
# and Intel (iHD).
for p in ffmpeg-free noopenh264; do
	if rpm -q --quiet "$p"; then
		echo "packages.sh: $p is still installed" >&2
		exit 1
	fi
done
rpm -q ffmpeg openh264 gstreamer1-plugin-openh264 intel-media-driver
[ -f /usr/lib64/dri/radeonsi_drv_video.so ]
[ -f /usr/lib64/dri-nonfree/iHD_drv_video.so ]
[ -f /usr/lib64/dri-freeworld/radeonsi_drv_video.so ] ||
	echo "packages.sh: WARNING: radeonsi has no freeworld VA-API driver" >&2

# Printing: CUPS (in keep below, started on demand by its socket) and KDE's
# printer settings (Fedora's plasma-print-manager).
"${dnf[@]}" install plasma-print-manager
systemctl enable cups.socket

# The firewall's page in System Settings (firewalld's backend for it), so a
# port can be opened without a terminal. firewall-config, a separate app,
# stays out. The Telamon OS zone (build.sh) is what it starts from.
"${dnf[@]}" install plasma-firewall-firewalld

# The desktop the image promises. A removal above that took one of these with
# it fails the build here instead of shipping a broken image.
keep=(
	plasma-workspace plasma-desktop kwin ghostty dolphin plasma-systemsettings
	plasma-login-manager NetworkManager NetworkManager-wifi
	pipewire pipewire-pulseaudio wireplumber bluez cups
	flatpak plasma-discover plasma-discover-flatpak
	plymouth zram-generator power-profiles-daemon xorg-x11-server-Xwayland
	podman podman-compose podman-docker toolbox distrobox git just
	gwenview okular qalculate-qt haruna plasma-camera ffmpeg openh264 steam-devices plasma-print-manager
	firewalld plasma-firewall-firewalld
	kde-settings-plasma plasma-lookandfeel-fedora fedora-release-kinoite
)
rpm -q "${keep[@]}"
# What the installer's "Choose your apps" step offers is not preinstalled:
# none of these may be in the image (or pulled back as a dependency).
for pkg in brave-origin brave-browser firefox gh mise gdb strace perf; do
	if rpm -q --quiet "$pkg"; then
		echo "packages.sh: $pkg is installed; it is offered at first boot instead" >&2
		exit 1
	fi
done

# Everyday names for the everyday apps, in every language (as macOS calls
# its file manager Finder everywhere): Terminal, Files (Telamon Explorer) and Discover. (Telamon
# Notepad is called Notepad already.)
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
rename_app /usr/share/applications/org.kde.dolphin.desktop Dolphin
rename_app /usr/share/applications/org.kde.discover.desktop Discover

# Tools kept but left out of the app menu. Kvantum Manager would fight
# kvantum-sync, which sets the theme from Telamon Light/Dark. Menu Editor
# can't go (plasma-desktop requires it) and stays a right-click away on the
# launcher ("Edit Applications").
hide_app() { # desktop file
	grep -q '^NoDisplay=' "$1" && {
		echo "packages.sh: $1 already sets NoDisplay=" >&2
		exit 1
	}
	sed -i '0,/^\[Desktop Entry\]$/ s//&\nNoDisplay=true/' "$1"
	grep -qx 'NoDisplay=true' "$1" || {
		echo "packages.sh: couldn't hide $1" >&2
		exit 1
	}
}
hide_app /usr/share/applications/kvantummanager.desktop
hide_app /usr/share/applications/org.kde.kmenuedit.desktop

### KIO

# Fedora's kf6-kio rebuilt with Telamon OS's fix for a crash on closing Dolphin
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
	echo "packages.sh: kf6-kio-core is not Telamon OS's build" >&2
	exit 1
}
[ "$(rpm -qa --qf '%{RELEASE}\n' 'kf6-kio-*' | sort -u | wc -l)" -eq 1 ] || {
	echo "packages.sh: KIO packages from different builds:" >&2
	rpm -qa 'kf6-kio-*' >&2
	exit 1
}

### First-run wizard

# Fedora's plasma-setup is not part of Telamon OS: Telamon Setup (apps.sh) is the
# first-run setup. Kinoite ships it, so it goes here, and the build fails if
# it is still there or if removing it took the desktop with it.
if rpm -q --quiet plasma-setup; then
	"${dnf[@]}" remove plasma-setup
fi
if rpm -q --quiet plasma-setup; then
	echo "packages.sh: plasma-setup is still installed" >&2
	exit 1
fi
rpm -q plasma-workspace plasma-login-manager kwin >/dev/null


### Boot health checks

# greenboot (greenboot-rs, made for bootc): after an update it runs the checks
# in /usr/lib/greenboot/check, reboots on failure, and rolls the update back
# when the retries are used up. Not greenboot-default-health-checks: its
# repository DNS check fails offline and would roll back good updates on
# laptops without a network. The checks are Telamon OS's own, in system_files.
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
