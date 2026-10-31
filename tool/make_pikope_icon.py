#!/usr/bin/env python3
"""Build a sharp PikoPe launcher icon from the brand logo.

    python tool/make_pikope_icon.py

Writes assets/icon/app_icon.png (1024) and Android mipmap/drawable layers.
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
ICON_DIR = os.path.join(ROOT, "assets", "icon")

# Prefer the high-res horizontal mark; fall back to in-app assets.
SOURCES = [
    os.path.join(ROOT, "landing", "assets", "pikope_logo.png"),
    os.path.join(ICON_DIR, "app_icon.jpg"),
    os.path.join(ROOT, "assets", "images", "pikope_logo.png"),
]

BG = (30, 30, 33, 255)  # #1E1E21 — matches launch_background
S = 1024
SAFE = 0.72  # logo fits adaptive-icon safe zone (with xml inset)


def load_logo() -> Image.Image:
    for path in SOURCES:
        if os.path.isfile(path):
            img = Image.open(path).convert("RGBA")
            print(f"source: {path} ({img.size[0]}x{img.size[1]})")
            return img
    raise SystemExit("No logo source found. Add landing/assets/pikope_logo.png")


def fit_center(layer: Image.Image, logo: Image.Image, scale: float) -> None:
    w, h = logo.size
    target = int(S * scale)
    ratio = min(target / w, target / h)
    nw, nh = max(1, int(w * ratio)), max(1, int(h * ratio))
    resized = logo.resize((nw, nh), Image.LANCZOS)
    resized = resized.filter(ImageFilter.UnsharpMask(radius=1.2, percent=140, threshold=2))
    x, y = (S - nw) // 2, (S - nh) // 2
    layer.paste(resized, (x, y), resized)


def solid_square(color: tuple[int, ...]) -> Image.Image:
    return Image.new("RGBA", (S, S), color)


def legacy_rounded(full: Image.Image) -> Image.Image:
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
    out = full.copy()
    out.putalpha(mask)
    return out


def save(img: Image.Image, path: str, size: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    logo = load_logo()

    full = solid_square(BG)
    fit_center(full, logo, 0.78)
    full_rgb = full.convert("RGB")
    save(full_rgb, os.path.join(ICON_DIR, "app_icon.png"), S)

    fg = solid_square((0, 0, 0, 0))
    fit_center(fg, logo, SAFE)
    save(fg, os.path.join(ICON_DIR, "app_icon_foreground.png"), S)

    legacy = legacy_rounded(full)

    for name, size in (
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ):
        save(legacy, os.path.join(RES, f"mipmap-{name}", "ic_launcher.png"), size)

    for name, size in (
        ("mdpi", 108),
        ("hdpi", 162),
        ("xhdpi", 216),
        ("xxhdpi", 324),
        ("xxxhdpi", 432),
    ):
        save(fg, os.path.join(RES, f"drawable-{name}", "ic_launcher_foreground.png"), size)

    print("PikoPe launcher icons updated.")


if __name__ == "__main__":
    main()
