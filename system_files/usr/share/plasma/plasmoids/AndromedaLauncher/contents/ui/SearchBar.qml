import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami

import org.kde.plasma.plasmoid 2.0

Rectangle {

    // AtlasOS: Atlas.Ui SearchField's pill.
    radius: height / 2
    color: Qt.alpha(Kirigami.Theme.textColor, textField.hovered && !textField.activeFocus ? 0.09 : 0.06)
    border.width: textField.activeFocus ? 2 : 1
    border.color: textField.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)

    property alias textField: textField

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Kirigami.Icon {
            id: searchIcon
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            source: "search"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.55
        }

        TextField {
            id: textField
            Layout.fillHeight: true
            Layout.fillWidth: true
            font: Kirigami.Theme.defaultFont
            color: Kirigami.Theme.textColor
            placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.5)
            selectionColor: Kirigami.Theme.highlightColor
            selectedTextColor: Kirigami.Theme.highlightedTextColor

            placeholderText: i18n("Search...")
            background: Rectangle{
                color: "transparent"
            }
            focus: true
            onTextChanged: {
                textField.forceActiveFocus(Qt.ShortcutFocusReason)
                runnerModel.query = text;   
            }

            Keys.onPressed: event => {
                if (event.key == Qt.Key_Escape) {
                    event.accepted = true;
                    if (searching) {
                        clear();
                    } else {
                        root.toggle()
                    }
                }
            }
        }
    }
}