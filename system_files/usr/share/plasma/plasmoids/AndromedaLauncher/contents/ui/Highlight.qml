import QtQuick
import org.kde.kirigami as Kirigami

// AtlasOS: the selection of Atlas.Ui's SidebarItem (4 px radius, accent
// tint) in place of the style's viewitem frame; no glow-effect masking.
Rectangle {
    id: highlight

    // Set automatically when used as a ListView or GridView highlight.
    property bool hovered: ListView.view !== null || GridView.view !== null
    property bool pressed: false
    // Kept for callers: true by default; false marks a current item that
    // isn't hovered.
    property bool active: true
    // Hide the tint (used when the glow effect marks the selection).
    property bool hideBg: false

    width: {
        const view = ListView.view;
        return view ? view.width - view.leftMargin - view.rightMargin : undefined;
    }

    radius: 4
    z: -20
    color: highlight.hideBg ? "transparent" : Qt.alpha(Kirigami.Theme.highlightColor, highlight.pressed ? 0.26 : 0.18)

    Behavior on color {
        ColorAnimation {
            duration: Kirigami.Units.shortDuration
        }
    }
}
