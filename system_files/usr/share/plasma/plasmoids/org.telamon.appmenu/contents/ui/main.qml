/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The rest of the menu bar's menus, so it is never empty like macOS's.
    Plasma's own App Menu (org.kde.plasma.appmenu, just before this one)
    shows the menus an app exports: only Qt and KDE apps do on Wayland (GTK
    needs X11 for its module, libadwaita has no menu bar, Chromium and
    Electron export none). For every other app, and for the desktop with no
    window active, this shows the app's name in bold and a default set of
    menus; with an app that does export its menus it hides itself.

    Plasma's App Menu keeps its model in its own plugin, so this can't ask
    it. It asks what that model asks: whether the active window has a menu
    registered (ApplicationMenuServiceName in the Task Manager's model).

    Wayland lets no app type keys into another, so there is no Undo, Cut,
    Copy or Paste here; Edit has the clipboard history and the emoji picker.
    Everything else goes through the Task Manager's own requests (the ones
    its right-click menu uses) or KWin's shortcuts.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // What the active window is, as of the last time that was safe to ask
    // (see refresh)
    property bool hasWindow: false
    property bool hasMenu: false
    property string appName: ""
    // The window's id, not its row: rows move while a menu is open
    property var winId: null
    property bool closable: false
    property bool minimizable: false
    property bool maximizable: false
    property bool fullScreenable: false
    property bool fullScreen: false

    property bool menuOpen: false

    // Horizontal only: the menu bar is a top panel
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: hasMenu ? PlasmaCore.Types.HiddenStatus : PlasmaCore.Types.ActiveStatus

    TaskManager.TasksModel {
        id: tasks
        filterByScreen: false
        onActiveTaskChanged: root.refresh()
        onCountChanged: root.refresh()
        onDataChanged: root.refresh()
    }

    // Clicking the panel itself makes it the active window. Keep what the
    // last app had meanwhile, so the bar doesn't turn to the desktop's while
    // a menu is open, and catch up when the panel lets go.
    Connections {
        target: Plasmoid.containment
        function onStatusChanged() {
            root.refresh();
        }
    }

    onMenuOpenChanged: refresh()
    Component.onCompleted: refresh()

    // Whether any window is up on screen
    function windowsShown() {
        const role = TaskManager.AbstractTasksModel;
        for (let row = 0; row < tasks.rowCount(); ++row) {
            if (tasks.data(tasks.index(row, 0), role.IsMinimized) !== true) {
                return true;
            }
        }
        return false;
    }

    function refresh() {
        if (menuOpen || Plasmoid.containment.status === PlasmaCore.Types.AcceptingInputStatus) {
            return;
        }
        const index = tasks.activeTask;
        // The launcher, KRunner and the panels are active windows the Task
        // Manager doesn't list, so activeTask is empty for them as well as for
        // the desktop. Tell them apart by whether any window is up: with one,
        // keep the last app's menus. Not exact: the desktop clicked above
        // open windows keeps the app's menus.
        if (!index.valid && windowsShown() && winId !== null) {
            return;
        }
        if (!index.valid) {
            hasWindow = false;
            hasMenu = false;
            winId = null;
            appName = "";
            return;
        }
        const role = TaskManager.AbstractTasksModel;
        const service = String(tasks.data(index, role.ApplicationMenuServiceName) || "");
        hasWindow = true;
        winId = tasks.data(index, role.WinIdList)[0];
        hasMenu = !!service;
        appName = String(tasks.data(index, role.AppName) || i18n("App"));
        closable = tasks.data(index, role.IsClosable) === true;
        minimizable = tasks.data(index, role.IsMinimizable) === true;
        maximizable = tasks.data(index, role.IsMaximizable) === true;
        fullScreenable = tasks.data(index, role.IsFullScreenable) === true;
        fullScreen = tasks.data(index, role.IsFullScreen) === true;
    }

    // The window's row now, or an invalid index if it has gone, so a click
    // never reaches another window.
    function target() {
        const role = TaskManager.AbstractTasksModel;
        for (let row = 0; row < tasks.rowCount(); ++row) {
            const index = tasks.index(row, 0);
            const ids = tasks.data(index, role.WinIdList);
            if (ids && ids[0] === winId) {
                return index;
            }
        }
        return tasks.index(-1, -1);
    }

    function act(request) {
        const index = target();
        if (index.valid) {
            request(index);
        }
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

    // One of KWin's shortcuts, which act on the active window or the desktop.
    function kwin(shortcut) {
        run.command("gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.invokeShortcut '" + shortcut + "'");
    }

    function openFolder(dir) {
        run.command("xdg-open \"$(xdg-user-dir " + dir + ")\"");
    }

    // A word in the menu bar that opens a menu when clicked. The items are
    // its children.
    component BarMenu: PlasmaComponents3.ToolButton {
        id: button

        default property alias items: menu.content

        checked: menu.status === PlasmaExtras.Menu.Open
        onPressed: checked ? menu.close() : menu.openRelative()

        PlasmaExtras.Menu {
            id: menu
            visualParent: button
            placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
            onStatusChanged: root.menuOpen = status === PlasmaExtras.Menu.Open
        }
    }

    fullRepresentation: RowLayout {
        spacing: 0
        Layout.minimumWidth: root.hasMenu ? 0 : implicitWidth
        Layout.maximumWidth: root.hasMenu ? 0 : -1
        visible: !root.hasMenu

        // The app's name, bold like macOS's; the desktop's is "Desktop"
        PlasmaComponents3.Label {
            text: root.hasWindow ? root.appName : i18n("Desktop")
            font.bold: true
            elide: Text.ElideRight
            Layout.maximumWidth: Kirigami.Units.gridUnit * 12
            Layout.leftMargin: 6
            Layout.rightMargin: 6
        }

        // An app's window
        BarMenu {
            text: i18n("File")
            visible: root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("New Window")
                onClicked: root.act(index => tasks.requestNewInstance(index))
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                text: i18n("Close Window")
                enabled: root.closable
                onClicked: root.act(index => tasks.requestClose(index))
            }
        }
        BarMenu {
            text: i18n("Edit")
            visible: root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("Clipboard History…")
                onClicked: run.command("gdbus call --session --dest org.kde.klipper --object-path /klipper --method org.kde.klipper.klipper.showKlipperPopupMenu")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Emoji & Symbols…")
                onClicked: run.command("plasma-emojier")
            }
        }
        BarMenu {
            text: i18n("View")
            visible: root.hasWindow
            PlasmaExtras.MenuItem {
                text: root.fullScreen ? i18n("Exit Full Screen") : i18n("Enter Full Screen")
                enabled: root.fullScreenable
                onClicked: root.act(index => tasks.requestToggleFullScreen(index))
            }
        }
        BarMenu {
            text: i18n("Window")
            visible: root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("Minimize")
                enabled: root.minimizable
                onClicked: root.act(index => tasks.requestToggleMinimized(index))
            }
            PlasmaExtras.MenuItem {
                text: i18n("Zoom")
                enabled: root.maximizable
                onClicked: root.act(index => tasks.requestToggleMaximized(index))
            }
            PlasmaExtras.MenuItem { separator: true }
            PlasmaExtras.MenuItem {
                text: i18n("Show All Windows")
                onClicked: root.kwin("Overview")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Show Desktop")
                onClicked: root.kwin("Show Desktop")
            }
        }

        // The desktop, with no window active
        BarMenu {
            text: i18n("File")
            visible: !root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("New Folder")
                // On the desktop, named like Finder's, and never over one
                onClicked: run.command("d=\"$(xdg-user-dir DESKTOP)\"; n=\"untitled folder\"; i=2; while [ -e \"$d/$n\" ]; do n=\"untitled folder $i\"; i=$((i+1)); done; mkdir -p \"$d/$n\"")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Open Home Folder")
                onClicked: root.openFolder("HOME")
            }
        }
        BarMenu {
            text: i18n("Go")
            visible: !root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("Home")
                onClicked: run.command("xdg-open \"$HOME\"")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Documents")
                onClicked: root.openFolder("DOCUMENTS")
            }
            PlasmaExtras.MenuItem {
                text: i18n("Downloads")
                onClicked: root.openFolder("DOWNLOAD")
            }
        }
        BarMenu {
            text: i18n("Window")
            visible: !root.hasWindow
            PlasmaExtras.MenuItem {
                text: i18n("Show All Windows")
                onClicked: root.kwin("Overview")
            }
        }

        BarMenu {
            text: i18n("Help")
            PlasmaExtras.MenuItem {
                text: i18n("Keyboard Shortcuts…")
                onClicked: run.command("telamon-settings --kcm kcm_keys")
            }
        }
    }
}
