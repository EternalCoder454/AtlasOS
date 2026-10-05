// The AtlasOS desktop: a macOS-style menu bar along the top and a dock along
// the bottom.
//
// Menu bar: three floating islands, each only as wide as what it holds. On
// the left the AtlasOS menu (About, settings and power, like the Apple menu)
// and the active window's menus (File, Edit, View...); in the middle the time
// over the date (the calendar opens on a click); on the right the system
// tray. The islands hide while a window covers them, so maximized and
// fullscreen apps get the whole screen. Meta+M shows them over the windows
// (/usr/libexec/atlasos/menubar-toggle), which keep their size.
//
// Dock: like macOS's, floating, centred and only as wide as its icons, which
// sit close together: the app launcher, a separator, then pinned and open
// apps. Running apps have a short underline. Its look (the see-through
// rounded plate, the icon spacing, the hover tile and the underline) is the
// AtlasOS Plasma style's, made by scripts/plasma-style.py for this height
// (60 px: 48 px icons). The launcher is Andromeda.

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

var launcher = dock.addWidget("AndromedaLauncher");
launcher.currentConfigGroup = ["General"];
launcher.writeConfig("launcherPosition", 1); // centred over the dock
launcher.writeConfig("icon", "atlasos");

dock.addWidget("org.atlasos.dockseparator");

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("fill", false);
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser",
    "applications:com.mitchellh.ghostty.desktop",
    "applications:org.kde.discover.desktop",
    "applications:systemsettings.desktop",
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
menus.addWidget("org.atlasos.menu");
// The active app's own menus when it exports them (Qt and KDE apps)...
menus.addWidget("org.kde.plasma.appmenu");
// ...and for any other app, or the desktop, the app's name and a default set,
// so the menu bar is never empty
menus.addWidget("org.atlasos.appmenu");

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

var tray = island("right");
tray.addWidget("org.kde.plasma.systemtray");
