/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    One paired Bluetooth device: click to connect or disconnect. `device` is
    the row of BlueZ-Qt's devices model.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.bluetooth as PlasmaBt

PC3.ItemDelegate {
    id: item

    property var device

    readonly property bool connected: device.Connected
    readonly property bool busy: device.Connecting || device.Disconnecting
    readonly property int battery: device.Battery ? device.Battery.percentage : -1
    readonly property string stateText: device.Connecting ? i18n("Connecting…") : device.Disconnecting ? i18n("Disconnecting…")
        : connected ? i18n("Connected") : i18n("Not connected")

    Accessible.name: i18nc("device name, state, battery", "%1, %2%3", device.Name, stateText,
        battery >= 0 ? i18n(", battery %1 %", battery) : "")
    Accessible.description: connected ? i18n("Disconnect") : i18n("Connect")

    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    onClicked: {
        if (busy) {
            return;
        }
        if (connected) {
            PlasmaBt.SharedDevicesStateProxyModel.registerDisconnectingCallForDeviceUbi(device.Device.disconnectFromDevice(), device.Ubi);
        } else {
            PlasmaBt.SharedDevicesStateProxyModel.registerConnectingCallForDeviceUbi(device.Device.connectToDevice(), device.Ubi);
        }
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing * 2
        Kirigami.Icon {
            // The symbolic one follows the text colour (the plain one is dark in the dark theme)
            source: item.device.Icon ? item.device.Icon + "-symbolic" : "network-bluetooth-symbolic"
            fallback: "network-bluetooth-symbolic"
            isMask: true
            color: Kirigami.Theme.textColor
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
            Accessible.ignored: true
        }
        PC3.Label {
            Layout.fillWidth: true
            text: item.device.Name
            elide: Text.ElideRight
            font.weight: item.connected ? Font.DemiBold : Font.Normal
            Accessible.ignored: true
        }
        PC3.Label {
            visible: item.battery >= 0
            text: i18n("%1 %", item.battery)
            opacity: 0.7
            Accessible.ignored: true
        }
        PC3.Label {
            text: item.stateText
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Accessible.ignored: true
        }
    }
}
