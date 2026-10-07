# Ghostty has no system-wide configuration, so each user gets Telamon OS's
# (/etc/skel) once, at their first Plasma session: new users and users from
# before it existed. Never over a config of their own, and not again after they
# delete it.
state="${XDG_STATE_HOME:-$HOME/.local/state}/atlasos"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
if [ ! -e "$state/ghostty-config" ]; then
	mkdir -p "$state" && : >"$state/ghostty-config"
	if [ ! -e "$cfg/config" ] && [ ! -e "$cfg/config.ghostty" ] && [ -f /etc/skel/.config/ghostty/config ]; then
		mkdir -p "$cfg" && cp /etc/skel/.config/ghostty/config "$cfg/config"
	fi
fi
