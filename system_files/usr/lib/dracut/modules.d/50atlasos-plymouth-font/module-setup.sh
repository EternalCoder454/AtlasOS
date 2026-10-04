#!/usr/bin/bash
# Plymouth's text (the update progress, a disk password prompt) is drawn by
# its label-freetype plugin, which ignores the theme's Font= and loads only
# /usr/share/fonts/Plymouth.ttf. plymouth-populate-initrd links that to
# whatever a bare `fc-match` returns (Noto Sans), so this module, run after
# the plymouth module, points it at IBM Plex Sans instead.

check() {
    return 255 # only when asked for (dracut.conf.d/50-atlasos-plymouth.conf)
}

depends() {
    echo plymouth
}

# shellcheck disable=SC2154 # initdir is dracut's
install() {
    local font=/usr/share/fonts/ibm-plex-sans-fonts/IBMPlexSans-Regular.otf
    inst_simple "$font" || return 1
    rm -f "${initdir}/usr/share/fonts/Plymouth.ttf"
    ln -s "$font" "${initdir}/usr/share/fonts/Plymouth.ttf"
}
