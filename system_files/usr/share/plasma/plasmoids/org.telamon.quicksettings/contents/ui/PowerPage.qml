/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The power mode view: Power Saver, Balanced and Performance (what
    power-profiles-daemon offers), the active one with a check mark.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

DetailPage {
    id: page

    required property var power

    title: i18n("Power mode")
    settingsText: i18n("Power settings…")
    settingsPage: "power"

    Repeater {
        model: page.power.offered
        delegate: PC3.ItemDelegate {
            id: choice
            required property string modelData
            readonly property bool current: page.power.activeProfile === modelData
            Layout.fillWidth: true
            activeFocusOnTab: true
            text: page.power.labels[modelData]
            Accessible.name: text
            Accessible.description: current ? i18n("current mode") : ""
            Accessible.role: Accessible.RadioButton
            Accessible.checkable: true
            Accessible.checked: current
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            onClicked: page.power.setProfile(modelData)
            contentItem: RowLayout {
                spacing: 12
                Kirigami.Icon {
                    source: page.power.icons[choice.modelData]
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    isMask: true
                    color: Kirigami.Theme.textColor
                    Accessible.ignored: true
                }
                PC3.Label {
                    Layout.fillWidth: true
                    text: choice.text
                    font.weight: choice.current ? Font.DemiBold : Font.Normal
                    Accessible.ignored: true
                }
                Kirigami.Icon {
                    visible: choice.current
                    source: "checkmark-symbolic"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    isMask: true
                    color: Kirigami.Theme.highlightColor
                    Accessible.ignored: true
                }
            }
        }
    }
    PC3.Label {
        Layout.fillWidth: true
        Layout.topMargin: 8
        visible: page.power.hasBattery
        text: page.power.batteryText
        opacity: 0.65
    }
}
