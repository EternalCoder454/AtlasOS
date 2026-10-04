# AtlasOS: a minimal Fedora Kinoite 44 desktop, built as a bootc image.

# The base. CI passes the digest it resolved, so the image records exactly
# which Kinoite it was built on (the org.atlasos.base-image label below).
ARG BASE_IMAGE=quay.io/fedora/fedora-kinoite:44

# Logos, icons and wallpapers, rendered from branding/. A separate
# stage so the SVG tools never reach the OS, and so this layer is cached until
# branding/ changes.
FROM docker.io/library/alpine:3.24 AS branding
RUN apk add --no-cache rsvg-convert imagemagick imagemagick-jpeg imagemagick-jxl
COPY branding /branding
RUN sh /branding/render.sh /branding /out

# atlas-framework, the shared base of the Atlas apps (Atlas.Ui, its Material
# Symbols fonts and the Atlas Symbols gallery), built into RPMs the same way
# from the build context named "atlas-framework"
# (EternalCoder454/atlas-framework). The apps below are built against these
# RPMs (ATLAS_LOCAL_RPMS, see build-rpm.sh in each app), and apps.sh installs
# them before the apps. The stage has its own name: a stage named like the
# build context would hide it from COPY --from.
FROM registry.fedoraproject.org/fedora:44 AS framework
COPY --from=atlas-framework --exclude=.git --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/atlas-framework-build,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    ATLAS_BUILD_CACHE=/var/cache/atlas-framework-build drop-build-deps.sh /src/packaging/build-rpm.sh /out

# The Atlas apps (Atlas Updater and atlas-system-helper), built into RPMs in a Fedora 44
# container, the release the image is based on. The source is the build
# context named "atlas-updater" (`podman build --build-context
# atlas-updater=<path>`; `just build` and CI pass it). Cargo's downloads and
# build output (ATLAS_BUILD_CACHE, see build-rpm.sh there) and dnf's downloads
# are cache mounts, so they survive between builds without ending up in an
# image layer. Only a machine that keeps its Podman storage benefits: the VPS
# runner and local builds (see CI.md).
# Without what build-rpm.sh leaves out of the source too: .git differs in every
# checkout, so with it this step and the build after it never come from the
# cache, and a local checkout's build output is gigabytes.
FROM registry.fedoraproject.org/fedora:44 AS atlas-apps
COPY --from=atlas-updater --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/atlas-build,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/atlas-framework-rpms \
    ATLAS_LOCAL_RPMS=/atlas-framework-rpms \
    ATLAS_BUILD_CACHE=/var/cache/atlas-build drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Atlas Monitor, built the same way from the build context named
# "atlas-monitor" (EternalCoder454/atlasos-monitor). A stage of its own, so a
# change to one app doesn't rebuild the other. Cargo's crate downloads are a
# cache mount (CARGO_HOME, see the spec there). Its build fetches the
# atlas-framework crates from GitHub at the commit its Cargo.toml pins, so it
# needs the network. Like Atlas Updater, it is built against the framework
# RPMs (ATLAS_LOCAL_RPMS).
FROM registry.fedoraproject.org/fedora:44 AS monitor-app
COPY --from=atlas-monitor --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/atlas-monitor-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/atlas-framework-rpms \
    ATLAS_LOCAL_RPMS=/atlas-framework-rpms \
    CARGO_HOME=/var/cache/atlas-monitor-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Atlas Notepad, built the same way as Atlas Monitor from the build context
# named "atlas-notepad" (the AtlasOS Text Editor source).
FROM registry.fedoraproject.org/fedora:44 AS notepad-app
COPY --from=atlas-notepad --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/atlas-notepad-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/atlas-framework-rpms \
    ATLAS_LOCAL_RPMS=/atlas-framework-rpms \
    CARGO_HOME=/var/cache/atlas-notepad-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# KIO with AtlasOS's crash fix (see build_files/kio/build-rpm.sh): Fedora's
# kf6-kio, rebuilt at the version the base image has.
FROM ${BASE_IMAGE} AS base-kio
RUN rpm -q kf6-kio-core --qf '%{VERSION}-%{RELEASE}' >/kio-nvr

FROM registry.fedoraproject.org/fedora:44 AS kio
COPY --from=base-kio /kio-nvr /kio-nvr
COPY build_files/kio /kio
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    drop-build-deps.sh /kio/build-rpm.sh /out

# The first-run wizard in AtlasOS's style (see
# build_files/plasma-setup/build-rpm.sh): Fedora's plasma-setup, rebuilt at
# the version the base image has.
FROM ${BASE_IMAGE} AS base-plasma-setup
RUN rpm -q plasma-setup --qf '%{VERSION}-%{RELEASE}' >/plasma-setup-nvr

FROM registry.fedoraproject.org/fedora:44 AS plasma-setup
COPY --from=base-plasma-setup /plasma-setup-nvr /plasma-setup-nvr
COPY build_files/plasma-setup /plasma-setup
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    drop-build-deps.sh /plasma-setup/build-rpm.sh /out

# The SELinux modules (selinux/: the PIN verifier's, see DEV.md "PIN sign-in",
# and atlasos_bootc, bootc's install_t from services, see DEV.md "SELinux"),
# compiled in Fedora's own container, which has selinux-policy-devel; the
# image gets only the compiled modules, and build.sh installs them.
FROM registry.fedoraproject.org/fedora:44 AS selinux-policy
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False install selinux-policy-devel make
COPY selinux /selinux
RUN make -C /selinux -f /usr/share/selinux/devel/Makefile atlasos_pin.pp atlasos_bootc.pp \
 && install -D -t /out /selinux/atlasos_pin.pp /selinux/atlasos_bootc.pp

# The PIN stack's one PAM module (build_files/pam-pin/), a small C file.
FROM registry.fedoraproject.org/fedora:44 AS pam-pin
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    dnf5 -y --setopt=keepcache=True --setopt=install_weak_deps=False install gcc pam-devel
COPY build_files/pam-pin /pam-pin
# -fcf-protection is x86-only: the image is built for x86_64 only.
RUN install -d /out && gcc -O2 -Wall -Wextra -Werror \
    -fstack-protector-strong -D_FORTIFY_SOURCE=3 -fstack-clash-protection -fcf-protection -fPIC -shared -Wl,-z,relro,-z,now \
    -o /out/pam_atlasos_pin.so /pam-pin/pam_atlasos_pin.c -lpam

# Build scripts and config files, mounted into the build rather than copied
# into the image.
# Each RUN step below sees only its own inputs, so Podman reruns a step (and
# those after it) only when one of them changed: a change to system_files
# doesn't reinstall the packages.
FROM scratch AS ctx-packages
COPY build_files/packages.sh build_files/cleanup.sh /
COPY build_files/keys /keys
COPY build_files/repos /repos

FROM scratch AS ctx-apps
COPY build_files/apps.sh build_files/cleanup.sh /

FROM scratch AS ctx-version
COPY build_files/version.sh build_files/cleanup.sh /

FROM scratch AS ctx
COPY build_files/build.sh build_files/cleanup.sh cosign.pub /
COPY system_files /system_files
COPY branding/cursors /cursors

FROM ${BASE_IMAGE}

ARG BASE_IMAGE

# /var/cache/libdnf5 is bound in from the host by `just build` and CI, which
# keep it between builds. Without that bind, dnf just downloads as usual.
# PACKAGES_DATE (today, from `just build`) reruns the packages step once a
# day even when nothing else changed, so updates from Fedora and the
# third-party repos (Brave above all) never wait for a new base image.
ARG PACKAGES_DATE=
RUN --mount=type=bind,from=ctx-packages,source=/,target=/ctx \
    --mount=type=bind,from=kio,source=/out,target=/kio-rpms \
    --mount=type=bind,from=plasma-setup,source=/out,target=/plasma-setup-rpms \
    --mount=type=tmpfs,dst=/tmp \
    PACKAGES_DATE="${PACKAGES_DATE}" /ctx/packages.sh

RUN --mount=type=bind,from=ctx-apps,source=/,target=/ctx \
    --mount=type=bind,from=framework,source=/out,target=/atlas-framework-rpms \
    --mount=type=bind,from=atlas-apps,source=/out,target=/atlas-rpms \
    --mount=type=bind,from=monitor-app,source=/out,target=/atlas-monitor-rpms \
    --mount=type=bind,from=notepad-app,source=/out,target=/atlas-notepad-rpms \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/apps.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=branding,source=/out,target=/branding \
    --mount=type=bind,from=selinux-policy,source=/out,target=/selinux \
    --mount=type=bind,from=pam-pin,source=/out,target=/pam-pin \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# The version changes every day: declared only here, so it reruns only this.
ARG IMAGE_VERSION=dev
RUN --mount=type=bind,from=ctx-version,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_VERSION="${IMAGE_VERSION}" /ctx/version.sh

RUN bootc container lint

# Last, so only the finished image has it: the VPS runner's cleanup removes
# the images with this label after every job (ci/vps-runner/cleanup.sh), and
# the build steps above, which would otherwise inherit it, are its cache.
LABEL org.atlasos.base-image="${BASE_IMAGE}"
