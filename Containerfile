# Telamon OS: a minimal Fedora Kinoite 44 desktop, built as a bootc image.

# The base. CI passes the digest it resolved, so the image records exactly
# which Kinoite it was built on (the org.telamon.base-image label below).
ARG BASE_IMAGE=quay.io/fedora/fedora-kinoite:44

# Logos, icons and wallpapers, rendered from branding/. A separate
# stage so the SVG tools never reach the OS, and so this layer is cached until
# branding/ changes.
FROM docker.io/library/alpine:3.24 AS branding
RUN apk add --no-cache rsvg-convert imagemagick imagemagick-jpeg imagemagick-jxl
COPY branding /branding
RUN sh /branding/render.sh /branding /out

# telamon-framework, the shared base of the Telamon apps (Telamon.Ui, its Material
# Symbols fonts and the Atlas Symbols gallery), built into RPMs the same way
# from the build context named "telamon-framework"
# (EternalCoder454/atlas-framework). The apps below are built against these
# RPMs (TELAMON_LOCAL_RPMS, see build-rpm.sh in each app), and apps.sh installs
# them before the apps. The stage has its own name: a stage named like the
# build context would hide it from COPY --from.
FROM registry.fedoraproject.org/fedora:44 AS framework
COPY --from=telamon-framework --exclude=.git --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
# atlas-framework 1.5.0's (and later) build-rpm.sh packages git's HEAD, and the context
# is the pinned tree without .git: commit that tree into a throwaway
# repository (fixed author and date, so this layer stays cacheable) whose HEAD
# is exactly the pin. The image's label names the real commit.
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    dnf -y install git-core && \
    git -C /src init -q && git -C /src add -A -f && \
    GIT_AUTHOR_DATE='1970-01-01T00:00:01Z' GIT_COMMITTER_DATE='1970-01-01T00:00:01Z' git -C /src \
        -c user.name=Telamon -c user.email=build@telamon.invalid commit -qm pin
RUN --mount=type=cache,target=/var/cache/telamon-framework-build,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    TELAMON_BUILD_CACHE=/var/cache/telamon-framework-build ATLAS_BUILD_CACHE=/var/cache/telamon-framework-build drop-build-deps.sh /src/packaging/build-rpm.sh /out

# The Telamon apps (Telamon Updater and telamon-system-helper), built into RPMs in a Fedora 44
# container, the release the image is based on. The source is the build
# context named "telamon-updater" (`podman build --build-context
# telamon-updater=<path>`; `just build` and CI pass it). Cargo's downloads and
# build output (TELAMON_BUILD_CACHE, see build-rpm.sh there) and dnf's downloads
# are cache mounts, so they survive between builds without ending up in an
# image layer. Only a machine that keeps its Podman storage benefits: the VPS
# runner and local builds (see CI.md).
# Without what build-rpm.sh leaves out of the source too: .git differs in every
# checkout, so with it this step and the build after it never come from the
# cache, and a local checkout's build output is gigabytes.
FROM registry.fedoraproject.org/fedora:44 AS updater-app
COPY --from=telamon-updater --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-updater-build,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    TELAMON_BUILD_CACHE=/var/cache/telamon-updater-build ATLAS_BUILD_CACHE=/var/cache/telamon-updater-build drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Monitor, built the same way from the build context named
# "telamon-monitor" (EternalCoder454/atlasos-monitor). A stage of its own, so a
# change to one app doesn't rebuild the other. Cargo's crate downloads are a
# cache mount (CARGO_HOME, see the spec there). Its build fetches the
# telamon-framework crates from GitHub at the commit its Cargo.toml pins, so it
# needs the network. Like Telamon Updater, it is built against the framework
# RPMs (TELAMON_LOCAL_RPMS).
FROM registry.fedoraproject.org/fedora:44 AS monitor-app
COPY --from=telamon-monitor --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-monitor-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-monitor-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Notepad, built the same way as Telamon Monitor from the build context
# named "telamon-notepad" (the Telamon Notepad source).
FROM registry.fedoraproject.org/fedora:44 AS notepad-app
COPY --from=telamon-notepad --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-notepad-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-notepad-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Settings, built the same way from the build context named
# "telamon-settings". Its telamon-settings-systemsettings subpackage replaces
# plasma-systemsettings (apps.sh); every KDE KCM stays, for kcmshell6.
FROM registry.fedoraproject.org/fedora:44 AS settings-app
COPY --from=telamon-settings --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-settings-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-settings-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Setup, the first-run setup (replaces plasma-setup), built the same
# way from the build context named "telamon-wizard". Its build-rpm.sh wants a
# git checkout for HEAD, which the copy leaves out, so it builds the tree it is
# given (TELAMON_RPM_WORKTREE=1 ATLAS_RPM_WORKTREE=1): the pinned commit, which CI and `just build`
# check out or copy, labelled in the image's net.eterneon.telamon.wizard.revision.
FROM registry.fedoraproject.org/fedora:44 AS wizard-app
COPY --from=telamon-wizard --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-wizard-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms TELAMON_RPM_WORKTREE=1 ATLAS_RPM_WORKTREE=1 \
    CARGO_HOME=/var/cache/telamon-wizard-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Store, the app store added beside Discover, built the same way from the
# build context named "telamon-store". Its build-rpm.sh tars the tree it is
# given (no git needed), so no TELAMON_RPM_WORKTREE; the pinned commit is labelled
# in the image's net.eterneon.telamon.store.revision.
FROM registry.fedoraproject.org/fedora:44 AS store-app
COPY --from=telamon-store --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-store-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-store-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Archive, the archive manager (replaces Ark), built the same way from the
# build context named "telamon-archive". Its build-rpm.sh tars the tree it is
# given (no git needed), so no TELAMON_RPM_WORKTREE; the pinned commit is labelled
# in net.eterneon.telamon.archive.revision.
FROM registry.fedoraproject.org/fedora:44 AS archive-app
COPY --from=telamon-archive --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-archive-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-archive-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Launcher, the app launcher (replaces Andromeda), built the same way from
# the build context named "telamon-launcher". Its build-rpm.sh tars the tree it is
# given (no git needed), so no TELAMON_RPM_WORKTREE; the pinned commit is labelled
# in net.eterneon.telamon.launcher.revision.
FROM registry.fedoraproject.org/fedora:44 AS launcher-app
COPY --from=telamon-launcher --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-launcher-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-launcher-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Screenshot (Meta+Shift+S: freeze, drag, copy; Ctrl for OCR text,
# Alt for a redacted PNG), built from the build context named
# "telamon-screenshot". The capture program has no Qt; the annotation editor
# (telamon-screenshot-editor) is Qt Quick on Telamon.Ui, so this stage builds
# against the framework's RPMs. Its build-rpm.sh tars the tree it is given (no
# git needed). Makes telamon-screenshot and the telamon-screenshot-spectacle-compat
# subpackage (apps.sh installs both, packages.sh removes Spectacle first). The
# pinned commit is labelled in net.eterneon.telamon.screenshot.revision.
FROM registry.fedoraproject.org/fedora:44 AS screenshot-app
COPY --from=telamon-screenshot --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-screenshot-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms \
    CARGO_HOME=/var/cache/telamon-screenshot-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# Telamon Explorer (Files), the file manager and its index service, built the same
# way from the build context named "telamon-explorer"; the pinned commit is
# labelled in net.eterneon.telamon.explorer.revision.
FROM registry.fedoraproject.org/fedora:44 AS explorer-app
COPY --from=telamon-explorer --exclude=.git --exclude=target --exclude=out --exclude=build / /src
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/telamon-explorer-cargo,sharing=locked \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    TELAMON_LOCAL_RPMS=/telamon-framework-rpms ATLAS_LOCAL_RPMS=/telamon-framework-rpms TELAMON_RPM_WORKTREE=1 ATLAS_RPM_WORKTREE=1 \
    CARGO_HOME=/var/cache/telamon-explorer-cargo drop-build-deps.sh /src/packaging/build-rpm.sh /out

# KIO with Telamon OS's crash fix (see build_files/kio/build-rpm.sh): Fedora's
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

# The login screen with Telamon OS's placeholder (see build_files/login/build-rpm.sh):
# Fedora's plasma-login-manager, rebuilt at the version the base image has.
FROM ${BASE_IMAGE} AS base-login
RUN rpm -q plasma-login-manager --qf '%{VERSION}-%{RELEASE}' >/login-nvr

FROM registry.fedoraproject.org/fedora:44 AS login
COPY --from=base-login /login-nvr /login-nvr
COPY build_files/login /login
COPY build_files/drop-build-deps.sh /usr/local/bin/
RUN echo keepcache=True >>/etc/dnf/dnf.conf
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    drop-build-deps.sh /login/build-rpm.sh /out

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
# third-party repos never wait for a new base image.
ARG PACKAGES_DATE=
RUN --mount=type=bind,from=ctx-packages,source=/,target=/ctx \
    --mount=type=bind,from=kio,source=/out,target=/kio-rpms \
    --mount=type=bind,from=login,source=/out,target=/login-rpms \
    --mount=type=tmpfs,dst=/tmp \
    PACKAGES_DATE="${PACKAGES_DATE}" /ctx/packages.sh

RUN --mount=type=bind,from=ctx-apps,source=/,target=/ctx \
    --mount=type=bind,from=framework,source=/out,target=/telamon-framework-rpms \
    --mount=type=bind,from=updater-app,source=/out,target=/telamon-updater-rpms \
    --mount=type=bind,from=monitor-app,source=/out,target=/telamon-monitor-rpms \
    --mount=type=bind,from=notepad-app,source=/out,target=/telamon-notepad-rpms \
    --mount=type=bind,from=settings-app,source=/out,target=/telamon-settings-rpms \
    --mount=type=bind,from=wizard-app,source=/out,target=/telamon-wizard-rpms \
    --mount=type=bind,from=store-app,source=/out,target=/telamon-store-rpms \
    --mount=type=bind,from=explorer-app,source=/out,target=/telamon-explorer-rpms \
    --mount=type=bind,from=archive-app,source=/out,target=/telamon-archive-rpms \
    --mount=type=bind,from=launcher-app,source=/out,target=/telamon-launcher-rpms \
    --mount=type=bind,from=screenshot-app,source=/out,target=/telamon-screenshot-rpms \
    --mount=type=bind,from=telamon-installer,source=/firstboot,target=/telamon-firstboot \
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
# (org.atlasos.base-image is the same label under its name before Telamon: the
# VPS runner's own cleanup.sh, which is installed beside the runner and not
# updated with this repository, still looks for it.)
LABEL org.telamon.base-image="${BASE_IMAGE}" \
      org.atlasos.base-image="${BASE_IMAGE}"
