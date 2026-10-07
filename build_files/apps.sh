#!/usr/bin/env bash
# Turns stock Fedora Kinoite into Telamon OS, part 2 of 4: the Telamon apps, after
# packages.sh, in a step of their own because they change more often than the
# rest of the packages. Then build.sh.
set -euxo pipefail
: >/tmp/atlasos-step-start # (see cleanup.sh, "Times")

# SOURCE_DATE_EPOCH: the RPM database's install times stay the same from build
# to build (see packages.sh).
dnf=(env SOURCE_DATE_EPOCH=1 dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Telamon apps

# telamon-framework first: Telamon.Ui (telamon-ui), the QML module every Telamon
# app imports, its Material Symbols fonts (telamon-symbols-fonts) and the
# Telamon Symbols gallery (telamon-symbols), built by the framework stage of the
# Containerfile (bound in at /telamon-framework-rpms). The apps are built
# against this Telamon.Ui and require it; no app needs the 1.x module
# (Atlas.Ui, atlas-ui) any more, so it is not in the image. Then Telamon Updater
# and telamon-system-helper (the root helper, called atlas-system-helper before
# 0.3.0 and atlas-core before that), built by the updater-app stage (at
# /telamon-updater-rpms), Telamon Monitor (the monitor-app stage, at
# /telamon-monitor-rpms) and Telamon Notepad (the notepad-app stage, at
# /telamon-notepad-rpms), Telamon Settings (the settings-app stage, at
# /telamon-settings-rpms) and Telamon Setup (the wizard-app stage, at
# /telamon-wizard-rpms), the first-run setup that replaces plasma-setup
# (packages.sh removes it); nothing is copied into the image. They are required
# parts of the system: the build fails without them, and their protected.d files
# (telamon-framework.conf from telamon-ui, telamon-updater.conf from
# telamon-system-helper, telamon-monitor.conf, telamon-notepad.conf,
# telamon-settings.conf, telamon-wizard.conf, telamon-store.conf,
# telamon-explorer.conf) stop dnf removing them.
# Every package has been renamed from atlas-<app> with Obsoletes: and Provides:
# of the old name. rpm -q matches package names, not what a package provides,
# so the checks below name the new packages.
"${dnf[@]}" install /telamon-framework-rpms/*.rpm
rpm -q telamon-ui telamon-symbols-fonts telamon-symbols
[ -f /etc/dnf/protected.d/telamon-framework.conf ]
[ -f /usr/lib64/qt6/qml/Telamon/Ui/qmldir ]
"${dnf[@]}" install /telamon-updater-rpms/*.rpm /telamon-monitor-rpms/*.rpm /telamon-notepad-rpms/*.rpm /telamon-settings-rpms/*.rpm /telamon-wizard-rpms/*.rpm /telamon-store-rpms/*.rpm /telamon-explorer-rpms/*.rpm /telamon-archive-rpms/*.rpm /telamon-launcher-rpms/*.rpm /telamon-screenshot-rpms/*.rpm
rpm -q telamon-system-helper telamon-updater telamon-monitor telamon-notepad telamon-settings telamon-wizard telamon-store telamon-explorer telamon-archive telamon-launcher telamon-screenshot
# None of the packages before the rename may be left beside the new ones.
for old in atlas-ui atlas-symbols atlas-symbols-fonts atlas-core atlas-system-helper atlas-updater atlas-monitor atlas-notepad \
	atlas-settings atlas-wizard atlas-store atlas-explorer atlas-archive atlas-launcher atlasos-screenshot; do
	if rpm -q --quiet "$old"; then
		echo "apps.sh: $old is still installed beside its Telamon package" >&2
		exit 1
	fi
done
[ -f /etc/dnf/protected.d/telamon-updater.conf ]
[ -f /etc/dnf/protected.d/telamon-monitor.conf ]
[ -f /etc/dnf/protected.d/telamon-notepad.conf ]
[ -f /etc/dnf/protected.d/telamon-settings.conf ]
[ -f /etc/dnf/protected.d/telamon-wizard.conf ]
[ -f /etc/dnf/protected.d/telamon-store.conf ]
[ -f /etc/dnf/protected.d/telamon-explorer.conf ]
# The default apps (mimeapps.list), launcher favourites and the menu name
# these.
[ -f /usr/share/applications/net.eterneon.telamon.notepad.desktop ]
[ -f /usr/share/applications/net.eterneon.telamon.monitor.desktop ]
[ -f /usr/share/applications/net.eterneon.telamon.settings.desktop ]
[ -x /usr/bin/telamon-settings ]
# Telamon Store sits beside Discover (the default for Flatpak links and RPM files).
[ -f /usr/share/applications/net.eterneon.telamon.store.desktop ]
[ -x /usr/bin/telamon-store ]
# Telamon Explorer (Files) is the default file manager (inode/directory in
# mimeapps.list) and owns org.freedesktop.FileManager1. Dolphin stays installed
# but its service file for that name goes, so it can't be started for it. The
# index service is D-Bus activated (no preset, not started at login).
[ -f /usr/share/applications/net.eterneon.telamon.explorer.desktop ]
[ -x /usr/bin/telamon-explorer ]
[ -x /usr/bin/telamon-explorer-indexd ]
[ -x /usr/bin/telamon-explorer-search ]
[ -f /usr/share/dbus-1/services/net.eterneon.telamon.explorer.Search.service ]
[ -f /usr/lib/systemd/user/telamon-explorer-indexd.service ]
[ -f /usr/share/dbus-1/services/org.freedesktop.FileManager1.service ]
rm -f /usr/share/dbus-1/services/org.kde.dolphin.FileManager1.service
[ "$(grep -l '^Name=org.freedesktop.FileManager1$' /usr/share/dbus-1/services/*.service)" = /usr/share/dbus-1/services/org.freedesktop.FileManager1.service ]
grep -q telamon-explorer /usr/share/dbus-1/services/org.freedesktop.FileManager1.service
# Telamon Archive replaces Ark (removed in packages.sh, with ark-libs); both ship
# KIO service menus, so Ark must be gone and Archive's menu present.
[ -f /usr/share/applications/net.eterneon.telamon.archive.desktop ]
[ -x /usr/bin/telamon-archive ]
[ -f /usr/share/kio/servicemenus/net.eterneon.telamon.archive.desktop ]
if rpm -q --quiet ark ark-libs; then
	echo "apps.sh: ark is still installed beside telamon-archive" >&2
	exit 1
fi
# Telamon Launcher replaces Andromeda: the binary, its user unit (enabled in
# build.sh), the D-Bus activation file, the dock button plasmoid and the
# default pins (system_files overrides the list later, in build.sh).
[ -x /usr/bin/telamon-launcher ]
[ -f /usr/lib/systemd/user/telamon-launcher.service ]
[ -f /usr/share/dbus-1/services/net.eterneon.telamon.launcher.service ]
[ -d /usr/share/plasma/plasmoids/net.eterneon.telamon.launcher.button ]
[ -f /etc/xdg/telamon-launcher/pinned.list ]
[ -f /usr/share/applications/net.eterneon.telamon.launcher.desktop ]
# The package's own Plasma update script swaps the dock button of the old id in
# the panels of existing users (the image's kconf_update migration renames it
# first, in the same login; each leaves the other nothing to do).
[ -f /usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/telamon-20261007-launcher-button.js ]
# Telamon Screenshot takes Meta+Shift+S (its .desktop, in kglobalaccel too, so
# KDE's ScreenShot2 grant matches the binary); Spectacle keeps Print and its
# other shortcuts. The kglobalaccel copy of Spectacle's file is a symlink.
[ -x /usr/bin/telamon-screenshot ]
# The old name is a link to it, which is how KWin's grant reaches the shortcut.
[ "$(readlink -f /usr/bin/atlasos-screenshot)" = /usr/bin/telamon-screenshot ]
grep -qx 'X-KDE-Shortcuts=Meta+Shift+S' /usr/share/kglobalaccel/net.eterneon.telamon.screenshot.desktop
grep -qx 'X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2' /usr/share/applications/net.eterneon.telamon.screenshot.desktop
sed -i 's/^X-KDE-Shortcuts=Print,Meta+Shift+S$/X-KDE-Shortcuts=Print/' /usr/share/applications/org.kde.spectacle.desktop
if grep -q 'Meta+Shift+S' /usr/share/applications/org.kde.spectacle.desktop; then
	echo "apps.sh: Spectacle still claims Meta+Shift+S" >&2
	exit 1
fi
grep -qx 'X-KDE-Shortcuts=Print' /usr/share/applications/org.kde.spectacle.desktop
# The first-run setup: its session user comes from the RPM's sysusers.d file
# (provides user(telamon-setup)), and its boot unit, which runs before the
# display manager on every boot, is on by the RPM's preset; enabled here too,
# so the image never depends on the scriptlet having run in a container.
rpm -q --provides telamon-wizard | grep -q '^user(telamon-setup)\( \|$\)'
[ -f /usr/lib/systemd/system/telamon-wizard-boot.service ]
[ -x /usr/libexec/telamon-wizard-boot ]
[ -f /usr/share/wayland-sessions/telamon-wizard.desktop ]
systemctl enable telamon-wizard-boot.service
[ "$(systemctl is-enabled telamon-wizard-boot.service)" = enabled ]
if rpm -q --quiet plasma-setup; then
	echo "apps.sh: plasma-setup is still installed beside telamon-wizard" >&2
	exit 1
fi
# The installer's first-boot apps step (no RPM): the Installer's firstboot/
# files, bound in at /telamon-firstboot. It installs what the "Choose your apps"
# page picked (browser, developer tools) on the first boot after setup.
/telamon-firstboot/install.sh /
[ -x /usr/libexec/telamon/telamon-first-boot-apps ]
[ -f /usr/share/telamon/first-boot-apps.json ]
[ -f /usr/lib/systemd/system/telamon-first-boot-apps.service ]
[ -f /usr/lib/systemd/user/telamon-first-boot-apps.service ]
[ -e /usr/lib/systemd/system/multi-user.target.wants/telamon-first-boot-apps.service ]
[ -e /usr/lib/systemd/user/graphical-session.target.wants/telamon-first-boot-apps.service ]
[ -f /etc/profile.d/telamon-mise.sh ]
# What the script runs: python3, gdbus (glib2), toolbox, curl and flatpak.
for tool in python3 gdbus toolbox curl flatpak; do
	command -v "$tool" >/dev/null || {
		echo "apps.sh: $tool is missing; the first-boot apps step needs it" >&2
		exit 1
	}
done
# Flathub (system_files/usr/share/flatpak/remotes.d) lands after this step; build.sh checks it.
# Telamon Monitor takes Plasma System Monitor's shortcuts (Ctrl+Shift+Esc,
# Ctrl+Esc); packages.sh removes that app.
[ -f /usr/share/kglobalaccel/net.eterneon.telamon.monitor.desktop ]
# The updater autostarts in the tray at login (users can turn that off in
# System Settings; the background staging timer doesn't depend on it).
rpm -ql telamon-updater >/tmp/telamon-updater.files
grep -q '/autostart/' /tmp/telamon-updater.files
rm /tmp/telamon-updater.files

/ctx/cleanup.sh
