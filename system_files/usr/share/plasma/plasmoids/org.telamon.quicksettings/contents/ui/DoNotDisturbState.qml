/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Do Not Disturb: the same switch the notification bell's popup has
    (notifications hidden for a year, or until it is turned off again).
*/

import QtQuick
import org.kde.notificationmanager as NotificationManager

Item {
    id: self
    visible: false

    readonly property bool available: NotificationManager.Server.valid
    readonly property bool on: NotificationManager.Server.inhibited

    function setOn(enable) {
        if (enable) {
            const until = new Date();
            until.setFullYear(until.getFullYear() + 1);
            settings.notificationsInhibitedUntil = until;
        } else {
            settings.notificationsInhibitedUntil = undefined;
            settings.revokeApplicationInhibitions();
        }
        settings.save();
    }

    NotificationManager.Settings { id: settings }
}
