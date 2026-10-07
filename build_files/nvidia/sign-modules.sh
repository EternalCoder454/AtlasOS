#!/usr/bin/env bash
# Signs the modules build-kmod.sh built with the Telamon OS module key, so they
# load with Secure Boot on once the key is enrolled (see
# system_files_nvidia/usr/libexec/telamon/nvidia-enroll-key). $1 is the
# output directory; /unsigned holds build-kmod.sh's output, /signing.der the
# public certificate, and /signing.key the private key.
# Runs in Containerfile.nvidia's nvidia-kmod stage, the only RUN that mounts
# the key, and that RUN has no network. /unsigned came from the stage that
# ran NVIDIA's build, so it is treated as hostile: only plain files of the
# expected names are read, and sign-file is the one fetch-sign-file.sh got
# from Fedora, not one from /unsigned.
#   kmod-nvidia-*.rpm   copied from /unsigned
#   modules/            the signed modules, laid out as under /usr/lib/modules
#   version             copied from /unsigned
set -euxo pipefail

out=$1
kver=$(cat /kver)
[ -n "$kver" ] && [ "$(wc -l </kver)" -eq 1 ]

[ -s /signing.key ] || {
	echo "sign-modules.sh: no signing key (podman build --secret id=nvidia-signing-key,src=...)" >&2
	exit 1
}
fail() {
	echo "sign-modules.sh: $*" >&2
	exit 1
}

# Nothing in /unsigned but plain files (no links, devices, sockets) in the one
# directory build-kmod.sh makes.
[ -d /unsigned ] && [ ! -L /unsigned ]
[ -d /unsigned/unsigned ] && [ ! -L /unsigned/unsigned ] || fail "/unsigned/unsigned is not a directory"
other=$(find /unsigned -mindepth 1 ! -type f ! -path /unsigned/unsigned)
[ -z "$other" ] || fail "not plain files: $other"

# The driver version, as `rpm -q --qf %{VERSION}` prints it, e.g. 595.58.03.
read -r version </unsigned/version
[[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "unexpected driver version in /unsigned/version"
shopt -s nullglob
rpms=(/unsigned/kmod-nvidia-"$kver"-*.rpm)
[ ${#rpms[@]} -eq 1 ] || fail "expected one kmod-nvidia rpm for $kver"

# Only NVIDIA's open modules, by name.
modules=(/unsigned/unsigned/*)
[ ${#modules[@]} -gt 0 ] || fail "no modules to sign in /unsigned/unsigned"
for xz in "${modules[@]}"; do
	case $(basename "$xz") in
	nvidia.ko.xz | nvidia-modeset.ko.xz | nvidia-drm.ko.xz | nvidia-uvm.ko.xz | nvidia-peermem.ko.xz) ;;
	*) fail "unexpected module: $xz" ;;
	esac
done

mkdir -p "$out/modules/$kver/extra/nvidia"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for xz in "${modules[@]}"; do
	ko=$work/$(basename "$xz" .xz)
	xz -dc "$xz" >"$ko"
	/usr/local/bin/sign-file sha256 /signing.key /signing.der "$ko"
	# The kernel's xz decompressor wants CRC32 checks.
	xz -C crc32 --lzma2=dict=1MiB -c "$ko" >"$out/modules/$kver/extra/nvidia/$(basename "$xz")"
	[ "$(modinfo -F signer "$ko")" = "AtlasOS module signing" ]
	rm "$ko"
done
install -m644 "${rpms[0]}" "$out/"
printf '%s\n' "$version" >"$out/version"
ls -R "$out"
