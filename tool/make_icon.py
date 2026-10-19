#!/usr/bin/env python3
"""Draws the launcher icon (an 8-ball and cue on felt) and writes the Android
mipmaps, the adaptive-icon layers and a 1024px master.

    python3 tool/make_icon.py
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), '..')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
S = 2048  # work at 2x, scale down for smooth edges


def background():
    """Teal felt, brighter under the ball, darker at the edges."""
    img = Image.new('RGB', (S, S))
    px = img.load()
    cx, cy = S * 0.46, S * 0.42
    inner, outer = (26, 190, 196), (4, 58, 78)
    for y in range(S):
        for x in range(S):
            t = min(1.0, math.hypot(x - cx, y - cy) / (S * 0.78))
            t = t * t * (3 - 2 * t)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


def foreground(scale=1.0):
    """Cue and 8-ball on a transparent layer; [scale] shrinks them about the centre."""
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    c = S / 2

    def P(x, y):  # design coordinates 0..1 -> pixels, scaled about the centre
        return (c + (x - 0.5) * S * scale, c + (y - 0.5) * S * scale)

    R = 0.30 * S * scale
    bx, by = P(0.47, 0.53)

    # Soft shadow under the ball.
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [bx - R * 0.95 + R * 0.16, by - R * 0.55 + R * 0.72, bx + R * 0.95 + R * 0.16, by + R * 0.55 + R * 0.72],
        fill=(0, 20, 30, 170))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(R * 0.14)))

    # Cue: a tapered stick from the lower left towards the upper right, behind the ball.
    cue = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(cue)
    (x0, y0), (x1, y1) = P(0.02, 0.95), P(0.93, 0.13)
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)

    def quad(t0, t1, w0, w1, color):
        ax, ay = x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0
        bx2, by2 = x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1
        w0, w1 = w0 * S * scale, w1 * S * scale
        d.polygon([(ax + nx * w0, ay + ny * w0), (bx2 + nx * w1, by2 + ny * w1),
                   (bx2 - nx * w1, by2 - ny * w1), (ax - nx * w0, ay - ny * w0)], fill=color)

    quad(0.00, 0.30, 0.036, 0.031, (58, 30, 18, 255))      # butt
    quad(0.30, 0.33, 0.031, 0.030, (232, 232, 236, 255))   # ring
    quad(0.33, 0.945, 0.030, 0.019, (226, 178, 106, 255))  # shaft
    quad(0.33, 0.945, 0.011, 0.007, (246, 214, 150, 255))  # shaft highlight
    quad(0.945, 0.975, 0.019, 0.018, (240, 240, 240, 255))  # ferrule
    quad(0.975, 1.00, 0.018, 0.016, (58, 120, 214, 255))   # chalked tip
    cue_shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cue_shadow.paste((0, 20, 30, 130), mask=cue.getchannel('A'))
    layer.alpha_composite(ImageChops.offset(cue_shadow.filter(ImageFilter.GaussianBlur(S * 0.008)), int(S * 0.012), int(S * 0.016)))
    layer.alpha_composite(cue)

    # The ball: black sphere shaded from a light at the upper left.
    ball = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    bp = ball.load()
    lx, ly = bx - R * 0.38, by - R * 0.42
    for y in range(int(by - R) - 1, int(by + R) + 2):
        for x in range(int(bx - R) - 1, int(bx + R) + 2):
            dist = math.hypot(x - bx, y - by)
            if dist > R + 1 or not (0 <= x < S and 0 <= y < S):
                continue
            a = max(0.0, min(1.0, R + 0.5 - dist))
            lit = max(0.0, 1 - math.hypot(x - lx, y - ly) / (R * 1.55))
            rim = (dist / R) ** 6
            v = 14 + 62 * lit ** 1.6 + 26 * rim * max(0.0, (y - by) / R)
            bp[x, y] = (int(v), int(v), int(v * 1.08) + 2, int(255 * a))
    layer.alpha_composite(ball)

    # White number disc with the 8.
    d = ImageDraw.Draw(layer)
    dr = R * 0.47
    dx, dy = bx - R * 0.10, by - R * 0.12
    d.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=(250, 250, 250, 255))
    font = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'Orbitron.ttf'), int(dr * 1.5))
    try:
        font.set_variation_by_axes([640])
    except Exception:
        pass
    box = d.textbbox((0, 0), '8', font=font)
    d.text((dx - (box[0] + box[2]) / 2, dy - (box[1] + box[3]) / 2), '8', font=font, fill=(16, 16, 20, 255),
           stroke_width=int(dr * 0.012), stroke_fill=(16, 16, 20, 255))

    # Glossy highlights.
    gloss = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(gloss)
    g.ellipse([bx - R * 0.70, by - R * 0.80, bx - R * 0.14, by - R * 0.42], fill=(255, 255, 255, 150))
    g.ellipse([bx + R * 0.30, by + R * 0.52, bx + R * 0.62, by + R * 0.70], fill=(255, 255, 255, 40))
    layer.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(R * 0.07)))
    return layer


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)


bg = background()
full = bg.convert('RGBA')
full.alpha_composite(foreground())
save(full.convert('RGB'), os.path.join(ROOT, 'assets', 'icon', 'app_icon.png'), 1024)

# Legacy launcher icons (pre-Android 8): rounded square.
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
legacy = full.copy()
legacy.putalpha(mask)
for name, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    save(legacy, os.path.join(RES, f'mipmap-{name}', 'ic_launcher.png'), size)

# Adaptive icon (Android 8+): the launcher crops to the middle 2/3, so the
# drawing is scaled into that safe zone.
fg = foreground(scale=0.66)
for name, size in (('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)):
    save(fg, os.path.join(RES, f'mipmap-{name}', 'ic_launcher_foreground.png'), size)
    save(bg, os.path.join(RES, f'mipmap-{name}', 'ic_launcher_background.png'), size)
os.makedirs(os.path.join(RES, 'mipmap-anydpi-v26'), exist_ok=True)
with open(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
print('icon written')
