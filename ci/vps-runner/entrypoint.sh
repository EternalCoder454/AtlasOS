#!/bin/bash
# Entry point of the runner container (see README.md here).
#   run         restore the registration from /state and run the runner (default)
#   register    register with GitHub; needs RUNNER_TOKEN (a registration token)
#   unregister  remove the registration; needs RUNNER_TOKEN (a removal token)
#   selftest    check that rootless Podman works in here the way the build needs
# Settings (from the Quadlet unit): ATLAS_RUNNER_REPO (owner/name),
# ATLAS_RUNNER_NAME (default atlasos-vps).
#
# It starts as container root, which is the unprivileged atlas-runner account
# on the host. Root keeps the registration in /state, where jobs (which run as
# "podman") can't change it, and copies it in at every start, so whatever a
# job does to the runner's files lasts only until the next restart.
set -euo pipefail

runner=/opt/actions-runner
state=/state
# What config.sh writes and the runner reads on every start.
files=(.runner .credentials .credentials_rsaparams .env .path)

[ "$(id -u)" = 0 ] || { echo "atlas-runner: start the container as root (it drops to podman)" >&2; exit 2; }

export HOME=/home/podman USER=podman LOGNAME=podman
as_podman() { setpriv --reuid=podman --regid=podman --init-groups "$@"; }

# Volumes the jobs write to belong to "podman"; /state stays root's.
for d in /work /cache /home/podman/.local/share/containers; do
    mkdir -p "$d"
    chown podman:podman "$d"
done
mkdir -p "$state"
chown root:root "$state"
chmod 0700 "$state"
chmod 1777 /var/tmp

restore() {
    [ -s "$state/.runner" ] || return 1
    for f in "${files[@]}"; do
        rm -f "${runner:?}/$f"
        if [ -e "$state/$f" ]; then
            install -o podman -g podman -m 0600 "$state/$f" "$runner/$f"
        fi
    done
}

cd "$runner"
case ${1:-run} in
run)
    if ! restore; then
        echo "Not registered yet: run 'setup.sh register' on the host." >&2
        # 78 (EX_CONFIG) stops systemd restarting it (RestartPreventExitStatus).
        exit 78
    fi
    exec setpriv --reuid=podman --regid=podman --init-groups ./run.sh
    ;;
register)
    : "${RUNNER_TOKEN:?RUNNER_TOKEN must hold a registration token}"
    : "${ATLAS_RUNNER_REPO:?ATLAS_RUNNER_REPO is not set}"
    rm -f "${files[@]}"
    # config.sh reads --token from ACTIONS_RUNNER_INPUT_TOKEN, which keeps the
    # token out of the process list.
    ACTIONS_RUNNER_INPUT_TOKEN=$RUNNER_TOKEN as_podman ./config.sh --unattended --replace \
        --url "https://github.com/${ATLAS_RUNNER_REPO}" \
        --name "${ATLAS_RUNNER_NAME:-atlasos-vps}" \
        --labels atlasos-vps \
        --work /work
    for f in "${files[@]}"; do
        if [ -e "$f" ]; then install -m 0600 "$f" "$state/$f"; fi
    done
    echo "Registered as ${ATLAS_RUNNER_NAME:-atlasos-vps}."
    ;;
unregister)
    : "${RUNNER_TOKEN:?RUNNER_TOKEN must hold a removal token}"
    restore || { echo "Not registered." >&2; exit 0; }
    ACTIONS_RUNNER_INPUT_TOKEN=$RUNNER_TOKEN as_podman ./config.sh remove
    for f in "${files[@]}"; do rm -f "$state/$f"; done
    ;;
selftest)
    # shellcheck disable=SC2016 # expanded by the inner shell
    as_podman /bin/bash -euo pipefail -c '
        img=registry.fedoraproject.org/fedora-minimal:44
        graphroot=$(podman info --format "{{.Store.GraphRoot}}")
        echo "Podman storage: $graphroot ($(podman info --format "{{.Store.GraphDriverName}}"))"
        podman pull -q "$img" >/dev/null
        # A build with a network RUN and a cache mount, as the Containerfile does.
        printf "FROM %s\nRUN --mount=type=cache,target=/c curl -fsS -o /c/probe https://github.com/ && echo network-ok\n" "$img" |
            podman build --no-cache -t localhost/atlas-selftest -f - /var/tmp
        # A privileged container with the storage bound in, as `just rechunk` does.
        podman run --rm --privileged \
            --mount=type=image,src=localhost/atlas-selftest,target=/img \
            --mount=type=bind,src="$graphroot",target=/run/host-container-storage,rw \
            "$img" sh -c "test -d /img/usr && test -d /run/host-container-storage/overlay && mount -t tmpfs none /mnt && echo privileged-ok"
        podman rmi -f localhost/atlas-selftest "$img" >/dev/null
        echo "Self-test passed."'
    ;;
*)
    echo "usage: atlas-runner [run|register|unregister|selftest]" >&2
    exit 2
    ;;
esac
