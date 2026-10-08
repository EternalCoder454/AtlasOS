/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    What Quick Settings knows about Bluetooth: whether there is any, whether
    it is on, who is connected and the paired devices, from BlueZ-Qt.
*/

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.bluetooth as PlasmaBt

Item {
    id: self
    visible: false

    readonly property bool available: BluezQt.Manager.adapters.length > 0 || BluezQt.Manager.bluetoothBlocked
    readonly property bool on: BluezQt.Manager.bluetoothOperational
    readonly property var connected: BluezQt.Manager.connectedDevices
    readonly property string subtitle: {
        if (!on) {
            return i18n("Off");
        }
        if (connected.length === 0) {
            return i18n("On");
        }
        return connected.length === 1 ? connected[0].name : i18np("%1 device", "%1 devices", connected.length);
    }
    readonly property string iconName: connected.length > 0 ? "network-bluetooth-activated-symbolic"
        : on ? "network-bluetooth-symbolic" : "network-bluetooth-inactive-symbolic"
    readonly property alias paired: paired

    function setEnabled(enable) {
        BluezQt.Manager.bluetoothBlocked = !enable;
        BluezQt.Manager.adapters.forEach(adapter => adapter.powered = enable);
    }

    PlasmaBt.DevicesProxyModel {
        id: allDevices
        hideBlockedDevices: true
        // Not a binding: the shared model is a singleton and setting this
        // from a binding makes QML warn of a loop
        Component.onCompleted: sourceModel = PlasmaBt.SharedDevicesStateProxyModel
    }
    // Paired devices only
    KItemModels.KSortFilterProxyModel {
        id: paired
        sourceModel: allDevices
        filterRowCallback: (row, parent) => sourceModel.data(sourceModel.index(row, 0, parent), sourceModel.KItemModels.KRoleNames.role("Paired")) === true
    }
}
