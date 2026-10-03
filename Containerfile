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
FROM registry.fedoraproject.org/fedora:44 AS atlas-apps
COPY --from=atlas-updater / /src
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/atlas-build,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    ATLAS_BUILD_CACHE=/var/cache/atlas-build /src/packaging/build-rpm.sh /out

# KIO with AtlasOS's crash fix (see build_files/kio/build-rpm.sh): Fedora's
# kf6-kio, rebuilt at the version the base image has.
FROM ${BASE_IMAGE} AS base-kio
RUN rpm -q kf6-kio-core --qf '%{VERSION}-%{RELEASE}' >/kio-nvr

FROM registry.fedoraproject.org/fedora:44 AS kio
COPY --from=base-kio /kio-nvr /kio-nvr
COPY build_files/kio /kio
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    /kio/build-rpm.sh /out

# The first-run wizard in AtlasOS's style (see
# build_files/plasma-setup/build-rpm.sh): Fedora's plasma-setup, rebuilt at
# the version the base image has.
FROM ${BASE_IMAGE} AS base-plasma-setup
RUN rpm -q plasma-setup --qf '%{VERSION}-%{RELEASE}' >/plasma-setup-nvr

FROM registry.fedoraproject.org/fedora:44 AS plasma-setup
COPY --from=base-plasma-setup /plasma-setup-nvr /plasma-setup-nvr
COPY build_files/plasma-setup /plasma-setup
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    /plasma-setup/build-rpm.sh /out

# Build scripts and config files, mounted into the build rather than copied
# into the image.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY branding/cursors /cursors
COPY branding/icon-theme /icon-theme

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG IMAGE_VERSION=dev
LABEL org.atlasos.base-image="${BASE_IMAGE}"

# /var/cache/libdnf5 is bound in from the host by `just build` and CI, which
# keep it between builds. Without that bind, dnf just downloads as usual.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=branding,source=/out,target=/branding \
    --mount=type=bind,from=atlas-apps,source=/out,target=/atlas-rpms \
    --mount=type=bind,from=kio,source=/out,target=/kio-rpms \
    --mount=type=bind,from=plasma-setup,source=/out,target=/plasma-setup-rpms \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_VERSION="${IMAGE_VERSION}" /ctx/build.sh

RUN bootc container lint
