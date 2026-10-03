# AtlasOS runner on the VPS

A self-hosted GitHub Actions runner for this repository on `eterneon-vps`.
It builds pushes to `main`, the daily scheduled build, manual runs on `main`
and tags. Pull requests and `beta` always build on GitHub's runners, and so
does everything else whenever this runner is offline. [CI.md](../../CI.md)
covers the routing, the caches and the build times.

## How it is put together

- **A dedicated account.** `atlas-runner`, with its home and all its data in
  `/var/lib/atlas-runner`. No password, no login shell, no sudo, and not in the
  `docker` group, so it can't reach the VPS's Docker containers (the panel,
  the site, Forgejo, their databases).
- **Inside a container.** The runner runs in a rootless Podman container
  (`localhost/atlas-runner`, built from the [Containerfile](Containerfile)
  here) as an unprivileged user, and builds AtlasOS with rootless Podman
  inside that container, as GitHub's hosted runners do. Nothing runs as root.
  Rootful Podman is installed with the package but is not used.
- **Started by systemd.** A Quadlet unit in the account's own systemd
  (`/etc/containers/systemd/users/<uid>/atlas-runner.container`, root-owned)
  starts it at boot and restarts it if it stops.
- **A disk of its own, 50 GB.** `/var/lib/atlas-runner` is an ext4 image
  file, `/var/lib/atlas-runner.img`, mounted at boot. Whatever a build does,
  it can fill only that, never the disk the VPS's other services use. The
  space is reserved up front (60 GB free on the VPS leaves 10 GB).
- **Limited.** `/etc/systemd/system/user-<uid>.slice.d/50-atlas-runner.conf`
  gives everything the account runs a CPU weight of 20 (other services have
  100: the build uses idle CPU in full and yields when they are busy), a
  3.5 GB memory throttle, a 4 GB hard limit, 1 GB of swap and 4096 tasks. The
  VPS's services use about 1.6 GB.
- **Kept off the VPS's own services.** Jobs run the repository's code with
  network access. A firewall (`/etc/atlas-runner/firewall.nft`, loaded by
  `atlas-runner-firewall.service` before the account's systemd starts) stops
  the account connecting to the VPS's own addresses (the services listening
  there, Docker's published ports) and to private networks (Docker's
  bridges, with the panel's and Forgejo's databases). DNS to
  systemd-resolved is allowed, and so is the internet. If nftables.service
  is ever enabled, its `flush ruleset` would delete the table, so the
  firewall unit loads after it and again when it reloads; restarting
  nftables.service restarts the runner. `setup.sh status` says whether the
  table is loaded.
- **Only trusted jobs.** The repository is public, and a pull request from a
  fork runs the workflow from the pull request, which could ask for this
  runner. Before every job, [hooks/job-started.sh](hooks/job-started.sh)
  refuses anything but a push, schedule or manual run of this repository on
  `main` or a tag. The hook lives in the image, not in the repository, so a
  pull request can't change it.
- **Caches that stay, and a cleanup that keeps them small.** Five Podman
  volumes survive restarts: the registration, the checkouts, dnf's
  downloads, Podman's image and layer storage, and `/var/tmp`, which holds
  Podman's build cache mounts (the Rust build cache). After every job (and
  before, in case one was cut short) [cleanup.sh](cleanup.sh) removes what
  the next build can't reuse; see [Disk](#disk).

## Before you start

1. **Disk.** `setup.sh check` wants 55 GB free on the root disk: 50 GB for
   the runner's disk image and 5 GB left over. The VPS has 60 GB free. For a
   different size, set `RUNNER_DISK_GB` on every `setup.sh` command. If you
   add a block volume instead, mount it at `/var/lib/atlas-runner` first and
   `setup.sh` uses it as it is.

2. **Fork pull requests need approval.** In the repository's Settings, under
   Actions, General, set "Approval for running fork pull request workflows
   from contributors" to **Require approval for all external contributors**.
   The job-started hook already refuses pull requests; this stops them
   reaching the runner at all.

## Install

On the VPS, from a checkout of this repository:

```sh
git clone https://github.com/EternalCoder454/AtlasOS ~/AtlasOS
cd ~/AtlasOS

# 1. What the VPS has and what is missing. Changes nothing.
sudo ci/vps-runner/setup.sh check

# 2. Install Podman and nftables, create the 50 GB disk, the atlas-runner
#    account, the firewall, the runner image and the unit. Ends with a
#    self-test of Podman inside the runner container.
sudo ci/vps-runner/setup.sh install
```

3. **Register it.** From a machine where `gh` is signed in, pipe a one-hour
   registration token straight to the VPS, so it never appears on a command line:

   ```sh
   gh api -X POST repos/EternalCoder454/AtlasOS/actions/runners/registration-token --jq .token |
     ssh eterneon-vps 'sudo ~/AtlasOS/ci/vps-runner/setup.sh register'
   ```

   It registers as `atlasos-vps`, with the labels `self-hosted`, `Linux`, `X64`
   and `atlasos-vps`, starts, and shows its log.

4. **Let the workflow see it.** The workflow checks whether the runner is
   online before it sends a build there, and that needs a token GitHub's own
   can't be. Create a fine-grained personal access token (Settings, Developer
   settings) for the AtlasOS repository only, with **Administration:
   Read-only** and nothing else, then store it:

   ```sh
   gh secret set RUNNER_STATUS_TOKEN -R EternalCoder454/AtlasOS
   ```

   Without this secret every build stays on GitHub's runners.

5. **Check it.**

   ```sh
   gh api repos/EternalCoder454/AtlasOS/actions/runners --jq '.runners[] | [.name, .status] | @tsv'
   gh workflow run build.yml -R EternalCoder454/AtlasOS --ref main
   ```

   The build job is named "Build and push (vps)" when it ran here.

## Running it

| Task | Command (on the VPS) |
|---|---|
| State, disk use and recent log | `sudo ~/AtlasOS/ci/vps-runner/setup.sh status` |
| Follow the log | `sudo journalctl -f _SYSTEMD_USER_UNIT=atlas-runner.service` |
| Cache sizes, and what the next cleanup removes | `sudo ci/vps-runner/setup.sh cache` |
| Rebuild the image (new runner version, changed hooks) | `git pull && sudo ci/vps-runner/setup.sh image` |
| Stop / start / restart | `sudo ci/vps-runner/setup.sh stop` (or `start`, `restart`) |
| Clear every cache (the next build starts cold) | `sudo ci/vps-runner/setup.sh clear-cache` |
| Firewall hits | `sudo nft list table inet atlas_runner` (the counters) |

`image`, `stop`, `restart` and `clear-cache` wait for a running job to finish
first; `FORCE=1` skips the wait, failing the job.

The runner updates itself when GitHub requires a newer version. A restart goes
back to the version in the image and updates again, so rebuild the image now
and then (`RUNNER_VERSION` and `RUNNER_SHA256` in the Containerfile).

## Disk

Measured on the VPS (2026-10-03): a build from empty caches took the disk
from 12 GB used (the runner image and its checkouts) to 42 GB at its peak,
while rechunking with rpm-ostree's chunker, which needed 8 to 10 GB of
working space. With chunkah, a build that reused the caches went from 29 GB
to 34 GB. What stays is Kinoite, Fedora, every cached build step,
the Rust and CMake build cache (5 GB) and dnf's downloads (1 GB); the
builder stages remove their build dependencies before their layer is saved
([drop-build-deps.sh](../../build_files/drop-build-deps.sh)), which keeps
about 6 GB out of it. Rechunking needs only its result, a 3 GB OCI
directory in the job's temporary directory, which the runner empties after
the job. atlasos-nvidia is built in the same job, on the
layers already there. (As a job of its own it downloaded the rechunked image,
9 GB that shares no layers with the cache, and the cache never survived.) On
a day Fedora publishes a new Kinoite, add 7 GB until the old one is removed
after the job. The 50 GB disk holds 49 GB.

[cleanup.sh](cleanup.sh) (`atlas-runner-cleanup` in the image) runs after
every job, and before the next in case one was cut short. It removes:

- the images the build made (the image and the NVIDIA image, both labelled
  `org.atlasos.base-image`). They are in the registry.
- base images a newer pull replaced (yesterday's Kinoite, a `fedora:44` that
  lost its tag to a newer one), with every cached build step made on them.
- Podman's build cache mounts (the Rust build cache) past 8 GB, and dnf's
  downloads past 3 GB (packages unused for 30 days go sooner).

Then, while less than 16 GB is free (what a build needs), it clears more,
cheapest to rebuild first: the build cache mounts, then dnf's downloads, then
every image. A job doesn't start with less than 16 GB free even after that.

The limits are in `/etc/atlas-runner/runner.env` (`ATLAS_RUNNER_MIN_FREE_GB`,
`ATLAS_RUNNER_BUILD_CACHE_GB`, `ATLAS_RUNNER_DNF_CACHE_GB`); `setup.sh`
creates it and doesn't overwrite it. `sudo ci/vps-runner/setup.sh restart`
applies a change.

## Removing it

```sh
gh api -X POST repos/EternalCoder454/AtlasOS/actions/runners/remove-token --jq .token |
  ssh eterneon-vps 'sudo ~/AtlasOS/ci/vps-runner/setup.sh unregister'
```

That removes it from GitHub and stops it; builds go back to GitHub's runners.
To delete the account, its disk and every cache as well:

```sh
uid=$(id -u atlas-runner)
sudo loginctl disable-linger atlas-runner
sudo systemctl stop user@$uid.service
sudo systemctl disable --now atlas-runner-firewall.service
sudo rm -rf /etc/containers/systemd/users/$uid /etc/systemd/system/user-$uid.slice.d \
  /etc/systemd/system/user@$uid.service.d /etc/systemd/system/atlas-runner-firewall.service \
  /etc/atlas-runner
sudo userdel atlas-runner
sudo umount /var/lib/atlas-runner
sudo sed -i '\|^/var/lib/atlas-runner.img |d' /etc/fstab
sudo rm /var/lib/atlas-runner.img
sudo rmdir /var/lib/atlas-runner
sudo systemctl daemon-reload
```

## If the self-test fails

The install ends by running Podman inside the runner container. If that fails:

- `newuidmap ... Operation not permitted` or `cannot set up namespace using
  "/usr/bin/newuidmap"`: the account has no subordinate ids. Check that
  `grep atlas-runner /etc/subuid /etc/subgid` shows a range of 65536.
- `unshare: Operation not permitted` or `user namespaces are not enabled`:
  Ubuntu's AppArmor limit on unprivileged user namespaces
  (`kernel.apparmor_restrict_unprivileged_userns`, 1 on this VPS) is
  blocking Podman inside the container. Lifting it is a system-wide security
  change, so decide that deliberately; the alternative is to run the runner
  directly as `atlas-runner` without the outer container.
- A pull or `curl` that times out: the firewall. `sudo nft list table inet
  atlas_runner` shows which rule's counter went up.
