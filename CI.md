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
[ci/vps-runner](ci/vps-runner/README.md) sets it up. The build and NVIDIA jobs
name the runner they got: "Build and push (vps)" or "Build and push (hosted)".

`promote-stable.yml` (the weekly stable release) stays on GitHub's runners. It
builds nothing: skopeo copies the newest `testing` image to `stable` by
digest, so it has nothing to cache.

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

## Caches on the VPS

GitHub's runners start empty every time; their only cache is dnf's downloads
(`actions/cache`, keyed by ISO week). The VPS keeps, between builds:

| What | Where (runner container) | Saves |
|---|---|---|
| Podman's images and layers | `/home/podman/.local/share/containers` | Pulling Kinoite and Fedora (about 4 GB); every Containerfile stage whose inputs didn't change: branding, the Atlas apps, KIO, plasma-setup |
| Rust build cache | `/var/tmp` (Podman's `RUN --mount=type=cache`, `ATLAS_BUILD_CACHE`) | Crates and their build output: when Atlas Updater changes, its dependencies come from the cache and only its own crates and app recompile (the checkout gives every source file a new time) |
| dnf's downloads | `/cache/dnf` (`ATLAS_DNF_CACHE`) | Fedora packages for the build |

The Rust cache needs `packaging/build-rpm.sh` with `ATLAS_BUILD_CACHE`
support in atlasos-updater; with an older one the build still works, uncached.

The runner has a 50 GB disk; the caches take about 20 GB of it and a build
about 20 GB more at its peak. After every job (and before the next) its
cleanup removes the images the build made, which are in the registry by
then, and base images a newer pull replaced, with the build steps cached on
them. It clears the Rust cache past 8 GB and dnf's past 3 GB, and when less
than 26 GB is free (what a build needs) it gives up more, cheapest first:
the Rust cache, dnf's downloads, every image.
[ci/vps-runner](ci/vps-runner/README.md#disk) has the details.

## Build times

`scripts/ci-times.sh [runs]` prints these tables from the GitHub API (the last
40 successful runs by default). Re-run it and paste the output here once the
VPS has built a few times.

"Build step" is `just build`; "Rechunk" and "Push" only run when an image is
published; pull requests and tags ("build only") skip them.

### Measured

As of 2026-10-02, GitHub-hosted runners (ubuntu-26.04: 4 CPUs, 16 GB):

| Runner | Image | Work | Jobs | Job (median) | Build step | Rechunk | Push |
|---|---|---|---:|---:|---:|---:|---:|
| GitHub-hosted | atlasos | build + publish | 5 | 22m 5s | 13m 22s | 5m 56s | 1m 10s |
| GitHub-hosted | atlasos | build only | 2 | 23m 6s | 21m 38s | – | – |
| GitHub-hosted | atlasos-nvidia | build + publish | 1 | 13m 51s | 6m 0s | 6m 25s | 0m 50s |

| Date | Run | Runner | Image | Job | Build step | Rechunk | Push |
|---|---|---|---|---:|---:|---:|---:|
| 2026-10-02 | 37076981806 | GitHub-hosted | atlasos | 31m 0s | 29m 41s | – | – |
| 2026-10-02 | 37076799895 | GitHub-hosted | atlasos-nvidia | 13m 51s | 6m 0s | 6m 25s | 0m 50s |
| 2026-10-02 | 37076799895 | GitHub-hosted | atlasos | 40m 14s | 32m 12s | 6m 0s | 1m 7s |
| 2026-10-02 | 37051711038 | GitHub-hosted | atlasos | 21m 52s | 13m 20s | 5m 56s | 1m 27s |
| 2026-10-02 | 37036023567 | GitHub-hosted | atlasos | 21m 26s | 13m 19s | 5m 59s | 1m 10s |
| 2026-10-02 | 37024803877 | GitHub-hosted | atlasos | 22m 5s | 13m 22s | 5m 55s | 1m 9s |
| 2026-10-02 | 37016232908 | GitHub-hosted | atlasos | 23m 4s | 14m 26s | 5m 49s | 1m 35s |
| 2026-10-02 | 36971654710 | GitHub-hosted | atlasos | 15m 13s | 13m 36s | – | – |

VPS (4 CPUs, 7.6 GB): no builds yet. The runner is installed but not yet
registered; see [ci/vps-runner](ci/vps-runner/README.md#install).

### What to expect on the VPS

Not VPS numbers: a local test of the runner container on the development
desktop (32 threads, nested rootless Podman as on the VPS), running
`just build` and `just rechunk` twice on the same commit, 2026-10-02:

| Run | Build step | Rechunk |
|---|---:|---:|
| First, every cache empty | 18m 35s | 5m 15s |
| Second, nothing changed | 0m 14s | 4m 26s |

Atlas Updater's RPMs alone, in the `atlas-apps` stage: 4m 4s with an empty
Rust cache, 5s with a full one.

So on the VPS, a build where nothing in a stage changed skips that stage, and
rechunking (about 4 to 5 minutes here, on every published build) becomes
most of the job. A new Kinoite reruns the stages built on it, and a change to
Atlas Updater reruns its stage with the Rust cache. The VPS has 4 CPUs
against the desktop's 32, so its cold builds will be slower than these;
the table above gets its real numbers after the first builds there.
