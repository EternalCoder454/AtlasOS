# Telamon OS: developer notes

How Telamon OS is built, updated and tested. For what Telamon OS is and how to
install it, see the [README](README.md). Test reports are in
[docs/](docs/): [PHASE1.md](docs/PHASE1.md) (the base image),
[UPDATES.md](docs/UPDATES.md) (the update system) and
[PRIVACY.md](docs/PRIVACY.md) (what is sent and kept).

Telamon OS is a Fedora Kinoite 44 [bootc](https://bootc-dev.github.io/bootc/)
image. Images: `ghcr.io/eternalcoder454/telamonos`, and the same builds under
their old name, `ghcr.io/eternalcoder454/atlasos` ("The two image names" below).

| Tag | Channel | Built from |
|---|---|---|
| `testing`, `testing-44.YYYYMMDD-N` | Testing: built daily and on every push | `main` |
| `stable`, `latest`, `44`, `44.YYYYMMDD-N` | Stable: weekly | the newest testing image, copied by digest (never rebuilt) |
| `beta`, `beta-44.YYYYMMDD-N` | Beta | `beta` |

`ghcr.io/eternalcoder454/telamonos-nvidia` (and `atlasos-nvidia`) has the same
tags: each Telamon OS image plus NVIDIA's driver (see NVIDIA below).

`latest` is `stable`. The version `44.YYYYMMDD-N` (the build's UTC date, and
N its number that day across all channels, from 1) is the same in the image's `org.opencontainers.image.version` label, in
`/etc/os-release` and in the tags. The `org.opencontainers.image.revision`
label is the Telamon OS commit the image was built from,
`net.eterneon.telamon.framework.revision` the telamon-framework commit,
`net.eterneon.telamon.updater.revision` the Telamon Updater commit, and
`net.eterneon.telamon.monitor.revision` the Telamon Monitor commit.

## Updates

- **Staging:** `atlasos-update-stage.timer` runs `bootc upgrade --quiet`
  (`atlasos-update-stage.service`; `rpm-ostree upgrade` on a system with
  packages added by `rpm-ostree install`, which bootc refuses to upgrade, so
  they are kept) 15 minutes after boot and every 6 hours
  after that, with a random delay of up to 15 minutes. It downloads and stages
  the new image and never reboots; a staged update is used at the next
  shutdown or reboot. It runs at idle CPU and disk priority, only on an
  image-based boot, with the network up, and not on a connection NetworkManager
  reports as metered. A download that failed with a network error is tried again
  after 15 minutes (at most 4 tries in 3 hours). It skips the image this
  machine went back from, one that failed its boot checks, and one older than
  the installed version (a tag that went back). That last check runs twice:
  before the download against the registry, and after it against what was
  staged (`check_staged` in `update-stage`), which takes an older image out
  again with `rpm-ostree cleanup -p` and fails the run; it also does that when
  it can't tell. Both use `/usr/share/telamon/image-age.jq`, the same rule as
  Telamon Updater's `ImageStatus::is_older_than`. The service is sandboxed as
  far as bootc allows (no `ProtectSystem` or `RestrictNamespaces`: it writes
  `/sysroot`, `/boot`, `/etc` and `/var`, and needs mount namespaces;
  `CAP_SYS_PTRACE` stays because bootc reads `/proc/1/ns/mnt`). An older
  version of the same image staged by hand (`rpm-ostree deploy`) is taken out
  by the next run too; to stay on one, pin it or stop the timer.
- **SELinux:** bootc and ostree must run in `install_t`, which may write
  labels the running policy doesn't know yet (a new image can bring new
  types). Fedora's policy enters it from a unit whose ExecStart is bootc
  (`init_t`) or a root shell, not from `unconfined_service_t`, where
  `update-stage`, Telamon Updater's helper, `telamon-record-boot`,
  `grub-greenboot` and the greenboot checks run. `selinux/atlasos_bootc.te`
  adds that transition (with `nnp_transition`, for `grub-greenboot`'s
  `NoNewPrivileges`). Without it, bootc's probe (`chcon` to a made-up type)
  was denied and logged twice per `bootc status` at every boot, and bootc
  carried on without the right. Check with
  `ausearch -m avc -ts boot -c chcon` (empty).
- **Signatures, tested:** with the policy's key swapped for a wrong one,
  `bootc switch` (without `--enforce-container-sigpolicy`), `bootc upgrade`,
  `rpm-ostree rebase` to both `ostree-unverified-registry:` and
  `ostree-image-signed:`, and `skopeo` all refuse the image, and an unsigned
  tag fails with "A signature was required". rpm-ostreed reads the policy
  when it starts: a changed `policy.json` applies after a restart of it (a
  reboot does that).
  `bootc-fetch-apply-updates.timer` (which reboots) and
  `rpm-ostreed-automatic.timer` stay disabled; `build.sh` fails if they are
  enabled.
- **Notifier:** [Telamon Updater](https://github.com/EternalCoder454/atlasos-updater)
  shows what is staged and offers the restart. Discover's notifier is removed
  and its unattended updates are off; the build checks both.
- **Release notes:** the GitHub releases are the changelog Telamon Updater
  shows. Each testing build gets a pre-release tagged with its version.
  `build.yml` writes it after the push (`scripts/build-notes.py`): the app
  pins that moved, each with the pull requests and commits it brings, this
  repository's own changes since the previous release, the day's Fedora
  updates, and the "Download size" line (`scripts/update-size.py`, see
  [Update size](#update-size)). Notes written by hand before the build finishes are kept. Promoting it to stable moves the tag to the commit
  the image came from and makes it the latest release, notes kept. A stable
  build with no pre-release gets the commits since the previous stable
  release, grouped by what they touch (`scripts/release-notes.sh`; the first
  stable lists the newest commits). Older releases are plain `44.YYYYMMDD`.
- **Telamon apps are system components.** `telamon-system-helper` (called
  `atlas-system-helper` before 0.3.0 and `atlas-core` before 0.1.0-2), `telamon-updater`, `telamon-monitor` and
  `telamon-notepad`, `telamon-settings`, `telamon-wizard`, and the framework they share (`telamon-ui`, the Telamon.Ui
  QML module in `/usr/lib64/qt6/qml/Telamon/Ui`, with `telamon-symbols-fonts`
  and the `telamon-symbols` gallery), are RPMs built into the image under
  `/usr`, so Discover (its backends here are Flatpak and fwupd, no
  PackageKit) has no way to uninstall them, and
  `/etc/dnf/protected.d/telamon-framework.conf` (from `telamon-ui`), `telamon-updater.conf`
  (from `telamon-system-helper`), `telamon-monitor.conf`, `telamon-notepad.conf`, `telamon-settings.conf` and `telamon-wizard.conf`
  stop dnf removing them. The build fails without them. Root can still run
  `rpm-ostree override remove`; that is the limit on an open system. The
  tray autostart can be turned off in System Settings; background staging is
  a system timer and keeps working.

## Update size

What an update downloads is the compressed size of the layers a machine does
not have yet (bootc keeps every layer it imported and skips one whose digest
it has). `scripts/update-size.py` computes that from manifests and image
configs only, nothing is pulled:

    scripts/update-size.py ghcr.io/eternalcoder454/telamonos:testing-44.20261007-6 \
        --history ghcr.io/eternalcoder454/telamonos --history ghcr.io/eternalcoder454/atlasos
    scripts/update-size.py --series OLDEST ... NEWEST     # consecutive builds, oldest first

Images can be registry references or anything skopeo reads (`oci:DIR:TAG`
for a `just rechunk` result). `build.yml` runs it after every push: the job
summary has the table (from the previous build, a week and four weeks
earlier, with the biggest new layers), and the testing build's changelog gets
"Download size: X MB from the previous build" (`scripts/build-notes.py`).

What keeps an update small, all in `just rechunk`:

- **255 layers**, split by package (chunkah). Measured by replaying the
  published builds 44.20261007-3 to -6 (3 updates): mean 361 MB per update
  with 127 layers and no hints, 357 MB with hints and 127 layers, 241 MB
  with hints and 255 (median 215, 366 and 114 MB).
- **Hints** (`build_files/layer-hints.sh`, run in a throwaway copy of the
  image): every file and directory time is 0 (a directory with a time from
  the build, such as `/etc`, made every layer under it new: about 115 MB of
  every update), the locale archive (233 MB, the same for every glibc) is a
  layer of its own, and Telamon's own packages and `system_files` are
  components with an update interval, so chunkah packs what changes daily
  with what changes daily. chunkah does not promise a layer per component:
  the version stamp (`os-release`, `telamon-release`) ends up beside others
  in one layer (8.8 MB).
- **A reproducible RPM database.** `packages.sh` and `apps.sh` run dnf with
  `SOURCE_DATE_EPOCH=1`, which rpm 6 writes as every package's install time,
  so `rpmdb.sqlite` (100 MB, 36 MB compressed) is the same in builds of the
  same packages. dnf5's transaction history (a record with the build's
  times, nothing on an image-based system reads it) is removed by
  `cleanup.sh`. Install times of packages added by the build are therefore
  1970; Fedora's own packages keep theirs.

Measured on two local builds one version apart (nothing else changed): 207 MB
before, 8.8 MB now (the version stamp's layer). A real day brings real package
updates on top of that.

## Flatpaks and Flathub

Flathub is a system remote (`/usr/share/flatpak/remotes.d/flathub.flatpakrepo`)
next to Fedora's. Apps in `/usr/share/flatpak/preinstall.d/atlasos.preinstall`
(Flatseal for now) are installed by `atlasos-flatpak-preinstall.service`,
which `atlasos-flatpak-preinstall.timer` starts 3 minutes after boot, so it
can't delay boot or login. It runs `flatpak preinstall --system -y
--noninteractive`, and skips while `/var/lib/atlasos/flatpak-preinstall.sha256`
matches a hash of the `preinstall.d` files. The stamp is written only on
success, so without a network it tries again every 6 hours and at the next
boot. Flathub gets remote priority 2 the first time it runs (Fedora's remote
has Flatseal too); change it with `flatpak remote-modify` and it stays.
Users who uninstall a preinstalled app don't get it back. To add an app, add a
`[Flatpak Preinstall <app id>]` group with `Branch=` to the file (the format
is in `flatpak-preinstall(1)`).

## Settings updates for existing users

Plasma applies the image's `/etc/xdg` defaults to keys a user hasn't set, but
anything a theme's `defaults` file or an old image already wrote into
`~/.config` stays. `kconf_update` fixes that. `atlasos-kconf-update.service`
(a user unit) runs it on `atlasos.upd` at every Plasma login, before KWin and
the shell start; each `Id` runs once per user, recorded in
`~/.config/kconf_updaterc`. Plasma's `kded6` also runs `kconf_update`, but
skips our file: it only reads a `.upd` whose mtime changed, and ostree gives
every file in `/usr` mtime 0, the same as "never seen".

To add an update:

1. Write `system_files/usr/share/kconf_update/atlasos-YYYYMMDD-<name>.sh`
   (executable, safe to run twice, never overwriting a value the user set;
   `kreadconfig6` and `kwriteconfig6` are there).
2. Add to `atlasos.upd` in the same folder:
   ```
   Id=atlasos-YYYYMMDD-<name>
   Script=atlasos-YYYYMMDD-<name>.sh,sh
   ```
   The `Id` must be new and never change.
3. Try it: `kconf_update --testmode --debug system_files/usr/share/kconf_update/atlasos.upd`
   with a throwaway `HOME` (the image's `/usr/libexec/kf6/kconf_update`; in
   a container, with the folder mounted at `/usr/share/kconf_update`).
   `--testmode` doesn't record the `Id`, so it runs again each time.

`build.sh` checks that the scripts are executable and the `Id`s unique. The
first entry fills look-and-feel keys of the user's Telamon OS theme that they
never set.

## Boot health checks and rollback

[greenboot](https://github.com/fedora-iot/greenboot-rs) (greenboot-rs 0.16.4,
Fedora's package, built for bootc) checks every boot and rolls a bad update
back. `greenboot-healthcheck.service` and `greenboot-set-rollback-trigger.service`
are enabled; `greenboot-default-health-checks` is **not** installed (its
repository DNS check fails offline and would roll back good updates on a
laptop without a network). `packages.sh` fails if that package is present,
`build.sh` if a unit is not enabled. `/etc/greenboot/greenboot.conf`: `GREENBOOT_MAX_BOOT_ATTEMPTS=3`.

**Checks.** Image-owned, in `/usr/lib/greenboot/check/required.d` (greenboot
reads it before `/etc/greenboot`, which users can change). Each logs one line
(`journalctl -u greenboot-healthcheck.service`) and has its own awake-time
deadline. When in doubt a check **passes**, because a false failure reboots a
healthy machine. Every check passes ("skipped") when:

- there is no rollback deployment (greenboot's `bootc rollback` fails with one,
  so a failure could only reboot in a loop: a fresh install);
- login and Plasma: first-run setup is not done (neither `/etc/telamon/setup-done` nor `/etc/plasma-setup-done` exists, the wizard runs before the display manager, with no greeter), the
  boot isn't graphical (`systemd.unit=`, `single`, `1`-`4`, `rescue`,
  `emergency`), the default target isn't `graphical.target`, the display manager
  isn't plasmalogin or it is masked, or at the end there is no `/dev/dri/card*`.

Each check finds its processes by the program they run (`/proc/<pid>/exe`,
`hc_pids_of` in `health-lib`), not by name, only in the host's mount
namespace, and the greeter's by its user (`plasmalogin`) too: a process name
is whatever a process says, and in a mount namespace of its own (`unshare
-Urm`, open to any user) a process can mount anything over
`/usr/bin/plasmashell`. And a user's Plasma counts only for a user logind
says has a local graphical session (`hc_graphical_uids`): otherwise any user
could start a `plasmashell` at boot (a lingering user service, a cron job) and
either keep a broken update or, with no `kwin_wayland` beside it, fail a
healthy one and force a rollback. Not covered: the signed-in user's own
programs can still make their desktop crash twice, which fails the check;
that takes code already running as that user.

| Check | Passes when | Waits | Limit |
|---|---|---|---|
| `10_atlasos_login.sh` | `plasmalogin.service` is active and the greeter (`/usr/libexec/plasma-login-greeter`) or the `plasmashell` of a graphical session (autologin) has run for 10 s | until 190 s awake | 240 s |
| `20_atlasos_plasma.sh` | with a user's graphical session: that user's `plasmashell` and `kwin_wayland` run for 10 s, and neither unit restarted twice or more (one crash is tolerated; one healthy session is enough); without one: the greeter and the greeter's `kwin_wayland` run for 10 s and `plasmalogin.service` hasn't restarted twice | until 240 s awake | 300 s |
| `30_atlasos_network.sh` | `NetworkManager.service` is active and `nmcli general status` answers; connectivity is not needed | until 90 s awake | 120 s |

Time is counted awake (`sleep` in a loop; `/proc/uptime` and `timeout(1)` count
suspend), so a laptop that suspends in the window isn't failed. The `timeout`
around each script is only a guard against a hung command: when it fires, or
the script itself errors, the check passes. A greeter that keeps exiting never
reaches 10 s, so it fails the login check. **Limit:** without autologin only the
greeter is exercised, so a broken `plasmashell` or a session that crashes right
after login is not caught (the checks run once, before anyone logs in).
`greenboot-healthcheck.service` has no `After=` on `multi-user.target` or
`graphical.target` (it is only `WantedBy=multi-user.target`, and
`Before=boot-complete.target`), so waiting for the checks delays neither.
A drop-in sets its `TimeoutStartSec=infinity` (the checks bound themselves).

`red.d/10_atlasos_red.sh` logs `atlasos-health: boot health check failed ...`
to the journal on every failed boot. Only at the **last** failure (boot counter
0, when the rollback happens) it also calls
`/usr/libexec/telamon-system-helper record-event health-check-failed` and appends
the image digest to `/var/lib/atlasos/bad-image-digests`;
`update-stage-condition` then skips staging while the newest image on the
registry has that digest, so a rolled-back update isn't downloaded again (a
newer image has a new digest), and Telamon Updater shows it as an update that
didn't start properly instead of offering it. `green.d/10_atlasos_green.sh` records
`health-check-passed` once per deployment, on its first good boot (the last 20
passed digests are in `/var/lib/atlasos/health-passed-digests`; a digest that
boots healthy also leaves `bad-image-digests`, which holds at most 20). The hooks never fail: greenboot's
reboot must not depend on them. Each check leaves its result in
`/run/atlasos/health/<name>`, which red.d reads.

**How a rollback happens** (greenboot-rs source, bootupd 0.3.2, bootc 1.16.13):

1. `greenboot-set-rollback-trigger.service` stops just before
   `ostree-finalize-staged.service` at the shutdown that applies a staged update
   and writes `greenboot_next_deployment_id` (the staged image digest) and
   `fallback=1` into `/boot/grub2/grubenv`.
2. A failed check on the new image: the first time greenboot sets
   `boot_counter=3` and reboots. GRUB (the greenboot snippet,
   `08_greenboot.cfg`) decrements it at each boot while `boot_success=0`. When
   the checks fail with the counter at 0 (4 boots in all) greenboot runs
   **`bootc rollback`**, clears the variables and reboots into the old image,
   and that is permanent: it is the default deployment from then on.
3. If the counter reaches 0 inside GRUB, the snippet boots `default=1`, the
   previous deployment, and sets `boot_counter=-1`. On that boot greenboot sees
   the booted image differs from `greenboot_next_deployment_id` and runs
   `bootc rollback` itself to make it permanent. No Telamon OS script is needed.
4. `telamon-system-helper record-boot` then sees the rollback in the boot history.

Stale counter: if the user runs `bootc rollback` while `boot_counter` is set,
`atlasos-grub-greenboot.service` unsets it at that shutdown (`ExecStop`, from
`bootc status` `rollbackQueued`), or an older image without greenboot would let
GRUB count it to 0 and boot the broken image. It can't help when the rollback is
done some other way (power loss, a rollback made by an older image).

Limits: the counter is only set by a failed health check, so a boot that never
reaches `greenboot-healthcheck.service` (kernel panic, systemd stuck early) is
not counted; only GRUB's own `fallback` handles an entry that fails to load.
The update that first introduces greenboot is not protected either, because the
old system has no trigger service, and its boot with no `greenboot_next_deployment_id`
that fails ends in "manual intervention required" rather than a rollback.

**The GRUB snippet and existing installs.** bootupd does not source
`configs.d` at boot. `bootupctl` (at install, `bootc install` and
bootc-image-builder) pastes the snippets of `/usr/lib/bootupd/grub2-static/configs.d`
into one `/boot/grub2/grub.cfg` ("Generated by bootupd / do not edit"), and
`bootupctl update` only updates the EFI binaries, never `grub.cfg`. So the
snippet reaches new installs only. For installs made before,
`atlasos-grub-greenboot.service` (`/usr/libexec/telamon/grub-greenboot`) runs at
every boot, after `ostree-remount` and `bootloader-update` and before greenboot:
when `grub.cfg` has no `08_greenboot.cfg` section it puts the same snippet into
`/boot/grub2/custom.cfg`, between `# BEGIN/# END atlasos-greenboot` markers
and keeping anything else in the file. GRUB sources `custom.cfg` after
`blscfg`, and bootupd never touches it. It writes nothing when the file is
already right, removes its block again when `grub.cfg` has the snippet (or the
counter would count twice), and leaves a `grub.cfg` that is not bootupd's
alone. `packages.sh` also adds the final newline the RPM's snippet lacks: bootupd
writes its `### END` marker right after it, which would join `save_env boot_success`
to the marker.

Check it in a VM (serial console):

```sh
sudo grub2-editenv list                 # boot_success, boot_counter, fallback, greenboot_next_deployment_id
sudo ls -l /boot/grub2                  # custom.cfg on an install made before greenboot
sudo grep -n -B1 -A3 'boot_counter' /boot/grub2/grub.cfg /boot/grub2/custom.cfg
systemctl status atlasos-grub-greenboot.service greenboot-healthcheck.service
journalctl -b -u greenboot-healthcheck.service -u atlasos-grub-greenboot.service
journalctl -b -t atlasos-health
cat /etc/motd.d/boot-status /run/atlasos/health/*
sudo bootc status                       # booted / staged / rollback
```

`tests/update/broken/` has an image whose login fails the check on purpose.

## What differs from Kinoite

- **Removed:** KDE PIM's Akonadi server, Baloo's file indexer, Discover's
  background update notifier, KDE Connect, and the extra apps Filelight,
  KCharSelect, KFind, KHelpCenter, KJournald, KRfb, KWalletManager, KWrite,
  System Monitor, Plasma Welcome, Partition Manager, KDebugSettings and the
  Firewall app (firewalld itself stays). Firefox, Konsole, and with it
  DrKonqi, KDE's crash reporter, which needs it. Also Fedora's wallpapers
  (F44, Default, Breeze's Next: the picker shows only Telamon OS's, checked at
  build time; `kde-settings-plasma` requires the Fedora set, so its packages
  stay installed and `build.sh` deletes only the pictures), Fedora's bookmarks,
  Chromium policy packages (Brave doesn't read them) and Fedora Linux's
  AppStream entry. (Menu Editor and Emoji Selector stay: they are part
  of `plasma-desktop`. Menu Editor and Kvantum Manager are hidden from the
  app menu by `packages.sh`; Menu Editor still opens from the launcher's
  "Edit Applications".)
- **Network:** firewalld's default zone is `Telamon OS`
  (`/usr/lib/firewalld/zones/Telamon.xml`, set in `firewalld-workstation.conf`
  by `build.sh`): Fedora Workstation's zone without its open ports
  1025-65535, so nothing on the network reaches this computer except replies,
  DHCPv6, mDNS (printers and other devices), Windows file share browsing, and
  SSH once its server is turned on. A port is opened in System Settings,
  Firewall (`plasma-firewall-firewalld`). Steam's Remote Play and local
  game transfers stay open (`steam-streaming`, `steam-lan-transfer`; only
  Steam listens there). An install whose `/etc/firewalld/firewalld.conf` is
  still the shipped link gets the zone with the update; one where an admin
  replaced it keeps its own default, and NetworkManager connections set to
  another zone keep theirs. LLMNR is off
  (`/usr/lib/systemd/resolved.conf.d/50-atlasos.conf`): anyone on the network
  can answer an LLMNR query for a one-word name and send this computer to
  their own address. mDNS (`.local`, through Avahi) and DNS are unchanged.
- **Turned off:** Discover's unattended updates, automatic reboots for
  updates (see Updates), dnf's metadata refresh
  timer (dnf can't change an image-based system anyway), and Fedora's
  on-screen keyboard (System Settings > Keyboard > Virtual Keyboard turns it
  back on).
- **Added:** Telamon Updater (the update screen and tray, with its `telamon-system-helper`
  helper), Flathub, Ghostty as the terminal (Ctrl+Alt+T), from the
  [scottames/ghostty](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/)
  COPR that Ghostty's install guide points to, since Fedora doesn't package
  it; IBM Plex Sans for the interface and JetBrains Mono for terminals
  and code. Dolphin's "Open Terminal Here" (and Shift+F4) opens
  Ghostty; Ghostty's own duplicate "Open Ghostty Here" entry is removed. Native RPMs for the everyday apps, so
  they take the Kvantum style and Papirus icons: Gwenview, Okular,
  Qalculate! (`qalculate-qt`) and Haruna, with `kf6-kimageformats`,
  `qt6-qtimageformats` and `kdegraphics-thumbnailers` named explicitly (weak
  dependencies are off). They are the default for images, PDFs, video and
  audio (`mimeapps.list`), and Okular starts without a menu bar and with small
  toolbar icons (`/etc/xdg/okularrc`). Haruna and Qalculate! read only their
  own `~/.config` files, so Telamon OS can't set their defaults system-wide;
  Haruna's hardware decoding is on (`auto`) by default anyway.
- **Third-party repos (Ghostty's COPR, NVIDIA's container
  toolkit):** never trusted on first use. Each repo's `.repo` file is in
  `build_files/repos` (`gpgcheck=1`, and `repo_gpgcheck=1` where the vendor
  signs its repodata: NVIDIA; COPR doesn't) and its public key
  in `build_files/keys`, with the key's fingerprint pinned in `packages.sh`
  (`nvidia/build.sh` for NVIDIA). The build refuses a key that doesn't match
  ("vendor rotated its key"); then check the new key, replace the file and
  update the fingerprint. The repo and key are removed again after the
  install. Fedora's own koji downloads (KIO, kernel-devel) are
  taken from koji's `data/signed` copies and checked against Fedora's
  release key before use.
  Key expiry, for diagnosing a future build failure:
  Ghostty 2030-05-15 (UTC),
  NVIDIA's primary key never (its signing subkey expired in 2021; the
  primary signs the repodata).
- **Codecs and video decoding:** `ffmpeg` replaces `ffmpeg-free`, with
  GStreamer's ugly, bad-freeworld and libav plugins, and Cisco's
  `openh264` plus `gstreamer1-plugin-openh264` replace `noopenh264`. These,
  `mesa-va-drivers-freeworld` (AMD) and `intel-media-driver` (Intel) come
  from RPM Fusion, whose release packages `packages.sh` installs for the
  build and removes again: no RPM Fusion repo is enabled in the image. If
  RPM Fusion's freeworld Mesa isn't the exact version of Fedora's yet,
  the build logs a warning and goes on with Fedora's own VA-API drivers. The
  NVIDIA image adds `libva-nvidia-driver`. Also added: `steam-devices`
  (controller udev rules) and `plasma-print-manager`. Discover's firmware
  updates come with `plasma-discover-libs` (its fwupd backend); there is no
  separate package.
- **Kept:** Plasma, KWin, Dolphin, Discover for Flatpaks,
  NetworkManager, PipeWire, Bluetooth, CUPS printing, Flatpak, zram swap.
- **Branding:** Telamon OS boot splash, Plasma splash, launcher icon, About page,
  login screen and wallpaper; `os-release` says Telamon OS (`ID=telamonos`,
  `ID_LIKE="atlasos fedora"`, `VERSION_ID=44`), and so do `/etc/system-release` and
  `/etc/redhat-release` ("Telamon OS release 44 (version)", in
  `/usr/lib/telamon-release`; `/etc/fedora-release` stays Fedora's). Plymouth's
  font is IBM Plex Sans: its label plugin ignores the theme's `Font=` and
  loads the file `Plymouth.ttf`, so a dracut module
  (`system_files/usr/lib/dracut/modules.d/50atlasos-plymouth-font`) links
  that to Plex in the initramfs. Ghostty has no system-wide config, so
  `/etc/skel/.config/ghostty/config` (JetBrains Mono, padding, themes `Telamon OS
  Light` and `Telamon Dark` in `/usr/share/ghostty/themes`, following the
  system's light and dark setting) is copied once to each user's
  `~/.config/ghostty/config` at their first Plasma session, unless they have
  one; their file overrides it from then on.
- **Windows 11 and macOS-style desktop:** a macOS-style menu bar along the
  top, as three floating islands each only as wide as what it holds: the
  Telamon OS menu and the active app's menus (File, Edit, View...) on the left,
  the time over the date in the middle (the calendar opens on a click), and
  the tray on the right: apps' status icons and the notification bell, then
  Quick Settings (below). The islands hide while a window covers them
  (`dodgewindows`), so maximized and fullscreen apps get the whole screen,
  and come back when the pointer reaches the top edge. **Meta+M**
  (`/usr/libexec/telamon/menubar-toggle`, registered by
  `/usr/share/kglobalaccel/org.telamon.menubar-toggle.desktop`, a link to
  its `applications/` file) switches them to staying on top of windows
  (`windowsgobelow`), which keep their size, and back. Existing desktops'
  one-piece bar becomes the islands through `atlasos-20261004-islands.js`,
  on the old bar's screen, keeping the tray's shown, hidden and turned-off
  icons, the clock's 12/24-hour, seconds and custom date settings, and any
  widgets the user added (after the tray, with their defaults). Meta+M only
  touches the islands (floating top panels in "fit" mode). In the
  left island the menus are never missing, as on macOS: Plasma's App Menu
  shows the ones an app exports (on Wayland only Qt and KDE apps do: GTK's
  module needs X11, libadwaita has no menu bar, Chromium and Electron export
  none), and our `org.telamon.appmenu` plasmoid, hidden when the active window
  has menus registered, shows the app's name in bold with a default File,
  Edit, View, Window and Help (Task Manager requests and KWin shortcuts;
  Wayland allows no synthesized Cut/Copy/Paste), and on the desktop a
  File/Go/Window/Help set. Existing desktops get it from
  `atlasos-20261003-appmenu.js`. A dock
  along the bottom (floating, centred, as wide as its icons) with the app
  launcher, a separator (our own small `org.telamon.dockseparator`
  plasmoid: Plasma's only draws a gap), then pinned and open apps, like
  macOS's: 48 px icons packed at a 60 px pitch on a rounded, see-through
  plate. Open apps get a short underline (accent colour for the active
  one) and a rounded tile covering the whole item on hover. All of that is
  the Telamon OS Plasma style (`system_files/usr/share/plasma/desktoptheme/telamon/`:
  the task frames, the dock's and menu bar's background, and every surface
  Plasma draws from its theme: popups (`dialogs/background`, 8 px card,
  hairline, soft shadow, see-through so KWin's blur shows), tooltips, desktop
  widget backgrounds, 4 px-radius buttons and flat tool buttons, text fields,
  sliders, switches, check and radio marks, scrollbars, tabs, list and view
  items, frames and progress bars, all sized like the Kvantum themes and
  coloured from the colour scheme so light, dark and the accent follow; with
  `plasmarc` copied from Breeze at build time; what is left (icons, clock,
  calendar, weather, action overlays) falls back to Breeze's `default`).
  Its SVGs are generated by `scripts/plasma-style.py` (the dock's 60 px, and
  each element keeps the ids of Breeze's); change the script and rerun it
  rather than editing them, and bump `Version` in the theme's
  `metadata.json` when they change (Plasma caches theme SVGs by it).
  The dock is made before the menu bar's islands, so Meta opens the dock's
  launcher (Plasma opens the first one it finds). Both bars are
  see-through, with a strong blur and a little noise behind them like
  Windows 11's acrylic (`[Effect-blur]` in `/etc/xdg/kwinrc`, which the
  menus and popups share). The launcher is Telamon Launcher
  (`EternalCoder454/atlasos-launcher`, built from its pinned commit): its dock
  button plasmoid (`net.eterneon.telamon.launcher.button`) is the dock's first
  item, `telamon-launcher.service` (enabled for every user by `build.sh`) runs
  it, and Meta opens it through plasmashell's "Activate Application
  Launcher" shortcut, which reaches the dock button (it provides
  `org.kde.plasma.launchermenu`); KWin 6.7 no longer reads
  `[ModifierOnlyShortcuts]`. Its
  default pins are `/etc/xdg/telamon-launcher/pinned.list` (from system_files,
  over the package's). (Andromeda Launcher and Simple Kickoff are gone; the
  `atlasos-20261005-launcher.js` update swaps them, Kickoff and Kicker out of
  existing panels and copies their favourites into the button's `ImportPins`.)
  The launcher's search is the only search: KRunner (Alt+Space) is retired
  by `build.sh`, which deletes its program, shortcuts file and D-Bus
  activation and masks `plasma-krunner.service` (the KRunner library and
  its plugins stay; Telamon Launcher runs them in its own process, and Settings'
  Plasma Search page still picks them). Notifications drop down at the top
  centre (`PopupPosition=TopCenter`, added to `/etc/xdg/plasmanotifyrc` by
  `build.sh`), sliding down from the top edge, just under the clock island;
  the tray island is too narrow for Plasma's "near the icon" default.
  Window titles on the left; minimize, maximize and close on the right; rounded window corners with a thin outline and soft shadows;
  translucent, blurred menus with a little noise (Windows' "acrylic"); the
  IBM Plex Sans font in place of Segoe UI. All of it is Plasma's own Breeze and KWin,
  configured; nothing extra runs.
- **macOS-style login and lock screens:** the wallpaper blurred and tinted
  with the logo's ink (done once at build time, not live), with the clock
  above the avatar and password field, in Telamon OS colours and IBM Plex Sans.
- **Two themes, and only two:** Telamon Light (the default) and Telamon Dark,
  Global Themes with colour schemes taken from the logo's violets. Breeze's
  and Fedora's Global Themes, colour schemes and Plasma Styles are removed.
- **Cursors:** [Bibata Modern](https://github.com/ful1e5/Bibata_Cursor)
  (GPL-3.0, `branding/cursors/`): Ice, white, with Telamon Light and as the
  default everywhere else; Classic, black, with Telamon Dark. Breeze's
  cursors are removed (the empty `breeze-cursor-theme` package stays, since
  `plasma-integration` requires it), and a settings update moves existing
  users off them.
- **Icons:** [Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)
  (GPL-3.0, Fedora's `papirus-icon-theme` and `-dark`): Papirus with
  Telamon Light and Papirus-Dark with Dark, set in each global theme's
  `defaults`; their panel and symbolic icons follow the colour scheme.
  `build.sh` turns the folders violet, as papirus-folders does: it points
  the `folder-*.svg` and `user-*.svg` links in each `places/` directory at
  the `-violet-` files instead of the `-blue-` ones, and fails if any is
  missing. A settings update (`atlasos-20261003-papirus.sh`) moves users
  from Dracula, which Telamon OS used before, to the matching Papirus.

## Patched KIO

`kf6-kio` is Fedora's own package, rebuilt with one extra patch
(`build_files/kio/`): KIO's SIGTERM handler wrote to a worker after the worker
was destroyed, so closing Dolphin crashed its thumbnail workers, one coredump
each ([KDE bug 518400](https://bugs.kde.org/show_bug.cgi?id=518400)). The
Containerfile's `kio` stage downloads the source RPM of exactly the version in
the base image from Koji, adds the patch, builds with release `.atlas1`, and
`packages.sh` installs those RPMs over Kinoite's. The build fails if the patch
stops applying; drop the stage once Fedora ships the fix.

## Patched login screen

`plasma-login-manager` is Fedora's own package, rebuilt with one patch
(`build_files/login/`, same method as the KIO one). The sign-in PIN is typed in
the login screen's password field, whose "Password" placeholder is fixed in the
greeter's compiled QML (`Login.qml`), so no PAM change can relabel it. The patch
makes the greeter's `main()` read `/etc/authselect/authselect.conf` once (a
bounded read of 4 KiB, any failure meaning "no") and expose one boolean to QML
(`PlasmaLogin.TelamonSignIn.pinSignIn`); `Login.qml` shows "Password or PIN"
when it is true, "Password" otherwise. The greeter runs before anyone has
authenticated, so QML gets no file access (`QML_XHR_ALLOW_FILE_READ` stays
off, and `packages.sh` checks the binary for it). Only the placeholder
changes; the file is world-readable (`etc_t`). The Containerfile's `login` stage downloads the source RPM of
exactly the version in the base image from Koji (checked against Fedora's key),
builds it with release `.atlas1` (plasma-login-manager and kcm-plasmalogin),
and `packages.sh` upgrades the image's two packages with those RPMs, with every
repo off, and checks the release and that the greeter binary holds the new
strings. To drop it: when upstream makes the placeholder configurable (or says
"PIN" itself), delete `build_files/login/`, the `login` stage and its bind in
the Containerfile, and the "Login screen" block of `packages.sh`; the build
fails earlier if the patch stops applying. The same applies to the lock screen
patch in `build.sh` (MainBlock.qml).

## First-run setup

The wizard on first boot is Telamon Setup (`telamon-wizard`, built from the
`wizard-app` stage, pinned like the other apps). It replaces Fedora's
`plasma-setup`, which `packages.sh` removes. Its design is in the wizard
repository's `docs/DESIGN.md`. In short:

- `telamon-wizard-boot.service` (enabled by the RPM's preset and again in
  `apps.sh`) runs before the display manager on every boot. With no done
  marker it writes a plasmalogin autologin drop-in
  (`/etc/plasmalogin.conf.d/99-telamon-wizard.conf`) for the locked
  `telamon-setup` user (a sysusers.d user of the RPM) and its `telamon-wizard`
  session; once setup is done it removes it and locks the user again. After
  repeated failures it starts a text-mode fallback instead.
- Setup is done when `/etc/telamon/setup-done` exists. The wizard also writes
  `/etc/plasma-setup-done`, which health-lib, `pin-setup`,
  `fingerprint-setup` and `nvidia-key-setup` still read, and an existing
  `/etc/plasma-setup-done` counts as done.

To see the wizard again in a VM:
`sudo rm /etc/telamon/setup-done /etc/plasma-setup-done` and reboot.
Test VMs skip it by creating both markers (`vmctl.py`, `vmswitch.py`).

## Fingerprint readers and smart cards

Everything ships in the image; `build.sh` turns on authselect's
`with-fingerprint` (as Fedora Workstation does) and fails the build if
`pam_fprintd` is missing from `system-auth` or `fingerprint-auth`, or has
crept into `password-auth` (the login screen stays password-only, so the
wallet unlocks). That gives fingerprint unlock for the lock screen, `sudo` and
polkit prompts. `pam_fprintd` falls through at once with no reader or no
enrolled finger, so other machines see no change, and fprintd is D-Bus
activated, so nothing runs at idle. Images updated from older ones pick it up
through the /etc merge, as long as nobody changed authselect locally.

Asking to set one up is `/usr/libexec/telamon/fingerprint-setup`, an XDG
autostart (`/etc/xdg/autostart/atlasos-fingerprint-setup.desktop`). It is not a
wizard page: the wizard runs as its own `telamon-setup` user before the account
exists, and enrolling needs the account. At login, once the wizard is done, it
asks fprintd (`Manager.GetDevices`) for readers; with one and no finger
enrolled it shows a kdialog and, on "Set Up Fingerprint", opens System
Settings' Users page, whose Fingerprint dialog does the enrolling. Any answer
(or an already enrolled finger) writes
`~/.local/state/atlasos/fingerprint-setup-done`; with no reader nothing is
written, so a reader plugged in later still gets the question. Existing users
are asked once too, after the update. To see it again, delete that file.

Smart card readers work as shipped (`pcscd.socket`, ccid, opensc, for browsers,
ssh and gpg). Logging in with a card is not offered: authselect's `local`
profile has no smartcard support, and it would need the `sssd` profile plus
certificate mapping, which a home PC has no use for.

## PIN sign-in

A Windows Hello-style PIN, 4 to 8 digits, for the login screen (plasmalogin)
and the lock screen (kscreenlocker, PAM service `kde`) and nowhere else: not
`sudo`, polkit, `su` or ssh. It is typed in the same field as the password; the
password always keeps working.

- **PAM.** `build.sh` makes a custom authselect profile, `atlasos`, based on
  `local` (every file but `password-auth` is a symlink to local's), selects it
  with the features the image already had plus `with-pin`, and fails the build
  if the profile, the lines, their order or the units are missing. `with-pin`
  adds to `password-auth`, right after `pam_unix.so ... try_first_pass`:
  `pam_succeed_if service in kde:plasmalogin` (skips the next line otherwise),
  then `pam_atlasos_pin.so` (`sufficient`), then the stock `pam_deny`; and one
  `pam_atlasos_pin.so` line in the session part. The module is C
  (`build_files/pam-pin/`, built in a Containerfile stage). pam_unix tries the
  typed text first as a password and keeps it as PAM_AUTHTOK; the module reads
  that same token (it never prompts), so there is only ever one prompt.
  `system-auth` has no PIN lines. The module also checks the service itself
  (kde or plasmalogin, else `PAM_IGNORE`), and for text that is not 4 to 8
  digits it does not call the verifier and counts nothing.
- **setcred.** The login screen calls `pam_setcred` after authenticating (the
  lock screen doesn't). pam_unix answers it with its saved failure (it saw the
  PIN as a wrong password), so the module also answers setcred: success, but
  only for a login it let in (a flag in the PAM handle), else `PAM_IGNORE`.
  Without that a correct PIN failed with "Failure setting user credentials".
  Nothing here relies on `pam_exec` or `pam_permit` returning or not returning
  `PAM_IGNORE`.
- **The PIN is not a login secret.** On a correct PIN the module clears
  PAM_AUTHTOK. plasmalogin's own file runs `pam_gnome_keyring`, `pam_kwallet5`,
  `pam_kwallet` and `pam_oo7` after `password-auth`; they would otherwise take
  the PIN for the password (a keyring or wallet protected by 4 to 8 digits), and
  with the token gone `pam_kwallet5` prompts for the password a second time.
  So `build.sh` writes `/etc/pam.d/plasmalogin` (the vendor file with one line
  added, and fails if the vendor file is not the expected shape):
  `auth [success=4 default=ignore] pam_atlasos_pin.so pinlogin` right after
  `substack password-auth`, which jumps over those four lines after a PIN login.
  After a password login they get the password as before.
- **Storage.** `/var/lib/atlasos/pin/<uid>` (root only, 0700; tmpfiles.d),
  JSON with a yescrypt hash, the count of wrong tries and a stamp (a digest of
  the user name, uid and the shadow password hash). The PIN hash is only as
  safe as the disk: without disk encryption anyone who can read the disk can
  guess a 4 to 8 digit PIN offline in moments. A PIN is weaker at rest than
  a password: only 10^4 to 10^8 values behind one yescrypt cost-8 hash, in a
  root-only store, so disk encryption matters, and `pin-setup` tells users not
  to reuse a bank-card PIN and that a longer PIN is safer. The lock screen runs as the user
  and can't read the store, so the check goes through `atlasos-pin.socket`
  (`/run/atlasos/pin.sock`, Accept=yes, no start rate limit, 2 connections per
  user), which starts a sandboxed `atlasos-pin@.service` (`pin-daemon`, root,
  ProtectSystem=strict, only the PIN folder writable, no network, 10 s limit)
  per question. It reads SO_PEERCRED: root may ask about any user, everyone else
  only about their own. Requests: `verify <uid> <name> <pin>` (the name must be what
  `getpwuid` gives for the uid, so an alias account with the same uid can't use
  another name's PIN), `status`, and `reset` (root only). The unit also has
  MemoryMax=640M (a verify peaks near 148 MB), TasksMax=8, CPUQuota=100%,
  ProtectProc=invisible, ProcSubset=pid and `~@privileged @resources`. A
  request without its newline (the client left) is never counted. The store's
  lock is held only for reading and writing the count, never while hashing.
- **Lockout.** Wrong PINs accumulate (each is logged to the journal as
  `atlasos-pin: wrong PIN for uid ...`); a correct PIN does not reduce the
  count. After 5, `verify` answers "locked" without checking, and the lock
  screen shows "Too many wrong PINs. Use your password." (not the login screen,
  which would show which names have a PIN). Only a session opened at the login screen
  clears the count: the module's `open_session` hook acts only when PAM_SERVICE
  is exactly `plasmalogin` (never the lock screen, `kde`) and resets when the
  session was not opened by a PIN login. Auto-login goes through its own
  service, `plasmalogin-autologin` (checked in the VM), which has no PIN line,
  so it leaves the count alone. A user with an all-digit password who
  mistypes it counts as a wrong PIN too.
- **Lifetime cap.** A second count, wrong PINs since the PIN was set
  (`life`, with `life_at` in the record), is not cleared by a password sign-in
  or a correct PIN; it falls by one per full day (at most 7 credited per try, and the
  clock going backwards credits nothing). At 20 the PIN is retired for good (a
  latch, `retired: true`; decay never undoes it):
  `verify` refuses as for "locked" (same dummy hash), `status` answers
  "retired", the daemon logs it (uid and count), and `pin-setup` says so and
  offers a new PIN. `pin-admin set` clears it. Records without the fields count
  as 0.
- **When a PIN stops working.** It is refused for an account whose password is
  locked (`passwd -l`, a `!` or `*` hash) or empty (`pin-daemon` answers
  `deny`; `pin-admin set` refuses). When the stamp no longer matches (the
  password was changed, or the uid went to another user), the entry is deleted
  and the PIN is gone: set it again. With no PIN, a locked PIN, a refused
  account or an unknown user, the daemon still hashes a dummy, so the answer
  takes as long as a real check.
- **SELinux.** `selinux/atlasos_pin.te` gives the daemon its own domain
  (`atlasos_pin_t`, its socket `atlasos_pin_var_run_t`, the store
  `atlasos_pin_var_lib_t`) and lets the login screen's domain (`xdm_t`, where
  plasmalogin runs PAM, and so the module) connect to it; the lock screen's
  `unconfined_t` is already allowed. The unit has `NoNewPrivileges=yes`, which
  blocks the transition into `atlasos_pin_t` unless the policy has
  `init_nnp_daemon_domain(atlasos_pin_t)` (it does; without it the daemon ran as
  `init_t`). The Containerfile's `selinux-policy` stage compiles it and
  `build.sh` installs it with `semodule -i`; the module store is under
  `/etc/selinux/targeted/active` (store-root is /etc/selinux), which a bootc
  upgrade replaces with the new image's, unless someone changed it locally (for
  example `semanage` or `setsebool -P`). `atlasos_pin_t` is enforcing: it ran
  permissive through VM pass 2, where its only denial was yescrypt mapping a
  huge page (now allowed). After a change to the daemon, check
  `ausearch -m avc -ts boot -c pin-daemon`: a denial ends a verify with no
  answer, so the PIN fails and the password still works.
- **Setting it.** `pin-admin set|remove` runs through pkexec under the polkit
  action `org.atlasos.pin.manage` (`auth_self`: the user confirms with their
  own password), acts only for PKEXEC_UID and reads the PIN from stdin.
  It refuses PINs that are not 4 to 8 digits, one repeated digit, or a straight
  run (1234, 4321). `pin-admin status` needs no pkexec. The user-facing pieces
  are `pin-setup` (the "Set Up PIN" launcher entry), `pin-prompt` (the
  window where the PIN is typed twice, fields labelled PIN; GTK 4 through
  PyGObject, which `build.sh` checks is there; kdialog's `--password` is only
  the fallback when no window can be shown, because its field says "Password"),
  and `telamon pin set|remove|status`. The polkit prompt that follows asks for
  the account password on purpose: it confirms the user, it is not the PIN.
- **What the screens say.** The PAM prompt (pam_unix's "Password: ") is shown
  by neither greeter: both draw a fixed placeholder in QML and answer PAM's
  conversation with the text typed. So no PAM module or option can relabel the
  field. The lock screen's placeholder is patched in `build.sh` to "Password or
  PIN" (MainBlock.qml; the build fails if the line moves). The login screen's
  is in `plasma-login-greeter`'s compiled QML, so the image rebuilds
  plasma-login-manager with a patch (see "Patched login screen"): "Password or
  PIN" when `/etc/authselect/authselect.conf` lists `with-pin`, else "Password".
- **First login.** `/etc/xdg/autostart/atlasos-pin-setup.desktop` runs
  `pin-setup --first-login`: once the first-run wizard is done, a user without
  a PIN is asked once; any answer writes
  `~/.local/state/atlasos/pin-setup-done`. It waits for the fingerprint
  question, any other kdialog and Settings first, so two dialogs never
  show at once.
- **KWallet.** After a PIN login the keyring modules are skipped (above), so
  KWallet asks for the password once, itself: the wallet opens with the real
  password, and a PIN is not that. Typing the password at the login screen once
  avoids it. Tell users this; there is no way around it short of storing the
  wallet's key, which a PIN of 4 digits would not protect.
- **Testing.** The tools use fixed paths (no overrides, as they run as root);
  a test that needs others patches `pinlib.STORE`, `SOCKET` and `SHADOW`. The
  PAM stack can be tried in a container from the image with a small libpam
  conversation program (counting prompts; call `pam_authenticate`,
  `pam_setcred`, `pam_open_session`): run `pin-daemon` on a socket with
  `systemd-socket-activate --inetd -a -l /run/atlasos/pin.sock
  /usr/libexec/telamon/pin-daemon`, then authenticate with service `kde`
  (as the user), `plasmalogin` (as root) and `sshd` or `sudo`. A probe module
  placed in place of the wallet lines shows what they would be given.
  SELinux and the real greeters are not covered that way.

## NVIDIA

`atlasos-nvidia` (`Containerfile.nvidia`, `just build-nvidia`) is the Telamon OS
image plus NVIDIA's driver from RPM Fusion's NVIDIA repository (the one Fedora
ships disabled). It uses NVIDIA's open kernel modules, so it supports GeForce
GTX 16 and RTX 20 series cards and newer; older NVIDIA cards stay on the main
image with nouveau.

- **Kernel modules:** built in a throwaway stage with `akmods` for exactly the
  image's kernel (headers from Koji), then signed with the Telamon OS module key
  so they load with Secure Boot on. The image has no compilers and no akmods.
- **Secure Boot:** the firmware must trust the key once, and it is a dialog,
  not a terminal step. At login, when an NVIDIA display device is present,
  Secure Boot is on and the key is not enrolled, `nvidia-key-setup
  --first-login` (XDG autostart) asks "Set Up Now / Not Now" (Not Now asks
  again at the next login). "Set Up Now" runs `pkexec nvidia-enroll-key
  --new-code` (polkit action `org.atlasos.nvidia.enroll-key`,
  `auth_admin`), which makes a random 8-digit code, sets it as the
  one-time password (piped to mokutil), and prints it;
  the dialog shows it with the blue-screen steps (Enroll MOK, Continue, Yes,
  type the code, Reboot) and offers Restart Now. The launcher entry "NVIDIA
  Driver Setup" runs the same dialog by hand (it also offers a new code
  after "I Lost the Code"). A request made this boot is marked in
  `/run/atlasos-nvidia-key-pending` (root-owned, for every user, gone at the
  next boot like an unfinished request). The helper runs one at a time
  (flock) and replaces only its own pending request: one for another key,
  queued by hand, makes it stop with a message. `--new-code` also
  sets MokTimeout to 300, so the blue screen's "Press any key" waits five
  minutes instead of 10 seconds (and still boots on by itself); a missed
  screen drops the request, so a later boot with the key still missing asks
  again. Tested end to end in the Secure Boot VM: code, restart, the six
  steps, and `mokutil --test-key` then reports the key enrolled, for a normal
  user too (MokListRT is world-readable). Accepted: the code is in kdialog's
  command line while it is shown; it only confirms someone at the keyboard
  at boot and can only enrol this one certificate. MokAuth (its hash) is
  root-only. From a terminal,
  `sudo /usr/libexec/telamon/nvidia-enroll-key` still works (it asks for the
  password itself). With Secure Boot off nothing is needed.
- **Also in it:** CUDA's driver libraries, VA-API video decoding
  (`libva-nvidia-driver`), the suspend/resume services, and NVIDIA's container
  toolkit (`podman run --device nvidia.com/gpu=all ...`).
- **Kernel arguments** (`/usr/lib/bootc/kargs.d/10-atlasos-nvidia.toml`):
  nouveau blacklisted (initramfs too), `nvidia-drm.modeset=1`.
- **The signing key:** the private key is `secrets/nvidia-signing.key`
  (gitignored, kept out of `build/` so `just clean` leaves it) and, for CI,
  the `NVIDIA_SIGNING_KEY` repository secret. The public half is
  `system_files_nvidia/usr/share/telamon/nvidia/telamon-module-signing.der`.
  It is a build secret: never in an image layer. Losing it means a new key,
  and every user enrolling again.

## The rename to Telamon

AtlasOS became Telamon OS in October 2026 (the brand is "Telamon"). What moved,
what kept its old name for now, and why:

**Moved.** The image's name (`telamonos`), `os-release` (`NAME="Telamon OS"`,
`ID=telamonos`, `ID_LIKE="atlasos fedora"`, `HOME_URL=https://telamon.eterneon.net`,
`DEFAULT_HOSTNAME=telamon`, `LOGO=telamon`), the packages (`telamon-*`, with
`Obsoletes:` and `Provides:` of `atlas-*`), `/usr/libexec/telamon`,
`/usr/share/telamon` (`telamon.just`, `image-age.jq`, the NVIDIA module key),
`/etc/telamon` (setup markers), `/etc/xdg/telamonrc`,
`/etc/xdg/telamon-launcher/pinned.list`, the `telamon` command (`atlas` is a
link to it), the Global Themes `org.telamon.desktop` and
`org.telamon.dark.desktop`, the colour schemes `TelamonLight` and `TelamonDark`,
the Kvantum themes `Telamon`, `TelamonDark`, `TelamonSolid` and
`TelamonDarkSolid`, the Aurorae themes `Telamon-Light` and `Telamon-Dark`, the
Plasma style `telamon`, the plasmoids `org.telamon.menu`, `.appmenu` and
`.dockseparator`, the icon `telamon`, the wallpapers `Telamon` and
`Telamon-Login`, the Plymouth theme `telamon`, the Ghostty themes
`Telamon Light` and `Telamon Dark`, the firewall zone `Telamon`, and the desktop
IDs of the apps (`net.eterneon.telamon.*`) in the default apps, the launcher's
pins and the dock's layout. The apps are built from the contexts
`telamon-<app>`, and the image's labels are `net.eterneon.telamon.<app>.revision`
and `org.telamon.base-image` / `org.telamon.built`.

**Kept, because renaming would reset what a user chose or touch security
policy, and nothing outside the image reads the name:**
the systemd units (`atlasos-update-stage.timer`, `atlasos-pin.socket`,
`atlasos-kconf-update.service`, ...: a timer a user turned off must stay off),
the kconf_update and Plasma update scripts' file names and `Id`s
(`atlasos.upd`, `atlasos-2026*`: a new name would run them again for everyone),
the PIN's PAM module (`pam_atlasos_pin`), authselect profile (`custom/atlasos`),
SELinux modules and types (`atlasos_pin`, `atlasos_bootc`), polkit action ids
(`org.atlasos.pin.manage`, `org.atlasos.nvidia.enroll-key`), and the state
directories `/var/lib/atlasos` (PIN hashes, bad digests) and `/run/atlasos`
(the telamon-framework crates read the same path), the greenboot script names,
the GRUB markers in `/boot/grub2/custom.cfg`, and `~/.local/state/atlasos` (the
"already asked" markers). The module signing certificate still says "AtlasOS
module signing": a new name needs a new key and every NVIDIA user enrolling it
again, so that is a decision for later. The VM test scripts keep their
`build/atlasos.qcow2` and domain names.

**Kept for one release, as hidden aliases** (the apps move to the new names
one by one, and what a user's files name has to resolve meanwhile):
`AtlasOSLight.colors` and `AtlasOSDark.colors`, the Aurorae themes
`AtlasOS-Light` and `AtlasOS-Dark`, the Global Themes `org.atlasos.desktop` and
`org.atlasos.dark.desktop` (their name says "(old name)"), the plasmoids
`org.atlasos.menu`, `.appmenu` and `.dockseparator` (`NoDisplay`), the icon
`atlasos`, the Ghostty themes `AtlasOS Light` and `AtlasOS Dark`, the firewall
zone `AtlasOS`, the commands `atlas`, `/usr/bin/atlasos-screenshot` and the
other old binaries (the packages' own links), the label `org.atlasos.base-image`
(the VPS runner's cleanup looks for it) and `org.atlasos.built`. `build.sh`
makes the copies from the new ones, so they can't differ. Remove them, the
Obsoletes and the apps' own links together, in the release after this one.

### What happens to an existing user

`system_files/usr/share/kconf_update/telamon-20261007-rename.sh` (the first
`Id` of `atlasos.upd`) runs once per user at the next Plasma login, before
KWin, the shell and `kded6` read their settings. It rewrites, in
`kdeglobals`, `kdedefaults/*`, `kwinrc`, `plasmarc`, `ksplashrc`,
`kscreenlockerrc`, `plasma-org.kde.plasma.desktop-appletsrc`, `mimeapps.list`
and Kvantum's `kvantum.kvconfig`: the Global Theme, the colour scheme, the
window decoration, the Plasma style (`name=atlasos`), the Kvantum theme, the
wallpaper paths, the plasmoid ids of the panels (`plugin=`), and every
`net.eterneon.atlas.<app>.desktop` (the dock's `launchers=`, the default apps).
It also changes the theme line of Ghostty's config, gives an autostart
override of a renamed app its new name, and renames the groups of
`kglobalshortcutsrc` (a shortcut the user changed for Monitor, Screenshot or the
menu bar toggle) unless the new group already exists. It does not touch
`AtlasOSHighContrast*`, which Settings and Setup make. Every file it changes is
copied first to `~/.local/state/telamon/migrated-from-atlasos/`, which is how
to go back to an image from before the rename (the new names mean nothing
to it): copy the files back into `~/.config`. `kvantum-sync` accepts the old
Kvantum names as well and reads `atlasrc` until there is a `telamonrc`.

The Launcher's package installs its own Plasma update script,
`telamon-20261007-launcher-button.js`, which swaps the dock button in the
panels of users who never had this migration run; after it, that script finds
nothing to do.

Test it with a throwaway `HOME` in a container (the image has
`kconf_update`): seed `~/.config` with an AtlasOS-era `kdeglobals`, Kvantum
config and appletsrc, run `/usr/libexec/kf6/kconf_update
/usr/share/kconf_update/atlasos.upd`, and diff.

### Settings replaces System Settings

Telamon Settings' `telamon-settings-systemsettings` package replaces
Fedora's `plasma-systemsettings` (`apps.sh` checks it: the old package is
gone, plasma-desktop, colord-kde and kcm-plasmalogin stay, `/usr/bin/systemsettings`
is the shim). The image's own callers open Settings directly
(`telamon-settings [--kcm kcm_x]`: the menu, the shortcuts plasmoid,
`fingerprint-setup`); anything else that runs `systemsettings <kcm>` goes
through the shim. The dock's default pin and the Launcher's list name
`net.eterneon.telamon.settings.desktop`. Existing users' pins that name
`systemsettings.desktop`, `kdesystemsettings.desktop` or
`org.kde.systemsettings.desktop` (dock `launchers=`, `favorites=`,
`favoriteApps=`, `ImportPins=`, the activity manager's favourites and the
Launcher's `pinned.list`) move over once, in
`telamon-20261007-settings-cutover.sh`; test it with
`tests/settings-cutover/run.sh [IMAGE]`. The first-login scripts wait for
`telamon-settings` or `kcmshell6` where they waited for `systemsettings`.

### The two image names

Installed computers follow `ghcr.io/eternalcoder454/atlasos:<channel>` (or
`atlasos-nvidia`), and their Updater's driver switch names the same. Every
build is therefore pushed and signed under both names, the same digest;
`promote-stable.yml` promotes both. The image accepts both under the same key
(`policy.json`, `registries.d`, `update-stage`). Moving installed computers to
`telamonos` is a later step (the Updater's, with a signed origin), and only
after they have booted an image that has the `telamonos` entries in
`policy.json`: on an older image the new name matches no entry and its default
accepts anything, so the pull wouldn't check the signature. Until then nothing
needs to change on them. The
ISOs and `/dl/*.json` keep their file names (`atlasos-44.*.iso`,
`atlasos.json`, `atlasos-nvidia.json`): the website reads them.

## Quick Settings

The tray island shows apps' status icons (StatusNotifierItems: Telamon
Updater, Claude, Discord...) and the notification bell, and, as its last
widget, where Plasma's "show hidden icons" arrow was, **Quick Settings**
(`system_files/usr/share/plasma/plasmoids/org.telamon.quicksettings`, QML).
Its popup is narrow and fixed (about 360 px): a main view and detail views
that replace it in place (a Back arrow and a title; Escape goes back).

- **Main view**: tiles for Wi-Fi, Bluetooth, Power mode and Do Not Disturb (the
  tile body switches it on or off, the power tile goes to the next mode; the
  chevron opens the detail view; active tiles are filled with the accent
  colour), a volume slider (its icon mutes) and a brightness slider (one slider
  for the built-in display; with several displays its chevron lists them), and
  a bottom row: the battery charge (only with a battery), Clipboard history and
  Settings. What the computer lacks (Bluetooth, brightness control, a battery,
  a Wi-Fi adapter: then the tile is "Network" and opens the network settings)
  is left out and the tiles that remain share the width.
- **Detail views**: Wi-Fi (networks to connect or disconnect, a password for a
  new one), Bluetooth (paired devices), Power mode (Power Saver, Balanced,
  Performance, with a check mark), Sound (the outputs as a list with a check
  mark, then every app playing sound with its own volume, mute and output
  chooser: this moves the stream, as Plasma's volume widget does) and
  Brightness (one slider for each display). Each ends with one "... settings"
  link to its page of Telamon Settings (`telamon-settings --page
  network|devices|power|sound|displays`; the ids are in
  `crates/settings-registry/src/pages.rs` of atlasos-settings); the gear in the
  bottom row opens Telamon Settings itself.
- Do Not Disturb is the same switch the notification bell's popup has
  (`org.kde.notificationmanager`); it is left out when plasmashell's
  notification server is not there.

It adds no backend: the models and handlers are Plasma's own (plasma-pa's
`org.kde.plasma.private.volume`, plasma-nm's `org.kde.plasma.networkmanagement`,
BlueZ-Qt's `org.kde.bluezqt` and `org.kde.plasma.private.bluetooth`,
`org.kde.plasma.private.batterymonitor` and `.battery`,
`org.kde.plasma.private.brightnesscontrolplugin`, `org.kde.notificationmanager`), so it follows them across
Plasma updates (`build.sh` checks the modules exist). The widget's state
objects (`SoundState.qml`, `NetworkState.qml`...) wrap those modules; the
views only draw. Tab, Space and Enter work and every control has an accessible name (a
screen reader hears "Volume of Speakers", "Wi-Fi networks"...). A Wi-Fi
password typed here goes to NetworkManager through plasma-nm's handler and is
neither logged nor kept; a company (802.1X) network is left to NetworkManager's
own prompt.

**What the tray keeps and what moved** (decided here, not by Plasma's defaults):

- *Volume, Network, Bluetooth, Battery and Brightness* are in Quick Settings.
- *Notifications*: the bell stays in the tray. Its widget draws the
  notification popups (without it no notification shows), so it has to be
  loaded, and "show all entries" below shows it. Its popup has the history; Quick Settings also has a Do Not Disturb tile.
- *Microphone in use*: the Volume widget used to start Plasma's microphone
  indicator. Quick Settings starts it (`MicrophoneIndicator.init()`), so a
  "Microphone" icon is in the tray, as an app status icon, exactly while an
  app records. (The camera indicator widget is off; see the gaps below.)
- *Clipboard*: the widget is off, but Plasma 6.7 has no separate Klipper: the
  clipboard history, Meta+V and the `org.kde.klipper` D-Bus service (the app
  menu's Edit > Clipboard History) run while something has loaded
  `org.kde.plasma.private.clipboard`, which the widget did. Quick Settings
  loads it (`KlipperInterface`), so all three keep working, and its bottom row
  has a "Clipboard history" button (the same menu as Meta+V).
- *Disks & Devices, media controls, keyboard layout, Caps Lock indicator,
  input method, Vault, print manager, disk quota, weather, trash, Kate
  sessions, display configuration, camera indicator, KDE Connect's widget* are
  off: only their own window or tray UI goes (what runs in the background,
  such as the pairing agent, the print and volume key services and the
  keyboard layout shortcuts, are separate services and stay). Apps' own icons
  (KDE Connect's, Telamon Updater's) stay. There is no replacement yet for the
  media controls, the keyboard layout indicator, the removable-drive popup and
  the camera-in-use indicator.
- *Show all entries* is on (`showAllItems`): every icon is in the tray itself,
  so there is no overflow popup and no arrow, and an app icon is never hidden
  out of reach. A widget Plasma enables by default later would then be shown
  at once, so `build.sh` fails when a widget that can go in the tray is missing from
  the new-user layout's list or the update script's list below.

New users get this from the layout
(`system_files/usr/share/plasma/look-and-feel/org.telamon.desktop/contents/layouts/org.kde.plasma.desktop-layout.js`,
copied to the dark theme by `build.sh`). Existing users get it from the Plasma
update `telamon-20261008-quick-settings.js` (the `Id` is the file name; it runs
once per user at the next Plasma start, after the islands update): in the right
island of the menu bar (a right-aligned top "fit" panel with a system tray and
no Quick Settings, on a screen with the Telamon OS Menu) it adds the widget at the
end of the panel, turns the widgets above off (and records them as known so
Plasma does not turn them back on), turns "show all entries" on, and keeps
everything else: the app icons they turned off, the ones they showed or hid
(hidden ones are now shown), plasmoids they added to the tray, other widgets in
the panel. It adds the widget first, so if that fails the tray is not touched
and the next start tries again. A full-width bar of the user's own is left
alone. Test it with `[OUT=dir] tests/quick-settings/run.sh [IMAGE]`: a real
plasmashell on a virtual KWin in a container is started on sample homes (an
existing user, one whose update already ran, the one-piece bar of an older
image, a user's own bar) and the panel config it writes is checked.

Test the widget itself with `tests/quick-settings/widget/run.sh [IMAGE]`: its
QML runs under Qt Test (no GPU or compositor) against PipeWire with two null
outputs and two playing apps (it moves a stream between the outputs from the
keyboard, sets an app's volume and mute with the mouse, then asks PulseAudio),
mocked NetworkManager (connecting, a password typed for a new network),
BlueZ, UPower and power-profiles-daemon, and a PowerDevil stand-in; it also
walks the controls with Tab and checks each has an accessible name, and runs
once more as a desktop (no battery, Bluetooth, brightness or Wi-Fi).

Trying it by eye, without the desktop: a container of the image with a private session
bus, PipeWire with two null sinks (`support.null-audio-sink`: two outputs and
playing apps to move between them), a virtual KWin and plasmashell, and
python-dbusmock's NetworkManager, BlueZ, UPower and power-profiles-daemon on a
private system bus plus a small PowerDevil stand-in (brightness, profiles) on
the session bus. Run containers with `--ulimit core=0`, so a crash does not
reach the host's core dumps. KWin's screenshot interface needs the host's GPU
render node (`--device /dev/dri/renderD128`) to render; the software
compositor cancels every screenshot.

## Switching an existing Fedora Atomic install

```sh
sudo bootc switch ghcr.io/eternalcoder454/telamonos:latest
```

## Layout

| Path | What it is |
|---|---|
| `Containerfile` | The image: stages for branding, the Telamon apps, the patched KIO and the restyled wizard (RPMs), then Kinoite plus the scripts below, one build step each so a change reruns only its step and those after it |
| `build_files/packages.sh` | Package removals and additions, the patched KIO and wizard, greenboot |
| `build_files/apps.sh` | The Telamon apps |
| `build_files/build.sh` | Services, settings, branding, initramfs |
| `build_files/version.sh` | The image's version in os-release (last: it changes daily) |
| `build_files/kio/` | The KIO crash fix: rebuilds Fedora's `kf6-kio` with one patch |
| `build_files/login/` | The login screen's "Password or PIN" placeholder: rebuilds Fedora's `plasma-login-manager` with one patch |
| `build_files/drop-build-deps.sh` | Runs a builder stage's build, then removes its build dependencies |
| `Containerfile.nvidia`, `build_files/nvidia/`, `system_files_nvidia/` | The `telamonos-nvidia` image (and `atlasos-nvidia`) |
| `system_files/usr/lib/greenboot/` | The boot health checks and their red/green hooks |
| `system_files/` | Files copied as-is into the image (`/etc`, `/usr`), including the two Global Themes, their colour schemes, the menu bar and dock layout and the launcher |
| `branding/source/` | The Telamon OS logo SVGs (copies, never edited) |
| `branding/cursors/` | Bibata cursors, as a tarball with its license |
| `branding/wallpaper.jpg`, `wallpaper-dark.jpg` | The wallpaper and its night picture for Dark, 4K copies of the originals; the light one also blurred for the login screen |
| `branding/render.sh` | Renders icons, splash images and wallpapers (plain and blurred) at build time |
| `disk_config/` | bootc-image-builder configs, and the kickstart for the stock baseline VM |
| `scripts/` | `bib.sh` (disk images), `vm.sh`, `vmctl.py` and `vmswitch.py` (test VMs) |
| `docs/` | Test reports (phase 1, updates, privacy) and the README's screenshots |
| `.github/workflows/build.yml` | Builds, rechunks, pushes and signs testing and beta |
| `.github/workflows/promote-stable.yml` | Weekly: testing becomes stable, then tag and release |
| `scripts/release-notes.sh` | Writes a stable release's notes from the git log |
| `scripts/plasma-style.py` | Writes the Telamon OS Plasma style's SVGs (dock tasks, panels, popups, tooltips, buttons, fields, sliders, switches, scrollbars, tabs, items) |

## Building and testing locally

Needs Podman, just, libvirt with OVMF, `qemu-img`, `uv` and ImageMagick.

The Telamon apps' shared base, telamon-framework (Telamon.Ui and its fonts), and the
Telamon apps (Telamon Updater with telamon-system-helper, Telamon Monitor, Telamon
Notepad, Telamon Settings, Telamon Setup, Telamon Explorer (Files, the default file manager), Telamon Archive (replaces Ark), Telamon Launcher (replaces Andromeda), Telamon Screenshot (Meta+Shift+S; Spectacle keeps Print), Telamon Store (beside Discover, which stays the default for Flatpak and RPM links), and the Installer's first-boot apps files) come from their own repositories, each passed to `podman build` as a
named build context: `telamon-framework`, `telamon-updater`, `telamon-monitor`, `telamon-notepad`,
`telamon-settings`, `telamon-wizard`, `telamon-store`, `telamon-explorer`, `telamon-archive`, `telamon-launcher`, `telamon-screenshot` and `telamon-installer` (no RPM: its `firstboot/` is bound into the
`apps.sh` step, which runs `install.sh`). telamon-framework's `framework` stage makes the RPMs; the app
stages build against them (`TELAMON_LOCAL_RPMS`), and `apps.sh` installs them
before the apps. Telamon.Ui changes go there, never into an app.

### App pins

Which commit of each goes in the image is pinned in `telamon-apps.lock`, one
line per app: name, repository, the full commit, and its release tag when it
has one. An app's new version reaches the image only through a commit here
that moves its pin, never because its main branch moved, so a new app or
framework release doesn't make a new image by itself, and every image says
exactly what it holds.

- `just build` fetches each pinned commit into `build/pinned/<name>` (reused
  while it still is the pin) and builds from there. To build a local checkout
  instead while working on an app, point `TELAMON_FRAMEWORK_SRC`,
  `TELAMON_UPDATER_SRC`, `TELAMON_MONITOR_SRC`, `TELAMON_NOTEPAD_SRC`, `TELAMON_SETTINGS_SRC`, `TELAMON_WIZARD_SRC`, `TELAMON_STORE_SRC`, `TELAMON_EXPLORER_SRC`, `TELAMON_ARCHIVE_SRC`, `TELAMON_LAUNCHER_SRC`, `TELAMON_SCREENSHOT_SRC` or `TELAMON_INSTALLER_SRC` at it.
- Each build records the commits in the `net.eterneon.telamon.<name>.revision`
  labels, so a build from a local checkout can't pass for a pinned one.
- `just pins` lists the pins and checks each: it must be on its repository's
  default branch (a commit that only exists in a fork can still be fetched
  through the parent by its hash) and match its release tag.
- `just pins-update [name]` moves pins forward to each app's newest release
  (or its main branch's head for an app with no releases), lists the commits
  each brings, and refuses to move a pin back or sideways. Build, VM-test and
  commit `telamon-apps.lock` after.
- The "Update Telamon app pins" workflow does the same daily on the
  `pins/update` branch and opens a pull request with the commit lists; its
  test build runs from there. Merging it is what puts the new apps in
  `testing`. It needs an `ATLAS_PINS_TOKEN` secret or the "Allow GitHub
  Actions to create and approve pull requests" setting (see the workflow).
- `scripts/telamon-pins.py` does the work; `set --force` exists only for an
  app that rewrote its history so the old pin is gone.

| Command | Does |
|---|---|
| `just build` | Build `localhost/telamonos:latest` with rootless Podman |
| `just pins` | List the Telamon app pins and check them |
| `just pins-update [name]` | Move the pins forward to each app's newest version |
| `just build-nvidia` | Build `localhost/telamonos-nvidia:latest` on top of it (needs the module signing key) |
| `just qcow2` | VM disk `build/atlasos.qcow2` (bootc-image-builder; **sudo**) |
| `just iso` | Live installer ISO `build/atlasos.iso` of the published `:stable`, made with Telamon Installer (see below) |
| `just iso-local` | The same from the local `just build` |
| `just iso-anaconda` | The old Anaconda installer ISO `build/atlasos.iso` (bootc-image-builder; **sudo**) |
| `just vm` | Boot the qcow2 in libvirt: UEFI, serial console |
| `just vm-stop` | Stop it |
| `just vm-update` | Without sudo: the qcow2 updated to the latest `just build`, as `build/vm/updated/atlasos-latest.qcow2` |
| `just mem [disk]` | Stock Kinoite vs Telamon OS memory and services, 8 GB VMs |
| `just check` | Lint the Justfile and scripts |
| `just sbom [tag] [dir]` | SBOM and vulnerability report of the built image into `build/sbom` (syft, grype) |

`just iso` runs `iso/make-iso.sh` from the Telamon Installer repository,
`../AtlasOS Installer` (the folder's name until the repositories are
renamed) or `$TELAMON_INSTALLER_SRC`, without root. It builds
the installer in that repository's dev container and boots into it
full-screen. Give it a tag and a name to change the image, such as
`just iso latest atlasos-nvidia` (the ISO's image names are the old ones for now). The image goes on the ISO, and is
installed, as `ghcr.io/eternalcoder454/<name>:stable`, which the installed
system then follows. A published image is embedded with ghcr.io's own
layers, so the first update downloads only what changed; a `just iso-local`
image matches nothing there, so its first update downloads all of it.

Everything generated goes in `build/`, which is gitignored: images, VM disks,
the dnf cache, reports.

VMs run in the system libvirt (`qemu:///system`), so they show in
virt-manager. You need to be in the `libvirt` group, and libvirt's `qemu`
user must be able to pass through your home folder to reach `build/`; the
scripts check, and print the fix (`setfacl -m u:qemu:x ~`) if not. Each boot
runs on a throwaway overlay, so the disk images in `build/` never change. The
VM user is `atlas`; its password is generated into `build/vm-password` on
first use.

`just mem` installs stock Kinoite 44 once, unattended, from
`~/VMs/Fedora-Kinoite-ostree-x86_64-44-1.7.iso` (set `KINOITE_ISO` for
another), then boots each system in turn with 8 GB of RAM, logs in on the
serial console, switches on autologin, waits two minutes after Plasma starts,
and records `free`, running services and the largest processes. Reports and
screenshots go to `build/mem/<date>/`. Give it another disk to measure, such
as `just mem build/vm/updated/atlasos-latest.qcow2`.

`just qcow2` needs root once. After that, `just vm-update` tests new builds
without it: it boots the qcow2 through a copy-on-write disk with the image
shared in over virtiofs, runs `bootc switch` to it, and powers off. That disk
can't `bootc upgrade` afterwards, since its image source was the share.

## CI

`.github/workflows/build.yml` runs on pushes to `main` and `beta`, on tags
and pull requests (build only), daily, and by hand. Builds of `main` and tags
run on the self-hosted runner on the VPS while it is online, everything else
on GitHub's runners; [CI.md](CI.md) has the routing, the caches and build
times, and [ci/vps-runner](ci/vps-runner/README.md) the runner's setup. It checks out the
commits pinned in `telamon-apps.lock` (see [App pins](#app-pins)), after
`scripts/telamon-pins.py verify`: `EternalCoder454/atlas-framework` as the
`telamon-framework` build context (if private, with a token in the
`ATLAS_FRAMEWORK_TOKEN` secret), `EternalCoder454/atlasos-updater` as the
`telamon-updater` one (if private, with a token in `ATLAS_UPDATER_TOKEN`),
`EternalCoder454/atlasos-monitor` as `telamon-monitor`, and
`EternalCoder454/atlasos-notepad` as `telamon-notepad`,
`EternalCoder454/atlasos-settings` as `telamon-settings`, and
`EternalCoder454/atlasos-wizard` as `telamon-wizard`,
`EternalCoder454/atlasos-store` as `telamon-store`,
`EternalCoder454/atlasos-explorer` as `telamon-explorer`,
`EternalCoder454/atlasos-archive` as `telamon-archive`,
`EternalCoder454/atlasos-launcher` as `telamon-launcher`, and
`EternalCoder454/atlasos-installer` as `telamon-installer`.

- `main` publishes `testing`; `beta` publishes `beta`.
- The daily run rebuilds `main` only (GitHub runs schedules on the default
  branch), and skips the build when the published `testing` image already has
  this commit, the same Telamon app commits and the current Kinoite digest.
  GitHub pauses schedules in repos with no activity for 60 days.
- `promote-stable.yml` runs weekly (Saturday) and by hand: `skopeo copy --all`
  of the `testing` image, by digest, to `stable`, `latest`, `44` and
  `44.YYYYMMDD-N`; then the release job (the only one with `contents: write`)
  creates the tag and the release, or promotes the testing build's
  pre-release. Nothing happens if `stable` already has that digest, and an
  existing stable release is left as it is.
- After pushing, the build job builds `atlasos-nvidia` on the image it just
  built (the local copy, which has the same files and labels as the pushed
  one and shares its cached layers), rechunks, pushes it with the same tags
  and signs it. It needs the `NVIDIA_SIGNING_KEY` secret (the contents of
  `secrets/nvidia-signing.key`); without it the job only leaves a notice.
  Pull requests skip it.
  `promote-stable.yml` promotes `atlasos-nvidia:testing` the same way.
- dnf's downloads are cached between runs, keyed by ISO week (on the VPS,
  kept on its disk with Podman's layer cache and the Rust build cache).
- Images are rechunked before pushing, so updates download only what changed
  (see [Update size](#update-size)).
  Their layers are zstd (level 7, from a pinned skopeo; see `just rechunk`),
  12% smaller than gzip and quicker to unpack. bootc and rpm-ostree read
  plain zstd layers (VM-checked 2026-10-03: `bootc switch`, `bootc upgrade`
  reusing unchanged layers, and `rpm-ostree rebase`); zstd:chunked is not
  used. The first zstd build changes
  every layer's digest, so every install downloads that update whole (about
  2.7 GB), once.
- Images are signed with cosign. The private key is `secrets/cosign.key`
  here (gitignored, no password) and the `SIGNING_SECRET` repository secret
  in CI; the public half is `cosign.pub`, which the image ships as
  `/etc/pki/containers/telamon.pub`. With `cosign.pub` in the repo, a push
  build fails before pushing when the secret is empty or holds a key that
  isn't `cosign.pub`'s, and after signing CI verifies the signature against
  `cosign.pub` once more. A
  signature belongs to a digest, so one signature covers every tag of a
  promoted image; the promote workflow signs it again.
- The image accepts `ghcr.io/eternalcoder454/telamonos`, `telamonos-nvidia`
  and the old `atlasos` and `atlasos-nvidia` only with that signature (`/etc/containers/policy.json`, written by
  build.sh, and `/etc/containers/registries.d/telamon.yaml`, key `/etc/pki/containers/telamon.pub`); bootc,
  rpm-ostree and Podman all check it, from the first signed image an install
  runs, even with an `ostree-unverified-registry` origin (VM-checked: a
  plain `bootc upgrade` refused a bad signature). `update-stage` then records
  it in the origin: one `bootc switch --enforce-container-sigpolicy`
  (`rpm-ostree rebase ostree-image-signed:...` with local packages) to the
  same image. Never push an unsigned image to these repositories: every
  install on a signed image refuses it.
  To change the key: `cosign generate-key-pair` (the cosign container
  works: `ghcr.io/sigstore/cosign/cosign`), ship the new public key as a
  second file in the policy's `keyPaths` (build.sh) in images still signed
  with the old key, and switch `cosign.pub` and the secret only once
  installs have had that for a while.
- Every build also makes an SBOM and a vulnerability report (`just sbom`:
  syft and grype from their pinned container images), kept as the run's
  `sbom-<tag>` artifact; for a pushed image the SBOM is also a signed
  attestation on the registry (`cosign download attestation`). The build
  fails before the push on a Critical vulnerability with a fix available
  (CI.md, "SBOM and vulnerability gate"; ignore list: `.grype.yaml`).

## Window title bars (Aurorae)

Rounded-square caption buttons (26 px, 7 px corners, 10 px apart, tinted at rest,
accent on hover, red close) come from two Aurorae themes,
`system_files/usr/share/aurorae/themes/Telamon-Light` and `Telamon-Dark`
(theme ids `__aurorae__svg__Telamon-Light` / `-Dark`, `library=org.kde.kwin.aurorae`),
selected in `/etc/xdg/kwinrc` and each look-and-feel's `defaults`. The files are
generated: change sizes or colours in `scripts/gen-aurorae-themes.py`, run it, and
commit the output. Title bar colours are the schemes' `[Colors:Header]` colours.
`atlasos-20261003-aurorae.sh` (kconf_update) moves users still on Breeze.

## Application style (Kvantum)

Qt and KDE apps (Dolphin, System Settings, Discover...) use the Kvantum widget
style (`widgetStyle=kvantum`: `/etc/xdg/kdeglobals`, the look-and-feel
`defaults`, and `atlasos-20261003-kvantum.sh` for users still on Breeze) with
the Telamon OS themes in `system_files/usr/share/Kvantum/`: `Telamon OS`,
`TelamonDark`, and `TelamonSolid` / `TelamonDarkSolid` (no translucency or
blur). The look is Telamon.Ui 1.4.0's: 4 px corners on buttons, fields,
tool buttons and selections (6 px while a button is pressed), 6 px cards, menus
and tooltips, grey hover and press, an accent cell for the selected tab; no
pills. The themes live in `/usr`, so an image update changes them for every
user and apps pick them up when restarted: no kconf_update is needed. The `opaque=` list in each `.kvconfig` keeps browsers, video players,
editors, games, terminals and the Telamon apps opaque.

The themes are generated: edit colours and sizes in
`scripts/gen-kvantum-themes.py` (colours come from the Telamon OS colour schemes),
run `python3 scripts/gen-kvantum-themes.py`, commit the output. Splitters stay
2 px wide, near Breeze's 1 px: Dolphin's floating status bar cuts its text off
under a wider splitter (its width sum assumes Breeze's).

`/usr/libexec/telamon/kvantum-sync` writes `theme=` in
`~/.config/Kvantum/kvantum.kvconfig`: Dark when the `ColorScheme` in kdeglobals
contains "Dark" (read like the session does: `~/.config/kdeglobals`, then
`~/.config/kdedefaults/kdeglobals`, where applying a Global Theme puts it, then
`/etc/xdg`), Solid when `telamonrc` `[Appearance] Transparency` is false (the
switch the Telamon apps use). It leaves a Kvantum theme the user picked that
isn't one of ours alone. The user units `atlasos-kvantum-sync.service` and
`.path` (both enabled globally) run it at login and on any save directly in
`~/.config` or `~/.config/kdedefaults`. The path unit watches the folders, not
the files: KConfig saves by renaming a new file over the old one, and a
`PathChanged=` on the file misses some of those saves. Started by the
path unit, kvantum-sync first checks a stamp in `$XDG_RUNTIME_DIR` and stops
unless kdeglobals, kdedefaults/kdeglobals or telamonrc was saved since its last
read (other apps' saves cost only that check); then it waits a second for a
theme switch's burst of saves to settle, and reads again (twice at most) if
one landed while it ran, since that starts nothing new. Running apps keep their style until restarted.

It keeps GTK in step too. Plasma's gtkconfig (kded) sets GTK's dark
preference, icon theme and gsettings colour scheme when kdeglobals notifies a
change of `[General] ColorScheme` or `[Icons] Theme`, and once when kded
starts. Applying a Global Theme writes both keys into `kdedefaults`, which
notifies nothing, so GTK (Brave's dark mode, GTK dialogs) kept the theme the
session started with. When `~/.config/gtk-3.0/settings.ini` disagrees with
the scheme, kvantum-sync sends gtkconfig that notification itself
(`org.kde.kconfig.notify` `ConfigChanged` on `/kdeglobals`), so gtkconfig does
the usual work. A settings.ini with no `gtk-theme-name` (GTK then draws its
light Adwaita) gets `Breeze`, which gtkconfig colours from the scheme, and the
gtkconfig module is reloaded so the name reaches xsettingsd.

To go back to Breeze: System Settings > Colors & Themes > Application Style.
