/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    What Quick Settings knows about the network: the Wi-Fi adapter, its
    switch, the network it is on and the networks in range, from plasma-nm.
*/

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.networkmanager as NMQt
import org.kde.plasma.networkmanagement as PlasmaNM

Item {
    id: self
    visible: false

    readonly property bool hasWifi: devices.wirelessDeviceAvailable
    readonly property bool wifiOn: enabled.wirelessEnabled && !PlasmaNM.Configuration.airplaneModeEnabled
    readonly property bool canSwitch: enabled.wirelessHwEnabled && !PlasmaNM.Configuration.airplaneModeEnabled
    readonly property bool connected: hasWifi ? (wifiOn && wifiStatus.wifiSSID !== "") : status.activeConnections !== ""
    readonly property string title: hasWifi ? i18n("Wi-Fi") : i18n("Network")
    readonly property string subtitle: {
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
    readonly property string iconName: {
        if (!hasWifi) {
            return status.activeConnections === "" ? "network-disconnect-symbolic" : "network-wired-symbolic";
        }
        return wifiOn && wifiStatus.wifiSSID ? "network-wireless-connected-symbolic" : "network-wireless-disconnected-symbolic";
    }
    readonly property alias wifiList: wifiList
    readonly property alias handler: nmHandler

    function setWifi(on) {
        nmHandler.enableWireless(on);
    }
    function scan() {
        if (wifiOn) {
            nmHandler.requestScan("");
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
}
