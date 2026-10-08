/*
    SPDX-FileCopyrightText: 2026 Telamon OS
    SPDX-License-Identifier: Apache-2.0

    The frame of a detail view: a Back arrow and the title (and a switch, if
    the thing has one) over the content, and one "... settings" link at the
    bottom. Escape goes back. The content scrolls when it is long.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

FocusScope {
    id: page

    property string title
    // The link at the bottom: its text, and the Telamon Settings page it opens
    property string settingsText
    property string settingsPage
    // A switch beside the title
    property bool hasSwitch: false
    property bool switchChecked: false
    property bool switchEnabled: true
    default property alias content: contentColumn.data
    readonly property real maxContentHeight: Kirigami.Units.gridUnit * 20

    signal back()
    signal settingsRequested(string page)
    signal switchToggled(bool checked)

    implicitHeight: frame.implicitHeight + 32
    Accessible.role: Accessible.Pane
    Accessible.name: title

    Keys.onEscapePressed: event => {
        page.back();
        event.accepted = true;
    }

    ColumnLayout {
        id: frame
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PC3.ToolButton {
                id: backButton
                display: PC3.AbstractButton.IconOnly
                contentItem: Chevron { back: true; color: Kirigami.Theme.textColor }
                text: i18n("Back")
                Accessible.name: i18n("Back to Quick Settings")
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered || visualFocus
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: page.back()
            }
            PC3.Label {
                Layout.fillWidth: true
                text: page.title
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                elide: Text.ElideRight
                Accessible.ignored: true
            }
            PC3.Switch {
                visible: page.hasSwitch
                checked: page.switchChecked
                enabled: page.switchEnabled
                Accessible.name: page.title
                onToggled: {
                    page.switchToggled(checked);
                    // Back to what the system says (it may refuse, e.g. a hardware block)
                    checked = Qt.binding(() => page.switchChecked);
                }
            }
        }

        PC3.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentColumn.implicitHeight, page.maxContentHeight)
            contentWidth: availableWidth
            PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

            ColumnLayout {
                id: contentColumn
                width: scroll.availableWidth
                spacing: 8
            }
        }

        PC3.Button {
            visible: page.settingsText !== ""
            Layout.alignment: Qt.AlignLeft
            flat: true
            text: page.settingsText
            icon.name: "preferences-system-symbolic"
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            onClicked: page.settingsRequested(page.settingsPage)
        }
    }

    // The Back arrow has the focus first, so Enter or Escape goes straight back
    Component.onCompleted: backButton.forceActiveFocus()
}
