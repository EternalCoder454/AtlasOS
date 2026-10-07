image_name := "telamonos"
# What the live installer ISO is called, and the image it installs from: not
# renamed yet (the website downloads build/atlasos.iso; see DEV.md, "Telamon").
iso_name := "atlasos"
image := "localhost/" + image_name
# The rechunker (see `rechunk`).
chunkah := "quay.io/coreos/chunkah@sha256:0da1fa543fafe92468ad667d00580aea544a384198f668f1499675c241642e11"
# What compresses its layers with zstd (see `rechunk`): pinned, since another
# encoder version could compress the same layer to other bytes. The
# -immutable tag: quay rebuilds v1.22.3 every day and deletes the digests the
# tag leaves behind, so a pin on it stopped pulling ("manifest unknown").
skopeo := "quay.io/skopeo/stable:v1.22.3-immutable@sha256:c0ee1f4edca5c01cb8d5611124f92f3cc47196ecab68aee5d0f90834e00574d5"
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
    # image). The VPS runner sets ATLAS_DNF_CACHE (still read) to a directory outside the
    # checkout, which actions/checkout cleans.
    dnf_cache="${TELAMON_DNF_CACHE:-${ATLAS_DNF_CACHE:-$PWD/build/cache/dnf}}"
    mkdir -p "$dnf_cache"
    # CI passes IMAGE_VERSION (44.YYYYMMDD-N) so the image and its pushed tag
    # carry the same version; a local build is the plain 44.YYYYMMDD.
    version="${IMAGE_VERSION:-44.$(date -u +%Y%m%d)}"
    # The Telamon apps' and telamon-framework's source, each a named build context
    # the Containerfile builds RPMs from: the commits pinned in
    # telamon-apps.lock, fetched into build/pinned/ (CI checks the same commits
    # out). To build a local checkout instead while working on an app, point
    # TELAMON_FRAMEWORK_SRC, TELAMON_UPDATER_SRC, TELAMON_MONITOR_SRC,
    # TELAMON_NOTEPAD_SRC, TELAMON_SETTINGS_SRC, TELAMON_WIZARD_SRC, TELAMON_STORE_SRC, TELAMON_EXPLORER_SRC, TELAMON_ARCHIVE_SRC, TELAMON_LAUNCHER_SRC, TELAMON_SCREENSHOT_SRC or TELAMON_INSTALLER_SRC at it; the image's label then names that checkout's
    # commit, so it can't pass for a pinned build.
    app_source() { # name, the variable's value (empty: the pin)
        if [ -n "$2" ]; then
            printf '%s\n' "$2"
        else
            # `|| exit 1`: set -e doesn't reach inside $(...), and a failed
            # fetch would otherwise build whatever build/pinned/ held before.
            scripts/telamon-pins.py fetch "$1" "build/pinned/$1" >&2 || exit 1
            printf '%s\n' "build/pinned/$1"
        fi
    }
    framework=$(app_source framework "${TELAMON_FRAMEWORK_SRC:-}")
    updater=$(app_source updater "${TELAMON_UPDATER_SRC:-}")
    monitor=$(app_source monitor "${TELAMON_MONITOR_SRC:-}")
    notepad=$(app_source notepad "${TELAMON_NOTEPAD_SRC:-}")
    settings=$(app_source settings "${TELAMON_SETTINGS_SRC:-}")
    wizard=$(app_source wizard "${TELAMON_WIZARD_SRC:-}")
    store=$(app_source store "${TELAMON_STORE_SRC:-}")
    explorer=$(app_source explorer "${TELAMON_EXPLORER_SRC:-}")
    archive=$(app_source archive "${TELAMON_ARCHIVE_SRC:-}")
    launcher=$(app_source launcher "${TELAMON_LAUNCHER_SRC:-}")
    screenshot=$(app_source screenshot "${TELAMON_SCREENSHOT_SRC:-}")
    installer=$(app_source installer "${TELAMON_INSTALLER_SRC:-}")
    for dir in "$framework" "$updater" "$monitor" "$notepad" "$settings" "$wizard" "$store" "$explorer" "$archive" "$launcher" "$screenshot"; do
        [ -d "$dir/packaging" ] || { echo "No app source (packaging/) at '$dir'" >&2; exit 1; }
    done
    [ -x "$installer/firstboot/install.sh" ] || { echo "No installer source (firstboot/install.sh) at '$installer'" >&2; exit 1; }
    # Only the files git keeps (tracked, plus new ones it doesn't ignore) go
    # in: a local checkout's target/ is many GB, and podman would copy all of
    # it each build and rebuild the RPMs whenever a cargo build touched it.
    copy_source() { # checkout, destination
        rm -rf "$2"
        mkdir -p "$2"
        git -C "$1" ls-files -z --cached --others --exclude-standard |
            rsync -a --from0 --files-from=- --ignore-missing-args "$1/" "$2/"
        # An app's own .containerignore is written for its dev image (the
        # wizard's keeps only its spec), and podman applies it to a named
        # build context too, hiding packaging/build-rpm.sh from the stage.
        rm -f "$2/.containerignore" "$2/.dockerignore"
    }
    copy_source "$framework" build/framework-src
    copy_source "$updater" build/updater-src
    copy_source "$monitor" build/monitor-src
    copy_source "$notepad" build/notepad-src
    copy_source "$settings" build/settings-src
    copy_source "$wizard" build/wizard-src
    copy_source "$store" build/store-src
    copy_source "$explorer" build/explorer-src
    copy_source "$archive" build/archive-src
    copy_source "$launcher" build/launcher-src
    copy_source "$screenshot" build/screenshot-src
    copy_source "$installer" build/installer-src
    podman build --pull=newer \
        --build-context telamon-framework=build/framework-src \
        --build-context telamon-updater=build/updater-src \
        --build-context telamon-monitor=build/monitor-src \
        --build-context telamon-notepad=build/notepad-src \
        --build-context telamon-settings=build/settings-src \
        --build-context telamon-wizard=build/wizard-src \
        --build-context telamon-store=build/store-src \
        --build-context telamon-explorer=build/explorer-src \
        --build-context telamon-archive=build/archive-src \
        --build-context telamon-launcher=build/launcher-src \
        --build-context telamon-screenshot=build/screenshot-src \
        --build-context telamon-installer=build/installer-src \
        --security-opt label=disable \
        --volume "$dnf_cache:/var/cache/libdnf5" \
        --build-arg IMAGE_VERSION="$version" \
        --build-arg PACKAGES_DATE="$(date -u +%F)" \
        --label org.opencontainers.image.version="$version" \
        --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
        --label net.eterneon.telamon.framework.revision="$(git -C "$framework" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.updater.revision="$(git -C "$updater" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.monitor.revision="$(git -C "$monitor" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.notepad.revision="$(git -C "$notepad" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.settings.revision="$(git -C "$settings" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.wizard.revision="$(git -C "$wizard" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.store.revision="$(git -C "$store" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.explorer.revision="$(git -C "$explorer" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.archive.revision="$(git -C "$archive" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.launcher.revision="$(git -C "$launcher" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.screenshot.revision="$(git -C "$screenshot" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label net.eterneon.telamon.installer.revision="$(git -C "$installer" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label "org.opencontainers.image.title=Telamon OS" \
        --label org.opencontainers.image.description="Minimal Fedora Kinoite 44 desktop" \
        --label org.opencontainers.image.licenses=Apache-2.0 \
        --label containers.bootc=1 \
        {{ args }} \
        --tag "{{ image }}:{{ tag }}" .

# Each pin must be on its repository's main branch, and match its release tag
# where it has one.
# Show and check the Telamon app pins (telamon-apps.lock)
[group('Build')]
pins:
    @scripts/telamon-pins.py list
    @scripts/telamon-pins.py verify

# Each moves to its newest release, or its main branch's head for an app with
# no releases yet, and the commits it brings are listed. A pin never moves
# back. Then build, test and commit telamon-apps.lock.
# Move the Telamon app pins forward (all, or the one named)
[group('Build')]
pins-update name="":
    #!/usr/bin/env bash
    set -euo pipefail
    names={{ quote(name) }}
    [ -n "$names" ] || names="framework updater monitor notepad settings wizard store explorer archive launcher screenshot installer"
    for n in $names; do
        newest=$(scripts/telamon-pins.py latest "$n")
        read -r sha tag <<<"$newest"
        if [ "$sha" = "$(scripts/telamon-pins.py get "$n")" ]; then
            echo "$n: up to date"
            continue
        fi
        echo "$n: what the new pin brings"
        scripts/telamon-pins.py log "$n" "$sha" | sed 's/^/  /'
        scripts/telamon-pins.py set "$n" "$sha" "$tag"
    done

# Build the NVIDIA image (localhost/telamonos-nvidia) on top of a built Telamon OS
# image with the same tag. Needs the module signing key: secrets/nvidia-signing.key
# here, or the file named in NVIDIA_SIGNING_KEY (CI). Extra arguments go to
# `podman build`.
[group('Build')]
build-nvidia tag="latest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    key="${NVIDIA_SIGNING_KEY:-secrets/nvidia-signing.key}"
    [ -s "$key" ] || { echo "No module signing key at $key (see DEV.md, NVIDIA)" >&2; exit 1; }
    dnf_cache="${TELAMON_DNF_CACHE:-${ATLAS_DNF_CACHE:-$PWD/build/cache/dnf}}"
    mkdir -p "$dnf_cache"
    podman build \
        --security-opt label=disable \
        --volume "$dnf_cache:/var/cache/libdnf5" \
        --secret id=nvidia-signing-key,src="$key" \
        --build-arg BASE_IMAGE="{{ image }}:{{ tag }}" \
        --label org.opencontainers.image.title="Telamon OS (NVIDIA)" \
        --label org.opencontainers.image.description="Minimal Fedora Kinoite 44 desktop with NVIDIA's driver" \
        {{ args }} \
        --file Containerfile.nvidia \
        --tag "{{ image }}-nvidia:{{ tag }}" .

# Split the built image into up to 127 layers by package (chunkah), so an
# update downloads only the parts that changed. CI does this before pushing;
# local test builds don't need it.
# Before that, build_files/layer-hints.sh runs in a throwaway copy of the
# image: it zeroes the times left from the build and tells chunkah which files
# belong together and how often they change (the locale archive, Telamon's own
# files). Nothing in the image changes but times and two attributes per file.
# `scripts/update-size.py` measures what an update then downloads.
# With an oci directory, the result goes there (as oci:<dir>:<tag>) instead of
# replacing the image: CI pushes it from there with skopeo, which uploads the
# layers as compressed here, and only those the registry doesn't have.
# chunkah writes a plain OCI image (no OSTree commit, which rpm-ostree's
# chunker spent minutes making), with gzip at its fastest level; skopeo then
# compresses each layer again with zstd at level 7 (12% smaller than gzip's
# level 6, and quicker to unpack). The gzip keeps the disk this takes small:
# about 3 GB of gzip beside the 2.7 GB result (5.6 GB at the peak);
# uncompressed layers would take 7 GB. The layers depend only on the files
# and SOURCE_DATE_EPOCH, the commit's time here, and the pinned zstd encoder
# (not on the gzip): a build of the same files makes the same layers. (Plain
# zstd, not zstd:chunked, which bootc's ostree backend doesn't read reliably
# yet. Levels above 7 took three times as long for 4% more.)
[group('Build')]
rechunk tag="latest" name=image_name oci="" layers="127":
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
    while [ "${oci%/}" != "$oci" ]; do oci="${oci%/}"; done
    case "$oci" in
    "" | . | .. | */. | */.. | *,*) echo "rechunk: no OCI directory at '{{ oci }}'" >&2; exit 1 ;;
    esac
    # chunkah's gzip copy goes when done or failed; so does the result when
    # it only feeds the local image, and the hinted copy of the image always.
    gz="$oci.gzip"
    hinted="localhost/{{ name }}-hinted:{{ tag }}"
    trap 'rm -rf "$gz"; [ -n "$keep" ] || rm -rf "$oci"; podman rmi -f "$hinted" >/dev/null 2>&1 || true' EXIT
    rm -rf "$oci" "$gz"
    mkdir -p "$(dirname "$oci")"
    parent=$(realpath "$(dirname "$oci")")
    # --no-cache: a RUN step's cache key doesn't include what is mounted into
    # it, so a changed script would keep the old result.
    printf 'FROM %s\nRUN --mount=type=bind,source=build_files/layer-hints.sh,target=/hints/layer-hints.sh --mount=type=bind,source=system_files,target=/hints/system_files bash /hints/layer-hints.sh /hints/system_files\n' "$img" |
        podman build --quiet --no-cache --pull=never --security-opt label=disable \
            --tag "$hinted" --file - . >/dev/null
    # The image's config (labels, command) carries over, without the base
    # image's OSTree labels, which describe a commit this image doesn't have.
    config=$(podman image inspect "$hinted" | jq -c '.[0].Config')
    # The time layers and the image are made at: the commit's, unless
    # SOURCE_DATE_EPOCH says otherwise (reproducing an older build).
    podman run --rm --pull=missing --security-opt label=disable \
        --mount=type=image,src="$hinted",target=/chunkah \
        --mount=type=bind,src="$parent",target=/out,rw \
        -e CHUNKAH_CONFIG_STR="$config" \
        -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}" \
        {{ chunkah }} build --rootfs /chunkah --prune /sysroot/ \
        --max-layers {{ layers }} --compressed --compression-level 1 \
        --label ostree.commit- --label ostree.final-diffid- \
        --tag "{{ tag }}" --output "oci:/out/$(basename "$gz")"
    # (the image's entrypoint is skopeo)
    podman run --rm --pull=missing --security-opt label=disable \
        --mount=type=bind,src="$parent",target=/out,rw \
        {{ skopeo }} copy --quiet --dest-force-compress-format \
        --dest-compress-format zstd --dest-compress-level 7 \
        "oci:/out/$(basename "$gz"):{{ tag }}" "oci:/out/$(basename "$oci"):{{ tag }}"
    rm -rf "$gz"
    if [ -z "$keep" ]; then
        id=$(podman pull -q "oci:$oci:{{ tag }}")
        podman tag "$id" "$img"
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
    # can't tell from os-release (ID=telamonos).
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

# The live installer ISO, made with Telamon Installer (../AtlasOS Installer,
# or the folder in TELAMON_INSTALLER_SRC). No root. Its image names are still
# the ones before Telamon (atlasos, atlasos-nvidia): the same builds are
# published under both, and the ISO's file name is what the website downloads.
# Live installer ISO build/<name>.iso of ghcr.io/eternalcoder454/<name>:<tag>
[group('Disk images')]
iso tag="stable" name=iso_name:
    "${TELAMON_INSTALLER_SRC:-../AtlasOS Installer}/iso/make-iso.sh" -o "build/{{ name }}.iso" {{ name }} {{ tag }}

# The same, to try a build before it's published. Its first update downloads
# the whole image, since its layers match nothing on ghcr.io. The installer
# looks for localhost/<name>, so the build gets that name too (the same image).
# Live installer ISO build/<name>.iso of the local build localhost/<name>:<tag>
[group('Disk images')]
iso-local tag="latest" name=iso_name:
    podman tag "localhost/{{ replace(name, 'atlasos', 'telamonos') }}:{{ tag }}" "localhost/{{ name }}:{{ tag }}"
    "${TELAMON_INSTALLER_SRC:-../AtlasOS Installer}/iso/make-iso.sh" --local -o "build/{{ name }}.iso" {{ name }} {{ tag }}

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

# Boot stock Kinoite 44 (installed from the ISO in ~/VMs) and Telamon OS one after
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
# virtiofs, for testing Telamon Updater end to end.
updtest:
    scripts/vm.sh updtest

# Check the Justfile's formatting and lint the scripts.
[group('Checks')]
lint:
    just --unstable --fmt --check
    shellcheck build_files/*.sh build_files/kio/*.sh build_files/nvidia/*.sh system_files_nvidia/usr/libexec/telamon/* scripts/*.sh scripts/guest/*.sh $(grep -lE '^#!.*sh$' system_files/usr/libexec/telamon/*) system_files/usr/lib/greenboot/*/*.sh system_files/usr/lib/greenboot/check/required.d/*.sh ci/vps-runner/*.sh ci/vps-runner/hooks/*.sh
    shellcheck -s sh branding/render.sh system_files/usr/bin/telamon system_files/etc/profile.d/*.sh system_files/usr/lib/systemd/user-environment-generators/*
    shellcheck -s sh system_files/usr/share/kconf_update/*.sh
    just --unstable --fmt --check --justfile system_files/usr/share/telamon/telamon.just
    python3 -m py_compile scripts/vmctl.py scripts/vmswitch.py scripts/vmbench.py scripts/benchsum.py scripts/vmlive.py scripts/guest/atspi.py system_files/usr/libexec/telamon/pinlib.py
    python3 -m py_compile system_files/usr/libexec/telamon/pin-admin system_files/usr/libexec/telamon/pin-daemon
    python3 -m py_compile scripts/telamon-pins.py scripts/update-size.py scripts/build-notes.py
    scripts/telamon-pins.py list >/dev/null
    rm -rf system_files/usr/libexec/telamon/__pycache__ scripts/__pycache__

# Stop the test VMs and remove everything in build/: disk images, the stock
# Kinoite VM (reinstalled on the next `just mem`), the VM password, memory
# reports and the dnf cache. Root's copy of the image, made by `just qcow2`,
# stays; `sudo podman rmi localhost/atlasos` removes it.
[group('Checks')]
clean:
    for vm in atlasos atlasos-bench kinoite-stock kinoite-stock-install; do scripts/vm.sh stop $vm || true; done
    rm -rf build/
