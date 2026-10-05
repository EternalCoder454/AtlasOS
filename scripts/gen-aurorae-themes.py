#!/usr/bin/env python3
"""Writes the AtlasOS-Light and AtlasOS-Dark Aurorae window decoration themes
to system_files/usr/share/aurorae/themes/. The output is committed; run this
after changing the numbers or colours below, then rebuild the image.

    python3 scripts/gen-aurorae-themes.py

Rounded-square caption buttons (Klassy style): a 26 px square, 7 px corners, in a 32 px square cell,
4 px between cells, a 9 px glyph with a 1.6 px round stroke. The square is a
faint tint of the glyph colour at rest, accent on hover, solid red for close. Title bar colours are the [Colors:Header]
colours of system_files/usr/share/color-schemes/AtlasOS{Light,Dark}.colors.
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "system_files", "usr", "share", "aurorae", "themes")

BTN = 32                   # caption button cell (square)
DIAM = 26                  # the rounded square in it
RADIUS_BTN = 7             # its corner radius
GLYPH, STROKE = 9, 1.6
TITLE_H = 32               # title bar height (BorderTop)
BORDER = 1                 # left, right and bottom frame
RADIUS = 8                 # top corners
PAD_SIDE, PAD_TOP, PAD_BOTTOM = 16, 16, 24   # transparent room for the shadow

THEMES = {
    "AtlasOS-Light": dict(
        bar="#E2DFF4", bar_inactive="#F3F2FA",
        text="#1B1748", text_inactive="#6B658C",
        glyph="#1B1748", glyph_inactive_opacity=0.7,
        accent="#6858E2",
        shadow=0.30, shadow_inactive=0.16),
    "AtlasOS-Dark": dict(
        bar="#2B2748", bar_inactive="#211E38",
        text="#EEECFA", text_inactive="#A59FC4",
        glyph="#EEECFA", glyph_inactive_opacity=0.7,
        accent="#8A7AF4",
        shadow=0.55, shadow_inactive=0.30),
}
CLOSE_RED = "#C42B1C"
CLOSE_RED_PRESSED = "#A52416"


def f(n):
    return ("%.3f" % n).rstrip("0").rstrip(".")


class Svg:
    def __init__(self, w, h):
        self.w, self.h, self.defs, self.body, self.n = w, h, [], [], 0

    def grad(self, kind, attrs, stops):
        self.n += 1
        gid = "g%d" % self.n
        st = "".join('<stop offset="%s" stop-color="#000" stop-opacity="%s"/>' % (f(o), f(a))
                     for o, a in stops)
        self.defs.append('<%sGradient id="%s" gradientUnits="userSpaceOnUse" %s>%s</%sGradient>'
                         % (kind, gid, attrs, st, kind))
        return "url(#%s)" % gid

    def cell(self, eid, ox, oy, w, h, content):
        """An element of size w x h placed at ox,oy. The invisible rect gives
        the element its full bounds."""
        self.body.append('<g id="%s"><g transform="translate(%s %s)">'
                         '<rect width="%s" height="%s" fill="#000" fill-opacity="0"/>%s</g></g>'
                         % (eid, f(ox), f(oy), f(w), f(h), content))

    def text(self):
        return ('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">\n'
                '<defs>%s</defs>\n%s\n</svg>\n'
                % (f(self.w), f(self.h), f(self.w), f(self.h),
                   "".join(self.defs), "\n".join(self.body)))


def fall(a):
    """Shadow alpha from the window edge (0) to the outer edge (1), soft."""
    return [(0, a), (0.25, a * 0.62), (0.5, a * 0.3), (0.75, a * 0.1), (1, 0)]


def inner(a, r0):
    """Radial stops that stay at full alpha up to fraction r0 (under the window)."""
    return [(0, a), (r0, a)] + [(r0 + (1 - r0) * o, v) for o, v in fall(a)[1:]]


# ---------------------------------------------------------------- decoration

def decoration(t):
    PL = PR = PAD_SIDE
    PT, PB = PAD_TOP, PAD_BOTTOM
    CW = PL + RADIUS                 # left/right margin: shadow + corner radius
    TH = PT + TITLE_H                # top margin
    BH = PB + BORDER                 # bottom margin
    svg = Svg(2 * CW + 40, 2 * (TH + BH) + 200)
    y0 = 0
    for prefix, bar, sh in (("decoration", t["bar"], t["shadow"]),
                            ("decoration-inactive", t["bar_inactive"], t["shadow_inactive"])):
        def cell(name, x, y, w, h, c):
            svg.cell(prefix + "-" + name, x, y0 + y, w, h, c)

        r0 = RADIUS / (RADIUS + PAD_SIDE)
        # top-left: radial shadow around the arc, left band, bar with arc
        rg = svg.grad("radial", 'cx="%s" cy="%s" r="%s"' % (f(CW), f(TH - TITLE_H + RADIUS), f(RADIUS + PAD_SIDE)), inner(sh, r0))
        lg = svg.grad("linear", 'x1="0" y1="0" x2="%s" y2="0"' % f(-0 + PL), [(0, 0)] + [(1 - o, a) for o, a in reversed(fall(sh))][1:] )
        # (left band: alpha 0 at x=0 rising to the full value at x=PL)
        arc_y = PT
        topleft = ('<rect x="0" y="0" width="%s" height="%s" fill="%s"/>'
                   '<rect x="0" y="%s" width="%s" height="%s" fill="%s"/>'
                   '<path d="M%s %s V%s A%s %s 0 0 1 %s %s V%s Z" fill="%s"/>'
                   % (f(CW), f(PT + RADIUS), rg,
                      f(PT + RADIUS), f(PL), f(TH - PT - RADIUS), lg,
                      f(PL), f(TH), f(arc_y + RADIUS), RADIUS, RADIUS, f(PL + RADIUS), f(arc_y), f(TH), bar))
        cell("topleft", 0, 0, CW, TH, topleft)
        # top-right is the mirror
        topright = '<g transform="translate(%s 0) scale(-1 1)">%s</g>' % (f(CW), topleft)
        cell("topright", CW + 20, 0, CW, TH, topright)
        # top: shadow above, bar below (stretches sideways)
        tg = svg.grad("linear", 'x1="0" y1="0" x2="0" y2="%s"' % f(PT), [(0, 0)] + [(1 - o, a) for o, a in reversed(fall(sh))][1:])
        cell("top", 2 * CW + 40 - 10, 0, 8, TH,
             '<rect width="8" height="%s" fill="%s"/><rect y="%s" width="8" height="%s" fill="%s"/>'
             % (f(PT), tg, f(PT), f(TITLE_H), bar))
        # left/right: shadow band, then the bar colour under the client
        lgx = svg.grad("linear", 'x1="0" y1="0" x2="%s" y2="0"' % f(PL), [(0, 0)] + [(1 - o, a) for o, a in reversed(fall(sh))][1:])
        left = ('<rect width="%s" height="8" fill="%s"/><rect x="%s" width="%s" height="8" fill="%s"/>'
                % (f(PL), lgx, f(PL), f(RADIUS), bar))
        cell("left", 0, TH + 10, CW, 8, left)
        cell("right", CW + 20, TH + 10, CW, 8, '<g transform="translate(%s 0) scale(-1 1)">%s</g>' % (f(CW), left))
        # bottom-left: bar strip, corner radial, bottom band
        by = BORDER
        brg = svg.grad("radial", 'cx="%s" cy="%s" r="%s"' % (f(PL), f(by), f(PAD_SIDE)),
                       fall(sh))
        # elliptical: wider drop at the bottom
        self_t = 'gradientTransform="translate(%s %s) scale(1 %s) translate(%s %s)"' % (
            f(PL), f(by), f(PB / PAD_SIDE), f(-PL), f(-by))
        svg.defs[-1] = svg.defs[-1].replace('gradientUnits="userSpaceOnUse"', 'gradientUnits="userSpaceOnUse" ' + self_t)
        bg = svg.grad("linear", 'x1="0" y1="%s" x2="0" y2="%s"' % (f(by), f(by + PB)), fall(sh))
        blx = svg.grad("linear", 'x1="0" y1="0" x2="%s" y2="0"' % f(PL), [(0, 0)] + [(1 - o, a) for o, a in reversed(fall(sh))][1:])
        bottomleft = ('<rect width="%s" height="%s" fill="%s"/>'
                      '<rect x="%s" width="%s" height="%s" fill="%s"/>'
                      '<rect y="%s" width="%s" height="%s" fill="%s"/>'
                      % (f(PL), f(by), blx, f(PL), f(RADIUS), f(by), bar,
                         f(by), f(PL), f(PB), brg))
        # bottom band under the strip (x >= PL)
        bottomleft += '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % (f(PL), f(by), f(RADIUS), f(PB), bg)
        cell("bottomleft", 0, TH + 40, CW, BH, bottomleft)
        cell("bottomright", CW + 20, TH + 40, CW, BH, '<g transform="translate(%s 0) scale(-1 1)">%s</g>' % (f(CW), bottomleft))
        bgx = svg.grad("linear", 'x1="0" y1="%s" x2="0" y2="%s"' % (f(by), f(by + PB)), fall(sh))
        cell("bottom", 2 * CW + 40 - 10, TH + 40, 8, BH,
             '<rect width="8" height="%s" fill="%s"/><rect y="%s" width="8" height="%s" fill="%s"/>'
             % (f(by), bar, f(by), f(PB), bgx))
        cell("center", 2 * CW + 40 - 10, TH + 10, 8, 8, '<rect width="8" height="8" fill="%s"/>' % bar)
        # maximized: just the bar
        if prefix == "decoration":
            cell("maximized-center", 2 * CW + 40 - 10, TH + 70, 8, TITLE_H,
                 '<rect width="8" height="%s" fill="%s"/>' % (TITLE_H, bar))
        else:
            cell("maximized-inactive-center", 2 * CW + 40 - 10, TH + 70, 8, TITLE_H,
                 '<rect width="8" height="%s" fill="%s"/>' % (TITLE_H, bar))
        y0 += TH + BH + 110
    svg.h = y0 + 10
    return svg.text()


# ------------------------------------------------------------------- buttons

def glyph(kind, color):
    """9 px glyph, 1.6 px round stroke, centred in the BTN x BTN cell."""
    c = BTN / 2
    h = GLYPH / 2
    x0, y0 = c - h, c - h
    s = ('fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" '
         'stroke-linejoin="round"' % (color, f(STROKE)))
    if kind == "minimize":
        return '<path d="M%s %s H%s" %s/>' % (f(x0), f(c), f(c + h), s)
    if kind == "maximize":
        return '<rect x="%s" y="%s" width="%d" height="%d" rx="1.8" %s/>' % (f(x0), f(y0), GLYPH, GLYPH, s)
    if kind == "restore":
        q, r = 6.5, 1.4          # square size, corner radius
        return ('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" %s/>'
                '<path d="M%s %s V%s A%s %s 0 0 1 %s %s H%s A%s %s 0 0 1 %s %s V%s A%s %s 0 0 1 %s %s H%s" %s/>'
                % (f(x0), f(y0 + GLYPH - q), f(q), f(q), f(r), s,
                   f(x0 + GLYPH - q), f(y0 + GLYPH - q), f(y0 + r), f(r), f(r),
                   f(x0 + GLYPH - q + r), f(y0), f(x0 + GLYPH - r), f(r), f(r),
                   f(x0 + GLYPH), f(y0 + r), f(y0 + q - r), f(r), f(r),
                   f(x0 + GLYPH - r), f(y0 + q), f(x0 + q), s))
    if kind == "close":
        return '<path d="M%s %s L%s %s M%s %s L%s %s" %s/>' % (
            f(x0), f(y0), f(x0 + GLYPH), f(y0 + GLYPH), f(x0 + GLYPH), f(y0), f(x0), f(y0 + GLYPH), s)
    raise ValueError(kind)


def button(kind, t):
    svg = Svg(BTN, 8 * BTN)
    gl, acc = t["glyph"], t["accent"]
    close = kind == "close"
    gi = t["glyph_inactive_opacity"]

    def disc(color, op):
        o = (BTN - DIAM) / 2
        return '<rect x="%s" y="%s" width="%d" height="%d" rx="%d" fill="%s" fill-opacity="%s"/>' % (
            f(o), f(o), DIAM, DIAM, RADIUS_BTN, color, f(op))

    def dim(op, c):
        return '<g opacity="%s">%s</g>' % (f(op), c)

    rest = disc(gl, 0.07) + glyph(kind, gl)
    rest_in = disc(gl, 0.05) + dim(gi, glyph(kind, gl))
    hover = (disc(CLOSE_RED, 1) + glyph(kind, "#FFFFFF")) if close else (disc(acc, 0.28) + glyph(kind, gl))
    press = (disc(CLOSE_RED_PRESSED, 1) + glyph(kind, "#FFFFFF")) if close else (disc(acc, 0.45) + glyph(kind, gl))
    states = {
        "active": rest,
        "hover": hover,
        "pressed": press,
        "deactivated": disc(gl, 0.04) + dim(0.4, glyph(kind, gl)),
        "inactive": rest_in,
        "hover-inactive": hover,
        "pressed-inactive": press,
        "deactivated-inactive": disc(gl, 0.03) + dim(0.35, glyph(kind, gl)),
    }
    for i, (name, c) in enumerate(states.items()):
        svg.cell(name + "-center", 0, i * BTN, BTN, BTN, c)
    return svg.text()


def rc(name, t):
    return f"""# Aurorae layout of {name}: rounded-square caption buttons. Written by
# scripts/gen-aurorae-themes.py.
[General]
ActiveTextColor={t['text']}
InactiveTextColor={t['text_inactive']}
UseTextShadow=false
TitleAlignment=Left
TitleVerticalAlignment=Center
Animation=120
ButtonSize=Normal

[Layout]
BorderLeft={BORDER}
BorderRight={BORDER}
BorderBottom={BORDER}
BorderTop={TITLE_H}
BorderLeftMaximized=0
BorderRightMaximized=0
BorderBottomMaximized=0
BorderTopMaximized={TITLE_H}
TitleEdgeTop=0
TitleEdgeBottom=0
TitleEdgeLeft=4
TitleEdgeRight=9
TitleEdgeTopMaximized=0
TitleEdgeBottomMaximized=0
TitleEdgeLeftMaximized=4
TitleEdgeRightMaximized=9
TitleBorderLeft=4
TitleBorderRight=8
TitleHeight={TITLE_H}
ButtonWidth={BTN}
ButtonWidthMinimize={BTN}
ButtonWidthMaximizeRestore={BTN}
ButtonWidthClose={BTN}
ButtonWidthMenu=32
ButtonWidthAppMenu=32
ButtonWidthAlldesktops=32
ButtonWidthKeepabove=32
ButtonWidthKeepbelow=32
ButtonWidthShade=32
ButtonWidthHelp=32
ButtonHeight={BTN}
ButtonSpacing=4
ButtonMarginTop=0
ButtonMarginTopMaximized=0
ExplicitButtonSpacer=8
PaddingLeft={PAD_SIDE}
PaddingRight={PAD_SIDE}
PaddingTop={PAD_TOP}
PaddingBottom={PAD_BOTTOM}
"""


def metadata(name, t):
    return f"""[Desktop Entry]
Name={name.replace('-', ' ')}
Comment=Title bar with rounded-square caption buttons
X-KDE-PluginInfo-Name={name}
X-KDE-PluginInfo-Author=AtlasOS
X-KDE-PluginInfo-License=GPL
"""


def main():
    for name, t in THEMES.items():
        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)
        files = {"decoration.svg": decoration(t), name + "rc": rc(name, t),
                 "metadata.desktop": metadata(name, t)}
        for k in ("minimize", "maximize", "restore", "close"):
            files[k + ".svg"] = button(k, t)
        for fn, content in files.items():
            with open(os.path.join(d, fn), "w") as fh:
                fh.write(content)


main()
