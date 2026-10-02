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
| `broken` | 44.20261099-broken | built on I: a greeter and a plasmashell that exit at once (`tests/update/broken`) |

## Results

### Staging and restarting

- Evidence: `atlasos-update-stage.service` staged update E in the background
  with no window open. Memory peak of the unit while staging: **1.3 GB**
  (`MemoryPeak`) for E; **995 MB** for the first broken image (one new 152 kB
  layer) and **751 MB** for the rebuilt one (one new 585 kB layer, staged in
  25 s). Most of the cost is the ostree deploy, not the download.
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

- Evidence (shutdown during staging): on I, the stager was started and the VM
  forced off (`virsh destroy`) 8 s later, while `bootc upgrade` was running
  (the new layer fetched, the deploy under way). The previous boot's journal
  ends inside the run, with no "Finished" line. The VM booted I, passed every
  check (`boot_success=1`), had no staged or half-made deployment, and `ostree
  fsck` found no errors in 72 commits. The next stager run staged the image
  normally.
- Evidence (broken image): the stager staged the broken image (built on I) and
  the VM restarted into it at 13:35. Each boot failed the login check ("no
  login screen or Plasma session within 180 s of boot") about 3 min 15 s in,
  and the red.d script logged it; greenboot set `boot_counter=3`, then GRUB
  counted 2, 1, 0 over the next boots. On the fourth failed boot greenboot ran
  `bootc rollback` and rebooted: at 13:49, 14 minutes after the restart, I
  booted, passed all three checks and cleared the counter. `bootc status`
  showed the broken image as the rollback entry, and its digest was in
  `/var/lib/atlasos/bad-image-digests`. (The VM was killed 26 s into that
  boot, by `just mem` running on the host at the same time; the next boot was
  I again and passed.)
- Evidence: the first broken image, which broke only the greeter, **passed**
  its checks on this VM and was kept: with autologin plasmalogin starts the
  session without a greeter, and the login check rightly counts a running
  `plasmashell`. The test image now breaks `plasmashell` too.
- But after the rollback the stager staged the same broken image again: see
  Known issues.

## Memory

| | |
|---|---|
| Stager while staging (`atlasos-update-stage.service` `MemoryPeak`) | 1.3 GB |
| Idle, 2 minutes after login, image I (`just mem`, median of 3) | 1,059 MiB used (ps_mem 816 MiB); Atlas Updater in the tray 17.6 MiB |

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

- **After a rollback, newer updates aren't staged in the background, and Atlas
  Updater doesn't offer them** (evidence, image I, bootc 1.16.13). `bootc
  upgrade --check` saves what it found on the commit the image's ostree ref
  points to: the newest image pulled. After going back, that is the rollback
  entry, not the booted one. In the VM, after `bootc rollback` from the first
  broken image to I and publishing a new image, `--check` reported the new
  digest, but `bootc status` had it as `rollback.cachedUpdate`, while
  `booted.cachedUpdate` still held the digest of the image the machine went
  back from. `update-stage-condition` reads `booted.cachedUpdate`, sees "the
  version this machine went back from" and skips every run; Atlas Updater
  (`atlas-core` `bootc.rs`, `view.rs`) reads the same field. The fix is to
  take the cached update from the entry whose commit the image ref points to.
  Worse, it can **re-stage a bad update**: after greenboot rolled the broken
  image back, the booted entry's stale value matched neither the rollback
  entry nor `bad-image-digests`, so the stager went ahead and staged the
  broken image again (the next restart would have started another four failed
  boots). It happens when the booted commit's cached update is from an older
  check, as here after an earlier "Go back"; after a single bad update the
  stale value happens to be the bad image and the stager skips it. Removing
  the rollback deployment (`rpm-ostree cleanup -r`) works around the first
  case, and that is how the staging tests above ran.
- `just mem` (and `boot`, `bench`, `check`) stop every VM the scripts made
  when they finish, `atlasos-updtest` included; don't run them during an
  update test.

- Without autologin the health checks only exercise the greeter, so a Plasma
  session that crashes right after login isn't caught (inference, from how the
  checks work; see the README).
- The update that first introduces greenboot isn't protected by it
  (inference, README).
