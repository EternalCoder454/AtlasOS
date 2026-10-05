#!/usr/bin/env python3
"""Writes the AtlasOS Plasma style's SVGs into
system_files/usr/share/plasma/desktoptheme/atlasos/: the dock's task frames,
the panel background of the dock and menu bar, popups (dialogs/background),
tooltips, desktop widget backgrounds, and the controls Plasma's own
components draw from the theme (buttons, tool buttons, text fields, sliders,
switches, check and radio marks, scrollbars, tabs, list and view items,
frames, progress bars, headings), so every shell surface looks like the
Atlas apps (Atlas.Ui) instead of Breeze. Each element keeps the ids of
Breeze's counterpart (Plasma looks them up by name); only the drawing is ours.

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
# Popups (the app launcher's too): a DIALOG_R card, Breeze's 4 px margins
# (the launcher's layout counts on them) and a soft shadow SHADOW px wide.
# The sizes below match scripts/gen-kvantum-themes.py and Atlas.Ui.
DIALOG_R = 8  # radiusLarge
DIALOG_MARGIN = 4
SHADOW = 10
TOOLTIP_R = 6
DIALOG_ALPHA = 0.78  # see-through, so KWin's blur shows behind it
FIELD_R = 4  # radiusSmall
CARD_R = 6  # radius
ITEM_R = 4  # list and view items, tool buttons (radiusSmall)
TAB_R = 6  # the selected tab, like the segmented control's cell (radius)
BTN_R = 4  # buttons: radiusSmall, growing to BTN_PRESSED_R while pressed
BTN_PRESSED_R = 6
SLIDER_GROOVE = 6
SLIDER_HANDLE = 18
SCROLL_W = 10  # the scrollbar's track; the thumb is SCROLL_W - 2 * SCROLL_PAD
SCROLL_PAD = 2
SWITCH_BAR = (40, 18)
SWITCH_HANDLE = 24
CHECK = 16
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
   .ColorScheme-HighlightedText {{ color:#ffffff; }} .ColorScheme-ViewBackground {{ color:#ffffff; }}
   .ColorScheme-ButtonBackground {{ color:#e6e4f4; }} .ColorScheme-ButtonText {{ color:#1b1748; }}
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
    if piece == "left" and t == top and b == bottom:
        return (f"M{rgt} {top} H{left + r} A{r} {r} 0 0 0 {left} {top + r} "
                f"V{bottom - r} A{r} {r} 0 0 0 {left + r} {bottom} H{rgt} Z")
    if piece == "right" and t == top and b == bottom:
        return (f"M{lft} {top} H{right - r} A{r} {r} 0 0 1 {right} {top + r} "
                f"V{bottom - r} A{r} {r} 0 0 1 {right - r} {bottom} H{lft} Z")
    return f"M{lft} {t} H{rgt} V{b} H{lft} Z"


class Shape:
    """A rounded rectangle filled with a colour-scheme colour; ring=N draws
    only its N px edge (True is 1)."""

    def __init__(self, rect, r, cls, opacity, ring=False):
        self.rect, self.r, self.cls, self.opacity, self.ring = rect, r, cls, opacity, ring

    def svg(self, region, piece):
        d = piece_path(self.rect, self.r, region, piece)
        if not d:
            return ""
        rule = ""
        if self.ring:
            x, y, w, h = self.rect
            n = int(self.ring)
            d += " " + piece_path((x + n, y + n, w - 2 * n, h - 2 * n), max(self.r - n, 0), region, piece)
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
            if x1 <= x0 or y1 <= y0:  # a frame without top and bottom edges
                continue
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
        out.append(hint_el(name_prefix, hint, value))
    return out


def hint_el(name_prefix, hint, value):
    """One of Plasma's hint rectangles: stretch-borders, or a margin or
    inset, whose height (top/bottom) or width (left/right) is its value."""
    if hint == "stretch-borders":
        return f' <rect id="{name_prefix}hint-stretch-borders" width="1" height="1" fill="#000" opacity="0.004"/>'
    vertical = hint.split("-")[0] in ("top", "bottom")
    value = value or 1e-08  # an empty rectangle would count as missing
    return (f' <rect id="{name_prefix}hint-{hint}" x="0" y="0" '
            f'width="{1 if vertical else value}" height="{value if vertical else 1}" fill="#000" opacity="0.004"/>')


SIDES = ("top", "bottom", "left", "right")


def margins(top, bottom=None, left=None, right=None):
    """Margin hints: margins(6) is 6 all round, margins(5, left=12) 5 above
    and below and 12 at the sides."""
    bottom = top if bottom is None else bottom
    left = top if left is None else left
    right = left if right is None else right
    return {f"{side}-margin": v for side, v in zip(SIDES, (top, bottom, left, right))}


def insets(n):
    return {f"{side}-inset": n for side in SIDES}


def card(prefix, r, layers, hints=None, bounds=True, extra=8):
    """A rounded frame r px in the corners (so r + 1 px borders), drawn as
    layers: (colour class, opacity[, ring width[, inset]]), each a rounded
    rectangle filling the frame (less its inset); a ring width draws only
    that edge. The frame is extra px bigger than its corners need."""
    b = r + 1
    size = 2 * b + extra
    shapes = []
    for layer in layers:
        cls, opacity, ring, inset = (tuple(layer) + (0, 0))[:4]
        shapes.append(Shape((inset, inset, size - 2 * inset, size - 2 * inset),
                            max(r - inset, 0), cls, opacity, ring=ring))
    return size, frame(prefix, (size, size), (b, b, b, b), shapes, hints or {}, bounds)


def svg_of(what, size, body):
    return HEADER.format(what=what, w=size, h=size) + "\n".join(body) + "\n</svg>\n"


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


def popup(what, r, alpha, margin, shadow, blurred=False):
    """A popup's or tooltip's background, which asks for Plasma's dialog
    background: a card with the dock's hairline edge, and a shadow KWin draws
    around it, fading over `shadow` px, and the "mask" frame KWin blurs
    behind it (so the blur follows the rounded shape). The shadow's rings are
    drawn 1 px apart (no SVG filters: KSvg doesn't run them), and none lies
    under the card, so the corners stay clear."""
    plate = [("ColorScheme-Background", alpha), ("ColorScheme-Text", 0.12, 1)]
    size, body = card("", r, plate, {**margins(margin), **insets(0)})
    body += card("mask", r, [("ColorScheme-Text", 1)], bounds=False)[1]
    if blurred:  # the prefix of desktop widgets whose background is blurred
        body += card("blurred", r, plate, {**margins(margin), **insets(0)})[1]
        body += card("blurred-mask", r, [("ColorScheme-Text", 1)], bounds=False)[1]
    b = r + 1
    s = shadow
    ssize = 2 * (s + b) + 8
    rings = [Shape((s - k - 1, s - k - 1, ssize - 2 * (s - k - 1), ssize - 2 * (s - k - 1)),
                   r + k + 1, "", round(0.16 * (1 - (k + 0.5) / s) ** 2, 4), ring=True)
             for k in range(s)]
    body += frame("shadow", (ssize, ssize), (s + b,) * 4, rings,
                  {f"{side}-{kind}": s for side in SIDES for kind in ("margin", "inset")})
    # The shadow is black whatever the colours (its rings have no class).
    body = "\n".join(body).replace('class="" fill="currentColor"', 'fill="#000"')
    return HEADER.format(what=what, w=ssize, h=ssize) + body + "\n</svg>\n"


def dialog(alpha, what):
    return popup(what, DIALOG_R, alpha, DIALOG_MARGIN, SHADOW)


def tooltip(alpha, what):
    return popup(what, TOOLTIP_R, alpha, 4, 6)


def background(alpha, what):
    """A desktop widget's background: the popup's card."""
    return popup(what, DIALOG_R, alpha, 8, SHADOW, blurred=True)


# Elements that aren't frames: a circle's path (filled, or as a ring).
def disc(cx, cy, r):
    return f"M{cx - r} {cy} a{r} {r} 0 1 0 {2 * r} 0 a{r} {r} 0 1 0 {-2 * r} 0Z"


def disc_path(cls, opacity, cx, cy, r, ring=0):
    d = disc(cx, cy, r)
    rule = ""
    if ring:
        d += " " + disc(cx, cy, r - ring)
        rule = ' fill-rule="evenodd"'
    klass = f' class="{cls}"' if cls else ""
    colour = "currentColor" if cls else "#000"
    return f'<path d="{d}"{klass} fill="{colour}"{rule} opacity="{opacity}"/>'


def element(eid, cx, cy, box, *parts):
    """A named element box x box centred on (cx, cy) holding parts. The
    near-invisible rectangle gives it its size."""
    return "\n".join([f' <g id="{eid}">',
                      "  " + BOUNDS.format(x=cx - box / 2, y=cy - box / 2, w=box, h=box),
                      *("  " + p for p in parts), " </g>"])


def rect_el(eid, x, y, w, h):
    return f' <rect id="{eid}" x="{x}" y="{y}" width="{w}" height="{h}" fill="#000" opacity="0.004"/>'


def handle_set(cx, cy, box, r, face, ring):
    """The pieces of a round handle (slider and switch): the face, the soft
    shadow around it, a pointer-over tint and the keyboard-focus ring. The
    faces are ViewBackground with a hairline; the accent shows through the
    focus ring and the hover tint. Returns (face, shadow, hover, pressed,
    focus) parts, to be wrapped by the caller with ids."""
    shadow = [disc_path("", round(0.035, 4), cx, cy + 1, r + k) for k in range(1, 6)]
    return (face, shadow,
            [disc_path("ColorScheme-Highlight", 0.18, cx, cy, r)],
            [disc_path("ColorScheme-Highlight", 0.32, cx, cy, r)],
            [disc_path("ColorScheme-Highlight", 0.55, cx, cy, r + 3, ring=2)])


def slider():
    r = SLIDER_HANDLE // 2
    box = 30
    body = []
    for orient, row in (("horizontal", 0), ("vertical", 1)):
        cx, cy = box / 2, box / 2 + row * box
        face = [disc_path("ColorScheme-ViewBackground", 1, cx, cy, r),
                disc_path("ColorScheme-Text", 0.22, cx, cy, r, ring=1)]
        face, shadow, hover, _, focus = handle_set(cx, cy, box, r, face, 1)
        body += [element(f"{orient}-slider-handle", cx, cy, SLIDER_HANDLE, *face),
                 element(f"{orient}-slider-shadow", cx, cy, box, *shadow),
                 element(f"{orient}-slider-hover", cx, cy, SLIDER_HANDLE, *hover),
                 element(f"{orient}-slider-focus", cx, cy, SLIDER_HANDLE + 6, *focus)]
    body.append(rect_el("hint-handle-size", box, 0, SLIDER_HANDLE, SLIDER_HANDLE))
    g = SLIDER_GROOVE // 2
    for prefix, cls, op in (("groove", "ColorScheme-Text", 0.16),
                            ("groove-highlight", "ColorScheme-Highlight", 1)):
        # A pill SLIDER_GROOVE high: its corners are the whole of its
        # height, so its middle row is empty.
        shape = Shape((0, 0, 3 * g, 3 * g), g, cls, op)
        body += frame(prefix, (3 * g, 3 * g), (g, g, g, g), [shape], {})
    return HEADER.format(what="Sliders: the groove, its accent fill and the round handle.",
                         w=2 * box, h=2 * box) + "\n".join(body) + "\n</svg>\n"


def switch():
    bw, bh = SWITCH_BAR
    r = bh // 2
    hr = SWITCH_HANDLE // 2
    body = [rect_el("hint-bar-size", 0, 0, bw, bh)]
    for prefix, cls, op in (("inactive", "ColorScheme-Text", 0.2),
                            ("active", "ColorScheme-Highlight", 1)):
        shapes = [Shape((0, 0, bw, bh), r, cls, op)]
        body += frame(prefix, (bw, bh), (r, 0, r, 0), shapes, {})
    body.append(hint_el("", "stretch-borders", 1))
    cx, cy = SWITCH_HANDLE, SWITCH_HANDLE
    face = [disc_path("ColorScheme-ViewBackground", 1, cx, cy, hr),
            disc_path("ColorScheme-Text", 0.22, cx, cy, hr, ring=1)]
    face, shadow, hover, pressed, focus = handle_set(cx, cy, 2 * hr, hr, face, 1)
    body += [element("handle", cx, cy, 2 * hr, *face),
             element("handle-shadow", cx, cy, 2 * hr + 12, *shadow),
             element("handle-hover", cx, cy, 2 * hr, *face, *hover),
             element("handle-pressed", cx, cy, 2 * hr, *face, *pressed),
             element("handle-focus", cx, cy, 2 * hr + 6, *focus)]
    return HEADER.format(what="Switches: a pill bar that fills with the accent, and a round handle.",
                         w=2 * SWITCH_HANDLE + 12, h=2 * SWITCH_HANDLE + 12) + "\n".join(body) + "\n</svg>\n"


def radiobutton():
    n = CHECK + 2
    cx = cy = n / 2 + 4
    ring = [disc_path("ColorScheme-Text", 0.35, cx, cy, n / 2, ring=1)]
    body = [rect_el("hint-size", 0, 0, n, n),
            element("normal", cx, cy, n, disc_path("ColorScheme-Text", 0.08, cx, cy, n / 2), *ring),
            element("shadow", cx, cy, n, ""),
            element("checked", cx, cy, n, disc_path("ColorScheme-Highlight", 1, cx, cy, n / 2)),
            element("symbol", cx, cy, n, disc_path("ColorScheme-HighlightedText", 1, cx, cy, n / 6)),
            element("hover", cx, cy, n, disc_path("ColorScheme-Highlight", 0.2, cx, cy, n / 2)),
            element("focus", cx, cy, n, disc_path("ColorScheme-Highlight", 0.8, cx, cy, n / 2, ring=2))]
    return HEADER.format(what="Radio buttons.", w=n + 8, h=n + 8) + "\n".join(body) + "\n</svg>\n"


def checkmarks():
    """The mark Plasma draws over a check box (which has the button's frame
    behind it, a pill: so the mark fills a disc) and a radio button."""
    n = CHECK
    tick = (f'<path d="M{n * 0.28} {n * 0.52} L{n * 0.44} {n * 0.68} L{n * 0.74} {n * 0.34}" '
            f'class="ColorScheme-HighlightedText" fill="none" stroke="currentColor" '
            f'stroke-width="{n / 9:.2f}" stroke-linecap="round" stroke-linejoin="round"/>')
    body = [element("checkbox", n / 2, n / 2, n, disc_path("ColorScheme-Highlight", 1, n / 2, n / 2, n / 2), tick),
            element("radiobutton", n / 2, n + n / 2, n,
                    disc_path("ColorScheme-Highlight", 1, n / 2, n + n / 2, n / 2),
                    disc_path("ColorScheme-HighlightedText", 1, n / 2, n + n / 2, n / 6))]
    return HEADER.format(what="Check box and radio button marks.", w=n, h=2 * n) + "\n".join(body) + "\n</svg>\n"


def button():
    """Buttons: Plasma draws "normal", then the pointer-over, keyboard-focus
    and pressed frames on top. Raised buttons are Atlas.Ui's: the control
    fill, a hairline border and a grey hover and press overlay; flat (tool) buttons only show a rounded tile on hover or press."""
    hl, text = "ColorScheme-Highlight", "ColorScheme-Text"
    m = margins(5, left=12)
    body = []
    body += card("normal", BTN_R, [(text, 0.055), (text, 0.22, 1)], m)[1]
    body += card("mask-normal", BTN_R, [(text, 1)], bounds=False)[1]
    body += card("hover", BTN_R, [(text, 0.055)], margins(0))[1]
    body += card("pressed", BTN_PRESSED_R, [(text, 0.10)], m)[1]
    # The focus ring sits 2 px outside the button.
    body += card("focus", BTN_R + 2, [(hl, 0.9, 2)], margins(2))[1]
    body += card("shadow", BTN_R, [], margins(0))[1]
    body += card("toolbutton-hover", ITEM_R, [(text, 0.10)], margins(4))[1]
    body += card("toolbutton-pressed", ITEM_R, [(text, 0.16)], margins(4))[1]
    body += card("toolbutton-focus", ITEM_R + 2, [(hl, 0.9, 2)], margins(2))[1]
    return HEADER.format(what="Buttons.", w=2 * BTN_PRESSED_R + 10, h=2 * BTN_PRESSED_R + 10) + "\n".join(body) + "\n</svg>\n"


def lineedit():
    view, text, hl = "ColorScheme-ViewBackground", "ColorScheme-Text", "ColorScheme-Highlight"
    body = [rect_el("hint-focus-over-base", 0, 0, 2, 2)]
    body += card("base", FIELD_R, [(view, 1), (text, 0.22, 1)], margins(5, left=8))[1]
    body += card("hover", FIELD_R, [(text, 0.4, 1)], margins(0))[1]
    for prefix in ("focus", "focusframe"):
        body += card(prefix, FIELD_R, [(hl, 1, 2)], margins(0))[1]
    return HEADER.format(what="Text fields.", w=2 * FIELD_R + 10, h=2 * FIELD_R + 10) + "\n".join(body) + "\n</svg>\n"


def scrollbar():
    """A thin rounded thumb (SCROLL_W - 2 * SCROLL_PAD wide) in a track that
    only shows, faintly, under the pointer."""
    text = "ColorScheme-Text"
    body = [rect_el("hint-scrollbar-size", 0, 0, SCROLL_W, SCROLL_W)]
    r = SCROLL_W // 2 - 1  # (r + 1) * 2 = SCROLL_W: the corners fill the track
    for orient in ("horizontal", "vertical"):
        body += card(f"background-{orient}", r, [(text, 0.07)], {}, extra=2)[1]
    n = SCROLL_W - 2 * SCROLL_PAD
    for prefix, op in (("slider", 0.32), ("mouseover-slider", 0.55)):
        shape = Shape((0, 0, 3 * (n // 2), 3 * (n // 2)), n // 2, text, op)
        body += frame(prefix, (3 * (n // 2),) * 2, (n // 2,) * 4, [shape], insets(SCROLL_PAD))
    return HEADER.format(what="Scrollbars.", w=2 * SCROLL_W, h=2 * SCROLL_W) + "\n".join(body) + "\n</svg>\n"


def tabbar():
    """The selected tab: a rounded tile tinted with the accent, whichever
    edge the bar is on, and no underline."""
    body = []
    for side in ("north", "south", "east", "west"):
        body += card(f"{side}-active-tab", TAB_R, [("ColorScheme-Highlight", 0.22)],
                     margins(4, left=10))[1]
    return HEADER.format(what="Tab bars.", w=2 * TAB_R + 10, h=2 * TAB_R + 10) + "\n".join(body) + "\n</svg>\n"


def viewitem():
    hl = "ColorScheme-Highlight"
    body = []
    for prefix, layers in (("normal", []), ("hover", [(hl, 0.14)]), ("selected", [(hl, 0.28)]),
                           ("selected+hover", [(hl, 0.36)])):
        body += card(prefix, ITEM_R, layers, margins(4))[1]
    return HEADER.format(what="Items of icon and list views.", w=2 * ITEM_R + 10, h=2 * ITEM_R + 10) + "\n".join(body) + "\n</svg>\n"


def listitem():
    hl, text = "ColorScheme-Highlight", "ColorScheme-Text"
    body = []
    for prefix, layers in (("normal", []), ("hover", [(hl, 0.12)]), ("pressed", [(hl, 0.26)]),
                           ("section", [])):
        body += card(prefix, ITEM_R, layers, margins(6))[1]
    n = 2 * ITEM_R + 10  # the canvas: the separator is scaled to the row's width
    body.append(f' <rect id="separator" x="0" y="{n - 2}" width="{n}" height="1" class="{text}" fill="currentColor" opacity="0.12"/>')
    return HEADER.format(what="Rows of lists: rounded tint on hover and press.", w=2 * ITEM_R + 10, h=2 * ITEM_R + 10) + "\n".join(body) + "\n</svg>\n"


def plasmoidheading():
    """Flat: the heading and footer of a popup draw nothing of their own."""
    body = []
    for prefix in ("header", "footer"):
        body += frame(prefix, (3, 3), (1, 1, 1, 1), [], {})
    body.append(hint_el("", "stretch-borders", 1))
    body += [hint_el("", k, v) for k, v in margins(6).items()]
    return HEADER.format(what="Popup headings and footers (flat).", w=3, h=3) + "\n".join(body) + "\n</svg>\n"


def frames():
    """Frames and group boxes: rounded cards (CARD_R)."""
    text = "ColorScheme-Text"
    body = []
    for prefix, layers in (("plain", [(text, 0.14, 1)]),
                           ("raised", [(text, 0.05), (text, 0.10, 1)]),
                           ("sunken", [(text, 0.07)])):
        body += card(prefix, CARD_R, layers, margins(6))[1]
    return HEADER.format(what="Frames.", w=2 * CARD_R + 10, h=2 * CARD_R + 10) + "\n".join(body) + "\n</svg>\n"


def toolbar():
    return svg_of("Tool bars (flat).", 2 * ITEM_R + 10, card("", ITEM_R, [], margins(4))[1])


def bar_meter():
    """Progress bars: a pill groove with an accent fill."""
    g = SLIDER_GROOVE // 2
    body = [rect_el("hint-bar-size", 0, 0, SLIDER_GROOVE, SLIDER_GROOVE)]
    for prefix, cls, op in (("bar-inactive", "ColorScheme-Text", 0.16),
                            ("bar-active", "ColorScheme-Highlight", 1)):
        body += frame(prefix, (3 * g, 3 * g), (g, g, g, g), [Shape((0, 0, 3 * g, 3 * g), g, cls, op)], {})
    return HEADER.format(what="Progress bars.", w=3 * g, h=3 * g) + "\n".join(body) + "\n</svg>\n"


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
    }
    # Popups, tooltips and widget backgrounds, in the same four variants.
    for folder, alpha, note in (("", DIALOG_ALPHA, "adaptive"), ("translucent/", DIALOG_ALPHA, "translucent"),
                                ("opaque/", 1, "opaque"), ("solid/", 1, "solid, without compositing")):
        files[f"{folder}dialogs/background.svg"] = dialog(alpha, f"Popups and the app launcher (dialog background, {note}).")
        files[f"{folder}widgets/tooltip.svg"] = tooltip(alpha, f"Tooltips ({note}).")
    for folder, alpha, note in (("", DIALOG_ALPHA, "adaptive"), ("translucent/", DIALOG_ALPHA, "translucent"),
                                ("opaque/", 1, "opaque"), ("solid/", 1, "solid")):
        files[f"{folder}widgets/background.svg"] = background(alpha, f"Desktop widget backgrounds ({note}).")
    files.update({
        "widgets/button.svg": button(),
        "widgets/lineedit.svg": lineedit(),
        "widgets/slider.svg": slider(),
        "widgets/switch.svg": switch(),
        "widgets/checkmarks.svg": checkmarks(),
        "widgets/radiobutton.svg": radiobutton(),
        "widgets/scrollbar.svg": scrollbar(),
        "widgets/tabbar.svg": tabbar(),
        "widgets/viewitem.svg": viewitem(),
        "widgets/listitem.svg": listitem(),
        "widgets/plasmoidheading.svg": plasmoidheading(),
        "widgets/frame.svg": frames(),
        "widgets/toolbar.svg": toolbar(),
        "widgets/bar_meter_horizontal.svg": bar_meter(),
        # The pill is symmetric, so vertical bars use the same tiles.
        "widgets/bar_meter_vertical.svg": bar_meter(),
    })
    for rel, text in files.items():
        path = OUT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path.relative_to(ROOT))


main()
