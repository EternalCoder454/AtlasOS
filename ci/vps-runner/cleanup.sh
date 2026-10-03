#!/bin/bash
# Disk housekeeping for the VPS runner, whose disk is a fixed 50 GB. The job
# hooks run it as "podman":
#   atlas-runner-cleanup after-job   after every job, and before the next
#   atlas-runner-cleanup emergency   clear every cache
#   atlas-runner-cleanup list        what after-job would remove, and sizes
#
# after-job removes what the next build can't reuse and keeps what it can:
#   - AtlasOS's own images (the finished image, NVIDIA): every build makes new
#     ones, and they are in the registry by now. They are the ones labelled
#     org.atlasos.base-image, which `just build` puts on the finished images
#     alone: the build steps under them, NVIDIA's included, stay as cache.
#   - Base images a newer pull replaced (yesterday's Kinoite, a fedora:44 that
#     lost its tag), with every cached build step made on top of them.
#   - Podman's build cache mounts (the Rust build cache) and dnf's downloads,
#     each once it passes its limit.
# Then, while less than ATLAS_RUNNER_MIN_FREE_GB is free (what a build needs),
# it clears more, cheapest to rebuild first: the build cache mounts, dnf's
# downloads, and last everything. Otherwise the cached build steps on the
# current base images stay: that is the cache.
set -uo pipefail

storage=/home/podman/.local/share/containers
build_cache_gb=${ATLAS_RUNNER_BUILD_CACHE_GB:-8}
dnf_cache_gb=${ATLAS_RUNNER_DNF_CACHE_GB:-3}
min_free_gb=${ATLAS_RUNNER_MIN_FREE_GB:-16}

log() { echo "cleanup: $*"; }
free_gb() { df -P --block-size=1G "$storage" | awk 'NR == 2 { print $4 }'; }
# podman unshare: build steps leave files owned by ids only it can read.
size_gb() {
    [ $# -gt 0 ] || { echo 0; return; }
    local out
    if ! out=$(podman unshare du -s --block-size=1G "$@" 2>&1); then
        log "can't measure $* ($(tail -1 <<<"$out")); treating it as over its limit" >&2
        echo 999999
        return
    fi
    awk '{ s += $1 } END { print s + 0 }' <<<"$out"
}

# Images as "id|parent|created|names|repo digests", one per line, full ids.
# Every time is in the container's zone (UTC), so the times sort as text.
images() {
    podman images --all --no-trunc \
        --format '{{.ID}}|{{.ParentId}}|{{.CreatedAt}}|{{.Names}}|{{.RepoDigests}}' |
        sed 's/sha256:\([0-9a-f]\{64\}\)|/\1|/g; s/^sha256://'
}

# Remove exactly these images, newest first (children before parents). An
# image whose children come later in the list gets another try.
# --no-prune: otherwise podman also removes each one's unnamed parents, which
# are the cached build steps.
remove_images() {
    local id left
    for _ in 1 2 3; do
        left=()
        for id in "$@"; do
            podman image exists "$id" || continue
            podman rmi --force --no-prune "$id" >/dev/null 2>&1 || left+=("$id")
        done
        [ ${#left[@]} -gt 0 ] || return 0
        set -- "${left[@]}"
    done
    log "could not remove $# images" >&2
}

# AtlasOS's images, newest first.
atlas_images() {
    podman images --all --no-trunc --filter label=org.atlasos.base-image \
        --format '{{.CreatedAt}} {{.ID}}' | sort -r | awk '{ print $NF }' | sed 's/^sha256://'
}

# Pulled base images that a newer pull replaced, and everything built on
# them, newest first:
#   - a pulled image that lost its tag to a newer pull (fedora:44 last week),
#   - a base pulled by digest (Kinoite) other than the newest of its repository.
# A tagged base stays. So do images with no parent that weren't pulled: those
# are FROM scratch stages, and rebuilding one would invalidate every stage
# that copies from it, the Rust build included.
stale_images() {
    images | awk -F'|' '
        {
            id = $1; parent[id] = $2; created[id] = $3; all[id] = 1
            if ($2 != "" || $5 == "[]") next
            names = $4
            gsub(/[][]/, "", names)
            n = split(names, list, " ")
            if (n == 0) { stale[id] = 1; next }
            tagged = 0
            for (i = 1; i <= n; i++) if (list[i] !~ /@/) tagged = 1
            if (tagged) next
            repo = list[1]
            sub(/@.*/, "", repo)
            by_digest[id] = repo
            if (!(repo in newest) || created[id] > created[newest[repo]]) newest[repo] = id
        }
        END {
            for (id in by_digest) if (newest[by_digest[id]] != id) stale[id] = 1
            # Everything built on a stale base is stale too.
            do {
                added = 0
                for (id in all) if (!(id in stale) && (parent[id] in stale)) { stale[id] = 1; added = 1 }
            } while (added)
            for (id in stale) print created[id] "|" id
        }' | sort -r | cut -d'|' -f2
}

cache_dirs() { compgen -G '/var/tmp/buildah-cache-*' || true; }

clear_build_cache() {
    local d
    for d in $(cache_dirs); do podman unshare rm -rf "$d"; done
}
clear_dnf() { podman unshare rm -rf /cache/dnf; }

emergency() {
    log "clearing every cache ($(free_gb) GB free)"
    podman container prune --force >/dev/null
    podman image prune --all --force >/dev/null
    clear_build_cache
    clear_dnf
}

after_job() {
    local ids dirs size
    # Containers a cancelled step left behind.
    podman container prune --force >/dev/null

    mapfile -t ids < <(atlas_images)
    if [ ${#ids[@]} -gt 0 ]; then
        log "removing ${#ids[@]} AtlasOS images"
        remove_images "${ids[@]}"
    fi

    mapfile -t ids < <(stale_images)
    if [ ${#ids[@]} -gt 0 ]; then
        log "removing ${#ids[@]} images built on replaced base images"
        remove_images "${ids[@]}"
    fi

    mapfile -t dirs < <(cache_dirs)
    size=$(size_gb "${dirs[@]}")
    if [ "$size" -gt "$build_cache_gb" ]; then
        log "build cache mounts use ${size} GB (limit ${build_cache_gb}): clearing them"
        clear_build_cache
    fi
    # Podman's leftovers from interrupted pulls and builds.
    find /var/tmp -mindepth 1 -maxdepth 1 -mmin +720 ! -name 'buildah-cache-*' \
        -exec podman unshare rm -rf {} + 2>/dev/null

    if [ -d /cache/dnf ]; then
        find /cache/dnf -name '*.rpm' -mtime +30 -delete 2>/dev/null
        size=$(size_gb /cache/dnf)
        if [ "$size" -gt "$dnf_cache_gb" ]; then
            log "dnf cache uses ${size} GB (limit ${dnf_cache_gb}): clearing it"
            clear_dnf
        fi
    fi

    # Room for the next build, giving up the cheapest caches first.
    if [ "$(free_gb)" -lt "$min_free_gb" ]; then
        log "$(free_gb) GB free, a build needs ${min_free_gb}: clearing the build cache mounts"
        clear_build_cache
    fi
    if [ "$(free_gb)" -lt "$min_free_gb" ]; then
        log "$(free_gb) GB free: clearing dnf's downloads"
        clear_dnf
    fi
    if [ "$(free_gb)" -lt "$min_free_gb" ]; then
        emergency
    fi
    log "$(free_gb) GB free"
}

list() {
    local dirs
    echo "AtlasOS images:"; atlas_images
    echo "Images on replaced base images:"; stale_images
    mapfile -t dirs < <(cache_dirs)
    echo "Build cache mounts: $(size_gb "${dirs[@]}") GB (limit ${build_cache_gb})"
    dirs=()
    if [ -d /cache/dnf ]; then dirs=(/cache/dnf); fi
    echo "dnf cache: $(size_gb "${dirs[@]}") GB (limit ${dnf_cache_gb})"
    echo "Free: $(free_gb) GB (a build needs ${min_free_gb})"
}

case ${1:-} in
after-job) after_job ;;
emergency) emergency ;;
list) list ;;
*) echo "usage: atlas-runner-cleanup after-job|emergency|list" >&2; exit 2 ;;
esac
