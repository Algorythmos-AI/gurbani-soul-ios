#!/usr/bin/env python3
"""check_hukamnama_build.py APP CHANNEL [--testflight-api URL] — is the Hukamnama in this build what
its channel promises?

testflight_archive.sh switches the Hukamnama on (card, sheet, push, widget) only for
CHANNEL=testflight, by command-line overrides. Nothing proved the overrides reached the binary:
the flags were checked by hand before 1.7.5 (2). This checks the archived SGGS.app itself
(after archiving, before export and upload):

  testflight  HukamnamaEnabled = YES; app and widget HukamnamaAPIBase = the testflight API;
              the Hukamnama widget is compiled into the widget binary.
  appstore    exactly what project.yml's Release configuration says: today HukamnamaEnabled = NO,
              the production API, and no Hukamnama widget code. When G3/G4 are signed and Release
              is flipped, this follows it. Nothing here needs editing.

The widget check looks for the Swift type name `HukamnamaProvider` in the widget binary. It is there
only when HUKAMNAMA_WIDGET is compiled in (checked against the 1.7.1 (1) App Store archive and the
1.7.5 (2) TestFlight archive). Prints every mismatch, not only the first. Stdlib only.
"""
import argparse
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = ROOT / "ios" / "App" / "project.yml"
WIDGET_MARKER = b"HukamnamaProvider"
DEFAULT_TESTFLIGHT_API = "https://api-staging.gurbanisoul.com"


def release_settings(project_text, target):
    """The `configs: Release:` settings of one target in project.yml (flat KEY: value lines only)."""
    targets = project_text.split("\ntargets:\n", 1)[1].split("\nschemes:\n", 1)[0]
    m = re.search(rf"(?m)^  {re.escape(target)}:\n((?:(?:    .*|\s*)\n)*)", targets + "\n")
    if not m:
        raise SystemExit(f"error: target {target} not found in project.yml")
    lines = m.group(1).splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if re.match(r"^        Release:(\s+#.*)?$", l))
    except StopIteration:
        raise SystemExit(f"error: target {target} has no Release config in project.yml")
    settings = {}
    for line in lines[start + 1:]:
        if line.strip() and not line.startswith("          "):
            break
        kv = re.match(r"^\s+([A-Z_]+):\s*(.*?)\s*(?:#.*)?$", line)
        if kv:
            settings[kv.group(1)] = kv.group(2).strip('"')
    return settings


def expected(channel, project_text, testflight_api):
    if channel == "testflight":
        return {"enabled": "YES", "app_api": testflight_api, "widget_api": testflight_api, "widget_compiled": True}
    app, widget = release_settings(project_text, "SGGS"), release_settings(project_text, "SGGSWidgets")
    for key, block in (("HUKAMNAMA_ENABLED", app), ("HUKAMNAMA_API_BASE", app), ("HUKAMNAMA_API_BASE", widget),
                       ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", widget)):
        if key not in block:
            raise SystemExit(f"error: project.yml Release config has no {key}")
    return {"enabled": app["HUKAMNAMA_ENABLED"], "app_api": app["HUKAMNAMA_API_BASE"],
            "widget_api": widget["HUKAMNAMA_API_BASE"],
            "widget_compiled": "HUKAMNAMA_WIDGET" in widget["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split()}


def actual(app):
    app = Path(app)
    widget = app / "PlugIns" / "SGGSWidgets.appex"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    winfo = plistlib.loads((widget / "Info.plist").read_bytes())
    binary = widget / winfo.get("CFBundleExecutable", "SGGSWidgets")
    return {"enabled": info.get("HukamnamaEnabled"), "app_api": info.get("HukamnamaAPIBase"),
            "widget_api": winfo.get("HukamnamaAPIBase"), "widget_compiled": WIDGET_MARKER in binary.read_bytes()}


def check(app, channel, project_text, testflight_api=DEFAULT_TESTFLIGHT_API):
    """A list of mismatches; empty when the build matches its channel."""
    want, got = expected(channel, project_text, testflight_api), actual(app)
    names = {"enabled": "HukamnamaEnabled", "app_api": "app HukamnamaAPIBase",
             "widget_api": "widget HukamnamaAPIBase", "widget_compiled": "Hukamnama widget compiled in"}
    return [f"{names[k]} is {got[k]!r}, channel {channel} needs {want[k]!r}" for k in want if got[k] != want[k]]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("app", help="path to the archived SGGS.app")
    ap.add_argument("channel", choices=["testflight", "appstore"])
    ap.add_argument("--testflight-api", default=DEFAULT_TESTFLIGHT_API)
    ap.add_argument("--project", default=str(PROJECT_YML))
    a = ap.parse_args(argv)
    problems = check(a.app, a.channel, Path(a.project).read_text(encoding="utf-8"), a.testflight_api)
    for p in problems:
        print(f"  ✗ {p}", file=sys.stderr)
    if problems:
        return 1
    got = actual(a.app)
    print(f"  ✓ Hukamnama matches channel {a.channel}: enabled={got['enabled']} api={got['app_api']} "
          f"widget={'compiled' if got['widget_compiled'] else 'absent'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
