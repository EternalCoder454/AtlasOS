/*
    SPDX-FileCopyrightText: 2026 AtlasOS
    SPDX-License-Identifier: Apache-2.0

    The AtlasOS menu at the left of the menu bar was Kicker, a second app
    launcher beside the dock's. It becomes the AtlasOS Menu
    (org.atlasos.menu: About, settings, Force Quit and power), in the same
    place. Only the menu bar AtlasOS made is changed: a Kicker on a top panel
    with the AtlasOS icon. Plasma runs each script here once per user
    (plasmashellrc, [Updates]); never rename this file.

    The panel lays its widgets out from its AppletOrder setting (ids, left
    to right) and puts any it doesn't list at the end, so the new menu takes
    Kicker's id there. Moving it with widget.index instead breaks the panel
    while Plasma starts.
*/

panels().forEach(function (panel) {
    if (panel.location !== "top") {
        return;
    }
    panel.widgets("org.kde.plasma.kicker").forEach(function (kicker) {
        kicker.currentConfigGroup = ["General"];
        if (kicker.readConfig("icon", "") !== "atlasos") {
            return;
        }
        panel.currentConfigGroup = ["General"];
        var order = String(panel.readConfig("AppletOrder", ""));
        var ids = order ? order.split(";") : panel.widgetIds.map(String);
        var menu = panel.addWidget("org.atlasos.menu");
        var at = ids.indexOf(String(kicker.id));
        if (at < 0) {
            ids.unshift(String(menu.id));
        } else {
            ids[at] = String(menu.id);
        }
        kicker.remove();
        panel.currentConfigGroup = ["General"];
        panel.writeConfig("AppletOrder", ids.join(";"));
    });
});
