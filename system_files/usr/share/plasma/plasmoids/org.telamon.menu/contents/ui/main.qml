/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The Telamon OS menu at the left of the menu bar, like macOS's Apple menu:
    the computer, settings and power, and no apps (those are the dock's
    launcher). One click opens a plain menu; nothing is loaded until then.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    Plasmoid.icon: "telamon"
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // The button itself, shown in place (as Plasma's Lock/Logout widget does)
    preferredRepresentation: fullRepresentation

    Sessions.SessionManagement {
        id: session
    }

    // Starts a program as the user would from a launcher.
    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
        function command(cmd) {
            connectSource(cmd);
        }
    }

    fullRepresentation: MouseArea {
        id: button

        readonly property bool open: menu.status === PlasmaExtras.Menu.Open

        // Square: as wide as the menu bar is tall.
        Layout.minimumWidth: root.vertical ? 0 : height
        Layout.minimumHeight: root.vertical ? width : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.name: Plasmoid.title
        Accessible.role: Accessible.ButtonMenu

        onPressed: open ? menu.close() : menu.openRelative()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                menu.openRelative();
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: button.containsMouse || button.open
        }

        PlasmaExtras.Menu {
            id: menu
            visualParent: button
            placement: root.vertical ? PlasmaExtras.Menu.RightPosedTopAlignedPopup
                                     : PlasmaExtras.Menu.BottomPosedLeftAlignedPopup

            PlasmaExtras.MenuItem {
                text: i18n("About This Computer")
                onClicked: run.command("telamon-monitor --page system")
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                text: i18n("System Settings…")
                onClicked: run.command("systemsettings")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Store…")
                onClicked: run.command("plasma-discover")
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                // KWin's own: the next window clicked is closed by force.
                text: i18n("Force Quit…")
                onClicked: run.command("gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.killWindow")
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                text: i18n("Sleep")
                visible: session.canSuspend
                onClicked: session.suspend()
            }
            PlasmaExtras.MenuItem {
                text: i18n("Restart…")
                visible: session.canReboot
                onClicked: session.requestReboot()
            }
            PlasmaExtras.MenuItem {
                text: i18n("Shut Down…")
                visible: session.canShutdown
                onClicked: session.requestShutdown()
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                text: i18n("Lock Screen")
                visible: session.canLock
                onClicked: session.lock()
            }
            PlasmaExtras.MenuItem {
                text: i18n("Log Out…")
                visible: session.canLogout
                onClicked: session.requestLogout()
            }
        }
    }
}
