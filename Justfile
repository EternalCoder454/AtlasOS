image_name := "atlasos"
image := "localhost/" + image_name
# The rechunker (see `rechunk`).
chunkah := "quay.io/coreos/chunkah@sha256:0da1fa543fafe92468ad667d00580aea544a384198f668f1499675c241642e11"
# The SBOM generator and vulnerability scanner (see `sbom`).
syft := "ghcr.io/anchore/syft:v1.54.0@sha256:0356562f495d432056237fbea5cbc2d4839c9c75cd500784a66de2e7cc95ca7c"
grype := "ghcr.io/anchore/grype:v0.120.0@sha256:5c88961f4130e830542d441c7ed6c78baa28e799163abac53d2be4923fb5ab7d"

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
    # CI passes IMAGE_VERSION (44.YYYYMMDD-N) so the image and its pushed tag
    # carry the same version; a local build is the plain 44.YYYYMMDD.
    version="${IMAGE_VERSION:-44.$(date -u +%Y%m%d)}"
    # The Atlas apps' source (Atlas Updater and atlas-core): a named build
    # context, so the Containerfile can build their RPMs. CI points it at a
    # checkout of EternalCoder454/atlasos-updater.
    updater="${ATLAS_UPDATER_SRC:-../Atlas Updater}"
    [ -d "$updater/packaging" ] || { echo "Atlas Updater source not found at '$updater' (set ATLAS_UPDATER_SRC)" >&2; exit 1; }
    # Atlas Monitor's source: the build context named "atlas-monitor". CI
    # points it at a checkout of EternalCoder454/atlasos-monitor.
    monitor="${ATLAS_MONITOR_SRC:-../AtlasOS Monitor}"
    [ -d "$monitor/packaging" ] || { echo "Atlas Monitor source not found at '$monitor' (set ATLAS_MONITOR_SRC)" >&2; exit 1; }
    # Only the files git keeps (tracked, plus new ones it doesn't ignore) go
    # in: a local checkout's target/ is many GB, and podman would copy all of
    # it each build and rebuild the RPMs whenever a cargo build touched it.
    copy_source() { # checkout, destination
        rm -rf "$2"
        mkdir -p "$2"
        git -C "$1" ls-files -z --cached --others --exclude-standard |
            rsync -a --from0 --files-from=- --ignore-missing-args "$1/" "$2/"
    }
    copy_source "$updater" build/updater-src
    copy_source "$monitor" build/monitor-src
    podman build --pull=newer \
        --build-context atlas-updater=build/updater-src \
        --build-context atlas-monitor=build/monitor-src \
        --volume "$dnf_cache:/var/cache/libdnf5:Z" \
        --build-arg IMAGE_VERSION="$version" \
        --build-arg PACKAGES_DATE="$(date -u +%F)" \
        --label org.opencontainers.image.version="$version" \
        --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
        --label net.eterneon.atlas.updater.revision="$(git -C "$updater" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.atlas.monitor.revision="$(git -C "$monitor" rev-parse HEAD 2>/dev/null || echo unknown)" \
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

# Split the built image into up to 127 layers by package (chunkah), so an
# update downloads only the parts that changed. CI does this before pushing;
# local test builds don't need it.
# With an oci directory, the result goes there (as oci:<dir>:<tag>) instead of
# replacing the image: CI pushes it from there with skopeo, which uploads the
# layers as compressed here, and only those the registry doesn't have.
# chunkah compresses the layers in parallel and writes a plain OCI image (no
# OSTree commit, which rpm-ostree's chunker spent minutes making). The layers
# depend only on the files and SOURCE_DATE_EPOCH, the commit's time here: a
# build of the same files makes the same layers.
[group('Build')]
rechunk tag="latest" name=image_name oci="":
    #!/usr/bin/env bash
    set -euo pipefail
    img="localhost/{{ name }}:{{ tag }}"
    oci="{{ oci }}"
    keep=1
    if [ -z "$oci" ]; then
        oci="$PWD/build/rechunk"
        keep=
    fi
    # It is removed (chunkah makes it), and its parent goes into a --mount
    # option.
    case "$oci" in
    / | *,*) echo "rechunk: no OCI directory at '$oci'" >&2; exit 1 ;;
    esac
    rm -rf "$oci"
    mkdir -p "$(dirname "$oci")"
    parent=$(realpath "$(dirname "$oci")")
    # The image's config (labels, command) carries over, without the base
    # image's OSTree labels, which describe a commit this image doesn't have.
    config=$(podman image inspect "$img" | jq -c '.[0].Config')
    podman run --rm --pull=missing --security-opt label=disable \
        --mount=type=image,src="$img",target=/chunkah \
        --mount=type=bind,src="$parent",target=/out,rw \
        -e CHUNKAH_CONFIG_STR="$config" \
        -e SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
        {{ chunkah }} build --rootfs /chunkah --prune /sysroot/ \
        --max-layers 127 --compressed \
        --label ostree.commit- --label ostree.final-diffid- \
        --tag "{{ tag }}" --output "oci:/out/$(basename "$oci")"
    if [ -z "$keep" ]; then
        id=$(podman pull -q "oci:$oci:{{ tag }}")
        podman tag "$id" "$img"
        rm -rf "$oci"
    fi

# What the built image contains and its known vulnerabilities, into a
# directory: sbom.spdx.json (SPDX, from syft) and vulnerabilities.json and
# vulnerabilities.txt (grype, matched against that SBOM). Both run from their
# own container images with the image mounted, not copied. CI attaches the
# SBOM to the signed image. Reports only: findings don't fail it. grype has
# no Fedora data, so it checks the Go and Python modules built into programs,
# not the RPMs themselves: those get their fixes from Fedora's updates, which
# the daily build picks up.
[group('Build')]
sbom tag="latest" out="build/sbom" name=image_name:
    #!/usr/bin/env bash
    set -euo pipefail
    img="localhost/{{ name }}:{{ tag }}"
    mkdir -p "{{ out }}"
    out=$(realpath "{{ out }}")
    # Packages only: listing every file made the SBOM 100 MB (22 MB without).
    podman run --rm --pull=missing --security-opt label=disable --user 0 \
        -e SYFT_FILE_METADATA_SELECTION=none \
        -e SYFT_RELATIONSHIPS_PACKAGE_FILE_OWNERSHIP=false \
        --mount=type=image,src="$img",target=/rootfs \
        --mount=type=bind,src="$out",target=/out,rw \
        {{ syft }} scan dir:/rootfs --quiet \
        --source-name "{{ name }}" --source-version "{{ tag }}" \
        -o spdx-json=/out/sbom.spdx.json
    # grype's vulnerability database (about 1 GB unpacked) is downloaded each
    # time into a directory beside the output, which goes afterwards (not
    # /tmp, which can be a small tmpfs). Matched as Fedora 44, which syft
    # can't tell from os-release (ID=atlasos).
    db=$(mktemp -d "$(dirname "$out")/grype-db.XXXXXX")
    trap 'rm -rf "$db"' EXIT
    podman run --rm --pull=missing --security-opt label=disable --user 0 \
        --mount=type=bind,src="$out",target=/out,rw \
        --mount=type=bind,src="$db",target=/db,rw \
        -e GRYPE_DB_CACHE_DIR=/db \
        {{ grype }} sbom:/out/sbom.spdx.json --quiet --distro fedora:44 \
        -o json=/out/vulnerabilities.json -o table=/out/vulnerabilities.txt
    jq -r '[.matches[].vulnerability.severity] | group_by(.) | map("\(.[0]): \(length)") | .[]' \
        "$out/vulnerabilities.json"

# Make a VM disk (build/atlasos.qcow2) with bootc-image-builder. Needs sudo.
[group('Disk images')]
qcow2 tag="latest":
    scripts/bib.sh qcow2 "{{ image }}:{{ tag }}"

# The live installer ISO, made with AtlasOS Installer (../AtlasOS Installer,
# or the folder in ATLAS_INSTALLER_SRC). No root.
# Live installer ISO build/<name>.iso of ghcr.io/eternalcoder454/<name>:<tag>
[group('Disk images')]
iso tag="stable" name=image_name:
    "${ATLAS_INSTALLER_SRC:-../AtlasOS Installer}/iso/make-iso.sh" -o "build/{{ name }}.iso" {{ name }} {{ tag }}

# The same, to try a build before it's published. Its first update downloads
# the whole image, since its layers match nothing on ghcr.io.
# Live installer ISO build/<name>.iso of the local build localhost/<name>:<tag>
[group('Disk images')]
iso-local tag="latest" name=image_name:
    "${ATLAS_INSTALLER_SRC:-../AtlasOS Installer}/iso/make-iso.sh" --local -o "build/{{ name }}.iso" {{ name }} {{ tag }}

# Kept until the live installer passes its test matrix.
# Anaconda installer ISO build/atlasos.iso (bootc-image-builder). Needs sudo.
[group('Disk images')]
iso-anaconda tag="latest":
    rm -f build/atlasos.iso.image
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
    shellcheck -s sh branding/render.sh system_files/usr/bin/atlas system_files/etc/profile.d/*.sh system_files/usr/lib/systemd/user-environment-generators/*
    just --unstable --fmt --check --justfile system_files/usr/share/atlasos/atlas.just
    python3 -m py_compile scripts/vmctl.py scripts/vmswitch.py scripts/vmbench.py scripts/benchsum.py scripts/vmlive.py scripts/guest/atspi.py

# Stop the test VMs and remove everything in build/: disk images, the stock
# Kinoite VM (reinstalled on the next `just mem`), the VM password, memory
# reports and the dnf cache. Root's copy of the image, made by `just qcow2`,
# stays; `sudo podman rmi localhost/atlasos` removes it.
[group('Checks')]
clean:
    for vm in atlasos atlasos-bench kinoite-stock kinoite-stock-install; do scripts/vm.sh stop $vm || true; done
    rm -rf build/
