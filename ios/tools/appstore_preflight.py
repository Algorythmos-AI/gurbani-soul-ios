#!/usr/bin/env python3
"""appstore_preflight.py VERSION — may this marketing version be SUBMITTED to App Review?

A TestFlight binary and an App Store binary are the same upload, so "which build do I submit?" is
answered by the tracked ledger, not by memory. Exit 0 only when ALL of these hold:

  1. the newest recorded build for VERSION has channel == "appstore" (it was archived with
     CHANNEL=appstore, i.e. it passed the scholar-review gate on the Nitnem non-SGGS text);
  2. ios/Resources/NITNEM-REVIEW.md reads `REVIEWED: true`;
  3. the in-app label is off (NitnemReview.extraTextReviewed = true);
  4. that build was made with an SDK at or above the App Store floor;
  5. scripts/release/check_versions.py passes and the top CHANGELOG entry is VERSION;
  6. the store-listing lint (ios/tests/test_ios_gates.py) passes;
  7. a physical-device run of the very tree that was archived PASSED: ios/device-runs/index.json
     has a run for VERSION with verdict PASS whose tree is the tree of that build's source_commit
     (a tree, not a commit, survives a squash merge), and the device-run records pass
     `device_run.py check` and `rebuild --check` (docs/ios/device-evidence.md).

Prints every failed condition, never just the first. Stdlib only.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIN_SDK_MAJOR = 26   # keep in step with MIN_XCODE_MAJOR in testflight_archive.sh


def newest_build(version, builds):
    rows = [b for b in builds if b.get("version") == version]
    return max(rows, key=lambda b: b["build"]) if rows else None


def device_problems(version, build, runs, tree_of):
    """Condition 7: a PASS device run of the archived tree. `runs` are index.json's rows;
    `tree_of(commit)` gives a commit's tree, or None when it is not here."""
    if build is None:
        return []
    commit = build.get("source_commit")
    if not commit:
        return [f"build {version} ({build['build']}) records no source_commit, so no device run can be bound to it"]
    tree = tree_of(commit)
    if tree is None:
        return [f"the tree of {commit[:12]} (the archived commit) is not known here — git fetch origin, then retry"]
    if any(r.get("version") == version and r.get("verdict") == "PASS" and r.get("tree") == tree for r in runs):
        return []
    seen = [f"{r['run_id']} {r['verdict']} (tree {(r.get('tree') or '')[:7]})" for r in runs if r.get("version") == version]
    return [f"no PASS device run of tree {tree[:7]} (from {commit[:7]}) for {version} in ios/device-runs/index.json"
            + (f"; recorded: {', '.join(seen)}" if seen else "") + " — docs/ios/device-evidence.md"]


def evaluate(version, builds, review_text, schedule_text, device_runs=None, tree_of=None):
    """The pure part: every reason VERSION may not be submitted, given the ledger rows, the
    attestation file, the Swift source that carries the in-app label and, when given, the
    device-run index and a commit → tree lookup."""
    problems = []
    build = newest_build(version, builds)
    if build is None:
        problems.append(f"no uploaded build is recorded for {version} in ios/testflight-builds.json")
    else:
        label = f"{version} ({build['build']})"
        if build.get("channel") != "appstore":
            problems.append(f"newest build {label} has channel={build.get('channel', 'testflight')!r} — "
                            "rebuild with `make testflight … CHANNEL=appstore`; a TestFlight-channel build "
                            "has not passed the scholar-review gate and must not be submitted")
        sdk = str(build.get("sdk") or "")
        m = re.match(r"[a-z]+(\d+)", sdk)
        if not m or int(m.group(1)) < MIN_SDK_MAJOR:
            problems.append(f"build {label} records sdk={sdk or 'unknown'} — App Store Connect requires the "
                            f"iOS {MIN_SDK_MAJOR} SDK or later")
    if not re.search(r"(?m)^REVIEWED:\s*true\s*$", review_text):
        problems.append("ios/Resources/NITNEM-REVIEW.md is not signed (REVIEWED: true) — owner gate H1")
    if not re.search(r"(?m)^\s*static let extraTextReviewed = true\s*$", schedule_text):
        problems.append('the app still labels the Nitnem extra text "Under scholarly review" '
                        "(NitnemReview.extraTextReviewed is not true)")
    if device_runs is not None:
        problems += device_problems(version, build, device_runs, tree_of)
    return build, problems


def git_tree(commit):
    out = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{commit}^{{tree}}"], cwd=ROOT,
                         capture_output=True, text=True)
    return out.stdout.strip() or None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    version = argv[0]
    doc = json.loads((ROOT / "ios" / "testflight-builds.json").read_text(encoding="utf-8"))
    index = ROOT / "ios" / "device-runs" / "index.json"
    runs = json.loads(index.read_text(encoding="utf-8")).get("runs", []) if index.exists() else []
    build, problems = evaluate(
        version, doc.get("builds", []),
        (ROOT / "ios" / "Resources" / "NITNEM-REVIEW.md").read_text(encoding="utf-8"),
        (ROOT / "ios/App/Sources/Data/NitnemSchedule.swift").read_text(encoding="utf-8"),
        device_runs=runs, tree_of=git_tree)

    checks = [("version strings / CHANGELOG", [sys.executable, "scripts/release/check_versions.py"])]
    # The listing lint is part of the iOS gates; it always runs (a missing file is a failure, never a skip).
    checks.append(("store-listing lint", [sys.executable, "-m", "unittest", "-q", "ios.tests.test_ios_gates"]))
    checks.append(("device-run records", [sys.executable, "ios/tools/device_run.py", "check"]))
    checks.append(("device-run derived files", [sys.executable, "ios/tools/device_run.py", "rebuild", "--check"]))
    for title, cmd in checks:
        run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if run.returncode != 0:
            tail = (run.stdout + run.stderr).strip().splitlines()[-3:]
            problems.append(f"{title} failed: " + " | ".join(tail))

    if problems:
        print(f"NOT ready to submit {version}:")
        for p in problems:
            print(f"  ✗ {p}")
        print("\nOwner gates that no script can check: G3 scholar/Granthi sign-off, G4 legal clearance, "
              "Charter S on this build, the accessibility pass, the App Store Connect forms.")
        return 1
    print(f"OK  {version} ({build['build']}) may be submitted: channel=appstore, review signed, "
          f"sdk {build.get('sdk')}, versions and listing clean, a PASS device run of its tree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
