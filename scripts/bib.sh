#!/usr/bin/env bash
# Turns the locally built image into a VM disk or installer ISO with
# bootc-image-builder, which needs root: sudo asks for your password once.
#
#   scripts/bib.sh qcow2|iso <image>
#
# Output: build/atlasos.qcow2 or build/atlasos.iso, owned by you.
set -euo pipefail

type=$1
image=$2
bib_image=quay.io/centos-bootc/bootc-image-builder:latest

cd "$(dirname "$0")/.."
mkdir -p build/bib
extra_mounts=()

podman image exists "$image" || {
	echo "No local image $image. Run 'just build' first." >&2
	exit 1
}

case $type in
qcow2)
	# The VM's test user, "atlas". Its password is made once and kept in
	# build/vm-password, so it never reaches git; `just mem` logs in with it.
	[ -s build/vm-password ] ||
		(umask 077 && openssl rand -hex 12 >build/vm-password)
	hash=$(openssl passwd -6 -stdin <build/vm-password)
	{
		cat disk_config/disk.toml
		printf '\n[[customizations.user]]\nname = "atlas"\npassword = "%s"\ngroups = ["wheel"]\n' "$hash"
	} >build/bib/config.toml
	output=qcow2/disk.qcow2
	;;
iso)
	cp disk_config/iso.toml build/bib/config.toml
	output=bootiso/install.iso
	# The installer's package list is looked up by os-release ID-VERSION_ID,
	# and bootc-image-builder has none for "telamonos" (it ignores ID_LIKE).
	# Lend it the newest Fedora list it ships, under Telamon OS's name.
	version=$(podman run --rm --entrypoint cat "$image" /usr/lib/os-release |
		sed -n 's/^VERSION_ID=//p')
	podman pull -q "$bib_image" >/dev/null
	podman run --rm --entrypoint sh "$bib_image" -c \
		'cat "$(ls /usr/share/bootc-image-builder/defs/fedora-*.yaml | sort -V | tail -1)"' \
		>build/bib/def.yaml
	extra_mounts=(-v "$PWD/build/bib/def.yaml:/usr/share/bootc-image-builder/defs/telamonos-$version.yaml:ro")
	;;
*)
	echo "usage: $0 qcow2|iso <image>" >&2
	exit 2
	;;
esac

echo ">> bootc-image-builder runs as root; sudo may ask for your password."

# Root has its own image store. Copy the image over unless root already has
# this exact build.
user_id=$(podman image inspect --format '{{.Id}}' "$image")
root_id=$(sudo podman image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
if [ "$user_id" != "$root_id" ]; then
	echo ">> Copying $image into root's image store"
	# docker-archive keeps the image's name, which oci-archive can lose.
	podman save --format docker-archive "$image" | sudo podman load
fi

sudo rm -rf build/bib/out
mkdir -p build/bib/out
sudo podman run --rm --privileged --pull=newer \
	--security-opt label=type:unconfined_t \
	-v "$PWD/build/bib/config.toml:/config.toml:ro" \
	-v "$PWD/build/bib/out:/output" \
	-v /var/lib/containers/storage:/var/lib/containers/storage \
	"${extra_mounts[@]}" \
	"$bib_image" \
	--type "$type" --rootfs btrfs --use-librepo=True \
	"$image"

sudo chown -R "$(id -u):$(id -g)" build/bib/out
mv -f "build/bib/out/$output" "build/atlasos.$type"
rm -rf build/bib/out
echo ">> Wrote build/atlasos.$type"
