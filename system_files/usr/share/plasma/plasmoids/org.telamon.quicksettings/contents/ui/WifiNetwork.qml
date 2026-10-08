/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    One Wi-Fi network in the list. `network` is the row of plasma-nm's
    model. The password typed for a new network goes to NetworkManager and
    nowhere else: it is never logged or kept.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.networkmanagement as PlasmaNM

ColumnLayout {
    id: item

    property var network
    property var handler
    property bool askingPassword: false

    readonly property bool active: network.ConnectionState === PlasmaNM.Enums.Activated
    readonly property bool busy: network.ConnectionState === PlasmaNM.Enums.Activating
        || network.ConnectionState === PlasmaNM.Enums.Deactivating
    readonly property int security: network.SecurityType
    readonly property bool secured: security !== PlasmaNM.Enums.NoneSecurity && security !== PlasmaNM.Enums.UnknownSecurity
    // A new network whose password can be typed here (the others: open
    // ones need none; a company network's secrets are asked for by NM)
    readonly property bool needsPassword: !network.Uuid && (security === PlasmaNM.Enums.StaticWep
        || security === PlasmaNM.Enums.WpaPsk || security === PlasmaNM.Enums.Wpa2Psk || security === PlasmaNM.Enums.SAE)
    readonly property string signalWord: network.Signal >= 75 ? i18n("excellent signal")
        : network.Signal >= 50 ? i18n("good signal") : network.Signal >= 25 ? i18n("weak signal") : i18n("very weak signal")
    readonly property string actionText: busy ? i18n("Connecting…") : active ? i18n("Disconnect") : i18n("Connect")

    spacing: 0

    function toggle() {
        if (busy) {
            return;
        }
        if (active) {
            handler.deactivateConnection(network.ConnectionPath, network.DevicePath);
        } else if (network.Uuid) {
            handler.activateConnection(network.ConnectionPath, network.DevicePath, network.SpecificPath);
        } else if (needsPassword) {
            askingPassword = true;
            password.forceActiveFocus();
        } else {
            handler.addAndActivateConnection(network.DevicePath, network.SpecificPath);
        }
    }

    function submitPassword() {
        if (password.acceptableInput) {
            handler.addAndActivateConnection(network.DevicePath, network.SpecificPath, password.text);
            password.text = "";
            askingPassword = false;
        }
    }

    PC3.ItemDelegate {
        Layout.fillWidth: true
        Accessible.name: i18nc("network name, security, signal, state", "%1, %2, %3, %4",
            network.ItemUniqueName, secured ? i18n("secured") : i18n("open"), signalWord,
            active ? i18n("connected") : busy ? i18n("connecting") : item.network.Uuid ? i18n("saved") : i18n("not connected"))
        Accessible.description: actionText
        onClicked: item.toggle()
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing * 2
            Kirigami.Icon {
                source: item.network.ConnectionIcon ? item.network.ConnectionIcon + "-symbolic" : "network-wireless-symbolic"
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
                isMask: true
                color: Kirigami.Theme.textColor
                Accessible.ignored: true
            }
            PC3.Label {
                Layout.fillWidth: true
                text: item.network.ItemUniqueName
                elide: Text.ElideRight
                font.weight: item.active ? Font.DemiBold : Font.Normal
                Accessible.ignored: true
            }
            Kirigami.Icon {
                visible: item.secured
                source: "lock-symbolic"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                isMask: true
                color: Kirigami.Theme.textColor
                opacity: 0.7
                Accessible.ignored: true
            }
            PC3.Label {
                text: item.actionText
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                Accessible.ignored: true
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        visible: item.askingPassword
        spacing: Kirigami.Units.smallSpacing

        PlasmaExtras.PasswordField {
            id: password
            Layout.fillWidth: true
            placeholderText: i18n("Password")
            Accessible.name: i18n("Password for %1", item.network.ItemUniqueName)
            validator: RegularExpressionValidator {
                regularExpression: item.security === PlasmaNM.Enums.StaticWep
                    ? /^(?:.{5}|[0-9a-fA-F]{10}|.{13}|[0-9a-fA-F]{26})$/ : /^(?:.{8,64})$/
            }
            onAccepted: item.submitPassword()
            Keys.onEscapePressed: event => {
                text = "";
                item.askingPassword = false;
                event.accepted = true;
            }
        }
        PC3.Button {
            text: i18n("Connect")
            enabled: password.acceptableInput
            onClicked: item.submitPassword()
        }
    }
}
