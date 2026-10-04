#!/usr/bin/env bash
# Puts the kernel's sign-file tool at /usr/local/bin/sign-file, taken from
# Fedora's signed kernel-devel for the kernel in /kver, not from the stage
# that compiled NVIDIA's code. Runs in Containerfile.nvidia's nvidia-kmod
# stage, before the signing key is mounted (that step has no network).
set -euxo pipefail

kver=$(cat /kver)
[ -n "$kver" ] && [ "$(wc -l </kver)" -eq 1 ]
kernel_ver=${kver%.*}       # 7.2.8-200.fc44
version=${kernel_ver%-*}    # 7.2.8
release=${kernel_ver##*-}   # 200.fc44
arch=${kver##*.}            # x86_64

# The copies koji signed with Fedora 44's release key (see build-kmod.sh).
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 -o "$tmp/kernel-devel.rpm" \
	"https://kojipkgs.fedoraproject.org/packages/kernel/$version/$release/data/signed/6d9f90a6/$arch/kernel-devel-$kernel_ver.$arch.rpm"
rpmkeys --checksig "$tmp/kernel-devel.rpm" | grep -q ': digests signatures OK$' || {
	echo "fetch-sign-file.sh: kernel-devel is not signed by Fedora's key" >&2
	rpmkeys --checksig -v "$tmp/kernel-devel.rpm" >&2
	exit 1
}
(cd "$tmp" && rpm2cpio kernel-devel.rpm | cpio -idm --no-absolute-filenames "./usr/src/kernels/$kver/scripts/sign-file")
[ -f "$tmp/usr/src/kernels/$kver/scripts/sign-file" ] && [ ! -L "$tmp/usr/src/kernels/$kver/scripts/sign-file" ]
install -m755 "$tmp/usr/src/kernels/$kver/scripts/sign-file" /usr/local/bin/sign-file
