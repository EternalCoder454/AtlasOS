#!/usr/bin/env bash
# Usage: verify-image.sh REPO DIGEST
# Checks that REPO@DIGEST carries a signature made with cosign.pub (in the
# current directory) that names exactly this repository and this digest. The
# key is shared by atlasos and atlasos-nvidia, so a bare `cosign verify` would
# also accept one image's signature copied next to the other's. Every
# workflow that verifies an image uses this.
set -euo pipefail

repo=${1:?usage: verify-image.sh REPO DIGEST}
digest=${2:?usage: verify-image.sh REPO DIGEST}
[[ "$repo" =~ ^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)+$ ]] || { echo "bad repository '$repo'" >&2; exit 2; }
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "bad digest '$digest'" >&2; exit 2; }

# stdout is a JSON array with one payload per valid signature; the notes go
# to stderr.
out=$(cosign verify --insecure-ignore-tlog=true --key cosign.pub "${repo}@${digest}")
jq -e --arg repo "$repo" --arg digest "$digest" '
  type == "array" and length > 0 and
  all(.[]; .critical.identity."docker-reference" == $repo and
           .critical.image."docker-manifest-digest" == $digest)' <<<"$out" >/dev/null ||
  { echo "the signature on ${repo}@${digest} names a different repository or digest" >&2; exit 1; }
