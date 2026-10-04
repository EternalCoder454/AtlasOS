/*****************************************************************************
 *   Copyright (C) 2022 by Friedrich Schriewer <friedrich.schriewer@gmx.net> *
 *                                                                           *
 *   This program is free software; you can redistribute it and/or modify    *
 *   it under the terms of the GNU General Public License as published by    *
 *   the Free Software Foundation; either version 2 of the License, or       *
 *   (at your option) any later version.                                     *
 *                                                                           *
 *   This program is distributed in the hope that it will be useful,         *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of          *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           *
 *   GNU General Public License for more details.                            *
 *                                                                           *
 *   You should have received a copy of the GNU General Public License       *
 *   along with this program; if not, write to the                           *
 *   Free Software Foundation, Inc.,                                         *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .          *
 ****************************************************************************/
import QtQuick 2.15
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.coreaddons 1.0 as KCoreAddons

import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigami as Kirigami
import QtQuick.Controls

import "js/colorType.js" as ColorType

Item {
  id: main
  property bool searching: (searchBar.textField.text != "")
 // signal  newTextQuery(string text)

  readonly property color textColor: Kirigami.Theme.textColor
  readonly property string textFont: plasmoid.configuration.useSystemFontSettings ? Kirigami.Theme.defaultFont.family : "SF Pro Text"
  readonly property real textSize: plasmoid.configuration.useSystemFontSettings ? Kirigami.Theme.defaultFont.pointSize : 11
  readonly property color bgColor: Kirigami.Theme.backgroundColor
  readonly property color highlightColor: Kirigami.Theme.highlightColor
  readonly property color highlightedTextColor: Kirigami.Theme.highlightedTextColor

  readonly property color glowColor1: plasmoid.configuration.glowColor == 0 ? "#6252DD" : // AtlasOS violets
                                      plasmoid.configuration.glowColor == 1 ? "#20bdff" :
                                      "#ff005d"
  readonly property color glowColor2: plasmoid.configuration.glowColor == 0 ? "#9C8CF8" :
                                      plasmoid.configuration.glowColor == 1 ? "#5433ff" :
                                      "#ff8b26"

  property bool showAllApps: false

  property bool isDarkTheme: ColorType.isDark(bgColor)
  // AtlasOS: the neutral tint Atlas.Ui puts on its pill controls.
  property color contrastBgColor: Qt.alpha(Kirigami.Theme.textColor, 0.08)

  property int pinnedModel: plasmoid.configuration.pinnedModel

  property alias headerLabelRow: headerLabelRow
  property alias searchBar: searchBar
  property alias contentY: backdrop
  property int itemSpacing: Kirigami.Units.largeSpacing

  KCoreAddons.KUser {
      id: kuser
  }

  function reset(){
    showAllApps = false;
    searchBar.textField.clear();
    searchBar.textField.forceActiveFocus();
    stack.replace(pinnedAppsComponent)
    headerLabelRow.reset();
  }

  onPinnedModelChanged: headerLabelRow.reset()

  Rectangle {
    id: backdrop
    x: 0
    // AtlasOS: below the user row.
    y: headerBar.height + itemSpacing
    width: main.width
    height: main.height - y
    color: bgColor
    opacity: 0
  }

  // AtlasOS: a compact user row (small avatar, name) with the settings, lock
  // and power buttons on the right, instead of the big floating avatar.

  RowLayout {
    id: headerBar
    width: main.width
    spacing: Kirigami.Units.largeSpacing

    UserAvatar {
      id: userAvatar
      Layout.preferredWidth: Kirigami.Units.iconSizes.large
      Layout.preferredHeight: Kirigami.Units.iconSizes.large
      Layout.alignment: Qt.AlignVCenter
    }

    Greeting {
      id: greeting
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      textSize: Kirigami.Theme.defaultFont.pointSize
    }

    Header {
      id: powerSettings
      iconSize: Kirigami.Units.iconSizes.smallMedium
      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    }
  }

  // Fvorites / All apps label
  ColumnLayout {

    anchors.top: backdrop.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    spacing: itemSpacing

    // Search Bar (AtlasOS: on top, a pill like Atlas.Ui's SearchField)

    SearchBar {
      id: searchBar
      Layout.fillWidth: true
      Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 2.2)
      Layout.maximumHeight: Layout.preferredHeight
      Layout.alignment: Qt.AlignTop
      Keys.priority: Keys.AfterItem
      Keys.forwardTo: stack.currentItem.viewItem
    }

    RowLayout {
      id: headerLabelRow
      visible: !searching

      function reset() {
        if(showAllApps) {
          var appList = stack.currentItem
          var currentCategory = appList.getCurrentCategory();
          mainLabelGrid.text = currentCategory.name;
          sortingImage.source = currentCategory.icon;
          appList.updateShowedModel(currentCategory.index);
        } else {
          mainLabelGrid.text =  pinnedModel == 0 ? i18n("Favorite Apps") : i18n("Recent Apps");
        }
      }
        
      Kirigami.Icon {
        id: sortingImage
        Layout.preferredHeight: 15
        Layout.preferredWidth: 15
        Layout.fillHeight: false
        visible: main.showAllApps
      }

      PlasmaComponents.Label {
        id: mainLabelGrid
        font.family: textFont
        font.pointSize: textSize
        // AtlasOS: Atlas.Ui's Section title: semibold, subdued.
        font.weight: Font.DemiBold
        opacity: 0.65
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          enabled: showAllApps && !searching
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onClicked: {
            var appList = stack.currentItem;
            if (mouse.button == Qt.LeftButton) { appList.incrementCurrentStateIndex() }
            else if (mouse.button == Qt.RightButton) { appList.decrementCurrentStateIndex() }
            else if (mouse.button == Qt.MiddleButton) { appList.resetCurrentStateIndex() }
            headerLabelRow.reset();
          }
        }
      }

      // Show all app buttons
      PlasmaComponents.Button  {
        id: allAppsButton
        text: showAllApps ? i18n("Back") : i18n("All apps")
        flat: false
        
        topPadding: 6
        bottomPadding: topPadding
        leftPadding: 10
        rightPadding: 10

      //  icon.name: showAllApps ? "go-previous" : "go-next"
        icon.height: 15
        icon.width: 15

        font.pointSize: textSize
        font.family: textFont
        
        LayoutMirroring.enabled: true
        LayoutMirroring.childrenInherit: !showAllApps 
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

        onClicked: {
          showAllApps = !showAllApps;
          stack.replace(showAllApps ? allAppsComponent : pinnedAppsComponent)
          headerLabelRow.reset();
          searchBar.textField.forceActiveFocus(Qt.BacktabFocusReason);
        }
        background: Rectangle {
          id: btnBg
          color: Qt.alpha(Kirigami.Theme.highlightColor, allAppsButton.down ? 0.3 : allAppsButton.hovered ? 0.22 : 0.14)
          radius: height / 2

          Rectangle {
            id: bgMask
            width: parent.width
            height: parent.height
            radius: height / 2
            border.width: 1
            visible: plasmoid.configuration.enableGlow && !searching
          }
          Item {
            visible: plasmoid.configuration.enableGlow && !searching
            anchors.fill: bgMask
            layer.enabled: true
            layer.effect: OpacityMask { maskSource: bgMask }

            LinearGradient {
              anchors.fill: parent
              start: Qt.point(bgMask.width, 0)
              end: Qt.point(0, bgMask.height)
              gradient: Gradient {
                  GradientStop { position: 0.0; color: glowColor1 }
                  GradientStop { position: 1.0; color: glowColor2 }
              }
            }
          }
        }

        //All apps button shadow
        DropShadow {
            anchors.fill: btnBg
            cached: true
            horizontalOffset: 0
            verticalOffset: 0
            radius: 11.0
            samples: 16
            color: glowColor1
            source: btnBg
            visible: plasmoid.configuration.enableGlow && !searching
        }
      }

      Component.onCompleted: headerLabelRow.reset()
    }

    StackView {
      id: stack
      initialItem: pinnedAppsComponent
      Layout.fillWidth: true
      Layout.preferredHeight: root.cellSizeHeight*root.rows
      Keys.priority: Keys.AfterItem
      Keys.forwardTo: searchBar.textField
    }

    Component {
      id: pinnedAppsComponent
      PinnedApps{
        id: pinnedApps
      }
    }

    Component {
      id: allAppsComponent
      AllAppsList{
        id: appList
      }
    }

    Component {
      id:searchComponent
      RunnerList {
        id: runnerList
        model: runnerModel.count ? runnerModel.modelForRow(0) : null
      }
    }

  }
  onSearchingChanged: {
    if(searching){
      stack.replace(searchComponent)
    } else if(showAllApps) {
      stack.replace(allAppsComponent);
       headerLabelRow.reset();
    } else { 
      stack.replace(pinnedAppsComponent);
       headerLabelRow.reset();
    }
  }
}
