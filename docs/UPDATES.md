# Updates report

The update system and Atlas Updater: background staging, the Atlas Updater
app, channels, going back, boot health checks with automatic rollback, and
opt-in crash reports. How each part works is in the README ("Updates",
"Boot health checks and rollback"); this report says what was tested.

**Evidence** means it was built and seen working in a VM. **Inference** means
it is reasoned from documentation or code, not tested.

## Test setup

- VM `atlasos-updtest` (qemu:///system, UEFI, 8 GB, 4 CPUs, virtio GPU),
  installed from `build/atlasos.qcow2` and switched to a local registry
  (`build/vm/updtest`, shared over virtiofs) with `stable` and `testing`
  channels. `just publish <tag> <channel> <notes>` puts a built image on a
  channel with release notes; `just updtest` boots the VM.
- Screenshots of every screen on image I: `s-*.png` in the run folder.
- The app was driven through accessibility (AT-SPI, `scripts/guest/atspi.py`)
  and the screen captured with `virsh screenshot`. Screenshots are in
  `build/vm/updtest/run8/` (not committed).
- Test images, each with a newer version label than the one before:

| Tag | Version | What it adds |
|---|---|---|
| `update-e` | 44.20261020 | Atlas Updater restart fix |
| `update-f` | 44.20261021 | KCalc and a `[WM]` title bar colour (no visible effect, see below) |
| `update-g` | 44.20261022 | KCalc and a purple `[Colors:Header]` title bar (`tests/update/b`) |
| `update-h` | 44.20261023 | Atlas Updater fixes (banners, channel, accessibility) |
| `update-i` | 44.20261024 | Atlas Updater fixes (keyboard focus, crash report screens) |
| `broken` | 44.20261099-broken | a greeter that exits at once (`tests/update/broken`) |

## Results

### Staging and restarting

- Evidence: `atlasos-update-stage.service` staged update E in the background
  with no window open. Memory peak of the unit while staging: **1.3 GB**
  (`MemoryPeak`) for E, and **995 MB** for the broken image, which needed one
  new 152 kB layer (most of the cost is the ostree deploy, not the download).
- Evidence: Atlas Updater found F, G, H and I, showed their release notes,
  downloaded and staged them, and **Restart to update** restarted into each.
  Each new boot reached `boot_success=1`.
- Evidence: the updater updates itself. It is part of the image, so each new
  image brought the new Atlas Updater (H's and I's fixes were tested on the
  versions they installed).
- Evidence: a restart Plasma doesn't confirm is reported on the Updates page,
  or with a notification when the window is closed. The earlier panic in
  "Restart to update" (a Tokio timer built outside the runtime) is fixed and
  covered by a test.

### What a user sees change

- Evidence: after updating to G, KCalc is in the launcher and the active
  window's title bar is AtlasOS purple; the inactive one keeps the light
  scheme's colour.
- Evidence (the KWin finding): KWin colours title bars from the colour
  scheme's `[Colors:Header]` group. `[WM]` (`activeBackground`) is only read
  by schemes without a Header group, so image F, which changed `[WM]` in the
  scheme and in `/etc/xdg/kdeglobals`, booted with an unchanged title bar.
- Evidence: Plasma re-applies a changed scheme file at login. After the
  update, `ColorSchemeHash` in the user's `~/.config/kdeglobals` equalled the
  new file's SHA-1 and the file had been rewritten, so a scheme change in an
  image reaches existing users without a migration script.

### Going back

- Evidence: **Go back to 44.20261021** asks for an administrator password
  (polkit). Cancelling it shows "You aren't allowed to do this. Nothing was
  changed."
- Evidence: going back can be undone before the restart (**Don't go back**),
  without a second password prompt. Going back again and **Restart now**
  booted 44.20261021.
- Evidence: the next check showed "You went back from version 44.20261022"
  with **Download anyway**, and the background stager skipped that version
  ("the version this machine went back from").

### Channels

- Evidence: switching from stable to testing in the app and restarting booted
  the testing image; switching back worked the same way. Each boot reached
  `boot_success=1`.
- Evidence: the Channel page shows the new channel as soon as the switch is
  made, before the restart (it reads bootc's `spec.image`, which changes at
  once, rather than the booted image, which changes at the restart).

### Crash reports

See [PRIVACY.md](PRIVACY.md). Evidence: off collects nothing; on, a crash is
collected and announced with a notification when the window isn't active;
**Don't send** deletes the report and sends nothing; **Send** reaches the
local GlitchTip and moves the report to Sent reports; turning reports off
deletes waiting ones.

### Boot health and rollback

_Pending: broken image, shutdown during staging._

## Memory

| | |
|---|---|
| Stager while staging (`atlasos-update-stage.service` `MemoryPeak`) | 1.3 GB |
| Idle, 2 minutes after login (`just mem`) | _pending_ |

## Fixed during testing

- Atlas Updater panicked on **Restart to update** (Tokio timer outside the
  runtime).
- A modal "Restart problem" dialog was replaced by the Updates page.
- Radio rows didn't respond to the accessibility Toggle action, so a screen
  reader couldn't pick a channel.
- The Channel page showed the old channel until the restart.
- Banners ("You are up to date.") showed even when the page already said so.
- The Versions list called an update that wasn't downloaded yet "Ready to
  install"; it is now "Available" (checked headless; not in image I).
- Controls below the fold weren't scrolled into view on keyboard focus, so
  a keyboard or screen-reader user tabbing to **Send** couldn't see it.
- Sent reports always highlighted Settings in the sidebar.
- Settings said no crash server was set up after reports were turned off.
- "Crash report sent" stayed on every page until dismissed.

## Known issues

- Without autologin the health checks only exercise the greeter, so a Plasma
  session that crashes right after login isn't caught (inference, from how the
  checks work; see the README).
- The update that first introduces greenboot isn't protected by it
  (inference, README).
