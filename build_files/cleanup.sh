#!/usr/bin/env bash
# The end of each build step (packages.sh, apps.sh, build.sh): what a step
# leaves behind is cleared in that step, so no layer stores it (only for a
# later step to delete again) and the cached steps stay small.
set -euxo pipefail

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
