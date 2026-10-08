/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The top-bar button's glyph: two sliders, drawn here so it looks the same
    in every icon theme (and is not the gear of the Settings button inside
    the popup).
*/

import QtQuick

Item {
    id: glyph

    property color color: "black"

    implicitWidth: 22
    implicitHeight: 22

    // Two tracks, a knob on each (one up, one down, as Control Center's)
    Repeater {
        model: [ { y: 6.5, knob: 14 }, { y: 15.5, knob: 8 } ]
        delegate: Item {
            required property var modelData
            Rectangle {
                x: 3
                y: modelData.y - 1
                width: 16
                height: 2
                radius: 1
                antialiasing: true
                color: glyph.color
                opacity: 0.55
            }
            Rectangle {
                x: modelData.knob - 3
                y: modelData.y - 3
                width: 6
                height: 6
                radius: 3
                antialiasing: true
                color: glyph.color
            }
        }
    }
}
