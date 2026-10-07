# Updates report

The update system and Telamon Updater: background staging, the Telamon Updater
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
| `update-e` | 44.20261020 | Telamon Updater restart fix |
| `update-f` | 44.20261021 | KCalc and a `[WM]` title bar colour (no visible effect, see below) |
| `update-g` | 44.20261022 | KCalc and a purple `[Colors:Header]` title bar (`tests/update/b`) |
| `update-h` | 44.20261023 | Telamon Updater fixes (banners, channel, accessibility) |
| `update-i` | 44.20261024 | Telamon Updater fixes (keyboard focus, crash report screens) |
| `update-j` | 44.20261025 | the stale check-result fix (stager and Telamon Updater) |
| `update-k`, `update-l` | 44.20261026, 44.20261027 | J with only a newer version label |
| `update-m` | 44.20261028 | the bad-update warning in Telamon Updater |
| `update-n` | 44.20261030 | Telamon Updater scheduled restart, Flatpak updates, history |
| `update-o-kconf` | 44.20261032 | the kconf_update fix, the plural fix, and a test settings update (`tests/update/kconf`) |
| `update-p` | 44.20261033 | O with only a newer version label |
| `update-q` | 44.20261034 | Telamon Updater wording in KDE's style |
| `broken` | 44.20261099-broken | a greeter and a plasmashell that exit at once (`tests/update/broken`), built on I and again on J |

## Results

### Staging and restarting

- Evidence: `atlasos-update-stage.service` staged update E in the background
  with no window open. Memory peak of the unit while staging: **1.3 GB**
  (`MemoryPeak`) for E; **995 MB** for the first broken image (one new 152 kB
  layer) and **751 MB** for the rebuilt one (one new 585 kB layer, staged in
  25 s). Most of the cost is the ostree deploy, not the download.
- Evidence: Telamon Updater found F, G, H and I, showed their release notes,
  downloaded and staged them, and **Restart to update** restarted into each.
  Each new boot reached `boot_success=1`.
- Evidence: the updater updates itself. It is part of the image, so each new
  image brought the new Telamon Updater (H's and I's fixes were tested on the
  versions they installed).
- Evidence: a restart Plasma doesn't confirm is reported on the Updates page,
  or with a notification when the window is closed. The earlier panic in
  "Restart to update" (a Tokio timer built outside the runtime) is fixed and
  covered by a test.

- Evidence (scheduled restart, N, 2026-10-02): with N staged on M, **Restart
  later…** for 17:57 saved the time (`ScheduledAt` in `atlas-updaterrc`) and
  **Cancel scheduled restart** cleared it. Scheduled again with the window
  closed, the tray process warned at 17:52 ("Restarting in 5 minutes", with
  **Restart now** and **Cancel restart**), restarted at 17:57:03 into N and
  cleared the schedule. The same on O into P (18:38).
- Evidence (background staging, N): with no window open the stager staged O
  in 35 s and exited without restarting; `MemoryPeak` **1.8 GB**. The tray
  process then sent "Update ready" with **Open Telamon Updater** and **Restart
  to update**, once for that digest.

### Release notes, apps and history

- Evidence: with `release_notes_url` pointed at the real GitHub release
  44.20261002, "What's new" showed its body as formatted Markdown; a version
  with no release shows "No release notes for this version". The URL is read
  when the app starts, so a changed `updater.toml` needs the tray restarted.
- Evidence (Flatpak, N): Flatseal rolled back one commit was listed under app
  updates and **Update apps** installed the current commit without a password
  prompt. Flatseal itself came from the Flatpak preinstall service at boot.
- Evidence (History, N): every version this machine started, with its first
  start and channel, from `/var/lib/atlas-core/history.jsonl`. The version
  that failed its checks (44.20261029) looks like the others.

### What a user sees change

- Evidence: after updating to G, KCalc is in the launcher and the active
  window's title bar is Telamon OS purple; the inactive one keeps the light
  scheme's colour.
- Evidence (the KWin finding): KWin colours title bars from the colour
  scheme's `[Colors:Header]` group. `[WM]` (`activeBackground`) is only read
  by schemes without a Header group, so image F, which changed `[WM]` in the
  scheme and in `/etc/xdg/kdeglobals`, booted with an unchanged title bar.
- Evidence: Plasma re-applies a changed scheme file at login. After the
  update, `ColorSchemeHash` in the user's `~/.config/kdeglobals` equalled the
  new file's SHA-1 and the file had been rewritten, so a scheme change in an
  image reaches existing users without a migration script.

- Evidence (the kconf_update finding, 2026-10-02): kded6 runs `kconf_update`
  only on a `.upd` file whose mtime differs from the recorded one, and ostree
  gives every file in `/usr` mtime 0, which reads as "never recorded", so
  `atlasos.upd` never ran on an installed system. `atlasos-kconf-update.service`
  (a user unit) now names the file at each Plasma login, before KWin starts.
  Updating N to O, whose `atlasos.upd` had a new test Id, ran it once at the
  first login (the unit finished 65 ms before KWin); after the update to P
  it had still run once.

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

- Evidence (ghcr.io, 2026-10-02): the first stable release. `build.yml`
  (workflow_dispatch, Telamon OS 5271896, Telamon Updater 4a9e9a1) pushed
  `testing` and `testing-44.20261002`; `promote-stable.yml` copied that digest
  (`sha256:3c350ac1…`) to `stable`, `latest`, `44` and `44.20261002`, tagged
  `44.20261002` on 5271896 and published the GitHub release, which the release
  notes URL Telamon Updater uses returns. A VM switched to
  `ghcr.io/eternalcoder454/atlasos:stable` booted it; Telamon Updater's check
  against the registry said it was up to date. Switching to testing in the app
  (admin password) staged `ghcr.io/eternalcoder454/atlasos:testing`, and after
  the restart the VM booted it with Testing shown as the channel.

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
- On image I the stager then staged the same broken image again, because it
  read a stale check result (fixed in J, below).

### After a rollback (image J)

bootc records an `upgrade --check` result as the `cachedUpdate` of the commit
the image's ostree ref points to: the image pulled last. After a rollback that
is the rollback entry, and the booted entry keeps a stale `cachedUpdate` from
an older check (bootc 1.16.13). Up to image I the stager and Telamon Updater read
the booted entry's, so after a rollback they skipped newer images, or went
ahead with a bad one. From J both take the result of the entry whose commit
is the ref's head (`/ostree/repo/refs/heads/ostree/container/image`, readable
without root), or that entry's own image when it has none.

- Evidence (on I, the bug): after `bootc rollback` from the first broken image
  and a new image published, `--check` found it, but `bootc status` had it as
  `rollback.cachedUpdate`; `booted.cachedUpdate` still held the image the
  machine went back from, and the stager skipped every run. After greenboot
  rolled the second broken image back, the stale value matched neither the
  rollback entry nor `bad-image-digests`, and the stager staged the broken
  image again.
- Evidence (J, going back): J staged K by itself and booted it; **Go back**
  (`bootc rollback`) returned to J, and L was published. Booted J's
  `cachedUpdate` was K (stale, the rollback image), the rollback entry held L.
  Telamon Updater showed "Telamon OS 44.20261027 is available", and the stager
  staged L.
- Evidence (J, greenboot): the broken image built on J failed four boots and
  was rolled back to J 14 minutes after the restart. Booted J's stale
  `cachedUpdate` was again K; the stager skipped: "is the version this machine
  went back from".

### A bad update in Telamon Updater (image M)

From M, Telamon Updater reads `bad-image-digests` too (without root, next to
the ref heads). An update with a listed digest isn't offered as a normal one:
the Updates page says "Version X didn't start properly", with a warning icon
and only "Download anyway", behind a confirmation. When the bad image is the
rollback entry, the Go back page says so and offers "Go back anyway" instead of
the usual button, also behind a confirmation. The digest leaves the list once
that image boots healthy (green.d), and the warning with it.

- Evidence (M, 2026-10-02): before the failure, "Check for updates" offered the
  broken image (44.20261029, built on M) as "Telamon OS 44.20261029 is
  available" with "Download update". After `bootc upgrade` and a restart it
  failed four boots, and greenboot rolled back to M about 14 minutes later; its
  digest was in `bad-image-digests`. Telamon Updater then showed "Version
  44.20261029 didn't start properly", still after another check, and
  "Download anyway" opened "Download 44.20261029 anyway?". The Go back page
  showed "The previous version didn't start properly" with "Go back anyway"
  (that page's wording was checked with the final build over a `/usr` overlay).

## Memory

| | |
|---|---|
| Stager while staging (`atlasos-update-stage.service` `MemoryPeak`) | 1.3 GB (E), 1.8 GB (O) |
| Idle, 2 minutes after login, image I (`just mem`, median of 3) | 1,059 MiB used (ps_mem 816 MiB); Telamon Updater in the tray 17.6 MiB |

## Fixed during testing

- Telamon Updater panicked on **Restart to update** (Tokio timer outside the
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
- After a rollback the stager and Telamon Updater read a stale check result
  (see "After a rollback").
- The broken test image only broke the greeter, so it passed on the autologin
  VM; it now breaks plasmashell too.
- Telamon OS's settings updates (`atlasos.upd`) never ran (see "What a user sees
  change").
- The restart warning said "Restarting in 5 minute(s)".
- Buttons and titles were in sentence case; from image Q (44.20261034) they
  use Title Case like KDE's own apps ("Check for Updates", "Go Back"), so the
  sentence-case names quoted above are the older wording.

## Known issues

- If no deployment holds the image ref's commit any more (for example after
  `rpm-ostree cleanup -r`), the stager and Telamon Updater fall back to the
  booted entry's `cachedUpdate`, which can be stale (inference, from the code).
- Installs made before the images were signed show their origin as
  `ostree-unverified-registry` until the background stager's next run
  switches it to `ostree-image-signed` (DEV.md). Signatures are checked
  either way, from the first signed image an install runs.
- `just mem` (and `boot`, `bench`, `check`) stop every VM the scripts made
  when they finish, `atlasos-updtest` included; don't run them during an
  update test.
- Without autologin the health checks only exercise the greeter, so a Plasma
  session that crashes right after login isn't caught (inference, from how the
  checks work; see the README).
- `sudo rpm-ostree override remove telamon-updater` removes Telamon Updater (it
  needs the admin password; `rpm-ostree override reset` undoes it). dnf
  refuses, the image build fails without it.
- The stager peaks at 1.8 GB while staging, a lot on an 8 GB machine.
- The update that first introduces greenboot isn't protected by it
  (inference, README).
