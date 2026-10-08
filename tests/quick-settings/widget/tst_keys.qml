import QtQuick
import QtQuick.Layouts
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    id: root
    width: 420; height: 1200
    ColumnLayout {
        width: 400
        SoundCard { id: sound }
        DisplayCard { id: display }
        NetworkCard { id: network }
        BluetoothCard { id: bluetooth }
        PowerCard { id: power }
    }
    TestCase {
        name: "keys"
        when: windowShown
        function name(item) {
            return item.Accessible.name || item.text || "";
        }
        function test_tab_walk_reaches_every_control_with_a_name() {
            tryVerify(() => power.visible && bluetooth.on, 10000);
            wait(1500);
            const seen = [];
            // start at the first focusable control
            keyClick(Qt.Key_Tab);
            for (let i = 0; i < 30; i++) {
                const f = Window.activeFocusItem ? Window.activeFocusItem : null;
                if (!f) break;
                const n = name(f);
                seen.push(n);
                verify(n.length > 0, "a focused control has no accessible name: " + f);
                keyClick(Qt.Key_Tab);
                if (seen.length > 3 && n === seen[0]) break;
            }
            console.warn("TAB_ORDER", JSON.stringify(seen));
            for (const want of ["Sound", "Open Sound settings", "Open Display settings", "Wi-Fi", "Open Network settings", "Bluetooth", "Open Bluetooth settings", "Open Power settings"]) {
                verify(seen.indexOf(want) >= 0, "Tab never reaches: " + want);
            }
        }
        function test_header_opens_with_space_and_enter() {
            const hdr = (function find(i) {
                if (i.hasOwnProperty("checkable") && i.hasOwnProperty("highlighted") && i.Accessible.name === "Sound") return i;
                for (let k = 0; k < i.children.length; k++) { const r = find(i.children[k]); if (r) return r; }
                return null;
            })(sound);
            verify(hdr, "the Sound header button");
            verify(!sound.expanded);
            hdr.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(sound.expanded, "Space opens the details");
            keyClick(Qt.Key_Return);
            verify(!sound.expanded, "Enter closes them");
        }
        function test_slider_by_keyboard() {
            const sliders = [];
            (function walk(i) { if (i.hasOwnProperty("snapMode") && i.hasOwnProperty("handle")) sliders.push(i); for (let k = 0; k < i.children.length; k++) walk(i.children[k]); })(display);
            verify(sliders.length >= 1);
            const s = sliders[0];
            s.forceActiveFocus();
            const before = s.value;
            keyClick(Qt.Key_Left);
            verify(s.value < before, "Left lowers it");
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            verify(s.value > before, "Right raises it");
        }
    }
}
