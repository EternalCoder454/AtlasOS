#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 2 of 4: the Atlas apps, after
# packages.sh, in a step of their own because they change more often than the
# rest of the packages. Then build.sh.
set -euxo pipefail

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Atlas apps

# atlas-framework first: Atlas.Ui (atlas-ui), the QML module every Atlas app
# imports, its Material Symbols fonts (atlas-symbols-fonts) and the Atlas
# Symbols gallery (atlas-symbols), built by the framework stage of the
# Containerfile (bound in at /atlas-framework-rpms). The apps are built
# against this Atlas.Ui and require it. Then Atlas Updater and atlas-core,
# built by the atlas-apps stage (at /atlas-rpms), and Atlas Monitor, built by
# the monitor-app stage (at /atlas-monitor-rpms); nothing is copied into the
# image. They are required parts of the system: the build fails without them,
# and their protected.d files (atlas-framework.conf from atlas-ui, atlas.conf
# from atlas-core, atlas-monitor.conf) stop dnf removing them.
"${dnf[@]}" install /atlas-framework-rpms/*.rpm
rpm -q atlas-ui atlas-symbols-fonts atlas-symbols
[ -f /etc/dnf/protected.d/atlas-framework.conf ]
[ -f /usr/lib64/qt6/qml/Atlas/Ui/qmldir ]
"${dnf[@]}" install /atlas-rpms/*.rpm /atlas-monitor-rpms/*.rpm
rpm -q atlas-core atlas-updater atlas-monitor
[ -f /etc/dnf/protected.d/atlas.conf ]
[ -f /etc/dnf/protected.d/atlas-monitor.conf ]
# Atlas Monitor takes Plasma System Monitor's shortcuts (Ctrl+Shift+Esc,
# Ctrl+Esc); packages.sh removes that app.
[ -f /usr/share/kglobalaccel/net.eterneon.atlas.monitor.desktop ]
# The updater autostarts in the tray at login (users can turn that off in
# System Settings; the background staging timer doesn't depend on it).
rpm -ql atlas-updater >/tmp/atlas-updater.files
grep -q '/autostart/' /tmp/atlas-updater.files
rm /tmp/atlas-updater.files

/ctx/cleanup.sh
