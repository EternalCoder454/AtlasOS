/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The Wi-Fi view: the networks in range to connect to (a saved one connects
    at once; a new one with a password asks for it here; anything else, such as
    a company network, goes to NetworkManager's own prompt).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

DetailPage {
    id: page

    required property var net
    // How many networks show before "Show more"
    property int shown: 7

    title: i18n("Wi-Fi")
    settingsText: i18n("Network settings…")
    settingsPage: "network"
    hasSwitch: net.hasWifi
    switchChecked: net.wifiOn
    switchEnabled: net.canSwitch
    onSwitchToggled: checked => net.setWifi(checked)
    Component.onCompleted: net.scan()

    PC3.Label {
        Layout.fillWidth: true
        visible: !page.net.wifiOn
        text: i18n("Wi-Fi is off.")
        wrapMode: Text.Wrap
        opacity: 0.65
    }
    PC3.Label {
        Layout.fillWidth: true
        visible: page.net.wifiOn && page.net.wifiList.count === 0
        text: i18n("Looking for networks…")
        wrapMode: Text.Wrap
        opacity: 0.65
    }
    Repeater {
        model: page.net.wifiOn ? page.net.wifiList : null
        delegate: WifiNetwork {
            required property int index
            required property var model
            network: model
            handler: page.net.handler
            visible: index < page.shown
            Layout.fillWidth: true
        }
    }
    PC3.Button {
        visible: page.net.wifiOn && page.net.wifiList.count > page.shown
        Layout.alignment: Qt.AlignHCenter
        flat: true
        text: i18n("Show more networks")
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: page.shown = page.net.wifiList.count
    }
}
