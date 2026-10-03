#!/usr/bin/env python3
"""Draws preview.png (Workshop, 256), poster.png (mod list, 512) and icon.png (32).
Same look as the other Konijima mods: dark background, yellow title, grey line art.
Run from anywhere: python3 tools/make-images.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "Contents/mods/VehicleEvents/42")
BG = (30, 34, 39)
LINE = (203, 208, 214)
DARK = (21, 25, 29)
YELLOW = (236, 178, 72)
BLUE = (70, 140, 220)
GREY = (150, 156, 164)
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
S = 4  # draw big then shrink, for smooth edges


def car(d, cx, cy, w, lw):
    """side view of a car centered on cx, wheels resting on cy"""
    h = w * 0.30
    x0, x1 = cx - w / 2, cx + w / 2
    body_top = cy - h
    # body
    d.rounded_rectangle([x0, body_top, x1, cy - w * 0.04], radius=w * 0.07, fill=DARK, outline=LINE, width=lw)
    # cabin
    cab = [(x0 + w * 0.22, body_top + lw / 2), (x0 + w * 0.34, body_top - w * 0.19),
           (x0 + w * 0.68, body_top - w * 0.19), (x0 + w * 0.82, body_top + lw / 2)]
    d.polygon(cab, fill=DARK, outline=LINE)
    d.line(cab, fill=LINE, width=lw, joint="curve")
    # windows
    d.polygon([(x0 + w * 0.29, body_top - lw), (x0 + w * 0.37, body_top - w * 0.15),
               (x0 + w * 0.49, body_top - w * 0.15), (x0 + w * 0.49, body_top - lw)], fill=BLUE)
    d.polygon([(x0 + w * 0.53, body_top - lw), (x0 + w * 0.53, body_top - w * 0.15),
               (x0 + w * 0.66, body_top - w * 0.15), (x0 + w * 0.75, body_top - lw)], fill=BLUE)
    # headlight
    d.ellipse([x1 - w * 0.07, body_top + h * 0.22, x1 - w * 0.02, body_top + h * 0.42], fill=YELLOW)
    # wheels
    r = w * 0.095
    for wx in (x0 + w * 0.22, x0 + w * 0.78):
        d.ellipse([wx - r, cy - r, wx + r, cy + r], fill=BG, outline=LINE, width=lw)
        d.ellipse([wx - r * 0.35, cy - r * 0.35, wx + r * 0.35, cy + r * 0.35], fill=LINE)
    return body_top - w * 0.19


def waves(d, cx, cy, r0, step, lw, count=3):
    """signal arcs above the car: the 'event' going out"""
    for i in range(count):
        r = r0 + step * i
        d.arc([cx - r, cy - r, cx + r, cy + r], start=225, end=315, fill=YELLOW, width=lw)


def centered(d, y, text, font, fill, size):
    w = d.textlength(text, font=font)
    d.text(((size - w) / 2, y), text, font=font, fill=fill)


def picture(size, title_lines, subtitle):
    big = size * S
    im = Image.new("RGB", (big, big), BG)
    d = ImageDraw.Draw(im)
    lw = max(S, int(big * 0.016))
    cx = big / 2
    roof = car(d, cx, big * 0.50, big * 0.56, lw)
    waves(d, cx, roof - big * 0.005, big * 0.06, big * 0.055, lw)
    tf = ImageFont.truetype(BOLD, int(big * 0.098))
    y = big * 0.60
    for line in title_lines:
        centered(d, y, line, tf, YELLOW, big)
        y += big * 0.12
    sf = ImageFont.truetype(REGULAR, int(big * 0.062))
    centered(d, y + big * 0.025, subtitle, sf, GREY, big)
    return im.resize((size, size), Image.LANCZOS)


def icon():
    big = 32 * S * 4
    im = Image.new("RGB", (big, big), BG)
    d = ImageDraw.Draw(im)
    lw = int(big * 0.06)
    roof = car(d, big / 2, big * 0.80, big * 0.86, lw)
    waves(d, big / 2, roof, big * 0.10, big * 0.12, lw, count=2)
    return im.resize((32, 32), Image.LANCZOS)


picture(256, ["Vehicle Events", "API"], "Lua events for cars").save(os.path.join(ROOT, "preview.png"))
picture(512, ["Vehicle Events", "API"], "Lua events for cars").save(os.path.join(MOD, "poster.png"))
icon().save(os.path.join(MOD, "icon.png"))
print("done")
