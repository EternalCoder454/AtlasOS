// The AtlasOS desktop: a macOS-style menu bar along the top and a dock along
// the bottom.
//
// Menu bar: the AtlasOS menu (apps, settings and power, like the Apple menu)
// and the active window's menus (File, Edit, View...) on the left; the system
// tray and the day, date and time on the right.
//
// Dock: like macOS's, floating, centred and only as wide as its icons, which
// sit close together: the app launcher, a separator, then pinned and open
// apps. Running apps have a short underline. Its look (the see-through
// rounded plate, the icon spacing, the hover tile and the underline) is the
// AtlasOS Plasma style's, made by scripts/plasma-style.py for this height
// (60 px: 48 px icons). The launcher is the one
// chosen in the first-run wizard: Modern (Andromeda, the default) or Classic
// (Simple Kickoff).

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

// The dock comes first: Meta (and Alt+F1) open the first app launcher Plasma
// finds, panel by panel in the order they were made, and that should be the
// dock's rather than the menu bar's AtlasOS menu.
var dock = new Panel;
dock.location = "bottom";
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.height = 60;
dock.opacity = "translucent";

// The wizard's launcher page writes this file (see
// /usr/lib/tmpfiles.d/atlasos-setup.conf); without it, Modern.
var choices = ConfigFile("/var/lib/atlasos-setup/choices.ini", "Launcher");
var classic = choices.readEntry("style") == "classic";

var launcher;
if (classic) {
    launcher = dock.addWidget("org.kde.plasma.simplekickoff");
    launcher.currentConfigGroup = ["General"];
} else {
    launcher = dock.addWidget("AndromedaLauncher");
    launcher.currentConfigGroup = ["General"];
    launcher.writeConfig("launcherPosition", 1); // centred over the dock
}
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

var bar = new Panel;
bar.location = "top";
bar.floating = false;
bar.height = 28;
// See-through with the desktop blurred behind it, like macOS's menu bar
bar.opacity = "translucent";

var menu = bar.addWidget("org.kde.plasma.kicker");
menu.currentConfigGroup = ["General"];
menu.writeConfig("icon", "atlasos");

bar.addWidget("org.kde.plasma.appmenu");
bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.kde.plasma.systemtray");

var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", 1); // beside the time, on one line
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd MMM d"); // Fri Oct 2
