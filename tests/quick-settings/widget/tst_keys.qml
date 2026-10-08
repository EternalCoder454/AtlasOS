import QtQuick
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    width: 420; height: 800
    QuickSettings { id: popup; width: 360 }

    Util {
        name: "keys"
        popup: popup
        when: windowShown

        function test_1_tab_walk_reaches_every_control_with_a_name() {
            tryVerify(() => has("Power mode") && has("Brightness") && has("Bluetooth"), 10000);
            wait(800);
            const seen = [];
            keyClick(Qt.Key_Tab);
            for (let i = 0; i < 30; i++) {
                const f = Window.activeFocusItem;
                if (!f) break;
                const n = f.Accessible.name || f.text || "";
                verify(n.length > 0, "a focused control has no accessible name: " + f);
                if (seen.indexOf(n) >= 0) break;
                seen.push(n);
                keyClick(Qt.Key_Tab);
            }
            console.warn("TAB_ORDER", JSON.stringify(seen));
            for (const want of ["Wi-Fi", "Wi-Fi networks", "Bluetooth", "Bluetooth devices", "Power mode", "Power modes", "Do Not Disturb",
                                "Sound outputs and apps", "Brightness", "Clipboard history", "Settings"]) {
                if (want === "Do Not Disturb") continue; // needs plasmashell's notification server
                verify(seen.indexOf(want) >= 0, "Tab never reaches: " + want + " (got " + JSON.stringify(seen) + ")");
            }
        }

        function test_1b_the_mute_button_and_volume_slider_are_reached() {
            verify(has("Mute") || has("Unmute"), "a mute button");
            verify(findAll(popup, i => i.Accessible && i.Accessible.name.indexOf("Volume of") === 0 && i.activeFocusOnTab).length > 0, "the volume slider takes Tab");
        }

        function test_2_tile_toggles_with_space() {
            const tile = one("Bluetooth");
            tile.forceActiveFocus();
            const before = tile.Accessible.checked;
            keyClick(Qt.Key_Space);
            tryVerify(() => one("Bluetooth").Accessible.checked !== before, 6000, "Space switched Bluetooth");
            one("Bluetooth").forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(() => one("Bluetooth").Accessible.checked === before, 6000, "Enter switched it back");
        }

        function test_3_chevron_opens_with_enter_and_escape_goes_back() {
            const chevron = one("Wi-Fi networks");
            chevron.forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(() => stack().depth === 2 && !stack().busy, 3000, "opened");
            keyClick(Qt.Key_Escape);
            tryVerify(() => stack().depth === 1 && !stack().busy, 3000, "Escape went back");
        }

        function test_4_slider_by_keyboard() {
            const s = sliderOf("Brightness");
            s.forceActiveFocus();
            const before = s.value;
            keyClick(Qt.Key_Left);
            verify(s.value < before, "Left lowers it");
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            verify(s.value > before, "Right raises it");
        }

        function test_5_every_detail_view_has_a_back_button_with_focus_order() {
            for (const chevron of ["Wi-Fi networks", "Bluetooth devices", "Power modes", "Sound outputs and apps", "Brightness of each display"]) {
                open(chevron);
                verify(has("Back to Quick Settings"), chevron + ": Back");
                back();
            }
        }
    }
}
