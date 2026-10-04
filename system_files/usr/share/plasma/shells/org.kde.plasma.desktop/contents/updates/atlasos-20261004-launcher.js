/*
    SPDX-FileCopyrightText: 2026 AtlasOS
    SPDX-License-Identifier: Apache-2.0

    The Classic app launcher (Simple Kickoff) is gone: Modern (Andromeda) is
    the only one. A dock or panel that still holds the Classic launcher would
    show a broken widget, so each gets Andromeda in its place: at the same
    spot in the panel, set up as the Global Themes' layout does (centred,
    the AtlasOS icon). Desktops without Simple Kickoff are left alone, and a
    second run finds nothing to change. Plasma runs each script here once per
    user (plasmashellrc, [Updates]); never rename this file.
*/

panels().forEach(function (panel) {
    var old = panel.widgets("org.kde.plasma.simplekickoff");
    if (old.length === 0) {
        return;
    }
    // Where the first Classic launcher sat, among the panel's widgets
    var index = old[0].index;
    // A panel that already has Andromeda only loses the Classic one
    if (panel.widgets("AndromedaLauncher").length === 0) {
        var launcher = panel.addWidget("AndromedaLauncher");
        if (launcher) {
            launcher.currentConfigGroup = ["General"];
            launcher.writeConfig("launcherPosition", 1);
            launcher.writeConfig("icon", "atlasos");
            try {
                // addWidget puts it last; the launcher is the first thing in
                // the dock, so without a known spot it goes first
                launcher.index = (typeof index === "number" && index >= 0) ? index : 0;
            } catch (e) {
                // The position can't be set: it stays where it was added
            }
        }
    }
    old.forEach(function (widget) {
        widget.remove();
    });
});
