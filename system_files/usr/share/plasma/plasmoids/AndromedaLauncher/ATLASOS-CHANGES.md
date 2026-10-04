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

Restyled to match the Atlas apps (Atlas.Ui), using only Kirigami theme colours
and units (no hard-coded colours), drawing on the AtlasOS style's dialog frame:

- contents/ui/MainView.qml: a compact user row (small avatar, name, then the
  settings, lock and power buttons) replaces the large floating avatar; the
  search field moved to the top as a pill; the section title is semibold and
  subdued, without the star icon; the "All apps" button is accent-tinted;
  the font family fix (a font object was assigned to a string).
- contents/ui/Header.qml: settings, lock (new; the system model's lock action,
  hidden when absent) and power as small round accent-tinted buttons.
- contents/ui/AtlasSymbol.qml (new): a Material Symbols Rounded glyph
  (atlas-symbols-fonts) drawn as plain text, with a theme icon as fallback
  when the font is missing. Atlas.Ui's Symbol is not used: it needs the Atlas
  apps' startup singletons.
- contents/ui/SearchBar.qml: SearchField's pill, border and focus ring.
- contents/ui/Highlight.qml, GenericItem.qml: an 8 px accent-tinted
  selection/hover as SidebarItem, instead of the style's viewitem frame.
- contents/ui/Greeting.qml, UserAvatar.qml: sized by the layout, semibold
  name; no inner avatar margin.
