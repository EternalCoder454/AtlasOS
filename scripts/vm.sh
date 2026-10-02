#!/usr/bin/env bash
# Test VMs in the system libvirt (qemu:///system), so they show in
# virt-manager. Needs membership of the libvirt group, and libvirt's qemu user
# must be able to pass through your home folder to reach build/ (checked below).
#
#   vm.sh run <name> <base disk>   boot <base disk> through a fresh overlay
#   vm.sh stop <name>              stop the VM and delete its overlay
#   vm.sh update <name> [tag] [settle]
#                                  build/vm/updated/<name>.qcow2: build/atlasos.qcow2
#                                  switched to localhost/atlasos:<tag>
#   vm.sh install-stock            install stock Kinoite 44 from the ISO in ~/VMs
#   vm.sh mem [disk]               the `just mem` comparison
#
# Every VM is UEFI (OVMF) with 8 GB of RAM, 4 CPUs, a serial console, and
# virtio video with 3D acceleration, so Plasma runs on the host GPU (virgl) as
# it would on real hardware, shown over SPICE with OpenGL. QEMU can't read
# a SPICE OpenGL display back, so once Plasma draws, scripts/vmctl.py takes
# screenshots inside the guest instead (see session_screenshot there).
set -euo pipefail

cd "$(dirname "$0")/.."
export LIBVIRT_DEFAULT_URI=qemu:///system

iso=${KINOITE_ISO:-$HOME/VMs/Fedora-Kinoite-ostree-x86_64-44-1.7.iso}
iso_label=Fedora-Knt-ostree-x86_64-44
stock_disk=build/vm/kinoite-stock-base.qcow2
memory_mb=8192
vcpus=4
# The GPU that draws the VMs' 3D: the first one, unless RENDERNODE says.
rendernode=${RENDERNODE-}
for n in /dev/dri/renderD*; do
	[ -z "$rendernode" ] && [ -e "$n" ] && rendernode=$n
done

# The commas are virt-install's own option syntax, not array separators.
# shellcheck disable=SC2054
common=(
	--memory "$memory_mb" --vcpus "$vcpus"
	--osinfo fedora-unknown
	--boot uefi
	--network network=default,model=virtio
	--graphics "spice,listen=none,gl.enable=yes,gl.rendernode=$rendernode"
	--video model.type=virtio,model.acceleration.accel3d=yes
	--serial pty --console pty,target_type=serial
	--noautoconsole
)

exists() { virsh dominfo "$1" >/dev/null 2>&1; }

# Only VMs this script made, whose disks are all in build/vm, are ever
# stopped or removed; a VM of the same name made in virt-manager is left alone.
ours() {
	local vmdir disks
	vmdir=$(realpath build/vm 2>/dev/null) || return 1
	# Disks only: the stock install also has the ISO in a CD drive.
	disks=$(virsh domblklist --details "$1" | awk '$2 == "disk" && $4 ~ /^\// { print $4 }')
	[ -n "$disks" ] && ! grep -qv "^$vmdir/" <<<"$disks"
}

valid_name() {
	case $1 in
	'' | *[!a-z0-9-]*)
		echo "VM names are lowercase letters, digits and dashes: '$1'" >&2
		exit 1
		;;
	esac
}

# The VMs draw with the host GPU, and 8 GB on top of a loaded Ollama model is
# how the desktop runs out of memory. Don't start while one is loaded.
no_ollama_model() {
	local loaded
	loaded=$(curl -s --max-time 2 localhost:11434/api/ps || true)
	if grep -q '"name"' <<<"$loaded"; then
		echo "An Ollama model is loaded. Unload it first, then try again." >&2
		exit 1
	fi
}

# The VMs run as the qemu user, which needs search (x) permission on every
# folder above their disks, and read permission on a file it opens (the ISO).
# A home folder is usually closed to it.
reachable() {
	local d
	d=$(realpath "$1")
	if [ -f "$d" ]; then
		case $(stat -c %A "$d") in
		???????r??) ;;
		*)
			getfacl -p "$d" 2>/dev/null | grep -q '^user:qemu:r' || {
				echo "libvirt's qemu user can't read $1:  setfacl -m u:qemu:r $d" >&2
				exit 1
			}
			;;
		esac
		d=$(dirname "$d")
	fi
	while [ "$d" != / ]; do
		case $(stat -c %A "$d") in
		*[xt]) ;;
		*)
			getfacl -p "$d" 2>/dev/null | grep -q '^user:qemu:..x' || {
				echo "libvirt's qemu user can't reach $1 (blocked at $d). Let it pass" >&2
				echo "through, without being able to list it:  setfacl -m u:qemu:x $d" >&2
				exit 1
			}
			;;
		esac
		d=$(dirname "$d")
	done
}

stop() {
	local name=$1
	valid_name "$name"
	if exists "$name"; then
		ours "$name" || {
			echo "$name in qemu:///system wasn't made by these scripts (its disks aren't in build/vm); leaving it alone." >&2
			exit 1
		}
		virsh destroy "$name" >/dev/null 2>&1 || true
		virsh undefine --nvram "$name" >/dev/null
	fi
	rm -f "build/vm/overlays/$name.qcow2"
}

run() {
	local name=$1 base=$2
	[ -f "$base" ] || {
		echo "No $base. For AtlasOS, run 'just build' and 'just qcow2' first." >&2
		exit 1
	}
	# Overlays live apart from the base disks, so removing one can never
	# touch a base disk of the same name.
	no_ollama_model
	[ -n "$rendernode" ] || {
		echo "No GPU render node in /dev/dri; the VMs need one for 3D." >&2
		exit 1
	}
	mkdir -p build/vm/overlays
	reachable build/vm/overlays
	stop "$name"
	qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$base")" "build/vm/overlays/$name.qcow2"
	virt-install --name "$name" --import \
		--disk "path=build/vm/overlays/$name.qcow2,bus=virtio" "${common[@]}"
}

# Brings a disk up to an image in local (rootless) container storage without
# bootc-image-builder, which needs root: a fresh copy-on-write disk over
# build/atlasos.qcow2 boots with the image shared in over virtiofs, `bootc
# switch`es to it and powers off. The result, build/vm/updated/<name>.qcow2,
# boots through overlays like any base disk. Only build/atlasos.qcow2 is used
# as shipped; the new image arrives as an update, as it would for a user.
# "settle" readies it for scripts/vmbench.py (see scripts/vmswitch.py).
update_dir=build/vm/updated
share=build/vm/share
update() {
	local name=$1 tag=$2 settle=$3
	local disk=$update_dir/$name.qcow2
	valid_name "$name"
	[ -f build/atlasos.qcow2 ] || {
		echo "No build/atlasos.qcow2 to start from. Run 'just qcow2' once." >&2
		exit 1
	}
	no_ollama_model
	stop "$name-update"
	mkdir -p "$update_dir"
	rm -rf "$share" "$disk.partial"
	mkdir -p "$share"
	echo ">> Exporting localhost/atlasos:$tag"
	podman save --quiet --format oci-dir -o "$share/image" "localhost/atlasos:$tag"
	chmod -R a+rX "$share"
	reachable "$share/image"
	qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath build/atlasos.qcow2)" "$disk.partial"
	# virtiofs needs the guest's memory shared with virtiofsd.
	virt-install --name "$name-update" --import \
		--disk "path=$disk.partial,bus=virtio" "${common[@]}" \
		--memorybacking source.type=memfd,access.mode=shared \
		--filesystem "source.dir=$(realpath "$share"),target.dir=atlasos-image,driver.type=virtiofs" >/dev/null
	echo ">> Switching $disk to the new image (several minutes)"
	local ok=0
	uv run --quiet scripts/vmswitch.py "$name-update" "$update_dir/$name-update.log" \
		build/vm-password ${settle:+--settle} || ok=1
	for _ in $(seq 60); do
		[ "$(virsh domstate "$name-update" 2>/dev/null)" = "shut off" ] && break
		sleep 2
	done
	virsh destroy "$name-update" >/dev/null 2>&1 || true
	virsh undefine --nvram "$name-update" >/dev/null
	rm -rf "$share"
	[ "$ok" -eq 0 ] || exit 1
	mv "$disk.partial" "$disk"
	echo ">> $disk runs localhost/atlasos:$tag"
}

install_stock() {
	[ -f "$stock_disk" ] && return
	[ -f "$iso" ] || {
		echo "No Kinoite ISO at $iso (set KINOITE_ISO to use another)." >&2
		exit 1
	}
	mkdir -p build/vm
	reachable build/vm
	reachable "$iso"
	password_file
	local hash
	hash=$(openssl passwd -6 -stdin <build/vm-password)
	sed "s|@PASSWORD_HASH@|$hash|" disk_config/kinoite-stock.ks >build/vm/kinoite-stock.ks

	echo ">> Installing stock Kinoite 44 from $iso (about 10 minutes)"
	stop kinoite-stock-install
	rm -f "$stock_disk.partial"
	# Made here, not by virt-install, so it stays ours: libvirt gives a disk
	# back to its owner after each run, and one it made itself belongs to root's
	# qemu user, which leaves the next overlay unable to read it.
	qemu-img create -q -f qcow2 "$stock_disk.partial" 30G
	# The kickstart powers the VM off when it is done, which ends the wait. A
	# failed install stops at an error instead, so give up after 40 minutes.
	virt-install --name kinoite-stock-install \
		--location "$iso,kernel=images/pxeboot/vmlinuz,initrd=images/pxeboot/initrd.img" \
		--initrd-inject build/vm/kinoite-stock.ks \
		--extra-args "inst.ks=file:/kinoite-stock.ks inst.stage2=hd:LABEL=$iso_label inst.text console=ttyS0,115200" \
		--disk "path=$stock_disk.partial,format=qcow2,bus=virtio" \
		"${common[@]}" --noreboot --wait 40 || true
	# Only a VM that powered itself off finished the kickstart.
	if [ "$(virsh domstate kinoite-stock-install 2>/dev/null)" != "shut off" ]; then
		echo "The stock install did not finish; see the VM's console. Removing it." >&2
		stop kinoite-stock-install
		rm -f "$stock_disk.partial"
		exit 1
	fi
	virsh undefine --nvram kinoite-stock-install >/dev/null
	mv "$stock_disk.partial" "$stock_disk"
}

password_file() {
	[ -s build/vm-password ] ||
		(umask 077 && openssl rand -hex 12 >build/vm-password)
}

# On Ctrl-C or a failure, don't leave an 8 GB VM running.
stop_all() {
	local vm
	for vm in kinoite-stock-install kinoite-stock atlasos; do
		(stop "$vm") || true
	done
}

mem() {
	local atlas=$1
	trap stop_all EXIT
	trap 'exit 130' INT TERM
	no_ollama_model
	[ -f "$atlas" ] || {
		echo "No $atlas. Run 'just build' and 'just qcow2' first." >&2
		exit 1
	}
	install_stock

	local stamp
	stamp=$(date +%Y%m%d-%H%M%S)
	# One at a time, so the two never compete for the host's memory.
	for vm in kinoite-stock:"$stock_disk" atlasos:"$atlas"; do
		local name=${vm%%:*} disk=${vm#*:}
		echo ">> $name"
		run "$name" "$disk"
		uv run --quiet scripts/vmctl.py "$name" "build/mem/$stamp/$name" build/vm-password ||
			echo "!! $name: measurement failed, see build/mem/$stamp/$name/console.log" >&2
		stop "$name"
	done

	echo
	echo "== Summary (MiB, 'used' and 'available' from free -m) =="
	for name in kinoite-stock atlasos; do
		local f=build/mem/$stamp/$name/report.txt
		[ -f "$f" ] || continue
		awk -v n="$name" '/^### free -m/{f=1;next} f&&/^Mem:/{printf "%-14s used %5d  available %5d  ", n, $3, $7}
			/^### running system services/{s=1;next} s&&/^###/{s=0} s&&/\.service/{c++}
			END{printf "running system services %d\n", c}' "$f"
	done
	echo "Full reports and screenshots: build/mem/$stamp/"
}

case ${1-} in
run) run "$2" "$3" ;;
stop) stop "$2" ;;
update)
	valid_name "${2-}"
	trap '(stop "$2-update") || true; rm -rf "$share" "$update_dir/$2.qcow2.partial"' EXIT
	trap 'exit 130' INT TERM
	update "$2" "${3:-latest}" "$([ "${4-}" = settle ] && echo 1)"
	;;
install-stock)
	trap stop_all EXIT
	trap 'exit 130' INT TERM
	install_stock
	;;
mem) mem "${2:-build/atlasos.qcow2}" ;;
*)
	sed -n '2,13p' "$0"
	exit 2
	;;
esac
