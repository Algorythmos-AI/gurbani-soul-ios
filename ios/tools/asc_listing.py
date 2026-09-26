#!/usr/bin/env python3
"""The App Store listing, from the reviewed doc to App Store Connect — without ever writing to it.

  sheet   Print every field App Store Connect takes, in console order, exactly as it must be
          pasted (from docs/ios/app-store-listing.md), with Apple's character limits. Offline.
  diff    Read App Store Connect (GET only) and compare it with the doc field by field:
          OK / DRIFT / MISSING. Exit 0 only when nothing drifts or is missing. Run it after pasting,
          and on submission day (runbook app-store-submission §2 H6, §3).

This tool has no write path by design: App Store Connect is edited by a person, the doc is the
record, and `diff` proves the two agree (runbook §4: "the doc and the listing must never diverge").

diff needs the App Store Connect API key (path only — the key is never printed or copied) and
PyJWT with its crypto extra:

  SGGS_ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<ID>.p8 \\
  SGGS_ASC_KEY_ID=<key id> SGGS_ASC_ISSUER_ID=<issuer id> \\
  uv run --with 'pyjwt[crypto]' python3 ios/tools/asc_listing.py diff
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import listing_doc  # noqa: E402

ROOT = listing_doc.ROOT
PROJECT = ROOT / "ios" / "App" / "project.yml"
LEDGER = ROOT / "ios" / "testflight-builds.json"
API = "https://api.appstoreconnect.apple.com"
LOCALE = "en-GB"
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
            "INVALID_BINARY")

# What only a person can do in App Store Connect (not exposed by the public API) — printed as a
# checklist, never claimed as checked.
OWNER_ONLY = [
    "App Privacy → Data Not Collected → Publish",
    "Pricing and Availability → Mac and Apple Vision Pro availability unticked",
    "Business → EU Digital Services Act trader status declared and verified",
    "Business → Agreements: nothing pending",
    "Age rating questionnaire answered on the live form (expected 4+)",
    "Accessibility labels: only what the hardware pass (H5) proved",
]


def marketing_version() -> str:
    m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', PROJECT.read_text(encoding="utf-8"))
    return m.group(1)


def bundle_id() -> str:
    m = re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", PROJECT.read_text(encoding="utf-8"))
    return m.group(1)


def expected_build(version: str) -> int | None:
    """The newest App Store channel build of `version` in the ledger — the one to attach."""
    builds = json.loads(LEDGER.read_text(encoding="utf-8")).get("builds", [])
    nums = [int(b["build"]) for b in builds if b.get("version") == version and b.get("channel") == "appstore"]
    return max(nums) if nums else None


def category_id(name: str | None) -> str | None:
    return name.strip().upper().replace(" ", "_") if name else None


def expected(version: str) -> dict:
    f = listing_doc.load()
    return {
        "App Information · Name": f["name"],
        "App Information · Subtitle": f["subtitle"],
        "App Information · Primary category": category_id(f["primary_category"]),
        "App Information · Secondary category": category_id(f["secondary_category"]),
        "App Information · Content rights": "USES_THIRD_PARTY_CONTENT",
        "App Privacy · Privacy Policy URL": f["privacy_url"],
        "Version · Version string": version,
        "Version · Promotional text": f["promo"],
        "Version · Description": f["description"],
        "Version · Keywords": f["keywords"],
        "Version · Support URL": f["support_url"],
        "Version · Marketing URL": f["marketing_url"],
        "Version · Copyright": f["copyright"],
        "Version · Release": "MANUAL",
        "Version · Build": expected_build(version),
        "App Review · Sign-in required": False,
        "App Review · Contact email": f["review_email"],
        "App Review · Notes": f["review_notes"],
    }


# ---------------------------------------------------------------------------------------- sheet

# How the console words the API values the diff compares (the sheet is read by a person).
DISPLAY = {
    "App Information · Primary category": {"REFERENCE": "Reference"},
    "App Information · Secondary category": {"EDUCATION": "Education"},
    "App Information · Content rights": {"USES_THIRD_PARTY_CONTENT":
                                         "Yes — it contains third-party content, and I have the necessary rights"},
    "Version · Release": {"MANUAL": "Manually release this version"},
    "App Review · Sign-in required": {False: "No (untick \"Sign-in required\")"},
}

def cmd_sheet(_args) -> int:
    version = marketing_version()
    rows = expected(version)
    limits = {"App Information · Name": "name", "App Information · Subtitle": "subtitle",
              "Version · Promotional text": "promo", "Version · Description": "description",
              "Version · Keywords": "keywords", "App Review · Notes": "review_notes"}
    over = []
    print(f"App Store listing — paste sheet for {version} (source: docs/ios/app-store-listing.md)\n")
    for label, value in rows.items():
        value = DISPLAY.get(label, {}).get(value, value)
        if label == "Version · Build" and value is not None:
            value = f"{version} ({value})"          # as the console lists it
        lim = listing_doc.LIMITS.get(limits.get(label, ""))
        n = len(value) if isinstance(value, str) else None
        meta = f"  [{n}/{lim}]" if lim else ""
        if lim and n is not None and n > lim:
            over.append(label)
        print(f"━━ {label}{meta}")
        print(value if value is not None else "(not in the ledger yet — upload the App Store build first)")
        print()
    print("━━ Owner-only (not in the public API — tick by hand):")
    for item in OWNER_ONLY:
        print(f"  ☐ {item}")
    print("  ☐ App Review contact name and phone (the phone is never stored in the repo)")
    print("  ☐ Screenshots: iPhone 6.9\" and iPad 13\" sets from the release candidate (ios/AppStore/README.md)")
    if over:
        print(f"\nOVER THE LIMIT: {', '.join(over)}", file=sys.stderr)
        return 1
    return 0


# ----------------------------------------------------------------------------------------- diff

class Client:
    """GET-only App Store Connect client. There is deliberately no other method."""

    def __init__(self, token: str, base: str = API):
        self.token, self.base = token, base

    def get(self, path: str) -> dict:
        req = urllib.request.Request(self.base + path, headers={"Authorization": f"Bearer {self.token}"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return {"data": None}
            raise SystemExit(f"App Store Connect GET {path} → HTTP {e.code}") from None


def token_from_env() -> str:
    try:
        import jwt  # PyJWT
    except ImportError:
        raise SystemExit("diff needs PyJWT with crypto: uv run --with 'pyjwt[crypto]' python3 ios/tools/asc_listing.py diff")
    missing = [v for v in ("SGGS_ASC_KEY_PATH", "SGGS_ASC_KEY_ID", "SGGS_ASC_ISSUER_ID") if not os.environ.get(v)]
    if missing:
        raise SystemExit(f"set {', '.join(missing)} (key by path only — see the module docstring)")
    key = Path(os.path.expanduser(os.environ["SGGS_ASC_KEY_PATH"])).read_text(encoding="utf-8")
    now = int(time.time())
    return jwt.encode({"iss": os.environ["SGGS_ASC_ISSUER_ID"], "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                      headers={"kid": os.environ["SGGS_ASC_KEY_ID"], "typ": "JWT"})


def _one(client: Client, path: str) -> dict | None:
    return (client.get(path) or {}).get("data")


def _locale(items: list[dict]) -> dict:
    for it in items or []:
        if it["attributes"].get("locale") == LOCALE:
            return it
    return {}


def fetch_state(client: Client, bundle: str, version: str) -> dict:
    """What App Store Connect holds today, keyed like expected()."""
    apps = client.get(f"/v1/apps?filter[bundleId]={bundle}&fields[apps]=bundleId,contentRightsDeclaration")["data"]
    if not apps:
        raise SystemExit(f"no App Store Connect app with bundle id {bundle}")
    app = apps[0]
    app_id = app["id"]
    infos = client.get(f"/v1/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION"), infos[0])
    info_loc = _locale(client.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]).get("attributes", {})
    primary = _one(client, f"/v1/appInfos/{info['id']}/primaryCategory")
    secondary = _one(client, f"/v1/appInfos/{info['id']}/secondaryCategory")

    versions = client.get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    ver = (next((v for v in versions if v["attributes"].get("versionString") == version), None)
           or next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None))
    state: dict = {
        "App Information · Name": info_loc.get("name"),
        "App Information · Subtitle": info_loc.get("subtitle"),
        "App Information · Primary category": (primary or {}).get("id"),
        "App Information · Secondary category": (secondary or {}).get("id"),
        "App Information · Content rights": app["attributes"].get("contentRightsDeclaration"),
        "App Privacy · Privacy Policy URL": info_loc.get("privacyPolicyUrl"),
    }
    if not ver:
        return state | {"_version_state": "no editable App Store version"}
    va = ver["attributes"]
    loc = _locale(client.get(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"])
    la = loc.get("attributes", {})
    review = _one(client, f"/v1/appStoreVersions/{ver['id']}/appStoreReviewDetail") or {}
    ra = review.get("attributes", {})
    build = _one(client, f"/v1/appStoreVersions/{ver['id']}/build")
    build_label = None
    if build:
        full = client.get(f"/v1/builds/{build['id']}?include=preReleaseVersion")
        pre = next((i for i in full.get("included", []) if i["type"] == "preReleaseVersions"), {})
        build_label = f"{pre.get('attributes', {}).get('version')} ({build['attributes'].get('version')})"
    state |= {
        "Version · Version string": va.get("versionString"),
        "Version · Promotional text": la.get("promotionalText"),
        "Version · Description": la.get("description"),
        "Version · Keywords": la.get("keywords"),
        "Version · Support URL": la.get("supportUrl"),
        "Version · Marketing URL": la.get("marketingUrl"),
        "Version · Copyright": va.get("copyright"),
        "Version · Release": va.get("releaseType"),
        "Version · Build": build_label,
        "App Review · Sign-in required": ra.get("demoAccountRequired") if review else None,
        "App Review · Contact email": ra.get("contactEmail"),
        "App Review · Notes": ra.get("notes"),
        "_version_state": va.get("appStoreState"),
        "_review_contact_complete": bool(review and all(ra.get(k) for k in
                                         ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"))),
        "_screenshot_sets": _screenshots(client, loc.get("id")) if loc else {},
    }
    return state


def _screenshots(client: Client, loc_id: str) -> dict:
    sets = client.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"] or []
    out = {}
    for s in sets:
        shots = client.get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=10")["data"] or []
        out[s["attributes"]["screenshotDisplayType"]] = len(shots)
    return out


def _norm(v):
    return v.replace("\r\n", "\n").strip() if isinstance(v, str) else v


def compare(want: dict, have: dict, version: str) -> list[tuple[str, str, str]]:
    """(label, OK|DRIFT|MISSING, detail) for every expected field."""
    rows = []
    for label, w in want.items():
        h = have.get(label)
        if label == "Version · Build":
            w = f"{version} ({w})" if w is not None else None
        if h in (None, ""):
            rows.append((label, "MISSING", "empty in App Store Connect"))
        elif _norm(h) == _norm(w):
            rows.append((label, "OK", ""))
        else:
            a, b = _norm(w) or "", _norm(h) or ""
            i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
            rows.append((label, "DRIFT", f"differs at char {i}: doc {a[i:i + 40]!r} vs ASC {b[i:i + 40]!r}"))
    return rows


def cmd_diff(_args, client: Client | None = None) -> int:
    version = marketing_version()
    client = client or Client(token_from_env())
    have = fetch_state(client, bundle_id(), version)
    rows = compare(expected(version), have, version)
    print(f"App Store Connect vs docs/ios/app-store-listing.md — {version} "
          f"(ASC version state: {have.get('_version_state')})\n")
    for label, status, detail in rows:
        print(f"  {status:7} {label}{('  — ' + detail) if detail else ''}")
    contact_ok = have.get("_review_contact_complete")
    print(f"  {'OK' if contact_ok else 'MISSING':7} App Review · Contact name + phone"
          f"{'' if contact_ok else '  — entered by a person, never stored in the repo'}")
    shots = have.get("_screenshot_sets") or {}
    print(f"  {'OK' if shots else 'MISSING':7} Screenshots — {shots or 'none uploaded'}")
    print("\nNot checkable through the API — confirm by hand:")
    for item in OWNER_ONLY:
        print(f"  ☐ {item}")
    bad = [r for r in rows if r[1] != "OK"] + ([1] if not contact_ok else []) + ([1] if not shots else [])
    print(f"\nRESULT: {'NO DRIFT — the console matches the doc' if not bad else f'{len(bad)} item(s) to fix'}")
    return 0 if not bad else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sheet", help="print the paste sheet (offline)").set_defaults(fn=cmd_sheet)
    sub.add_parser("diff", help="compare App Store Connect with the doc (GET only)").set_defaults(fn=cmd_diff)
    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
