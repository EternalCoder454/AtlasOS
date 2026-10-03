# Homebrew (https://brew.sh), once `atlas brew` installed it: its commands come
# after the system's in PATH, so a formula never replaces a command AtlasOS
# itself uses (Homebrew's own `brew shellenv` would put them first).
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
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
