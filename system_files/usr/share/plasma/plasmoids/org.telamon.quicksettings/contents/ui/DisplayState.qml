/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    What Quick Settings knows about display brightness: the displays
    PowerDevil can control (laptop panels, DDC/CI monitors). `primary` is the
    one the main slider sets: the built-in display, else the first.
*/

import QtQuick
import QtQml
import org.kde.plasma.private.brightnesscontrolplugin

Item {
    id: self
    visible: false

    readonly property alias control: control
    readonly property bool available: control.isBrightnessAvailable && count > 0
    readonly property int count: displays.count
    property var primary: null

    function set(displayName, value) {
        control.setBrightness(displayName, Math.round(value));
    }

    ScreenBrightnessControl {
        id: control
        // No on-screen display from the popup: the slider is the feedback
        isSilent: true
    }

    // One object for each display, with the model's roles as properties
    Instantiator {
        id: displays
        model: control.displays
        delegate: QtObject {
            required property string displayName
            required property string label
            required property int brightness
            required property int maxBrightness
            required property bool isInternal
        }
        onObjectAdded: self.pickPrimary()
        onObjectRemoved: self.pickPrimary()
    }

    function pickPrimary() {
        let best = null;
        for (let i = 0; i < displays.count; i++) {
            const d = displays.objectAt(i);
            if (d && (best === null || (d.isInternal && !best.isInternal))) {
                best = d;
            }
        }
        primary = best;
    }
}
