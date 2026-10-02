// SPDX-FileCopyrightText: 2026 AtlasOS
// SPDX-License-Identifier: Apache-2.0

import QtCore
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasmasetup.prepareutil as Prepare
import org.kde.plasmasetup.components as PlasmaSetupComponents

// The first-run wizard's launcher choice, right after Appearance: Modern
// (Andromeda, the default) or Classic (Simple Kickoff). The choice goes to
// /var/lib/atlasos-setup/choices.ini (made for the wizard's user by
// tmpfiles.d/atlasos-setup.conf); the Global Themes' layout script reads it
// when a new user's desktop is first set up.
PlasmaSetupComponents.SetupModule {
    id: root

    nextEnabled: true

    Settings {
        id: choices
        location: "file:///var/lib/atlasos-setup/choices.ini"
        category: "Launcher"
        property string style: "modern"
    }

    function choose(style: string): void {
        choices.style = style;
        choices.sync();
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.gridUnit

        Item {
            Layout.fillHeight: true
        }

        Text {
            Layout.fillWidth: true
            Layout.maximumWidth: root.cardWidth
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Choose how apps open from the dock. You can switch later: right-click the launcher and choose Show Alternatives.")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font: Kirigami.Theme.defaultFont
            color: Kirigami.Theme.disabledTextColor
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            Layout.leftMargin: Kirigami.Units.gridUnit
            Layout.rightMargin: Kirigami.Units.gridUnit
            Layout.topMargin: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.gridUnit * 1.5

            PlasmaSetupComponents.ChoiceCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: i18n("Modern")
                description: i18n("Centred, with your favourite apps up front")
                checked: choices.style !== "classic"
                preview: PlasmaSetupComponents.DesktopPreview {
                    dark: Prepare.PrepareUtil.usingDarkTheme
                    launcher: "modern"
                }
                onClicked: root.choose("modern")
            }

            PlasmaSetupComponents.ChoiceCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: i18n("Classic")
                description: i18n("A compact menu with every app in a list")
                checked: choices.style === "classic"
                preview: PlasmaSetupComponents.DesktopPreview {
                    dark: Prepare.PrepareUtil.usingDarkTheme
                    launcher: "classic"
                }
                onClicked: root.choose("classic")
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
