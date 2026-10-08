/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    Quick Settings. The tray island showed the volume, Wi-Fi, Bluetooth,
    battery and brightness widgets next to the apps' icons, and Plasma's
    "show hidden icons" arrow. Now the tray shows only apps' icons (and the
    notification bell), and our Quick Settings widget (org.telamon.quicksettings)
    sits after it where the arrow was. In the tray of the right island of the
    menu bar (a right-aligned top panel in "fit" mode with a system tray, on a
    screen with the Telamon OS Menu):

      * the widgets Quick Settings replaces and the other system ones are
        turned off, and recorded as known so Plasma doesn't turn them back on;
      * "show all entries" is on: every app icon is in the tray itself, so
        there is no overflow popup and no arrow. Icons the user had put in
        the overflow are shown, which is the only way to reach them now;
      * everything else stays as the user had it: the app icons they turned
        off, the plasmoids they added to the tray (anything not in the list
        below), their other widgets in the panel;
      * Quick Settings is added once, at the end of the panel.

    The notification bell's widget is kept (not in the list): it draws the
    notification popups, so without it no notification would show.

    Plasma runs each script here once per user (plasmashellrc, [Updates]);
    never rename this file. It also does nothing when run again: a panel with
    Quick Settings is left alone. A panel the user made full-width, or one on
    another edge, is not touched. tests/quick-settings/run.sh runs this file
    on sample panels.
*/

// What Quick Settings replaces, and the system widgets that do not belong in
// a tray of apps' icons. Keep in step with the new-user layout in
// org.telamon.*.desktop/contents/layouts/org.kde.plasma.desktop-layout.js.
var turnedOff = [
    "org.kde.plasma.volume",
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.battery",
    "org.kde.plasma.brightness",
    "org.kde.plasma.clipboard",
    "org.kde.plasma.devicenotifier",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.keyboardlayout",
    "org.kde.plasma.keyboardindicator",
    "org.kde.plasma.manage-inputmethod",
    "org.kde.plasma.cameraindicator",
    "org.kde.plasma.printmanager",
    "org.kde.plasma.diskquota",
    "org.kde.plasma.vault",
    "org.kde.plasma.weather",
    "org.kde.plasma.trash",
    "org.kde.plasma.addons.katesessions",
    "org.kde.kscreen",
    "org.kde.kdeconnect",
];

// A list setting as an array without empty entries
function list(value) {
    var items = typeof value === "string"
        ? value.split(",") : Array.prototype.slice.call(value || []);
    return items.filter(function (item) { return item !== ""; });
}

function without(items, remove) {
    return items.filter(function (item) { return remove.indexOf(item) < 0; });
}

function withEach(items, add) {
    var out = items.slice();
    add.forEach(function (item) {
        if (out.indexOf(item) < 0) {
            out.push(item);
        }
    });
    return out;
}

// The right island of the menu bar Telamon OS made: a top, right-aligned "fit"
// panel with a tray, on a screen whose top panels include the Telamon OS Menu
// (a "fit" bar of the user's own, on another screen say, is not ours)
var all = panels();
all.filter(function (panel) {
    return panel.location === "top" && panel.lengthMode === "fit" && panel.alignment === "right"
        && panel.widgets("org.kde.plasma.systemtray").length > 0
        && panel.widgets("org.telamon.quicksettings").length === 0
        && all.some(function (other) {
            return other.screen === panel.screen && other.location === "top"
                && other.widgets("org.telamon.menu").length > 0;
        });
}).forEach(function (panel) {
    // Add the widget first: if it can't be, the tray keeps its volume,
    // network and the rest, and the next start tries again
    var quick = null;
    try {
        quick = panel.addWidget("org.telamon.quicksettings");
    } catch (e) {
        quick = null;
    }
    if (!quick) {
        return;
    }

    var tray = panel.widgets("org.kde.plasma.systemtray")[0];
    tray.currentConfigGroup = ["General"];
    var extra = list(tray.readConfig("extraItems", []));
    var known = list(tray.readConfig("knownItems", []));
    var shown = list(tray.readConfig("shownItems", []));
    var hidden = list(tray.readConfig("hiddenItems", []));

    // A tray Plasma never filled in (no entries known): the notification
    // bell is all that is on
    if (extra.length === 0 && known.length === 0) {
        extra = ["org.kde.plasma.notifications"];
    }

    tray.writeConfig("extraItems", without(extra, turnedOff));
    tray.writeConfig("knownItems", withEach(known, turnedOff.concat(["org.kde.plasma.notifications"])));
    tray.writeConfig("shownItems", without(shown, turnedOff));
    tray.writeConfig("hiddenItems", without(hidden, turnedOff));
    tray.writeConfig("showAllItems", true);
});
