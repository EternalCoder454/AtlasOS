/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Wi-Fi: a switch, the network you are on, and, folded, the networks in
    range to connect to (a saved one connects at once; a new one with a
    password asks for it here; anything else, such as a company network,
    goes to NetworkManager's own prompt). Without a Wi-Fi adapter it is a
    plain "Network" line with the wired connection. The models and the
    handler are plasma-nm's.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.networkmanager as NMQt
import org.kde.plasma.networkmanagement as PlasmaNM

Card {
    id: card

    readonly property bool hasWifi: devices.wirelessDeviceAvailable
    readonly property bool wifiOn: enabled.wirelessEnabled && !PlasmaNM.Configuration.airplaneModeEnabled
    // How many networks show before "Show more"
    property int shown: 6

    iconName: {
        if (!hasWifi) {
            return status.connectivity === NMQt.NetworkManager.UnknownConnectivity || status.activeConnections === ""
                ? "network-disconnect-symbolic" : "network-wired-symbolic";
        }
        if (!wifiOn) {
            return "network-wireless-disconnected-symbolic";
        }
        return wifiStatus.wifiSSID ? "network-wireless-connected-symbolic" : "network-wireless-disconnected-symbolic";
    }
    title: hasWifi ? i18n("Wi-Fi") : i18n("Network")
    subtitle: {
        if (!hasWifi) {
            return status.activeConnections || i18n("Not connected");
        }
        if (PlasmaNM.Configuration.airplaneModeEnabled) {
            return i18n("Airplane mode");
        }
        if (!enabled.wirelessEnabled) {
            return i18n("Off");
        }
        return wifiStatus.wifiSSID || i18n("Not connected");
    }
    settingsLabel: i18n("Open Network settings")
    hasDetails: hasWifi && wifiOn
    hasSwitch: hasWifi
    switchChecked: wifiOn
    switchEnabled: enabled.wirelessHwEnabled && !PlasmaNM.Configuration.airplaneModeEnabled
    switchLabel: i18n("Wi-Fi")
    onSwitchToggled: checked => nmHandler.enableWireless(checked)
    // Looking for networks when the list opens
    Connections {
        target: card
        function onExpandedChanged() {
            if (card.expanded && card.wifiOn) {
                nmHandler.requestScan("");
            }
        }
    }

    PlasmaNM.EnabledConnections { id: enabled }
    PlasmaNM.AvailableDevices { id: devices }
    PlasmaNM.NetworkStatus { id: status }
    PlasmaNM.WirelessStatus { id: wifiStatus }
    PlasmaNM.Handler { id: nmHandler }
    PlasmaNM.NetworkModel { id: connections }
    PlasmaNM.AppletProxyModel {
        id: sorted
        sourceModel: connections
    }
    // Wi-Fi only (the proxy above also lists wired and VPN connections)
    KItemModels.KSortFilterProxyModel {
        id: wifiList
        sourceModel: sorted
        filterRowCallback: (row, parent) => {
            const index = sourceModel.index(row, 0, parent);
            return sourceModel.data(index, sourceModel.KItemModels.KRoleNames.role("Type")) === PlasmaNM.Enums.Wireless;
        }
    }

    details: [
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                visible: wifiList.count === 0
                text: i18n("Looking for networks…")
                wrapMode: Text.Wrap
                opacity: 0.7
            }
            Repeater {
                model: wifiList
                delegate: WifiNetwork {
                    required property int index
                    required property var model
                    network: model
                    handler: nmHandler
                    visible: index < card.shown
                    Layout.fillWidth: true
                }
            }
            PC3.Button {
                visible: wifiList.count > card.shown
                Layout.alignment: Qt.AlignHCenter
                text: i18n("Show more networks")
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: card.shown = wifiList.count
            }
            PC3.Button {
                Layout.alignment: Qt.AlignHCenter
                flat: true
                text: i18n("Network settings…")
                icon.name: "preferences-system-symbolic"
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: card.settingsRequested()
            }
        }
    ]
}
