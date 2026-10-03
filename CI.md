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

| atlas.spec | From scratch | After an atlas-core change |
|---|---:|---:|
| Old flags (20ff489) | 261 | 66 |
| New flags, helper beside the app (7830fb6) | 189 | 20 |
| New flags, helper after the app | 185 | 32 |

Peak memory stayed under 5 GB. The VPS is about 4 times slower than that
container: the old flags' 66 seconds took 4m 20s in 37130390547. A change to
the spec's Rust flags starts the Rust cache over, like a new compiler.
