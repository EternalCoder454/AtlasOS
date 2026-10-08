/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The popup: a column of sections, common ones first, details folded.
    Tab walks the controls top to bottom; Escape closes it (Plasma).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PC3.ScrollView {
    id: popup

    signal settingsRequested(string page)
    signal clipboardRequested()

    // Sections that exist on this computer decide the height
    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Math.min(column.implicitHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 40)
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: Math.min(implicitHeight, Kirigami.Units.gridUnit * 16)
    Layout.preferredHeight: implicitHeight

    contentWidth: availableWidth
    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
    Accessible.name: i18n("Quick Settings")

    // The setting is also changed from outside (Plasma's scripting)
    Connections {
        target: Plasmoid.configuration
        function onSoundOpenChanged() { sound.expanded = Plasmoid.configuration.soundOpen; }
        function onNetworkOpenChanged() { network.expanded = Plasmoid.configuration.networkOpen; }
        function onBluetoothOpenChanged() { bluetooth.expanded = Plasmoid.configuration.bluetoothOpen; }
    }

    ColumnLayout {
        id: column
        width: popup.availableWidth
        spacing: Kirigami.Units.smallSpacing

        SoundCard {
            id: sound
            // Which sections are open is remembered
            Component.onCompleted: expanded = Plasmoid.configuration.soundOpen
            onExpandedChanged: Plasmoid.configuration.soundOpen = expanded
            onSettingsRequested: popup.settingsRequested("sound")
        }
        DisplayCard {
            onSettingsRequested: popup.settingsRequested("displays")
        }
        NetworkCard {
            id: network
            // Which sections are open is remembered
            Component.onCompleted: expanded = Plasmoid.configuration.networkOpen
            onExpandedChanged: Plasmoid.configuration.networkOpen = expanded
            onSettingsRequested: popup.settingsRequested("network")
        }
        BluetoothCard {
            id: bluetooth
            // Which sections are open is remembered
            Component.onCompleted: expanded = Plasmoid.configuration.bluetoothOpen
            onExpandedChanged: Plasmoid.configuration.bluetoothOpen = expanded
            onSettingsRequested: popup.settingsRequested("devices")
        }
        PowerCard {
            onSettingsRequested: popup.settingsRequested("power")
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing
            PC3.Button {
                flat: true
                text: i18n("Clipboard history")
                icon.name: "edit-paste-symbolic"
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: popup.clipboardRequested()
            }
            PC3.Button {
                flat: true
                text: i18n("All settings…")
                icon.name: "preferences-system-symbolic"
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: popup.settingsRequested("")
            }
        }
    }
}
