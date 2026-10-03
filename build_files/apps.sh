#!/usr/bin/env bash
# Turns stock Fedora Kinoite into AtlasOS, part 2 of 4: the Atlas apps, after
# packages.sh, in a step of their own because they change more often than the
# rest of the packages. Then build.sh.
set -euxo pipefail

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)

### Atlas apps

# Atlas Updater and atlas-core, built by the atlas-apps stage of the
# Containerfile (bound in at /atlas-rpms; nothing is copied into the image).
# They are required parts of the system: the build fails without them, and
# atlas-core ships /etc/dnf/protected.d/atlas.conf so dnf won't remove them.
"${dnf[@]}" install /atlas-rpms/*.rpm
rpm -q atlas-core atlas-updater
[ -f /etc/dnf/protected.d/atlas.conf ]
# The updater autostarts in the tray at login (users can turn that off in
# System Settings; the background staging timer doesn't depend on it).
rpm -ql atlas-updater >/tmp/atlas-updater.files
grep -q '/autostart/' /tmp/atlas-updater.files
rm /tmp/atlas-updater.files

/ctx/cleanup.sh
