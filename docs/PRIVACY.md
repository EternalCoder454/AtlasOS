# Privacy

What Telamon OS and the Telamon apps send over the network, and what they keep on
the machine. **Evidence** means it was seen in a VM test (the update test VM,
`build/vm/updtest`, with a local registry and a local GlitchTip). **Inference**
means it is read from the code or documentation and not tested.

## Summary

- There is no telemetry, usage statistics or analytics in Telamon OS or the
  Telamon apps. Two Fedora defaults still talk to Fedora's servers: a weekly
  anonymous count of installed systems (countme) and a connectivity check
  every 5 minutes (see the table).
- Crash reports are the only data a Telamon app can send about the machine.
  They are **off by default**, and when on, every report is shown in full and
  sent only when the user presses Send.
- Updates download images from the registry and release notes from GitHub,
  like any bootc system. Neither request carries anything about the user.

## Network requests

| What | Where | When | What is sent |
|---|---|---|---|
| OS image updates | the image registry (`ghcr.io/eternalcoder454/telamonos`, and `atlasos`, its old name) | `atlasos-update-stage.timer` (15 to 30 minutes after boot, then every 6 h, not on metered connections), or **Check for updates** | an ordinary registry pull (bootc / containers-image); no user data |
| Release notes | `https://api.github.com/repos/EternalCoder454/AtlasOS/releases/tags/<version>` | when Telamon Updater shows an update or the history | the version; User-Agent `telamon-updater/<version>` |
| Flatpak updates | Flathub (and any other Flatpak remote you added) | Telamon Updater 10 minutes after login and then every 6 hours, **Check for App Updates**, and Flatpak's own schedule; with "Download app updates in the background" on (off by default), the downloads too | an ordinary Flatpak update check |
| Crash reports | the GlitchTip server in `/etc/telamon/crash-reporting.toml` | only when the user presses **Send** on a report | the report shown on screen, nothing more |
| Report on GitHub | the user's browser opens a prefilled GitHub issue | only when the user presses **Report on GitHub instead** | nothing until the user submits the issue form themselves |
| Fedora's system count (countme) | Fedora's mirror list, `mirrors.fedoraproject.org` | `rpm-ostree-countme.timer`, once a week (Fedora's default) | no ID: the OS name and version, the architecture, and how old the install is in coarse steps (one week, one month, six months, older) |
| Connectivity check | `http://fedoraproject.org/static/hotspot.txt` (plain HTTP, Fedora's NetworkManager default) | every 5 minutes while connected, and when a network comes up | an ordinary HTTP request; Fedora's servers see the IP address |
| Time sync | `2.fedora.pool.ntp.org` (chrony, NTP) | at boot, then every few minutes to hours | time requests only |
| Flatpak remotes | Flathub (`dl.flathub.org`) and Fedora's Flatpak registry (`registry.fedoraproject.org`, added by `flatpak-add-fedora-repos.service`) | the first boot's app setup, update checks | ordinary Flatpak metadata requests |
| Local network | the router's DHCP and DNS; mDNS (Avahi) on the local network only | as needed; mDNS announces the machine's host name on the local network | the host name on the local network; nothing leaves it (LLMNR is off) |
| DNSSEC root key | `data.iana.org`, only if the DNS check fails | `unbound-anchor.timer`, daily | an ordinary HTTPS request (inference: not seen in the capture) |

Evidence for the table: the VM's updates came from the local registry and
the report from the local GlitchTip, and nothing was sent before **Send**.

Idle capture (2026-10-04, the 2026-10-04 image in a VM, left idle
for an hour after boot, every outgoing packet logged with its user): DNS to
the router; mDNS on the local network; NTP to the Fedora pool; HTTP to
fedoraproject.org every 5 minutes (NetworkManager); HTTPS to Flathub and
Fedora's Flatpak registry (Flatpak); one HTTPS request from a dynamic
systemd user to Fedora's servers (countme); and HTTPS to ghcr.io from the
update stager 27 minutes after boot. Nothing else: no Telamon app or Plasma
component made a request on its own (Brave was not opened). What countme
sends is from Fedora's documentation; the release-notes request is inference
(from the code).

## Crash reports

**Off by default.** The switch is per user, in Telamon Updater → Settings →
Send crash reports (`~/.config/telamon/crash-reporting.toml`, `enabled = false`).
When it is off nothing is collected or written, and turning it off deletes
every report still waiting. Evidence: with it off, a crashing program left a
core dump in `coredumpctl` but no report and no notification; turning it off
with one report waiting deleted that report, and a crash after that made none.

**No server, no sending.** The server comes from `/etc/telamon/crash-reporting.toml`
(default `/usr/share/telamon/crash-reporting.toml`, which is empty). With no
server, reports can't be sent and Settings says so. Sending uses HTTPS only;
plain HTTP is accepted only for a server on the machine itself (loopback),
for testing.

**Sources.** Crashes of Telamon apps (Rust panics), crashes of the user's own
programs that systemd-coredump recorded, and update and rollback failures
recorded by the system helper. At most 5 reports an hour, and the same crash
(the same top frames) once.

**What a report contains:**

- Telamon OS version, channel and the previous version
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
`/var/home/USER/crashtest`, the Telamon OS version, kernel, GPU, uptime and a
stack trace; the user name (`atlas`) appeared nowhere in it except as part of
the OS name `atlasos`. **Show exact data** shows the JSON that is sent.

**Review and send.** A new report raises a notification ("Crash report ready",
with a **Review** button) when the Telamon Updater window is not active, and
appears under Crash reports. The user chooses **Send**, **Don't send** (the
report is deleted) or **Report on GitHub instead**. Evidence: **Don't send**
deleted the report and the server received nothing; **Send** delivered it to
the local GlitchTip and moved it to Sent reports.

**On disk.** Waiting reports: `~/.local/state/telamon/crash-reports/pending/`.
Sent reports: `sent/` next to it, kept 90 days so the user can see what was
sent, then deleted. Both directories are readable only by the user.
