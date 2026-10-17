"""App Store screenshot captions (ios/AppStore/captions.json): short, English, true to the listing,
and naming only screens the release candidate's own capture test produces. The compositor
(ios/AppStore/compose_store_shots.py, Pillow) is not imported here — CI runs these stdlib-only."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAPTIONS = json.loads((ROOT / "ios" / "AppStore" / "captions.json").read_text(encoding="utf-8"))
UI_TESTS = (ROOT / "ios" / "App" / "Tests" / "UI" / "SGGSUITests.swift").read_text(encoding="utf-8")
LISTING = (ROOT / "docs" / "ios" / "app-store-listing.md").read_text(encoding="utf-8").lower()
SETS = {k: v for k, v in CAPTIONS.items() if not k.startswith("_")}


class StoreShotCaptions(unittest.TestCase):
    def test_both_required_sets_exist(self):
        self.assertEqual(set(SETS), {"iphone-6.9", "ipad-13"})
        for name, entries in SETS.items():
            self.assertTrue(3 <= len(entries) <= 10, f"{name}: App Store Connect takes 1–10; we ship 3+")

    def test_captions_are_short_english_and_never_gurmukhi(self):
        for name, entries in SETS.items():
            for e in entries:
                c = e["caption"]
                self.assertLessEqual(len(c), 42, f"{name}/{e['shot']}: caption too long for two lines")
                self.assertIsNone(re.search(r"[਀-੿]", c),
                                  "no Gurmukhi is typeset over screenshots — scripture shows only as the app renders it")

    def test_captions_claim_nothing_the_app_does_not_do(self):
        forbidden = r"(?i)\baudio\b|\bkirtan\b|\bbeta\b|\btestflight\b|\bandroid\b|\bAI\b|\bfree\b|\bbest\b|#1"
        for entries in SETS.values():
            for e in entries:
                self.assertIsNone(re.search(forbidden, e["caption"]), e["caption"])

    def test_caption_keywords_are_in_the_listing(self):
        # each caption restates a listing claim: its key nouns must appear in the reviewed listing
        stop = {"every", "your", "the", "and", "their", "by", "or", "of", "this", "any", "a", "across", "draw", "kept"}
        for entries in SETS.values():
            for e in entries:
                words = [w for w in re.findall(r"[a-z]+", e["caption"].lower()) if w not in stop]
                missing = [w for w in words if w not in LISTING]
                self.assertEqual(missing, [], f"{e['caption']!r}: not found in the listing: {missing}")

    def test_every_shot_is_produced_by_the_capture_test(self):
        produced = set(re.findall(r'shot\("([a-z0-9_]+)"\)', UI_TESTS))
        for name, entries in SETS.items():
            for e in entries:
                shot = e["shot"].removeprefix("land_")      # SGGS_SHOT_TAG=land for the landscape run
                self.assertIn(shot, produced, f"{name}: testCaptureScreens has no shot({shot!r})")


V2 = json.loads((ROOT / "ios" / "AppStore" / "captions_v2.json").read_text(encoding="utf-8"))
V2_SETS = {k: v for k, v in V2.items() if not k.startswith("_")}


class NightSetCaptions(unittest.TestCase):
    """captions_v2.json (compose_store_shots_v2.py): the same rules, for headline and sub line."""

    def lines(self):
        for name, entries in V2_SETS.items():
            for e in entries:
                yield name, e, e["headline"], 42
                if "sub" in e:
                    yield name, e, e["sub"], 60

    def test_short_english_never_gurmukhi(self):
        for name, e, text, limit in self.lines():
            self.assertLessEqual(len(text), limit, f"{name}/{e['shot']}: {text!r} too long")
            self.assertIsNone(re.search(r"[\u0A00-\u0A7F]", text), "no Gurmukhi typeset over screenshots")

    def test_claim_nothing_the_app_does_not_do(self):
        forbidden = r"(?i)\baudio\b|\bkirtan\b|\bbeta\b|\btestflight\b|\bandroid\b|\bAI\b|\bfree\b|\bbest\b|#1"
        for _, _, text, _ in self.lines():
            self.assertIsNone(re.search(forbidden, text), text)

    def test_every_word_is_in_the_listing(self):
        stop = {"every", "your", "the", "and", "their", "by", "or", "of", "this", "any", "a", "across",
                "draw", "kept", "each", "all", "ji"}
        for _, _, text, _ in self.lines():
            words = [w for w in re.findall(r"[a-z]+", text.lower()) if w not in stop]
            self.assertEqual([w for w in words if w not in LISTING], [], text)

    def test_one_hero_first(self):
        for name, entries in V2_SETS.items():
            self.assertTrue(entries[0].get("hero"), f"{name}: the first frame is the hero")
            self.assertEqual(sum(bool(e.get("hero")) for e in entries), 1)
            self.assertTrue(3 <= len(entries) <= 10)

    def test_every_shot_is_produced_by_the_capture_test(self):
        produced = set(re.findall(r'shot\("([a-z0-9_]+)"\)', UI_TESTS))
        for name, entries in V2_SETS.items():
            for e in entries:
                look, _, shot = e["shot"].partition("_")
                self.assertIn(look, {"light", "dark"}, e["shot"])
                self.assertIn(shot, produced, f"{name}: testCaptureScreens has no shot({shot!r})")


if __name__ == "__main__":
    unittest.main()
