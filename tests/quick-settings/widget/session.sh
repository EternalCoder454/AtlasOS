#!/bin/bash
# shellcheck disable=SC2016 # the checks are strings that chk evaluates
# A private session bus (from dbus-run-session): PipeWire, mocks, then the QML tests of the scene.
set -uo pipefail
scene=$1
here=/t/widget
export XDG_RUNTIME_DIR HOME

# --- audio: PipeWire with two null outputs and a microphone, PulseAudio protocol on top
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat >"$HOME/.config/pipewire/pipewire.conf.d/10-null.conf" <<'CONF'
context.objects = [
  { factory = adapter
    args = { factory.name = support.null-audio-sink node.name = "speakers" node.description = "Speakers"
             media.class = Audio/Sink object.linger = true audio.position = [ FL FR ] } }
  { factory = adapter
    args = { factory.name = support.null-audio-sink node.name = "headphones" node.description = "Headphones"
             media.class = Audio/Sink object.linger = true audio.position = [ FL FR ] } }
]
CONF
pipewire >/tmp/pipewire.log 2>&1 &
sleep 1
wireplumber >/tmp/wireplumber.log 2>&1 &
pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &
sleep 2

# --- the system services, on a private system bus
dbus-daemon --config-file="$here/sys.conf" --fork >/dev/null
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/system_bus_socket
for t in upower upower_power_profiles_daemon networkmanager bluez5; do
	python3 -m dbusmock --system -t "$t" >"/tmp/mock-$t.log" 2>&1 &
done
sleep 3
python3 "$here/mock_setup.py" "$scene" >/tmp/mock-setup.log 2>&1 || { cat /tmp/mock-setup.log; exit 1; }
python3 "$here/powerdevil_mock.py" >/tmp/mock-powerdevil.log 2>&1 &
sleep 1

fail=0
chk() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
qtest() { # file
	(cd /tmp && timeout 120 /usr/lib64/qt6/bin/qmltestrunner -input "$here/$1" -o "/tmp/out/$1.txt,txt" >"/tmp/out/$1.log" 2>&1)
	grep -E "^(PASS|FAIL|Totals)|Loc:" "/tmp/out/$1.txt"
	if grep -q "^FAIL" "/tmp/out/$1.txt" || ! grep -q "^Totals" "/tmp/out/$1.txt"; then fail=1; fi
}

if [ "$scene" = laptop ]; then
	# two apps playing, to move between the outputs
	python3 - <<'PY'
import wave, struct, math
w = wave.open("/tmp/tone.wav", "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<hh", s, s) for s in (int(8000 * math.sin(2 * math.pi * 330 * i / 48000)) for i in range(48000 * 120))))
w.close()
PY
	paplay --client-name="YouTube Music" --property=media.name="Lofi beats" /tmp/tone.wav &
	paplay --client-name="Discord" /tmp/tone.wav &
	sleep 2

	echo "== sound"
	qtest tst_sound.qml
	# PulseAudio's own view of what the UI did
	rows=$(pactl -f json list sink-inputs)
	sinks=$(pactl -f json list sinks)
	field() { echo "$rows" | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    if s['properties'].get('application.name') == '$1':
        print($2)"; }
	sinkname() { echo "$sinks" | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    if s['index'] == $1: print(s['name'])"; }
	yt=$(sinkname "$(field 'YouTube Music' "s['sink']")")
	dc=$(sinkname "$(field Discord "s['sink']")")
	pct() { field "$1" "round(float(list(s['volume'].values())[0]['value_percent'].rstrip('%')))"; }
	chk "YouTube Music was moved to the headphones (is on $yt)" '[ "$yt" = headphones ]'
	chk "Discord stayed on the speakers (is on $dc)" '[ "$dc" = speakers ]'
	chk "Discord is muted" '[ "$(field Discord "s[\"mute\"]")" = True ]'
	chk "Discord's volume is about 25 % (is $(pct Discord))" '[ "$(pct Discord)" -ge 15 ] && [ "$(pct Discord)" -le 35 ]'
	chk "YouTube Music's volume is untouched (is $(pct 'YouTube Music'))" '[ "$(pct "YouTube Music")" = 100 ]'
	chk "the speakers are muted by the main mute button" '[ "$(pactl get-sink-mute speakers)" = "Mute: yes" ]'
	pkill paplay || true

	echo "== display, power, Wi-Fi, Bluetooth"
	qtest tst_misc.qml
	chk "the first display was set to about 30 % (writes: $(tr '\n' ' ' </tmp/brightness.log))" 'grep -qE "^display0=(2[2-9]|3[0-8])$" /tmp/brightness.log'
	chk "connecting to the open network asked NetworkManager (AddAndActivateConnection)" 'grep -q "AddAndActivateConnection.*Cafe Guest\|AddAndActivateConnection.*\[67, 97, 102, 101" /tmp/mock-networkmanager.log'
	chk "PowerDevil was asked for the performance profile" 'grep -qx performance /tmp/profile.log'
	chk "NetworkManager got a connection with the password typed" 'grep -q "\"psk\": \"correct horse battery\"" /tmp/mock-networkmanager.log'
	chk "the password is in no test output" '! grep -rq "correct horse battery" /tmp/out/'

	echo "== keyboard"
	qtest tst_keys.qml
else
	echo "== a desktop: no battery, Bluetooth, brightness control or Wi-Fi"
	qtest tst_desktop.qml
fi
[ "$fail" = 0 ]
