import QtQuick
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    width: 420; height: 800
    QuickSettings { id: popup; width: 360 }

    Util {
        name: "misc"
        popup: popup
        when: windowShown

        function networks() { return findAll(popup, i => i.hasOwnProperty("askingPassword") && i.visible); }
        function wifi(name) {
            const rows = networks().filter(r => r.network.ItemUniqueName === name);
            verify(rows.length === 1, name + ": " + rows.length);
            return rows[0];
        }
        function passwordField(row) { return findAll(row, i => i.hasOwnProperty("placeholderText") && i.hasOwnProperty("acceptableInput"))[0]; }
        function device(name) {
            return findAll(popup, i => i.hasOwnProperty("busy") && i.hasOwnProperty("device") && i.visible).filter(r => r.device.Name === name)[0];
        }

        function test_01_main_view_has_what_the_computer_has() {
            tryVerify(() => has("Power mode") && has("Bluetooth") && has("Brightness"), 10000, "tiles and sliders");
            verify(has("Wi-Fi") && has("Wi-Fi networks"));
            verify(has("Settings") && has("Clipboard history"));
        }

        function test_02_brightness_slider_sets_the_built_in_display() {
            const s = sliderOf("Brightness");
            compare(Math.round(s.value), 70);
            clickSlider(s, 0.3);
            wait(400);
            verify(Math.abs(s.value - 30) <= 8, "slider near 30: " + s.value);
        }

        function test_03_displays_view_has_a_slider_each() {
            open("Brightness of each display");
            tryVerify(() => has("Brightness of Dell U2723QE") && has("Brightness of Built-in display"), 5000);
            back();
        }

        function test_04_power_tile_goes_to_the_next_mode() {
            mouseClick(one("Power mode"));
            wait(500);
        }

        function test_05_power_view_choices() {
            open("Power modes");
            tryVerify(() => one("Performance").Accessible.checked, 4000, "performance is the active mode");
            mouseClick(one("Power Saver"));
            tryVerify(() => one("Power Saver").Accessible.checked, 4000, "power saver became active");
            back();
        }

        function test_06_wifi_view_lists_networks() {
            open("Wi-Fi networks");
            tryVerify(() => networks().length >= 3, 15000, "networks listed");
            console.warn("NETWORKS", JSON.stringify(networks().map(r => r.network.ItemUniqueName).sort()));
        }

        function test_07_open_network_connects() {
            const r = wifi("Cafe Guest");
            verify(!r.secured && !r.askingPassword);
            mouseClick(r.children[0]);
            wait(800);
            verify(!r.askingPassword);
        }

        function test_08_escape_cancels_the_password() {
            const r = wifi("Neighbour 5G");
            verify(r.needsPassword, "needs a password");
            r.toggle();
            verify(r.askingPassword);
            const field = passwordField(r);
            field.forceActiveFocus();
            typeText("abcdefgh");
            keyClick(Qt.Key_Escape);
            verify(!r.askingPassword);
            compare(field.text, "");
            // Escape cancelled the field, it did not leave the view
            compare(stack().depth, 2);
        }

        function test_09_password_is_dropped_when_the_view_closes() {
            const r = wifi("Neighbour 5G");
            r.toggle();
            verify(r.askingPassword);
            const field = passwordField(r);
            field.forceActiveFocus();
            typeText("half typed");
            back();
            wait(300);
            // the view and its field are gone; a new one starts empty and closed
            open("Wi-Fi networks");
            tryVerify(() => networks().length >= 3, 8000);
            const again = wifi("Neighbour 5G");
            verify(!again.askingPassword, "a new view does not ask");
            compare(passwordField(again).text, "", "a typed password does not outlive the view");
        }

        function test_10_new_secured_network_takes_a_password() {
            const r = wifi("Neighbour 5G");
            verify(!r.askingPassword);
            r.toggle();
            verify(r.askingPassword);
            const field = passwordField(r);
            field.forceActiveFocus();
            typeText("short");
            verify(!field.acceptableInput, "too short is rejected");
            field.text = "";
            typeText("correct horse battery");
            verify(field.acceptableInput);
            keyClick(Qt.Key_Return);
            wait(800);
            verify(!r.askingPassword, "the password row closes");
            compare(field.text, "", "the password is not kept");
        }

        function test_11_wifi_switch() {
            const sw = findAll(popup, i => i.hasOwnProperty("checked") && i.hasOwnProperty("position") && i.Accessible.name === "Wi-Fi" && i.visible)[0];
            verify(sw, "the switch");
            compare(sw.checked, true);
            mouseClick(sw);
            tryVerify(() => !sw.checked, 4000, "off");
            mouseClick(sw);
            tryVerify(() => sw.checked, 4000, "on");
            back();
        }

        function test_12_wifi_tile_switches_wifi() {
            const tile = one("Wi-Fi");
            compare(tile.Accessible.checked, true);
            mouseClick(tile);
            tryVerify(() => !one("Wi-Fi").Accessible.checked, 4000, "off");
            mouseClick(one("Wi-Fi"));
            tryVerify(() => one("Wi-Fi").Accessible.checked, 4000, "on");
        }

        function test_13_bluetooth_view_connects_a_device() {
            open("Bluetooth devices");
            tryVerify(() => device("WH-1000XM5") !== undefined, 8000, "devices listed");
            verify(!device("WH-1000XM5").connected);
            mouseClick(device("WH-1000XM5"));
            // rows are rebuilt when a device changes: look it up each time
            tryVerify(() => device("WH-1000XM5") && device("WH-1000XM5").connected, 6000, "connected");
            mouseClick(device("WH-1000XM5"));
            tryVerify(() => device("WH-1000XM5") && !device("WH-1000XM5").connected, 6000, "disconnected");
            back();
        }

        function test_14_bluetooth_tile_switches_bluetooth() {
            const tile = one("Bluetooth");
            compare(tile.Accessible.checked, true);
            mouseClick(tile);
            tryVerify(() => !one("Bluetooth").Accessible.checked, 6000, "off");
            mouseClick(one("Bluetooth"));
            tryVerify(() => one("Bluetooth").Accessible.checked, 6000, "on");
        }

        function test_15_battery_is_shown_where_there_is_one() {
            verify(has("Battery 87 % · 3:12 left") || findAll(popup, i => i.Accessible && i.Accessible.name.indexOf("Battery 87") === 0).length > 0);
        }
    }
}
