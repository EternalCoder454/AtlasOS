# Update tests

## broken: an update that fails its health check

`broken/Containerfile` builds a deliberately broken AtlasOS on top of another
AtlasOS image (`--build-arg BASE=`, default `localhost/atlasos:update-a`),
labelled version `44.20261099-broken`. The machine still boots to a serial
console, but `/usr/libexec/plasma-login-greeter` and `/usr/bin/plasmashell` are
replaced by scripts that exit at once, so there is neither a login screen nor,
with autologin, a desktop, and the greenboot login check
(`/usr/lib/greenboot/check/required.d/10_atlasos_login.sh`) fails 180 s after
boot. (An earlier version broke only the greeter: on the autologin test VM
plasmalogin started the session without it, the check passed on the running
plasmashell, and the image was kept.) Each failed boot reboots; after 4 boots in all greenboot runs
`bootc rollback` and comes back up on the previous image. The base must be an
image with greenboot, and the VM must already be running one (see "Boot health
checks and rollback" in the top-level README for the limits).

```sh
podman build --build-arg BASE=localhost/atlasos:latest \
    -f tests/update/broken/Containerfile -t localhost/atlasos:broken tests/update/broken
```

In the VM: `bootc switch` (or Atlas Updater) to the broken image and reboot,
then (each failed boot takes about 3 minutes, 4 boots, so allow 15 minutes) watch `sudo grub2-editenv list` and `journalctl -b -u greenboot-healthcheck.service`
on the serial console. Expect `boot_counter` 3, 2, 1, 0 over four failed boots,
then a boot of the previous image with `bootc status` showing the broken one as
the rollback entry.

## b: a visible change to update to

`b/Containerfile` adds one app (KCalc) and turns the active window's header,
title bar included, AtlasOS purple, on top of any AtlasOS image (`--build-arg A=`).
After the update both are easy to check: KCalc is in the launcher and its title
bar is purple. Give it a newer version label than the image the VM runs:

```sh
podman build -v "$PWD/build/cache/dnf:/var/cache/libdnf5:Z" --build-arg A=localhost/atlasos:update-e \
    --label org.opencontainers.image.version=44.20261022 -t localhost/atlasos:update-g tests/update/b
```

KWin colours title bars from the scheme's `[Colors:Header]` group; `[WM]` is
only read by schemes without one, so an earlier version of this layer that
changed `[WM]` had no visible effect.

## Release notes

`notes-*.md` are release notes for the test images, in the Markdown Atlas
Updater renders: `scripts/vm.sh publish <tag> <channel> tests/update/notes-f.md`.
