#!/bin/bash
# Runs inside the image's container (run.sh): the registry is on 127.0.0.1:$PORT.
set -uo pipefail
fail=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
expect_ok() { # WHAT CMD...
	local what=$1
	shift
	if out=$("$@" 2>&1); then ok "$what"; else bad "$what: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi
}
expect_refused() { # WHAT CMD...
	local what=$1
	shift
	if out=$("$@" 2>&1); then bad "$what: it was accepted"; else ok "$what ($(echo "$out" | grep -o -i -E 'signature[^"]{0,60}|no signatures[^"]{0,40}' | head -1))"; fi
}

policy=/etc/containers/policy.json
key=/etc/pki/containers/telamon.pub
phase_files() {
echo "== 1. the image's own files"
[ "$(stat -c '%a %U' $policy)" = "644 root" ] && ok "policy.json is 0644 root" || bad "policy.json: $(stat -c '%a %U' $policy)"
[ "$(stat -c '%a %U' $key)" = "644 root" ] && ok "the key is 0644 root" || bad "key: $(stat -c '%a %U' $key)"
cmp -s $key /repo/cosign.pub && ok "the installed key is the repository's cosign.pub" || bad "the installed key differs from cosign.pub"
jq -e '.default == [{"type":"reject"}]' $policy >/dev/null && ok "the default is reject" || bad "the default is not reject"
for n in telamonos telamonos-nvidia atlasos atlasos-nvidia; do
	jq -e --arg s "ghcr.io/eternalcoder454/$n" '.transports.docker[$s] == [{"type":"sigstoreSigned","keyPaths":["/etc/pki/containers/telamon.pub"],"signedIdentity":{"type":"matchRepository"}}]' $policy >/dev/null &&
		ok "ghcr.io/eternalcoder454/$n needs a sigstore signature from the project key (matchRepository)" || bad "the scope for $n is wrong"
done
# only these scopes demand a signature, and only the "" scope of each
# transport accepts anything
jq -e '[.transports.docker | to_entries[] | select(.value[0].type == "sigstoreSigned") | .key] | length == 4' $policy >/dev/null && ok "exactly four docker scopes demand a signature" || bad "the number of signed scopes changed"
jq -e '[.transports[] | to_entries[] | select(.value[0].type == "insecureAcceptAnything") | .key] | all(. == "")' $policy >/dev/null && ok "insecureAcceptAnything is only ever the empty (catch-all) scope" || bad "insecureAcceptAnything on a named scope"
grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/telamon.yaml && grep -q 'ghcr.io/eternalcoder454:' /etc/containers/registries.d/telamon.yaml &&
	ok "registries.d reads the signatures from the registry for ghcr.io/eternalcoder454" || bad "registries.d does not enable sigstore attachments"
jq -e '.transports.docker."ghcr.io/eternalcoder454/telamonos" | .[0].keyPaths | length == 1' $policy >/dev/null && ok "one key is trusted (a rotation adds a second beside it first, see DEV.md)" || bad "more than one key trusted"

}

R=127.0.0.1:$PORT
base=docker.io/library/alpine:3.24
mkdir -p /tmp/reg.d
printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$R" >/tmp/reg.d/test.yaml
mkpolicy() { # KEYFILE OUT: the image's policy, its ghcr.io/eternalcoder454 scopes moved to the local registry
	jq --arg r "$R" --arg k "$1" '
		.transports.docker |= with_entries(
			if (.key | startswith("ghcr.io/eternalcoder454/")) then
				.key |= sub("^ghcr.io/"; ($r + "/")) |
				(.value[0].keyPaths // empty) |= [$k]
			else . end)' $policy >"$2"
}
mkpolicy /k/a.pub /tmp/policy-a.json
mkpolicy /k/b.pub /tmp/policy-b.json
pull() { # POLICY IMAGE
	rm -rf /tmp/out
	skopeo --policy "$1" --registries.d /tmp/reg.d copy --src-tls-verify=false "docker://$2" dir:/tmp/out
}
push() { # [skopeo options] DEST
	skopeo --insecure-policy copy --dest-tls-verify=false "$@" >/dev/null 2>&1
}

phase_push() {
	push "docker://$base" "docker://$R/eternalcoder454/telamonos:testing" &&
		push "docker://$base" "docker://$R/eternalcoder454/telamonos-nvidia:testing" &&
		push "docker://$base" "docker://$R/elsewhere/tool:1" || { echo "  FAIL could not push the test images"; exit 1; }
	skopeo inspect --tls-verify=false "docker://$R/eternalcoder454/telamonos:testing" | jq -r .Digest >/k/digest
}

phase_unsigned() {
	echo "== 2. the image's policy against a local registry: nothing signed yet"
	jq -e --arg r "$R" '.transports.docker | has($r + "/eternalcoder454/telamonos")' /tmp/policy-a.json >/dev/null && ok "the test policy has the local telamonos scope" || bad "the test policy was not made"
	digest=$(cat /k/digest)
	expect_refused "an unsigned telamonos is refused" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos:testing"
	expect_refused "an unsigned telamonos-nvidia is refused" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos-nvidia:testing"
	expect_refused "an unsigned image by digest is refused" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos@$digest"
	expect_ok "a repository the policy does not name is accepted (an administrator's own image)" pull /tmp/policy-a.json "$R/elsewhere/tool:1"
}

phase_signed() {
	echo "== 3. signed with the project's key (a); b is another key"
	digest=$(cat /k/digest)
	expect_ok "telamonos signed with a is accepted under a policy that trusts a" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos:testing"
	expect_ok "and by digest" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos@$digest"
	expect_refused "telamonos signed with a is refused under a policy that trusts only b" pull /tmp/policy-b.json "$R/eternalcoder454/telamonos:testing"
	expect_refused "the signed image's sibling telamonos-nvidia (unsigned) is still refused" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos-nvidia:testing"
	# the tag moves to a build nobody signed (a registry compromise, a stolen
	# push token): the signature belongs to the old digest
	push --override-arch arm64 --override-os linux "docker://$base" "docker://$R/eternalcoder454/telamonos:testing"
	new=$(skopeo inspect --tls-verify=false "docker://$R/eternalcoder454/telamonos:testing" | jq -r .Digest)
	[ "$new" != "$digest" ] && ok "the tag now points to another build" || bad "the tag did not move"
	expect_refused "a tag moved to an unsigned build is refused" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos:testing"
	expect_ok "while the old, signed build is still accepted by digest" pull /tmp/policy-a.json "$R/eternalcoder454/telamonos@$digest"
}

case ${1:-} in
files) phase_files ;;
push) phase_push ;;
unsigned) phase_unsigned ;;
signed) phase_signed ;;
esac
exit "$fail"
