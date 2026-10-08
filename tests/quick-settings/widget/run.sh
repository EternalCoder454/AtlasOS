#!/bin/sh
# Tests the Quick Settings widget (system_files/usr/share/plasma/plasmoids/
# org.telamon.quicksettings) in a container, with the widget's QML run under
# Qt Test against real Plasma modules and these services on private buses:
#
#   PipeWire, two null outputs (Speakers, Headphones) and two playing apps
#   NetworkManager, BlueZ, UPower, power-profiles-daemon (python-dbusmock)
#   PowerDevil's brightness and power profiles (powerdevil_mock.py)
#
# It moves a stream between the outputs from the keyboard, sets an app's
# volume and mute with the mouse, connects to Wi-Fi networks (a password
# typed for a new one reaches NetworkManager), connects a Bluetooth device,
# changes the power profile and brightness, and walks the controls with Tab,
# then asks PulseAudio, NetworkManager and the mocks what happened. A second
# pass, as a desktop (no battery, Bluetooth, brightness control or Wi-Fi),
# checks those sections stay out of the way. No GPU or compositor is needed.
#
#   tests/quick-settings/widget/run.sh [IMAGE]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
image=${1:-ghcr.io/eternalcoder454/telamonos:testing}
tag=localhost/telamon-quicksettings-test:$(printf %s "$image" | cksum | cut -d' ' -f1)
podman image exists "$tag" || podman build --ulimit core=0 -q --build-arg "IMAGE=$image" -t "$tag" -f "$here/Containerfile" "$here" >/dev/null
# core=0: a crash in the container must not land in the host's core dumps
exec podman run --rm --ulimit core=0 --network=none --security-opt label=disable \
	-v "$here/..:/t:ro" -v "$repo/system_files/usr/share/plasma/plasmoids/org.telamon.quicksettings:/usr/share/plasma/plasmoids/org.telamon.quicksettings:ro" \
	"$tag" bash /t/widget/inner.sh
