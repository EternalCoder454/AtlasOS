/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The menu bar showed menus only for apps that export them. The Telamon OS App
    Menu (org.telamon.appmenu) goes right after Plasma's App Menu and fills
    the bar for every other app and for the desktop. Only the menu bar
    Telamon OS made is changed: a top panel with the Telamon OS Menu. Plasma runs
    each script here once per user (plasmashellrc, [Updates]); never rename
    this file.

    The panel lays its widgets out from its AppletOrder setting (ids, left
    to right) and puts any it doesn't list at the end, so the new widget is
    put in the order next to Plasma's App Menu. Moving it with widget.index
    instead breaks the panel while Plasma starts.
*/

panels().forEach(function (panel) {
    if (panel.location !== "top" || panel.widgets("org.telamon.menu").length === 0) {
        return;
    }
    if (panel.widgets("org.telamon.appmenu").length > 0) {
        return;
    }
    panel.currentConfigGroup = ["General"];
    var order = String(panel.readConfig("AppletOrder", ""));
    var ids = order ? order.split(";") : panel.widgetIds.map(String);
    var appmenu = panel.addWidget("org.telamon.appmenu");
    var after = panel.widgets("org.kde.plasma.appmenu");
    var at = after.length > 0 ? ids.indexOf(String(after[0].id)) : -1;
    if (at < 0) {
        // No App Menu in the bar: after the Telamon OS Menu
        at = ids.indexOf(String(panel.widgets("org.telamon.menu")[0].id));
    }
    if (at < 0) {
        // Neither is in the order: leave it to Plasma, which puts the widget last
        return;
    }
    ids.splice(at + 1, 0, String(appmenu.id));
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ids.join(";"));
});
