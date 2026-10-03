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

# The Atlas apps (Atlas Updater and atlas-core), built into RPMs in a Fedora 44
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
    ATLAS_BUILD_CACHE=/var/cache/atlas-build drop-build-deps.sh /src/packaging/build-rpm.sh /out

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

# Build scripts and config files, mounted into the build rather than copied
# into the image.
# Each RUN step below sees only its own inputs, so Podman reruns a step (and
# those after it) only when one of them changed: a change to system_files
# doesn't reinstall the packages.
FROM scratch AS ctx-packages
COPY build_files/packages.sh build_files/cleanup.sh /

FROM scratch AS ctx-apps
COPY build_files/apps.sh build_files/cleanup.sh /

FROM scratch AS ctx-version
COPY build_files/version.sh /

FROM scratch AS ctx
COPY build_files/build.sh build_files/cleanup.sh /
COPY system_files /system_files
COPY branding/cursors /cursors
COPY branding/icon-theme /icon-theme

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
    --mount=type=bind,from=atlas-apps,source=/out,target=/atlas-rpms \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/apps.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=branding,source=/out,target=/branding \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# The version changes every day: declared only here, so it reruns only this.
ARG IMAGE_VERSION=dev
RUN --mount=type=bind,from=ctx-version,source=/,target=/ctx \
    IMAGE_VERSION="${IMAGE_VERSION}" /ctx/version.sh

RUN bootc container lint

# Last, so only the finished image has it: the VPS runner's cleanup removes
# the images with this label after every job (ci/vps-runner/cleanup.sh), and
# the build steps above, which would otherwise inherit it, are its cache.
LABEL org.atlasos.base-image="${BASE_IMAGE}"
