/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Power: the power profile (Power Saver, Balanced, Performance: what
    power-profiles-daemon offers) and, on a computer with a battery, its
    charge and time left. Nothing about a battery on one without. Hidden
    when there is neither. PowerDevil's own models.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.private.batterymonitor
import org.kde.plasma.private.battery

Card {
    id: card

    readonly property bool hasBattery: battery.hasInternalBatteries
    readonly property bool hasProfiles: profiles.isPowerProfileDaemonInstalled && profiles.profiles.length > 0
    // The profiles in the order they are offered
    readonly property var offered: ["power-saver", "balanced", "performance"].filter(p => profiles.profiles.indexOf(p) >= 0)
    readonly property var labels: ({
        "power-saver": i18n("Power Saver"),
        "balanced": i18n("Balanced"),
        "performance": i18n("Performance")
    })
    readonly property var icons: ({
        "power-saver": "battery-profile-powersave-symbolic",
        "balanced": "battery-profile-balanced-symbolic",
        "performance": "battery-profile-performance-symbolic"
    })

    visible: hasBattery || hasProfiles
    iconName: {
        if (!hasBattery) {
            return card.icons[profiles.activeProfile] || "battery-profile-balanced-symbolic";
        }
        const level = Math.round(battery.percent / 10) * 10;
        const base = "battery-" + (level >= 100 ? "full" : String(level).padStart(3, "0"));
        return battery.state === BatteryControlModel.Charging ? base + "-charging-symbolic" : base + "-symbolic";
    }
    title: hasBattery ? i18n("Power & Battery") : i18n("Power")
    subtitle: {
        if (!hasBattery) {
            return card.labels[profiles.activeProfile] || "";
        }
        const parts = [i18n("%1 %", battery.percent)];
        if (battery.pluggedIn && battery.state === BatteryControlModel.FullyCharged) {
            parts.push(i18n("Fully charged"));
        } else if (battery.state === BatteryControlModel.Charging) {
            parts.push(battery.smoothedRemainingMsec > 0
                ? i18n("%1 until full", KCoreAddons.Format.formatDuration(battery.smoothedRemainingMsec, KCoreAddons.FormatTypes.HideSeconds))
                : i18n("Charging"));
        } else if (battery.state === BatteryControlModel.Discharging && battery.smoothedRemainingMsec > 0) {
            parts.push(i18n("%1 left", KCoreAddons.Format.formatDuration(battery.smoothedRemainingMsec, KCoreAddons.FormatTypes.HideSeconds)));
        } else if (battery.pluggedIn) {
            parts.push(i18n("Plugged in"));
        }
        return parts.join(" · ");
    }
    settingsLabel: i18n("Open Power settings")

    BatteryControlModel { id: battery }
    PowerProfilesControl {
        id: profiles
        // No on-screen display from the popup: the buttons are the feedback
        isSilent: true
    }

    RowLayout {
        Layout.fillWidth: true
        visible: card.hasProfiles
        spacing: Kirigami.Units.smallSpacing
        // Exactly one profile is on
        QQC2.ButtonGroup { id: group }
        Repeater {
            model: card.offered
            delegate: PC3.Button {
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                QQC2.ButtonGroup.group: group
                checkable: true
                checked: profiles.activeProfile === modelData
                text: card.labels[modelData]
                icon.name: card.icons[modelData]
                Accessible.name: i18n("Power profile %1", text)
                Accessible.checkable: true
                Accessible.checked: checked
                onClicked: {
                    profiles.setProfile(modelData);
                    // Back to what the daemon says if it refuses
                    checked = Qt.binding(() => profiles.activeProfile === modelData);
                }
            }
        }
    }
}
