// The AtlasOS desktop: a macOS-style menu bar along the top and a Windows
// 11-style taskbar along the bottom.
//
// Menu bar: the AtlasOS menu (apps, settings and power, like the Apple menu)
// and the active window's menus (File, Edit, View...) on the left; the system
// tray and the day, date and time on the right.
//
// Taskbar: the start button and pinned apps centred between two flexible
// spacers, and "show desktop" in the corner.

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

var bar = new Panel;
bar.location = "top";
bar.floating = false;
bar.height = 28;
// See-through with the desktop blurred behind it, like both macOS's menu
// bar and Windows 11's taskbar
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

var panel = new Panel;
panel.location = "bottom";
panel.floating = false;
panel.height = 48;
panel.opacity = "translucent";

panel.addWidget("org.kde.plasma.panelspacer");

var start = panel.addWidget("org.kde.plasma.kickoff");
start.currentConfigGroup = ["General"];
start.writeConfig("icon", "atlasos");

// Pinned like Windows' File Explorer, browser and Store. "fill" off, so the
// task manager takes only the room its icons need and stays centred.
var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("fill", false);
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser",
    "applications:org.kde.discover.desktop",
]);

panel.addWidget("org.kde.plasma.panelspacer");

panel.addWidget("org.kde.plasma.showdesktop");
