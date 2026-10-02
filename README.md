# AtlasOS

A minimal KDE Plasma desktop built on Fedora Kinoite 44 as a
[bootc](https://bootc-dev.github.io/bootc/) image. The aim is a desktop that
runs well on an 8 GB machine: fewer preinstalled apps, fewer background
services.

Images: `ghcr.io/eternalcoder454/atlasos`

| Tag | Built from |
|---|---|
| `latest`, `44`, `44.YYYYMMDD` | `main` |
| `beta`, `beta-44.YYYYMMDD` | `beta` |

## What differs from Kinoite

- **Removed:** KDE PIM's Akonadi server, Baloo's file indexer, Discover's
  background update notifier, KDE Connect, and the extra apps Filelight,
  KCharSelect, KFind, KHelpCenter, KJournald, KRfb, KWalletManager, KWrite,
  System Monitor, Plasma Welcome, Partition Manager, KDebugSettings and the
  Firewall app (firewalld itself stays). Firefox, Konsole, and with it
  DrKonqi, KDE's crash reporter, which needs it. Also two wallpaper sets
  nothing depends on. (Menu Editor and Emoji Selector stay: they are part
  of `plasma-desktop`.)
- **Turned off:** Discover's unattended updates, dnf's metadata refresh
  timer (dnf can't change an image-based system anyway), and Fedora's
  on-screen keyboard (System Settings > Keyboard > Virtual Keyboard turns it
  back on).
- **Added:** Ghostty as the terminal (Ctrl+Alt+T), from the
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
  on the left and the tray and the day, date and time on the right; a Windows
  11-style taskbar along the bottom, with the start button and pinned apps
  centred and "show desktop" in the corner. Both bars are see-through and
  blurred. Window titles on the left; minimize, maximize and close on the
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

## Switching an existing Fedora Atomic install

```sh
sudo bootc switch ghcr.io/eternalcoder454/atlasos:latest
```

## Layout

| Path | What it is |
|---|---|
| `Containerfile` | The image: a branding stage, then Kinoite plus `build_files/build.sh` |
| `build_files/build.sh` | Package removals, services, branding, initramfs |
| `system_files/` | Files copied as-is into the image (`/etc`, `/usr`), including the two Global Themes, their colour schemes and the taskbar layout |
| `branding/source/` | The AtlasOS logo SVGs (copies, never edited) |
| `branding/wallpaper.jpg` | The wallpaper, a 4K copy of the original; also blurred for the login screen |
| `branding/render.sh` | Renders icons, splash images and wallpapers (plain and blurred) at build time |
| `disk_config/` | bootc-image-builder configs, and the kickstart for the stock baseline VM |
| `scripts/` | `bib.sh` (disk images), `vm.sh`, `vmctl.py` and `vmswitch.py` (test VMs) |
| `docs/` | Phase reports |
| `.github/workflows/build.yml` | Builds, rechunks, pushes and signs |

## Building and testing locally

Needs Podman, just, libvirt with OVMF, `qemu-img`, `uv` and ImageMagick.

| Command | Does |
|---|---|
| `just build` | Build `localhost/atlasos:latest` with rootless Podman |
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
requests (build only), daily, and by hand.

- The daily run rebuilds `main` only (GitHub runs schedules on the default
  branch), and skips the build when the published image already has this
  commit on the current Kinoite digest. GitHub pauses schedules in repos with
  no activity for 60 days.
- dnf's downloads are cached between runs, keyed by ISO week.
- Images are rechunked before pushing, so updates download only what changed.
- Signing turns on when the `SIGNING_SECRET` repository secret is set:
  generate a key pair with `cosign generate-key-pair` (leave the password
  empty, or store it in a `COSIGN_PASSWORD` secret), store `cosign.key`'s
  contents in `SIGNING_SECRET`, and commit `cosign.pub`.

## License

Apache-2.0
