import QtQuick
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

// Choosing the default output in the sound view (run apart: it changes the default)
Item {
    width: 420; height: 700
    QuickSettings { id: popup; width: 360 }
    Util {
        name: "output"
        popup: popup
        when: windowShown
        function test_choose_headphones() {
            tryVerify(() => has("Sound outputs and apps"), 8000);
            open("Sound outputs and apps");
            tryVerify(() => has("Headphones"), 5000);
            mouseClick(one("Headphones"));
            tryVerify(() => one("Headphones").Accessible.checked, 5000, "headphones are ticked");
            compare(one("Speakers").Accessible.checked, false);
        }
    }
}
