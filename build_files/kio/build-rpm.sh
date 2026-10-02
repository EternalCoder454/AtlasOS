#!/usr/bin/env bash
# Rebuilds Fedora's kf6-kio, the exact version in the base image, with
# AtlasOS's fix for a crash KDE hasn't fixed yet, and puts the RPMs in $1.
# Runs in the Containerfile's kio stage; /kio-nvr holds the base image's
# kf6-kio-core version-release.
#
# The fix: KIO's SIGTERM handler writes to the worker object after it is
# destroyed. Dolphin sends SIGTERM to its thumbnail workers as it closes, so
# closing Dolphin crashed several workers each time (use after free; one
# coredump each). https://bugs.kde.org/show_bug.cgi?id=518400
#
# Remove this stage once Fedora's kf6-kio has the fix: the build fails here
# when the patch no longer applies.
set -euxo pipefail

out=$1
nvr=$(cat /kio-nvr)
ver=${nvr%-*}
rel=${nvr##*-}

# tsflags= undoes the container image's nodocs: building the API docs (part
# of Fedora's build) reads Qt's doc templates from /usr/share/doc.
dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False --setopt=tsflags=)
"${dnf[@]}" install rpm-build 'dnf5-command(builddep)'

# Koji keeps every build, so this works even after Fedora's repos move on.
curl -fsSL --retry 3 -o /tmp/kio.src.rpm \
	"https://kojipkgs.fedoraproject.org/packages/kf6-kio/$ver/$rel/src/kf6-kio-$nvr.src.rpm"
rpm -i /tmp/kio.src.rpm
top=$(rpm -E %_topdir)
spec=$top/SPECS/kf6-kio.spec
cp /kio/*.patch "$top/SOURCES/"

# Fedora's %autosetup -p1 applies every PatchN. The release gets ".atlas1",
# so the image shows which KIO it has and dnf sees it as newer.
grep -q '^%autosetup .*-p1' "$spec"
grep -qE '^Release:\s*[0-9]+%\{\?dist\}$' "$spec"
sed -i -E 's/^(Release:\s*[0-9]+%\{\?dist\})$/\1.atlas1/' "$spec"
sed -i '0,/^%description/s//Patch9001: kio-clear-worker-on-destroy.patch\n\n%description/' "$spec"
grep -q '^Patch9001:' "$spec"

"${dnf[@]}" builddep "$spec"
rpmbuild -bb --nocheck "$spec"

mkdir -p "$out"
find "$top/RPMS" -name 'kf6-kio-*.rpm' ! -name '*-debug*' ! -name '*-devel-*' -exec cp {} "$out/" \;
ls "$out"
