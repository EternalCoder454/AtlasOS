#!/usr/bin/env python3
"""Generates AtlasOS's Kvantum themes: the application style for Qt/KDE apps
(Dolphin, System Settings, Discover...), drawn to match the Atlas apps (Atlas
Updater, Atlas Monitor): pill buttons, 10 px cards with a hairline border, soft
accent-tinted selection, thin rounded scrollbars.

Four themes come out, into system_files/usr/share/Kvantum/<name>/:

    AtlasOS            light, translucent (blur behind windows)
    AtlasOSDark        dark, translucent
    AtlasOSSolid       light, opaque
    AtlasOSDarkSolid   dark, opaque

Colours come from the AtlasOS colour schemes (system_files/usr/share/
color-schemes), sizes and the opaque-app list from the constants below. Edit
those, run this script, commit the result:

    python3 scripts/gen-kvantum-themes.py

The SVGs are drawn here, not copied from any Kvantum theme. Every control is a
9-patch: the script draws one master shape per element and state and cuts it
into the tiles Kvantum expects (-topleft, -top, ... and the interior).
"""

import configparser
import math
import pathlib
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMES = ROOT / "system_files/usr/share/color-schemes"
OUT = ROOT / "system_files/usr/share/Kvantum"

# --- Sizes, in logical pixels -------------------------------------------------
PILL_H = 33  # height a pill is drawn for; the text line plus the frame
PILL_CAP = 17  # width of a pill's end cap (about half its height)
FIELD_R = 8  # text fields, spin boxes
CARD_R = 10  # group boxes and cards (Section.qml)
MENU_R = 8
TOOLTIP_R = 6
ITEM_R = 6  # list rows, menu items, tabs
TOOL_R = 6  # tool buttons
SCROLL_W = 10  # scrollbar track; the visible thumb is SCROLL_W - 2 * SCROLL_PAD
SCROLL_PAD = 2
CHECK = 18
SLIDER_GROOVE = 6
SLIDER_HANDLE = 18
WINDOW_OPACITY_REDUCTION = 20  # percent: translucent windows are 80% opaque
MENU_OPACITY_REDUCTION = 8
CARD_ALPHA = 0.94  # Section.qml: cards are nearly opaque on blurred windows
SHADOW = 8
# Splitter handles stay as thin as Breeze's: Dolphin sizes its floating status
# bar as text + one average character + 2 * (2 + 2 * splitter width) but lays
# the text out inside 3 * (2 + 2 * splitter width) of margins, so anything much
# wider than this cuts its text off ("1 f... B)").
SPLITTER_W = 2

# Apps that break or look bad when translucent: they stay opaque in every theme.
# Browsers, video players, image/video editors, office suites, games and
# emulators, terminals, and the Atlas apps (they blur their own windows).
OPAQUE = [
    "atlas-updater", "atlas-monitor", "atlas-notes",
    "brave", "brave-browser", "brave-origin", "firefox", "chromium", "chrome",
    "google-chrome", "librewolf", "falkon", "qutebrowser", "epiphany",
    "vlc", "mpv", "celluloid", "haruna", "smplayer", "dragon", "kaffeine",
    "totem", "obs", "kdenlive", "krita", "gimp", "inkscape", "blender",
    "libreoffice", "soffice", "soffice.bin", "oosplash", "onlyoffice",
    "steam", "lutris", "heroic", "retroarch", "yuzu", "dolphin-emu",
    "ghostty", "konsole", "kitty", "alacritty",
    "plasmashell", "kscreenlocker_greet", "ksplashqml", "spectacle",
    "okular", "gwenview", "virt-manager", "qemu-system-x86_64", "remote-viewer",
]


# --- Colours ------------------------------------------------------------------
def load_scheme(name):
    cp = configparser.RawConfigParser()
    cp.optionxform = str
    cp.read(SCHEMES / f"{name}.colors")

    def c(section, key):
        return tuple(int(v) for v in cp[section][key].split(","))

    return {
        "window": c("Colors:Window", "BackgroundNormal"),
        "window_alt": c("Colors:Window", "BackgroundAlternate"),
        "base": c("Colors:View", "BackgroundNormal"),
        "base_alt": c("Colors:View", "BackgroundAlternate"),
        "button": c("Colors:Button", "BackgroundNormal"),
        "text": c("Colors:Window", "ForegroundNormal"),
        "subtext": c("Colors:Window", "ForegroundInactive"),
        "accent": c("Colors:Selection", "BackgroundNormal"),
        "link": c("Colors:Window", "ForegroundLink"),
        "visited": c("Colors:Window", "ForegroundVisited"),
        "neg": c("Colors:Window", "ForegroundNegative"),
    }


def hx(rgb):
    return "#%02x%02x%02x" % tuple(rgb)


def mix(a, b, t):
    """a over b, t = share of a."""
    return tuple(round(a[i] * t + b[i] * (1 - t)) for i in range(3))


def lighten(rgb, f):
    return tuple(min(255, round(v * f)) for v in rgb)


def darken(rgb, f):
    return tuple(round(v / f) for v in rgb)


class Theme:
    def __init__(self, pal, dark, translucent):
        self.p = pal
        self.dark = dark
        self.translucent = translucent
        p = pal
        self.text = p["text"]
        self.accent = p["accent"]
        self.white = (255, 255, 255)
        # Card colour: Section.qml (lighter in light mode, a 6% white tint in dark).
        if dark:
            self.card = mix(self.white, p["window"], 0.06)
        else:
            self.card = lighten(p["window"], 1.5)
        self.card_alpha = CARD_ALPHA if translucent else 1.0
        self.menu_alpha = 0.96 if translucent else 1.0


# --- SVG building ---------------------------------------------------------------
def rr(x, y, w, h, r):
    r = max(0, min(r, w / 2, h / 2))
    return (
        f"M{x + r:g},{y:g}H{x + w - r:g}A{r:g},{r:g} 0 0 1 {x + w:g},{y + r:g}"
        f"V{y + h - r:g}A{r:g},{r:g} 0 0 1 {x + w - r:g},{y + h:g}"
        f"H{x + r:g}A{r:g},{r:g} 0 0 1 {x:g},{y + h - r:g}"
        f"V{y + r:g}A{r:g},{r:g} 0 0 1 {x + r:g},{y:g}Z"
    )


def paint(color, alpha=1.0):
    return f'fill="{hx(color)}" fill-opacity="{alpha:.3f}"'


class Sheet:
    WIDTH = 720

    def __init__(self):
        self.defs = []
        self.items = []
        self.x = 0
        self.y = 0
        self.rowh = 0
        self.n = 0

    def place(self, w, h):
        if self.x + w > self.WIDTH:
            self.x = 0
            self.y += self.rowh + 2
            self.rowh = 0
        pos = (self.x, self.y)
        self.x += w + 2
        self.rowh = max(self.rowh, h)
        return pos

    def tile(self, ident, w, h, body):
        """A tile whose bounding box is exactly w x h (an invisible rect makes
        sure of it), with body(ox, oy) drawn inside."""
        ox, oy = self.place(w, h)
        self.items.append(
            f'<g id="{ident}"><rect x="{ox}" y="{oy}" width="{w}" height="{h}" '
            f'fill="#000000" fill-opacity="0.004"/>{body(ox, oy)}</g>'
        )

    def frame9(self, prefix, state, fl, ft, fr, fb, master_h, spec, interior=True, sv=None, under=None):
        """The 9 tiles of `prefix-state` (and the interior `prefix-state`).

        spec comes from box(). The master shape is fl + S + fr wide and
        master_h tall (default ft + S + fb); a master taller than the frame
        tiles' sum is how the pill caps get their full height. Each tile is
        cut out of the master here, in Python, as plain filled paths: no
        clipPath, use or masks (QtSvg is SVG Tiny). under(n, w, h, ox, oy),
        if given, draws below each tile's shape (n is the tile's name, None
        for the interior)."""
        S = 4
        W = fl + S + fr
        H = master_h if master_h else ft + S + fb
        sv = H - ft - fb
        outer, inner = master_polys(W, H, spec)
        xs = [(0, fl), (fl, S), (fl + S, fr)]
        ys = [(0, ft), (ft, sv), (ft + sv, fb)]
        names = {
            (0, 0): "topleft", (1, 0): "top", (2, 0): "topright",
            (0, 1): "left", (1, 1): None, (2, 1): "right",
            (0, 2): "bottomleft", (1, 2): "bottom", (2, 2): "bottomright",
        }
        for (i, j), n in names.items():
            tx, tw = xs[i]
            ty, th = ys[j]
            if tw <= 0 or th <= 0:
                continue
            if n is None and not interior:
                continue
            ident = (f"{prefix}-{state}" if state else prefix) + (f"-{n}" if n else "")

            def body(ox, oy, tx=tx, ty=ty, tw=tw, th=th, n=n):
                out = under(n, tw, th, ox, oy) if under else ""
                fo = clip_poly(outer, tx, ty, tx + tw, ty + th)
                if spec["fill"] and fo:
                    out += f'<path d="{poly_d(fo, ox - tx, oy - ty)}" {paint(*spec["fill"])}/>'
                if spec["stroke"] and fo:
                    fi = clip_poly(inner, tx, ty, tx + tw, ty + th) if inner else []
                    d = poly_d(fo, ox - tx, oy - ty) + (poly_d(fi, ox - tx, oy - ty) if fi else "")
                    out += f'<path fill-rule="evenodd" d="{d}" {paint(*spec["stroke"])}/>'
                return out

            self.tile(ident, tw, th, body)

    def svg(self):
        h = self.y + self.rowh + 2
        return (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            "<!-- Generated by scripts/gen-kvantum-themes.py. Do not edit. -->\n"
            f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{self.WIDTH}" height="{h}" viewBox="0 0 {self.WIDTH} {h}">\n'
            "<defs>\n" + "\n".join(self.defs) + "\n</defs>\n" + "\n".join(self.items) + "\n</svg>\n"
        )


def box(fill=None, stroke=None, r=8, inset=0, sw=1):
    """A rounded rectangle with an optional hairline border. fill = (rgb, alpha),
    stroke = (rgb, alpha). inset leaves a transparent margin."""
    return dict(fill=fill, stroke=stroke, r=r, inset=inset, sw=sw)


def rrect_poly(x, y, w, h, r, n=14):
    """A rounded rectangle as a polygon, clockwise."""
    r = max(0.0, min(r, w / 2, h / 2))
    if r == 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0),
                       (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def master_polys(w, h, spec):
    m, sw = spec["inset"], spec["sw"]
    x, y, bw, bh = m, m, w - 2 * m, h - 2 * m
    rad = min(spec["r"], bh / 2) if spec["r"] else 0
    outer = rrect_poly(x, y, bw, bh, rad)
    inner = rrect_poly(x + sw, y + sw, bw - 2 * sw, bh - 2 * sw, max(0, rad - sw)) if spec["stroke"] else None
    return outer, inner


def clip_poly(pts, x0, y0, x1, y1):
    """Sutherland-Hodgman: pts clipped to the rectangle."""
    def clip(pts, inside, cut):
        out = []
        for i, p in enumerate(pts):
            q = pts[i - 1]
            if inside(p):
                if not inside(q):
                    out.append(cut(q, p))
                out.append(p)
            elif inside(q):
                out.append(cut(q, p))
        return out

    def cx(xv):
        return lambda a, b: (xv, a[1] + (b[1] - a[1]) * (xv - a[0]) / (b[0] - a[0]))

    def cy(yv):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (yv - a[1]) / (b[1] - a[1]), yv)

    for inside, cut in ((lambda p: p[0] >= x0, cx(x0)), (lambda p: p[0] <= x1, cx(x1)),
                        (lambda p: p[1] >= y0, cy(y0)), (lambda p: p[1] <= y1, cy(y1))):
        if not pts:
            return []
        pts = clip(pts, inside, cut)
    return pts if len(pts) >= 3 else []


def poly_d(pts, dx, dy):
    return "M" + "L".join(f"{px + dx:.2f},{py + dy:.2f}" for px, py in pts) + "Z"


# --- Drawing the elements ----------------------------------------------------------
def draw_theme(t):
    s = Sheet()
    p = t.p
    txt = t.text
    acc = t.accent
    white = t.white

    def neutral(a):
        return (txt, a)

    # Pills. Normal/hover/pressed follow AtlasButton.qml: text colour at 7/12/20%
    # with a 14% hairline; the default and toggled button is the accent.
    cap, ph = PILL_CAP, PILL_H
    cap_v = 8  # a pill's cap tiles are cap wide and 8 tall; the middle row stretches

    hair = neutral(0.14)
    button_states = {
        "normal": (neutral(0.07), hair),
        "focused": (neutral(0.12), hair),
        "pressed": (neutral(0.20), hair),
        "toggled": ((acc, 1.0), None),
        "toggled-focused": ((lighten(acc, 1.12), 1.0), None),
        "toggled-pressed": ((darken(acc, 1.2), 1.0), None),
        "disabled": (neutral(0.04), neutral(0.08)),
    }
    for st, (fill, stroke) in button_states.items():
        s.frame9("button", st, cap, cap_v, cap, cap_v, ph, box(fill, stroke, r=ph / 2))

    # The default button (Enter activates it): Kvantum draws the unstated
    # `button-default` frame over it. Make that the accent fill.
    # Kvantum can't recolour the label of a default button: it stays the normal
    # text colour. So on the light theme the fill is a lighter accent (dark text
    # stays readable); on the dark theme it is the accent itself.
    dfill = acc if t.dark else mix(acc, white, 0.55)
    s.frame9("button", "default", cap, cap_v, cap, cap_v, ph, box((dfill, 1.0), None, r=ph / 2))
    s.frame9("button-default", None, cap, cap_v, cap, cap_v, ph, box((dfill, 1.0), None, r=ph / 2))
    s.tile("button-default-indicator", 4, 4, lambda ox, oy: "")

    # Tool buttons: flat until hovered.
    tb = TOOL_R
    for st, fill, stroke in [
        ("normal", None, None),
        ("focused", neutral(0.08), None),
        ("pressed", neutral(0.16), None),
        ("toggled", (acc, 0.18), None),
        ("toggled-focused", (acc, 0.26), None),
    ]:
        s.frame9("tbutton", st, tb, tb, tb, tb, 0, box(fill, stroke, r=tb))

    # Text fields: soft fill, 1 px border; 2 px accent ring while focused.
    fr_ = FIELD_R
    field_fill = (txt, 0.06)
    for st, fill, stroke in [
        ("normal", field_fill, neutral(0.12)),
        ("focused", (txt, 0.09), (acc, 0.8)),
        ("disabled", (txt, 0.03), neutral(0.07)),
    ]:
        w = 2 if st == "focused" else 1
        s.frame9("lineedit", st, fr_, fr_, fr_, fr_, 0, box(fill, stroke, r=fr_, sw=w))

    # Cards: group boxes, tab frames and generic frames.
    cd = CARD_R
    card = (t.card, t.card_alpha)
    s.frame9("group", "normal", cd, cd, cd, cd, 0, box(card, neutral(0.12), r=cd), interior=False)
    s.frame9("tabframe", "normal", cd, cd, cd, cd, 0, box(card, neutral(0.12), r=cd), interior=False)
    s.frame9("common", "normal", 6, 6, 6, 6, 0, box(None, neutral(0.12), r=6), interior=False)
    s.frame9("common", "focused", 6, 6, 6, 6, 0, box(None, (acc, 0.8), r=6, sw=2), interior=False)

    # Tabs: a soft pill for the selected one.
    tr = ITEM_R + 2
    for st, fill in [("normal", None), ("focused", neutral(0.06)), ("toggled", (acc, 0.18))]:
        s.frame9("tab", st, tr, tr, tr, tr, 0, box(fill, None, r=tr))
        s.frame9("floating-tab", st, tr, tr, tr, tr, 0, box(fill, None, r=tr))

    # Lists: a rounded accent selection. QML apps (System Settings, Discover) draw
# the selected row's text in the colour scheme's white, so a pale tint would
# leave it unreadable; the selection is the accent itself, rounded.
    ir = ITEM_R
    for st, fill in [
        ("normal", None),
        ("focused", neutral(0.06)),
        ("pressed", (acc, 0.28)),
        ("toggled", (acc, 1.0)),
        ("toggled-focused", (lighten(acc, 1.08), 1.0)),
    ]:
        s.frame9("itemview", st, ir, ir, ir, ir, 0, box(fill, None, r=ir))

    # Menus and tooltips.
    mr = MENU_R
    menu = (t.card, t.menu_alpha)
    s.frame9("menu", "normal", mr, mr, mr, mr, 0, box(menu, neutral(0.16), r=mr))
    tr = TOOLTIP_R
    s.frame9("tooltip", "normal", tr, tr, tr, tr, 0, box((t.card, t.menu_alpha), neutral(0.16), r=tr))
    mi = 5
    for st, fill in [("pressed", (acc, 0.18)), ("toggled", (acc, 0.18)), ("normal", None)]:
        s.frame9("menuitem", st, mi, mi, mi, mi, 0, box(fill, None, r=mi))
    for st, fill in [("normal", None), ("focused", neutral(0.08)), ("pressed", (acc, 0.2)), ("toggled", (acc, 0.2))]:
        s.frame9("menubaritem", st, mi, mi, mi, mi, 0, box(fill, None, r=mi))

    # Menu and tooltip shadows. With a compositor Kvantum paints a menu's
    # (and tooltip's) whole margin, shadow depth plus frame, from the
    # -shadow tiles and only the interior from -normal (PE_PanelMenu,
    # PE_PanelTipLabel). So each -shadow tile holds both: a soft falloff
    # SHADOW px deep on the outside, then the rounded card with its hairline.
    sh = SHADOW
    shade = "#000000"
    a = 0.28 if t.dark else 0.18
    for prefix, r, fill in (("menu", MENU_R, menu), ("tooltip", TOOLTIP_R, (t.card, t.menu_alpha))):
        T = r + sh
        for n, (x1, y1, x2, y2) in {"top": (0, 0, 0, 1), "bottom": (0, 1, 0, 0),
                                     "left": (0, 0, 1, 0), "right": (1, 0, 0, 0)}.items():
            s.defs.append(
                f'<linearGradient id="g{prefix}{n}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
                f'<stop offset="0" stop-color="{shade}" stop-opacity="0"/>'
                f'<stop offset="1" stop-color="{shade}" stop-opacity="{a}"/></linearGradient>'
            )
        inner = r / T
        for n, (cx, cy) in {"topleft": (1, 1), "topright": (0, 1), "bottomleft": (1, 0), "bottomright": (0, 0)}.items():
            s.defs.append(
                f'<radialGradient id="g{prefix}{n}" cx="{cx}" cy="{cy}" r="1">'
                f'<stop offset="0" stop-color="{shade}" stop-opacity="0"/>'
                f'<stop offset="{inner - 0.01:.3f}" stop-color="{shade}" stop-opacity="0"/>'
                f'<stop offset="{inner:.3f}" stop-color="{shade}" stop-opacity="{a}"/>'
                f'<stop offset="1" stop-color="{shade}" stop-opacity="0"/></radialGradient>'
            )

        def falloff(n, w, h, ox, oy, prefix=prefix):
            if n is None:
                return ""
            if n in ("top", "bottom", "left", "right"):
                # The shadow band is the outer sh px of the tile
                x, y = ox, oy
                bw, bh = (w, sh) if n in ("top", "bottom") else (sh, h)
                if n == "bottom":
                    y = oy + h - sh
                if n == "right":
                    x = ox + w - sh
                return f'<rect x="{x}" y="{y}" width="{bw}" height="{bh}" fill="url(#g{prefix}{n})"/>'
            return f'<rect x="{ox}" y="{oy}" width="{w}" height="{h}" fill="url(#g{prefix}{n})"/>'

        s.frame9(f"{prefix}-shadow", "", T, T, T, T, 0,
                 box(fill, neutral(0.16), r=r, inset=sh), interior=False, under=falloff)
        # The shadow hints tell Kvantum how much of that margin is shadow, so
        # its blur stops at the visible rounded card (Style::getShadow: the
        # inset is the margin times hint / tile). Without them the whole
        # window, shadow included, is blurred: a square box around the menu.
        for n in ("top", "bottom", "left", "right"):
            w, h = (sh, 4) if n in ("left", "right") else (4, sh)
            s.tile(f"{prefix}-shadow-hint-{n}", w, h, lambda ox, oy: "")

    # Scrollbars: a thin rounded thumb on an invisible track.
    sr = SCROLL_W // 2
    for st, a in [("normal", 0.30), ("focused", 0.45), ("pressed", 0.55)]:
        s.frame9("scrollbarslider", st, sr, sr, sr, sr, 0,
                 box((txt, a), None, r=sr - SCROLL_PAD, inset=SCROLL_PAD))

    # Sliders: a 6 px groove, accent up to the handle, and a white round handle.
    g = SLIDER_GROOVE // 2
    s.frame9("slider", "normal", g, g, g, g, 0, box(neutral(0.16), None, r=g))
    s.frame9("slider", "toggled", g, g, g, g, 0, box((acc, 1.0), None, r=g))
    for st, ring in [("normal", 0.22), ("focused", 0.30), ("pressed", 0.38), ("disabled", 0.12)]:
        def handle(ox, oy, ring=ring, st=st):
            d = SLIDER_HANDLE
            fill = (mix(white, t.p["window"], 0.55 if st == "disabled" else 1.0), 1.0)
            return (
                f'<circle cx="{ox + d / 2}" cy="{oy + d / 2}" r="{d / 2 - 0.5}" {paint(*fill)} '
                f'stroke="{hx(txt)}" stroke-opacity="{ring}" stroke-width="1"/>'
            )
        s.tile(f"slidercursor-{st}", SLIDER_HANDLE, SLIDER_HANDLE, handle)

    # Progress bars: a 6 px track and an accent fill.
    s.frame9("progress", "normal", g, g, g, g, 0, box(neutral(0.12), None, r=g))
    s.frame9("progress-pattern", "normal", g, g, g, g, 0, box((acc, 1.0), None, r=g))
    s.frame9("progress-pattern", "disabled", g, g, g, g, 0, box(neutral(0.25), None, r=g))

    # Check boxes and radio buttons.
    def check(kind, checked, state):
        def draw(ox, oy):
            d = CHECK
            cx = cy = d / 2
            focus = state in ("focused", "pressed")
            edge = (acc, 1.0) if focus else neutral(0.38)
            if state == "disabled":
                edge = neutral(0.2)
            on = checked
            out = ""
            if kind == "radio":
                if on:
                    out += f'<circle cx="{ox + cx}" cy="{oy + cy}" r="{d / 2 - 1}" {paint(*((acc, 1.0) if state != "disabled" else (txt, 0.25)))}/>'
                    out += f'<circle cx="{ox + cx}" cy="{oy + cy}" r="{d / 6}" fill="#ffffff"/>'
                else:
                    out += f'<circle cx="{ox + cx}" cy="{oy + cy}" r="{d / 2 - 1.25}" {paint(txt, 0.04 if state != "pressed" else 0.12)} stroke="{hx(edge[0])}" stroke-opacity="{edge[1]}" stroke-width="1.5"/>'
                return out
            r = 5
            if on:
                fill = (acc, 1.0) if state != "disabled" else (txt, 0.25)
                out += f'<path d="{rr(ox + 1, oy + 1, d - 2, d - 2, r)}" {paint(*fill)}/>'
                if kind == "tristate":
                    out += f'<path d="M{ox + 5},{oy + cy}H{ox + d - 5}" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>'
                else:
                    out += (f'<path d="M{ox + 5},{oy + cy + 0.5}L{ox + cx - 1},{oy + d - 6}L{ox + d - 4.5},{oy + 5}" '
                            f'fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')
            else:
                out += (f'<path d="{rr(ox + 0.75, oy + 0.75, d - 1.5, d - 1.5, r)}" {paint(txt, 0.04 if state != "pressed" else 0.12)} '
                        f'stroke="{hx(edge[0])}" stroke-opacity="{edge[1]}" stroke-width="1.5"/>')
            return out
        return draw

    for kind in ("checkbox", "radio"):
        for st in ("normal", "focused", "pressed", "disabled"):
            on, off = ("radio", "radio") if kind == "radio" else ("checked", "unchecked")
            s.tile(f"{kind}-{st}", CHECK, CHECK, check(off, False, st))
            s.tile(f"{kind}-checked-{st}", CHECK, CHECK, check(on, True, st))
    for st in ("normal", "focused", "pressed", "disabled"):
        s.tile(f"checkbox-tristate-{st}", CHECK, CHECK, check("tristate", True, st))

    # Arrows (chevrons).
    A = 12
    pts = {
        "up": "M2.5,8L6,4.5L9.5,8",
        "down": "M2.5,4L6,7.5L9.5,4",
        "left": "M8,2.5L4.5,6L8,9.5",
        "right": "M4,2.5L7.5,6L4,9.5",
    }
    for d, path in pts.items():
        for st, color, a in [
            ("normal", txt, 0.7), ("focused", txt, 0.9), ("pressed", txt, 1.0),
            ("toggled", white, 1.0), ("disabled", txt, 0.3),
        ]:
            s.tile(f"arrow-{d}-{st}", A, A,
                   lambda ox, oy, path=path, color=color, a=a:
                   f'<path transform="translate({ox} {oy})" d="{path}" fill="none" stroke="{hx(color)}" '
                   f'stroke-opacity="{a}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>')

    # Spin box +/- (used when the spin indicators are inline).
    for nm, d in (("plus", "M3,6H9M6,3V9"), ("minus", "M3,6H9")):
        for st, a in [("normal", 0.7), ("pressed", 1.0), ("disabled", 0.3)]:
            s.tile(f"arrow-{nm}-{st}", A, A,
                   lambda ox, oy, d=d, a=a:
                   f'<path transform="translate({ox} {oy})" d="{d}" fill="none" stroke="{hx(txt)}" '
                   f'stroke-opacity="{a}" stroke-width="1.6" stroke-linecap="round"/>')

    # Grips and separators.
    s.tile("splitter-grip-normal", 16, 4,
           lambda ox, oy: f'<path d="{rr(ox + 4, oy + 1, 8, 2, 1)}" {paint(txt, 0.35)}/>')
    s.tile("grip-normal", 13, 13, lambda ox, oy: "")
    s.tile("resize-grip-normal", 13, 13,
           lambda ox, oy: "".join(f'<circle cx="{ox + x}" cy="{oy + y}" r="1" {paint(txt, 0.35)}/>'
                                  for x, y in ((10, 10), (6, 10), (10, 6))))
    s.tile("header-separator", 2, 16,
           lambda ox, oy: f'<rect x="{ox + 0.5}" y="{oy + 2}" width="1" height="12" {paint(txt, 0.14)}/>')
    s.tile("toolbar-handle", 6, 16,
           lambda ox, oy: "".join(f'<circle cx="{ox + 3}" cy="{oy + y}" r="1" {paint(txt, 0.3)}/>' for y in (4, 8, 12)))
    s.tile("titlebar-normal", 4, 4, lambda ox, oy: "")
    s.tile("titlebar-focused", 4, 4, lambda ox, oy: "")
    s.tile("splitter-normal", 4, 4, lambda ox, oy: "")
    # Dock and toolbar backgrounds are flat.
    s.frame9("toolbar", "normal", 1, 1, 1, 1, 0, box(None, None, r=0), interior=False)
    return s


# --- The theme config -----------------------------------------------------------------
def kvconfig(t, name, comment):
    p = t.p
    txt, acc = hx(t.text), hx(t.accent)
    disabled = hx(mix(t.text, p["window"], 0.4))
    translucent = t.translucent
    onoff = lambda b: "true" if b else "false"
    opaque = ",".join(OPAQUE)
    dark = t.dark
    return f"""[%General]
author=AtlasOS
comment={comment}
x11drag=menubar_and_primary_toolbar
alt_mnemonic=true
left_tabs=false
attach_active_tab=false
joined_tabs=false
group_toolbar_buttons=false
composite=true
translucent_windows={onoff(translucent)}
blurring={onoff(translucent)}
popup_blurring={onoff(translucent)}
reduce_window_opacity={WINDOW_OPACITY_REDUCTION if translucent else 0}
reduce_menu_opacity={MENU_OPACITY_REDUCTION if translucent else 0}
opaque={opaque}
menu_shadow_depth={SHADOW}
tooltip_shadow_depth={SHADOW}
spread_menuitems=false
spread_progressbar=true
progressbar_thickness={SLIDER_GROOVE}
splitter_width={SPLITTER_W}
scroll_width={SCROLL_W}
scroll_min_extent=36
scroll_arrows=false
transient_scrollbar=false
transient_groove=false
slider_width={SLIDER_GROOVE}
slider_handle_width={SLIDER_HANDLE}
slider_handle_length={SLIDER_HANDLE}
check_size={CHECK}
toolbar_icon_size=16
combo_as_lineedit=false
combo_menu=false
inline_spin_indicators=true
animate_states=true
button_contents_shift=false
layout_spacing=6
layout_margin=8
submenu_overlap=0
submenu_delay=250
menu_blur_radius={MENU_R}
tooltip_blur_radius={TOOLTIP_R}
fill_rubberband=true
scrollable_menu=true
vertical_spin_indicators=false
no_inactive_tint=false
dialog_button_layout=0

[GeneralColors]
window.color={hx(p["window"])}
inactive.window.color={hx(p["window"])}
base.color={hx(p["base"])}
inactive.base.color={hx(p["base"])}
alt.base.color={hx(p["base_alt"])}
inactive.alt.base.color={hx(p["base_alt"])}
button.color={hx(p["button"])}
light.color={hx(mix(t.white, p["window"], 0.5))}
mid.light.color={hx(mix(t.text, p["window"], 0.1))}
dark.color={hx(mix(t.text, p["window"], 0.3))}
mid.color={hx(mix(t.text, p["window"], 0.2))}
highlight.color={acc}
inactive.highlight.color={acc}
text.color={txt}
inactive.text.color={txt}
window.text.color={txt}
inactive.window.text.color={txt}
button.text.color={txt}
disabled.text.color={disabled}
tooltip.text.color={txt}
highlight.text.color=#ffffff
link.color={hx(p["link"])}
link.visited.color={hx(p["visited"])}

[Hacks]
respect_darkness={onoff(dark)}
transparent_ktitle_label=true
transparent_dolphin_view=false
transparent_pcmanfm_sidepane=false
blur_konsole=false
kcapacitybar_as_progressbar=true
iconless_pushbutton=false
normal_default_pushbutton=false
middle_click_scroll=false
disabled_icon_opacity=60
tint_on_mouseover=0
no_selection_tint=true
centered_forms=false

[PanelButtonCommand]
frame=true
frame.element=button
frame.top=8
frame.bottom=8
frame.left=17
frame.right=17
interior=true
interior.element=button
indicator.size=12
indicator.element=arrow
text.normal.color={txt}
text.focus.color={txt}
text.press.color={txt}
text.toggle.color=#ffffff
text.disabled.color={disabled}
text.shadow=0
text.margin=0
text.iconspacing=6
text.margin.top=0
text.margin.bottom=0
text.margin.left=0
text.margin.right=0

[PanelButtonTool]
inherits=PanelButtonCommand
interior.element=tbutton
frame.element=tbutton
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
text.toggle.color={txt}
text.margin.left=0
text.margin.right=0

[Dock]
inherits=PanelButtonCommand
frame=false
interior=false

[DockTitle]
inherits=PanelButtonCommand
frame=false
interior=false
text.bold=true

[IndicatorSpinBox]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=arrow
indicator.size=10
text.margin=0

[RadioButton]
inherits=PanelButtonCommand
frame=false
interior.element=radio
text.margin.left=4

[CheckBox]
inherits=PanelButtonCommand
frame=false
interior.element=checkbox
text.margin.left=4

[GenericFrame]
inherits=PanelButtonCommand
frame=true
interior=false
frame.element=common
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
text.margin=0

[LineEdit]
inherits=PanelButtonCommand
frame=true
interior=true
frame.element=lineedit
interior.element=lineedit
frame.top={FIELD_R}
frame.bottom={FIELD_R}
frame.left={FIELD_R}
frame.right={FIELD_R}
text.margin.top=0
text.margin.bottom=0
text.margin.left=1
text.margin.right=1

[DropDownButton]
inherits=PanelButtonCommand
indicator.element=arrow-down

[IndicatorArrow]
indicator.element=arrow
indicator.size=12

[ToolboxTab]
inherits=PanelButtonCommand
frame.left=8
frame.right=8

[Tab]
inherits=PanelButtonCommand
interior.element=tab
frame.element=tab
frame.top={ITEM_R + 2}
frame.bottom={ITEM_R + 2}
frame.left={ITEM_R + 2}
frame.right={ITEM_R + 2}
text.margin=0
text.toggle.color={txt}
text.press.color={txt}
indicator.element=tab
min_width=+0
min_height=+0

[TabBarFrame]
inherits=GenericFrame
frame=false
interior=false

[TabFrame]
inherits=PanelButtonCommand
frame=true
interior=false
frame.element=tabframe
frame.top={CARD_R}
frame.bottom={CARD_R}
frame.left={CARD_R}
frame.right={CARD_R}

[TreeExpander]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.size=10

[HeaderSection]
inherits=PanelButtonCommand
frame=false
interior=false
text.margin.top=4
text.margin.bottom=4
text.margin.left=6
text.margin.right=6
text.bold=true
text.normal.color={hx(mix(t.text, p["window"], 0.7))}

[SizeGrip]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=resize-grip
indicator.size=13

[Toolbar]
inherits=PanelButtonCommand
indicator.element=toolbar
indicator.size=6
text.margin=0
frame.element=toolbar
frame=false
interior=false

[Slider]
inherits=PanelButtonCommand
frame.element=slider
interior.element=slider
frame.top={SLIDER_GROOVE // 2}
frame.bottom={SLIDER_GROOVE // 2}
frame.left={SLIDER_GROOVE // 2}
frame.right={SLIDER_GROOVE // 2}

[SliderCursor]
inherits=PanelButtonCommand
frame=false
interior.element=slidercursor

[Progressbar]
inherits=PanelButtonCommand
frame.element=progress
interior.element=progress
frame.top={SLIDER_GROOVE // 2}
frame.bottom={SLIDER_GROOVE // 2}
frame.left={SLIDER_GROOVE // 2}
frame.right={SLIDER_GROOVE // 2}
text.margin=0
text.normal.color={txt}
text.focus.color={txt}
text.press.color={txt}
text.toggle.color={txt}

[ProgressbarContents]
inherits=PanelButtonCommand
frame=true
interior=true
frame.element=progress-pattern
interior.element=progress-pattern
frame.top={SLIDER_GROOVE // 2}
frame.bottom={SLIDER_GROOVE // 2}
frame.left={SLIDER_GROOVE // 2}
frame.right={SLIDER_GROOVE // 2}

[ItemView]
inherits=PanelButtonCommand
frame.element=itemview
interior.element=itemview
frame.top={ITEM_R}
frame.bottom={ITEM_R}
frame.left={ITEM_R}
frame.right={ITEM_R}
text.margin=0
text.margin.top=0
text.margin.bottom=0
text.margin.left=0
text.margin.right=0
text.normal.color={txt}
text.focus.color={txt}
text.press.color={txt}
text.toggle.color=#ffffff

[Splitter]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=splitter-grip
indicator.size=16

[Scrollbar]
inherits=PanelButtonCommand
indicator.size=9

[ScrollbarSlider]
inherits=PanelButtonCommand
frame.element=scrollbarslider
interior.element=scrollbarslider
frame.top={SCROLL_W // 2}
frame.bottom={SCROLL_W // 2}
frame.left={SCROLL_W // 2}
frame.right={SCROLL_W // 2}
indicator.element=grip
indicator.size=13

[ScrollbarGroove]
inherits=PanelButtonCommand
frame=false
interior=false

[MenuItem]
inherits=PanelButtonCommand
frame=true
frame.element=menuitem
interior.element=menuitem
indicator.element=menuitem
text.focus.color={txt}
text.press.color={txt}
text.toggle.color={txt}
text.margin.top=2
text.margin.bottom=2
text.margin.left=4
text.margin.right=4
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5

[MenuBarItem]
inherits=PanelButtonCommand
interior.element=menubaritem
frame.element=menubaritem
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
text.margin.left=4
text.margin.right=4
text.toggle.color={txt}
text.press.color={txt}

[TitleBar]
inherits=PanelButtonCommand
frame=false
interior.element=titlebar
indicator.size=12
text.bold=true

[ComboBox]
inherits=PanelButtonCommand
frame.left=17
frame.right=17

[Menu]
inherits=PanelButtonCommand
frame.top={MENU_R}
frame.bottom={MENU_R}
frame.left={MENU_R}
frame.right={MENU_R}
frame.element=menu
interior.element=menu
text.margin=0

[GroupBox]
inherits=GenericFrame
frame=true
interior=false
frame.element=group
text.shadow=0
text.margin=0
frame.top={CARD_R}
frame.bottom={CARD_R}
frame.left={CARD_R}
frame.right={CARD_R}

[ToolTip]
inherits=GenericFrame
frame.top={TOOLTIP_R}
frame.bottom={TOOLTIP_R}
frame.left={TOOLTIP_R}
frame.right={TOOLTIP_R}
interior=true
text.shadow=0
text.margin=0
interior.element=tooltip
frame.element=tooltip

[StatusBar]
inherits=GenericFrame
frame=false
interior=false

[Window]
interior=false
"""


THEMES = [
    ("AtlasOS", "AtlasOSLight", False, True, "AtlasOS light style, with blur behind windows"),
    ("AtlasOSDark", "AtlasOSDark", True, True, "AtlasOS dark style, with blur behind windows"),
    ("AtlasOSSolid", "AtlasOSLight", False, False, "AtlasOS light style, opaque windows"),
    ("AtlasOSDarkSolid", "AtlasOSDark", True, False, "AtlasOS dark style, opaque windows"),
]


def main():
    for name, scheme, dark, translucent, comment in THEMES:
        t = Theme(load_scheme(scheme), dark, translucent)
        d = OUT / name
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{name}.svg").write_text(draw_theme(t).svg())
        (d / f"{name}.kvconfig").write_text(kvconfig(t, name, escape(comment)))
        print(f"wrote {d}")


if __name__ == "__main__":
    main()
