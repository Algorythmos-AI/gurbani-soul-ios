#!/usr/bin/env python3
"""Frame App Store screenshots in the "Night" style: warm ink, a large device, one serif headline.

    uv run --with pillow python3 ios/AppStore/compose_store_shots_v2.py --captures <dir> [--out <dir>]

Reads captions_v2.json (listing order). Each entry: shot (capture file stem), headline, optional
sub (one line) and hero (true for the first frame: larger headline + the trust line). Writes RGB
PNGs at Apple's sizes and a contact sheet. Scripture on every frame is the app's own rendering;
captions are English only and restate claims already in docs/ios/app-store-listing.md.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SERIF = ROOT / "ios" / "App" / "Resources" / "SourceSerif4.ttf"
CAPTIONS = HERE / "captions_v2.json"
CONTACT = HERE / "contact-sheet"

# Brand tokens (docs/brand/tokens.json): warm ink, paper, Soul Gold. Gold is a fill or a hairline
# here, never small text; headline text is paper on ink (≥ 12:1).
INK_TOP = (0x2B, 0x22, 0x1B)
INK_BOTTOM = (0x0E, 0x0C, 0x0A)
PAPER = (0xF6, 0xEF, 0xE2)
MUTED = (0xC9, 0xBC, 0xA6)
GOLD_FILL = (0xFF, 0xBC, 0x0D)
GOLD_SOFT = (0xF0, 0x9A, 0x00)
BEZEL = (0x3B, 0x32, 0x29)

SIZES = {"iphone-6.9": (1320, 2868), "ipad-13": (2064, 2752)}


def serif(size, weight):
    f = ImageFont.truetype(str(SERIF), size)
    try:
        f.set_variation_by_axes([weight])
    except (OSError, AttributeError):
        pass
    return f


def relative_luminance(rgb) -> float:
    def ch(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b) -> float:
    la, lb = sorted((relative_luminance(a), relative_luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def wrap(draw, text, font, width, max_lines=2):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=font) <= width:
            cur = trial
        else:
            lines.append(cur); cur = w
    lines.append(cur)
    if len(lines) > max_lines:
        raise SystemExit(f"headline does not fit on {max_lines} lines: {text!r}")
    if len(lines) == 2:                      # balance the two lines
        best = None
        for i in range(1, len(words)):
            a, b = " ".join(words[:i]), " ".join(words[i:])
            m = max(draw.textlength(a, font=font), draw.textlength(b, font=font))
            if m <= width and (best is None or m < best[0]):
                best = (m, [a, b])
        lines = best[1]
    return lines


def background(W, H):
    col = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        col.putpixel((0, y), tuple(int(INK_TOP[i] + (INK_BOTTOM[i] - INK_TOP[i]) * t) for i in range(3)))
    return col.resize((W, H), Image.Resampling.BICUBIC)


def glow(W, H, cx, cy, r, colour, strength):
    layer = Image.new("L", (W, H), 0)
    ImageDraw.Draw(layer).ellipse((cx - r, cy - r, cx + r, cy + r), fill=strength)
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.55))
    return layer, Image.new("RGB", (W, H), colour)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


SYSTEM_FONT = Path("/System/Library/Fonts/SFNS.ttf")


def clean_status_bar(shot: Image.Image) -> Image.Image:
    """A device capture carries the real status bar (the hour, the battery, any live activity in
    the Dynamic Island). Repaint it as Apple's own marketing shots show it: 9:41, full signal,
    Wi-Fi and battery, an empty island. Only the top 150 px of a 1320-wide iPhone capture change."""
    if shot.width != 1320:
        return shot                              # iPad and simulator captures are already clean
    img = shot.copy()
    d = ImageDraw.Draw(img)
    bg = img.getpixel((24, 168))
    d.rectangle((0, 0, img.width, 158), fill=bg)
    dark = relative_luminance(bg) < 0.4
    fg = (255, 255, 255) if dark else (0, 0, 0)
    d.rounded_rectangle((474, 33, 846, 144), 56, fill=(0, 0, 0))            # the Dynamic Island
    f = ImageFont.truetype(str(SYSTEM_FONT), 54)
    try:
        f.set_variation_by_axes([590, 0, 0])[0] if False else f.set_variation_by_name("Semibold")
    except Exception:
        pass
    t = "9:41"
    d.text((232 - d.textlength(t, font=f) / 2, 61), t, font=f, fill=fg)
    # signal: four bars
    x0, base = 958, 112
    for i, h in enumerate((14, 21, 28, 35)):
        d.rounded_rectangle((x0 + i * 15, base - h, x0 + i * 15 + 10, base), 3, fill=fg)
    # Wi-Fi: three arcs and a dot
    cx, cy = 1062, 114
    for r in (40, 27, 14):
        d.arc((cx - r, cy - r, cx + r, cy + r), 225, 315, fill=fg, width=7)
    # battery: outline, full fill, cap
    bx, by = 1112, 80
    d.rounded_rectangle((bx, by, bx + 76, by + 36), 11, outline=fg, width=3)
    d.rounded_rectangle((bx + 6, by + 6, bx + 70, by + 30), 7, fill=fg)
    d.rounded_rectangle((bx + 80, by + 12, bx + 85, by + 24), 2, fill=fg)
    return img


def compose(capture: Path, entry: dict, size) -> Image.Image:
    W, H = size
    u = W / 1320
    hero = bool(entry.get("hero"))
    canvas = background(W, H)

    # headline block
    d = ImageDraw.Draw(canvas)
    top = int((150 if hero else 140) * u)
    rule_w, rule_h = int(96 * u), max(6, int(8 * u))
    d.rounded_rectangle(((W - rule_w) // 2, top, (W + rule_w) // 2, top + rule_h), rule_h // 2, fill=GOLD_FILL)
    hsize = int((112 if hero else 96) * u)
    font = serif(hsize, 640)
    y = top + rule_h + int(54 * u)
    for ln in wrap(d, entry["headline"], font, W - int(2 * 100 * u)):
        w = d.textlength(ln, font=font)
        d.text(((W - w) / 2, y), ln, font=font, fill=PAPER)
        y += int(hsize * 1.16)
    if entry.get("sub"):
        sf = serif(int(46 * u), 420)
        y += int(14 * u)
        w = d.textlength(entry["sub"], font=sf)
        if w > W - int(160 * u):
            raise SystemExit(f"sub line too long: {entry['sub']!r}")
        d.text(((W - w) / 2, y), entry["sub"], font=sf, fill=MUTED)
        y += int(46 * u * 1.3)
    text_bottom = y + int((60 if hero else 56) * u)

    # the device: large, rising from the bottom edge (its lower part runs off the canvas)
    shot = clean_status_bar(Image.open(capture).convert("RGB"))
    dev_w = int(W * (0.80 if W < 1500 else 0.78))
    scale = dev_w / shot.width
    dev_h = int(shot.height * scale)
    shot = shot.resize((dev_w, dev_h), Image.Resampling.LANCZOS)
    bezel = int(22 * u)
    radius = int(118 * u)
    x = (W - dev_w) // 2
    yy = text_bottom + bezel

    # warm glow behind the device, soft shadow under it
    gmask, gcol = glow(W, H, W // 2, yy + int(260 * u), int(620 * u), GOLD_SOFT, 70)
    canvas = Image.composite(gcol, canvas, gmask)
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle((x - bezel, yy - bezel + int(30 * u), x + dev_w + bezel,
                                          yy + dev_h + bezel + int(30 * u)), radius + bezel, fill=150)
    sh = sh.filter(ImageFilter.GaussianBlur(int(40 * u)))
    canvas = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), canvas, sh)

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((x - bezel, yy - bezel, x + dev_w + bezel, yy + dev_h + bezel), radius + bezel, fill=BEZEL)
    d.rounded_rectangle((x - bezel + 3, yy - bezel + 3, x + dev_w + bezel - 3, yy + dev_h + bezel - 3),
                        radius + bezel - 3, outline=(0x55, 0x49, 0x3C), width=max(2, int(3 * u)))
    canvas.paste(shot, (x, yy), rounded_mask(shot.size, radius))
    return canvas


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--captures", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=HERE / "screenshots-v2")
    ap.add_argument("--only", default=None, help="one set, e.g. iphone-6.9")
    ap.add_argument("--captions", type=Path, default=CAPTIONS)
    args = ap.parse_args(argv)
    assert contrast(PAPER, INK_TOP) >= 7 and contrast(MUTED, INK_TOP) >= 4.5, "caption contrast"
    spec = json.loads(args.captions.read_text(encoding="utf-8"))
    made = []
    for set_name, entries in spec.items():
        if set_name.startswith("_") or (args.only and set_name != args.only):
            continue
        for i, e in enumerate(entries, 1):
            src = args.captures / set_name / f"{e['shot']}.png"
            if not src.exists():
                print(f"MISSING capture {src}", file=sys.stderr)
                return 1
            img = compose(src, e, SIZES[set_name])
            out = args.out / set_name / f"{i:02d}-{e['shot']}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            img.save(out, "PNG", optimize=True)          # RGB, no alpha (App Store Connect rejects alpha)
            made.append(out)
            print(f"  {out}  {img.size}  “{e['headline']}”")
    print(f"{len(made)} screenshots; headline contrast {contrast(PAPER, INK_TOP):.1f}:1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
