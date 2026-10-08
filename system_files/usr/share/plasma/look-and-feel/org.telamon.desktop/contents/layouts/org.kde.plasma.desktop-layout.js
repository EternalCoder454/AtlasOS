// The Telamon OS desktop: a macOS-style menu bar along the top and a dock along
// the bottom.
//
// Menu bar: three floating islands, each only as wide as what it holds. On
// the left the Telamon OS menu (About, settings and power, like the Apple menu)
// and the active window's menus (File, Edit, View...); in the middle the time
// over the date (the calendar opens on a click); on the right the system
// tray (apps' icons) and Quick Settings. The islands hide while a window covers them, so maximized and
// fullscreen apps get the whole screen. Meta+M shows them over the windows
// (/usr/libexec/telamon/menubar-toggle), which keep their size.
//
// Dock: like macOS's, floating, centred and only as wide as its icons, which
// sit close together: the app launcher, a separator, then pinned and open
// apps. Running apps have a short underline. Its look (the see-through
// rounded plate, the icon spacing, the hover tile and the underline) is the
// Telamon OS Plasma style's, made by scripts/plasma-style.py for this height
// (60 px: 48 px icons). The launcher is Telamon Launcher.

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

// The dock comes first. Meta (and Alt+F1) open the first app launcher Plasma
// finds, panel by panel in the order they were made: the dock's.
var dock = new Panel;
dock.location = "bottom";
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.height = 60;
dock.opacity = "translucent";
// Hidden until the pointer reaches the bottom edge, as with macOS's
// "automatically hide and show the Dock": apps get the whole screen.
dock.hiding = "autohide";

// Telamon Launcher's dock button: it opens the launcher (telamon-launcher).
dock.addWidget("net.eterneon.telamon.launcher.button");

dock.addWidget("org.telamon.dockseparator");

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("fill", false);
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser",
    "applications:com.mitchellh.ghostty.desktop",
    "applications:net.eterneon.telamon.store.desktop",
    "applications:org.kde.discover.desktop",
    "applications:net.eterneon.telamon.settings.desktop",
]);

// The menu bar's islands. See-through with the desktop blurred behind them,
// like macOS's menu bar. "dodgewindows" hides one while a window overlaps it
// and shows it again when the pointer reaches the top edge; menubar-toggle
// switches them all between that and "windowsgobelow" (shown on top of the
// windows, which still get the whole screen).
function island(alignment) {
    var panel = new Panel;
    panel.location = "top";
    panel.floating = true;
    panel.lengthMode = "fit";
    panel.alignment = alignment;
    panel.height = 34;
    panel.opacity = "translucent";
    panel.hiding = "dodgewindows";
    return panel;
}

var menus = island("left");
// About, settings, Force Quit and power; no apps (those are the dock's)
menus.addWidget("org.telamon.menu");
// The active app's own menus when it exports them (Qt and KDE apps)...
menus.addWidget("org.kde.plasma.appmenu");
// ...and for any other app, or the desktop, the app's name and a default set,
// so the menu bar is never empty
menus.addWidget("org.telamon.appmenu");

var middle = island("center");
// A panel puts a gap between its last widget and an empty filler after it,
// so a lone clock sits that gap's half left of the island's centre. A 1 px
// spacer before it gets the same gap on the left.
var spacer = middle.addWidget("org.kde.plasma.panelspacer");
spacer.currentConfigGroup = ["General"];
spacer.writeConfig("expanding", false);
spacer.writeConfig("length", 1);
var clock = middle.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", 2); // below the time
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd MMM d"); // Fri Oct 2

// The tray island: apps' status icons, then Quick Settings (sound, display,
// Wi-Fi, Bluetooth and power in one popup) where Plasma's "show hidden
// icons" arrow would be.
var rightIsland = island("right");
var tray = rightIsland.addWidget("org.kde.plasma.systemtray");
// Only apps' icons (StatusNotifierItems) and the notification bell: the
// bell's widget draws the notification popups, so it has to be loaded. The
// widgets Quick Settings replaces (volume, Wi-Fi, Bluetooth, battery,
// brightness) and the other system ones are turned off: "known" so Plasma
// doesn't turn them back on. Everything is shown in the tray itself, so
// there is no overflow popup and no arrow. See DEV.md, "Quick Settings".
tray.currentConfigGroup = ["General"];
tray.writeConfig("showAllItems", true);
tray.writeConfig("extraItems", ["org.kde.plasma.notifications"]);
tray.writeConfig("knownItems", [
    "org.kde.plasma.notifications",
    "org.kde.plasma.volume",
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.battery",
    "org.kde.plasma.brightness",
    "org.kde.plasma.clipboard",
    "org.kde.plasma.devicenotifier",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.keyboardlayout",
    "org.kde.plasma.keyboardindicator",
    "org.kde.plasma.manage-inputmethod",
    "org.kde.plasma.cameraindicator",
    "org.kde.plasma.printmanager",
    "org.kde.plasma.diskquota",
    "org.kde.plasma.vault",
    "org.kde.plasma.weather",
    "org.kde.plasma.trash",
    "org.kde.plasma.addons.katesessions",
    "org.kde.kscreen",
    "org.kde.kdeconnect",
]);
rightIsland.addWidget("org.telamon.quicksettings");
