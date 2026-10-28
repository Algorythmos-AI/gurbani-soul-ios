#!/usr/bin/env python3
"""Report the automated device-checklist rows from an .xcresult, and fail unless every row PASSED.

A row counts as PASS only when its test ran and passed (not skipped, not missing) AND attached
its evidence to the result bundle. Anything else — a failure, a crash, a skip because
TEST_RUNNER_SGGS_DEVICE_CHECKLIST was not set, a run on a simulator, or a test that attached no
evidence — makes the report fail.

    python3 ios/tools/device_checklist_report.py path/to/run.xcresult
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from device_run import CHECKLIST  # noqa: E402  (one list of rows for both tools)

# checklist row -> test in DeviceChecklistTests (docs/ios/testflight-test-plan.md §8)
ROWS = {f"{row} {title}": test.split("/", 1)[1] for row, (title, test) in CHECKLIST.items() if test}


def xcresult(*args):
    out = subprocess.run(["xcrun", "xcresulttool", *args], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"FAIL: xcresulttool {' '.join(args[:3])}: {out.stderr.strip()}")
    return out.stdout


def main(path):
    tests = json.loads(xcresult("get", "test-results", "tests", "--path", path))
    devices = [d.get("platform", "") + " " + d.get("deviceName", "") for d in tests.get("devices", [])]
    results = {}

    def walk(node):
        ident = node.get("nodeIdentifier", "")
        if node.get("nodeType") == "Test Case" and ident.startswith("DeviceChecklistTests/"):
            results[ident.split("/", 1)[1]] = node
        for c in node.get("children", []):
            walk(c)

    for n in tests.get("testNodes", []):
        walk(n)

    with tempfile.TemporaryDirectory() as tmp:
        xcresult("export", "attachments", "--path", path, "--output-path", tmp)
        manifest = json.load(open(f"{tmp}/manifest.json"))
    attachments = {t["testIdentifier"].split("/", 1)[-1]: [a["suggestedHumanReadableName"] for a in t["attachments"]]
                   for t in manifest}

    ok = True
    print(f"devices: {', '.join(devices) or 'unknown'}")
    if not any("iOS" in d and "Simulator" not in d for d in devices):
        print("FAIL: not a physical-device run")
        ok = False
    for row, test in ROWS.items():
        node = results.get(test)
        state = node.get("result", "?") if node else "MISSING"
        rid = row.split()[0] + " "                 # evidence is named for its row: "D2 …"
        n = sum(1 for a in attachments.get(test, []) if a.startswith(rid))
        passed = state == "Passed" and n > 0
        ok &= passed
        why = "" if passed else ("  (no evidence attached)" if state == "Passed" else "")
        print(f"{'PASS' if passed else 'FAIL':4}  {row:32} {state:8} evidence: {n}{why}")
        for c in (node or {}).get("children", []):
            if c.get("nodeType") == "Failure Message":
                print(f"        {c.get('name')}")
    print("checklist automated rows:", "ALL PASS" if ok else "NOT PASSED")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
