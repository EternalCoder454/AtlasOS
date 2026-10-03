# Optimization pass

What AtlasOS 44 dropped or tuned after Phase 1, and what each change was
worth. Every number comes from the same 8 GB test VM (UEFI, virtio 3D, SPICE
OpenGL), measured with `just bench` (`just boot` and `just mem` from the same
boots): three boots from a fresh overlay each, medians reported, memory read
two minutes after Plasma starts.

The rule for the pass, from the roadmap: keep everything people can see
(blur, translucency, animations, rounded corners) and only trim what nobody
sees.

## Before and after

| | Before (image update-q) | After (image opt4) | Change |
|---|---|---|---|
| Memory in use (`free`, total − available) | 1,059 MiB | **987 MiB** | −72 MiB |
| Memory available | 6,801 MiB | 6,873 MiB | +72 MiB |
| All processes (`ps_mem`) | 814.8 MiB | 752.1 MiB | −62.7 MiB |
| Running system services | 32 | 30 | −2 |
| Running user services | 32 | 30 | −2 |
| Plasma's shell up (after kernel start) | 8.02 s | 8.05 s | same |
| Userspace boot (`systemd-analyze`) | 16.80 s | 16.96 s | same (see greenboot below) |
| Package docs in the image | 140 MB | licenses only | −140 MB |

"After" includes the work done since: the dock, the vendored launcher and our
dock separator cost about 7 MiB in plasmashell, and the patched KIO and
first-run wizard nothing at idle.

For reference, stock Kinoite 44 in the same VM used 2,075 MiB (`just
mem-stock`), and AtlasOS's Phase 1 baseline 1,043 MiB.

## Per change

Process sizes are `ps_mem` medians (private + shared), before → after.

| Change | Where | Measured |
|---|---|---|
| Removed Xwayland Video Bridge: it ran all the time so X11 apps could share Wayland windows; apps share the screen through the portal now | `packages.sh` | −29.9 MiB (xwaylandvideobridge) |
| power-profiles-daemon in place of TuneD and its PPD bridge: the same three power profiles in Plasma and powerdevil | `packages.sh` | −51.2 MiB (tuned 27.0 + tuned-ppd 24.2) for +1.0 MiB |
| Removed kunifiedpush: KDE's push-notification service starts with every session, and no app here uses it | `packages.sh` | −4.6 MiB, −1 user service |
| gssproxy only starts with a Kerberos keytab (`nfs-client.target` pulled it in at every boot) | `gssproxy.service.d/atlasos.conf` | −2.2 MiB, −1 system service |
| kded modules off: Baloo's search module (no Baloo here) and the Plasma Browser Integration reminder | `/etc/xdg/kded5rc` | too small to measure at idle; two fewer modules in kded6 |
| KRunner plugins off: file search (no Baloo index, it only started an idle helper), Konsole profiles (Ghostty is the terminal), AppStream (loads the whole catalogue on the first search) | `/etc/xdg/krunnerrc` | nothing at idle (KRunner isn't running); the first search no longer loads AppStream |
| zram with zstd instead of lzo-rle: about a third more fits in the same RAM, for a little more CPU | `zram-generator.conf.d/atlasos.conf` | `just check` confirms zstd |
| Swap tuning for zram: `vm.swappiness=180`, `vm.page-cluster=0`, `vm.watermark_boost_factor=0` | `sysctl.d/60-atlasos-zram.conf` | no idle cost; helps under memory pressure |
| Removed what the Phase 1 removals left behind: Akonadi's MariaDB server and Qt driver, DrKonqi's helpers, KJournald's and Partition Manager's libraries, the Plasma handbook, Konqueror's bookmark editor, PySide6, sos | `packages.sh` | disk only (nothing ran) |
| Package docs (READMEs, changelogs, KDE handbooks) deleted; licenses and man pages kept | `build.sh` | −140 MB of image |
| Weak dependencies stay off for everything AtlasOS installs (`install_weak_deps=False`) | `packages.sh` | already the case; checked |
| Closing Dolphin no longer crashes its thumbnail workers: KIO's SIGTERM handler wrote to a destroyed worker ([KDE bug 518400](https://bugs.kde.org/show_bug.cgi?id=518400)); patched KIO until Fedora ships the fix | `build_files/kio/` | 0 coredumps (was 1 per Dolphin close); the stability gate no longer needs its exception |

Desktop effects: nothing was turned off. Every effect that is on is one
people see.

## Findings worth keeping

**`vm.watermark_scale_factor=125` makes memory look worse.** It's in many
"zram tuning" guides, so the first round of this pass had it. It keeps 2.5%
of RAM free as headroom, and `free` counts that as used: the first round
measured 1,281 MiB in use instead of about 1,060, with *less* actually
allocated (ps_mem fell 69 MiB). It's a reserve for heavy memory pressure,
not something an 8 GB desktop needs, so it went back to the kernel's 10.

**Greenboot's 13 s is not boot time you wait for.** `systemd-analyze` says
userspace takes about 17 s, of which `greenboot-healthcheck.service` is
13.3 s: it waits for the login, Plasma and the network to come up and stay
up, so a bad update can be rolled back. It runs alongside the login, and
Plasma's shell is up at 8 s either way. Phase 1's baseline (3.7 s
userspace) was measured before greenboot was added.

## Not changed, and why

| Running at idle | Size | Why it stays |
|---|---|---|
| firewalld | 38.0 MiB | The firewall, with Plasma's firewall settings page on top. A static nftables ruleset would save the memory but lose the settings page and the zones NetworkManager switches between. |
| Xwayland | 35.2 MiB | Running from login. Starting it only when the first X11 app opens would save this until then; not tried yet, because something in the session may open an X11 client straight away and it needs testing app by app. |
| xdg-desktop-portal-gtk | 13.7 MiB | GTK apps (Flatpaks, Brave's file dialogs) use it for settings and appearance. Removing it breaks their dark mode and fonts. |
| ModemManager | 6.7 MiB | Mobile broadband on laptops with a WWAN modem. Could be socket-activated later. |
| cupsd | 3.4 MiB | Printing, which `just check` tests. cups.service is enabled, so it runs from boot; leaving it to its socket (start on the first print) is a candidate for later. |
| systemd-homed | 1.9 MiB | Fedora enables it. AtlasOS's users are classic ones, so it could go; left for now because it's small and the wizard and AccountsService work as they are. |
| wpa_supplicant (not iwd) | — | iwd was on the roadmap as a lighter replacement. NetworkManager still treats wpa_supplicant as its main Wi-Fi backend and iwd as the alternative, and the test VM has no Wi-Fi to check a switch with, so it stays for the first release. |

## How to repeat it

```bash
just build opt
just bench-disk opt
just bench 3
just check
```

Results land in `build/bench/` (`summary.json` with medians, and a
`report.txt` per boot with `systemd-analyze`, the blame list, the critical
chain, `free -h`, `ps_mem` and the running services).
