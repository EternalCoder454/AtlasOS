# Telamon OS: security

The Secure phase of the image repository: the privileged and per-user pieces
the image ships, who can reach them, what an attacker on the machine can and
cannot do, what was fixed, and what is left. Telamon Updater's helper, its
polkit actions and its crash and firmware code are in that repository's
`docs/SECURITY.md`; the PIN design is described in [DEV.md](../DEV.md) ("PIN
sign-in"), the update system in [UPDATES.md](UPDATES.md).

Run the checks with `just security-tests` (containers of the published image;
nothing is installed or started on the machine).

## Threat model

**Attacker.** An unprivileged local user or process (including a sandboxed app
with access to a user's home), a person with brief physical access to a
locked or logged-out machine, someone who controls a registry response or the
network between the machine and `ghcr.io`. Not in scope: root, the holder of
the image signing key, a user who is an administrator and runs `bootc switch`
on purpose, someone with the disk and no disk encryption (see the PIN).

**Assets.** What boots next; root's integrity; the accounts' passwords and
keyrings; one user's data from another; the user's consent.

## What runs with privilege, and who can reach it

| Piece | Runs as | Reached through | Who may use it |
|---|---|---|---|
| `atlasos-update-stage.service` (timer every 6 h) | root | the timer; no input | nobody can pass it anything |
| `atlasos-pin@.service` (`pin-daemon`) | root, in its own SELinux domain, sandboxed | `/run/atlasos/pin.sock` (mode 0666, one process per connection) | anyone may connect; the daemon reads `SO_PEERCRED`: root may ask about any uid, everyone else only about their own |
| `pin-admin` | root, through `pkexec` | polkit `org.atlasos.pin.manage` | the active local user, confirming with their own password; it acts only on `PKEXEC_UID`, reads the PIN from stdin |
| `pam_atlasos_pin.so` | whatever calls PAM | the `kde` (lock screen) and `plasmalogin` (login screen) services only | see below |
| `nvidia-enroll-key` | root, through `pkexec` | polkit `org.atlasos.nvidia.enroll-key` | the active local user, with an administrator's password; one fixed argument, one fixed certificate |
| `telamon-system-helper` | root | the system bus, polkit | see Telamon Updater's SECURITY.md |
| greenboot `red.d`/`green.d`, `grub-greenboot`, `btrfs-compress`, `flatpak-preinstall`, `mandb-needed`, `ldconfig-needed` | root | systemd units; no input | nobody |
| kconf_update scripts, `kvantum-sync` | the user, at login | `atlasos-kconf-update.service`, `atlasos-kvantum-sync.path` (user units) | the user's own files only |
| `pin-setup`, `pin-prompt`, `fingerprint-setup`, `nvidia-key-setup` | the user | XDG autostart, the launcher | the user |

The image ships no sudoers file, no `NOPASSWD`, no polkit rules (`rules.d`),
no setuid file of its own and no world-writable file; `tests/units` fails if
one appears.

## Polkit actions the image ships

| Action | Remote / inactive | Active local | Program |
|---|---|---|---|
| `org.atlasos.pin.manage` | no | `auth_self` | `/usr/libexec/telamon/pin-admin` |
| `org.atlasos.nvidia.enroll-key` (NVIDIA image) | no | `auth_admin` | `/usr/libexec/telamon/nvidia-enroll-key` |

Each names one program and pins no argument; the program validates its own
(`pin-admin`: `set`, `remove` or `status`, nothing else; `nvidia-enroll-key`:
no argument or `--new-code`). Telamon Updater adds its own five actions.

## Image references, signatures and updates

Every pull of `ghcr.io/eternalcoder454/telamonos`, `telamonos-nvidia`, `atlasos`
and `atlasos-nvidia` (bootc, rpm-ostree, podman, skopeo: one policy) needs a
cosign signature from the key in `cosign.pub`
(`/etc/pki/containers/telamon.pub`), found as a sigstore attachment beside the
image (`/etc/containers/registries.d/telamon.yaml`). `policy.json`'s default is
`reject`; each transport keeps a catch-all `insecureAcceptAnything` so that an
administrator can still pull any other image. The stager records the check in
an older install's origin (`--enforce-container-sigpolicy`). A signature proves
who built an image, not that it is the newest, so the stager and Telamon
Updater's helper both refuse an older build of the same image (before the
download when the registry can be asked, and again on what was staged).

Who can point the system elsewhere: only root. `bootc switch` and
`rpm-ostree rebase` need it; the one place that switches without a human is
Telamon Updater's helper, which only changes the tag between `stable` and
`testing` (or, for drivers, to a fixed list of Telamon OS images when the
pull is signature-checked). The tag is not trusted: a tag moved to an
unsigned build is refused (tested).

CI signs every pushed image and its SBOM attestation, verifies both with
`cosign.pub` before the job ends, and refuses to push if the signing secret is
not the key in `cosign.pub`. Attestations are not checked by the client; they
describe the image and do not gate an update (`scripts/verify-image.sh` checks
them by hand).

## PIN sign-in

Design in DEV.md. The security properties, and the test that holds each
(`tests/pin`, 116 checks against the published image's real PAM stack, PAM
module and the repository's verifier):

- The PIN is accepted at the lock screen and the login screen only. `sshd`,
  `sudo`, `su`, `login`, polkit, `passwd` and 13 other services never ask the
  verifier, even when it would say yes (a stand-in verifier answers "ok" to
  everything and logs what reaches it). The module checks the service name
  itself, and `password-auth` gates it with `pam_succeed_if` as well.
- Brute force: 5 wrong PINs lock it until a password sign-in at the login
  screen; 20 wrong PINs over its life retire it for good (it decays one per
  day, at most 7 per try, and a clock set back credits nothing). The try is
  counted and stored *before* the hash is checked, under a file lock, so
  parallel guesses cannot beat the limit (12 and 30 parallel requests tested).
  An unknown user, no PIN, a locked PIN and a refused account all hash a dummy,
  so timing does not say which users have a PIN.
- Who may ask: `verify`, `status` and `reset` are checked against the peer's
  uid; another user gets `deny` and nothing is counted. A name that is not the
  uid's name, a PIN that is not 4-8 digits, an incomplete line, a line over
  128 bytes and a request with extra words all answer without counting.
- Storage: `/var/lib/atlasos/pin` is 0700 root; a record is 0600 root, written
  to a temp file, synced and renamed, the directory synced; the hash is
  yescrypt with a random salt (the same PIN hashes differently each time); the
  PIN is in no file or log in the clear. The record carries a stamp of the
  user name, uid and the shadow hash: a changed password, a reused uid or a
  locked account kills the PIN. `pin-admin` refuses weak PINs (repeats, runs,
  years, common ones), root, a missing `PKEXEC_UID`, a PIN on the command line
  and use by a non-root caller.
- Not claimed: a 4-8 digit PIN has 10^4 to 10^8 values behind one hash, so
  anyone who can read the disk can guess it offline. Disk encryption is what
  protects it; `pin-setup` says so. The wallet and keyring never see the PIN
  (the module clears `PAM_AUTHTOK`).
- The unit: `NoNewPrivileges`, `ProtectSystem=strict` (only the store is
  writable), no network (`AF_UNIX` only), `CapabilityBoundingSet` of
  `CAP_DAC_READ_SEARCH` alone, `SystemCallFilter` without `@privileged
  @resources`, 10 s `RuntimeMaxSec`, 640 MB, 8 tasks, `UMask=0077`, SELinux
  `atlasos_pin_t`. Exposure 1.1 (`systemd-analyze security`).

## Units (system)

Exposure from `systemd-analyze security --offline=yes`; `tests/units` fails if
one rises above its number or loses the floor (`LockPersonality`,
`RestrictRealtime`, `SystemCallArchitectures`, `RestrictAddressFamilies`,
`CapabilityBoundingSet`), and requires `NoNewPrivileges=yes` except where
listed.

| Unit | Exposure | No `NoNewPrivileges` / what stays off |
|---|---|---|
| `atlasos-pin@.service` | 1.1 | has it |
| `atlasos-inotify-watches.service` | 1.3 | has it |
| `atlasos-grub-greenboot.service` | 4.3 | has it; no `ProtectSystem` (it remounts `/boot`) |
| `atlasos-btrfs-compress.service` | 4.5 | has it; no mount namespace (it remounts `/var`) |
| `atlasos-flatpak-preinstall.service` | 6.0 | bubblewrap needs capabilities and namespaces; `ProtectSystem=strict` |
| `atlasos-update-stage.service` | 6.7 | bootc and rpm-ostree need `/sysroot`, setuid checkouts, mount namespaces, SELinux transitions, `CAP_SYS_PTRACE` |

User units (`atlasos-kvantum-sync`, `atlasos-kconf-update`) run the user's own
tools on the user's own files. They have `NoNewPrivileges`, `LockPersonality`,
`RestrictRealtime`, `RestrictSUIDSGID` and `SystemCallArchitectures=native`;
the options that need a mount namespace are left off because a user manager
without user namespaces would fail the unit and the theme would stop following
the colour scheme.

## kconf_update and per-user scripts

They run as the user, at login, on files in the user's own `~/.config`,
`~/.local`. There is no privilege boundary to cross, so the aim is that they
cannot be turned against the user's own data by what is in those folders:
every script is `#!/bin/sh` with `set -eu`, none evals or runs a string it
read from a file, none writes a fixed `/tmp` name (temporary files are
`mktemp` files next to the target, 0600, renamed over it with the original
mode), each file it changes is copied once to
`~/.local/state/telamon/migrated-from-atlasos/`, and a symlinked target (a
dotfiles manager's) is written through, not replaced. `tests/units` checks
the shape; `tests/rename`, `tests/replace-dolphin-ark` and the
others check the behaviour. `kvantum-sync` reads values with `awk`, writes
only through `kwriteconfig6`, and keeps its stamp in `XDG_RUNTIME_DIR`.

## Findings of this phase

| # | Issue | Severity | Fix | Test |
|---|---|---|---|---|
| I1 | No automated test of the PIN stack, its PAM gating, lockout, store or tools existed in the repository (the harness lived outside it) | process | `tests/pin` | 116 checks |
| I2 | Nothing tested that the shipped units keep their sandboxing, that polkit actions stay closed to remote and inactive sessions, that no sudoers/rules/setuid file appears, or that scripts avoid eval and fixed temp files | process | `tests/units` | 274 checks |
| I3 | Nothing tested that a signed update is accepted, an unsigned or re-tagged or wrongly-signed one refused, under the image's real policy | process | `tests/signing` (local registry + cosign) | 24 checks |
| I4 | The two user units that run at every login had no sandboxing at all | low | `NoNewPrivileges`, `LockPersonality`, `RestrictRealtime`, `RestrictSUIDSGID`, `SystemCallArchitectures` | `tests/units` section 3 |
| I5 | `telamon jetbrains-toolbox` fetched with `curl` without pinning the protocol, did not check where the checksum link pointed, and passed whatever the checksum file held to `sha256sum` | low | https and TLS 1.2 only (also on redirects), the checksum link must be on `download.jetbrains.com`, the value must be 64 hex digits | `just --list` and `just --fmt --check` of the file |
| I7 | `/etc/profile.d/atlasos-brew.sh` added the Homebrew prefix to every login shell's PATH, root's and other users' included; the prefix belongs to one user, who could plant a program named like a command the image lacks, for root to run by typing it | low | only for the user who owns the prefix, never for root | `tests/units` section 7 |
| I8 | `telamon brew` fetched Homebrew's installer without pinning https | low | `--proto '=https' --tlsv1.2` | `just --fmt --check`, `--list` |
| I6 | `pin-daemon` answers `set` to `status` for an account whose password is locked (verify answers `deny`) | info | none: harmless, and `pin-admin status` only knows four words; recorded in the test | `tests/pin` |

Checked and fine: the PIN daemon and library, the PAM module and its gating,
the PAM file edits `build.sh` makes (and asserts), the signing policy and key,
`update-stage` and its condition (no eval, word splitting only on jq output
that only reaches `echo`, root-only temp directory), `nvidia-enroll-key`
(fixed certificate, random code from `/dev/urandom` without bias, 077 umask,
lock, never replaces another key's request), the greenboot scripts, the
tmpfiles and socket modes.

## Accepted, and what is left

| Item | Why it stays | What would close it |
|---|---|---|
| `update-stage` and the helper units are at 6.0-6.7 exposure | bootc/ostree need the privileges; options like `ProtectKernelTunables` or a syscall deny-list may or may not break them | try them in the test VM (`just updtest`) one at a time |
| `policy.json` accepts any unsigned image outside the four Telamon repositories | an administrator may pull anything; the policy must reject nothing else for rpm-ostree to keep working | none wanted |
| The PIN hash is guessable offline by someone with the disk | 4-8 digits | disk encryption (the installer offers it); a longer PIN |
| A user with an all-digit password who mistypes it counts as a wrong PIN | by design | none |
| No kernel hardening `sysctl` beyond Fedora's | `ptrace_scope`, `dmesg_restrict` and friends change developer workflows (this image targets developers); a product decision | pick a set |
| Ghostty comes from one person's COPR, unpinned, rebuilt daily, `repo_gpgcheck=0`; the key proves only "built by COPR" (`build_files/packages.sh`) | the terminal is wanted; a package from COPR runs as root at build time and ships under our signature | build it from a pinned upstream tag in its own stage, or fetch the RPM by URL and check a pinned hash |
| The signing and NVIDIA module-key secrets are repository secrets, readable by a workflow run from any branch by anyone with write access (no `environment:`) | GitHub settings, not code | a GitHub Environment limited to `main` with required reviewers |
| `iso.yml` builds the ISO from the installer's `main`, not the commit in `telamon-apps.lock`, in the job that later holds `ISO_UPLOAD_KEY`; the ISO has no detached signature | the ISO should carry the newest installer | use the pinned commit when uploading, split build and upload, sign the ISO |
| The VPS runner is not ephemeral and admits a push of any tag | `ci/vps-runner` | `--ephemeral` JIT registration; a tag ruleset |
| `ci/crash-relay` trusts `X-Forwarded-For` from any peer when `RELAY_PROXY_SECRET` is unset (compose.yaml requires it) | the global caps still hold | make the secret mandatory |
| Build stages use tag-only bases (`alpine`, `fedora`, `golang`); dependabot covers actions only | | digests and the docker ecosystem |
| The default firewall zone allows ssh (sshd is off), mdns and Steam's services on every network | documented intent | a separate trusted zone |
| The first-run wizard (`telamon-wizard`) creates the account as root | its own repository | audit it with this one's method |
| Attestations are not enforced client-side | not an update gate | none |
| SELinux and the real greeters are not covered by `tests/pin` | needs a booted VM | the VM pass in DEV.md |

## Reporting

Use GitHub's private vulnerability reporting on this repository, or email the
maintainer; please do not open a public issue for a way to gain root or to get
an unsigned image installed.
