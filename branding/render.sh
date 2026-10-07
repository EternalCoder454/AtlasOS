#!/bin/sh
# Renders every image the OS installs: the logos from branding/source/, which
# are copies of the Telamon OS logo set and are never edited, and the wallpaper in
# branding/wallpaper.jpg (light) and wallpaper-dark.jpg (dark). Runs in the Containerfile's branding stage; needs
# rsvg-convert and ImageMagick.
#
#   render.sh <branding dir> <output dir>
set -eu

src=$1/source
out=$2
work=$(mktemp -d)
cp "$src"/*.svg "$work/"
cd "$work"

# App icon "telamon": the full mark, and the mark drawn for 16 px where an
# icon is that small. Used by the app launcher and os-release's LOGO. The same
# files are also installed as "atlasos", the icon's name before Telamon, which
# the Launcher's dock button and Telamon Setup's welcome page still use
# (for one release).
mkdir -p "$out/icons/hicolor/scalable/apps" "$out/icons/hicolor/16x16/apps"
for name in telamon atlasos; do
	cp telamon-mark.svg "$out/icons/hicolor/scalable/apps/$name.svg"
	cp telamon-mark-16.svg "$out/icons/hicolor/16x16/apps/$name.svg"
done

# About page (kcm-about-distrorc's LogoPath)
mkdir -p "$out/pixmaps"
rsvg-convert -w 256 -h 256 telamon-mark.svg -o "$out/pixmaps/telamon-logo.png"

# Plasma splash: the mark, as SVG so it stays sharp at any scale
mkdir -p "$out/splash"
cp telamon-mark.svg "$out/splash/telamon.svg"

# Boot splash watermark: the lockup for dark backgrounds, at the size of the
# Fedora watermark it replaces (149x43). Plymouth draws it on black.
mkdir -p "$out/plymouth"
rsvg-convert -h 48 telamon-lockup-dark.svg -o "$out/plymouth/watermark.png"

# Wallpaper packages, one image per common screen size so Plasma never has
# to decode a 4K image to fill a smaller screen:
#   Telamon        wallpaper.jpg, cropped to fill (the desktop), and
#                  wallpaper-dark.jpg as its dark variant (images_dark), which
#                  Plasma shows instead while the colour scheme is dark
#   Telamon-Login  the same picture blurred and tinted with the logo's ink
#                  #1B1748, macOS style, so the clock, avatar and password
#                  field read clearly (login and lock screens). Blurred here,
#                  once, rather than live on every login.
sizes="1280x800 1366x768 1920x1080 1920x1200 2560x1440 2560x1600 3840x2160"

package() { # id, name
	mkdir -p "$out/wallpapers/$1/contents/images"
	printf '{\n    "KPackageStructure": "Wallpaper/Images",\n    "KPlugin": {\n        "Authors": [{ "Name": "Telamon OS" }],\n        "Id": "%s",\n        "Name": "%s"\n    }\n}\n' \
		"$1" "$2" >"$out/wallpapers/$1/metadata.json"
}

package Telamon Telamon
package Telamon-Login "Telamon Login"
for size in $sizes; do
	h=${size#*x}
	desktop=$out/wallpapers/Telamon/contents/images/$size.jpg
	magick "$1/wallpaper.jpg" -resize "$size^" -gravity center -extent "$size" \
		-quality 90 "$desktop"
	mkdir -p "$out/wallpapers/Telamon/contents/images_dark"
	magick "$1/wallpaper-dark.jpg" -resize "$size^" -gravity center -extent "$size" \
		-quality 90 "$out/wallpapers/Telamon/contents/images_dark/$size.jpg"
	# Blur at a tenth of the size, then scale back up: the same soft result
	# as a full-size blur, many times faster.
	magick "$desktop" -resize 10% -blur "0x$((h / 300 + 2))" -resize "$size!" \
		-fill "#1B1748" -colorize 35% \
		-quality 90 "$out/wallpapers/Telamon-Login/contents/images/$size.jpg"
done
# The first-run wizard of earlier images (plasma-setup) ignored the wallpaper setting and loads
# these two files, by name, from wallpapers/Default, which points here (the
# dark ones once Telamon Dark is chosen).
for size in 5120x2880 1440x2960; do
	magick "$1/wallpaper.jpg" -resize "$size^" -gravity center -extent "$size" \
		-quality 85 "$out/wallpapers/Telamon/contents/images/$size.jxl"
	magick "$1/wallpaper-dark.jpg" -resize "$size^" -gravity center -extent "$size" \
		-quality 85 "$out/wallpapers/Telamon/contents/images_dark/$size.jxl"
done
for p in Telamon Telamon-Login; do
	magick "$out/wallpapers/$p/contents/images/1920x1200.jpg" -resize 400x250 \
		"$out/wallpapers/$p/contents/screenshot.jpg"
done

rm -rf "$work"
find "$out" -type f | sort
