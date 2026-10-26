"""The website screenshot self-check (ios/AppStore/check_site_shots.py) on small synthetic sets, and
its names against the driver (ios/App/Tests/UI/SiteShotTests.swift). Stdlib only: the PNGs are
built here, with an optional eXIf chunk."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import re
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("check_site_shots", ROOT / "ios" / "AppStore" / "check_site_shots.py")
check_site_shots = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_site_shots)
DRIVER = (ROOT / "ios" / "App" / "Tests" / "UI" / "SiteShotTests.swift").read_text(encoding="utf-8")


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def png(width: int, height: int, shade: int = 0, orientation: int | None = None, big_endian: bool = True) -> bytes:
    """A grey RGB PNG; `orientation` adds an eXIf chunk with IFD0 tag 0x0112."""
    row = b"\x00" + bytes([shade % 256]) * 3 * width
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    if orientation is not None:
        e = ">" if big_endian else "<"
        tiff = (b"MM" if big_endian else b"II") + struct.pack(e + "HI", 42, 8)
        tiff += struct.pack(e + "H", 1) + struct.pack(e + "HHIHH", 0x0112, 3, 1, orientation, 0) + struct.pack(e + "I", 0)
        out += chunk(b"eXIf", tiff)
    return out + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b"")


class SiteShotCheck(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.out = Path(self._tmp.name)
        self.shade = 0

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, set_name: str, name: str, data: bytes | None = None, landscape: bool | None = None):
        d = self.out / set_name
        d.mkdir(exist_ok=True)
        if data is None:                               # a distinct picture per name
            self.shade += 1
            wide = "landscape" in set_name if landscape is None else landscape
            data = png(6, 4, self.shade) if wide else png(4, 6, self.shade)
        (d / f"{name}.png").write_bytes(data)

    def full_set(self):
        for set_name, names in check_site_shots.SETS.items():
            for n in names:
                self.write(set_name, n)

    def faults(self):
        with contextlib.redirect_stdout(io.StringIO()):          # the per-set tally
            return check_site_shots.check(self.out)

    def test_a_full_distinct_set_is_clean(self):
        self.full_set()
        self.assertEqual(self.faults(), [])

    def test_a_missing_name_is_a_fault(self):
        self.full_set()
        (self.out / "iphone-light" / "constellation-pair.png").unlink()
        (self.out / "iphone-dark" / "more_display.png").unlink()
        f = self.faults()
        self.assertIn("iphone-light: 1 shot(s) missing: constellation-pair", f)
        self.assertIn("iphone-dark: 1 shot(s) missing: more_display", f)
        self.assertEqual(len(f), 2)

    def test_a_missing_set_is_a_fault(self):
        self.full_set()
        for p in (self.out / "widgets").iterdir():
            p.unlink()
        (self.out / "widgets").rmdir()
        self.assertEqual(self.faults(), ["widgets: the set is missing"])

    def test_identical_pictures_under_different_names_are_a_fault(self):
        self.full_set()
        same = (self.out / "ipad-portrait" / "themes.png").read_bytes()
        for n in ("themes-index", "your-themes"):
            self.write("ipad-portrait", n, same)
        self.assertEqual(self.faults(),
                         ["ipad-portrait: identical pictures under different names: themes, themes-index, your-themes"])

    def test_allowed_groups_may_be_identical(self):
        self.full_set()
        for set_name, group in (("iphone-light", ("lineage", "lineage-roll", "voice-of-the-day")),
                                ("ipad-landscape", ("constellation", "constellation-focus")),
                                ("widgets", ("raagnow-inline-fixed-dark", "raagnow-inline-solar-dark"))):
            same = (self.out / set_name / f"{group[0]}.png").read_bytes()
            for n in group[1:]:
                self.write(set_name, n, same)
        self.assertEqual(self.faults(), [])

    def test_an_allowed_pair_with_a_stranger_is_still_a_fault(self):
        self.full_set()
        same = (self.out / "iphone-light" / "constellation.png").read_bytes()
        for n in ("constellation-focus", "clock"):
            self.write("iphone-light", n, same)
        self.assertEqual(len(self.faults()), 1)

    def test_themes_views_are_no_longer_allowed_to_match(self):
        self.full_set()
        self.write("iphone-dark", "themes-index", (self.out / "iphone-dark" / "themes.png").read_bytes())
        self.assertEqual(self.faults(), ["iphone-dark: identical pictures under different names: themes, themes-index"])

    def test_a_portrait_shot_in_the_landscape_set_is_a_fault(self):
        self.full_set()
        self.write("ipad-landscape", "reader", landscape=False)
        self.assertEqual(self.faults(), ["ipad-landscape/reader.png: shows 4×6, not landscape"])

    def test_exif_rotation_is_a_fault_and_turns_the_size(self):
        self.full_set()
        # v1.4.9: 2752×2064 stored (wide) with orientation 8, which viewers show tall
        self.write("ipad-landscape", "hukam", png(6, 4, 200, orientation=8))
        self.write("iphone-light", "clock", png(4, 6, 201, orientation=6, big_endian=False))
        f = self.faults()
        self.assertIn("ipad-landscape/hukam.png: EXIF orientation 8, viewers turn it", f)
        self.assertIn("ipad-landscape/hukam.png: shows 4×6, not landscape", f)
        self.assertIn("iphone-light/clock.png: EXIF orientation 6, viewers turn it", f)
        self.assertEqual(len(f), 3)

    def test_exif_orientation_one_is_fine(self):
        self.full_set()
        self.write("ipad-landscape", "hukam", png(6, 4, 202, orientation=1))
        self.assertEqual(self.faults(), [])

    def test_a_light_lock_screen_render_is_not_in_the_set(self):
        self.full_set()
        self.write("widgets", "raagnow-circular-fixed-light")
        self.assertEqual(self.faults(), ["widgets: 1 render(s) not in the set: raagnow-circular-fixed-light"])

    def test_hidden_files_are_never_shots(self):
        self.full_set()
        self.write("ipad-landscape", ".frame-reader", (self.out / "ipad-landscape" / "hukam.png").read_bytes())
        self.write("ipad-landscape", ".request-x", png(4, 6, 1))
        self.assertEqual(self.faults(), [])

    def test_png_info_reads_size_and_orientation(self):
        self.assertEqual(check_site_shots.png_info(png(7, 3)), (7, 3, 1))
        self.assertEqual(check_site_shots.png_info(png(7, 3, orientation=8)), (7, 3, 8))
        with self.assertRaises(ValueError):
            check_site_shots.png_info(b"GIF89a" + b"\x00" * 30)


class DriverNames(unittest.TestCase):
    """The check expects exactly the names the driver writes (testVaarsWeave adds the Vaars)."""

    def test_every_expected_name_is_shot_by_the_driver(self):
        shot = set(re.findall(r'shot\(app, "([a-z0-9_-]+)"', DRIVER))
        shot |= set(re.findall(r'\("[A-Za-z]+", "(voices_[a-z_]+)"\)', DRIVER))   # the grouping loop
        vaars = {"vaars_home", "vaar_weave_top", "vaar_reader_top"}
        expected = set(check_site_shots.EXPECTED) | set(check_site_shots.EXPECTED_IPHONE)
        self.assertEqual(expected - vaars, shot)

    def test_lock_screen_families_are_named_dark_only(self):
        for n in check_site_shots.WIDGETS:
            if any(f in n for f in check_site_shots.LOCK):
                self.assertTrue(n.endswith("dark"), n)


if __name__ == "__main__":
    unittest.main()
