import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "file:///usr/share/plasma/plasmoids/org.telamon.quicksettings/contents/ui"

Item {
    id: root
    width: 420; height: 620

    SoundCard { id: card; width: 400; expanded: true }

    TestCase {
        id: tc
        name: "sound"
        when: windowShown

        // Depth-first search of the visual tree
        function findAll(item, pred, out) {
            out = out || [];
            if (pred(item)) out.push(item);
            for (let i = 0; i < item.children.length; i++) findAll(item.children[i], pred, out);
            return out;
        }
        function byType(item, name) { return findAll(item, i => ("" + i).indexOf(name) === 0); }

        function waitForApps(n) {
            tryVerify(() => findAll(card, i => i.hasOwnProperty("appName")).length >= n, 8000, "apps listed");
        }
        function appItem(name) {
            const all = findAll(card, i => i.hasOwnProperty("appName") && i.appName === name);
            verify(all.length === 1, "one row for " + name + ", got " + all.length);
            return all[0];
        }

        function test_0_listsApps() {
            waitForApps(2);
            compare(findAll(card, i => i.hasOwnProperty("appName")).length, 2);
            tryVerify(() => card.subtitle.indexOf("2 apps playing") >= 0, 5000, card.subtitle);
            appItem("YouTube Music"); appItem("Discord");
        }

        function test_1_deviceListHasBothOutputs() {
            const row = appItem("YouTube Music");
            const picker = findAll(row, i => i.hasOwnProperty("textRole") && i.hasOwnProperty("valueRole"))[0];
            compare(picker.count, 2);
            compare(picker.currentText, "Speakers");
        }

        // The keyboard route: focus the box, Down moves to the next output and activates it
        function test_2_moveStreamWithKeyboard() {
            const row = appItem("YouTube Music");
            const picker = findAll(row, i => i.hasOwnProperty("textRole") && i.hasOwnProperty("valueRole"))[0];
            picker.forceActiveFocus();
            verify(picker.activeFocus);
            keyClick(Qt.Key_Down);
            compare(picker.currentText, "Headphones");
            // the other app stays where it was
            const other = findAll(appItem("Discord"), i => i.hasOwnProperty("textRole") && i.hasOwnProperty("valueRole"))[0];
            compare(other.currentText, "Speakers");
            wait(500);
            // the model follows what PulseAudio reports
            compare(picker.currentText, "Headphones");
        }

        function test_3_perAppVolumeWithMouse() {
            const row = appItem("Discord");
            const slider = findAll(row, i => i.hasOwnProperty("snapMode") && i.hasOwnProperty("handle"))[0];
            // click at 25 % of the groove
            mouseClick(slider, slider.leftPadding + slider.availableWidth * 0.25 , slider.height / 2);
            wait(300);
            verify(Math.abs(slider.value / slider.to - 0.25) < 0.08, "slider at " + slider.value / slider.to);
            console.warn("DISCORD_SLIDER", Math.round(slider.value / slider.to * 100));
        }

        function test_4_perAppMute() {
            const row = appItem("Discord");
            const buttons = findAll(row, i => i.hasOwnProperty("checkable") && i.hasOwnProperty("icon") && i.text.indexOf("Mute") === 0);
            compare(buttons.length, 1);
            mouseClick(buttons[0]);
            wait(300);
            verify(buttons[0].text.indexOf("Unmute") === 0, buttons[0].text);
        }

        function test_5_mainVolumeAndMute() {
            const slider = findAll(card, i => i.hasOwnProperty("snapMode") && i.hasOwnProperty("handle"))[0];
            mouseClick(slider, slider.leftPadding + slider.availableWidth * 0.5, slider.height / 2);
            wait(300);
            console.warn("MAIN_SLIDER", Math.round(slider.value / slider.to * 100));
            const mute = findAll(card, i => i.hasOwnProperty("checkable") && i.hasOwnProperty("icon") && i.text.indexOf("Mute Volume") === 0)[0];
            verify(mute, "main mute button");
            mouseClick(mute);
            wait(300);
            verify(mute.text.indexOf("Unmute") === 0, mute.text);
        }
    }
}
