/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The displays view: one brightness slider for each display PowerDevil can
    control, named by the display.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

DetailPage {
    id: page

    required property var display

    title: i18n("Brightness")
    settingsText: i18n("Display settings…")
    settingsPage: "displays"

    Repeater {
        model: page.display.control.displays
        delegate: ColumnLayout {
            id: entry
            required property var model
            Layout.fillWidth: true
            spacing: 0
            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: entry.model.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                opacity: 0.65
            }
            SliderRow {
                Layout.fillWidth: true
                label: i18n("Brightness of %1", entry.model.label)
                iconName: "video-display-brightness-symbolic"
                from: Math.max(1, Math.round(entry.model.maxBrightness / 100))
                to: Math.max(entry.model.maxBrightness, from + 1)
                stepSize: Math.max(1, entry.model.maxBrightness / 100)
                value: entry.model.brightness
                valueText: Math.round(entry.model.brightness / Math.max(1, entry.model.maxBrightness) * 100) + " %"
                onMoved: v => page.display.set(entry.model.displayName, v)
            }
        }
    }
}
