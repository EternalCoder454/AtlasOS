#!/bin/bash
# Set up the AtlasOS self-hosted GitHub Actions runner on a VPS (see README.md
# here). Run as root from a checkout of the AtlasOS repository:
#
#   sudo ci/vps-runner/setup.sh check      report what the VPS has and lacks; changes nothing
#   sudo ci/vps-runner/setup.sh install    install Podman, the atlas-runner account, image and service
#   sudo ci/vps-runner/setup.sh register   register with GitHub and start (token on stdin)
#   sudo ci/vps-runner/setup.sh image      rebuild the runner image and restart
#   sudo ci/vps-runner/setup.sh status     service state, disk use and the last log lines
#   sudo ci/vps-runner/setup.sh cache      cache sizes, and what the next cleanup removes
#   sudo ci/vps-runner/setup.sh start|stop|restart
#   sudo ci/vps-runner/setup.sh clear-cache  stop, delete every cache, start again
#   sudo ci/vps-runner/setup.sh unregister remove from GitHub and stop (removal token on stdin)
# image, stop, restart and clear-cache first wait for a running job to finish;
# with FORCE=1 they don't (the job fails).
#
# Settings, as environment variables:
#   RUNNER_USER=atlas-runner          the account the runner runs as
#   RUNNER_HOME=/var/lib/atlas-runner its home; all runner data and caches live here
#   RUNNER_REPO=EternalCoder454/AtlasOS
#   RUNNER_DISK_GB=50                 size of RUNNER_HOME's own disk, an ext4 image file
#                                     (RUNNER_HOME.img), unless RUNNER_HOME is a mount already
#   CPU_WEIGHT=20                     the runner's CPU share against the VPS's other
#                                     services (100 is everyone else's); idle CPU in full
#   MEMORY_HIGH=3584M MEMORY_MAX=4G   memory throttle and hard limit for the runner
#   MEMORY_SWAP_MAX=1G                swap it may use
set -euo pipefail

RUNNER_USER=${RUNNER_USER:-atlas-runner}
RUNNER_HOME=${RUNNER_HOME:-/var/lib/atlas-runner}
RUNNER_REPO=${RUNNER_REPO:-EternalCoder454/AtlasOS}
RUNNER_DISK_GB=${RUNNER_DISK_GB:-50}
CPU_WEIGHT=${CPU_WEIGHT:-20}
MEMORY_HIGH=${MEMORY_HIGH:-3584M}
MEMORY_MAX=${MEMORY_MAX:-4G}
MEMORY_SWAP_MAX=${MEMORY_SWAP_MAX:-1G}

here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
unit=atlas-runner
image=localhost/atlas-runner:latest
disk_image=${RUNNER_HOME}.img
# Space the disk image must leave on its filesystem for the VPS's other services.
headroom_gb=5
firewall=/etc/atlas-runner/firewall.nft
# Settings for the runner (cleanup limits); 'install' creates it and leaves it alone after.
runner_env=/etc/atlas-runner/runner.env

die() { echo "setup.sh: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || [ -z "${1:-}" ] || die "run as root (sudo)"

uid_of() { id -u "$RUNNER_USER"; }

# Run a command as the runner account, with its systemd user manager reachable.
as_runner() {
    local uid
    uid=$(uid_of)
    runuser -u "$RUNNER_USER" -- env -C "$RUNNER_HOME" HOME="$RUNNER_HOME" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# The nearest existing directory at or above $1 (for df before it exists).
existing_parent() {
    local d=$1
    while [ ! -d "$d" ]; do d=$(dirname "$d"); done
    echo "$d"
}

# ---------------------------------------------------------------- check
missing=0
report() { # report STATUS WHAT DETAIL
    printf '  %-8s %-26s %s\n' "$1" "$2" "$3"
    if [ "$1" = MISSING ]; then missing=$((missing + 1)); fi
}

check() {
    missing=0
    echo "AtlasOS runner prerequisites on $(hostname):"

    # /dev/kvm: not used by today's workflows, wanted for VM boot tests later.
    if [ -c /dev/kvm ]; then
        report OK /dev/kvm "present ($(stat -c '%G %a' /dev/kvm))"
    else
        report WARN /dev/kvm "no KVM (not needed yet); enable nested virtualisation with the VPS provider"
    fi

    # Podman. The runner uses rootless Podman (as on GitHub's hosted runners);
    # rootful is reported because it is the same package.
    if command -v podman >/dev/null; then
        report OK "podman" "$(podman --version)"
        if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -qx false; then
            report OK "rootful podman" "works (the runner doesn't use it)"
        else
            report WARN "rootful podman" "podman info as root failed"
        fi
    else
        report MISSING "podman" "not installed ('install' adds it)"
        report MISSING "rootful podman" "not installed ('install' adds it; the runner itself runs rootless)"
    fi
    for tool in newuidmap newgidmap; do
        command -v "$tool" >/dev/null || report MISSING "$tool" "package uidmap ('install' adds it)"
    done

    # Disk: the runner gets a disk of its own, so it can't fill the one the
    # VPS's other services use.
    local dir free size
    if mountpoint -q "$RUNNER_HOME"; then
        size=$(df -P --block-size=1G "$RUNNER_HOME" | awk 'NR == 2 { print $2 }')
        report OK "disk" "$RUNNER_HOME is a filesystem of its own, ${size} GB ($(findmnt -no SOURCE "$RUNNER_HOME"))"
    elif [ -e "$disk_image" ]; then
        report OK "disk" "$disk_image exists, not mounted ('install' mounts it)"
    else
        dir=$(existing_parent "$disk_image")
        free=$(df -P --block-size=1G "$dir" | awk 'NR == 2 { print $4 }')
        # fallocate reserves the space only on these.
        case $(stat -f -c %T "$dir") in
        ext2/ext3 | ext4 | xfs) ;;
        *) report WARN "disk" "$dir is on $(stat -f -c %T "$dir"): the disk image's space can't be reserved up front" ;;
        esac
        if [ "$free" -ge $((RUNNER_DISK_GB + headroom_gb)) ]; then
            report OK "disk" "${free} GB free: room for the ${RUNNER_DISK_GB} GB $disk_image, leaving $((free - RUNNER_DISK_GB)) GB"
        else
            report MISSING "disk" "${free} GB free; the ${RUNNER_DISK_GB} GB $disk_image needs $((RUNNER_DISK_GB + headroom_gb)) GB (or set RUNNER_DISK_GB)"
        fi
    fi

    # Size of the machine (information: the build runs on 4 CPUs too).
    local mem
    mem=$(awk '/MemTotal/ { printf "%.1f", $2 / 1048576 }' /proc/meminfo)
    report INFO "cpu / memory" "$(nproc) CPUs, ${mem} GB RAM"

    # Kernel features rootless Podman in a container needs.
    for dev in /dev/fuse /dev/net/tun; do
        if [ -c "$dev" ]; then report OK "$dev" "present"; else report MISSING "$dev" "not present"; fi
    done
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        report OK "cgroup v2" "$(cat /sys/fs/cgroup/cgroup.controllers)"
    else
        report MISSING "cgroup v2" "systemd's resource limits for the runner need it"
    fi
    command -v nft >/dev/null || report MISSING "nft" "package nftables ('install' adds it), for the runner's firewall"
    command -v mkfs.ext4 >/dev/null || report MISSING "mkfs.ext4" "package e2fsprogs ('install' adds it)"
    local userns
    userns=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo n/a)
    report INFO "apparmor userns limit" "$userns (Ubuntu's Podman package has a profile that allows it)"

    # Other services on the box.
    if command -v docker >/dev/null; then
        report INFO "docker" "running $(docker ps -q 2>/dev/null | wc -l) containers; the runner can't reach Docker"
    fi
    if id "$RUNNER_USER" >/dev/null 2>&1; then
        local groups
        groups=$(id -nG "$RUNNER_USER")
        if [[ " $groups " =~ \ (sudo|wheel|docker|admin)\  ]]; then
            report MISSING "$RUNNER_USER groups" "$groups: must not be in sudo, wheel, admin or docker"
        else
            report OK "$RUNNER_USER account" "exists ($groups)"
        fi
    fi

    if [ "$missing" -gt 0 ]; then
        echo "$missing missing."
        return 1
    fi
    echo "Nothing missing."
}

# ---------------------------------------------------------------- install
install_packages() {
    if command -v apt-get >/dev/null; then
        # NEEDRESTART_SUSPEND: don't let needrestart restart the VPS's
        # services (Docker among them) after the install.
        apt-get update -q
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y -q \
            podman uidmap passt fuse-overlayfs dbus-user-session nftables e2fsprogs
    elif command -v dnf >/dev/null; then
        dnf -y install podman shadow-utils passt fuse-overlayfs nftables e2fsprogs
    else
        die "no apt-get or dnf: install podman, uidmap and passt by hand"
    fi
}

# A subordinate uid/gid range for rootless Podman: 65536 ids above every range
# already handed out.
add_subids() {
    local file=$1 flag=$2 start
    grep -q "^${RUNNER_USER}:" "$file" 2>/dev/null && return 0
    start=$(awk -F: 'BEGIN { m = 100000 } { e = $2 + $3; if (e > m) m = e } END { print m }' "$file" 2>/dev/null || echo 100000)
    usermod "$flag" "${start}-$((start + 65535))" "$RUNNER_USER"
}

# RUNNER_HOME on a disk of its own: a preallocated ext4 image file, mounted at
# boot. Builds can fill it, never the root disk the other services use.
setup_disk() {
    mountpoint -q "$RUNNER_HOME" && return 0
    if [ -d "$RUNNER_HOME" ] && [ -n "$(ls -A "$RUNNER_HOME")" ]; then
        die "$RUNNER_HOME has files but isn't a mount; move them away first"
    fi
    if [ ! -e "$disk_image" ]; then
        echo "Creating the runner's ${RUNNER_DISK_GB} GB disk, $disk_image"
        # Under another name until it is complete, so a re-run after an
        # interruption starts over.
        rm -f "$disk_image.new"
        fallocate -l "${RUNNER_DISK_GB}G" "$disk_image.new"
        chmod 0600 "$disk_image.new"
        # nodiscard: discarding would punch the reserved space back out.
        mkfs.ext4 -q -m 0 -E nodiscard -L atlas-runner "$disk_image.new"
        mv "$disk_image.new" "$disk_image"
    fi
    mkdir -p "$RUNNER_HOME"
    if ! awk -v d="$RUNNER_HOME" '$2 == d { found = 1 } END { exit !found }' /etc/fstab; then
        printf '%s %s ext4 loop,noatime,nofail 0 2\n' "$disk_image" "$RUNNER_HOME" >>/etc/fstab
    fi
    systemctl daemon-reload
    mount "$RUNNER_HOME"
    mountpoint -q "$RUNNER_HOME" || die "could not mount $disk_image at $RUNNER_HOME"
}

# Jobs run the repository's code with network access. Keep them off the VPS
# itself: the account may not connect to the host's own addresses (the
# services listening there, Docker's published ports) or to private networks
# (Docker's bridges, with the panel's and Forgejo's databases), except for DNS
# to systemd-resolved. Loaded at boot, before the account's systemd starts.
write_firewall() {
    local uid
    uid=$(uid_of)
    mkdir -p "$(dirname "$firewall")"
    cat >"$firewall" <<NFT
# Written by AtlasOS ci/vps-runner/setup.sh: the atlas-runner account
# (uid ${uid}) reaches the internet only.
table inet atlas_runner
delete table inet atlas_runner
table inet atlas_runner {
    chain output {
        type filter hook output priority 0; policy accept;
        meta skuid != ${uid} accept
        ct state { established, related } accept
        ip daddr 127.0.0.53 meta l4proto { tcp, udp } th dport 53 accept
        fib daddr type local counter reject
        ip daddr { 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } counter reject
        ip6 daddr { fc00::/7, fe80::/10 } counter reject
    }
}
NFT
    cat >/etc/systemd/system/atlas-runner-firewall.service <<UNIT
# Written by AtlasOS ci/vps-runner/setup.sh
[Unit]
Description=Firewall for the AtlasOS runner account
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target
# nftables.service starts with "flush ruleset", which would delete this
# table: load after it, and again whenever it reloads or restarts.
After=nftables.service
PartOf=nftables.service
ReloadPropagatedFrom=nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f ${firewall}
ExecReload=/usr/sbin/nft -f ${firewall}
ExecStop=-/usr/sbin/nft delete table inet atlas_runner

[Install]
WantedBy=multi-user.target
UNIT
    # The account's systemd, and so the runner, starts only with the firewall
    # loaded and its disk mounted.
    mkdir -p "/etc/systemd/system/user@${uid}.service.d"
    cat >"/etc/systemd/system/user@${uid}.service.d/50-atlas-runner.conf" <<UNIT
# Written by AtlasOS ci/vps-runner/setup.sh
[Unit]
Requires=atlas-runner-firewall.service
After=atlas-runner-firewall.service
RequiresMountsFor=${RUNNER_HOME}
UNIT
    systemctl daemon-reload
    systemctl enable atlas-runner-firewall.service
    # Reload, not restart: the account's systemd requires this unit, so a
    # restart would restart it too, and kill a running job.
    if systemctl is-active --quiet atlas-runner-firewall.service; then
        systemctl reload atlas-runner-firewall.service
    else
        systemctl start atlas-runner-firewall.service
    fi
}

write_runner_env() {
    [ -e "$runner_env" ] && return 0
    mkdir -p "$(dirname "$runner_env")"
    cat >"$runner_env" <<ENV
# Settings for the AtlasOS runner container, read at every start
# (sudo ci/vps-runner/setup.sh restart). setup.sh doesn't overwrite this file.
# Cleanup limits (cleanup.sh), in GB:
#ATLAS_RUNNER_MIN_FREE_GB=16
#ATLAS_RUNNER_BUILD_CACHE_GB=8
#ATLAS_RUNNER_DNF_CACHE_GB=3
ENV
    chmod 0644 "$runner_env"
}

install_image() {
    # A copy the runner account can read; the checkout may sit in a private home.
    rm -rf "$RUNNER_HOME/image-src"
    cp -r "$here" "$RUNNER_HOME/image-src"
    chown -R "$RUNNER_USER:" "$RUNNER_HOME/image-src"
    as_runner podman build --pull=newer -t "$image" "$RUNNER_HOME/image-src"
    # Images the previous builds of the runner image left untagged.
    as_runner podman image prune -f >/dev/null
}

write_units() {
    local uid
    uid=$(uid_of)

    # Limits on everything the account runs, set by root so the runner can't
    # lift them. CPU is a weight: the runner uses the whole machine when it is
    # idle and yields to the other services when they are busy. (An IO weight
    # would do nothing: the VPS's disk uses the "none" IO scheduler.)
    mkdir -p "/etc/systemd/system/user-${uid}.slice.d"
    cat >"/etc/systemd/system/user-${uid}.slice.d/50-atlas-runner.conf" <<EOF
# Written by AtlasOS ci/vps-runner/setup.sh
[Slice]
CPUWeight=${CPU_WEIGHT}
MemoryHigh=${MEMORY_HIGH}
MemoryMax=${MEMORY_MAX}
MemorySwapMax=${MEMORY_SWAP_MAX}
TasksMax=4096
EOF
    systemctl daemon-reload

    # Quadlet for the account's own systemd, kept where only root can edit it.
    mkdir -p "/etc/containers/systemd/users/${uid}"
    cat >"/etc/containers/systemd/users/${uid}/${unit}.container" <<EOF
# Written by AtlasOS ci/vps-runner/setup.sh
[Unit]
Description=GitHub Actions runner for ${RUNNER_REPO}
# (A user manager has no network-online.target. At boot the runner retries
# until the network is up.)

[Container]
Image=${image}
ContainerName=${unit}
Environment=ATLAS_RUNNER_REPO=${RUNNER_REPO}
EnvironmentFile=${runner_env}
# Rootless Podman inside the container (the AtlasOS build).
AddDevice=/dev/fuse
AddDevice=/dev/net/tun
SecurityLabelDisable=true
# A minimal init as PID 1, to reap what Podman inside leaves behind.
RunInit=true
# Kept between jobs: registration, checkouts, the dnf cache, Podman's image
# and layer cache, and /var/tmp, which holds Podman's build cache mounts (the
# Rust target cache).
Volume=${unit}-state:/state
Volume=${unit}-work:/work
Volume=${unit}-cache:/cache
Volume=${unit}-storage:/home/podman/.local/share/containers
Volume=${unit}-vartmp:/var/tmp

[Service]
Restart=always
RestartSec=30
# Exit 78: not registered yet. Don't retry until 'setup.sh register'.
RestartPreventExitStatus=78
# Let a running job finish its current step.
TimeoutStopSec=300

[Install]
WantedBy=default.target
EOF
    as_runner systemctl --user daemon-reload
}

install() {
    install_packages
    echo
    check || die "fix what is missing first"

    setup_disk
    if ! id "$RUNNER_USER" >/dev/null 2>&1; then
        # Its home is the new disk; no skeleton files.
        useradd --no-create-home --home-dir "$RUNNER_HOME" --shell /usr/sbin/nologin \
            --user-group --comment "AtlasOS GitHub Actions runner" "$RUNNER_USER"
    fi
    chown "$RUNNER_USER:" "$RUNNER_HOME"
    chmod 0750 "$RUNNER_HOME"
    add_subids /etc/subuid --add-subuids
    add_subids /etc/subgid --add-subgids

    # Before the account's systemd starts, which requires it.
    write_firewall
    write_runner_env
    # The account's systemd keeps running without a login.
    loginctl enable-linger "$RUNNER_USER"
    local uid
    uid=$(uid_of)
    for _ in $(seq 30); do
        [ -S "/run/user/$uid/bus" ] && break
        sleep 1
    done
    [ -S "/run/user/$uid/bus" ] || die "the systemd user manager for $RUNNER_USER did not start"

    as_runner podman system migrate
    install_image
    write_units

    echo "Self-test (rootless Podman in the runner container):"
    as_runner podman run --rm --security-opt label=disable \
        --device /dev/fuse --device /dev/net/tun \
        -v "${unit}-storage:/home/podman/.local/share/containers" \
        -v "${unit}-vartmp:/var/tmp" \
        "$image" selftest

    echo
    echo "Installed. Next: register it (README.md, step 3)."
}

# ---------------------------------------------------------------- register etc.
read_token() {
    if [ -z "${RUNNER_TOKEN:-}" ]; then
        [ -t 0 ] && echo "Paste the token, then press Enter:" >&2
        IFS= read -r RUNNER_TOKEN || true
    fi
    [ -n "$RUNNER_TOKEN" ] || die "no token on stdin"
    export RUNNER_TOKEN
}

register() {
    id "$RUNNER_USER" >/dev/null 2>&1 || die "run 'install' first"
    read_token
    as_runner systemctl --user stop "$unit" 2>/dev/null || true
    # The token goes in through the environment, never on a command line.
    as_runner podman run --rm --security-opt label=disable \
        -e RUNNER_TOKEN -e ATLAS_RUNNER_REPO="$RUNNER_REPO" \
        -v "${unit}-state:/state" "$image" register
    as_runner systemctl --user start "$unit"
    sleep 5
    status
}

unregister() {
    read_token
    as_runner systemctl --user stop "$unit" 2>/dev/null || true
    as_runner podman run --rm --security-opt label=disable \
        -e RUNNER_TOKEN -e ATLAS_RUNNER_REPO="$RUNNER_REPO" \
        -v "${unit}-state:/state" "$image" unregister
    echo "Unregistered and stopped. The account and its caches are still in $RUNNER_HOME."
}

# Wait for the runner's current job, if any, to finish (FORCE=1: don't).
wait_idle() {
    [ "${FORCE:-}" = 1 ] && return 0
    local said=false
    while as_runner podman exec "$unit" pgrep -f Runner.Worker >/dev/null 2>&1; do
        [ "$said" = true ] || echo "A job is running; waiting for it to finish (Ctrl-C to give up, FORCE=1 not to wait)."
        said=true
        sleep 20
    done
}

status() {
    as_runner systemctl --user --no-pager status "$unit" | head -5 || true
    df -h "$RUNNER_HOME" | tail -1
    if nft list table inet atlas_runner >/dev/null 2>&1; then
        echo "Firewall: loaded"
    else
        echo "Firewall: NOT LOADED; the runner can reach the VPS's services. Run: systemctl restart atlas-runner-firewall" >&2
    fi
    journalctl _SYSTEMD_USER_UNIT="$unit.service" --no-pager -n 15 || true
}

case ${1:-} in
check) check ;;
install) install ;;
register) register ;;
image) install_image && wait_idle && as_runner systemctl --user restart "$unit" ;;
status) status ;;
cache) as_runner podman exec --user podman "$unit" atlas-runner-cleanup list ;;
start) as_runner systemctl --user start "$unit" ;;
stop | restart) wait_idle && as_runner systemctl --user "$1" "$unit" ;;
clear-cache)
    wait_idle
    as_runner systemctl --user stop "$unit"
    as_runner podman volume rm --force "${unit}-storage" "${unit}-vartmp" "${unit}-cache" "${unit}-work"
    as_runner systemctl --user start "$unit"
    ;;
unregister) unregister ;;
*) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
