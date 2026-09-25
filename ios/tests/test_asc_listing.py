"""The listing paste sheet and the App Store Connect verifier (ios/tools/asc_listing.py): the doc is
parsed into exactly what gets pasted, the verifier compares field by field, and the tool can only
ever read App Store Connect. Offline — App Store Connect is replaced by a recorded fake."""
from __future__ import annotations

import io
import re
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ios" / "tools"))
import asc_listing  # noqa: E402
import listing_doc  # noqa: E402

TOOL = ROOT / "ios" / "tools" / "asc_listing.py"


class ListingDocParse(unittest.TestCase):
    def setUp(self):
        self.f = listing_doc.load()

    def test_every_field_is_present(self):
        for k, v in self.f.items():
            self.assertTrue(v, f"listing field {k!r} did not parse")

    def test_identity_rows_take_the_value_not_the_prose(self):
        # "Reference (matches `LSApplicationCategoryType`)" is the value Reference, not the backticked word.
        self.assertEqual(self.f["primary_category"], "Reference")
        self.assertEqual(self.f["secondary_category"], "Education")
        self.assertEqual(asc_listing.category_id(self.f["primary_category"]), "REFERENCE")
        self.assertTrue(self.f["copyright"].startswith("© "))

    def test_pasted_text_carries_no_markdown(self):
        for k in ("promo", "description", "review_notes"):
            self.assertNotIn("**", self.f[k], k)
            self.assertNotIn("`", self.f[k], k)

    def test_review_notes_are_reflowed_prose(self):
        notes = self.f["review_notes"]
        # a hard-wrapped doc line must not survive as a line break inside a paragraph
        for para in notes.split("\n\n"):
            self.assertNotIn("\n", para, f"paragraph still hard-wrapped: {para[:60]!r}")
        self.assertIn("More → About & credits → Integrity", notes)

    def test_description_keeps_its_bullets_on_their_own_lines(self):
        self.assertRegex(self.f["description"], r"(?m)^• ")

    def test_limits(self):
        for key, lim in listing_doc.LIMITS.items():
            self.assertLessEqual(len(self.f[key]), lim, key)


class Fake:
    """Recorded App Store Connect answers, keyed by request path."""

    def __init__(self, want: dict, **override):
        v = want
        info_loc = {"locale": "en-GB", "name": v["App Information · Name"], "subtitle": v["App Information · Subtitle"],
                    "privacyPolicyUrl": v["App Privacy · Privacy Policy URL"]}
        ver_loc = {"locale": "en-GB", "description": v["Version · Description"], "keywords": v["Version · Keywords"],
                   "promotionalText": v["Version · Promotional text"], "supportUrl": v["Version · Support URL"],
                   "marketingUrl": v["Version · Marketing URL"]}
        info_loc.update(override.get("info_loc", {}))
        ver_loc.update(override.get("ver_loc", {}))
        self.paths = {
            "/v1/apps?filter[bundleId]=org.sggs.app&fields[apps]=bundleId,contentRightsDeclaration":
                {"data": [{"id": "A1", "attributes": {"bundleId": "org.sggs.app",
                                                      "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}]},
            "/v1/apps/A1/appInfos": {"data": [{"id": "I1", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}]},
            "/v1/appInfos/I1/appInfoLocalizations": {"data": [{"id": "IL1", "attributes": info_loc}]},
            "/v1/appInfos/I1/primaryCategory": {"data": {"id": v["App Information · Primary category"]}},
            "/v1/appInfos/I1/secondaryCategory": {"data": {"id": v["App Information · Secondary category"]}},
            "/v1/apps/A1/appStoreVersions?filter[platform]=IOS&limit=20":
                {"data": [{"id": "V1", "attributes": {"versionString": v["Version · Version string"],
                                                      "appStoreState": "PREPARE_FOR_SUBMISSION",
                                                      "copyright": v["Version · Copyright"],
                                                      "releaseType": "MANUAL"}}]},
            "/v1/appStoreVersions/V1/appStoreVersionLocalizations": {"data": [{"id": "VL1", "attributes": ver_loc}]},
            "/v1/appStoreVersions/V1/appStoreReviewDetail":
                {"data": {"attributes": {"demoAccountRequired": False, "contactEmail": v["App Review · Contact email"],
                                         "contactFirstName": "A", "contactLastName": "B", "contactPhone": "+61 0",
                                         "notes": v["App Review · Notes"]}}},
            "/v1/appStoreVersions/V1/build": {"data": {"id": "B1", "attributes": {"version": str(v["Version · Build"])}}},
            "/v1/builds/B1?include=preReleaseVersion":
                {"data": {}, "included": [{"type": "preReleaseVersions",
                                           "attributes": {"version": v["Version · Version string"]}}]},
            "/v1/appStoreVersionLocalizations/VL1/appScreenshotSets":
                {"data": [{"id": "S1", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"}}]},
            "/v1/appScreenshotSets/S1/appScreenshots?limit=10": {"data": [{"id": "x"}] * 7},
        }
        self.seen: list[str] = []

    def get(self, path):
        self.seen.append(path)
        return self.paths[path]


class Verifier(unittest.TestCase):
    VERSION = "9.9.9"

    def want(self):
        with mock.patch.object(asc_listing, "expected_build", return_value=1):
            return asc_listing.expected(self.VERSION)

    def run_diff(self, fake):
        have = asc_listing.fetch_state(fake, "org.sggs.app", self.VERSION)
        return {label: status for label, status, _ in asc_listing.compare(self.want(), have, self.VERSION)}

    def test_matching_console_is_all_ok(self):
        self.assertEqual(set(self.run_diff(Fake(self.want())).values()), {"OK"})

    def test_edited_description_is_drift(self):
        statuses = self.run_diff(Fake(self.want(), ver_loc={"description": "Something else"}))
        self.assertEqual(statuses["Version · Description"], "DRIFT")

    def test_empty_field_is_missing(self):
        statuses = self.run_diff(Fake(self.want(), info_loc={"subtitle": None}))
        self.assertEqual(statuses["App Information · Subtitle"], "MISSING")

    def test_diff_command_exit_code_follows_the_result(self):
        with mock.patch.object(asc_listing, "marketing_version", return_value=self.VERSION), \
                mock.patch.object(asc_listing, "expected_build", return_value=1):
            with redirect_stdout(io.StringIO()):
                ok = asc_listing.cmd_diff(None, client=Fake(self.want()))
            with redirect_stdout(io.StringIO()):
                bad = asc_listing.cmd_diff(None, client=Fake(self.want(), ver_loc={"keywords": "x"}))
        self.assertEqual((ok, bad), (0, 1))


class ReadOnlyByConstruction(unittest.TestCase):
    """The tool may only read App Store Connect: no write verb, no request body, one GET client."""

    def test_no_write_path(self):
        src = TOOL.read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"\b(POST|PATCH|PUT|DELETE)\b", src), "a write verb appears in asc_listing.py")
        self.assertNotIn("method=", src)
        self.assertNotIn("data=", src)
        self.assertEqual(src.count("urllib.request.Request("), 1)

    def test_key_is_passed_by_path_only(self):
        src = TOOL.read_text(encoding="utf-8")
        self.assertNotRegex(src, r"print\([^)]*key\b", "the key must never be printed")


if __name__ == "__main__":
    unittest.main()
