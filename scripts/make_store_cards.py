#!/usr/bin/env python3
"""Build App Store screenshot cards, share image and contact sheet.

    python scripts/make_store_cards.py [--raw docs/store/raw] [--set 6.9|6.5|all]
                                       [--only SCENE] [--check] [--icon PATH]

Deterministic: same raws in, same pixels out. Spec: docs/store/store-review.md s4.
Scenes missing from --raw fall back (with a warning) to docs/store/raw-before.
"""
import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BRAND = "Flight Dash"
BUILT = "2026-11-11"  # fixed so output is deterministic
ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "docs" / "store"
FONT_PATH = Path(__file__).resolve().parent / "fonts" / "Manrope[wght].ttf"
FALLBACK_BOLD = Path(r"C:\Windows\Fonts\segoeuib.ttf")
FALLBACK_MED = Path(r"C:\Windows\Fonts\seguisb.ttf")

W, H = 1320, 2868
W65, H65 = 1284, 2778
BG_TOP, BG_BOT = (0x0B, 0x0B, 0x0F), (0x15, 0x1A, 0x33)
ACCENTS = {
    "blue": (0x4D, 0x8F, 0xFF), "green": (0x33, 0xD6, 0x80), "orange": (0xFF, 0x9E, 0x26),
    "red": (0xFF, 0x47, 0x4D), "purple": (0xA8, 0x78, 0xFF), "cyan": (0x40, 0xC7, 0xEB),
}
DOT = "\u00b7"
FOOT_DEMO = f"Sample trip shown {DOT} Demo Mode"
FOOT_LIVE = f"Live data shown {DOT} times and traffic vary"
FOOT_MIX = f"Sample flight shown with live traffic {DOT} Demo Mode"

# (file, scene, accent, headline, subline, footer)
CARDS = [
    ("01-your-flight-live", "detail", "orange", "Your flight, live.",
     "Countdown, gates, and a forecast of when you'll land.", FOOT_DEMO),
    ("02-every-flight-one-glance", "flights", "blue", "Every flight,|one glance.",
     "Delays shown in the airport's own time zone.", FOOT_DEMO),
    ("03-who-is-around-you", "tracking", "cyan", "See who's|around you.",
     "Real aircraft on the map, in the air and on the ground.", FOOT_MIX),
    ("04-will-you-make-it", "connection", "red", "Will you|make it?",
     "Connections rated from live times, not the schedule.", FOOT_DEMO),
    ("05-passport", "passport", "purple", "A Passport that|writes itself.",
     "Miles, hours, airports, countries \u2014 from the flights you take.", FOOT_DEMO),
    ("06-airport-status", "airports", "green", "Airport status,|in plain English.",
     "FAA delays and decoded weather. No key needed.", FOOT_LIVE),
    ("07-taxiway", "airportTraffic", "cyan", "Who's ahead|on the taxiway.",
     "Ground traffic on satellite imagery, aircraft by aircraft.", FOOT_LIVE),
    ("08-every-minute-lost", "delays", "orange", "Every minute|lost, counted.",
     "On-time rate and worst delays, the way the DOT counts them.", FOOT_DEMO),
]

BANNED = re.compile(
    r"flighty|flightradar|flightaware|tripit|delta|united|american airlines|southwest|jetblue|"
    r"\bAI\b|real-time|\$\d|\bbest\b|#1|fastest", re.I)


def font(size, weight):
    if FONT_PATH.exists():
        f = ImageFont.truetype(str(FONT_PATH), size)
        f.set_variation_by_name(weight)
        return f
    print("WARNING: Manrope missing, using Segoe UI fallback", file=sys.stderr)
    fb = FALLBACK_BOLD if weight in (b"ExtraBold", b"Bold") else FALLBACK_MED
    return ImageFont.truetype(str(fb), size)


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    return img


def glow(img, center, radii, color, alpha=0.16, blur=180):
    mask = Image.new("L", img.size, 0)
    cx, cy = center
    rx, ry = radii
    ImageDraw.Draw(mask).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=round(255 * alpha))
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", img.size, color + (0,))
    layer.putalpha(mask)
    img.alpha_composite(layer)


def rr_mask(size, radius):
    m = Image.new("L", (size[0] * 2, size[1] * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] * 2 - 1, size[1] * 2 - 1], radius * 2, fill=255)
    return m.resize(size, Image.LANCZOS)


def framed_phone(canvas, raw, xy, size, radius, bezel=14, shadow_dy=36, shadow_blur=70):
    """Raw scaled to `size` at xy, rounded clip, bezel and shadow (canvas is RGBA)."""
    x, y = xy
    shot = raw.convert("RGB").resize(size, Image.LANCZOS)
    bw, bh = size[0] + 2 * bezel, size[1] + 2 * bezel
    brad = radius + bezel
    bx, by = x - bezel, y - bezel
    sm = Image.new("L", canvas.size, 0)
    sm.paste(rr_mask((bw, bh), brad).point(lambda v: int(v * 0.55)), (bx, by + shadow_dy))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh.putalpha(sm.filter(ImageFilter.GaussianBlur(shadow_blur)))
    canvas.alpha_composite(sh)
    S = 2
    b = Image.new("RGBA", (bw * S, bh * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(b)
    d.rounded_rectangle([0, 0, bw * S - 1, bh * S - 1], brad * S, fill=(0x1C, 0x1C, 0x24, 255),
                        outline=(0, 0, 0, 153), width=2 * S)
    d.rounded_rectangle([2 * S, 2 * S, bw * S - 1 - 2 * S, bh * S - 1 - 2 * S], (brad - 2) * S,
                        outline=(255, 255, 255, 26), width=2 * S)
    b = b.resize((bw, bh), Image.LANCZOS)
    canvas.paste(b, (bx, by), b)
    canvas.paste(shot, (x, y), rr_mask(size, radius))


def text_rgba(img, xy, s, f, fill, anchor="ls"):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, s, font=f, fill=fill, anchor=anchor)
    img.alpha_composite(layer)


def draw_tracked(img, xy, s, f, fill, tracking):
    x, y = xy
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill, anchor="ls")
        x += f.getlength(ch) + tracking
    img.alpha_composite(layer)


def wrap(s, f, maxw, balance=True):
    lines, cur = [], ""
    for word in s.split():
        t = (cur + " " + word).strip()
        if f.getlength(t) <= maxw or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    if balance and len(lines) > 1:  # balance: narrowest width that keeps the same line count (no orphans)
        n, lo = len(lines), 0
        hi = maxw
        while hi - lo > 4:
            mid = (lo + hi) // 2
            if len(wrap(s, f, mid, balance=False)) <= n:
                hi = mid
            else:
                lo = mid
        return wrap(s, f, hi, balance=False)
    return lines


def build_card(raw_img, accent, headline, subline, footer):
    img = gradient(W, H).convert("RGBA")
    glow(img, (660, 1900), (820, 1100), ACCENTS[accent])
    fh, fs, ff = font(104, b"ExtraBold"), font(44, b"Medium"), font(30, b"Medium")
    y = 300
    last = y
    for line in headline.split("|"):
        draw_tracked(img, (100, y), line, fh, (255, 255, 255, 255), -2)
        last = y
        y += 112
    sy = last + 36 + 44
    for line in wrap(subline, fs, 1120):
        text_rgba(img, (100, sy), line, fs, (255, 255, 255, 168))
        sy += 56
    framed_phone(img, raw_img, (173, 620), (974, 2116), 138)
    text_rgba(img, (W // 2, 2800), footer, ff, (255, 255, 255, 107), anchor="mm")
    return img.convert("RGB")


def find_raw(scene, raw_dir, fallback):
    p = raw_dir / f"{scene}.png"
    if p.exists():
        return p
    q = fallback / f"{scene}.png"
    if q.exists():
        print(f"WARNING: {scene}.png missing in {raw_dir}, using {fallback.name}", file=sys.stderr)
        return q
    return None


def build_share(raw_dir, fallback, icon):
    img = gradient(1200, 630).convert("RGBA")
    glow(img, (900, 400), (520, 420), ACCENTS["blue"], 0.22, 120)
    for scene, xy in (("detail", (700, 90)), ("tracking", (900, 160))):
        p = find_raw(scene, raw_dir, fallback)
        if p:
            framed_phone(img, Image.open(p), xy, (224, 488), 32, bezel=6, shadow_dy=14, shadow_blur=24)
    text_rgba(img, (80, 230), BRAND, font(76, b"ExtraBold"), (255, 255, 255, 255))
    fs = font(30, b"Medium")
    y = 292
    for line in wrap("Your flight, live \u2014 with a forecast that shows its working.", fs, 560):
        text_rgba(img, (80, y), line, fs, (255, 255, 255, 168))
        y += 42
    fc = font(24, b"Medium")
    x, cy = 80, y + 22
    for label in ("Free", "No account", "iPhone"):
        w = int(fc.getlength(label)) + 44
        lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(lay).rounded_rectangle([x, cy, x + w, cy + 52], 26, fill=(0x23, 0x23, 0x30, 255),
                                              outline=(255, 255, 255, 26), width=1)
        img.alpha_composite(lay)
        text_rgba(img, (x + w // 2, cy + 26), label, fc, (255, 255, 255, 204), anchor="mm")
        x += w + 16
    if icon:
        ic = Image.open(icon).convert("RGBA").resize((120, 120), Image.LANCZOS)
        img.paste(ic, (1000, 60), rr_mask((120, 120), 27))
    return img.convert("RGB")


def contact_sheet(files):
    tw, th = 264, 574
    cols, gx, gy, m = 4, 40, 70, 40
    rows = (len(files) + cols - 1) // cols
    cw = m * 2 + cols * tw + (cols - 1) * gx
    ch = m + 80 + rows * (th + gy) + m - 30
    img = Image.new("RGB", (cw, ch), (0x0B, 0x0B, 0x0F))
    d = ImageDraw.Draw(img)
    d.text((m, m + 30), f"Store cards {DOT} 6.9-inch {DOT} built {BUILT}", font=font(30, b"Bold"),
           fill=(255, 255, 255), anchor="ls")
    fl = font(20, b"Medium")
    for i, f in enumerate(files):
        r, c = divmod(i, cols)
        x, y = m + c * (tw + gx), m + 80 + r * (th + gy)
        img.paste(Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x, y + th + 30), f.stem, font=fl, fill=(153, 153, 155), anchor="ls")
    return img


def check(items):
    ok = True
    print(f"{'file':<52}{'size':<12}{'mode':<6}status")
    for p, size in items:
        im = Image.open(p)
        good = im.size == size and im.mode == "RGB"
        ok &= good
        print(f"{p.relative_to(ROOT).as_posix():<52}{str(im.size[0]) + 'x' + str(im.size[1]):<12}"
              f"{im.mode:<6}{'OK' if good else 'BAD'}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(STORE / "raw"))
    ap.add_argument("--set", default="all", choices=["6.9", "6.5", "all"])
    ap.add_argument("--only")
    ap.add_argument("--check", action="store_true", help="(always run at the end of a build)")
    ap.add_argument("--icon")
    a = ap.parse_args()
    raw_dir, fallback = Path(a.raw), STORE / "raw-before"
    out = {"6.9": STORE / "screenshots" / "6.9", "6.5": STORE / "screenshots" / "6.5"}
    for d in out.values():
        d.mkdir(parents=True, exist_ok=True)
    made = []
    for name, scene, accent, hl, sub, foot in CARDS:
        if a.only and a.only != scene:
            continue
        assert not BANNED.search(" ".join([hl, sub, foot])), f"banned word in {name}"
        p = find_raw(scene, raw_dir, fallback)
        if not p:
            print(f"WARNING: scene '{scene}' has no raw; skipping card {name}", file=sys.stderr)
            continue
        card = build_card(Image.open(p), accent, hl, sub, foot)
        if a.set in ("6.9", "all"):
            f = out["6.9"] / f"{name}.png"
            card.save(f, optimize=True)
            made.append((f, (W, H)))
        if a.set in ("6.5", "all"):
            f = out["6.5"] / f"{name}.png"
            card.resize((W65, H65), Image.LANCZOS).save(f, optimize=True)
            made.append((f, (W65, H65)))
    if not a.only:
        share = STORE / "share-image.png"
        build_share(raw_dir, fallback, a.icon).save(share, optimize=True)
        made.append((share, (1200, 630)))
        cards69 = sorted(out["6.9"].glob("[0-9][0-9]-*.png"))
        if cards69:
            contact_sheet(cards69).save(STORE / "contact-sheet.png", optimize=True)
    sys.exit(0 if check(made) else 1)


if __name__ == "__main__":
    main()
