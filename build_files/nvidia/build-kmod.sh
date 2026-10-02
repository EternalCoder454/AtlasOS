#!/usr/bin/env bash
# Builds NVIDIA's open kernel modules (RPM Fusion's akmod-nvidia) for the
# kernel in /kver, signs them with the AtlasOS module key, and puts in $1:
#   kmod-nvidia-*.rpm   the package, for its dependencies and file list
#   modules/            the signed modules, laid out as under /usr/lib/modules
#   version             the driver version, so the image gets the same one
# Runs in Containerfile.nvidia's nvidia-kmod stage. The repo is the RPM Fusion
# NVIDIA repo Fedora ships disabled, copied from the AtlasOS image.
set -euxo pipefail

out=$1
kver=$(cat /kver)
[ -n "$kver" ] && [ "$(wc -l </kver)" -eq 1 ]
kernel_ver=${kver%.*}       # 7.2.8-200.fc44
version=${kernel_ver%-*}    # 7.2.8
release=${kernel_ver##*-}   # 200.fc44
arch=${kver##*.}            # x86_64

dnf=(dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False)
# The repo checks packages with the key in distribution-gpg-keys.
"${dnf[@]}" install distribution-gpg-keys
# Headers for exactly the image's kernel. Koji keeps every build, so this
# works even after Fedora's repos have moved on to a newer kernel.
koji=https://kojipkgs.fedoraproject.org/packages/kernel/$version/$release/$arch
"${dnf[@]}" install "$koji/kernel-devel-$kernel_ver.$arch.rpm" \
	"$koji/kernel-devel-matched-$kernel_ver.$arch.rpm"
"${dnf[@]}" --enablerepo=rpmfusion-nonfree-nvidia-driver install akmod-nvidia

# akmods builds the kmod RPM as its own user, the way it would on a running
# system, and installs it here.
akmods --force --kernels "$kver" --kmod nvidia
mkdir -p "$out/modules"
cp /var/cache/akmods/nvidia/kmod-nvidia-"$kver"-*.rpm "$out/"
rpm -q --qf '%{VERSION}\n' akmod-nvidia >"$out/version"

# Open modules only (MIT/GPL); the proprietary ones would mean older GPUs
# and a different support story.
dir=/usr/lib/modules/$kver/extra/nvidia
[ "$(modinfo -F license "$dir/nvidia.ko.xz")" = "Dual MIT/GPL" ]

# Sign every module, so they load with Secure Boot on once the AtlasOS key
# is enrolled (see system_files_nvidia/usr/libexec/atlasos/nvidia-enroll-key).
[ -s /signing.key ] || {
	echo "build-kmod.sh: no signing key (podman build --secret id=nvidia-signing-key,src=...)" >&2
	exit 1
}
sign=/usr/src/kernels/$kver/scripts/sign-file
mkdir -p "$out/modules/$kver/extra/nvidia"
for xz in "$dir"/*.ko.xz; do
	ko=/tmp/$(basename "$xz" .xz)
	xz -dc "$xz" >"$ko"
	"$sign" sha256 /signing.key /signing.der "$ko"
	# The kernel's xz decompressor wants CRC32 checks.
	xz -C crc32 --lzma2=dict=1MiB -c "$ko" >"$out/modules/$kver/extra/nvidia/$(basename "$xz")"
	[ "$(modinfo -F signer "$ko")" = "AtlasOS module signing" ]
	rm "$ko"
done
ls -R "$out"
