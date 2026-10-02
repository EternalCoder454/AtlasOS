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
# atlas-updater=<path>`; `just build` and CI pass it). Cargo's registry and
# dnf's downloads are cache mounts, so they survive between builds without
# ending up in an image layer.
FROM registry.fedoraproject.org/fedora:44 AS atlas-apps
COPY --from=atlas-updater / /src
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    /src/packaging/build-rpm.sh /out

# Build scripts and config files, mounted into the build rather than copied
# into the image.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG IMAGE_VERSION=dev
LABEL org.atlasos.base-image="${BASE_IMAGE}"

# /var/cache/libdnf5 is bound in from the host by `just build` and CI, which
# keep it between builds. Without that bind, dnf just downloads as usual.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=branding,source=/out,target=/branding \
    --mount=type=bind,from=atlas-apps,source=/out,target=/atlas-rpms \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_VERSION="${IMAGE_VERSION}" /ctx/build.sh

RUN bootc container lint
