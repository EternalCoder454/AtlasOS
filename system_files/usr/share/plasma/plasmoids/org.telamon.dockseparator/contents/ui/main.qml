/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    A thin line between groups of icons in the dock. Plasma's own
    "margins separator" is only a gap.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int across: Kirigami.Units.largeSpacing + 1

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    fullRepresentation: Item {
        Layout.minimumWidth: root.vertical ? -1 : root.across
        Layout.maximumWidth: root.vertical ? -1 : root.across
        Layout.minimumHeight: root.vertical ? root.across : -1
        Layout.maximumHeight: root.vertical ? root.across : -1

        Rectangle {
            anchors.centerIn: parent
            width: root.vertical ? Math.round(parent.width * 0.6) : 1
            height: root.vertical ? 1 : Math.round(parent.height * 0.6)
            color: Kirigami.Theme.textColor
            opacity: 0.25
        }
    }
}
