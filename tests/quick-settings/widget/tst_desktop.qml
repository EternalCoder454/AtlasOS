import QtQuick
import QtQuick.Layouts
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

// A desktop with a cable: the sections for hardware it does not have stay out of the way.
Item {
    width: 420; height: 800
    ColumnLayout {
        width: 400
        SoundCard { id: sound }
        DisplayCard { id: display }
        NetworkCard { id: network }
        BluetoothCard { id: bluetooth }
        PowerCard { id: power }
    }
    TestCase {
        name: "desktop"
        when: windowShown
        function test_sections() {
            wait(3000);
            verify(!display.visible, "no brightness slider without a controllable display");
            verify(!bluetooth.visible, "no Bluetooth section without an adapter");
            compare(network.title, "Network");
            verify(!network.hasSwitch, "no Wi-Fi switch without a Wi-Fi adapter");
            verify(power.visible, "the power profiles still show");
            verify(!power.hasBattery, "no battery");
            compare(power.title, "Power");
            verify(power.subtitle.indexOf("%") < 0, "nothing about a charge: " + power.subtitle);
            verify(power.subtitle.indexOf("left") < 0 && power.subtitle.indexOf("Charging") < 0, power.subtitle);
        }
    }
}
