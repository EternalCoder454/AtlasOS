/*
    SPDX-FileCopyrightText: 2026 AtlasOS
    SPDX-License-Identifier: Apache-2.0

    Atlas Launcher replaces Andromeda and the stock launchers. In every panel
    each AndromedaLauncher, Kickoff, Kicker, Kicker Dashboard or Simple
    Kickoff widget becomes the Atlas Launcher button at the same spot, and the
    old favourites (favoriteApps, or Kickoff's favorites) are copied into the
    button's ImportPins. The AtlasOS menu bar's Kicker (icon "atlasos" on a
    top panel) was already turned into the AtlasOS menu by the 20261003 script
    and is not touched when that script has run. A panel without these widgets is left alone, and a
    second run finds nothing to change. Plasma runs each script here once per
    user (plasmashellrc, [Updates]); never rename this file.
    The position is set through AppletOrder, as atlasos-20261003-menu.js does:
    moving a widget with widget.index breaks the panel while Plasma starts.
*/

var OLD = [
    "AndromedaLauncher",
    "org.kde.plasma.kickoff",
    "org.kde.plasma.kicker",
    "org.kde.plasma.kickerdash",
    "org.kde.plasma.simplekickoff"
];
var BUTTON = "net.eterneon.atlas.launcher.button";

panels().forEach(function (panel) {
    var found = [];
    OLD.forEach(function (type) {
        panel.widgets(type).forEach(function (widget) {
            found.push(widget);
        });
    });
    if (found.length === 0) {
        return;
    }
    var pins = "";
    found.forEach(function (widget) {
        if (pins !== "") {
            return;
        }
        widget.currentConfigGroup = ["General"];
        var value = widget.readConfig("favoriteApps", "");
        if (!value) {
            value = widget.readConfig("favorites", "");
        }
        pins = value ? String(value) : "";
    });

    panel.currentConfigGroup = ["General"];
    var order = String(panel.readConfig("AppletOrder", ""));
    var ids = order ? order.split(";") : panel.widgetIds.map(String);

    // One button per panel; one that is already there only has the old ones removed
    var button = panel.widgets(BUTTON)[0];
    var fresh = !button;
    if (fresh) {
        button = panel.addWidget(BUTTON);
        if (button && pins !== "") {
            button.currentConfigGroup = ["General"];
            button.writeConfig("ImportPins", pins);
        }
    }
    if (button) {
        var buttonId = String(button.id);
        var at = ids.indexOf(String(found[0].id));
        if (fresh) {
            if (at < 0) {
                ids.unshift(buttonId);
            } else {
                ids[at] = buttonId;
            }
        }
    }
    found.forEach(function (widget) {
        var id = String(widget.id);
        widget.remove();
        var gone = ids.indexOf(id);
        if (gone >= 0) {
            ids.splice(gone, 1);
        }
    });
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ids.join(";"));
});
