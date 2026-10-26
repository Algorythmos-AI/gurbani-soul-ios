#!/usr/bin/env python3
"""Self-check of a gurbanisoul.com screenshot set (capture_site_shots.sh output). Exits 1 on a fault.

    python3 ios/AppStore/check_site_shots.py <out-dir>

1. Within a set (iphone-light, ipad-portrait, ...), two names never share a hash unless both are in
   one ALLOWED group. Identical names are how the v1.4.9 run hid that Themes and Constellation were
   shot on the Index (themes == constellation == index_forms).
2. Every name the driver should write is there. A step whose control is missing writes nothing,
   so only the list of expected names can tell a short set from a full one.
3. No shot carries an EXIF rotation, and every shot in a landscape set shows wider than it is tall
   (the v1.4.9 landscape shots stored 2752×2064 pixels with orientation 8: viewers turned them).

Hidden files (the capture's own request and temp files) are never shots. Standard library only.
"""
import hashlib
import struct
import sys
from pathlib import Path

# Names that may be the same picture: the second name is the screen's opening state, or the element
# it shows is already on screen on a tall display. Each group is checked as a whole.
ALLOWED = [
    {"themes", "themes-index"},                                    # the index is Themes' opening view
    {"constellation", "constellation-focus"},                      # Focus is the opening view
    {"lineage", "lineage-roll", "voice-of-the-day"},               # Roll opens; the card is in view
    {"insights_contributors", "voices_dots_voices", "voices_ribbon"},  # Voices opens; ribbon in view
    {"index_raags", "index_raags_hour_and_grid"},                  # the grid is in view on iPad
    # widgets: no coordinates, so the solar Raag Now is the fixed one; accessory Nitnem
    # families draw "done" and "next" alike
    {"raagnow-circular-fixed-light", "raagnow-circular-solar-light"},
    {"raagnow-inline-fixed-light", "raagnow-inline-solar-light"},
    {"nitnem_circular_done_light", "nitnem_circular_next_light"},
    {"nitnem_inline_done_light", "nitnem_inline_next_light"},
]

# The names SiteShotTests writes in every iPhone and iPad set (the iPad runs the same groups), then
# what the iPhone adds: Verify, About, and the Vaars shots the site uses (from testVaarsWeave).
EXPECTED = """
    search_results after_search reader reader_options reader_sehaj hukam clock
    nitnem_home bani_reader bani_jaap
    explore_hub index composition_reader index_compositions_continue index_raags
    index_raags_hour_and_grid raag_gauri raag_gauri_forms_time index_forms index_find
    themes themes-index your-themes theme-page theme-verses themes-search-gurmukhi
    constellation constellation-focus constellation-card constellation-pair constellation-sky
    insights_contributors voices_dots_traditions voices_dots_centuries voices_dots_voices
    voices_ribbon voices_resonance_chord_and_list voices_echoes
    lineage lineage-roll voice-of-the-day lineage-river voice-m9 compare-v2 more_display
""".split()
EXPECTED_IPHONE = "verify_typing verify about vaars_home vaar_weave_top vaar_reader_top".split()
# The widget renders (WidgetRenderTests, HukamWidgetRenderTests, NitnemWidgetRenderTests): every
# family × mode × appearance. A render whose PNG is never written can still pass its test.
WIDGETS = (
    [f"raagnow-{f}-{m}-{a}" for f in ("circular", "inline", "large", "medium", "rectangular", "small")
     for m in ("fixed", "solar") for a in ("light", "dark")] + ["raagnow-medium-silent-dark"]
    + [f"hukam-{f}-{x}{a}" for f in ("large", "medium") for x in ("", "ax2-") for a in ("light", "dark")]
    + [f"nitnem_{f}_{t}_{a}" for f in ("circular", "inline", "medium", "rectangular", "small")
       for t in ("done", "next") for a in ("light", "dark")])
SETS = {"iphone-light": EXPECTED + EXPECTED_IPHONE, "iphone-dark": EXPECTED + EXPECTED_IPHONE,
        "ipad-portrait": EXPECTED, "ipad-landscape": EXPECTED, "widgets": WIDGETS}


def png_info(data):
    """(width, height, orientation): IHDR size and the EXIF orientation (1 = as stored)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    orientation, pos = 1, 8
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        if kind == b"eXIf":
            orientation = exif_orientation(data[pos + 8:pos + 8 + n]) or orientation
        pos += 12 + n
    return width, height, orientation


def exif_orientation(tiff):
    """Tag 0x0112 of IFD0 in a TIFF-structured EXIF block, or None."""
    end = {b"MM": ">", b"II": "<"}.get(tiff[:2])
    if end is None or len(tiff) < 8:
        return None
    ifd = struct.unpack(end + "I", tiff[4:8])[0]
    if ifd + 2 > len(tiff):
        return None
    for i in range(struct.unpack(end + "H", tiff[ifd:ifd + 2])[0]):
        e = ifd + 2 + 12 * i
        if e + 12 > len(tiff):
            return None
        tag, kind = struct.unpack(end + "HH", tiff[e:e + 4])
        if tag == 0x0112 and kind == 3:
            return struct.unpack(end + "H", tiff[e + 8:e + 10])[0]
    return None


def check(out):
    faults = []
    sets = sorted(p for p in out.iterdir() if p.is_dir() and not p.name.startswith("."))
    for absent in sorted(set(SETS) - {p.name for p in sets}):
        faults.append(f"{absent}: the set is missing")
    for s in sets:
        shots = sorted(p for p in s.glob("*.png") if not p.name.startswith("."))
        by_hash = {}
        for p in shots:
            data = p.read_bytes()
            by_hash.setdefault(hashlib.sha256(data).hexdigest(), []).append(p.stem)
            w, h, orientation = png_info(data)
            if orientation != 1:
                # an XCUITest screenshot after a rotation: the pixels are stored one way and the
                # EXIF turns them (v1.4.9's iPad landscape set: 2752×2064 stored, orientation 8)
                faults.append(f"{s.name}/{p.name}: EXIF orientation {orientation}, viewers turn it")
            if orientation in (5, 6, 7, 8):
                w, h = h, w
            if "landscape" in s.name and w <= h:
                faults.append(f"{s.name}/{p.name}: shows {w}×{h}, not landscape")
        missing = sorted(set(SETS.get(s.name, [])) - {p.stem for p in shots})
        if missing:
            faults.append(f"{s.name}: {len(missing)} shot(s) missing: {', '.join(missing)}")
        for names in by_hash.values():
            if len(names) > 1 and not any(set(names) <= g for g in ALLOWED):
                faults.append(f"{s.name}: identical pictures under different names: {', '.join(sorted(names))}")
        print(f"  {s.name}: {len(shots)} shots, {len(by_hash)} distinct")
    return faults


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))
    faults = check(out)
    for f in faults:
        print(f"::error::site shots: {f}")
    print(f"self-check: {'FAIL, ' + str(len(faults)) + ' fault(s)' if faults else 'OK'}")
    sys.exit(1 if faults else 0)


if __name__ == "__main__":
    main()
