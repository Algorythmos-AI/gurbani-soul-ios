#!/usr/bin/env python3
"""Frame the release candidate's own screen captures for the App Store — deterministically.

Each capture from `testCaptureScreens` (the RC commit, public DB) is placed, unaltered apart from
scaling, on a Soul Gold / warm-paper frame with one English caption from captions.json, at
Apple's exact pixel size. Nothing is drawn over the app's pixels and no Gurmukhi is ever typeset
here: the scripture on every screenshot is the app's own rendering.

  uv run --with pillow python3 ios/AppStore/compose_store_shots.py \\
      --captures <dir with iphone-6.9/ and ipad-13/ PNGs> --out ios/AppStore/screenshots

Writes <out>/<set>/NN-<shot>.png (git-ignored masters) and ios/AppStore/contact-sheet/<set>--NN-<shot>.jpg
(small, committed, for review). Deterministic: same inputs → same bytes.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FONT = ROOT / "ios" / "App" / "Resources" / "SourceSerif4.ttf"
CAPTIONS = HERE / "captions.json"
CONTACT = HERE / "contact-sheet"

# Brand tokens (ios/App/Shared/DesignTokens.swift ↔ docs/brand/tokens.json): paper, ink, the gold
# rule is `accentFill` #FFBC0D always bordered by `accent` #A87900 (never gold text, never red).
PAPER = (0xFB, 0xF7, 0xF0)
INK = (0x20, 0x1A, 0x12)
GOLD_FILL = (0xFF, 0xBC, 0x0D)
GOLD_EDGE = (0xA8, 0x79, 0x00)

# Apple's accepted sizes (App Store Connect → screenshot specifications).
SIZES = {"iphone-6.9": (1320, 2868), "ipad-13": (2064, 2752)}


def relative_luminance(rgb) -> float:
    def ch(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b) -> float:
    la, lb = sorted((relative_luminance(a), relative_luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def wrap(draw, text, font, width):
    """One line if it fits; otherwise the two-line split with the most even line lengths."""
    if draw.textlength(text, font=font) <= width:
        return [text]
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        wa, wb = draw.textlength(a, font=font), draw.textlength(b, font=font)
        if max(wa, wb) <= width and (best is None or max(wa, wb) < best[0]):
            best = (max(wa, wb), [a, b])
    if best is None:
        raise SystemExit(f"caption does not fit on two lines: {text!r}")
    return best[1]


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def compose(capture: Path, caption: str, size: tuple[int, int]) -> Image.Image:
    W, H = size
    if capture.stat().st_size == 0:
        raise SystemExit(f"empty capture {capture}")
    shot = Image.open(capture).convert("RGB")
    landscape = shot.width > shot.height
    if landscape:                        # e.g. the iPad Reader in landscape → landscape canvas
        W, H = H, W
    canvas = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(canvas)
    unit = W / 1320                       # scale every measure from the iPhone design
    type_unit = min(unit, 1.2)            # …but keep iPad captions near the phone's visual size

    # caption band
    top = int(150 * type_unit)
    rule_w, rule_h = int(120 * type_unit), max(8, int(10 * type_unit))
    rx = (W - rule_w) // 2
    d.rounded_rectangle((rx, top, rx + rule_w, top + rule_h), rule_h // 2, fill=GOLD_FILL,
                        outline=GOLD_EDGE, width=max(1, int(2 * unit)))
    font = ImageFont.truetype(str(FONT), int(84 * type_unit))
    try:
        font.set_variation_by_axes([600])   # Source Serif 4 variable: semibold
    except (OSError, AttributeError):
        pass
    lines = wrap(d, caption, font, W - int(2 * 110 * unit))
    y = top + rule_h + int(56 * type_unit)
    for ln in lines:
        w = d.textlength(ln, font=font)
        d.text(((W - w) / 2, y), ln, font=font, fill=INK)
        y += int(84 * type_unit * 1.22)
    band_bottom = y + int(40 * type_unit)

    # the capture, scaled to fit, rounded like the device display, with a soft shadow
    margin_x, margin_b = int(110 * unit), int(110 * unit)
    box_w, box_h = W - 2 * margin_x, H - band_bottom - margin_b
    scale = min(box_w / shot.width, box_h / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    scaled = shot.resize((sw, sh), Image.Resampling.LANCZOS)
    radius = int((56 if not landscape and W < 1500 else 36) * unit * (sw / (W - 2 * margin_x)))
    x, yy = (W - sw) // 2, band_bottom + (box_h - sh) // 2
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, yy + int(18 * unit), x + sw, yy + sh + int(18 * unit)),
                                             radius, fill=70)
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(36 * unit)))
    canvas = Image.composite(Image.new("RGB", (W, H), (0xD8, 0xCF, 0xC0)), canvas, shadow)
    canvas.paste(rounded(scaled, radius), (x, yy), rounded(scaled, radius))
    ImageDraw.Draw(canvas).rounded_rectangle((x, yy, x + sw - 1, yy + sh - 1), radius,
                                             outline=(0xE5, 0xDC, 0xCD), width=max(1, int(2 * unit)))
    return canvas


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--captures", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=HERE / "screenshots")
    args = ap.parse_args(argv)
    spec = json.loads(CAPTIONS.read_text(encoding="utf-8"))
    assert contrast(INK, PAPER) >= 4.5, "caption contrast below 4.5:1"
    CONTACT.mkdir(exist_ok=True)
    made = 0
    for set_name, entries in spec.items():
        if set_name.startswith("_"):
            continue
        for i, e in enumerate(entries, 1):
            src = args.captures / set_name / f"{e['shot']}.png"
            if not src.exists():
                print(f"MISSING capture {src}", file=sys.stderr)
                return 1
            img = compose(src, e["caption"], SIZES[set_name])
            out = args.out / set_name / f"{i:02d}-{e['shot']}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            img.save(out, "PNG", optimize=True)       # RGB, no alpha — App Store Connect rejects alpha
            thumb = img.copy()
            thumb.thumbnail((360, 360))
            thumb.save(CONTACT / f"{set_name}--{i:02d}-{e['shot']}.jpg", "JPEG", quality=82)
            made += 1
            print(f"  {out.relative_to(args.out.parent) if args.out.is_relative_to(ROOT) else out}  {img.size}  “{e['caption']}”")
    print(f"{made} screenshots framed; caption contrast {contrast(INK, PAPER):.1f}:1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
