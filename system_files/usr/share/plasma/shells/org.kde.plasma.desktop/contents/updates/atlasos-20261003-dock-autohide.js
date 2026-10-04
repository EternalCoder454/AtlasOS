/*
    SPDX-FileCopyrightText: 2026 AtlasOS
    SPDX-License-Identifier: Apache-2.0

    The dock hides until the pointer reaches the bottom edge, so apps get the
    whole screen (new desktops get this from the layout). Only the dock
    AtlasOS made is changed: a bottom panel with the task manager and the AtlasOS dock separator. Plasma
    runs each script here once per user (plasmashellrc, [Updates]), so one
    turned back on in its settings stays that way; never rename this file.
*/

panels().forEach(function (panel) {
    if (panel.location !== "bottom") {
        return;
    }
    if (panel.widgets("org.kde.plasma.icontasks").length === 0
        || panel.widgets("org.atlasos.dockseparator").length === 0) {
        return;
    }
    panel.hiding = "autohide";
});
