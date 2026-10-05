# ISO downloads on the VPS

The live installer ISOs are served from `eterneon-vps` at
https://atlasos.eterneon.net/. [iso.yml](../../.github/workflows/iso.yml)
builds them on GitHub's runners after each weekly stable release
(`promote-stable.yml`) and uploads them here.

| File in `/srv/downloads/atlasos`, served under `/dl/` | What |
|---|---|
| `<image>.json` | The current version: `version`, `file`, `size`, `sha256`, `date` |
| `<image>-44.YYYYMMDD-N.iso` | The ISO of that stable version (`-N` is the build number; versions before 2026-10-03 have none) |
| `<image>-44.YYYYMMDD-N.iso.sha256` | Its checksum, in `sha256sum -c` format |

`<image>` is `atlasos` or `atlasos-nvidia`. Each image keeps one version. An
upload puts the new ISO and its checksum in place together once both are up,
then moves `<image>.json` to them, then deletes the older version, so there's
always a whole version to download.

## How it is put together

- **A disk of its own.** A 50 GB OVH additional disk (`/dev/sdb1`, ext4,
  label `downloads`) mounted at `/srv/downloads` by UUID in `/etc/fstab`,
  with `nofail`. ISOs can't fill the root disk that Matrix, Forgejo, the
  panel, the site and the CI runner rely on.
- **An upload account that can only upload.** `atlas-iso` (a system user, its
  password locked, home `/var/lib/atlas-iso`) owns `/srv/downloads/atlasos`.
  Its one SSH key is in `authorized_keys` with
  `restrict,command="/usr/bin/rrsync -wo -no-lock /srv/downloads/atlasos"`:
  rsync into that folder and nothing else, with no shell, no reading and no
  forwarding. `-no-lock` lets the two ISO jobs upload at the same time; their
  rsync filters touch different files.
- **Caddy serves it.** The `matrix` stack's Caddy (`/srv/matrix`) mounts the
  folder read-only at `/srv/atlasos-downloads` (`compose.yaml`), and the
  `atlasos.eterneon.net` block in `caddy/Caddyfile` serves it under `/dl/`.
  Versioned files are cached for a year, the `.json` files for a minute.
- **DNS.** An `A` record for `atlasos.eterneon.net` in Cloudflare, DNS only
  (not proxied): Cloudflare's free plan doesn't cache files this large, and
  its terms don't allow serving them through the proxy.

## Secrets

| Secret | What |
|---|---|
| `ISO_UPLOAD_KEY` | The private half of `atlas-iso`'s SSH key (ed25519, no passphrase) |
| `ISO_UPLOAD_KNOWN_HOSTS` | `ssh-keyscan -t ed25519 atlasos.eterneon.net`, checked against `/etc/ssh/ssh_host_ed25519_key.pub` on the VPS |

To replace the key, make a new one, put its public half in
`/var/lib/atlas-iso/.ssh/authorized_keys` with the same options, and set
`ISO_UPLOAD_KEY` to the private half:

```sh
ssh-keygen -t ed25519 -N '' -C 'atlas-iso upload (AtlasOS GitHub Actions)' -f iso_upload
gh secret set ISO_UPLOAD_KEY -R EternalCoder454/AtlasOS < iso_upload
```

## Building one by hand

Actions, "Live ISO", Run workflow: pick the image. "Build even if this
version's ISO is already up" rebuilds it, and turning off "Upload it" keeps
the ISO as a workflow artifact for 3 days instead.
