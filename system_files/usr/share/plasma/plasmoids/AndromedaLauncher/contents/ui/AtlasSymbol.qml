import QtQuick
import org.kde.kirigami as Kirigami

// AtlasOS: one Material Symbol, drawn like Atlas.Ui's Symbol (which needs the
// Atlas apps' startup singletons, so the launcher draws the font itself).
// `code` is the symbol's codepoint; `fallback` is a theme icon used when the
// font (atlas-symbols-fonts) is not installed.
Item {
    id: root

    property int code: 0
    property string fallback
    property real size: Kirigami.Units.iconSizes.smallMedium
    property color color: Kirigami.Theme.textColor
    property real fill: 0

    readonly property string family: "Material Symbols Rounded"
    readonly property bool available: Qt.fontFamilies().indexOf(family) >= 0

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Text {
        anchors.centerIn: parent
        visible: root.available
        text: root.code > 0 ? String.fromCodePoint(root.code) : ""
        textFormat: Text.PlainText
        color: root.color
        font.family: root.family
        font.pixelSize: Math.max(1, Math.round(root.size))
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({
                "FILL": root.fill,
                "wght": 400,
                "GRAD": 0,
                "opsz": Math.max(20, Math.min(48, root.size))
            })
    }

    Kirigami.Icon {
        anchors.fill: parent
        visible: !root.available && root.fallback.length > 0
        source: root.fallback
        isMask: true
        color: root.color
    }
}
