#!/bin/bash
# Inside the container: one private session per scene.
set -uo pipefail
export HOME=/tmp/h XDG_RUNTIME_DIR=/tmp/rt LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" /var/lib/dbus /tmp/out
chmod 700 "$XDG_RUNTIME_DIR"
[ -s /var/lib/dbus/machine-id ] || dbus-uuidgen >/var/lib/dbus/machine-id
status=0
for scene in laptop desktop; do
	rm -rf "$XDG_RUNTIME_DIR" "$HOME"
	mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
	chmod 700 "$XDG_RUNTIME_DIR"
	echo "===== scene: $scene"
	MOCK_SCENE=$scene timeout 300 dbus-run-session -- bash /t/widget/session.sh "$scene" 2>"/tmp/out/session-$scene.err" || status=1
done
[ "$status" = 0 ] && echo "ALL OK" || echo "SOME FAILED"
exit "$status"
