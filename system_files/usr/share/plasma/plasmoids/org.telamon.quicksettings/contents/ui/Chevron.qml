/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    A chevron drawn here, so it looks the same in every icon theme (the
    themes' arrows are filled triangles, arrows or chevrons as they like),
    from two rounded bars: no icon file, no path, sharp at every scale.
*/

import QtQuick

Item {
    id: chevron

    property color color: "black"
    // Pointing left, for Back
    property bool back: false

    implicitWidth: 16
    implicitHeight: 16

    transform: Scale {
        origin.x: chevron.width / 2
        xScale: chevron.back ? -1 : 1
    }

    // Two bars of 8 x 2 meeting at a point on the right: (6,3) - (11,8) - (6,13)
    Rectangle {
        width: 8
        height: 2
        radius: 1
        antialiasing: true
        color: chevron.color
        x: chevron.width / 2 + 0.5 - width / 2
        y: chevron.height / 2 - 2.5 - height / 2
        rotation: 45
    }
    Rectangle {
        width: 8
        height: 2
        radius: 1
        antialiasing: true
        color: chevron.color
        x: chevron.width / 2 + 0.5 - width / 2
        y: chevron.height / 2 + 2.5 - height / 2
        rotation: -45
    }
}
