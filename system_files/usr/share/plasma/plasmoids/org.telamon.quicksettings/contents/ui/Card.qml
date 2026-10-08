/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    One section of Quick Settings: a rounded surface with a header (icon,
    title, status line, optional switch, link to the section's Telamon
    Settings page), the always-visible content, and details that fold away.
    The header is one button when there are details (Enter or Space opens
    them); a screen reader hears its title, status and whether it is open.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Rectangle {
    id: card

    property string iconName
    property string title
    property string subtitle
    // Says what the gear opens, for the tooltip and screen readers
    property string settingsLabel
    property bool hasDetails: false
    property bool expanded: false
    // Switch in the header (Wi-Fi, Bluetooth)
    property bool hasSwitch: false
    property bool switchChecked: false
    property bool switchEnabled: true
    property string switchLabel

    // Always visible, under the header
    default property alias content: contentColumn.data
    // Shown while expanded
    property alias details: detailsColumn.data

    signal settingsRequested()
    signal switchToggled(bool checked)

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 3
    radius: 8
    color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
    border.width: 1
    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Kirigami.Units.smallSpacing
        }
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // With details: the whole title area is the button
            PC3.ItemDelegate {
                id: headerButton
                Layout.fillWidth: true
                visible: card.hasDetails
                text: card.title
                Accessible.name: card.title
                Accessible.description: card.subtitle
                Accessible.role: Accessible.Button
                onClicked: card.expanded = !card.expanded
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing * 2
                    HeaderText {
                        Layout.fillWidth: true
                        iconName: card.iconName
                        title: card.title
                        subtitle: card.subtitle
                    }
                    Kirigami.Icon {
                        source: card.expanded ? "go-up-symbolic" : "go-down-symbolic"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: implicitWidth
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }
                }
            }
            // Without: plain text
            HeaderText {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: !card.hasDetails
                iconName: card.iconName
                title: card.title
                subtitle: card.subtitle
            }

            PC3.Switch {
                visible: card.hasSwitch
                checked: card.switchChecked
                enabled: card.switchEnabled
                Accessible.name: card.switchLabel || card.title
                onToggled: card.switchToggled(checked)
            }
            PC3.ToolButton {
                icon.name: "preferences-system-symbolic"
                display: PC3.AbstractButton.IconOnly
                text: card.settingsLabel
                Accessible.name: card.settingsLabel
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered || activeFocus
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: card.settingsRequested()
            }
        }

        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: children.length > 0
        }

        ColumnLayout {
            id: detailsColumn
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: card.hasDetails && card.expanded
        }
    }
}
