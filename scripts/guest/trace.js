// KWin script for scripts/guest/daily.sh: logs, with millisecond times, each
// window that opens or closes and every size change of Plasma's panels.
function log(what, w) {
    var g = w.frameGeometry;
    console.info("ATLASTRACE " + Date.now() + " " + what + " " + w.resourceClass + " " +
                 Math.round(g.x) + "," + Math.round(g.y) + " " + Math.round(g.width) + "x" + Math.round(g.height) +
                 " " + w.caption);
}
function watch(w) {
    if (w.resourceClass == "plasmashell")
        w.frameGeometryChanged.connect(function () { log("geom", w); });
}
workspace.windowAdded.connect(function (w) { log("added", w); watch(w); });
workspace.windowRemoved.connect(function (w) { log("removed", w); });
workspace.windowActivated.connect(function (w) { if (w) log("active", w); });
workspace.windowList().forEach(watch);
