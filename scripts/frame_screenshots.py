#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==12.0.0"]
# ///
"""Puts raw screenshots into drawn device frames (architecture.md §2.7).

    scripts/frame_screenshots.py <raw folder> <output folder> [name...]

The kind of frame comes from the file name: `iphone-*` a phone, `ipad-*` a
tablet in the orientation of the image, `mac-*` a laptop for the main window,
and a window on a backdrop for anything small or for `mac-{mini,menu,settings,
pomodoro}-*`. Every frame is drawn here; none copies a manufacturer's artwork.
The output is a PNG with a transparent background, so it works on the site's
light and dark themes.
"""

import argparse
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

MAX_WIDTH = {"phone": 640, "tablet": 1500, "laptop": 1600, "window": 1200}

# Colors of the drawn hardware.
EDGE = (138, 141, 148, 255)
EDGE_LIGHT = (196, 199, 205, 255)
GLASS = (10, 10, 12, 255)
BODY_TOP = (208, 210, 214, 255)
BODY_BOTTOM = (168, 171, 176, 255)
BACKDROP_TOP = (92, 132, 196)
BACKDROP_BOTTOM = (58, 76, 136)


def rounded_mask(size, radius, supersample=4):
    """An antialiased mask of a rounded rectangle."""
    width, height = size
    big = Image.new("L", (width * supersample, height * supersample), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, width * supersample - 1, height * supersample - 1), radius * supersample, fill=255
    )
    return big.resize(size, Image.Resampling.LANCZOS)


def gradient(size, top, bottom):
    """A vertical gradient in RGBA."""
    width, height = size
    column = Image.new("RGBA", (1, height))
    for y in range(height):
        fraction = y / max(height - 1, 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * fraction) for a, b in zip(top[:3], bottom[:3], strict=True)) + (255,))
    return column.resize(size)


def filled(size, radius, color):
    """A rounded rectangle in one color, on transparency."""
    layer = Image.new("RGBA", size, color)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), rounded_mask(size, radius)))
    return layer


def shadowed(canvas, layer, position, blur, opacity, offset=(0, 0)):
    """Pastes `layer` onto `canvas` over a soft shadow of its shape."""
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    black = Image.new("RGBA", layer.size, (0, 0, 0, round(255 * opacity)))
    black.putalpha(ImageChops.multiply(black.getchannel("A"), layer.getchannel("A")))
    shadow.alpha_composite(black, (position[0] + offset[0], position[1] + offset[1]))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(layer, position)


def fit_width(image, width):
    if image.width <= width:
        return image
    height = round(image.height * width / image.width)
    return image.resize((width, height), Image.Resampling.LANCZOS)


def pad(image, margin):
    canvas = Image.new("RGBA", (image.width + 2 * margin, image.height + 2 * margin), (0, 0, 0, 0))
    canvas.alpha_composite(image, (margin, margin))
    return canvas


def phone(shot):
    """A phone with a metal band, black bezel, and a pill-shaped camera cutout.
    Sizes are relative to the screen's width (a 3x image of a 402 pt screen)."""
    unit = shot.width / 402
    bezel, band = round(11 * unit), round(4 * unit)
    radius = round(55 * unit)
    width = shot.width + 2 * (bezel + band)
    height = shot.height + 2 * (bezel + band)
    margin = round(10 * unit)
    canvas = Image.new("RGBA", (width + 2 * margin, height + 2 * margin), (0, 0, 0, 0))

    # Side buttons stick out behind the band.
    draw = ImageDraw.Draw(canvas)
    button = round(2.5 * unit)
    for x, top, length in (
        (margin - button, 140, 30),
        (margin - button, 190, 58),
        (margin - button, 262, 58),
        (margin + width - 1, 214, 92),
    ):
        y = margin + round(top * unit)
        draw.rounded_rectangle((x, y, x + 2 * button, y + round(length * unit)), button, fill=EDGE)

    outer = radius + bezel + band
    body = filled((width, height), outer, EDGE)
    body.alpha_composite(filled((width - 2, height - 2), outer - 1, EDGE_LIGHT), (1, 1))
    body.alpha_composite(filled((width - 2 * band, height - 2 * band), outer - band, GLASS), (band, band))
    screen = shot.convert("RGBA")
    screen.putalpha(rounded_mask(shot.size, radius))
    body.alpha_composite(screen, (band + bezel, band + bezel))

    # The camera cutout.
    pill = (round(126 * unit), round(37 * unit))
    pill_layer = filled(pill, pill[1] // 2, (0, 0, 0, 255))
    body.alpha_composite(pill_layer, ((width - pill[0]) // 2, band + bezel + round(11 * unit)))
    canvas.alpha_composite(body, (margin, margin))
    return fit_width(canvas, MAX_WIDTH["phone"])


def tablet(shot):
    """A tablet with an even black bezel and a thin metal edge; the camera
    sits on the long side above a landscape screen, and at the top in portrait."""
    unit = max(shot.size) / 1376
    bezel, band = round(22 * unit), round(3 * unit)
    radius = round(22 * unit)
    width = shot.width + 2 * (bezel + band)
    height = shot.height + 2 * (bezel + band)
    outer = radius + bezel + band
    body = filled((width, height), outer, EDGE)
    body.alpha_composite(filled((width - 2 * band, height - 2 * band), outer - band, GLASS), (band, band))
    screen = shot.convert("RGBA")
    screen.putalpha(rounded_mask(shot.size, radius))
    body.alpha_composite(screen, (band + bezel, band + bezel))
    camera = round(5 * unit)
    x, y = width // 2, band + bezel // 2
    ImageDraw.Draw(body).ellipse((x - camera, y - camera, x + camera, y + camera), fill=(30, 32, 38, 255))
    return fit_width(pad(body, round(6 * unit)), MAX_WIDTH["tablet"])


def laptop(shot):
    """The window on a backdrop inside a laptop's screen, above a slim base.
    Sizes are relative to the window's width (a 2x image of 1100 pt)."""
    unit = shot.width / 2200
    inset_x, inset_y = round(110 * unit), round(84 * unit)
    bezel, band = round(30 * unit), round(4 * unit)
    radius = round(26 * unit)
    screen_size = (shot.width + 2 * inset_x, shot.height + 2 * inset_y)
    screen = gradient(screen_size, BACKDROP_TOP, BACKDROP_BOTTOM)
    shadowed(screen, shot.convert("RGBA"), (inset_x, inset_y), round(36 * unit), 0.45, (0, round(16 * unit)))
    screen.putalpha(rounded_mask(screen_size, radius))

    lid_size = (screen_size[0] + 2 * (bezel + band), screen_size[1] + 2 * (bezel + band))
    outer = radius + bezel + band
    lid = filled(lid_size, outer, EDGE)
    lid.alpha_composite(filled((lid_size[0] - 2 * band, lid_size[1] - 2 * band), outer - band, GLASS), (band, band))
    lid.alpha_composite(screen, (band + bezel, band + bezel))

    base_height, overhang = round(46 * unit), round(120 * unit)
    width = lid_size[0] + 2 * overhang
    height = lid_size[1] + base_height
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(lid, (overhang, 0))
    base = gradient((width, base_height), BODY_TOP, BODY_BOTTOM)
    base.putalpha(rounded_mask((width, base_height), base_height // 2))
    # The top of the base is straight; only its lower corners are round.
    ImageDraw.Draw(base).rectangle((0, 0, width, base_height // 3), fill=BODY_TOP)
    canvas.alpha_composite(base, (0, lid_size[1]))
    notch = (round(300 * unit), round(16 * unit))
    notch_layer = filled((notch[0], notch[1] * 2), notch[1], (150, 153, 158, 255)).crop((0, notch[1], *((notch[0], notch[1] * 2))))
    canvas.alpha_composite(notch_layer, ((width - notch[0]) // 2, lid_size[1]))
    return fit_width(pad(canvas, round(10 * unit)), MAX_WIDTH["laptop"])


def window(shot):
    """A small window on a rounded backdrop, for what a laptop would dwarf."""
    unit = 2  # raw captures are 2x
    margin = 36 * unit
    size = (shot.width + 2 * margin, shot.height + 2 * margin)
    backdrop = gradient(size, BACKDROP_TOP, BACKDROP_BOTTOM)
    shadowed(backdrop, shot.convert("RGBA"), (margin, margin), 14 * unit, 0.45, (0, 6 * unit))
    backdrop.putalpha(rounded_mask(size, 16 * unit))
    return fit_width(backdrop, MAX_WIDTH["window"])


def frame_kind(name):
    if name.startswith("iphone"):
        return "phone"
    if name.startswith("ipad"):
        return "tablet"
    if re.match(r"mac-(mini|menu|settings|pomodoro)", name):
        return "window"
    return "laptop"


FRAMES = {"phone": phone, "tablet": tablet, "laptop": laptop, "window": window}


def frame_file(source, output):
    framed = FRAMES[frame_kind(source.stem)](Image.open(source).convert("RGBA"))
    framed.save(output / source.name, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raw", type=Path, help="the folder of raw images")
    parser.add_argument("output", type=Path, help="the folder for the framed images")
    parser.add_argument("names", nargs="*", help="the images to frame; default all")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for source in sorted(args.raw.glob("*.png")):
        if not args.names or source.stem in args.names:
            frame_file(source, args.output)
            print(source.stem)


if __name__ == "__main__":
    main()
