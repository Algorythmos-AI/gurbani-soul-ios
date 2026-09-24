#!/usr/bin/env python3
"""
check_versions.py — the app's version invariants. The CI `versions` gate; also run by the
archive script and the App Store preflight (`make check-versions`).

One-number policy (web == API == iOS binary):
  - ios/App/project.yml MARKETING_VERSION equals the platform APP_VERSION recorded in
    vendor.lock.json — the release whose golden contract this app is built and tested against.
    A version bump therefore arrives with its contract: `scripts/vendor_sync.py sync platform vX.Y.Z`.
  - the newest version in the ledger ios/testflight-builds.json is <= MARKETING_VERSION
    (the shipped binary may equal this release or trail it, never lead it).

Build invariants:
  - CURRENT_PROJECT_VERSION is the floor "1" (each upload passes BUILD=N to the archive
    script; the committed floor never moves).
  - no <x.y.z>+<n> version literal is hardcoded in ios/App/Tests/UI/*.swift (the About-screen
    UI test reads the built version, not a literal).

Exit 0 if consistent, 1 otherwise.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(p):
    return (ROOT / p).read_text(encoding="utf-8")


def first(pattern, text, label):
    m = re.search(pattern, text)
    return m.group(1) if m else f"<not found: {label}>"


def semver(v):
    try:
        return tuple(int(x) for x in v.split("."))
    except (ValueError, AttributeError):
        return None


def main():
    proj = read("ios/App/project.yml")
    marketing = first(r'MARKETING_VERSION:\s*"([^"]+)"', proj, "project.yml")
    try:
        platform = json.loads(read("vendor.lock.json"))["sources"]["platform"]["version"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        platform = "<not found: vendor.lock.json sources.platform.version>"
    cpv = first(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', proj, "project.yml CPV")

    ui_literals = []
    for sw in sorted((ROOT / "ios/App/Tests/UI").glob("*.swift")):
        for i, line in enumerate(sw.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"\b\d+\.\d+\.\d+\+\d+\b", line):
                ui_literals.append(f"{sw.relative_to(ROOT)}:{i}")

    try:
        rows = json.loads(read("ios/testflight-builds.json")).get("builds", [])
        led = [r["version"] for r in rows if isinstance(r, dict) and "version" in r]
    except (FileNotFoundError, json.JSONDecodeError, AttributeError):
        led = []
    newest = max((semver(v) for v in led if semver(v)), default=None)
    if not led:
        led_ok, led_detail = True, "ledger empty (no uploads yet)"
    elif semver(marketing) is None:
        led_ok, led_detail = False, f"MARKETING_VERSION {marketing!r} unparseable"
    else:
        newest_s = ".".join(map(str, newest))
        led_ok = newest <= semver(marketing)
        led_detail = (f"newest ledger {newest_s} <= MARKETING_VERSION {marketing}" if led_ok else
                      f"newest ledger {newest_s} is AHEAD of MARKETING_VERSION {marketing}")

    checks = [
        ("MARKETING_VERSION == platform APP_VERSION (vendor.lock.json)", marketing == platform,
         f"{marketing} vs {platform}"),
        ('CURRENT_PROJECT_VERSION is the floor "1"', cpv == "1", f"got {cpv!r}"),
        ("no x.y.z+n literal in UI tests", not ui_literals, ", ".join(ui_literals) or "none"),
        ("ledger not ahead of MARKETING_VERSION", led_ok, led_detail),
    ]
    width = max(len(k) for k, _, _ in checks)
    print(f"app version (project.yml): {marketing}\n")
    for k, passed, detail in checks:
        print(f"  {'ok  ' if passed else 'FAIL'} {k:<{width}} : {detail}")
    print()
    if not all(p for _, p, _ in checks):
        print("RESULT: FAIL — a version bump arrives with its contract: "
              "`python3 scripts/vendor_sync.py sync platform vX.Y.Z` and set MARKETING_VERSION to X.Y.Z.")
        return 1
    print(f"RESULT: PASS — {len(checks)} checks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
