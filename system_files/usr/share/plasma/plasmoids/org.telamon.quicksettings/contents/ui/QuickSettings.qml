/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The popup: a column of sections, common ones first, details folded.
    Tab walks the controls top to bottom; Escape closes it (Plasma).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PC3.ScrollView {
    id: popup

    signal settingsRequested(string page)

    // Sections that exist on this computer decide the height
    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Math.min(column.implicitHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 36)
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: Math.min(implicitHeight, Kirigami.Units.gridUnit * 16)
    Layout.preferredHeight: implicitHeight

    contentWidth: availableWidth
    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
    Accessible.name: i18n("Quick Settings")

    ColumnLayout {
        id: column
        width: popup.availableWidth
        spacing: Kirigami.Units.smallSpacing

        SoundCard {
            onSettingsRequested: popup.settingsRequested("sound")
        }
        DisplayCard {
            onSettingsRequested: popup.settingsRequested("displays")
        }
        NetworkCard {
            onSettingsRequested: popup.settingsRequested("network")
        }
        BluetoothCard {
            onSettingsRequested: popup.settingsRequested("devices")
        }
        PowerCard {
            onSettingsRequested: popup.settingsRequested("power")
        }

        PC3.Button {
            Layout.alignment: Qt.AlignHCenter
            flat: true
            text: i18n("All settings…")
            icon.name: "preferences-system-symbolic"
            onClicked: popup.settingsRequested("")
        }
    }
}
