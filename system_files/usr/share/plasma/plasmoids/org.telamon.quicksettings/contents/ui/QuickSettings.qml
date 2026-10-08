/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The popup: a main view (tiles, two sliders, a bottom row) and detail
    views that replace it in place (Wi-Fi, Bluetooth, power mode, sound,
    displays), each with a Back arrow. Fixed width, nothing scrolls on the main
    view. Tab walks the controls; Escape goes back, then (Plasma) closes.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: popup

    signal settingsRequested(string page)
    signal clipboardRequested()

    readonly property alias stack: stack

    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: stack.currentItem ? stack.currentItem.implicitHeight : Kirigami.Units.gridUnit * 16
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    // The popup opens on the main view
    onVisibleChanged: if (!visible && stack.depth > 1) stack.pop(null, QQC2.StackView.Immediate)

    SoundState { id: soundState }
    DisplayState { id: displayState }
    NetworkState { id: netState }
    BluetoothState { id: bluetoothState }
    PowerState { id: powerState }
    DoNotDisturbState { id: dndState }

    function open(component) {
        stack.push(component);
    }

    QQC2.StackView {
        id: stack
        anchors.fill: parent
        clip: true
        initialItem: mainView

        // Views slide in from the right and out to the left, and the other
        // way back
        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: stack.width / 4; to: 0; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Kirigami.Units.shortDuration }
            }
        }
        pushExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: 0; to: -stack.width / 4; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Kirigami.Units.shortDuration }
            }
        }
        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: -stack.width / 4; to: 0; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Kirigami.Units.shortDuration }
            }
        }
        popExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: 0; to: stack.width / 4; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Kirigami.Units.shortDuration }
            }
        }
    }

    Component {
        id: mainView
        MainView {
            net: netState
            bluetooth: bluetoothState
            power: powerState
            sound: soundState
            display: displayState
            dnd: dndState
            onOpenPage: name => popup.open(name === "wifi" ? wifiPage : name === "bluetooth" ? bluetoothPage
                : name === "power" ? powerPage : name === "sound" ? soundPage : displayPage)
            onSettingsRequested: page => popup.settingsRequested(page)
            onClipboardRequested: popup.clipboardRequested()
        }
    }
    Component { id: wifiPage; WifiPage { net: netState; onBack: stack.pop(); onSettingsRequested: page => popup.settingsRequested(page) } }
    Component { id: bluetoothPage; BluetoothPage { bluetooth: bluetoothState; onBack: stack.pop(); onSettingsRequested: page => popup.settingsRequested(page) } }
    Component { id: powerPage; PowerPage { power: powerState; onBack: stack.pop(); onSettingsRequested: page => popup.settingsRequested(page) } }
    Component { id: soundPage; SoundPage { sound: soundState; onBack: stack.pop(); onSettingsRequested: page => popup.settingsRequested(page) } }
    Component { id: displayPage; DisplayPage { display: displayState; onBack: stack.pop(); onSettingsRequested: page => popup.settingsRequested(page) } }
}
