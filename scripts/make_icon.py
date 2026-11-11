#!/usr/bin/env python3
"""Render the FlightDeck app icon.

Dev-only tooling, not an app dependency:  pip install pillow
Run from anywhere:                         python3 scripts/make_icon.py

Writes
  FlightDeck/Assets.xcassets/AppIcon.appiconset/AppIcon.png   1024x1024, opaque RGB
  docs/screenshots/icon.png                                   256 px copy for docs
  docs/screenshots/icon-preview-180.png / -60.png             legibility checks

The artwork is the app's own: the `AircraftGlyph` silhouette that every map
in the app draws (outline copied from AircraftGlyph.swift), flying north-east
over the dashed great-circle arc the route maps draw, on the app's navy
gradient. The old icon was the arc alone, which read as an empty square at
home-screen size; the silhouette is what makes it an aircraft app at 60 px.

Everything is drawn at 4x and downsampled, which is the cheap way to get
antialiased edges out of PIL's polygon fill.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "FlightDeck" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
DOCS = ROOT / "docs" / "screenshots"

SIZE = 1024
SS = 4                      # supersampling factor
W = SIZE * SS

TOP = (0x0B, 0x0B, 0x0F)    # Theme.background
BOTTOM = (0x1B, 0x24, 0x50)
ACCENT = (0x4D, 0x8F, 0xFF)  # Theme.accent

# AircraftGlyph.halfOutline, verbatim: right half, nose at (0, -1), tail at
# y = +1. Mirrored below for the left side, exactly as `path(size:)` does.
HALF_OUTLINE = [
    (0.00, -1.00),   # nose
    (0.085, -0.60),  # forward fuselage
    (0.11, -0.10),   # wing root, leading edge
    (0.78, 0.30),    # wing tip, leading edge
    (0.78, 0.44),    # wing tip, trailing edge
    (0.14, 0.30),    # wing root, trailing edge
    (0.11, 0.64),    # aft fuselage
    (0.34, 0.88),    # stabiliser tip, leading edge
    (0.34, 0.99),    # stabiliser tip, trailing edge
    (0.09, 0.90),    # stabiliser root
    (0.07, 1.00),    # tail cone
]


def s(v):
    """Icon pixels -> supersampled canvas pixels."""
    return v * SS


def gradient():
    img = Image.new("RGB", (W, W))
    draw = ImageDraw.Draw(img)
    for y in range(W):
        t = y / (W - 1)
        colour = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        draw.line([(0, y), (W, y)], fill=colour)
    return img


def bezier(p0, p1, p2, steps=2000):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return pts


def dashed_arc(img):
    """The route arc: a quadratic Bézier from (-60, 560) through an apex at
    (512, 330) to (1084, 560), stroked 22 px with 58/44 dashes."""
    start, end = (-60, 560), (1084, 560)
    apex = (512, 330)
    # A quadratic's midpoint is (p0 + 2c + p2) / 4, so solve for the control
    # point that puts the curve's midpoint on the apex.
    ctrl = (2 * apex[0] - (start[0] + end[0]) / 2, 2 * apex[1] - (start[1] + end[1]) / 2)
    pts = bezier(start, ctrl, end)

    # Each dash is stamped as a run of overlapping discs rather than drawn
    # with `ImageDraw.line`: PIL's wide polylines leave hairline gaps between
    # short segments, which showed up as hatching across every dash. Discs
    # also give the round caps the in-app StrokeStyle draws, for free.
    draw = ImageDraw.Draw(img)
    dash, gap, width = 58, 44, 22
    r = s(width) / 2
    # Round caps add half a width at each end, so the stamped centre run is
    # shortened (and the gap lengthened) by one width to keep 58 on / 44 off.
    run, space = dash - width, gap + width
    travelled, on = 0.0, True
    for a, b in zip(pts, pts[1:]):
        travelled += math.dist(a, b)
        if on:
            x, y = s(b[0]), s(b[1])
            draw.ellipse([x - r, y - r, x + r, y + r], fill=ACCENT)
        if travelled >= (run if on else space):
            on, travelled = not on, 0.0
    return img


def aircraft_polygon(centre, fuselage, heading_deg):
    """The glyph as a polygon in icon pixels. `fuselage` is nose-to-tail
    length; heading is clockwise from north, as on a map."""
    half = fuselage / 2
    pts = HALF_OUTLINE + [(-x, y) for x, y in reversed(HALF_OUTLINE[1:])]
    a = math.radians(heading_deg)
    cos_a, sin_a = math.cos(a), math.sin(a)
    out = []
    for x, y in pts:
        x, y = x * half, y * half
        # Screen coordinates (y down): rotating clockwise by `a`.
        out.append((centre[0] + x * cos_a - y * sin_a,
                    centre[1] + x * sin_a + y * cos_a))
    return out


def halo(img, centre, radius, alpha):
    """Soft accent glow under the aircraft — the one the in-app map draws
    under the user's own flight."""
    layer = Image.new("L", img.size, 0)
    ImageDraw.Draw(layer).ellipse(
        [s(centre[0] - radius * 0.55), s(centre[1] - radius * 0.55),
         s(centre[0] + radius * 0.55), s(centre[1] + radius * 0.55)],
        fill=round(255 * alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(s(radius) * 0.32))
    glow = Image.new("RGB", img.size, ACCENT)
    return Image.composite(glow, img, layer)


def render():
    img = gradient()
    centre = (512, 500)
    img = halo(img, centre, radius=300, alpha=0.18)
    img = dashed_arc(img)

    poly = [(s(x), s(y)) for x, y in aircraft_polygon(centre, fuselage=560, heading_deg=45)]

    # Separation stroke: the background colour at 55% over whatever is
    # beneath, so the silhouette lifts off the arc where they cross.
    outline = Image.new("L", img.size, 0)
    ImageDraw.Draw(outline).line(poly + [poly[0]], fill=round(255 * 0.55), width=s(10) * 2, joint="curve")
    img = Image.composite(Image.new("RGB", img.size, TOP), img, outline)

    ImageDraw.Draw(img).polygon(poly, fill=(255, 255, 255))

    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main():
    icon = render()
    ICON.parent.mkdir(parents=True, exist_ok=True)
    icon.save(ICON, optimize=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    icon.resize((256, 256), Image.LANCZOS).save(DOCS / "icon.png", optimize=True)
    for px in (180, 60):
        icon.resize((px, px), Image.LANCZOS).save(DOCS / f"icon-preview-{px}.png", optimize=True)
    print(f"wrote {ICON.relative_to(ROOT)} ({icon.size[0]}x{icon.size[1]}, {icon.mode})")


if __name__ == "__main__":
    main()
