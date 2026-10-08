/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Quick Settings, at the end of the menu bar's tray island where Plasma's
    "show hidden icons" arrow was: sound (with each app's own volume and
    output), display brightness, Wi-Fi, Bluetooth and power in one popup, each
    with a link to its page in Telamon Settings. The tray beside it shows only
    apps' status icons (and the notification bell, which has to stay: the
    notification popups are drawn by that widget).

    It reuses Plasma's own backends (plasma-pa, plasma-nm, BlueZ-Qt,
    PowerDevil's brightness and power profiles) and adds none. Calling
    MicrophoneIndicator.init() is what the tray's Volume widget did: it puts
    a "Microphone" icon in the tray while an app is recording, so the privacy
    indicator survives that widget leaving the tray.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.volume as Volume
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    Plasmoid.icon: "configure-symbolic"
    Plasmoid.title: i18n("Quick Settings")
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: i18n("Quick Settings")
    toolTipSubText: i18n("Sound, display, Wi-Fi, Bluetooth and power")

    Component.onCompleted: Volume.MicrophoneIndicator.init()

    // Starts a program as the user would from a launcher. Only fixed
    // command lines go through here.
    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    // Opens a page of Telamon Settings (ids: crates/settings-registry,
    // pages.rs) and closes the popup.
    function openSettings(page) {
        run.connectSource(page ? "telamon-settings --page " + page : "telamon-settings");
        root.expanded = false;
    }

    compactRepresentation: MouseArea {
        id: button

        property bool wasExpanded: false

        // Square: as wide as the menu bar is tall, like the menu button.
        Layout.minimumWidth: root.vertical ? 0 : height
        Layout.minimumHeight: root.vertical ? width : 0

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.name: i18n("Quick Settings")
        Accessible.description: i18n("Sound, display, Wi-Fi, Bluetooth and power")
        Accessible.role: Accessible.Button
        Accessible.onPressAction: root.expanded = !root.expanded

        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.expanded = !root.expanded;
                event.accepted = true;
            }
        }

        // The hover tile of the dock and menu bar: a rounded, see-through
        // highlight; also the keyboard focus ring.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 6
            color: Kirigami.Theme.highlightColor
            opacity: root.expanded ? 0.28 : (button.containsMouse ? 0.16 : 0)
            visible: opacity > 0
            border.width: button.activeFocus ? 2 : 0
            border.color: Kirigami.Theme.highlightColor
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 6
            color: "transparent"
            visible: button.activeFocus
            border.width: 2
            border.color: Kirigami.Theme.highlightColor
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            source: Plasmoid.icon
            color: Kirigami.Theme.textColor
            isMask: true
        }
    }

    fullRepresentation: QuickSettings {
        onSettingsRequested: page => root.openSettings(page)
    }
}
