/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Bluetooth: a switch, how many devices are connected, and, folded, the
    paired devices to connect or disconnect. Pairing a new device is the
    Bluetooth page's job. Hidden when the computer has no Bluetooth. The
    models are BlueZ-Qt's, as Plasma's Bluetooth widget uses.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.bluetooth as PlasmaBt

Card {
    id: card

    readonly property var connected: BluezQt.Manager.connectedDevices
    readonly property bool on: BluezQt.Manager.bluetoothOperational

    visible: BluezQt.Manager.adapters.length > 0 || BluezQt.Manager.bluetoothBlocked
    iconName: connected.length > 0 ? "network-bluetooth-activated-symbolic"
        : on ? "network-bluetooth-symbolic" : "network-bluetooth-inactive-symbolic"
    title: i18n("Bluetooth")
    subtitle: {
        if (BluezQt.Manager.bluetoothBlocked || BluezQt.Manager.adapters.length === 0) {
            return i18n("Off");
        }
        if (!on) {
            return i18n("Off");
        }
        if (connected.length === 0) {
            return i18n("On");
        }
        return connected.length === 1 ? connected[0].name : i18np("%1 device connected", "%1 devices connected", connected.length);
    }
    settingsLabel: i18n("Open Bluetooth settings")
    hasDetails: on
    hasSwitch: true
    switchChecked: on
    switchLabel: i18n("Bluetooth")
    onSwitchToggled: checked => {
        BluezQt.Manager.bluetoothBlocked = !checked;
        BluezQt.Manager.adapters.forEach(adapter => adapter.powered = checked);
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

    details: [
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                visible: paired.count === 0
                text: i18n("No paired devices.")
                wrapMode: Text.Wrap
                opacity: 0.7
            }
            Repeater {
                model: paired
                delegate: BluetoothDevice {
                    required property var model
                    device: model
                    Layout.fillWidth: true
                }
            }
            PC3.Button {
                Layout.alignment: Qt.AlignHCenter
                flat: true
                text: i18n("Bluetooth settings…")
                icon.name: "preferences-system-symbolic"
                onClicked: card.settingsRequested()
            }
        }
    ]
}
