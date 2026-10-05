#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 2 of 4: the Atlas apps, after
# packages.sh, in a step of their own because they change more often than the
# rest of the packages. Then build.sh.
set -euxo pipefail
: >/tmp/atlasos-step-start # (see cleanup.sh, "Times")

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Atlas apps

# atlas-framework first: Atlas.Ui (atlas-ui), the QML module every Atlas app
# imports, its Material Symbols fonts (atlas-symbols-fonts) and the Atlas
# Symbols gallery (atlas-symbols), built by the framework stage of the
# Containerfile (bound in at /atlas-framework-rpms). The apps are built
# against this Atlas.Ui and require it. Then Atlas Updater and
# atlas-system-helper (the root helper, called atlas-core before 0.1.0-2),
# built by the atlas-apps stage (at /atlas-rpms), Atlas Monitor (the
# monitor-app stage, at /atlas-monitor-rpms) and Atlas Notepad (the
# notepad-app stage, at /atlas-notepad-rpms), Atlas Settings (the
# settings-app stage, at /atlas-settings-rpms) and Atlas Wizard (the
# wizard-app stage, at /atlas-wizard-rpms), the first-run setup that replaces
# plasma-setup (packages.sh removes it); nothing is copied into the
# image. They are required parts of the system: the build fails without them,
# and their protected.d files (atlas-framework.conf from atlas-ui, atlas.conf
# from atlas-system-helper, atlas-monitor.conf, atlas-notepad.conf,
# atlas-settings.conf, atlas-wizard.conf) stop dnf
# removing them.
"${dnf[@]}" install /atlas-framework-rpms/*.rpm
rpm -q atlas-ui atlas-symbols-fonts atlas-symbols
[ -f /etc/dnf/protected.d/atlas-framework.conf ]
[ -f /usr/lib64/qt6/qml/Atlas/Ui/qmldir ]
"${dnf[@]}" install /atlas-rpms/*.rpm /atlas-monitor-rpms/*.rpm /atlas-notepad-rpms/*.rpm /atlas-settings-rpms/*.rpm /atlas-wizard-rpms/*.rpm
rpm -q atlas-system-helper atlas-updater atlas-monitor atlas-notepad atlas-settings atlas-wizard
# (rpm -q matches package names, not what a package provides.)
if rpm -q --quiet atlas-core; then
	echo "apps.sh: atlas-core is still installed beside atlas-system-helper" >&2
	exit 1
fi
[ -f /etc/dnf/protected.d/atlas.conf ]
[ -f /etc/dnf/protected.d/atlas-monitor.conf ]
[ -f /etc/dnf/protected.d/atlas-notepad.conf ]
[ -f /etc/dnf/protected.d/atlas-settings.conf ]
[ -f /etc/dnf/protected.d/atlas-wizard.conf ]
# The default apps (mimeapps.list), launcher favourites and the menu name
# these.
[ -f /usr/share/applications/net.eterneon.atlas.notepad.desktop ]
[ -f /usr/share/applications/net.eterneon.atlas.monitor.desktop ]
[ -f /usr/share/applications/net.eterneon.atlas.settings.desktop ]
[ -x /usr/bin/atlas-settings ]
# The first-run setup: its session user comes from the RPM's sysusers.d file
# (provides user(atlas-setup)), and its boot unit, which runs before the
# display manager on every boot, is on by the RPM's preset; enabled here too,
# so the image never depends on the scriptlet having run in a container.
rpm -q --provides atlas-wizard | grep -qxF 'user(atlas-setup)'
[ -f /usr/lib/systemd/system/atlas-wizard-boot.service ]
[ -x /usr/libexec/atlas-wizard-boot ]
[ -f /usr/share/wayland-sessions/atlas-wizard.desktop ]
systemctl enable atlas-wizard-boot.service
[ "$(systemctl is-enabled atlas-wizard-boot.service)" = enabled ]
if rpm -q --quiet plasma-setup; then
	echo "apps.sh: plasma-setup is still installed beside atlas-wizard" >&2
	exit 1
fi
# Atlas Monitor takes Plasma System Monitor's shortcuts (Ctrl+Shift+Esc,
# Ctrl+Esc); packages.sh removes that app.
[ -f /usr/share/kglobalaccel/net.eterneon.atlas.monitor.desktop ]
# The updater autostarts in the tray at login (users can turn that off in
# System Settings; the background staging timer doesn't depend on it).
rpm -ql atlas-updater >/tmp/atlas-updater.files
grep -q '/autostart/' /tmp/atlas-updater.files
rm /tmp/atlas-updater.files

/ctx/cleanup.sh
