#!/usr/bin/env python3
"""Writes the AtlasOS Plasma style's SVGs: the dock's task frames
(widgets/tasks.svg), the panel background of the dock and menu bar
(widgets/, translucent/, opaque/ and solid/ panel-background.svg) and the
app launcher's popup (solid/dialogs/background.svg), into
system_files/usr/share/plasma/desktoptheme/atlasos/.

    scripts/plasma-style.py

Every element is a nine-part frame Plasma stretches to size. Each frame is
drawn at the size the dock actually uses (DOCK_HEIGHT in the layout script),
so at the default size nothing is stretched and the underline is exactly
UNDERLINE_W wide; it grows with a taller dock. Colours come from the colour
scheme (AtlasOS Light or Dark) through Plasma's ColorScheme-* classes.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "system_files/usr/share/plasma/desktoptheme/atlasos"

# The dock: 60 px tall (the layout script's dock.height). Plasma gives the
# task manager the panel's whole height, and makes each icon-only task as
# wide as it is tall plus the left and right margins: so 60 x 60 tasks, a
# 48 px icon (a standard size, so Plasma doesn't round it down), 4 px above
# it and the underline in the 8 px below.
# Plasma pads a panel's contents by the "thick" frame's margins plus 4 px
# (Kirigami's smallSpacing), so those margins are 0. A panel can't be
# thinner than its frame's top and bottom edges, so the corners' radius
# keeps them within the menu bar's 28 px.
PANEL_MARGIN = 4
PANEL_RADIUS = 13
ICON = 48
TASK_MARGIN = {"top": 4, "bottom": 8, "left": 0, "right": 0}
TASK_H = ICON + TASK_MARGIN["top"] + TASK_MARGIN["bottom"]  # 60
TASK_W = TASK_H + TASK_MARGIN["left"] + TASK_MARGIN["right"]  # 60
TILE_INSET = 2
TILE_RADIUS = 10
# The launcher's popup: the dock's curve, Breeze's 4 px margins (the
# launcher's layout counts on them) and a soft shadow SHADOW px wide.
DIALOG_MARGIN = 4
SHADOW = 10
UNDERLINE_W = 10
UNDERLINE_H = 2

HEADER = """<?xml version="1.0" encoding="UTF-8"?>
<!--
  {what}
  Made by scripts/plasma-style.py; change that and run it again rather than
  editing this file.
  SPDX-License-Identifier: Apache-2.0
-->
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" version="1.1">
 <defs>
  <style id="current-color-scheme" type="text/css">
   .ColorScheme-Text {{ color:#1b1748; }} .ColorScheme-Background {{ color:#f3f2fa; }}
   .ColorScheme-Highlight {{ color:#6858e2; }} .ColorScheme-NegativeText {{ color:#da4453; }}
  </style>
 </defs>
"""

# An all-but-invisible rectangle gives each piece its full bounds, so
# Plasma cuts the pieces where intended even where nothing is drawn.
BOUNDS = '<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#000" opacity="0.004"/>'


def piece_path(rect, r, region, piece):
    """The part of a rounded rectangle inside one piece of a frame, as path
    data. The corners' arcs must lie inside the corner pieces."""
    x, y, w, h = rect
    (x0, y0, x1, y1) = region
    left, top, right, bottom = x, y, x + w, y + h
    t = max(top, y0)
    b = min(bottom, y1)
    lft = max(left, x0)
    rgt = min(right, x1)
    if t >= b or lft >= rgt:
        return ""
    if (left, top, right, bottom) == (lft, t, rgt, b):  # wholly inside: draw it all
        return (f"M{left + r} {top} H{right - r} A{r} {r} 0 0 1 {right} {top + r} "
                f"V{bottom - r} A{r} {r} 0 0 1 {right - r} {bottom} H{left + r} "
                f"A{r} {r} 0 0 1 {left} {bottom - r} V{top + r} A{r} {r} 0 0 1 {left + r} {top} Z")
    if piece == "topleft":
        return (f"M{left} {b} V{top + r} A{r} {r} 0 0 1 {left + r} {top} "
                f"H{rgt} V{b} Z")
    if piece == "topright":
        return (f"M{lft} {top} H{right - r} A{r} {r} 0 0 1 {right} {top + r} "
                f"V{b} H{lft} Z")
    if piece == "bottomleft":
        return (f"M{left} {t} V{bottom - r} A{r} {r} 0 0 0 {left + r} {bottom} "
                f"H{rgt} V{t} Z")
    if piece == "bottomright":
        return (f"M{lft} {t} V{bottom} H{right - r} A{r} {r} 0 0 0 {right} {bottom - r} "
                f"V{t} Z")
    return f"M{lft} {t} H{rgt} V{b} H{lft} Z"


class Shape:
    """A rounded rectangle filled with a colour-scheme colour; ring=True
    draws only its 1 px edge."""

    def __init__(self, rect, r, cls, opacity, ring=False):
        self.rect, self.r, self.cls, self.opacity, self.ring = rect, r, cls, opacity, ring

    def svg(self, region, piece):
        d = piece_path(self.rect, self.r, region, piece)
        if not d:
            return ""
        rule = ""
        if self.ring:
            x, y, w, h = self.rect
            d += " " + piece_path((x + 1, y + 1, w - 2, h - 2), self.r - 1, region, piece)
            rule = ' fill-rule="evenodd"'
        return (f'<path d="{d}" class="{self.cls}" fill="currentColor"'
                f'{rule} opacity="{self.opacity}"/>')


def frame(prefix, size, borders, shapes, hints, bounds=True):
    """A nine-part frame: each piece draws its part of the shapes.
    borders = (left, top, right, bottom); hints = {name: value}. bounds=False
    leaves out the near-invisible rectangles that fix each piece's size:
    a blur mask counts any pixel that isn't fully transparent."""
    w, h = size
    left, top, right, bottom = borders
    xs = {"left": (0, left), "": (left, w - right), "right": (w - right, w)}
    ys = {"top": (0, top), "": (top, h - bottom), "bottom": (h - bottom, h)}
    out = []
    name_prefix = f"{prefix}-" if prefix else ""
    for vy, (y0, y1) in ys.items():
        for hx, (x0, x1) in xs.items():
            piece = (vy + hx) or "center"
            out.append(f' <g id="{name_prefix}{piece}">')
            if bounds:
                out.append("  " + BOUNDS.format(x=x0, y=y0, w=x1 - x0, h=y1 - y0))
            for shape in shapes:
                part = shape.svg((x0, y0, x1, y1), piece)
                if part:
                    out.append("  " + part)
            out.append(" </g>")
    for hint, value in hints.items():
        if hint == "stretch-borders":
            out.append(f' <rect id="{name_prefix}hint-stretch-borders" width="1" height="1" fill="#000" opacity="0.004"/>')
        else:  # a margin: its height (top/bottom) or width (left/right)
            vertical = hint.split("-")[0] in ("top", "bottom")
            value = value or 1e-08  # an empty rectangle would count as missing
            out.append(f' <rect id="{name_prefix}hint-{hint}" x="0" y="0" '
                       f'width="{1 if vertical else value}" height="{value if vertical else 1}" fill="#000" opacity="0.004"/>')
    return out


def tasks():
    """Task frames. A tile covering the whole task (hover, the active window)
    and a short centred underline under running apps: the accent colour for
    the active window, the text colour (faded) for the others, red for one
    asking for attention. Launchers that aren't running only get the tile on
    hover. Plasma asks for <state>-hover, then hover, then <state>; the
    task frame's margins come from the "normal" frame."""
    w, h = TASK_W, TASK_H
    i = TILE_INSET
    tile_bottom = h - TASK_MARGIN["bottom"] + i  # just past the icon's foot
    line_y = tile_bottom + 1  # under the tile, 3 px above the edge
    # Each corner's arc stays inside its unstretched corner piece.
    side = i + TILE_RADIUS + 1
    borders = (side, side, side, h - tile_bottom + TILE_RADIUS + 1)

    def tile(cls, opacity):
        return Shape((i, i, w - 2 * i, tile_bottom - i), TILE_RADIUS, cls, opacity)

    def line(cls, opacity):
        # Whole inside the bottom edge's middle, so only that piece draws it.
        return Shape(((w - UNDERLINE_W) / 2, line_y, UNDERLINE_W, UNDERLINE_H),
                     UNDERLINE_H / 2, cls, opacity)

    text, accent, red = "ColorScheme-Text", "ColorScheme-Highlight", "ColorScheme-NegativeText"
    states = {
        "normal": [line(text, 0.45)],
        "normal-hover": [tile(text, 0.10), line(text, 0.45)],
        "hover": [tile(text, 0.10), line(text, 0.45)],
        "launcher-hover": [tile(text, 0.10)],
        "focus": [tile(text, 0.08), line(accent, 1)],
        "focus-hover": [tile(text, 0.14), line(accent, 1)],
        "minimized": [line(text, 0.25)],
        "minimized-hover": [tile(text, 0.10), line(text, 0.25)],
        "attention": [tile(red, 0.15), line(red, 1)],
        "attention-hover": [tile(red, 0.22), line(red, 1)],
        "progress": [tile(accent, 0.22)],
    }
    hints = {"stretch-borders": 1, "top-margin": TASK_MARGIN["top"],
             "bottom-margin": TASK_MARGIN["bottom"], "left-margin": TASK_MARGIN["left"],
             "right-margin": TASK_MARGIN["right"]}
    body = []
    for prefix, shapes in states.items():
        body += frame(prefix, (w, h), borders, shapes, hints)
    return HEADER.format(what="AtlasOS's task frames for the dock (Plasma's widgets/tasks).",
                         w=w, h=h) + "\n".join(body) + "\n</svg>\n"


def panel(opacity, what):
    """The dock's and menu bar's background: a rounded, see-through plate
    with a hairline edge, which KWin blurs behind (the "mask" frame is the
    area it blurs). On the menu bar, which touches the screen's edges, only
    the bottom edge shows."""
    size = 2 * (PANEL_RADIUS + 1) + 8
    r = PANEL_RADIUS
    b = r + 1
    plate = [Shape((0, 0, size, size), r, "ColorScheme-Background", opacity),
             Shape((0, 0, size, size), r, "ColorScheme-Text", 0.12, ring=True)]
    hints = {"stretch-borders": 1, "top-margin": PANEL_MARGIN, "bottom-margin": PANEL_MARGIN,
             "left-margin": PANEL_MARGIN, "right-margin": PANEL_MARGIN}
    body = frame("", (size, size), (b, b, b, b), plate, hints)
    body += frame("mask", (size, size), (b, b, b, b),
                  [Shape((0, 0, size, size), r, "ColorScheme-Text", 1)], {}, bounds=False)
    body += frame("thick", (size, size), (b, b, b, b), plate,
                  {"top-margin": 0, "bottom-margin": 0, "left-margin": 0, "right-margin": 0})
    return HEADER.format(what=what, w=size, h=size) + "\n".join(body) + "\n</svg>\n"


def dialog():
    """The app launcher's popup, which asks for Plasma's solid dialog
    background so that no other popup changes: an opaque plate with the
    dock's corners and hairline edge, and a shadow KWin draws around it,
    fading over SHADOW px. Its rings are drawn 1 px apart (no SVG filters:
    KSvg doesn't run them), and none lies under the plate, so the corners
    stay clear."""
    r = PANEL_RADIUS
    b = r + 1
    size = 2 * b + 8
    plate = [Shape((0, 0, size, size), r, "ColorScheme-Background", 1),
             Shape((0, 0, size, size), r, "ColorScheme-Text", 0.12, ring=True)]
    margins = {f"{side}-margin": DIALOG_MARGIN for side in ("top", "bottom", "left", "right")}
    insets = {f"{side}-inset": 0 for side in ("top", "bottom", "left", "right")}
    body = frame("", (size, size), (b, b, b, b), plate, {**margins, **insets})
    body += frame("mask", (size, size), (b, b, b, b),
                  [Shape((0, 0, size, size), r, "ColorScheme-Text", 1)], {}, bounds=False)
    # The shadow: its pieces reach SHADOW px out from the plate and the
    # plate's corner (b px) in, where KWin lays them under the window.
    s = SHADOW
    ssize = 2 * (s + b) + 8
    rings = [Shape((s - k - 1, s - k - 1, ssize - 2 * (s - k - 1), ssize - 2 * (s - k - 1)),
                   r + k + 1, "", round(0.16 * (1 - (k + 0.5) / s) ** 2, 4), ring=True)
             for k in range(s)]
    body += frame("shadow", (ssize, ssize), (s + b,) * 4, rings,
                  {f"{side}-{kind}": s for side in ("top", "bottom", "left", "right")
                   for kind in ("margin", "inset")})
    # The shadow is black whatever the colours (its rings have no class).
    body = "\n".join(body).replace('class="" fill="currentColor"', 'fill="#000"')
    return (HEADER.format(what="The app launcher's popup (Plasma's solid dialog background).",
                          w=ssize, h=ssize) + body + "\n</svg>\n")


def main():
    files = {
        "widgets/tasks.svg": tasks(),
        # Plasma picks the folder by the panel's opacity setting: translucent
        # (AtlasOS's dock and menu bar), adaptive (opaque only while a window
        # is maximized), opaque, and solid without compositing.
        "translucent/widgets/panel-background.svg": panel(0.55, "Panel background, translucent."),
        "widgets/panel-background.svg": panel(0.55, "Panel background, adaptive (see-through until a window is maximized)."),
        "opaque/widgets/panel-background.svg": panel(1, "Panel background, opaque."),
        "solid/widgets/panel-background.svg": panel(1, "Panel background, without compositing."),
        # Only popups that ask for a solid background use this, which in
        # AtlasOS is the app launcher's; every other popup stays Breeze's.
        "solid/dialogs/background.svg": dialog(),
    }
    for rel, text in files.items():
        path = OUT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path.relative_to(ROOT))


main()
