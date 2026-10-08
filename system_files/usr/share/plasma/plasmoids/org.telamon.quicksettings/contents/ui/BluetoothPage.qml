/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The Bluetooth view: the paired devices, to connect or disconnect. Pairing
    a new device is the Bluetooth page of Telamon Settings.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3

DetailPage {
    id: page

    required property var bluetooth

    title: i18n("Bluetooth")
    settingsText: i18n("Bluetooth settings…")
    settingsPage: "devices"
    hasSwitch: true
    switchChecked: bluetooth.on
    onSwitchToggled: checked => bluetooth.setEnabled(checked)

    PC3.Label {
        Layout.fillWidth: true
        visible: !page.bluetooth.on
        text: i18n("Bluetooth is off.")
        wrapMode: Text.Wrap
        opacity: 0.65
    }
    PC3.Label {
        Layout.fillWidth: true
        visible: page.bluetooth.on && page.bluetooth.paired.count === 0
        text: i18n("No paired devices.")
        wrapMode: Text.Wrap
        opacity: 0.65
    }
    Repeater {
        model: page.bluetooth.on ? page.bluetooth.paired : null
        delegate: BluetoothDevice {
            required property var model
            device: model
            Layout.fillWidth: true
        }
    }
}
