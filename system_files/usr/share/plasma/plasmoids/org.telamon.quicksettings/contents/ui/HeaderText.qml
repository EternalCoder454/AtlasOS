/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    A card's icon, title and status line. Not read out by itself: the
    control around it carries the accessible name.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

RowLayout {
    id: header
    property string iconName
    property string title
    property string subtitle

    spacing: Kirigami.Units.smallSpacing * 2
    Accessible.ignored: true

    Kirigami.Icon {
        source: header.iconName
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth
        isMask: true
        color: Kirigami.Theme.textColor
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        PC3.Label {
            Layout.fillWidth: true
            text: header.title
            textFormat: Text.PlainText
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        PC3.Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: header.subtitle
            textFormat: Text.PlainText
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
    }
}
