/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    An icon (a mute button when it can mute), a slider and its percentage.
    `label` names what the slider changes, for screen readers and tooltips.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

RowLayout {
    id: row

    property string label
    property string iconName
    property bool canMute: false
    property bool muted: false
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: (to - from) / 100
    property bool sliderEnabled: true
    // Shown as the percentage (of `to`) unless set
    property string valueText: Math.round(to > from ? (value - from) / (to - from) * 100 : 0) + " %"

    signal moved(real value)
    signal muteToggled()

    spacing: Kirigami.Units.smallSpacing

    PC3.ToolButton {
        visible: row.canMute
        icon.name: row.iconName
        display: PC3.AbstractButton.IconOnly
        checkable: false
        text: row.muted ? i18n("Unmute %1", row.label) : i18n("Mute %1", row.label)
        Accessible.name: text
        PC3.ToolTip.text: text
        PC3.ToolTip.visible: hovered || activeFocus
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: row.muteToggled()
    }
    Kirigami.Icon {
        visible: !row.canMute
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        source: row.iconName
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth
        isMask: true
        color: Kirigami.Theme.textColor
        Accessible.ignored: true
    }

    PC3.Slider {
        id: slider
        Layout.fillWidth: true
        from: row.from
        to: row.to
        stepSize: row.stepSize
        value: row.value
        enabled: row.sliderEnabled
        opacity: row.muted ? 0.5 : 1
        wheelEnabled: true
        Accessible.name: row.label
        Accessible.description: row.valueText
        onMoved: row.moved(value)
    }

    PC3.Label {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
        horizontalAlignment: Text.AlignRight
        text: row.valueText
        opacity: row.muted ? 0.5 : 1
        Accessible.ignored: true
    }
}
