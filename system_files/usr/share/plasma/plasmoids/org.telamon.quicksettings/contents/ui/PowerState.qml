/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    What Quick Settings knows about power: the power profile
    (power-profiles-daemon, through PowerDevil) and, on a computer with a
    battery, its charge and time left, from PowerDevil's own models.
*/

import QtQuick
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.private.batterymonitor
import org.kde.plasma.private.battery

Item {
    id: self
    visible: false

    readonly property bool hasBattery: battery.hasInternalBatteries
    readonly property bool hasProfiles: profiles.isPowerProfileDaemonInstalled && profiles.profiles.length > 0
    readonly property int percent: battery.percent
    readonly property bool charging: battery.state === BatteryControlModel.Charging
    // The profiles in the order they are offered
    readonly property var offered: ["power-saver", "balanced", "performance"].filter(p => profiles.profiles.indexOf(p) >= 0)
    readonly property string activeProfile: profiles.activeProfile
    readonly property var labels: ({
        "power-saver": i18n("Power Saver"),
        "balanced": i18n("Balanced"),
        "performance": i18n("Performance")
    })
    readonly property var icons: ({
        "power-saver": "battery-profile-powersave-symbolic",
        "balanced": "speedometer-symbolic",
        "performance": "battery-profile-performance-symbolic"
    })
    readonly property string profileLabel: labels[activeProfile] || ""
    readonly property string profileIcon: icons[activeProfile] || "speedometer-symbolic"
    readonly property string batteryIcon: {
        const level = Math.round(battery.percent / 10) * 10;
        const base = "battery-" + (level >= 100 ? "full" : String(level).padStart(3, "0"));
        return charging ? base + "-charging-symbolic" : base + "-symbolic";
    }
    // "87 % · 3 h 12 min left"
    readonly property string batteryText: {
        const parts = [i18n("%1 %", battery.percent)];
        if (battery.pluggedIn && battery.state === BatteryControlModel.FullyCharged) {
            parts.push(i18n("Fully charged"));
        } else if (charging) {
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

    function setProfile(profile) {
        profiles.setProfile(profile);
    }
    // The next profile in the order offered (Balanced after Power Saver...)
    function nextProfile() {
        const at = offered.indexOf(activeProfile);
        return offered[(at + 1) % offered.length];
    }

    BatteryControlModel { id: battery }
    PowerProfilesControl {
        id: profiles
        // No on-screen display from the popup: the choices are the feedback
        isSilent: true
    }
}
