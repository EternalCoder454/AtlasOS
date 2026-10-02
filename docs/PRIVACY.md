# Privacy

What AtlasOS and the Atlas apps send over the network, and what they keep on
the machine. **Evidence** means it was seen in a VM test (the update test VM,
`build/vm/updtest`, with a local registry and a local GlitchTip). **Inference**
means it is read from the code or documentation and not tested.

## Summary

- There is no telemetry, usage statistics or analytics in AtlasOS or the
  Atlas apps.
- Crash reports are the only data an Atlas app can send about the machine.
  They are **off by default**, and when on, every report is shown in full and
  sent only when the user presses Send.
- Updates download images from the registry and release notes from GitHub,
  like any bootc system. Neither request carries anything about the user.

## Network requests

| What | Where | When | What is sent |
|---|---|---|---|
| OS image updates | the image registry (`ghcr.io/eternalcoder454/atlasos`) | `atlasos-update-stage.timer` (about 1 h after boot, then every 6 h, not on metered connections), or **Check for updates** | an ordinary registry pull (bootc / containers-image); no user data |
| Release notes | `https://api.github.com/repos/EternalCoder454/AtlasOS/releases/tags/<version>` | when Atlas Updater shows an update or the history | the version; User-Agent `atlas-updater/<version>` |
| Flatpak updates | Flathub | **Check for updates** in Atlas Updater, and Flatpak's own schedule | an ordinary Flatpak update check |
| Crash reports | the GlitchTip server in `/etc/atlas/crash-reporting.toml` | only when the user presses **Send** on a report | the report shown on screen, nothing more |
| Report on GitHub | the user's browser opens a prefilled GitHub issue | only when the user presses **Report on GitHub instead** | nothing until the user submits the issue form themselves |

Inference for the table, apart from crash reports and image updates (evidence:
the VM's updates came from the local registry and the report from the local
GlitchTip, and nothing was sent before **Send**).

## Crash reports

**Off by default.** The switch is per user, in Atlas Updater → Settings →
Send crash reports (`~/.config/atlas/crash-reporting.toml`, `enabled = false`).
When it is off nothing is collected or written, and turning it off deletes
every report still waiting. Evidence: with it off, a crashing program left a
core dump in `coredumpctl` but no report and no notification; turning it off
with one report waiting deleted that report, and a crash after that made none.

**No server, no sending.** The server comes from `/etc/atlas/crash-reporting.toml`
(default `/usr/share/atlas/crash-reporting.toml`, which is empty). With no
server, reports can't be sent and Settings says so. Sending uses HTTPS only;
plain HTTP is accepted only for a server on the machine itself (loopback),
for testing.

**Sources.** Crashes of Atlas apps (Rust panics), crashes of the user's own
programs that systemd-coredump recorded, and update and rollback failures
recorded by the system helper. At most 5 reports an hour, and the same crash
(the same top frames) once.

**What a report contains:**

- AtlasOS version, channel and the previous version
- the app's name, version and category (for a program outside a package, its
  path with the home directory replaced: `/var/home/USER/program`)
- the stack trace from the journal
- kernel version, GPU model and driver, uptime, CPU model, RAM total and use
- a random ID that is replaced every 30 days (never `/etc/machine-id`), the
  time and the report type

**What it never contains:** the core dump itself, user names, host names,
MAC or IP addresses, serial numbers, installed apps, file contents, command
lines, environment variables or the working directory. Every string is
scrubbed: home directories, user names, host names, MAC and IP addresses and
machine and boot IDs are replaced.

Evidence: a report from a test program crashed with SIGSEGV showed
`/var/home/USER/crashtest`, the AtlasOS version, kernel, GPU, uptime and a
stack trace; the user name (`atlas`) appeared nowhere in it except as part of
the OS name `atlasos`. **Show exact data** shows the JSON that is sent.

**Review and send.** A new report raises a notification ("Crash report ready",
with a **Review** button) when the Atlas Updater window is not active, and
appears under Crash reports. The user chooses **Send**, **Don't send** (the
report is deleted) or **Report on GitHub instead**. Evidence: **Don't send**
deleted the report and the server received nothing; **Send** delivered it to
the local GlitchTip and moved it to Sent reports.

**On disk.** Waiting reports: `~/.local/state/atlas/crash-reports/pending/`.
Sent reports: `sent/` next to it, kept 90 days so the user can see what was
sent, then deleted. Both directories are readable only by the user.
