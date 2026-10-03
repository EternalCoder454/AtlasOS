image_name := "atlasos"
image := "localhost/" + image_name

[private]
default:
    @just --list

# Build the image with rootless Podman. Extra arguments go to `podman build`.
[group('Build')]
build tag="latest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # dnf's downloads are kept here between builds (gitignored, never in the
    # image). The VPS runner sets ATLAS_DNF_CACHE to a directory outside the
    # checkout, which actions/checkout cleans.
    dnf_cache="${ATLAS_DNF_CACHE:-$PWD/build/cache/dnf}"
    mkdir -p "$dnf_cache"
    # CI passes IMAGE_VERSION so the image and its pushed tag carry the same date.
    version="${IMAGE_VERSION:-44.$(date -u +%Y%m%d)}"
    # The Atlas apps' source (Atlas Updater and atlas-core): a named build
    # context, so the Containerfile can build their RPMs. CI points it at a
    # checkout of EternalCoder454/atlasos-updater.
    updater="${ATLAS_UPDATER_SRC:-../Atlas Updater}"
    [ -d "$updater/packaging" ] || { echo "Atlas Updater source not found at '$updater' (set ATLAS_UPDATER_SRC)" >&2; exit 1; }
    # Only the files git keeps (tracked, plus new ones it doesn't ignore) go
    # in: a local checkout's target/ is many GB, and podman would copy all of
    # it each build and rebuild the RPMs whenever a cargo build touched it.
    src=build/updater-src
    rm -rf "$src"
    mkdir -p "$src"
    git -C "$updater" ls-files -z --cached --others --exclude-standard |
        rsync -a --from0 --files-from=- --ignore-missing-args "$updater/" "$src/"
    podman build --pull=newer \
        --build-context atlas-updater="$src" \
        --volume "$dnf_cache:/var/cache/libdnf5:Z" \
        --build-arg IMAGE_VERSION="$version" \
        --build-arg PACKAGES_DATE="$(date -u +%F)" \
        --label org.opencontainers.image.version="$version" \
        --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
        --label net.eterneon.atlas.updater.revision="$(git -C "$updater" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label org.opencontainers.image.title=AtlasOS \
        --label org.opencontainers.image.description="Minimal Fedora Kinoite 44 desktop" \
        --label org.opencontainers.image.licenses=Apache-2.0 \
        --label containers.bootc=1 \
        {{ args }} \
        --tag "{{ image }}:{{ tag }}" .

# Build the NVIDIA image (localhost/atlasos-nvidia) on top of a built AtlasOS
# image with the same tag. Needs the module signing key: secrets/nvidia-signing.key
# here, or the file named in NVIDIA_SIGNING_KEY (CI). Extra arguments go to
# `podman build`.
[group('Build')]
build-nvidia tag="latest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    key="${NVIDIA_SIGNING_KEY:-secrets/nvidia-signing.key}"
    [ -s "$key" ] || { echo "No module signing key at $key (see DEV.md, NVIDIA)" >&2; exit 1; }
    dnf_cache="${ATLAS_DNF_CACHE:-$PWD/build/cache/dnf}"
    mkdir -p "$dnf_cache"
    podman build \
        --volume "$dnf_cache:/var/cache/libdnf5:Z" \
        --secret id=nvidia-signing-key,src="$key" \
        --build-arg BASE_IMAGE="{{ image }}:{{ tag }}" \
        --label org.opencontainers.image.title="AtlasOS (NVIDIA)" \
        --label org.opencontainers.image.description="Minimal Fedora Kinoite 44 desktop with NVIDIA's driver" \
        {{ args }} \
        --file Containerfile.nvidia \
        --tag "{{ image }}-nvidia:{{ tag }}" .

# Split the built image into up to 127 layers by package (rpm-ostree's
# chunker), so an update downloads only the parts that changed. CI does this
# before pushing; local test builds don't need it.
# With an oci directory, the result goes there (as oci:<dir>:<tag>) instead of
# replacing the image: CI pushes it from there with skopeo. That skips copying
# it back into Podman's storage, which unpacks every layer (minutes, and 8 GB
# more disk), and the push recompressing them all.
[group('Build')]
rechunk tag="latest" name=image_name oci="":
    #!/usr/bin/env bash
    set -euo pipefail
    img="localhost/{{ name }}:{{ tag }}"
    oci="{{ oci }}"
    # The chunker writes a fresh image config, so carry the labels over (the
    # daily CI run reads two of them to decide whether to rebuild).
    list=$(podman image inspect "$img" |
        jq -r '.[0].Labels // {} | to_entries[] | "\(.key)=\(.value)"')
    [ -n "$list" ] || { echo "$img has no labels to carry over" >&2; exit 1; }
    labels=()
    while IFS= read -r l; do labels+=(--label "$l"); done <<<"$list"
    if [ -n "$oci" ]; then
        # It is emptied, and goes into a --mount option.
        case "$oci" in
        / | *,*) echo "rechunk: no OCI directory at '$oci'" >&2; exit 1 ;;
        esac
        # An empty layout: the chunker looks for a previous image there first.
        rm -rf "$oci"
        mkdir -p "$oci/blobs/sha256"
        echo '{"imageLayoutVersion":"1.0.0"}' >"$oci/oci-layout"
        echo '{"schemaVersion":2,"manifests":[]}' >"$oci/index.json"
        mounts=(--mount=type=bind,src="$(realpath "$oci")",target=/out,rw)
        output="oci:/out:{{ tag }}"
    else
        graphroot="$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')"
        mounts=(
            --mount=type=bind,src="$graphroot",target=/run/host-container-storage,rw
            --mount=type=tmpfs,target=/run/rpm-ostree-storage
        )
        output="containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]$img"
    fi
    podman run --rm --pull=never --privileged \
        --mount=type=image,src="$img",target=/rpm-ostree \
        "${mounts[@]}" \
        --entrypoint /usr/bin/rpm-ostree \
        "$img" \
        compose build-chunked-oci \
        --max-layers 127 --format-version=2 --bootc "${labels[@]}" \
        --rootfs /rpm-ostree \
        --output "$output"

# Make a VM disk (build/atlasos.qcow2) with bootc-image-builder. Needs sudo.
[group('Disk images')]
qcow2 tag="latest":
    scripts/bib.sh qcow2 "{{ image }}:{{ tag }}"

# Make an installer ISO (build/atlasos.iso) with bootc-image-builder. Needs sudo.
[group('Disk images')]
iso tag="latest":
    scripts/bib.sh iso "{{ image }}:{{ tag }}"

# Boot build/atlasos.qcow2 in libvirt (UEFI, serial console). The disk itself
# is never written: each boot starts from a fresh overlay.
[group('VMs')]
vm:
    scripts/vm.sh run atlasos build/atlasos.qcow2
    @echo "Serial console: virsh -c qemu:///system console atlasos   (leave with Ctrl+])"
    @echo "Screen:         open 'atlasos' in virt-manager"
    @echo "Stop:           just vm-stop"

# Without root: build/vm/updated/atlasos-<tag>.qcow2, which is
# build/atlasos.qcow2 updated in place to the latest local build, the way a
# user's system would be (`bootc switch`).
[group('VMs')]
vm-update tag="latest":
    scripts/vm.sh update atlasos-{{ tag }} {{ tag }}

# Stop and remove the VM `just vm` started (its overlay disk goes with it).
[group('VMs')]
vm-stop name="atlasos":
    scripts/vm.sh stop {{ name }}

# Boot stock Kinoite 44 (installed from the ISO in ~/VMs) and AtlasOS one after
# the other with 8 GB of RAM, and record memory and services 2 minutes after login.
[group('VMs')]
mem-stock disk="build/atlasos.qcow2":
    scripts/vm.sh mem {{ disk }}

# The disk `boot`, `mem` and `check` use: build/atlasos.qcow2 updated to the
# latest local build, logging in to Plasma by itself, booted once already.
[group('Measure')]
bench-disk tag="latest":
    scripts/vm.sh update atlasos-bench {{ tag }} settle

# Boot times: systemd-analyze, blame (top 15), critical-chain, and when Plasma's
# shell starts. `runs` boots, each from a fresh overlay; prints the medians.
[group('Measure')]
boot runs="3" out=("build/bench/boot-" + datetime("%Y%m%d-%H%M%S")):
    scripts/vm.sh bench boot build/vm/updated/atlasos-bench.qcow2 {{ runs }} {{ out }}

# Idle memory two minutes after Plasma starts: free -h and ps_mem.
[group('Measure')]
mem runs="3" out=("build/bench/mem-" + datetime("%Y%m%d-%H%M%S")):
    scripts/vm.sh bench mem build/vm/updated/atlasos-bench.qcow2 {{ runs }} {{ out }}

# Boot and memory from the same boots (what the optimization loop runs).
[group('Measure')]
bench runs="3" out=("build/bench/all-" + datetime("%Y%m%d-%H%M%S")):
    scripts/vm.sh bench all build/vm/updated/atlasos-bench.qcow2 {{ runs }} {{ out }}

# Boot once and check the desktop works: Plasma, network, audio, Bluetooth,
# printing, Flatpak, SELinux, firewalld, zram (zstd), systemd-oomd, power
# profiles, no crashes, and Brave Origin, Ghostty and Dolphin opening.
# Screenshots in the output folder.
[group('Measure')]
check out=("build/bench/check-" + datetime("%Y%m%d-%H%M%S")):
    scripts/vm.sh bench check build/vm/updated/atlasos-bench.qcow2 1 {{ out }}

# Publish a built image to the update test registry (build/vm/updtest) as a
# channel, with optional release notes in Markdown.
publish tag channel="stable" notes="":
    scripts/vm.sh publish {{ tag }} {{ channel }} {{ notes }}

# Boot a VM that tracks the update test registry's stable channel over
# virtiofs, for testing Atlas Updater end to end.
updtest:
    scripts/vm.sh updtest

# Check the Justfile's formatting and lint the scripts.
[group('Checks')]
lint:
    just --unstable --fmt --check
    shellcheck build_files/*.sh build_files/kio/*.sh build_files/plasma-setup/*.sh build_files/nvidia/*.sh system_files_nvidia/usr/libexec/atlasos/* scripts/*.sh scripts/guest/*.sh system_files/usr/libexec/atlasos/* system_files/usr/lib/greenboot/*/*.sh system_files/usr/lib/greenboot/check/required.d/*.sh ci/vps-runner/*.sh ci/vps-runner/hooks/*.sh
    shellcheck -s sh branding/render.sh
    python3 -m py_compile scripts/vmctl.py scripts/vmswitch.py scripts/vmbench.py scripts/benchsum.py scripts/vmlive.py scripts/guest/atspi.py

# Stop the test VMs and remove everything in build/: disk images, the stock
# Kinoite VM (reinstalled on the next `just mem`), the VM password, memory
# reports and the dnf cache. Root's copy of the image, made by `just qcow2`,
# stays; `sudo podman rmi localhost/atlasos` removes it.
[group('Checks')]
clean:
    for vm in atlasos atlasos-bench kinoite-stock kinoite-stock-install; do scripts/vm.sh stop $vm || true; done
    rm -rf build/
