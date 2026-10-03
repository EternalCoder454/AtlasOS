#!/usr/bin/python3
"""Make Dracula's one-colour icons follow the colour scheme.

Dracula draws its symbolic icons (and some small action and panel icons) in
its own near-white, #f8f8f2, written into each file. Breeze's icons instead
mark the shapes with KDE's colour-scheme stylesheet, which Plasma fills with
the theme's text colour. So under AtlasOS Light, everything that asks for a
-symbolic icon (Discover's categories, Kirigami apps, the panel) drew white on
white. This rewrites those files the Breeze way: #f8f8f2 becomes currentColor
with class ColorScheme-Text, and the stylesheet keeps #f8f8f2 as the default,
so nothing changes where no theme colour is applied (GTK recolours symbolic
icons on its own).

Symbolic icons are always changed (an accent such as a red cross keeps its
colour). Among the sized ones, only one-colour icons are: one that also uses
other colours is art (a white page, a highlight) and stays as it is.

Usage: icon-recolor.py THEME_DIR SUBDIR...   (e.g. /usr/share/icons/Dracula
symbolic 16 22 24 32). Prints how many files it changed.
"""

import re
import sys
from pathlib import Path

WHITE = "#f8f8f2"
STYLE = (
    '<style id="current-color-scheme" type="text/css">'
    ".ColorScheme-Text { color:" + WHITE + "; }</style>"
)
# The colours an icon paints with (gradient stops don't count).
PAINT = re.compile(
    r'(?<![-\w])(?:fill|stroke|color)\s*(?:=\s*"|:\s*)(#[0-9a-fA-F]{3,6})\b',
    re.IGNORECASE,
)
ATTR = re.compile(r'(?<![-\w])(fill|stroke)="#f8f8f2"', re.IGNORECASE)
STYLE_PROP = re.compile(r"(?<![-\w])(fill|stroke)\s*:\s*#f8f8f2\b", re.IGNORECASE)
# `color` set to the white, for shapes painted with currentColor: the class
# overrides the attribute, but not an inline style, so that one goes.
COLOR_ATTR = re.compile(r'(?<![-\w])color="#f8f8f2"', re.IGNORECASE)
COLOR_STYLE = re.compile(r"(?<![-\w])color\s*:\s*#f8f8f2\s*;?", re.IGNORECASE)
TAG = re.compile(r"<(?!/|\?|!)[^>]*>", re.DOTALL)
CLASS = re.compile(r'\bclass="([^"]*)"')
ROOT = re.compile(r"<svg\b[^>]*>", re.DOTALL)
STYLE_BLOCK = re.compile(r"<style\b.*?</style>", re.DOTALL | re.IGNORECASE)


def one_colour(text: str) -> bool:
    paints = {c.lower() for c in PAINT.findall(STYLE_BLOCK.sub("", text))}
    return paints == {WHITE}


def mark(tag: str) -> str:
    """Rewrites one start tag if it paints with the white."""
    new = ATTR.sub(lambda m: f'{m.group(1)}="currentColor"', tag)
    new = STYLE_PROP.sub(lambda m: f"{m.group(1)}:currentColor", new)
    new = COLOR_STYLE.sub("", new)
    if new == tag and not COLOR_ATTR.search(tag):
        return tag
    m = CLASS.search(new)
    if m:
        if "ColorScheme-Text" not in m.group(1).split():
            new = new[: m.start(1)] + (m.group(1) + " ColorScheme-Text").strip() + new[m.end(1) :]
        return new
    end = -2 if new.endswith("/>") else -1
    return new[:end].rstrip() + ' class="ColorScheme-Text"' + new[end:]


def convert(text: str, symbolic: bool) -> str | None:
    if WHITE not in text.lower():
        return None
    if not symbolic and not one_colour(text):
        return None
    root = ROOT.search(text)
    if not root or root.group(0).endswith("/>"):
        return None
    head, body = text[: root.end()], text[root.end() :]
    new_body = TAG.sub(lambda m: mark(m.group(0)), body)
    new_head = head[: root.start()] + mark(root.group(0))
    if new_head + new_body == text:
        return None
    # Some already carry the stylesheet but paint with the white anyway:
    # those keep theirs (its other classes, such as the highlight colour).
    if "current-color-scheme" in text:
        return new_head + new_body
    return new_head + STYLE + new_body


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    theme = Path(sys.argv[1])
    changed = 0
    for sub in sys.argv[2:]:
        for f in sorted((theme / sub).rglob("*.svg")):
            if f.is_symlink() or not f.is_file():
                continue
            text = f.read_text(encoding="utf-8")
            out = convert(text, "symbolic" in f.relative_to(theme).parts)
            if out is not None:
                f.write_text(out, encoding="utf-8")
                changed += 1
    print(f"icon-recolor: {changed} icons now follow the colour scheme")
    return 0


if __name__ == "__main__":
    sys.exit(main())
