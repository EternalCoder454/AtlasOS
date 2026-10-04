# CI: where AtlasOS builds, and how long it takes

## Where builds run

`build.yml` starts with a small job, "Pick a runner", on GitHub's runners. It
sends the build to one of two places:

| Event | Runner |
|---|---|
| Push to `main` | VPS, if online |
| Daily schedule (builds `main`) | VPS, if online |
| Manual run on `main` | VPS, if online |
| Tag push (build and lint, nothing published) | VPS, if online |
| Pull request | GitHub-hosted, always |
| Push to `beta`, manual run on another branch | GitHub-hosted |

"VPS" is the self-hosted runner labelled `atlasos-vps` on `eterneon-vps`;
[ci/vps-runner](ci/vps-runner/README.md) sets it up. The build job names
the runner it got: "Build and push (vps)" or "Build and push (hosted)".

`promote-stable.yml` (the stable release, weekly plus a security fast path, see
below) stays on GitHub's runners. It
builds nothing: skopeo copies the newest `testing` image to `stable` by
digest, so it has nothing to cache. Then it calls `iso.yml` for each image
it promoted, which builds the live installer ISO on GitHub's runners (the VPS
runner's firewall keeps it off the VPS itself) and uploads it to
https://atlasos.eterneon.net/; [ci/iso-hosting](ci/iso-hosting/README.md)
covers that side.

### Fallback

The pick job asks GitHub for the state of runners labelled `atlasos-vps`,
using the `RUNNER_STATUS_TOKEN` secret (a fine-grained token for this
repository with Administration: read-only). GitHub-hosted runners build when:

- the VPS runner is offline (stopped, rebooting, unregistered, too old a version),
- the secret is missing, or the status can't be read (a notice or warning says so).

A runner that is online but busy keeps the job: it waits its turn there.

Not covered: if the VPS goes offline after the pick, the job waits in the
queue (up to 24 hours) for it to come back. Cancel it and re-run; the re-run
picks GitHub's runners.

### Only trusted code on the VPS

The repository is public, and a pull request from a fork runs the workflow
from the pull request, so it could ask for the VPS runner by label. Before
every job the runner's own hook (part of its image, not of this repository)
refuses anything that isn't a push, schedule or manual run of this repository
on `main` or a tag. Fork pull requests should also need approval: Settings,
Actions, General, "Require approval for all external contributors".

A tag runs the workflow as the tag has it, with the repository's secrets, on
the VPS. Only people who can push to `main` anyway can push tags, so that
trusts no one new; keep it in mind before giving anyone else write access.

On the VPS, jobs run as an unprivileged account in a container, on a 50 GB
disk of their own, with limits on memory and CPU, and a firewall that keeps
them off the VPS's other services (see
[ci/vps-runner](ci/vps-runner/README.md#how-it-is-put-together)).

### Security fast path

A Brave or kernel fix should not wait for Saturday. Two parts:

- **The build notices Brave.** The daily scheduled build skips only when
  nothing changed; Decide now also reads the newest `brave-origin` in Brave's
  RPM repo (`scripts/brave-version.sh`, a trigger only, the build verifies
  signatures through dnf) and rebuilds when it differs from the published
  image's `org.atlasos.brave.version` label. The label is set after the build
  from the version installed in the image, so it is what the image holds. If
  Brave's repo can't be read, the run builds rather than skips. A kernel
  update arrives with the Kinoite base, whose digest already triggers a build.
- **Promotion runs daily (14:30 UTC).** On Saturday and for a manual run it is
  the weekly promotion above. Any other day `scripts/pick-fast-promotion.sh`
  picks the newest `testing-44.YYYYMMDD-N` build that (1) was built at least
  24 hours ago, so it soaked in testing for a day, (2) has a newer
  `ostree.linux` (kernel) or `org.atlasos.brave.version` than `:stable` and an
  older one of neither, and (3) has a version label after `:stable`'s, so
  `:stable` never moves backwards. If none qualifies the run ends cleanly and
  its summary says why. A pick then goes through the same verification
  (cosign, ancestor of `main`, tag checks), copy and release steps as the
  weekly run, and its release notes start with the reason ("Security update
  ... kernel X and Brave Y"). The NVIDIA image of the same version is promoted
  from its own `testing-<version>` tag. No ISOs on a fast promotion: they stay
  weekly, and an existing install updates to `:stable` itself.
- **Details of the pick.** Build time is the signed `org.atlasos.built` label
  (epoch seconds, set next to the Brave label), not the image's `Created`,
  which is the commit's time (`SOURCE_DATE_EPOCH` in rechunk) and can be days
  old for a scheduled rebuild. Images built before the label existed count as
  too young, so the fast path only starts with builds that have it. Labels are
  checked to be short plain strings before they reach a message. Tags dated
  after today are ignored. A candidate without a Brave label is refused when
  `:stable` has one. The pick is the newest build that has soaked, even when
  a newer, younger build exists: that one gets its own turn a day later, or
  on Saturday. Each candidate is checked with `verify-image.sh` already
  while picking, so a forged tag is passed over, with cosign's message in
  the log.
- **When a fast promotion half fails.** If NVIDIA's `testing-<version>` is
  missing the NVIDIA job fails (a security update must not skip NVIDIA
  users). Nothing needs doing by hand: on a day with nothing new for
  atlasos, the workflow sees NVIDIA's `:stable` is older than atlasos's and
  runs only the NVIDIA job, for atlasos's current stable version, from
  `testing-<that version>` and with the same checks. A re-run of the failed
  run does the same, and fails the same way until that build exists. (Don't
  start it by hand with "Run workflow" for this: that is the weekly
  promotion of `:testing`, which fails if NVIDIA's `:testing` has moved on.)
  If the copy worked but the release job failed, the next day's pick sees
  `:stable` already there and does nothing. Run the workflow by hand: that is
  the weekly promotion of the current `:testing`. While `:testing` is still
  that build it skips the copy and makes the tag and release; if `:testing`
  has moved on, it promotes the newer build, with its own release, and the
  half-done one gets no release of its own.
- **Stable never goes backwards.** Both modes read `:stable`'s
  `org.opencontainers.image.revision` and promote only a build of that
  commit or a later one on main (`git merge-base --is-ancestor`); weekly
  also needs a version at or after stable's. So a re-run of an old build, or
  an old image tagged `:testing`, is refused. If main's history is ever
  rewritten so stable's commit is no longer on it, or `:stable` has no
  revision label, promotion stops until you fix it by hand (build from main,
  check the image, and copy it to `:stable` yourself): both the weekly and
  the fast run fail with "stable's commit ... is not in main's history".
  Only skopeo's "reading manifest stable in ...: manifest unknown" (or "name
  unknown") counts as "no `:stable` yet"; any other registry error stops
  the run.

### What gets promoted, and what goes into an ISO

Only the build workflow signs, and only for pushes of `main` and `beta` (beta
builds are signed too). promote-stable.yml never
signs: it checks that the `:testing` digest verifies against `cosign.pub`, with
`scripts/verify-image.sh`, which also requires the signature to name that
repository and digest (atlasos and atlasos-nvidia share the key, so a copied
signature must not pass), and
that its `org.opencontainers.image.revision` is an ancestor of `main`, and
otherwise stops without moving a tag. It verifies `:stable` afterwards even
when nothing was copied, so an unsigned `:stable` fails the run; the next
promotion of a signed `:testing` fixes it. The release tag only moves to a
commit on `main`. iso.yml verifies the stable digest the same way before
building, checks the version tag it builds from is that digest, and records
the image digest and the installer commit it checked out in `<image>.json`
and the job summary. It also checks that what make-iso.sh pinned (the
`.image` file beside the ISO) is that digest, and refuses to upload when
`installer_ref` is not `main`. promote-stable.yml hands iso.yml only the two upload
secrets.

Recommended in Settings, which no workflow can do:
- Pending (owner step): `SIGNING_SECRET` is still a repository secret, so any
  branch's workflow can read it. Move it, and `COSIGN_PASSWORD`, into an
  Environment named `signing` whose deployment branches are `main` and `beta`
  only, protect the `beta` branch (no force pushes, no deletion, pull
  requests or restricted pushes), and then add `environment: signing` to the
  build.yml jobs that sign (and nothing else).
- Put `ISO_UPLOAD_KEY` and `ISO_UPLOAD_KNOWN_HOSTS` in a GitHub Environment
  limited to the `main` branch, and name it in the jobs that use them.
- Make `ATLAS_FRAMEWORK_TOKEN` and `ATLAS_UPDATER_TOKEN` fine-grained tokens
  with read-only Contents access to just their repository, with an expiry.

## SBOM and vulnerability gate

Before the push, each image (atlasos, and atlasos-nvidia when it is built) is
scanned: syft makes an SPDX SBOM of its packages, grype
matches it against its vulnerability database. A **Critical with a fix
available** (`--only-fixed --fail-on critical`) fails the build, so such an
image never reaches `:testing` or `:beta`. Pull requests are scanned too.
Both tools run from the container images pinned by digest in the Justfile
(`just sbom`); the gate is the same SBOM matched again with `.grype.yaml`.

- grype has no Fedora data, so it covers the Go and Python modules built into
  programs, not the RPMs. Fedora's updates fix those; the daily build takes them.
- The database (about 1 GB) is downloaded on every scan, with 3 tries. If it
  can't be, the build fails rather than push unchecked. The scan takes about
  3 minutes per image (syft 1m45, grype 1m15 on the dev machine), twice the
  grype time with the gate's own run.
- The SBOM must list at least 1,000 RPMs and 100 Go modules (the image has
  about 1,900 and 1,000), or the build fails: "nothing found" must not be
  "nothing scanned".
- `.grype.yaml` lists ignored findings, one line each, naming the
  vulnerability and the package's exact name, version and type (another copy
  or version still fails), ending in `# until YYYY-MM-DD: reason`, at most 90
  days ahead. `scripts/grype-ignores.sh` checks every line and leaves out
  entries whose date has passed (the log names them); any other layout is an
  error. To release a blocked build, update the package, or add an entry with
  a short expiry. An expired entry blocks every build, Brave's updates
  included, until it is extended or removed.
- The gate runs only when a build does: a new Critical against an unchanged
  image, or an expired entry, shows at the next build, not before.
- The scan is of the image as built (`localhost/atlasos:<tag>`, and
  `localhost/atlasos-nvidia:<tag>`); the pushed atlasos is its rechunked copy,
  the same files with `/sysroot` pruned.
- atlasos-nvidia is built, and so scanned, after atlasos is pushed (it builds
  on it). A Critical only in the NVIDIA image (its Go tools) fails the job with
  atlasos already published and atlasos-nvidia a build behind until fixed.
- The attestation is tried 3 times: the image is already pushed, and a rerun
  of the same commit skips the build, so a failure there leaves that digest
  without an attestation (it stays signed).
- The SBOM and the full report are the run's `sbom-<tag>` (and
  `sbom-nvidia-<tag>`) artifacts, and the findings are in the job summary. For a
  signed image the SBOM is also attested on the registry with the signing key,
  and the step checks that the attestation names that image's digest (the two
  images share the key): `cosign verify-attestation --type spdxjson
  --insecure-ignore-tlog=true --key cosign.pub <image>@<digest>`.

## Caches on the VPS

GitHub's runners start empty every time; their only cache is dnf's downloads
(`actions/cache`, keyed by ISO week). The VPS keeps, between builds:

| What | Where (runner container) | Saves |
|---|---|---|
| Podman's images and layers | `/home/podman/.local/share/containers` | Pulling Kinoite and Fedora (about 4 GB); every Containerfile stage and step whose inputs didn't change: branding, the Atlas apps' RPMs, KIO, plasma-setup, and the image's own steps (see below) |
| Rust build cache | `/var/tmp` (Podman's `RUN --mount=type=cache`, `ATLAS_BUILD_CACHE`) | Crates and their build output: when Atlas Updater changes, its dependencies come from the cache and only its own crates and app recompile (the checkout gives every source file a new time) |
| dnf's downloads | `/cache/dnf` (`ATLAS_DNF_CACHE`) | Fedora packages for the build |

The image itself is built in steps (Containerfile, last stage), each rerun
only when its inputs change, and everything after it with it:

| Step | Reruns when |
|---|---|
| `packages.sh`: packages, KIO, wizard, greenboot | New Kinoite, the script, KIO or plasma-setup changed, or a new day (`PACKAGES_DATE`, so Brave's and Fedora's updates arrive daily) |
| `apps.sh`: the Atlas apps | Atlas Updater changed |
| `build.sh`: services, settings, branding, initramfs | `system_files`, branding or the script changed |
| `version.sh`: the version in os-release | Every build (a few seconds) |

So the first push of a day reinstalls the packages; later pushes that day
only redo what they changed.

The Rust cache needs `packaging/build-rpm.sh` with `ATLAS_BUILD_CACHE`
support in atlasos-updater; with an older one the build still works, uncached.

The runner has a 50 GB disk; a build from empty caches peaks at about 30 GB
over the runner's own 12, and a build that reuses them needs much less. After every job (and before the next) its
cleanup removes the images the build made, which are in the registry by
then, and base images a newer pull replaced, with the build steps cached on
them. It clears the Rust cache past 8 GB and dnf's past 3 GB, and when less
than 16 GB is free (what a build needs) it gives up more, cheapest first:
the Rust cache, dnf's downloads, every image.
[ci/vps-runner](ci/vps-runner/README.md#disk) has the details.

## Build times

`scripts/ci-times.sh [runs]` prints these tables from the GitHub API (the last
40 successful runs by default). Re-run it and paste the output here.

"Build step" is `just build`; "Rechunk" and "Push" only run when an image is
published; pull requests and tags ("build only") skip them.

### Measured

As of 2026-10-03. GitHub-hosted runners are ubuntu-26.04 (4 CPUs, 16 GB);
the VPS has 4 CPUs and 7.6 GB. The medians mix very different VPS runs (see
below the tables), so read the runs themselves.

| Runner | Image | Work | Jobs | Job (median) | Build step | Rechunk | Push |
|---|---|---|---:|---:|---:|---:|---:|
| GitHub-hosted | atlasos | build + publish | 6 | 22m 34s | 13m 54s | 5m 57s | 1m 9s |
| VPS | atlasos | build + publish | 4 | 35m 19s | 25m 47s | 8m 10s | 2m 21s |
| GitHub-hosted | atlasos | build only | 3 | 31m 0s | 29m 41s | – | – |
| GitHub-hosted | atlasos-nvidia | build + publish | 2 | 14m 55s | 6m 16s | 6m 35s | 0m 56s |
| VPS | atlasos-nvidia | build + publish | 4 | 16m 17s | 5m 59s | 8m 48s | 1m 45s |

| Date | Run | Runner | Image | Job | Build step | Rechunk | Push |
|---|---|---|---|---:|---:|---:|---:|
| 2026-10-03 | 37136001901 | VPS | atlasos-nvidia | 6m 39s | 1m 53s | 1m 58s | 2m 48s |
| 2026-10-03 | 37136001901 | VPS | atlasos | 6m 28s | 0m 12s | 2m 6s | 3m 57s |
| 2026-10-03 | 37130390547 | VPS | atlasos-nvidia | 11m 42s | 1m 52s | 9m 7s | 0m 43s |
| 2026-10-03 | 37130390547 | VPS | atlasos | 20m 16s | 10m 52s | 8m 27s | 0m 45s |
| 2026-10-03 | 37104350309 | VPS | atlasos-nvidia | 20m 53s | 10m 51s | 8m 56s | 0m 37s |
| 2026-10-03 | 37104350309 | VPS | atlasos | 50m 23s | 40m 43s | 8m 19s | 0m 36s |
| 2026-10-03 | 37103067656 | VPS | atlasos-nvidia | 24m 45s | 10m 5s | 8m 41s | 5m 35s |
| 2026-10-03 | 37103067656 | VPS | atlasos | 53m 49s | 40m 51s | 8m 2s | 4m 17s |
| 2026-10-03 | 37095610573 | GitHub-hosted | atlasos | 34m 22s | 33m 22s | – | – |
| 2026-10-03 | 37089158901 | GitHub-hosted | atlasos-nvidia | 15m 59s | 6m 33s | 6m 46s | 1m 2s |
| 2026-10-03 | 37089158901 | GitHub-hosted | atlasos | 40m 17s | 32m 22s | 5m 59s | 1m 5s |
| 2026-10-02 | 37076981806 | GitHub-hosted | atlasos | 31m 0s | 29m 41s | – | – |
| 2026-10-02 | 37076799895 | GitHub-hosted | atlasos-nvidia | 13m 51s | 6m 0s | 6m 25s | 0m 50s |
| 2026-10-02 | 37076799895 | GitHub-hosted | atlasos | 40m 14s | 32m 12s | 6m 0s | 1m 7s |
| 2026-10-02 | 37051711038 | GitHub-hosted | atlasos | 21m 52s | 13m 20s | 5m 56s | 1m 27s |
| 2026-10-02 | 37036023567 | GitHub-hosted | atlasos | 21m 26s | 13m 19s | 5m 59s | 1m 10s |
| 2026-10-02 | 37024803877 | GitHub-hosted | atlasos | 22m 5s | 13m 22s | 5m 55s | 1m 9s |
| 2026-10-02 | 37016232908 | GitHub-hosted | atlasos | 23m 4s | 14m 26s | 5m 49s | 1m 35s |
| 2026-10-02 | 36971654710 | GitHub-hosted | atlasos | 15m 13s | 13m 36s | – | – |

The VPS runs, oldest first:

- 37103067656 and 37104350309: every cache empty (the cleanup then cleared
  them after each job). KIO and the Rust apps compile from scratch.
- 37130390547: the caches kept. Only the Rust apps (Atlas Updater had
  changed, 6 minutes) and the steps after the packages step reran.
- 37136001901: the first with chunkah (see `just rechunk`), nothing to
  rebuild. Rechunking went from about 8.5 minutes per image to 2. Its pushes
  are slow because every layer was new to the registry; they take under a
  minute once the layers are there. Both images in 13m 12s.
- 37147087222: the first after atlas.spec's faster build flags
  (atlasos-updater 7830fb6, see below). New flags start the Rust cache over,
  so all 204 crates recompiled: the RPM's build took 13 minutes. It stopped
  before pushing (no `SIGNING_SECRET`), so it isn't in the tables.

### What to expect on the VPS

A build where nothing changed takes about 8 minutes for both images: rechunking
(2 minutes each), NVIDIA's driver step (2 minutes, rerun on every build because
the image under it carries the date and commit) and the pushes. A change to
Atlas Updater adds about 6 minutes with the old build flags (its stage, with
the Rust cache) and should add about 3 with the new ones (not yet measured on
the VPS), the daily package update about 2. A new Kinoite or a cleared cache
reruns the stages built on it: KIO and the Rust apps from scratch take about 40 minutes.

What limits it, measured on 37130390547 with sar: CPU. The build steps use
the 4 CPUs; the disk was under 20% busy, the network fetched at 34 MB/s, and
about 6 GB of memory stayed free. rpm-ostree's chunker ran on one CPU for
most of its 8.5 minutes, which is why chunkah, using all four, made the
largest difference.

### The Atlas Updater RPM's build flags

atlasos-updater 7830fb6 builds the Rust code with 4 codegen units and no LTO
(Fedora's flags ask for 1 and the profile for thin LTO), the C++ app without
LTO, and atlas-system-helper beside the app. The binaries are about 4 MB
larger. Measured locally in a container limited to 4 CPUs and 7.6 GB, the
VPS's size; the RPM's `%build`, in seconds:

| atlas.spec | From scratch | After an atlas-core (now atlas-update-engine) change |
|---|---:|---:|
| Old flags (20ff489) | 261 | 66 |
| New flags, helper beside the app (7830fb6) | 189 | 20 |
| New flags, helper after the app | 185 | 32 |

Peak memory stayed under 5 GB. The VPS is about 4 times slower than that
container: the old flags' 66 seconds took 4m 20s in 37130390547. A change to
the spec's Rust flags starts the Rust cache over, like a new compiler.
