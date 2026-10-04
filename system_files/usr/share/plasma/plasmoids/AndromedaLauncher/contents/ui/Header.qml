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
import org.kde.plasma.core as PlasmaCore
import QtQuick
import org.kde.kcmutils as KCM

import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PC3
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
  property var iconSize
  implicitWidth: buttons.implicitWidth
  implicitHeight: buttons.implicitHeight

  Kicker.SystemModel {
    id: systemModel
    favoritesModel: kicker.systemFavorites
  }

  component FilteredModel : KItemModels.KSortFilterProxyModel {
      sourceModel: systemModel

      function systemFavoritesContainsRow(sourceRow, sourceParent) {
          const FavoriteIdRole = sourceModel.KItemModels.KRoleNames.role("favoriteId");
          const favoriteId = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), FavoriteIdRole);
          return String(Plasmoid.configuration.systemFavorites).includes(favoriteId);
      }

      function trigger(index) {
          const sourceIndex = mapToSource(this.index(index, 0));
          systemModel.trigger(sourceIndex.row, "", null);
      }

      Component.onCompleted: {
          Plasmoid.configuration.valueChanged.connect((key, value) => {
              if (key === "systemFavorites") {
                  invalidateFilter();
              }
          });
      }
  }

  FilteredModel {
    id: filteredButtonsModel
    filterRowCallback: (sourceRow, sourceParent) =>
        systemFavoritesContainsRow(sourceRow, sourceParent)
  }

  FilteredModel {
      id: filteredMenuItemsModel
      filterRowCallback: root.shouldCollapseButtons
          ? null /*i.e. keep all rows*/
          : (sourceRow, sourceParent) => !systemFavoritesContainsRow(sourceRow, sourceParent)
  }

  // AtlasOS: a small round button tinted with the accent, as Atlas.Ui's
  // toolbar buttons; `symbol` is a Material Symbol codepoint.
  component RoundSymbolButton : PC3.RoundButton {
    id: btn
    property int symbol: 0
    property string fallbackIcon
    property bool open: false
    flat: true
    readonly property real glyph: Kirigami.Units.iconSizes.smallMedium
    height: Math.round(glyph * 1.6)
    width: height
    padding: 0
    hoverEnabled: true
    background: Rectangle {
      radius: width / 2
      color: Qt.alpha(Kirigami.Theme.highlightColor, btn.down || btn.open ? 0.3 : btn.hovered ? 0.22 : 0.14)
      border.width: btn.visualFocus ? 2 : 0
      border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.6)
      Behavior on color {
        ColorAnimation { duration: Kirigami.Units.shortDuration }
      }
    }
    contentItem: AtlasSymbol {
      code: btn.symbol
      fallback: btn.fallbackIcon
      size: btn.glyph
      color: Kirigami.Theme.highlightColor
    }
  }

  // The lock action of the system model, if this session offers one.
  property int lockRow: -1

  function findLockRow() {
    const role = systemModel.KItemModels.KRoleNames.role("favoriteId");
    for (let r = 0; r < systemModel.rowCount(); ++r) {
      if (systemModel.data(systemModel.index(r, 0), role) === "lock-screen") {
        return r;
      }
    }
    return -1;
  }

  Connections {
    target: systemModel
    function onRowsInserted() { lockRow = findLockRow(); }
    function onRowsRemoved() { lockRow = findLockRow(); }
    function onModelReset() { lockRow = findLockRow(); }
  }
  Component.onCompleted: lockRow = findLockRow()

  Row {
    id: buttons
    spacing: Kirigami.Units.smallSpacing

    RoundSymbolButton {
      id: settingsButton
      symbol: 0xe8b8 // settings
      fallbackIcon: "configure"
      Accessible.name: i18n("System Settings")
      onClicked: {
        KCM.KCMLauncher.openSystemSettings("kcm_landingpage")
        root.toggle()
      }
    }

    RoundSymbolButton {
      id: lockButton
      visible: lockRow >= 0
      symbol: 0xe897 // lock
      fallbackIcon: "system-lock-screen"
      Accessible.name: i18n("Lock Screen")
      onClicked: {
        const row = findLockRow();
        if (row >= 0) {
          root.toggle();
          systemModel.trigger(row, "", null);
        }
      }
    }

    RoundSymbolButton {
      id: leaveButton
      Accessible.role: Accessible.ButtonMenu
      Accessible.name: i18n("Leave")
      symbol: 0xe8ac // power_settings_new
      fallbackIcon: "system-shutdown"
      // Make it look pressed while the menu is open
      open: contextMenu.status === PlasmaExtras.Menu.Open

      Keys.onLeftPressed: event => {
          if (Qt.application.layoutDirection == Qt.LeftToRight) {
              nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
          }
      }
      Keys.onRightPressed: event => {
          if (Qt.application.layoutDirection == Qt.RightToLeft) {
              nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
          }
      }
      onPressed: contextMenu.openRelative()
    }
  }

  Instantiator {
      model: filteredMenuItemsModel
      delegate: PlasmaExtras.MenuItem {
          required property int index
          required property var model

          text: model.display
          icon: model.decoration
          onClicked: {
            root.toggle();
            filteredMenuItemsModel.trigger(index);
          }
      }
      onObjectAdded: (index, object) => contextMenu.addMenuItem(object)
      onObjectRemoved: (index, object) => contextMenu.removeMenuItem(object)
  }

  PlasmaExtras.Menu {
      id: contextMenu
      visualParent: leaveButton
      placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
  }
}
