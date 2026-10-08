/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The sound view: the output devices as a list with a check mark on the one
    in use, then the apps playing sound, each with its own volume, mute and
    output (its stream moves to the output chosen, as Plasma's volume widget
    does with a drag).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

DetailPage {
    id: page

    required property var sound

    title: i18n("Sound")
    settingsText: i18n("Sound settings…")
    settingsPage: "sound"

    PC3.Label {
        text: i18n("Output")
        font: Kirigami.Theme.smallFont
        opacity: 0.65
        Layout.leftMargin: 8
    }
    Repeater {
        model: page.sound.sinks
        delegate: PC3.ItemDelegate {
            id: output
            required property int index
            required property var model
            readonly property bool current: page.sound.hasSink && page.sound.sink.index === model.Index
            Layout.fillWidth: true
            activeFocusOnTab: true
            text: model.Description
            Accessible.name: text
            Accessible.description: current ? i18n("current output") : ""
            Accessible.role: Accessible.RadioButton
            Accessible.checkable: true
            Accessible.checked: current
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            onClicked: page.sound.useOutput(index)
            contentItem: RowLayout {
                spacing: 12
                PC3.Label {
                    Layout.fillWidth: true
                    text: output.text
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.weight: output.current ? Font.DemiBold : Font.Normal
                    Accessible.ignored: true
                }
                Kirigami.Icon {
                    visible: output.current
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
        Layout.topMargin: 8
        Layout.leftMargin: 8
        text: i18n("Apps")
        font: Kirigami.Theme.smallFont
        opacity: 0.65
    }
    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        visible: page.sound.apps.count === 0
        text: i18n("No app is playing sound.")
        wrapMode: Text.Wrap
    }
    Repeater {
        model: page.sound.apps
        delegate: AppStream {
            required property var model
            stream: model
            devices: page.sound.sinks
            Layout.fillWidth: true
        }
    }
}
