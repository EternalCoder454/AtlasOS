# AtlasOS changes

Andromeda Launcher by EliverLara, from
https://github.com/EliverLara/AndromedaLauncher (branch plasma6, commit
6bd0ac49b60888dd502169b0eacf5ca5146b1ec1), under the GNU GPL version 2 or
later (LICENSE). AtlasOS ships it as the "Modern" app launcher, changed as
follows (October 2026):

- contents/config/main.xml: the AtlasOS icon by default; the indicator
  colour follows the accent colour unless one is set; the shell, bookmarks
  and locations search plugins; the system font by default; and the
  `favoriteApps` and `favoritesPortedToKAstats` entries main.qml reads but
  the schema lacked, with AtlasOS's apps as the favourites.
- contents/ui/CompactRepresentation.qml and config/ConfigGeneral.qml: an
  unset indicator colour uses the accent colour.
- contents/ui/MainView.qml and UserAvatar.qml: the first glow and avatar
  presets in AtlasOS's violets (#6252DD, #9C8CF8, #C3B8FF); the settings
  page names it "AtlasOS violet".
- Removed: README.md, images/, kpac and translate/ (not used when
  installed).
