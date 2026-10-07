/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The menu bar was one bar across the top. It becomes three floating
    islands, as in new desktops' layout: the Telamon OS menu and the app's menus
    on the left, the time over the date in the middle, the tray on the right.
    They hide while a window covers them; Meta+M shows them over it
    (/usr/libexec/telamon/menubar-toggle). Only the menu bar Telamon OS made is
    changed: a full-width top panel with the Telamon OS Menu (the first one, if
    there are several; a bar the user made "fit" is left alone). Plasma runs
    each script here once per user (plasmashellrc, [Updates]); never rename
    this file.

    Widgets can't move between panels, and the old bar can't become the
    right island: changed while Plasma starts, its widgets are left out of
    its layout and it shows empty. So the islands are made new, on the old
    bar's screen, and the old bar removed. The tray keeps which icons the
    user showed, hid or turned off, the clock its 12 or 24-hour and seconds
    settings and a date format the user picked, and widgets the user added to
    the bar come back (with their defaults) after the tray.
*/

function island(alignment, screen) {
    var panel = new Panel;
    panel.screen = screen;
    panel.location = "top";
    panel.floating = true;
    panel.lengthMode = "fit";
    panel.alignment = alignment;
    panel.height = 34;
    panel.opacity = "translucent";
    panel.hiding = "dodgewindows";
    return panel;
}

// A setting as read: one never changed reads back empty, and written, that
// would replace its default (an empty use24hFormat is 12-hour), so it counts
// as not set
function isSet(value) {
    return value !== undefined && value !== null && value !== "";
}

// A list setting as an array without empty entries
function list(value) {
    var items = typeof value === "string"
        ? value.split(",") : Array.prototype.slice.call(value || []);
    return items.filter(function (item) { return item !== ""; });
}

var bar = panels().filter(function (panel) {
    return panel.location === "top" && panel.lengthMode !== "fit"
        && panel.widgets("org.telamon.menu").length > 0;
})[0];

if (bar) {
    var screen = bar.screen;

    // The bar's widgets, left to right (its AppletOrder, then any it doesn't
    // list, as Plasma lays them out)
    bar.currentConfigGroup = ["General"];
    var order = String(bar.readConfig("AppletOrder", ""));
    var ids = order ? order.split(";") : [];
    var widgets = bar.widgets().slice().sort(function (a, b) {
        var ia = ids.indexOf(String(a.id));
        var ib = ids.indexOf(String(b.id));
        return (ia < 0 ? ids.length : ia) - (ib < 0 ? ids.length : ib);
    });
    // What the islands make again, one of each, so a second clock or tray
    // the user added comes back too; spacers are dropped
    var remade = {
        "org.telamon.menu": 1,
        "org.kde.plasma.appmenu": 1,
        "org.telamon.appmenu": 1,
        "org.kde.plasma.systemtray": 1,
        "org.kde.plasma.digitalclock": 1,
        "org.kde.plasma.panelspacer": Infinity,
    };

    var menus = island("left", screen);
    menus.addWidget("org.telamon.menu");
    menus.addWidget("org.kde.plasma.appmenu");
    menus.addWidget("org.telamon.appmenu");

    var middle = island("center", screen);
    // A 1 px spacer before the clock centres it (see the look-and-feel
    // layout); atlasos-20261005-clock-centre.js then leaves it alone
    var spacer = middle.addWidget("org.kde.plasma.panelspacer");
    if (spacer) {
        spacer.currentConfigGroup = ["General"];
        spacer.writeConfig("expanding", false);
        spacer.writeConfig("length", 1);
    }
    var clock = middle.addWidget("org.kde.plasma.digitalclock");
    var oldClock = bar.widgets("org.kde.plasma.digitalclock")[0];
    var dateFormat = "ddd MMM d"; // Fri Oct 2
    if (clock && oldClock) {
        oldClock.currentConfigGroup = ["Appearance"];
        clock.currentConfigGroup = ["Appearance"];
        ["use24hFormat", "showSeconds"].forEach(function (key) {
            var value = oldClock.readConfig(key, undefined);
            if (isSet(value)) {
                clock.writeConfig(key, value);
            }
        });
        var custom = oldClock.readConfig("customDateFormat", undefined);
        if (String(oldClock.readConfig("dateFormat", "")) === "custom" && isSet(custom)) {
            dateFormat = String(custom);
        }
    }
    if (clock) {
        clock.currentConfigGroup = ["Appearance"];
        clock.writeConfig("showDate", true);
        clock.writeConfig("dateDisplayFormat", 2); // below the time
        clock.writeConfig("dateFormat", "custom");
        clock.writeConfig("customDateFormat", dateFormat);
    }

    var right = island("right", screen);
    var tray = right.addWidget("org.kde.plasma.systemtray");
    var oldTray = bar.widgets("org.kde.plasma.systemtray")[0];
    if (tray && oldTray) {
        // Only the lists: which icons are always shown, which are kept in
        // the overflow, which are turned on, and which the tray has seen
        // (without that, ones the user turned off come back on). "Show all"
        // copied as read leaves every icon shown.
        oldTray.currentConfigGroup = ["General"];
        tray.currentConfigGroup = ["General"];
        ["shownItems", "hiddenItems", "extraItems", "knownItems"].forEach(function (key) {
            var items = list(oldTray.readConfig(key, []));
            if (items.length > 0) {
                tray.writeConfig(key, items);
            }
        });
    }

    widgets.forEach(function (widget) {
        var type = String(widget.type);
        if (remade[type] > 0) {
            remade[type]--;
            return;
        }
        try {
            right.addWidget(type);
        } catch (e) {
            // A widget that's no longer installed: left out, and the old
            // bar still goes
        }
    });

    bar.remove();
}
