# Phase 1 report

AtlasOS Phase 1: a Fedora Kinoite 44 bootc image with a lighter app set,
AtlasOS branding, two themes, a Windows 11-style taskbar with a macOS-style
menu bar, and a macOS-style login screen.

**Evidence** means it was built and seen working in a VM (qemu:///system,
UEFI, 8 GB, 4 CPUs, virtio 3D over SPICE OpenGL). **Inference** means it is
reasoned from documentation or code, not tested.

## What was built

- Image layout from ublue's image-template: `Containerfile`,
  `build_files/build.sh`, `system_files/`, `Justfile`, and a GitHub Actions
  workflow that builds, rechunks, pushes to `ghcr.io/eternalcoder454/atlasos`
  and (optionally) signs. `main` publishes `latest`, `beta` publishes `beta`.
- Removed: KDE PIM and Akonadi, Baloo, Discover's update notifier, KDE
  Connect, Filelight, KCharSelect, KFind, KHelpCenter, KJournald, KRfb,
  KWalletManager, KWrite, System Monitor, Plasma Welcome, Partition Manager,
  KDebugSettings, the Firewall app (firewalld stays), Firefox, Konsole and
  DrKonqi, and two wallpaper sets.
- Kept as required: Menu Editor and Emoji Selector, which are part of
  `plasma-desktop` (`dnf repoquery --installed --whatrequires kmenuedit` →
  `plasma-desktop`, itself required by `plasma-workspace` and
  `plasma-setup`). They stay visible.
- Added: Ghostty 1.3.1 (scottames/ghostty COPR) as the terminal, Brave
  Origin 1.96.60 (Brave's RPM repo) as the browser, IBM Plex Sans and
  JetBrains Mono as the fonts.
- Branding: Plymouth splash, Plasma splash, launcher icon, About page,
  `os-release` (`NAME=AtlasOS`, `ID=atlasos`, `ID_LIKE=fedora`), sakura
  wallpaper (also on the first-run wizard), GRUB entry "AtlasOS 44".
- Themes: AtlasOS Light (default) and AtlasOS Dark; Breeze's and Fedora's
  Global Themes, colour schemes and Plasma Styles removed.
- Desktop: a 28 px macOS-style menu bar on top (AtlasOS menu, the active
  app's menus, tray, "Fri Oct 2  5:20 AM" clock) and a 48 px Windows
  11-style taskbar at the bottom (centred start button and pinned apps,
  show-desktop corner), both translucent and blurred.
- Login and lock screens: blurred, tinted wallpaper with the clock above the
  avatar and password field.
- `just` commands: `build`, `rechunk`, `qcow2`, `iso`, `vm`, `vm-update`,
  `vm-stop`, `mem`, `check`, `clean`.

## Test results

| Test | Result | Kind |
|---|---|---|
| Image builds; `bootc container lint` | 13 checks pass, 1 warning (`/var/cache/libdnf5` is the build's dnf cache volume mount point) | Evidence |
| Boot: GRUB "AtlasOS 44", Plymouth splash | Seen in VM screenshots | Evidence |
| First-run wizard shows the sakura wallpaper | Screenshot | Evidence |
| Login screen and lock screen in the macOS style | Screenshots | Evidence |
| Plasma loads with both bars from the image's layout | Screenshots | Evidence |
| Removed packages absent; Brave Origin, Ghostty, fonts present | `rpm -q` in the image | Evidence |
| Fonts | `fc-match sans-serif` → IBM Plex Sans, `monospace` → JetBrains Mono, in the VM | Evidence |
| Ctrl+Alt+T opens Ghostty; Ghostty is the default terminal | `pgrep`, `kreadconfig6` in the VM | Evidence |
| Dolphin: Shift+F4 opens Ghostty; "Open Ghostty Here" in the right-click menu | `pgrep`, screenshot | Evidence |
| Ghostty shell integration | Its default (`detect`), not changed | Inference: works for bash, as Ghostty documents |
| Brave Origin is the default browser | `xdg-settings get default-web-browser` and `xdg-mime query default x-scheme-handler/https` → `brave-origin.desktop` | Evidence |
| Brave Origin first run | A purchase screen; "Proceed with Origin for free on Linux" skips it, and the choice holds across restarts | Evidence (screenshots) |
| Brave Origin on Flathub | Not there; only regular Brave (`com.brave.Browser`) | Evidence (Flathub search) |
| New image as an update | `bootc switch` from the last qcow2 to the new build, then boot | Evidence |

The final image was tested as a `bootc switch` of the last bootc-image-builder
qcow2 (built from an earlier commit of this work) to the new build, not as a
fresh qcow2; `just qcow2` needs root.

## Memory

All measured in the 8 GB test VM. "Used" and "available" are from `free -m`.

### Browser, same three pages, 60 s after start

Pages: en.wikipedia.org/wiki/Linux, youtube.com, github.com/torvalds/linux.
Both browsers were started once beforehand to create their profile.

| | PSS of the browser's processes | System "used" before → after |
|---|---|---|
| Firefox (old image) | 1060 MiB, 16 processes | 1174 → 1973 MiB (+799) |
| Brave Origin | 701 MiB, 19 processes | 1352 → 1637 MiB (+285) |

Evidence, with caveats: Firefox also reopened its own two welcome tabs (five
tabs, not three), and Brave ran with `--password-store=basic` to keep the KDE
Wallet wizard (below) out of the way. PSS counts shared files too; the system
"used" change is the better guide to what a user would lose.

### Idle desktop, two minutes after Plasma starts

`just mem` (stock Kinoite 44 installed from its ISO, then AtlasOS; each in
an 8 GB VM, autologin, measured 120 s after plasmashell started). Evidence,
one run each (`build/mem/20261001-225235/`):

| | used | available | running system services |
|---|---|---|---|
| Stock Kinoite 44 | 2075 MiB | 5785 MiB | 37 |
| AtlasOS | 1097 MiB | 6762 MiB | 32 |

AtlasOS uses 978 MiB less after login. The biggest differences (RSS) are
programs AtlasOS doesn't have: Discover (355 MiB) and its notifier
(108 MiB), Plasma Welcome (340 MiB), the on-screen keyboard (164 MiB) and
KDE Connect (100 MiB). Stock also runs fwupd, passim, the Flatpak and
rpm-ostree helpers and systemd-localed, which AtlasOS doesn't start at login.
Plasma's shell itself is smaller too (326 vs 473 MiB RSS). Stock's numbers
include its first-login apps (Plasma Welcome, Discover), as a user would
see them. One run each, so differences of a few tens of MiB would be noise;
this one is not.

## Known issues

- **Brave's licence for a distro (inference).** Brave's Terms of Use give a
  "personal, non-exclusive license" and forbid altering its marks; no
  separate policy for redistributing the Linux build was found. Publishing an
  image that contains Brave Origin is redistribution. Ask Brave for written
  permission before publishing beyond personal use, or install it on first
  boot from Brave's repo instead of shipping it in the image.
- **KDE Wallet wizard with autologin (evidence in the VM).** On Brave's
  first launch in an autologin session, KDE's "create a new wallet" wizard
  appears. Password logins go through `pam_kwallet` in
  `/usr/lib/pam.d/plasmalogin`, which should create and open the wallet
  silently (inference).
- **Third-party repos.** Ghostty comes from a COPR and Brave Origin from
  Brave's repo. Both repo files are removed after install; updates arrive
  only with new AtlasOS images.
- **CI rebuilds** happen when the Kinoite base or this repo changes, not when
  Ghostty, Brave or Fedora's fonts get a new release on their own.
- **DrKonqi is gone with Konsole**, so a crashing KDE app shows no crash
  dialog. Dolphin's F4 terminal panel (Konsole's KPart) is gone too;
  Shift+F4 opens Ghostty instead.
- **Whole-file overrides of Fedora config** in `/etc/xdg` (kdeglobals and
  others) replace Fedora's versions, so a later Fedora change to those files
  won't reach AtlasOS.
- **Image size**: `/usr` is 6670 MiB with 1743 packages (stock Kinoite 44:
  6796 MiB, 1755 packages). Brave Origin alone is about 446 MB.
- The built `/etc/xdg/kdeglobals` has two `[WM]` groups (the title-bar font,
  then the colour scheme's colours appended by build.sh). KConfig merges
  them, so it is untidy rather than wrong (inference from KConfig's format).
- `branding/render.sh` uses paths relative to its arguments; it works when
  run from the Containerfile, as it is.
- Screenshots of Plasma itself are taken inside the guest with Spectacle:
  QEMU can't read a SPICE OpenGL display back, and `egl-headless` failed too.
