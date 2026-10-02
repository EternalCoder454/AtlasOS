#!/usr/bin/env bash
# Adds NVIDIA's driver to the AtlasOS image. Runs in Containerfile.nvidia's
# last stage, with the signed modules from the nvidia-kmod stage at /kmod.
set -euxo pipefail

dnf=(dnf5 -y --setopt=install_weak_deps=False)
kver=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n')
version=$(cat /kmod/version)

# The driver from RPM Fusion's NVIDIA repo (Fedora ships it, disabled), at
# the version the modules were built from:
# - the kmod package built in the nvidia-kmod stage (no akmods here: the
#   image is read-only and has no compilers)
# - OpenGL/Vulkan/EGL libraries, nvidia-smi and CUDA's driver libraries
#   (for GPU compute in toolbox and Podman containers)
# - suspend and resume support (nvidia-suspend/-resume/-hibernate)
# - VA-API video decoding, so Brave decodes video on the GPU
"${dnf[@]}" --enablerepo=rpmfusion-nonfree-nvidia-driver install \
	/kmod/kmod-nvidia-"$kver"-*.rpm \
	"xorg-x11-drv-nvidia-$version" \
	"xorg-x11-drv-nvidia-cuda-$version" \
	"xorg-x11-drv-nvidia-power-$version" \
	libva-nvidia-driver
rpm -q akmod-nvidia >/dev/null 2>&1 && {
	echo "nvidia/build.sh: akmod-nvidia must not be in the image" >&2
	exit 1
}

# The packaged modules are unsigned; put the signed ones in their place.
cp -a /kmod/modules/"$kver"/extra/nvidia/. "/usr/lib/modules/$kver/extra/nvidia/"
depmod -a "$kver"
for m in /usr/lib/modules/"$kver"/extra/nvidia/*.ko.xz; do
	[ "$(modinfo -F signer "$m")" = "AtlasOS module signing" ]
done

# NVIDIA's container toolkit, so `podman run --device nvidia.com/gpu=all`
# works: from NVIDIA's signed repo, removed again afterwards like the other
# outside repos. It writes the device list (CDI) itself when the driver loads.
curl -fsSL --retry 3 -o /etc/yum.repos.d/nvidia-container-toolkit.repo \
	https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
"${dnf[@]}" install nvidia-container-toolkit
rm /etc/yum.repos.d/nvidia-container-toolkit.repo
[ -f /usr/lib/systemd/system/nvidia-cdi-refresh.path ]
systemctl enable nvidia-cdi-refresh.path

# Modes come from the checkout. Everything here is meant to be readable by
# all (enrolling the key reads the certificate as the user), so a file a
# local checkout made private fails the build instead of shipping that way.
unreadable=$(find /ctx/system_files_nvidia ! -type l ! -perm -o=r)
[ -z "$unreadable" ] || {
	echo "build.sh: not readable by everyone: $unreadable" >&2
	exit 1
}
cp -a /ctx/system_files_nvidia/. /

# nouveau stays out of the way (also in the initramfs), and suspend keeps
# video memory (the power package's services, which systemd presets leave off
# in an image build).
grep -q nouveau /usr/lib/bootc/kargs.d/10-atlasos-nvidia.toml
systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

# What the image is, for `cat /etc/os-release` and bug reports.
sed -i -e 's/^VARIANT=.*/VARIANT="Desktop (NVIDIA)"/' \
	-e 's/^VARIANT_ID=.*/VARIANT_ID=desktop-nvidia/' \
	-e 's/^IMAGE_ID=.*/IMAGE_ID=atlasos-nvidia/' /usr/lib/os-release
grep -qx 'IMAGE_ID=atlasos-nvidia' /usr/lib/os-release

for f in /usr/libexec/atlasos/nvidia-*; do [ -x "$f" ] && bash -n "$f"; done

# As in build.sh: the dnf cache is left alone when it is the host's.
rm -rf /var/lib/dnf /var/log/dnf5.log* /run/dnf /var/cache/ldconfig/aux-cache /var/cache/akmods
mountpoint -q /var/cache/libdnf5 || rm -rf /var/cache/libdnf5
