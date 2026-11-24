#!/usr/bin/env python3
"""Refuse an archived .app if ANY bundle in it (the app, each PlugIns/*.appex, each embedded
framework) was built with an iOS SDK below the App Store floor.

App Store Connect validates every binary it is given, not only the app: a widget built against an
older SDK draws ITMS-90725 on its own. The floor is read from ios/tools/min-sdk-major, the single
source of truth shared with testflight_archive.sh, appstore_preflight.py and the select-xcode action.

Usage: check_bundle_sdk.py <path/to/App.app> [min-major]     exit 0 = every bundle passes
Plain plistlib, no PlistBuddy, so the tests run on Linux too.
"""
import plistlib, re, sys
from pathlib import Path

FLOOR_FILE = Path(__file__).resolve().parent / "min-sdk-major"


def read_floor(path=FLOOR_FILE):
    text = Path(path).read_text().strip()
    if not re.fullmatch(r"[0-9]+", text):
        raise ValueError(f"{path} must hold one integer (the minimum iOS SDK major), got {text!r}")
    return int(text)


def sdk_major(sdk_name):
    m = re.fullmatch(r"[a-z]+([0-9]+)(\.[0-9]+)*", sdk_name or "")
    return int(m.group(1)) if m else None


def bundles(app):
    app = Path(app)
    yield app
    for pattern in ("PlugIns/*.appex", "Frameworks/*.framework", "Extensions/*.appex"):
        yield from sorted(app.glob(pattern))


def problems(app, floor):
    out, seen = [], 0
    for b in bundles(app):
        plist = b / "Info.plist"
        if not plist.is_file():
            out.append(f"{b.name}: no Info.plist")
            continue
        seen += 1
        with plist.open("rb") as fh:
            sdk = plistlib.load(fh).get("DTSDKName", "")
        major = sdk_major(sdk)
        if major is None:
            out.append(f"{b.name}: DTSDKName is {sdk!r} — cannot tell which SDK built it")
        elif major < floor:
            out.append(f"{b.name}: built with SDK {sdk} — App Store Connect requires the iOS {floor} SDK or later (ITMS-90725)")
        else:
            print(f"  {b.name}: {sdk}")
    if not seen:
        out.append(f"{app}: no bundle found")
    return out


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2
    floor = int(argv[2]) if len(argv) == 3 else read_floor()
    found = problems(argv[1], floor)
    for p in found:
        print(f"FAIL: {p}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
