# AtlasOS's command menu: `atlas <command>` (/usr/bin/atlas runs this file
# with just, in your home folder). `atlas` alone lists the commands.
# Nothing here runs by itself; each command does one thing when you ask.

[private]
default:
    @echo 'AtlasOS commands (atlas <command>):'
    @just --justfile "{{ justfile() }}" --list --unsorted --list-heading ''

# Which AtlasOS this computer runs, and the image it updates from
info:
    #!/bin/bash
    set -euo pipefail
    . /usr/lib/os-release
    echo "$PRETTY_NAME"
    origin=$(rpm-ostree status --json | jq -r '.deployments[] | select(.booted) | .["container-image-reference"] // empty')
    case $origin in
    ostree-image-signed:*) echo "Updates from ${origin#*docker://} (signature checked)" ;;
    ostree-unverified-registry:*) echo "Updates from ${origin#*:} (signature not checked yet)" ;;
    *) echo "Updates from $origin" ;;
    esac

# Follow the stable or testing channel, from the next restart
channel name:
    #!/bin/bash
    set -euo pipefail
    case "{{ name }}" in
    stable | testing) ;;
    *) echo "atlas channel: the channel is stable or testing, not \"{{ name }}\"" >&2; exit 1 ;;
    esac
    # The newest deployment's image (a staged update's, if there is one), with
    # its tag replaced. Its signature setting stays. rpm-ostree, not bootc:
    # it also keeps packages added with `rpm-ostree install`.
    origin=$(rpm-ostree status --json | jq -r '.deployments[0]["container-image-reference"] // empty')
    case $origin in
    ostree-image-signed:docker://*) kind=ostree-image-signed:docker:// ;;
    ostree-unverified-registry:*) kind=ostree-unverified-registry: ;;
    *) echo "atlas channel: this computer follows ${origin:-no image}, not an AtlasOS channel" >&2; exit 1 ;;
    esac
    image=${origin#"$kind"}
    image=${image%@*}
    repo=${image%:*}
    case $repo in
    ghcr.io/eternalcoder454/atlasos | ghcr.io/eternalcoder454/atlasos-nvidia) ;;
    *) echo "atlas channel: $image is not an AtlasOS image" >&2; exit 1 ;;
    esac
    if [ "$image" = "$repo:{{ name }}" ]; then
        echo "Already following {{ name }}."
        exit 0
    fi
    rpm-ostree rebase "$kind$repo:{{ name }}"
    echo "Restart to start using {{ name }}."

# Install Homebrew, for command-line tools Fedora doesn't package
brew:
    #!/bin/bash
    set -euo pipefail
    prefix=/home/linuxbrew/.linuxbrew
    if [ -x "$prefix/bin/brew" ]; then
        echo "Homebrew is already installed."
        exit 0
    fi
    echo "This runs Homebrew's own installer from https://brew.sh."
    echo "It asks for your password once, to make $prefix yours."
    sudo install -d -o "$(id -u)" -g "$(id -g)" /home/linuxbrew "$prefix"
    NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo
    echo "Done. Open a new terminal, then: brew install <tool>"
    echo "Homebrew's commands come after the system's (/etc/profile.d/atlasos-brew.sh)."

# Let VS Code's Dev Containers and other Docker tools use Podman
devcontainers:
    #!/bin/bash
    set -euo pipefail
    systemctl --user enable --now podman.socket
    mkdir -p ~/.config/environment.d
    printf '%s\n' '# From `atlas devcontainers`: Docker tools talk to Podman.' \
        'DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock' \
        >~/.config/environment.d/50-atlas-podman-socket.conf
    echo "Podman's Docker socket is on. Log out and back in, then Docker tools"
    echo "(VS Code's Dev Containers, docker compose) use Podman."

# Install DistroShelf, an app for your Distrobox containers
distroshelf:
    flatpak install -y flathub com.ranfdev.DistroShelf

# Install JetBrains Toolbox, which installs and updates JetBrains IDEs
jetbrains-toolbox:
    #!/bin/bash
    set -euo pipefail
    dir="$HOME/.local/share/JetBrains/Toolbox"
    if [ ! -x "$dir/bin/jetbrains-toolbox" ]; then
        release=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release')
        url=$(jq -r '.TBA[0].downloads.linux.link' <<<"$release")
        sum=$(jq -r '.TBA[0].downloads.linux.checksumLink' <<<"$release")
        case $url in
        https://download.jetbrains.com/*.tar.gz) ;;
        *) echo "atlas jetbrains-toolbox: unexpected download link: $url" >&2; exit 1 ;;
        esac
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        echo "Downloading $url"
        curl -fL --retry 3 -o "$tmp/toolbox.tar.gz" "$url"
        echo "$(curl -fsSL "$sum" | cut -d' ' -f1)  $tmp/toolbox.tar.gz" | sha256sum -c --quiet
        mkdir -p "$dir"
        tar -xzf "$tmp/toolbox.tar.gz" -C "$dir" --strip-components=1
    fi
    # It adds itself to the app menu and to the apps that start at login.
    # Started by the user's service manager, like an app from the menu: from
    # the terminal's session it quit at once.
    systemd-run --user --quiet --collect "$dir/bin/jetbrains-toolbox"
    echo "JetBrains Toolbox is starting; it is in the app menu from now on."
