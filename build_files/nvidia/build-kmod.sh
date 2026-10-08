#!/usr/bin/env bash
# Builds NVIDIA's open kernel modules (RPM Fusion's akmod-nvidia) for the
# kernel in /kver and puts in $1:
#   kmod-nvidia-*.rpm   the package, for its dependencies and file list
#   unsigned/           the built modules (*.ko.xz), not yet signed
#   version             the driver version, so the image gets the same one
# Runs in Containerfile.nvidia's nvidia-kmod-build stage, which never sees the
# module signing key: this stage compiles NVIDIA's source, and sign-modules.sh
# (a later stage) is the only place the key is mounted. The repo is the RPM
# Fusion NVIDIA repo Fedora ships disabled, copied from the Telamon OS image.
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
koji=https://kojipkgs.fedoraproject.org/packages/kernel/$version/$release/data/signed/6d9f90a6/$arch
# Fetched here and installed only if Fedora's release key (the one this image
# carries) signed them: koji is not trusted by itself.
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary
devel=$(mktemp -d)
for pkg in kernel-devel kernel-devel-matched; do
	curl -fsSL --retry 3 --retry-all-errors --proto '=https' --tlsv1.2 \
		-o "$devel/$pkg.rpm" "$koji/$pkg-$kernel_ver.$arch.rpm"
	rpmkeys --checksig "$devel/$pkg.rpm" | grep -q ': digests signatures OK$' || {
		echo "build-kmod.sh: $pkg is not signed by Fedora's key" >&2
		rpmkeys --checksig -v "$devel/$pkg.rpm" >&2
		exit 1
	}
done
# --refresh: kernel-devel-matched needs the base image's kernel-core from the
# repositories, and the cached metadata (build.yml caches it for a week) can be
# older than a kernel that just reached updates.
"${dnf[@]}" --refresh install "$devel/kernel-devel.rpm" "$devel/kernel-devel-matched.rpm"
rm -rf "$devel"
"${dnf[@]}" --enablerepo=rpmfusion-nonfree-nvidia-driver install akmod-nvidia

# akmods builds the kmod RPM as its own user, the way it would on a running
# system, and installs it here.
akmods --force --kernels "$kver" --kmod nvidia
mkdir -p "$out"
cp /var/cache/akmods/nvidia/kmod-nvidia-"$kver"-*.rpm "$out/"
rpm -q --qf '%{VERSION}\n' akmod-nvidia >"$out/version"

# Open modules only (MIT/GPL); the proprietary ones would mean older GPUs
# and a different support story.
dir=/usr/lib/modules/$kver/extra/nvidia
[ "$(modinfo -F license "$dir/nvidia.ko.xz")" = "Dual MIT/GPL" ]

# Hand over the modules unsigned. The key is only ever mounted in
# sign-modules.sh's stage, which treats everything from here as hostile and
# brings its own sign-file (fetch-sign-file.sh).
mkdir -p "$out/unsigned"
cp "$dir"/*.ko.xz "$out/unsigned/"
ls -R "$out"
