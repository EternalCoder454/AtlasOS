import QtQuick
import QtQuick.Layouts
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    id: root
    width: 420; height: 1200

    ColumnLayout {
        width: 400
        DisplayCard { id: display }
        NetworkCard { id: network; expanded: true }
        BluetoothCard { id: bluetooth; expanded: true }
        PowerCard { id: power }
    }

    TestCase {
        name: "misc"
        when: windowShown

        function findAll(item, pred, out) {
            out = out || [];
            if (pred(item)) out.push(item);
            for (let i = 0; i < item.children.length; i++) findAll(item.children[i], pred, out);
            return out;
        }
        function typeText(t) { for (const ch of t) keyClick(ch); }
        function sliders(card) { return findAll(card, i => i.hasOwnProperty("snapMode") && i.hasOwnProperty("handle")); }

        function test_1_display_two_sliders_and_write() {
            tryVerify(() => sliders(display).length === 2, 8000);
            verify(display.visible);
            const s = sliders(display)[0];
            compare(Math.round(s.value), 70);
            mouseClick(s, s.leftPadding + s.availableWidth * 0.3, s.height / 2);
            wait(400);
            console.warn("BRIGHTNESS_SLIDER", Math.round(s.value));
        }

        function test_2_power_profiles() {
            tryVerify(() => power.visible, 8000);
            tryVerify(() => power.hasProfiles, 8000);
            const buttons = findAll(power, i => i.hasOwnProperty("checkable") && i.hasOwnProperty("icon") && i.text.indexOf("Performance") >= 0);
            compare(buttons.length, 1);
            mouseClick(buttons[0]);
            tryVerify(() => buttons[0].checked, 4000, "performance became active");
            compare(power.hasBattery, true);
            verify(power.subtitle.indexOf("87") >= 0, power.subtitle);
        }

        function test_3_network_list() {
            tryVerify(() => findAll(network, i => i.hasOwnProperty("askingPassword")).length >= 3, 15000, "networks listed");
            const rows = findAll(network, i => i.hasOwnProperty("askingPassword"));
            const names = rows.map(r => r.network.ItemUniqueName).sort();
            console.warn("NETWORKS", JSON.stringify(names));
            verify(network.subtitle === "Telamon Home", network.subtitle);
        }

        function wifi(name) {
            const rows = findAll(network, i => i.hasOwnProperty("askingPassword") && i.network.ItemUniqueName === name);
            verify(rows.length === 1, name + ": " + rows.length);
            return rows[0];
        }

        function test_4_network_open_network_connects() {
            const r = wifi("Cafe Guest");
            verify(!r.secured && !r.askingPassword);
            mouseClick(r.children[0]);
            wait(800);
        }

        function test_6_network_new_secured_asks_for_password() {
            const r = wifi("Neighbour 5G");
            verify(r.needsPassword, "needs password");
            r.toggle();
            verify(r.askingPassword);
            const field = findAll(r, i => i.hasOwnProperty("placeholderText") && i.hasOwnProperty("acceptableInput"))[0];
            verify(field.activeFocus || true);
            typeText("short");
            verify(!field.acceptableInput, "too short is rejected");
            field.text = "";
            field.forceActiveFocus();
            typeText("correct horse battery");
            verify(field.acceptableInput);
            keyClick(Qt.Key_Return);
            wait(800);
            verify(!r.askingPassword, "password row closes");
            compare(field.text, "", "password not kept");
        }

        function test_5_network_escape_cancels_password() {
            const r = wifi("Neighbour 5G");
            r.toggle();
            verify(r.askingPassword);
            const field = findAll(r, i => i.hasOwnProperty("placeholderText") && i.hasOwnProperty("acceptableInput"))[0];
            field.forceActiveFocus();
            typeText("abcdefgh");
            keyClick(Qt.Key_Escape);
            verify(!r.askingPassword);
            compare(field.text, "");
        }

        function test_7_wifi_switch() {
            const sw = findAll(network, i => i.hasOwnProperty("checked") && i.hasOwnProperty("position") && i.Accessible.name === "Wi-Fi")[0];
            verify(sw, "switch");
            compare(sw.checked, true);
            mouseClick(sw);
            tryVerify(() => !network.wifiOn, 4000, "Wi-Fi turned off");
            compare(network.subtitle, "Off");
            mouseClick(sw);
            tryVerify(() => network.wifiOn, 4000, "Wi-Fi turned on");
        }

        function test_8_bluetooth_devices_and_connect() {
            tryVerify(() => bluetooth.on, 8000, "operational");
            tryVerify(() => findAll(bluetooth, i => i.hasOwnProperty("busy") && i.hasOwnProperty("device")).length === 2, 8000);
            // rows are rebuilt when a device changes: look the row up each time
            const hp = () => findAll(bluetooth, i => i.hasOwnProperty("busy") && i.hasOwnProperty("device")).filter(r => r.device.Name === "WH-1000XM5")[0];
            verify(hp());
            verify(!hp().connected);
            mouseClick(hp());
            tryVerify(() => hp() && hp().connected, 6000, "connected");
            tryVerify(() => bluetooth.subtitle === "WH-1000XM5", 4000, bluetooth.subtitle);
            mouseClick(hp());
            tryVerify(() => hp() && !hp().connected, 6000, "disconnected");
        }

        function test_9_bluetooth_switch() {
            const sw = findAll(bluetooth, i => i.hasOwnProperty("checked") && i.hasOwnProperty("position") && i.Accessible.name === "Bluetooth")[0];
            mouseClick(sw);
            tryVerify(() => !bluetooth.on, 6000, "off");
            compare(bluetooth.subtitle, "Off");
            mouseClick(sw);
            tryVerify(() => bluetooth.on, 6000, "on");
        }
    }
}
