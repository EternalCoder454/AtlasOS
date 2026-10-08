import QtQuick
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    width: 420; height: 700
    QuickSettings { id: popup; width: 360 }

    Util {
        name: "sound"
        popup: popup
        when: windowShown

        function appRows() { return findAll(popup, i => i.hasOwnProperty("appName") && i.visible); }
        function app(name) {
            const r = appRows().filter(a => a.appName === name);
            verify(r.length === 1, "one row for " + name + ": " + r.length);
            return r[0];
        }
        function pickerOf(row) { return findAll(row, i => i.hasOwnProperty("textRole") && i.hasOwnProperty("valueRole"))[0]; }

        function test_0_main_volume_with_mouse() {
            tryVerify(() => has("Volume of Speakers"), 8000, "the volume slider");
            const s = sliderOf("Volume of Speakers");
            clickSlider(s, 0.5);
            wait(300);
            verify(Math.abs(s.value / s.to - 0.5) < 0.08, "slider at " + s.value / s.to);
        }

        function test_1_main_mute_button() {
            const b = one("Mute");
            mouseClick(b);
            tryVerify(() => has("Unmute"), 3000, "the button now unmutes");
        }

        function test_2_sound_view_lists_outputs_and_apps() {
            open("Sound outputs and apps");
            tryVerify(() => appRows().length >= 2, 8000, "apps listed");
            compare(appRows().length, 2);
            app("YouTube Music"); app("Discord");
            // the outputs: both, the one in use ticked
            const speakers = one("Speakers");
            compare(speakers.Accessible.checked, true);
            compare(one("Headphones").Accessible.checked, false);
        }

        function test_3_move_a_stream_with_the_keyboard() {
            const picker = pickerOf(app("YouTube Music"));
            compare(picker.count, 2);
            compare(picker.currentText, "Speakers");
            picker.forceActiveFocus();
            verify(picker.activeFocus);
            keyClick(Qt.Key_Down);
            compare(picker.currentText, "Headphones");
            compare(pickerOf(app("Discord")).currentText, "Speakers");
            wait(500);
            // the model follows what PulseAudio reports
            compare(pickerOf(app("YouTube Music")).currentText, "Headphones");
        }

        function test_4_per_app_volume_with_the_mouse() {
            const s = sliderOf("Volume of Discord");
            clickSlider(s, 0.25);
            wait(300);
            verify(Math.abs(s.value / s.to - 0.25) < 0.08, "slider at " + s.value / s.to);
        }

        function test_5_per_app_mute() {
            mouseClick(one("Mute Discord"));
            tryVerify(() => has("Unmute Discord"), 3000);
        }
    }
}
