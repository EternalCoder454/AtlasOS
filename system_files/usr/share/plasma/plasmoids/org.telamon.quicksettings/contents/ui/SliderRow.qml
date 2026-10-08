/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    A slider with its icon on the left (a button when it can be pressed:
    mute) and, when there is more to see, a chevron on the right that opens
    the detail view. No numbers: the slider is the display; a screen reader
    gets the value from its accessible description.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

RowLayout {
    id: row

    // What the slider changes, for screen readers ("Volume of Speakers")
    property string label
    property string iconName
    // The icon is a button (mute); its accessible name
    property string iconAction
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: (to - from) / 100
    property bool muted: false
    property bool hasDetail: false
    property string detailLabel
    // For screen readers: "70 %"
    property string valueText: Math.round(to > from ? (value - from) / (to - from) * 100 : 0) + " %"

    signal moved(real value)
    signal iconClicked()
    signal detailRequested()

    // The icon and the chevron take the same room in every row, so the
    // sliders of different rows line up
    readonly property int slot: Kirigami.Units.gridUnit * 2

    spacing: 8
    implicitHeight: Kirigami.Units.gridUnit * 2.25

    PC3.ToolButton {
        visible: row.iconAction !== ""
        Layout.preferredWidth: row.slot
        icon.name: row.iconName
        display: PC3.AbstractButton.IconOnly
        text: row.iconAction
        Accessible.name: text
        PC3.ToolTip.text: text
        PC3.ToolTip.visible: hovered || visualFocus
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: row.iconClicked()
    }
    Item {
        visible: row.iconAction === ""
        Layout.preferredWidth: row.slot
        Layout.preferredHeight: row.slot
        Kirigami.Icon {
            anchors.centerIn: parent
            source: row.iconName
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            isMask: true
            color: Kirigami.Theme.textColor
            Accessible.ignored: true
        }
    }

    PC3.Slider {
        Layout.fillWidth: true
        from: row.from
        to: row.to
        stepSize: row.stepSize
        value: row.value
        opacity: row.muted ? 0.5 : 1
        wheelEnabled: true
        Accessible.name: row.label
        Accessible.description: row.valueText
        onMoved: row.moved(value)
    }

    PC3.ToolButton {
        visible: row.hasDetail
        Layout.preferredWidth: row.slot
        display: PC3.AbstractButton.IconOnly
        contentItem: Chevron { color: Kirigami.Theme.textColor }
        text: row.detailLabel
        Accessible.name: text
        PC3.ToolTip.text: text
        PC3.ToolTip.visible: hovered || visualFocus
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: row.detailRequested()
    }
    // Keeps the sliders of rows with and without a chevron the same length
    Item {
        visible: !row.hasDetail
        Layout.preferredWidth: row.slot
    }
}
