import QtQuick
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

// A desktop with a cable: what it lacks is left out and the rest fills the width
Item {
    width: 420; height: 800
    QuickSettings { id: popup; width: 360 }
    Util {
        name: "desktop"
        popup: popup
        when: windowShown
        function test_main_view() {
            tryVerify(() => has("Power mode") && has("Network"), 10000, "tiles");
            verify(!has("Bluetooth"), "no Bluetooth tile without an adapter");
            verify(!has("Wi-Fi"), "no Wi-Fi tile without a Wi-Fi adapter: it is a Network tile");
            verify(!has("Brightness"), "no brightness slider without a controllable display");
            verify(!has("Wi-Fi networks"), "no Wi-Fi list to open");
            verify(findAll(popup, i => i.Accessible && i.Accessible.name.indexOf("Battery") === 0 && !i.Accessible.ignored && i.visible).length === 0, "nothing about a battery");
            verify(has("Volume of Speakers") || has("Volume of Headphones") || findAll(popup, i => i.Accessible && i.Accessible.name.indexOf("Volume of") === 0).length > 0, "the volume slider stays");
            // the Network tile has no toggle
            verify(one("Network").Accessible.checkable === false);
            // two tiles left (Network, Power mode): they share the row
            const a = one("Network"), b = one("Power mode");
            verify(Math.abs(a.width - b.width) < 2 && a.width < 200, "two tiles share the row");
        }
    }
}
