/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Display brightness: a slider for each display PowerDevil can control
    (laptop panels, and external monitors that speak DDC/CI). Hidden when
    there is none.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.brightnesscontrolplugin

Card {
    id: card

    visible: control.isBrightnessAvailable && displays.count > 0
    iconName: "video-display-brightness-symbolic"
    title: i18n("Display")
    subtitle: i18n("Brightness")
    settingsLabel: i18n("Open Display settings")

    ScreenBrightnessControl {
        id: control
        // No on-screen display from the popup: the slider is the feedback
        isSilent: true
    }

    Repeater {
        id: displays
        model: control.displays
        delegate: ColumnLayout {
            id: display

            required property var model
            readonly property bool several: displays.count > 1

            Layout.fillWidth: true
            spacing: 0

            // With several displays, which is which
            PC3.Label {
                visible: display.several
                text: display.model.label
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            ValueRow {
                Layout.fillWidth: true
                label: display.several ? i18n("Brightness of %1", display.model.label) : i18n("Brightness")
                iconName: "video-display-brightness-symbolic"
                // Never to zero: a black screen with the slider on it
                from: Math.max(1, Math.round(display.model.maxBrightness / 100))
                to: Math.max(display.model.maxBrightness, from + 1)
                stepSize: Math.max(1, display.model.maxBrightness / 100)
                value: display.model.brightness
                valueText: Math.round(display.model.brightness / Math.max(1, display.model.maxBrightness) * 100) + " %"
                onMoved: v => control.setBrightness(display.model.displayName, Math.round(v))
            }
        }
    }
}
