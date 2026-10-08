/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The first view: tiles for Wi-Fi, Bluetooth, power mode and Do Not
    Disturb, a volume and a brightness slider, and a bottom row with the
    battery (where there is one) and the buttons for the clipboard history
    and Settings. Whatever the computer lacks is left out, and the rest
    fills the width. Everything else is one chevron away.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.volume

Item {
    id: view

    required property var net
    required property var bluetooth
    required property var power
    required property var sound
    required property var display
    required property var dnd

    signal openPage(string name)
    signal settingsRequested(string page)
    signal clipboardRequested()

    implicitHeight: column.implicitHeight + 32
    Accessible.role: Accessible.Pane
    Accessible.name: i18n("Quick Settings")

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: 16

        // Two to a row; one left over takes the whole row
        Flow {
            id: tiles
            Layout.fillWidth: true
            spacing: 8

            readonly property var present: [wifi, bt, powerTile, dndTile].filter(t => t.shown)
            function widthOf(tile) {
                const half = (tiles.width - tiles.spacing) / 2;
                return present.length % 2 === 1 && present[present.length - 1] === tile ? tiles.width : half;
            }

            Tile {
                id: wifi
                width: tiles.widthOf(wifi)
                iconName: view.net.iconName
                title: view.net.title
                subtitle: view.net.subtitle
                // Without a Wi-Fi adapter there is nothing to switch: the tile
                // shows the wired connection and opens the network settings
                toggles: view.net.hasWifi
                active: view.net.hasWifi && view.net.wifiOn
                hasDetail: view.net.hasWifi
                detailLabel: i18n("Wi-Fi networks")
                onClicked: view.net.hasWifi ? (view.net.canSwitch && view.net.setWifi(!view.net.wifiOn)) : view.settingsRequested("network")
                onDetailRequested: view.openPage("wifi")
            }
            Tile {
                id: bt
                shown: view.bluetooth.available
                width: tiles.widthOf(bt)
                iconName: view.bluetooth.iconName
                title: i18n("Bluetooth")
                subtitle: view.bluetooth.subtitle
                active: view.bluetooth.on
                hasDetail: true
                detailLabel: i18n("Bluetooth devices")
                onClicked: view.bluetooth.setEnabled(!view.bluetooth.on)
                onDetailRequested: view.openPage("bluetooth")
            }
            Tile {
                id: powerTile
                shown: view.power.hasProfiles
                width: tiles.widthOf(powerTile)
                iconName: view.power.profileIcon
                title: i18n("Power mode")
                subtitle: view.power.profileLabel
                // A mode, not a switch: pressing goes to the next one
                toggles: false
                active: view.power.activeProfile !== "balanced" && view.power.activeProfile !== ""
                hasDetail: true
                detailLabel: i18n("Power modes")
                onClicked: view.power.setProfile(view.power.nextProfile())
                onDetailRequested: view.openPage("power")
            }
            Tile {
                id: dndTile
                shown: view.dnd.available
                width: tiles.widthOf(dndTile)
                iconName: view.dnd.on ? "notifications-disabled-symbolic" : "notifications-symbolic"
                title: i18n("Do Not Disturb")
                subtitle: view.dnd.on ? i18n("On") : i18n("Off")
                active: view.dnd.on
                onClicked: view.dnd.setOn(!view.dnd.on)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            SliderRow {
                Layout.fillWidth: true
                visible: view.sound.hasSink
                label: i18n("Volume of %1", view.sound.deviceName)
                iconName: view.sound.iconName
                iconAction: view.sound.muted ? i18n("Unmute") : i18n("Mute")
                from: PulseAudio.MinimalVolume
                to: view.sound.hasSink ? Math.max(PulseAudio.NormalVolume, view.sound.sink.volume) : PulseAudio.NormalVolume
                stepSize: PulseAudio.NormalVolume / 100
                value: view.sound.hasSink ? view.sound.sink.volume : 0
                valueText: view.sound.percent + " %"
                muted: view.sound.muted
                hasDetail: true
                detailLabel: i18n("Sound outputs and apps")
                onMoved: v => view.sound.setVolume(v)
                onIconClicked: view.sound.toggleMute()
                onDetailRequested: view.openPage("sound")
            }
            SliderRow {
                Layout.fillWidth: true
                visible: view.display.available
                label: i18n("Brightness")
                iconName: "video-display-brightness-symbolic"
                from: view.display.primary ? Math.max(1, Math.round(view.display.primary.maxBrightness / 100)) : 0
                to: view.display.primary ? Math.max(view.display.primary.maxBrightness, from + 1) : 1
                stepSize: view.display.primary ? Math.max(1, view.display.primary.maxBrightness / 100) : 1
                value: view.display.primary ? view.display.primary.brightness : 0
                valueText: view.display.primary ? Math.round(view.display.primary.brightness / Math.max(1, view.display.primary.maxBrightness) * 100) + " %" : ""
                // One per display when there are several
                hasDetail: view.display.count > 1
                detailLabel: i18n("Brightness of each display")
                onMoved: v => view.display.set(view.display.primary.displayName, v)
                onDetailRequested: view.openPage("display")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Only where there is a battery
            RowLayout {
                visible: view.power.hasBattery
                spacing: 8
                Accessible.role: Accessible.StaticText
                Accessible.name: i18n("Battery %1", view.power.batteryText)
                Kirigami.Icon {
                    source: view.power.batteryIcon
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    isMask: true
                    color: Kirigami.Theme.textColor
                    Accessible.ignored: true
                }
                PC3.Label {
                    text: i18n("%1 %", view.power.percent)
                    Accessible.ignored: true
                }
            }
            Item { Layout.fillWidth: true }
            PC3.ToolButton {
                icon.name: "edit-paste-symbolic"
                display: PC3.AbstractButton.IconOnly
                text: i18n("Clipboard history")
                Accessible.name: text
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered || visualFocus
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: view.clipboardRequested()
            }
            PC3.ToolButton {
                icon.name: "preferences-system-symbolic"
                display: PC3.AbstractButton.IconOnly
                text: i18n("Settings")
                Accessible.name: text
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered || visualFocus
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: view.settingsRequested("")
            }
        }
    }
}
