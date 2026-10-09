# Homebrew (https://brew.sh), once `telamon brew` installed it: its commands come
# after the system's in PATH, so a formula never replaces a command Telamon OS
# itself uses (Homebrew's own `brew shellenv` would put them first).
# Only for the user who owns the prefix, never for root or another user: whoever
# owns it can put a program there, and root must not run it by typing the name
# of a command the base image lacks.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && [ "$(id -u)" != 0 ] &&
	[ "$(stat -c %u /home/linuxbrew/.linuxbrew/bin/brew 2>/dev/null)" = "$(id -u)" ]; then
	export HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
	export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
	export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
	case ":$PATH:" in
	*":$HOMEBREW_PREFIX/bin:"*) ;;
	*)
		PATH="$PATH:$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin"
		# The empty entry keeps man's and info's default search path.
		export MANPATH="${MANPATH-}:$HOMEBREW_PREFIX/share/man"
		export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH-}"
		;;
	esac
fi
