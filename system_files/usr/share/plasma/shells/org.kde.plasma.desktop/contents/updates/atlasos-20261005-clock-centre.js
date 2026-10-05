/*
    SPDX-FileCopyrightText: 2026 AtlasOS
    SPDX-License-Identifier: Apache-2.0

    The middle island's clock sat a few pixels left of the island's centre:
    a panel puts a gap between its last widget and an empty filler after
    it. A 1 px spacer before the clock gets the same gap on the left. Only
    an island AtlasOS made is changed: a top, centred "fit" panel holding
    just a clock. Plasma runs each script here once per user
    (plasmashellrc, [Updates]); never rename this file.

    A panel keeps its widgets in the order they were added, and rewrites
    an order set from a script. Widgets changed while Plasma starts are
    left out of the panel's layout and it shows empty until the next
    start, so, as atlasos-20261004-islands.js does, the island is made
    new (spacer, then a clock with every setting of the old one) on the
    old one's screen, with its settings, and the old one removed.
*/

var islands = panels().filter(function (panel) {
    var widgets = panel.widgets();
    return panel.location === "top" && panel.lengthMode === "fit"
        && panel.alignment === "center" && widgets.length === 1
        && widgets[0].type === "org.kde.plasma.digitalclock";
});

islands.forEach(function (old) {
    var oldClock = old.widgets()[0];

    // The old clock's settings, one level of groups deep (the clock keeps
    // them all in [Appearance]). Read back as text, which KConfig parses
    // again when the new clock reads them.
    var settings = [];
    oldClock.currentConfigGroup = [];
    Array.prototype.slice.call(oldClock.configGroups || []).forEach(function (group) {
        oldClock.currentConfigGroup = [group];
        Array.prototype.slice.call(oldClock.configKeys || []).forEach(function (key) {
            settings.push({ group: group, key: key, value: oldClock.readConfig(key, "") });
        });
    });
    var shortcut = oldClock.globalShortcut;

    var panel = null;
    try {
        panel = new Panel;
        panel.screen = old.screen;
        panel.location = "top";
        panel.floating = old.floating;
        panel.lengthMode = "fit";
        panel.alignment = "center";
        panel.height = old.height;
        panel.opacity = old.opacity;
        // dodgewindows, or windowsgobelow after Meta+M
        panel.hiding = old.hiding;

        var spacer = panel.addWidget("org.kde.plasma.panelspacer");
        var clock = panel.addWidget("org.kde.plasma.digitalclock");
        if (!spacer || !clock) {
            throw new Error("a widget couldn't be added");
        }
        spacer.currentConfigGroup = ["General"];
        spacer.writeConfig("expanding", false);
        spacer.writeConfig("length", 1);
        settings.forEach(function (setting) {
            clock.currentConfigGroup = [setting.group];
            clock.writeConfig(setting.key, setting.value);
        });
    } catch (e) {
        // Keep the old island rather than end up with two, or none
        print("atlasos-20261005-clock-centre: " + e);
        if (panel) {
            panel.remove();
        }
        return;
    }
    old.remove();
    // After the old clock is gone: a key can only have one owner
    if (shortcut) {
        try {
            clock.globalShortcut = shortcut;
        } catch (e) {
            print("atlasos-20261005-clock-centre: the shortcut: " + e);
        }
    }
});
