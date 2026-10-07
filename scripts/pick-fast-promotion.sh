#!/usr/bin/env bash
# Usage: pick-fast-promotion.sh <repo>   e.g. ghcr.io/eternalcoder454/telamonos
#
# For promote-stable.yml's days between the weekly promotions: picks the
# newest per-build testing image (tag testing-44.YYYYMMDD-N) that
#   - has been in testing for at least MIN_AGE_HOURS (default 24), by its
#     org.telamon.built label (org.atlasos.built on images built before the
#     rename; the image's Created time is the commit's, not
#     the build's), so every stable build soaked in testing a day; an image
#     without that label counts as too young;
#   - carries a newer kernel (label ostree.linux) than :stable, not an older
#     one (Brave, the other component once, is no longer in the image);
#   - has a version label that sorts after :stable's, so :stable never moves
#     backwards;
#   - was built from the commit :stable was built from or a descendant of it
#     (org.opencontainers.image.revision, git merge-base --is-ancestor), so a
#     revert of the repo's own commits is never promoted. A candidate that
#     fails this is passed over, like one failing verification.
# A kernel label missing on stable says nothing, so it never triggers; one
# missing on the candidate while stable has one stops the pick (it can't be
# shown not to roll that back). Stable without a usable revision
# label is an error (fail closed), and so is a stable commit that is not in
# the checkout (history rewritten). No :stable at all finds nothing.
#
# Prints key=value lines (values are validated, one line each):
#   found=false / why=...                      nothing to promote
#   found=true / digest / version / reason     the pick
# Everything is read by digest; nothing is written. Verification, the
# ancestor check and the copy are the promotion's own steps, not done here.
# A candidate that is otherwise eligible must also pass verify-image.sh
# (cosign.pub in the current directory), so a forged tag is passed over
# rather than chosen and then failing the run; the promotion verifies again.
# Needs git and a checkout with full history (cosign.pub is read from it too)
# as the current directory.
# Env: SKOPEO_CREDS=user:token (optional; CI sets REGISTRY_AUTH_FILE
# instead, which skopeo reads by itself), MIN_AGE_HOURS, MAX_TAGS (40),
# NOW (epoch seconds, for tests), PICK_SKIP_VERIFY=1 (stub tests only).
set -euo pipefail

repo=${1:?usage: pick-fast-promotion.sh <repo>}
min_age=${MIN_AGE_HOURS:-24}
max_tags=${MAX_TAGS:-40}
now=${NOW:-$(date -u +%s)}
[[ "$min_age" =~ ^[0-9]+$ && "$max_tags" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] ||
  { echo "bad MIN_AGE_HOURS, MAX_TAGS or NOW" >&2; exit 2; }
creds=()
[ -z "${SKOPEO_CREDS:-}" ] || creds=(--creds "$SKOPEO_CREDS")

sk() { skopeo inspect --retry-times 3 "${creds[@]}" "$@"; }
none() { echo "found=false"; echo "why=$*"; exit 0; }
# label KEY JSON: the label's value, or "" when it's missing or isn't a plain
# version-like string. Registry labels end up in log lines and step summaries
# (why=...), so nothing else gets through.
label() {
  local v
  v=$(jq -r --arg k "$1" '.Labels[$k] // ""' <<<"$2")
  [[ "$v" =~ ^[A-Za-z0-9._+-]{1,80}$ ]] && printf '%s' "$v" || true
}
# newer A B: both set, different, and A sorts after B.
newer() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }

serr=$(mktemp)
trap 'rm -f "$serr"' EXIT
if ! sdigest=$(sk --format '{{.Digest}}' "docker://${repo}:stable" 2>"$serr"); then
  # No :stable at all (first promotion): nothing to compare with, so no
  # fast promotion; the weekly one makes the first. Only skopeo's own
  # "manifest unknown" / "name unknown" for that tag counts; any other
  # error stops.
  if grep -qiE 'reading manifest stable in [^ ]+: (manifest|name) unknown' "$serr"; then
    none "${repo} has no :stable yet; the weekly promotion makes the first"
  fi
  cat "$serr" >&2
  echo "can't read ${repo}:stable" >&2
  exit 1
fi
[[ "$sdigest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "bad stable digest '$sdigest'" >&2; exit 1; }
sjson=$(sk "docker://${repo}@${sdigest}")
s_ver=$(label org.opencontainers.image.version "$sjson")
s_kernel=$(label ostree.linux "$sjson")
s_rev=$(label org.opencontainers.image.revision "$sjson")
[[ "$s_ver" =~ ^44\.[0-9]{8}(-[0-9]+)?$ ]] || { echo "stable has no usable version label '$s_ver'" >&2; exit 1; }
[[ "$s_rev" =~ ^[0-9a-f]{40}$ ]] ||
  { echo "stable has no usable revision label '$s_rev'; can't check that a candidate descends from it, so not promoting." >&2; exit 1; }

# Stable's commit has to be in this checkout, or no descent can be checked
# (git's own "not an ancestor" and "no such commit" must not look alike).
git cat-file -e "${s_rev}^{commit}" 2>/dev/null || {
  echo "stable's commit ${s_rev} is not in main's history (rewritten or force-pushed?); not promoting. See CI.md." >&2
  exit 1
}

tags=$(skopeo list-tags --retry-times 3 "${creds[@]}" "docker://${repo}") || { echo "can't list ${repo}'s tags" >&2; exit 1; }
# A tag dated after today is bogus (anyone who can push could add one that
# sorts first forever); it's left out.
today=$(date -u -d "@$now" +%Y%m%d)
versions=$(jq -r '.Tags[]?' <<<"$tags" |
  sed -n 's/^testing-\(44\.[0-9]\{8\}-[0-9]\{1,4\}\)$/\1/p' |
  awk -v t="$today" '{ split($0, a, /[.-]/); if (a[2] <= t) print }' |
  sort -rV | head -n "$max_tags")

young=0
unverified=0
regressed=0
cand=""
for v in $versions; do
  # Newest first: from here on nothing is newer than what stable has.
  newer "$v" "$s_ver" || break
  d=$(sk --format '{{.Digest}}' "docker://${repo}:testing-${v}") || continue
  [[ "$d" =~ ^sha256:[0-9a-f]{64}$ ]] || continue
  json=$(sk "docker://${repo}@${d}") || continue
  if [ "$(label org.opencontainers.image.version "$json")" != "$v" ]; then
    echo "testing-${v} has another version label; skipped." >&2
    continue
  fi
  built=$(label org.telamon.built "$json")
  [ -n "$built" ] || built=$(label org.atlasos.built "$json")
  if ! [[ "$built" =~ ^[0-9]{10}$ ]] || [ $((now - built)) -lt $((min_age * 3600)) ]; then
    young=$((young + 1))
    continue
  fi
  # Built from stable's commit or a descendant of it, never an older one.
  # (Whether the commit is on main is not asked here: only pushes of main
  # make testing-* tags, build.yml's Decide step. The promotion checks it.)
  c_rev=$(label org.opencontainers.image.revision "$json")
  if [[ "$c_rev" =~ ^[0-9a-f]{40}$ ]] && ! git cat-file -e "${c_rev}^{commit}" 2>/dev/null; then
    echo "testing-${v}'s commit ${c_rev} is not in this checkout's history; skipped." >&2
    regressed=$((regressed + 1))
    continue
  fi
  if ! [[ "$c_rev" =~ ^[0-9a-f]{40}$ ]] ||
    { [ "$c_rev" != "$s_rev" ] && ! git merge-base --is-ancestor "$s_rev" "$c_rev"; }; then
    echo "testing-${v} was not built from stable's commit or a descendant of it; skipped." >&2
    regressed=$((regressed + 1))
    continue
  fi
  # Its own messages go to the log: a registry or network error must not
  # pass for a forged tag.
  # Tried twice, so a network blip doesn't pass over a good build.
  if [ "${PICK_SKIP_VERIFY:-}" != 1 ] &&
    ! "$(dirname "$0")/verify-image.sh" "$repo" "$d" >/dev/null &&
    ! { sleep 10; "$(dirname "$0")/verify-image.sh" "$repo" "$d" >/dev/null; }; then
    echo "testing-${v} (${d}) does not verify against cosign.pub (see above); skipped." >&2
    unverified=$((unverified + 1))
    continue
  fi
  cand=$v
  c_digest=$d
  c_kernel=$(label ostree.linux "$json")
  break
done

[ -n "$cand" ] || none "no testing build newer than stable ${s_ver} has been in testing for ${min_age} hours (${young} newer but younger, ${unverified} failing verification, ${regressed} not descending from stable's commit)"

# Never backwards.
if [ -n "$s_kernel" ] && [ -z "$c_kernel" ]; then
  none "${cand} has no kernel label and stable ${s_ver} has one; not promoting"
fi
if newer "$s_kernel" "$c_kernel"; then
  none "${cand} has an older kernel than stable ${s_ver}; not promoting"
fi
reason=""
if newer "$c_kernel" "$s_kernel"; then
  reason="kernel ${c_kernel%.x86_64}"
fi
[ -n "$reason" ] || none "${cand} has the same kernel (${c_kernel:-unknown}) as stable ${s_ver}; left for the weekly promotion"
[[ "$reason" =~ ^[A-Za-z0-9._\ :+-]+$ ]] || { echo "unexpected characters in '$reason'" >&2; exit 1; }

echo "found=true"
echo "digest=${c_digest}"
echo "version=${cand}"
echo "reason=Security update, promoted early after ${min_age} hours in testing: ${reason}"
