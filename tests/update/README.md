# Update tests

## broken: an update that fails its health check

`broken/Containerfile` builds a deliberately broken AtlasOS on top of another
AtlasOS image (`--build-arg BASE=`, default `localhost/atlasos:update-a`),
labelled version `44.20261099-broken`. The machine still boots to a serial
console, but `/usr/libexec/plasma-login-greeter` is replaced by a script that
exits at once, so there is never a login screen and the greenboot login check
(`/usr/lib/greenboot/check/required.d/10_atlasos_login.sh`) fails 180 s after
boot. Each failed boot reboots; after 4 boots in all greenboot runs
`bootc rollback` and comes back up on the previous image. The base must be an
image with greenboot, and the VM must already be running one (see "Boot health
checks and rollback" in the top-level README for the limits).

```sh
podman build --build-arg BASE=localhost/atlasos:latest \
    -f tests/update/broken/Containerfile -t localhost/atlasos:broken tests/update/broken
```

In the VM: `bootc switch` (or Atlas Updater) to the broken image and reboot,
then watch `sudo grub2-editenv list` and `journalctl -b -u greenboot-healthcheck.service`
on the serial console. Expect `boot_counter` 3, 2, 1, 0 over four failed boots,
then a boot of the previous image with `bootc status` showing the broken one as
the rollback entry.
