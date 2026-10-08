#!/usr/bin/env bash
# Rebuilds Fedora's plasma-login-manager, the exact version in the base image,
# with Telamon OS's login-screen placeholder, and puts the RPMs in $1.
# Runs in the Containerfile's login stage; /login-nvr holds the base image's
# plasma-login-manager version-release.
#
# The change (login-pin-placeholder.patch): the sign-in PIN is typed in the
# login screen's password field (DEV.md, "PIN sign-in"), but the field's
# placeholder is a fixed "Password" in the greeter's compiled QML, which no
# PAM module can change. With the authselect feature with-pin
# (/etc/authselect/authselect.conf) it now says "Password or PIN". Only the
# placeholder: nothing in authentication changes. The greeter is a
# pre-authentication process, so QML gets no file access: main() makes one
# bounded read of that file and hands QML a single boolean (TelamonSignIn).
#
# Remove this stage when Fedora's plasma-login-manager has a placeholder that
# can be set (or says "PIN" itself): the build fails here when the patch no
# longer applies.
set -euxo pipefail

out=$1
nvr=$(cat /login-nvr)
ver=${nvr%-*}
rel=${nvr##*-}

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)
"${dnf[@]}" install rpm-build 'dnf5-command(builddep)'

# Koji keeps every build, so this works even after Fedora's repos move on.
# data/signed/6d9f90a6 holds the copies signed with Fedora 44's release key
# (the files under the build itself are unsigned).
curl -fsSL --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 -o /tmp/login.src.rpm \
	"https://kojipkgs.fedoraproject.org/packages/plasma-login-manager/$ver/$rel/data/signed/6d9f90a6/src/plasma-login-manager-$nvr.src.rpm"
# Refuse an SRPM that isn't signed with Fedora's release key, which this
# image carries.
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary
rpmkeys --checksig /tmp/login.src.rpm | grep -q ': digests signatures OK$' || {
	echo "login/build-rpm.sh: the source RPM is not signed by Fedora's key" >&2
	rpmkeys --checksig -v /tmp/login.src.rpm >&2
	exit 1
}
rpm -i /tmp/login.src.rpm
top=$(rpm -E %_topdir)
spec=$top/SPECS/plasma-login-manager.spec
cp /login/*.patch "$top/SOURCES/"

# Fedora's %autosetup -p1 applies every PatchN. The release gets ".atlas1",
# so the image shows which build it has and dnf sees it as newer.
grep -q '^%autosetup .*-p1' "$spec"
grep -qE '^Release:\s*[0-9]+%\{\?dist\}$' "$spec"
sed -i -E 's/^(Release:\s*[0-9]+%\{\?dist\})$/\1.atlas1/' "$spec"
grep -q '^Provides:       service(graphical-login) = plasmalogin$' "$spec"
sed -i '0,/^Provides:       service(graphical-login) = plasmalogin$/s//Patch9001: login-pin-placeholder.patch\n\n&/' "$spec"
grep -q '^Patch9001:' "$spec"

"${dnf[@]}" builddep "$spec"
rpmbuild -bb --nocheck "$spec"

mkdir -p "$out"
find "$top/RPMS" -name '*.rpm' ! -name '*-debug*' -exec cp {} "$out/" \;
ls "$out"
