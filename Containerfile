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
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_VERSION="${IMAGE_VERSION}" /ctx/build.sh

RUN bootc container lint
