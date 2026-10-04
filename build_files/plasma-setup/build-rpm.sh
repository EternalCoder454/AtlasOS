#!/usr/bin/env bash
# Rebuilds Fedora's plasma-setup (the first-run wizard), the exact version in
# the base image, with AtlasOS's look and puts the RPM in $1. Runs in the
# Containerfile's plasma-setup stage; /plasma-setup-nvr holds the base
# image's plasma-setup version-release.
#
# The wizard's frame (welcome screen, card, buttons) is compiled into the
# program, so restyling it means rebuilding. plasma-setup-atlasos-style.patch
# also fixes the Dark choice: Fedora's own patch applies Fedora's Global
# Themes, which AtlasOS removes, so choosing Dark did nothing.
#
# On a new plasma-setup version the build fails here if the patch no longer
# applies; refresh it against the new source with Fedora's patches applied.
set -euxo pipefail

out=$1
nvr=$(cat /plasma-setup-nvr)
ver=${nvr%-*}
rel=${nvr##*-}

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)
"${dnf[@]}" install rpm-build 'dnf5-command(builddep)'

# Koji keeps every build, so this works even after Fedora's repos move on.
# data/signed/6d9f90a6 holds the copies signed with Fedora 44's release key
# (the files under the build itself are unsigned).
curl -fsSL --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 -o /tmp/plasma-setup.src.rpm \
	"https://kojipkgs.fedoraproject.org/packages/plasma-setup/$ver/$rel/data/signed/6d9f90a6/src/plasma-setup-$nvr.src.rpm"
# Koji's packages are signed with Fedora's release key, which this image
# carries: refuse an SRPM that isn't.
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary
rpmkeys --checksig /tmp/plasma-setup.src.rpm | grep -q ': digests signatures OK$' || {
	echo "plasma-setup/build-rpm.sh: the source RPM is not signed by Fedora's key" >&2
	rpmkeys --checksig -v /tmp/plasma-setup.src.rpm >&2
	exit 1
}
rpm -i /tmp/plasma-setup.src.rpm
top=$(rpm -E %_topdir)
spec=$top/SPECS/plasma-setup.spec
cp /plasma-setup/*.patch "$top/SOURCES/"

# Fedora's %autosetup -p1 applies every PatchN in order, so ours (9001) goes
# on top of Fedora's. The release gets ".atlas1", so the image shows which
# plasma-setup it has and dnf sees it as newer.
grep -q '^%autosetup .*-p1' "$spec"
grep -qE '^Release:\s*[0-9]+%\{\?dist\}$' "$spec"
sed -i -E 's/^(Release:\s*[0-9]+%\{\?dist\})$/\1.atlas1/' "$spec"
sed -i '0,/^%description/s//Patch9001: plasma-setup-atlasos-style.patch\n\n%description/' "$spec"
grep -q '^Patch9001:' "$spec"

"${dnf[@]}" builddep "$spec"
rpmbuild -bb "$spec"

mkdir -p "$out"
find "$top/RPMS" -name 'plasma-setup-*.rpm' ! -name '*-debug*' -exec cp {} "$out/" \;
ls "$out"
