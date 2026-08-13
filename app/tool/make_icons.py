#!/usr/bin/env python3
"""Builds the launcher icon and every size Android and iOS ask for.

The icon is the three things the app is: the Retro script lifted straight from
the Retro Recompilation logo, AMIGA in the wordmark's chrome blue, and the boot
tick. The tick is redrawn here from the same points and colour bands as
lib/widgets/amiga_logo.dart rather than traced from a bitmap, so the icon and
the tick the app draws on screen cannot drift apart.

    python3 tool/make_icons.py

Run from the app directory. Overwrites the mipmaps, the iOS icon set and
assets/images/app_icon.png.
"""

from __future__ import annotations

import os
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(HERE, "assets", "images", "retro_recomp_logo.png")
FONT = "/usr/share/fonts/liberation/LiberationSans-Bold.ttf"

SIZE = 1024

# Deep and dark, so the wording and the tick carry the icon rather than the
# background. Matches the launcher's own backdrop.
BG_TOP = (18, 10, 32)
BG_BOTTOM = (5, 4, 10)

# The wordmark's blue, top to bottom: white highlight into deep blue.
CHROME = [
    (232, 244, 255),
    (150, 205, 250),
    (56, 120, 220),
    (26, 60, 160),
    (120, 180, 240),
]

# The boot tick, from AmigaLogo's painter.
TICK_BANDS = [
    (0xFE, 0x38, 0x14),
    (0xFE, 0x88, 0x01),
    (0xFE, 0xD8, 0x02),
    (0xEE, 0xEF, 0x00),
    (0x5C, 0xE4, 0x68),
    (0x17, 0xCE, 0x76),
]
TICK_OUTLINE = (0x18, 0x2C, 0x48)
TICK_POINTS = [
    (0.72, 0.04),
    (0.99, 0.16),
    (0.40, 0.96),
    (0.02, 0.56),
    (0.16, 0.40),
    (0.41, 0.66),
]


def vertical_gradient(size, colours):
    """A strip of [colours] blended top to bottom, at [size]."""
    width, height = size
    grad = Image.new("RGB", (1, height))
    pixels = grad.load()
    steps = len(colours) - 1
    for y in range(height):
        position = y / max(1, height - 1) * steps
        index = min(int(position), steps - 1)
        blend = position - index
        start, end = colours[index], colours[index + 1]
        pixels[0, y] = tuple(
            int(start[c] + (end[c] - start[c]) * blend) for c in range(3)
        )
    return grad.resize((width, height))


def background():
    canvas = vertical_gradient((SIZE, SIZE), [BG_TOP, BG_BOTTOM]).convert("RGBA")
    # A glow behind the artwork, so the icon is not a flat rectangle at small
    # sizes. Blurred hard: at 48 pixels it reads as depth, not as a shape.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((60, 250, SIZE - 60, SIZE - 120), fill=(120, 40, 190, 120))
    draw.ellipse((200, 520, SIZE - 200, SIZE - 60), fill=(40, 120, 220, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    return Image.alpha_composite(canvas, glow)


def retro_script(width):
    """The Retro script, cut out of the logo.

    Cut rather than redrawn: it is a brush script with a gradient through it,
    and anything traced would look like an imitation of the logo sitting next
    to the real one everywhere else in the app.
    """
    logo = Image.open(LOGO).convert("RGBA")
    # Bounds found from the warm pixels of the top band; the purple bracket
    # rules at either end are left outside the crop.
    script = logo.crop((168, 0, 578, 92))

    # The bracket rules that run either side of the script in the logo poke
    # into the crop. Every pixel of the script itself is warm - pink through
    # to orange - so anything bluer than it is red is one of the rules.
    pixels = script.load()
    for y in range(script.height):
        for x in range(script.width):
            r, g, b, a = pixels[x, y]
            if a and b > r:
                pixels[x, y] = (r, g, b, 0)

    height = round(script.height * width / script.width)
    return script.resize((width, height), Image.LANCZOS)


def chrome_text(text, width, height):
    """[text] in the wordmark's blue, with the dark outline it has."""
    # Sized by trial: fit the glyphs to the box rather than guessing a point
    # size, since the box is what the layout knows about.
    size = 10
    font = ImageFont.truetype(FONT, size)
    while True:
        probe = ImageFont.truetype(FONT, size + 4)
        box = probe.getbbox(text)
        if box[2] - box[0] > width or box[3] - box[1] > height:
            break
        size += 4
        font = probe

    box = font.getbbox(text)
    pad = 18
    layer = Image.new("RGBA", (box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2))
    draw = ImageDraw.Draw(layer)
    draw.text((pad - box[0], pad - box[1]), text, font=font, fill=(255, 255, 255, 255))

    # The fill is a gradient masked by the glyphs; the outline is the same
    # glyphs grown and stamped underneath.
    mask = layer.split()[3]
    fill = vertical_gradient(layer.size, CHROME).convert("RGBA")
    fill.putalpha(mask)

    outline = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    grown = mask.filter(ImageFilter.MaxFilter(9))
    outline.paste(TICK_OUTLINE + (255,), (0, 0), grown)
    return Image.alpha_composite(outline, fill)


def tick(height):
    """The boot tick, drawn from the same points as the widget."""
    width = round(height * 1.1)
    scale = 4  # supersampled, because the outline is thin and diagonal
    layer = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    points = [
        (x * width * scale, y * height * scale) for x, y in TICK_POINTS
    ]

    shape = Image.new("L", layer.size, 0)
    ImageDraw.Draw(shape).polygon(points, fill=255)

    fill = vertical_gradient(layer.size, TICK_BANDS).convert("RGBA")
    fill.putalpha(shape)

    outline = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(outline).polygon(
        points, fill=None, outline=TICK_OUTLINE + (255,), width=6 * scale
    )
    stamped = Image.alpha_composite(fill, outline)
    return stamped.resize((width, height), Image.LANCZOS)


def artwork(width):
    """The three pieces stacked, on transparent, [width] across."""
    layer = Image.new("RGBA", (width, width), (0, 0, 0, 0))

    script = retro_script(round(width * 0.80))
    amiga = chrome_text("AMIGA", round(width * 0.68), round(width * 0.19))
    mark = tick(round(width * 0.46))

    # Centred as a block rather than pinned to the top, so the icon does not
    # sit high in its own square.
    stack = script.height + amiga.height + mark.height + round(width * 0.05)
    top = max(0, (width - stack) // 2)
    layer.alpha_composite(script, ((width - script.width) // 2, top))

    top += script.height + round(width * 0.015)
    layer.alpha_composite(amiga, ((width - amiga.width) // 2, top))

    top += amiga.height + round(width * 0.035)
    layer.alpha_composite(mark, ((width - mark.width) // 2, top))
    return layer


def master():
    canvas = background()
    art = artwork(round(SIZE * 0.86))
    canvas.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.width) // 2))
    return canvas


def foreground():
    """The adaptive icon's foreground layer.

    Everything sits inside the middle two-thirds. Android masks adaptive icons
    to whatever shape the launcher fancies and can zoom them, so artwork that
    fills the square gets its edges eaten - which is what happened to the old
    icon, and why it arrived as a cropped tick on a white plate.
    """
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    art = artwork(round(SIZE * 0.62))
    layer.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.width) // 2))
    return layer


def rounded(image, radius_fraction=0.22):
    mask = Image.new("L", image.size, 0)
    radius = round(image.width * radius_fraction)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1), radius=radius, fill=255
    )
    out = image.copy()
    out.putalpha(mask)
    return out


def main():
    icon = master()
    fore = foreground()

    icon.save(os.path.join(HERE, "assets", "images", "app_icon.png"))

    res = os.path.join(HERE, "android", "app", "src", "main", "res")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    # 108dp foreground at each density.
    fores = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, px in legacy.items():
        folder = os.path.join(res, f"mipmap-{density}")
        os.makedirs(folder, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher.png")
        )
        rounded(icon.resize((px, px), Image.LANCZOS), 0.5).save(
            os.path.join(folder, "ic_launcher_round.png")
        )
        fore.resize((fores[density],) * 2, Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_foreground.png")
        )

    ios = os.path.join(HERE, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in sizes.items():
        # iOS applies its own mask, so these stay square and opaque.
        icon.convert("RGB").resize((px, px), Image.LANCZOS).save(
            os.path.join(ios, name)
        )

    loose = os.path.join(HERE, "ios", "Runner", "LooseIcons")
    os.makedirs(loose, exist_ok=True)
    for name, source in {
        "AppIcon60x60@2x.png": "Icon-App-60x60@2x.png",
        "AppIcon60x60@3x.png": "Icon-App-60x60@3x.png",
        "AppIcon76x76@2x.png": "Icon-App-76x76@2x.png",
        "AppIcon83.5x83.5@2x.png": "Icon-App-83.5x83.5@2x.png",
        "AppIcon1024x1024.png": "Icon-App-1024x1024@1x.png",
    }.items():
        shutil.copyfile(os.path.join(ios, source), os.path.join(loose, name))

    print("icons written")


if __name__ == "__main__":
    main()
