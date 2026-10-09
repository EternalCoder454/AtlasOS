#!/bin/sh
# Tests that Telamon OS images are only accepted with a signature from the
# project key, the way an update (bootc, rpm-ostree, podman, skopeo: all use
# /etc/containers/policy.json) checks them.
#
#   1. The published image's real policy.json, key and registries.d are
#      checked as files.
#   2. The same policy, with its ghcr.io/eternalcoder454 scopes moved to a
#      throwaway local registry, is used to pull from that registry: an unsigned
#      image of a scoped repository is refused; one signed with the policy's
#      key is accepted; one signed with another key is refused; a tag that moved
#      to an unsigned build is refused; a repository the policy does not name is
#      accepted (by design: an administrator may run any image).
#
# Needs podman, a network for the first run (alpine, registry:3 and cosign are
# pulled), no root. The keys are made here and thrown away.
#
#   tests/signing/run.sh [IMAGE]    (default: the published testing image)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
cosign=ghcr.io/sigstore/cosign/cosign:v3.1.2
registry=docker.io/library/registry:3
work=$(mktemp -d "${TMPDIR:-/tmp}/signing.XXXXXX")
port=$((20000 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 20000))
name=telamon-signing-reg-$$
cleanup() {
	podman rm -f "$name" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT

run() { podman run --rm --ulimit core=0 --security-opt label=disable --network=host "$@"; }

podman run -d --rm --name "$name" --ulimit core=0 --network=host \
	-e REGISTRY_HTTP_ADDR="127.0.0.1:$port" "$registry" >/dev/null
for _ in $(seq 50); do
	curl -fsS "http://127.0.0.1:$port/v2/" >/dev/null 2>&1 && break
	sleep 0.2
done

# two throwaway key pairs
for k in a b; do
	run --user 0:0 -w /k -v "$work:/k" -e COSIGN_PASSWORD= "$cosign" generate-key-pair --output-key-prefix "$k" >/dev/null
done

inner() { run -v "$repo:/repo:ro" -v "$work:/k" -e PORT="$port" "$image" bash /repo/tests/signing/inner.sh "$@"; }
fail=0
inner files || fail=1
inner push || exit 1
inner unsigned || fail=1
digest=$(cat "$work/digest")
# sign what is in the registry with key A, the way CI signs (cosign, legacy
# sigstore attachment)
run --user 0:0 -w /k -v "$work:/k" -e COSIGN_PASSWORD= "$cosign" sign -y --new-bundle-format=false \
	--use-signing-config=false --tlog-upload=false --key /k/a.key \
	"127.0.0.1:$port/eternalcoder454/telamonos@$digest" >/dev/null 2>&1 || { echo "  FAIL cosign could not sign the test image"; exit 1; }
inner signed || fail=1
echo
if [ "$fail" = 0 ]; then echo "PASS: tests/signing"; else echo "FAIL: tests/signing"; fi
exit "$fail"
