#!/usr/bin/env bash
# Rebuilds Fedora's kf6-kio, the exact version in the base image, with
# Telamon OS's fix for a crash KDE hasn't fixed yet, and puts the RPMs in $1.
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

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)
"${dnf[@]}" install rpm-build 'dnf5-command(builddep)'

# Koji keeps every build, so this works even after Fedora's repos move on.
# data/signed/6d9f90a6 holds the copies signed with Fedora 44's release key
# (the files under the build itself are unsigned).
curl -fsSL --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 -o /tmp/kio.src.rpm \
	"https://kojipkgs.fedoraproject.org/packages/kf6-kio/$ver/$rel/data/signed/6d9f90a6/src/kf6-kio-$nvr.src.rpm"
# Koji's packages are signed with Fedora's release key, which this image
# carries: refuse an SRPM that isn't.
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary
rpmkeys --checksig /tmp/kio.src.rpm | grep -q ': digests signatures OK$' || {
	echo "kio/build-rpm.sh: the source RPM is not signed by Fedora's key" >&2
	rpmkeys --checksig -v /tmp/kio.src.rpm >&2
	exit 1
}
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

# Without the API docs (the qch-doc and html packages, which the image
# doesn't have): Fedora's KF6 build macros generate them with qdoc after the
# build, minutes on a small runner. The packages go from the spec with every
# doc file listed (-devel, not in the image either, has their indexes), and
# the build and install macros lose their doc targets.
awk '
	/^%(package|files|description)[[:space:]]+(qch-doc|html)$/ { skip = 1; next }
	/^%(package|description|files|prep|changelog)([[:space:]]|$)/ { skip = 0 }
	/%\{_qt6_docdir\}/ { next }
	!skip
' "$spec" >"$spec.new"
mv "$spec.new" "$spec"
if grep -qE '^%(package|files)[[:space:]]+(qch-doc|html)$|%\{_qt6_docdir\}' "$spec"; then
	echo "kio/build-rpm.sh: the API doc packages are still in the spec" >&2
	exit 1
fi
"${dnf[@]}" builddep "$spec"
rpmbuild -bb --nocheck \
	--define 'cmake_build_kf6 %cmake_build' \
	--define 'cmake_install_kf6 %cmake_install' \
	"$spec"

mkdir -p "$out"
find "$top/RPMS" -name 'kf6-kio-*.rpm' ! -name '*-debug*' ! -name '*-devel-*' -exec cp {} "$out/" \;
ls "$out"
