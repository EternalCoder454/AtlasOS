# AtlasOS: developer notes

How AtlasOS is built, updated and tested. For what AtlasOS is and how to
install it, see the [README](README.md). Test reports are in
[docs/](docs/): [PHASE1.md](docs/PHASE1.md) (the base image),
[UPDATES.md](docs/UPDATES.md) (the update system) and
[PRIVACY.md](docs/PRIVACY.md) (what is sent and kept).

AtlasOS is a Fedora Kinoite 44 [bootc](https://bootc-dev.github.io/bootc/)
image. Images: `ghcr.io/eternalcoder454/atlasos`

| Tag | Channel | Built from |
|---|---|---|
| `testing`, `testing-44.YYYYMMDD` | Testing: built daily and on every push | `main` |
| `stable`, `latest`, `44`, `44.YYYYMMDD` | Stable: weekly | the newest testing image, copied by digest (never rebuilt) |
| `beta`, `beta-44.YYYYMMDD` | Beta | `beta` |

`ghcr.io/eternalcoder454/atlasos-nvidia` has the same tags: each AtlasOS
image plus NVIDIA's driver (see NVIDIA below).

`latest` is `stable`. The version `44.YYYYMMDD` (the build's UTC date) is the
same in the image's `org.opencontainers.image.version` label, in
`/etc/os-release` and in the tags. The `org.opencontainers.image.revision`
label is the AtlasOS commit the image was built from, and
`net.eterneon.atlas.updater.revision` the Atlas Updater commit.

## Updates

- **Staging:** `atlasos-update-stage.timer` runs `bootc upgrade --quiet`
  (`atlasos-update-stage.service`) about an hour after boot and every 6 hours
  after that, with a random delay of up to 30 minutes. It downloads and stages
  the new image and never reboots; a staged update is used at the next
  shutdown or reboot. It runs at idle CPU and disk priority, only on an
  image-based boot, with the network up, and not on a connection NetworkManager
  reports as metered. `bootc-fetch-apply-updates.timer` (which reboots) and
  `rpm-ostreed-automatic.timer` stay disabled; `build.sh` fails if they are
  enabled.
- **Notifier:** [Atlas Updater](https://github.com/EternalCoder454/atlasos-updater)
  shows what is staged and offers the restart. Discover's notifier is removed
  and its unattended updates are off; the build checks both.
- **Release notes:** every stable build gets a git tag `44.YYYYMMDD` on the
  commit it was built from and a GitHub release with that tag: the commits
  since the previous stable tag, grouped by what they touch.
  `scripts/release-notes.sh` writes them; the first stable lists the newest
  commits.
- **Atlas apps are system components.** `atlas-core` and `atlas-updater` are
  RPMs built into the image under `/usr`, so Discover (its backends here are
  Flatpak, fwupd, KNewStuff and rpm-ostree, no PackageKit) has no way to
  uninstall them, and `/etc/dnf/protected.d/atlas.conf` (from `atlas-core`)
  stops dnf removing them. The build fails without them. Root can still run
  `rpm-ostree override remove`; that is the limit on an open system. The
  tray autostart can be turned off in System Settings; background staging is
  a system timer and keeps working.

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
first entry fills look-and-feel keys of the user's AtlasOS theme that they
never set.

## Boot health checks and rollback

[greenboot](https://github.com/fedora-iot/greenboot-rs) (greenboot-rs 0.16.4,
Fedora's package, built for bootc) checks every boot and rolls a bad update
back. `greenboot-healthcheck.service` and `greenboot-set-rollback-trigger.service`
are enabled; `greenboot-default-health-checks` is **not** installed (its
repository DNS check fails offline and would roll back good updates on a
laptop without a network). `build.sh` fails if that package is present or a
unit is not enabled. `/etc/greenboot/greenboot.conf`: `GREENBOOT_MAX_BOOT_ATTEMPTS=3`.

**Checks.** Image-owned, in `/usr/lib/greenboot/check/required.d` (greenboot
reads it before `/etc/greenboot`, which users can change). Each logs one line
(`journalctl -u greenboot-healthcheck.service`) and has its own awake-time
deadline. When in doubt a check **passes**, because a false failure reboots a
healthy machine. Every check passes ("skipped") when:

- there is no rollback deployment (greenboot's `bootc rollback` fails with one,
  so a failure could only reboot in a loop: a fresh install);
- login and Plasma: first-run setup is not done (`/etc/plasma-setup-done` is
  missing, the wizard runs before the display manager, with no greeter), the
  boot isn't graphical (`systemd.unit=`, `single`, `1`-`4`, `rescue`,
  `emergency`), the default target isn't `graphical.target`, the display manager
  isn't plasmalogin or it is masked, or at the end there is no `/dev/dri/card*`.

| Check | Passes when | Waits | Limit |
|---|---|---|---|
| `10_atlasos_login.sh` | `plasmalogin.service` is active and the greeter (`/usr/libexec/plasma-login-greeter`) or a `plasmashell` (autologin) has run for 10 s | until 190 s awake | 240 s |
| `20_atlasos_plasma.sh` | with a user session: `plasmashell` and that user's `kwin_wayland` run for 10 s, and neither unit restarted twice or more (one crash is tolerated); without one: the greeter and the greeter's `kwin_wayland` run for 10 s and `plasmalogin.service` hasn't restarted twice | until 240 s awake | 300 s |
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
`/usr/libexec/atlas-system-helper record-event health-check-failed` and appends
the image digest to `/var/lib/atlasos/bad-image-digests`;
`update-stage-condition` then skips staging while the newest image on the
registry has that digest, so a rolled-back update isn't downloaded again (a
newer image has a new digest), and Atlas Updater shows it as an update that
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
   `bootc rollback` itself to make it permanent. No AtlasOS script is needed.
4. `atlas-system-helper record-boot` then sees the rollback in the boot history.

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
`atlasos-grub-greenboot.service` (`/usr/libexec/atlasos/grub-greenboot`) runs at
every boot, after `ostree-remount` and `bootloader-update` and before greenboot:
when `grub.cfg` has no `08_greenboot.cfg` section it puts the same snippet into
`/boot/grub2/custom.cfg`, between `# BEGIN/# END atlasos-greenboot` markers
and keeping anything else in the file. GRUB sources `custom.cfg` after
`blscfg`, and bootupd never touches it. It writes nothing when the file is
already right, removes its block again when `grub.cfg` has the snippet (or the
counter would count twice), and leaves a `grub.cfg` that is not bootupd's
alone. `build.sh` also adds the final newline the RPM's snippet lacks: bootupd
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
  DrKonqi, KDE's crash reporter, which needs it. Also two wallpaper sets
  nothing depends on. (Menu Editor and Emoji Selector stay: they are part
  of `plasma-desktop`.)
- **Turned off:** Discover's unattended updates, automatic reboots for
  updates (see Updates), dnf's metadata refresh
  timer (dnf can't change an image-based system anyway), and Fedora's
  on-screen keyboard (System Settings > Keyboard > Virtual Keyboard turns it
  back on).
- **Added:** Atlas Updater (the update screen and tray, with its `atlas-core`
  helper), Flathub, Ghostty as the terminal (Ctrl+Alt+T), from the
  [scottames/ghostty](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/)
  COPR that Ghostty's install guide points to, since Fedora doesn't package
  it; Brave Origin as the browser, from
  [Brave's own RPM repository](https://brave.com/linux/) (it isn't on
  Flathub); IBM Plex Sans for the interface and JetBrains Mono for terminals
  and code. Ghostty's own "Open Ghostty Here" is in Dolphin's right-click
  menu, and Shift+F4 opens it too.
- **Kept:** Plasma, KWin, Dolphin, Discover for Flatpaks,
  NetworkManager, PipeWire, Bluetooth, CUPS printing, Flatpak, zram swap.
- **Branding:** AtlasOS boot splash, Plasma splash, launcher icon, About page,
  login screen and wallpaper; `os-release` says AtlasOS (`ID=atlasos`,
  `ID_LIKE=fedora`, `VERSION_ID=44`).
- **Windows 11 and macOS-style desktop:** a macOS-style menu bar along the
  top, with the AtlasOS menu and the active app's menus (File, Edit, View...)
  on the left and the tray and the day, date and time on the right; a dock
  along the bottom (floating, centred, as wide as its icons) with the app
  launcher, a separator (our own small `org.atlasos.dockseparator`
  plasmoid: Plasma's only draws a gap), then pinned and open apps, like
  macOS's: 48 px icons packed at a 60 px pitch on a rounded, see-through
  plate. Open apps get a short underline (accent colour for the active
  one) and a rounded tile covering the whole item on hover. All of that is
  the AtlasOS Plasma style (`system_files/usr/share/plasma/desktoptheme/atlasos/`:
  the task frames and the dock's and menu bar's background, with `plasmarc`
  copied from Breeze at build time; everything else falls back to Breeze's
  `default`). Its SVGs are generated by `scripts/plasma-style.py` for the
  dock's 60 px; change the script and rerun it rather than editing them.
  The dock is made before the menu bar, so Meta opens the dock's
  launcher (Plasma opens the first one it finds). Both bars are
  see-through, with a strong blur and a little noise behind them like
  Windows 11's acrylic (`[Effect-blur]` in `/etc/xdg/kwinrc`, which the
  menus and popups share). The launcher is Modern ([Andromeda
  Launcher](https://github.com/EliverLara/AndromedaLauncher)) or Classic
  ([Simple Application Launcher](https://github.com/HimDek/Simple-Kickoff-for-Plasma)),
  chosen in the first-run wizard; both are vendored in
  `system_files/usr/share/plasma/plasmoids/` (GPL, with an
  `ATLASOS-CHANGES.md` each), themed to AtlasOS. Window titles on the left; minimize, maximize and close on the
  right; rounded window corners with a thin outline and soft shadows;
  translucent, blurred menus with a little noise (Windows' "acrylic"); the
  IBM Plex Sans font in place of Segoe UI. All of it is Plasma's own Breeze and KWin,
  configured; nothing extra runs.
- **macOS-style login and lock screens:** the wallpaper blurred and tinted
  with the logo's ink (done once at build time, not live), with the clock
  above the avatar and password field, in AtlasOS colours and IBM Plex Sans.
- **Two themes, and only two:** AtlasOS Light (the default) and AtlasOS Dark,
  Global Themes with colour schemes taken from the logo's violets. Breeze's
  and Fedora's Global Themes, colour schemes and Plasma Styles are removed.
- **Cursors:** [Bibata Modern](https://github.com/ful1e5/Bibata_Cursor)
  (GPL-3.0, `branding/cursors/`): Ice, white, with AtlasOS Light and as the
  default everywhere else; Classic, black, with AtlasOS Dark. Breeze's
  cursors are removed (the empty `breeze-cursor-theme` package stays, since
  `plasma-integration` requires it), and a settings update moves existing
  users off them.
- **Icons:** [Dracula Icons](https://github.com/m4thewz/dracula-icons)
  (GPL-3.0, built from Tela-circle and Papirus; `branding/icon-theme/` has
  the tarball, the license and where it came from), one theme for both
  Light and Dark: its small panel icons follow the colour scheme. A
  settings update (`atlasos-20261002-dock-icons.sh`) moves existing users
  from Breeze's icons and Plasma style to Dracula and AtlasOS.

## Patched KIO

`kf6-kio` is Fedora's own package, rebuilt with one extra patch
(`build_files/kio/`): KIO's SIGTERM handler wrote to a worker after the worker
was destroyed, so closing Dolphin crashed its thumbnail workers, one coredump
each ([KDE bug 518400](https://bugs.kde.org/show_bug.cgi?id=518400)). The
Containerfile's `kio` stage downloads the source RPM of exactly the version in
the base image from Koji, adds the patch, builds with release `.atlas1`, and
`build.sh` installs those RPMs over Kinoite's. The build fails if the patch
stops applying; drop the stage once Fedora ships the fix.

## First-run setup

The wizard on first boot is Fedora's `plasma-setup`, rebuilt the same way as
KIO (the `plasma-setup` stage, `build_files/plasma-setup/`, release
`.atlas1`) with `plasma-setup-atlasos-style.patch` on top of Fedora's own
patches. Its frame is compiled into the program, which is why it is a rebuild
and not a theme. The patch:

- gives it the Atlas apps' look: pill buttons with the step forward in the
  accent colour, step dots, big bold titles, a rounder card with a shadow,
  rounded sections behind the lists, and a welcome screen with the AtlasOS
  logo and one accent button;
- turns "Dark Theme" into an **Appearance** page with AtlasOS Light and Dark
  as pictures of the desktop, applying AtlasOS's Global Themes. Fedora's patch
  applies Fedora's themes, which AtlasOS removes, so choosing Dark used to do
  nothing;
- falls back to the light wallpaper picture when a wallpaper has no dark one;
- adds the components AtlasOS's own pages use (`AtlasButton`, `ChoiceCard`,
  `DesktopPreview`, `SectionBackground` in `org.kde.plasmasetup.components`).

The **App Launcher** page is AtlasOS's own package,
`system_files/usr/share/plasma/packages/org.atlasos.plasmasetup.launcher`
(weight 11, right after Appearance). It writes `[Launcher] style=modern|classic`
to `/var/lib/atlasos-setup/choices.ini` as the wizard's `plasma-setup` user
(the folder comes from `tmpfiles.d/atlasos-setup.conf`), and the Global
Themes' layout script reads it when a user's desktop is first set up; no file
means Modern. The file stays, so accounts added later get the same launcher. To see the wizard again in a VM:
`sudo rm /etc/plasma-setup-done` and reboot.

To change the patch: clone plasma-setup at the base image's version, apply
Fedora's patches from the source RPM, then the AtlasOS patch, edit, commit
and `git format-patch -1`. The build fails when the patch no longer applies to
a new version.

## NVIDIA

`atlasos-nvidia` (`Containerfile.nvidia`, `just build-nvidia`) is the AtlasOS
image plus NVIDIA's driver from RPM Fusion's NVIDIA repository (the one Fedora
ships disabled). It uses NVIDIA's open kernel modules, so it supports GeForce
GTX 16 and RTX 20 series cards and newer; older NVIDIA cards stay on the main
image with nouveau.

- **Kernel modules:** built in a throwaway stage with `akmods` for exactly the
  image's kernel (headers from Koji), then signed with the AtlasOS module key
  so they load with Secure Boot on. The image has no compilers and no akmods.
- **Secure Boot:** the firmware must trust the key once:
  `sudo /usr/libexec/atlasos/nvidia-enroll-key`, set a one-time password,
  reboot, and choose "Enroll MOK" in the blue MOK Manager screen. With Secure
  Boot off nothing is needed.
- **Also in it:** CUDA's driver libraries, VA-API video decoding
  (`libva-nvidia-driver`), the suspend/resume services, and NVIDIA's container
  toolkit (`podman run --device nvidia.com/gpu=all ...`).
- **Kernel arguments** (`/usr/lib/bootc/kargs.d/10-atlasos-nvidia.toml`):
  nouveau blacklisted (initramfs too), `nvidia-drm.modeset=1`.
- **The signing key:** the private key is `secrets/nvidia-signing.key`
  (gitignored, kept out of `build/` so `just clean` leaves it) and, for CI,
  the `NVIDIA_SIGNING_KEY` repository secret. The public half is
  `system_files_nvidia/usr/share/atlasos/nvidia/atlasos-module-signing.der`.
  It is a build secret: never in an image layer. Losing it means a new key,
  and every user enrolling again.

## Switching an existing Fedora Atomic install

```sh
sudo bootc switch ghcr.io/eternalcoder454/atlasos:latest
```

## Layout

| Path | What it is |
|---|---|
| `Containerfile` | The image: stages for branding, the Atlas apps, the patched KIO and the restyled wizard (RPMs), then Kinoite plus `build_files/build.sh` |
| `build_files/build.sh` | Package removals, the Atlas apps, services, branding, initramfs |
| `build_files/kio/` | The KIO crash fix: rebuilds Fedora's `kf6-kio` with one patch |
| `Containerfile.nvidia`, `build_files/nvidia/`, `system_files_nvidia/` | The `atlasos-nvidia` image |
| `system_files/usr/lib/greenboot/` | The boot health checks and their red/green hooks |
| `system_files/` | Files copied as-is into the image (`/etc`, `/usr`), including the two Global Themes, their colour schemes, the menu bar and dock layout, the two launchers and the wizard's launcher page |
| `branding/source/` | The AtlasOS logo SVGs (copies, never edited) |
| `branding/cursors/`, `branding/icon-theme/` | Bibata cursors and Dracula icons, as tarballs with their licenses |
| `branding/wallpaper.jpg`, `wallpaper-dark.jpg` | The wallpaper and its night picture for Dark, 4K copies of the originals; the light one also blurred for the login screen |
| `build_files/plasma-setup/` | The first-run wizard rebuilt in AtlasOS's style (see First-run setup) |
| `branding/render.sh` | Renders icons, splash images and wallpapers (plain and blurred) at build time |
| `disk_config/` | bootc-image-builder configs, and the kickstart for the stock baseline VM |
| `scripts/` | `bib.sh` (disk images), `vm.sh`, `vmctl.py` and `vmswitch.py` (test VMs) |
| `docs/` | Test reports (phase 1, updates, privacy) and the README's screenshots |
| `.github/workflows/build.yml` | Builds, rechunks, pushes and signs testing and beta |
| `.github/workflows/promote-stable.yml` | Weekly: testing becomes stable, then tag and release |
| `scripts/release-notes.sh` | Writes a stable release's notes from the git log |
| `scripts/plasma-style.py` | Writes the AtlasOS Plasma style's SVGs (dock tasks, panel backgrounds) |

## Building and testing locally

Needs Podman, just, libvirt with OVMF, `qemu-img`, `uv` and ImageMagick.

The Atlas apps are built from a second repository, passed to `podman build` as
the named build context `atlas-updater`. `just build` uses `../Atlas Updater`
(next to this repo), or `$ATLAS_UPDATER_SRC`; it needs
`packaging/build-rpm.sh` there. Its commit goes in the
`net.eterneon.atlas.updater.revision` label.

| Command | Does |
|---|---|
| `just build` | Build `localhost/atlasos:latest` with rootless Podman |
| `just build-nvidia` | Build `localhost/atlasos-nvidia:latest` on top of it (needs the module signing key) |
| `just qcow2` | VM disk `build/atlasos.qcow2` (bootc-image-builder; **sudo**) |
| `just iso` | Installer `build/atlasos.iso` (bootc-image-builder; **sudo**) |
| `just vm` | Boot the qcow2 in libvirt: UEFI, serial console |
| `just vm-stop` | Stop it |
| `just vm-update` | Without sudo: the qcow2 updated to the latest `just build`, as `build/vm/updated/atlasos-latest.qcow2` |
| `just mem [disk]` | Stock Kinoite vs AtlasOS memory and services, 8 GB VMs |
| `just check` | Lint the Justfile and scripts |

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

`.github/workflows/build.yml` runs on pushes to `main` and `beta`, on pull
requests (build only), daily, and by hand. It checks out
`EternalCoder454/atlasos-updater` (`main`) as the `atlas-updater` build context
(if that repository is private, put a token that can read it in the
`ATLAS_UPDATER_TOKEN` secret).

- `main` publishes `testing`; `beta` publishes `beta`.
- The daily run rebuilds `main` only (GitHub runs schedules on the default
  branch), and skips the build when the published `testing` image already has
  this commit, this Atlas Updater commit and the current Kinoite digest.
  GitHub pauses schedules in repos with no activity for 60 days.
- `promote-stable.yml` runs weekly (Saturday) and by hand: `skopeo copy --all`
  of the `testing` image, by digest, to `stable`, `latest`, `44` and
  `44.YYYYMMDD`; then the release job (the only one with `contents: write`)
  creates the tag and the release. Nothing happens if `stable` already has
  that digest, and an existing release is left as it is.
- The `nvidia` job builds `atlasos-nvidia` from the image just pushed (by
  digest), rechunks, pushes it with the same tags and signs it. It needs the
  `NVIDIA_SIGNING_KEY` secret (the contents of `secrets/nvidia-signing.key`);
  without it the job only leaves a notice. Pull requests skip it.
  `promote-stable.yml` promotes `atlasos-nvidia:testing` the same way.
- dnf's downloads are cached between runs, keyed by ISO week.
- Images are rechunked before pushing, so updates download only what changed.
- Signing turns on when the `SIGNING_SECRET` repository secret is set:
  generate a key pair with `cosign generate-key-pair` (leave the password
  empty, or store it in a `COSIGN_PASSWORD` secret), store `cosign.key`'s
  contents in `SIGNING_SECRET`, and commit `cosign.pub`. A signature belongs
  to a digest, so one signature covers every tag of a promoted image; the
  promote workflow signs it again if the key is set.
