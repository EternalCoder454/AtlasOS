# Icon theme

[Dracula Icons](https://github.com/m4thewz/dracula-icons) by Matheus Vitor,
at commit `de2a8edd94608ba0ac4dcf5a187af0ffaa511ebc` (2025-08-02), GPL-3.0
(its README says so, and its icons are recoloured from
[Tela-circle](https://github.com/vinceliuice/Tela-circle-icon-theme) and
[Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme), both
GPL-3.0; the repository itself has no license file, so `LICENSE` here is the
GPL-3.0 text, installed as `/usr/share/licenses/dracula-icons/LICENSE`).
Fedora doesn't package it.

`Dracula.tar.xz` is the repository at that commit without `.git`, its
README and its preview picture, as `Dracula/`. `build.sh` unpacks it into
`/usr/share/icons` and points its fallbacks at Breeze Dark and hicolor (its
own list names themes Fedora doesn't have).

One theme serves AtlasOS Light and Dark: most of its small action and panel
icons use KDE's colour-scheme stylesheet, so Plasma draws them in the theme's
text colour. Its symbolic icons, and the rest of the one-colour small ones,
are drawn in Dracula's near-white (#f8f8f2) written into each file, which
disappeared on AtlasOS Light (Discover's categories, for one).
`build_files/icon-recolor.py` rewrites those at build time to use the
stylesheet too, keeping #f8f8f2 as the default colour. Breeze stays
installed underneath for the icons Dracula doesn't have.
