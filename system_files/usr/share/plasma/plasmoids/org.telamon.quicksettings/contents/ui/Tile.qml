/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    A toggle tile of the main view: icon, a title and a status line. Pressing
    the tile switches the thing on or off (or, with `toggles` off, just does
    it); the chevron opens its detail view. Active tiles are filled with the
    accent colour. The body and the chevron are two controls, each with its
    own accessible name.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: tile

    property string iconName
    property string title
    property string subtitle
    property bool active: false
    // A tile with nothing to switch (no Wi-Fi adapter): not drawn as on or off
    property bool toggles: true
    property bool hasDetail: false
    property string detailLabel
    // Whether the tile is there at all (not `visible`, which also follows layout)
    property bool shown: true

    signal clicked()
    signal detailRequested()

    readonly property color foreground: active ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

    implicitHeight: Kirigami.Units.gridUnit * 3.5
    implicitWidth: Kirigami.Units.gridUnit * 8
    visible: shown

    T.AbstractButton {
        id: body
        anchors.fill: parent
        hoverEnabled: true
        activeFocusOnTab: true
        text: tile.title
        // The chevron is a sibling control on top; leave its room
        rightPadding: tile.hasDetail ? 40 : 8
        Accessible.name: tile.title
        Accessible.description: tile.subtitle
        Accessible.role: tile.toggles ? Accessible.CheckBox : Accessible.Button
        Accessible.checkable: tile.toggles
        Accessible.checked: tile.active
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: tile.clicked()

        background: Rectangle {
            radius: 8
            color: tile.active ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, body.hovered ? 0.14 : 0.08)
            border.width: body.visualFocus ? 2 : 0
            border.color: Kirigami.Theme.highlightColor
            // Keeps the focus ring visible on an accent-filled tile
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 6
                visible: body.visualFocus && tile.active
                color: "transparent"
                border.width: 2
                border.color: Kirigami.Theme.highlightedTextColor
            }
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        }
        contentItem: RowLayout {
            spacing: 8
            Kirigami.Icon {
                Layout.leftMargin: 12
                source: tile.iconName
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
                isMask: true
                color: tile.foreground
                Accessible.ignored: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PC3.Label {
                    Layout.fillWidth: true
                    text: tile.title
                    textFormat: Text.PlainText
                    font.weight: Font.DemiBold
                    color: tile.foreground
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
                PC3.Label {
                    Layout.fillWidth: true
                    text: tile.subtitle
                    textFormat: Text.PlainText
                    font: Kirigami.Theme.smallFont
                    color: tile.foreground
                    opacity: tile.active ? 0.85 : 0.65
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }
        }
    }

    PC3.ToolButton {
        visible: tile.hasDetail
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        display: PC3.AbstractButton.IconOnly
        contentItem: Chevron { color: tile.foreground }
        text: tile.detailLabel
        Accessible.name: tile.detailLabel
        PC3.ToolTip.text: text
        PC3.ToolTip.visible: hovered || visualFocus
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: tile.detailRequested()
    }
}
