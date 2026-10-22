#!/usr/bin/env python3
"""
make_icon.py — draws the app icon: a little beige monitor showing the
command that starts the game: a ">" prompt over "/advent" and a block cursor, in the app's
own pixel font (read from PixelFont.swift) with green phosphor glow.

    python3 Tools/make_icon.py      # needs Pillow and NumPy
"""
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
FONT_SWIFT = ROOT / "OpenAdventure/Terminal/PixelFont.swift"
OUT = ROOT / "OpenAdventure/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
LINES = [">", "/advent"]   # prompt, then the command with the cursor after it
N = 1024
SS = 2  # supersampling


def glyphs():
    table = {}
    for ch, art in re.findall(r'\("(\\.|.)", "([.#|]+)"\)', FONT_SWIFT.read_text()):
        ch = ch.encode().decode('unicode_escape') if ch.startswith('\\') else ch
        table[ch] = [row[:5].ljust(5, '.') for row in art.split('|')][:8]
    return table


def main():
    g = glyphs()
    W = N * SS
    # case: warm beige, lighter at the top
    y = np.linspace(0, 1, W)[:, None, None]
    top, bot = np.array([222, 208, 176]), np.array([190, 174, 140])
    img = Image.fromarray((top * (1 - y) + bot * y).repeat(W, 1).astype(np.uint8)).convert('RGBA')
    d = ImageDraw.Draw(img)

    # screen
    x0, y0, x1, y1 = 110 * SS, 150 * SS, 914 * SS, 800 * SS
    d.rounded_rectangle([x0 - 6 * SS, y0 - 6 * SS, x1 + 6 * SS, y1 + 6 * SS], radius=96 * SS, fill=(150, 136, 108, 255))
    d.rounded_rectangle([x0, y0, x1, y1], radius=90 * SS, fill=(20, 20, 18, 255))

    # text: two lines, left-aligned like a terminal, the whole block centred
    widest = max(len(l) for l in LINES[:-1] + [LINES[-1] + "#"])
    px = int((x1 - x0 - 130 * SS) / (widest * 7 - 1.5))
    py = int(px * 1.3)
    lead = 10 * py                      # one text row: 8 pixel rows plus a gap
    tw = (widest * 7 - 2) * px + int(px * 0.45)
    th = (len(LINES) - 1) * lead + 7 * py
    tx = (x0 + x1) // 2 - tw // 2
    ty = (y0 + y1) // 2 - th // 2
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    green = (110, 255, 140, 255)

    def pix(cx, cy):
        # Pixels smear a little to the right, as on the Apple II's screen,
        # which keeps one-pixel strokes bold.
        gd.rectangle([cx, cy, cx + int(px * 1.45) - 1, cy + py - 1], fill=green)

    for n, line in enumerate(LINES):
        y = ty + n * lead
        for i, ch in enumerate(line):
            rows = g.get(ch, g['?'])
            for r, row in enumerate(rows[:7]):
                for c, on in enumerate(row):
                    if on == '#':
                        pix(tx + (i * 7 + c) * px, y + r * py)
    # block cursor after the last line
    cx = tx + len(LINES[-1]) * 7 * px
    for r in range(7):
        for c in range(5):
            pix(cx + c * px, ty + (len(LINES) - 1) * lead + r * py)

    bloom = glow.filter(ImageFilter.GaussianBlur(14 * SS))
    a = np.asarray(bloom).astype(np.float32)
    a[..., 3] *= 1.6
    img.alpha_composite(Image.fromarray(a.clip(0, 255).astype(np.uint8)))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(1.2 * SS)))

    # scanlines across the glass
    scan = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    for yy in range(y0, y1, 8 * SS):
        sd.rectangle([x0, yy + 5 * SS, x1, yy + 7 * SS], fill=(0, 0, 0, 90))
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=90 * SS, fill=255)
    img.paste(Image.alpha_composite(img, scan), (0, 0), mask)

    # glass sheen
    sheen = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse([x0 - 200 * SS, y0 - 420 * SS, x1 - 120 * SS, y0 + 160 * SS], fill=(255, 255, 255, 20))
    img.paste(Image.alpha_composite(img, sheen.filter(ImageFilter.GaussianBlur(30 * SS))), (0, 0), mask)

    # badge strip and power lamp
    d = ImageDraw.Draw(img)
    d.rectangle([150 * SS, 860 * SS, 874 * SS, 880 * SS], fill=(160, 146, 116, 255))
    lamp = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(lamp).ellipse([840 * SS, 845 * SS, 872 * SS, 877 * SS], fill=(80, 255, 110, 255))
    img.alpha_composite(lamp.filter(ImageFilter.GaussianBlur(6 * SS)))
    img.alpha_composite(lamp)

    img.convert('RGB').resize((N, N), Image.LANCZOS).save(OUT)
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
