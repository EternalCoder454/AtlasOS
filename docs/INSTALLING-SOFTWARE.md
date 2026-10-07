# Installing software on Telamon OS

Telamon OS is image-based: the system itself (`/usr`) is the same read-only image
on every computer, and it's replaced as a whole when you update. That's what
makes updates safe and Go Back possible. It also means `sudo dnf install`
doesn't work on the system itself. Here's what to use instead, best first.

| You want | Use |
| --- | --- |
| A desktop app (browser, chat, office, games, editors) | Store, which installs Flatpaks from Flathub |
| A command-line tool | Homebrew (`telamon brew` sets it up), or a Toolbox |
| A Fedora package, or a whole dev environment with `dnf` | Toolbox or Distrobox |
| A version of Node, Python, Go, Rust... per project | mise (offered in the installer's "Choose your apps" step) |
| A service or database for development | Podman (`docker` works too) |
| Something that has to be part of the system (a driver, a shell) | `rpm-ostree install`, as a last resort |

## Apps: Store and Flathub

Open **Store** (KDE's Discover) from the launcher, search, and click Install. Apps come from
[Flathub](https://flathub.org) as Flatpaks: they run in their own sandbox,
update separately from the system (Telamon Updater shows their updates too),
and never break an update of the OS. Flatseal (already installed) shows and
changes what each app can access.

From a terminal it's the same thing:

```sh
flatpak search obsidian
flatpak install flathub md.obsidian.Obsidian
```

## Command-line tools: Homebrew

[Homebrew](https://brew.sh) has the newest versions of thousands of
command-line tools. It installs them without root, in /home/linuxbrew:

```sh
telamon brew            # once: installs Homebrew in /home/linuxbrew
brew install lazygit  # then, in a new terminal
```

Homebrew's commands come after the system's in your `PATH`, so a formula
never replaces something Telamon OS itself uses. Use Homebrew for command-line
tools, not for desktop apps (that's Flathub) or libraries.

## A Fedora with dnf: Toolbox and Distrobox

A Toolbox is a normal, writable Fedora in a container that shares your home
folder, your user and your screen. Inside it `dnf` works as usual:

```sh
toolbox create
toolbox enter
sudo dnf install gcc-c++ cmake qt6-qtbase-devel
```

Distrobox does the same with any distribution (Ubuntu, Arch, Debian...) and
can add an app from inside to your launcher with `distrobox-export`.
`telamon distroshelf` installs DistroShelf, an app to manage them.

Break one and nothing else notices: delete it (`toolbox rm -f`) and make a
new one.

## Language versions: mise

[mise](https://mise.jdx.dev) is offered in the installer's "Choose your apps" step and switches Node, Python,
Go, Rust, Java and many more per project:

```sh
mise use node@22       # in a project folder: writes mise.toml there
mise use -g python@3.13  # your default everywhere else
```

## Services for development: Podman

Podman runs containers without a daemon or root. The `docker` command and
`docker compose` work and use Podman. For VS Code's Dev Containers and other
tools that want Docker's socket, run `telamon devcontainers` once and log in
again.

JetBrains IDEs: `telamon jetbrains-toolbox` installs JetBrains Toolbox, which
installs and updates the IDEs in your home folder.

## Last resort: rpm-ostree install

Some things have to be part of the system itself: a kernel driver, a login
shell, a program that must run as root at boot. For those:

```sh
sudo rpm-ostree install <package>
```

Restart to use it. It works, and Telamon OS keeps it across updates, but it has
costs:

- Every update takes longer: the package is installed again on each new image.
- An update can fail when the package no longer fits the new Fedora packages.
- Telamon Updater and the background updates switch to rpm-ostree for your
  computer, which is slower than bootc.

`rpm-ostree status` shows what you added, and
`sudo rpm-ostree uninstall <package>` (or `sudo rpm-ostree reset`, which
removes everything you added) undoes it.

## Everything `telamon` does

Run `telamon` alone for the list (`atlas`, its old name, still works). Each command does one thing when you ask:

| Command | What it does |
| --- | --- |
| `telamon info` | Which Telamon OS you run and the image it updates from |
| `telamon channel stable` / `testing` | Switch update channel, from the next restart |
| `telamon brew` | Install Homebrew |
| `telamon devcontainers` | Turn on Podman's Docker socket for Docker tools |
| `telamon distroshelf` | Install DistroShelf for your Distrobox containers |
| `telamon jetbrains-toolbox` | Install JetBrains Toolbox |
