#!/usr/bin/env bash
# The end of each build step (packages.sh, apps.sh, build.sh, version.sh and
# nvidia/build.sh): what a step leaves behind is cleared in that step, so no
# layer stores it (only for a later step to delete again) and the cached steps
# stay small.
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
	/var/lib/power-profiles-daemon \
	/var/lib/authselect/backups /run/selinux-policy
# (power-profiles-daemon's: systemd makes it, StateDirectory=. authselect
# backs up the files it replaces, and semodule leaves its work in /run.)
mountpoint -q /var/cache/libdnf5 || rm -rf /var/cache/libdnf5

# The library cache, made again from what the image now holds: a library put
# down without dnf (whose trigger runs ldconfig) would otherwise be missing
# from it, and an update's first boot only rebuilds it when /etc's copy
# differs from the image's (ldconfig-needed). Its aux-cache (inode numbers and
# times, new every build) stays out, as above.
ldconfig
rm -f /var/cache/ldconfig/aux-cache

# Times. An installed system shows every file with time 0 (OSTree keeps no
# times), so here they only decide which layers an update downloads: chunkah's
# layers carry each file's and directory's time, and anything a build writes
# made its layer new in every build even when its contents were the same (the
# 228 MB initramfs, and each directory a package added a file to). So every
# directory, and every file this step put down or changed, gets time 0. That
# is by change time, so files copied with their times kept (cp -a of
# system_files, whose times are the checkout's) count too.
# (/tmp/atlasos-step-start: the step's first command.)
[ -f /tmp/atlasos-step-start ]
find /usr /etc -xdev \( -type d -o -cnewer /tmp/atlasos-step-start \) \
	-newermt @0 -exec touch -h -d @0 {} +
# fontconfig's caches hold their directories' times: made again from the
# times above, they come out the same in every build.
fc-cache -s -f
find /usr/lib/fontconfig/cache -newermt @0 -exec touch -h -d @0 {} +
