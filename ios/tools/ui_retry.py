#!/usr/bin/env python3
"""The CI test gate for the iOS app job, with one narrow retry for simulator failures.

    ui_retry.py plan    <summary.json> <diagnostics-dir> [<spindumps-dir>]   -> prints -only-testing ids
    ui_retry.py gate    <unit.json> <uitests.json> [<retry.json> <planned.txt>]

Why a retry exists at all: the release PR for 1.7.7 changed only a version string, yet its UI run
failed twice, once per attempt, on a different test each time, while main passed the same tree:

* the suite's first launch on the freshly booted simulator returned no process ID;
* Apple's accessibility monitor (AXBinaryMonitor, which XCUITest turns on) crashed the app while
  reading a toolbar button's tint colour on a background queue: no app frame in the crash;
* the same monitor, starved at background priority on the 3-CPU runner VM, never finished loading,
  so XCTest gave up with "has not loaded accessibility" while the app's main thread sat idle in its
  run loop (XCTest's own spindump of the app, attempt 3).

All are simulator/OS faults. "has not loaded accessibility" is the one an app bug could also cause
(a main thread stuck at launch), so it is retried only when XCTest's spindump of the app shows the
main thread holding no frame of the app's own code beyond its entry point. No spindump, or one that
cannot be read, means no retry. Nothing else is retried: an assertion failure, a timeout in a test's
own wait, or any crash report whose crashing thread has a frame in the app's own code fails the job
on the first run, exactly as before. At most MAX_RETRIES tests are retried, once each, and every
retried test is named in a ::warning so a recurring one is visible.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

MAX_RETRIES = 3
UI_TARGET = "SGGSUITests"

# Failure texts XCTest writes when the simulator could not launch or keep the app or the runner.
INFRA_SIGNATURES = (
    re.compile(r"does not have a process ID"),
    re.compile(r"^Failed to .*application org\.sggs\.app is not running"),
    re.compile(r"^Crash: SGGSUITests-Runner at "),
)
# Retried only with a spindump that proves the app's main thread was idle (see main_thread_idle).
AX_NOT_LOADED = re.compile(r"^Application 'org\.sggs\.app' has not loaded accessibility$")
# The only app frames an idle main thread may hold: the entry point the run loop sits under.
ENTRY_FRAMES = ("__debug_main_executable_dylib_entry_point", "SGGSApp.$main()")
APP_IMAGE = re.compile(r"\((?:[^()]* in )?SGGS(?:\.debug\.dylib)? \+ \d+\)")


def failures(summary: dict) -> list[tuple[str, str]]:
    out = []
    for f in summary.get("testFailures", []) or []:
        ident = f.get("testIdentifierString") or f.get("testName") or ""
        text = (f.get("failureText") or "").splitlines()[0] if f.get("failureText") else ""
        out.append((ident, text))
    return out


def is_infra(text: str) -> bool:
    return any(p.search(text) for p in INFRA_SIGNATURES)


def app_code_crashes(diagnostics: Path) -> list[str]:
    """Crash reports of the app (SGGS-*.ips) whose crashing thread runs the app's own code.

    The app's code lives in the SGGS image (SGGS.debug.dylib in Debug builds). A report that
    cannot be read counts as app code: unknown never earns a retry.
    """
    bad = []
    for ips in sorted(diagnostics.rglob("SGGS-*.ips")):
        if ips.name.startswith("SGGSUITests"):
            continue
        try:
            _, body = ips.read_text(encoding="utf-8", errors="replace").split("\n", 1)
            report = json.loads(body)
            images = report.get("usedImages", [])
            thread = report["threads"][report.get("faultingThread", 0)]
            names = [images[fr["imageIndex"]].get("name") or "" for fr in thread.get("frames", [])
                     if 0 <= fr.get("imageIndex", -1) < len(images)]
        except Exception:  # noqa: BLE001 - unreadable means "assume ours"
            bad.append(f"{ips.name} (unreadable)")
            continue
        if any(n == "SGGS" or n.startswith("SGGS.") for n in names):
            bad.append(ips.name)
    return bad


def main_thread_idle(spindump: str) -> bool:
    """True iff the spindump's SGGS process has a main thread with no app frame but the entry point.

    Anything unexpected (no SGGS process, no main thread, no entry frame) is False.
    """
    m = re.search(r"^Process: +SGGS \(.*?(?=^Process: |\Z)", spindump, re.S | re.M)
    if not m:
        return False
    block = m.group(0)
    t = re.search(r'^ +Thread \S+ +DispatchQueue "com\.apple\.main-thread".*?(?=^ +Thread |^ +Binary Images:|\Z)',
                  block, re.S | re.M)
    if not t:
        return False
    frames = t.group(0).splitlines()[1:]
    if not any(e in f for f in frames for e in ENTRY_FRAMES):
        return False
    return not any(APP_IMAGE.search(f) and not any(e in f for e in ENTRY_FRAMES) for f in frames)


def spindumps_for(spindumps: Path | None, ident: str) -> list[Path]:
    """Spindump attachments of one test, from `xcresulttool export attachments --filter 'Spindump*'`."""
    if spindumps is None:
        return []
    try:
        manifest = json.loads((spindumps / "manifest.json").read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return []
    return [spindumps / a["exportedFileName"] for t in manifest if t.get("testIdentifier") == ident
            for a in t.get("attachments", [])
            if str(a.get("suggestedHumanReadableName", "")).startswith("Spindump")
            and (spindumps / a.get("exportedFileName", "")).is_file()]


def ax_hang_is_idle(spindumps: Path | None, ident: str) -> bool:
    found = spindumps_for(spindumps, ident)
    try:
        return bool(found) and all(main_thread_idle(f.read_text(encoding="utf-8", errors="replace")) for f in found)
    except Exception:  # noqa: BLE001
        return False


def only_testing(ident: str) -> str:
    """'SGGSUITests/testX()' -> 'SGGSUITests/SGGSUITests/testX' (target/class/method)."""
    return f"{UI_TARGET}/{ident.removesuffix('()')}"


def plan(summary: dict, diagnostics: Path, spindumps: Path | None = None) -> tuple[list[str], str]:
    """Returns (ids to retry, reason). An empty list means: do not retry."""
    fails = failures(summary)
    if not fails:
        return [], "no failures"
    for i, t in fails:
        if AX_NOT_LOADED.search(t) and not ax_hang_is_idle(spindumps, i):
            return [], (f"{i}: accessibility did not load and no spindump shows the app's main thread "
                        "idle — it may be stuck in the app's own code")
    genuine = [f"{i}: {t}" for i, t in fails if not (is_infra(t) or AX_NOT_LOADED.search(t))]
    if genuine:
        return [], "not a simulator failure: " + "; ".join(genuine)
    if len(fails) > MAX_RETRIES:
        return [], f"{len(fails)} failures is more than a simulator hiccup (limit {MAX_RETRIES})"
    crashes = app_code_crashes(diagnostics)
    if crashes:
        return [], "the app crashed in its own code: " + ", ".join(crashes)
    ids = sorted({only_testing(i) for i, _ in fails})
    return ids, "simulator failures only"


def bundle_ok(name: str, summary: dict | None) -> tuple[bool, list[str]]:
    if summary is None:
        return False, [f"::error title={name}::no readable result bundle — the test step did not finish"]
    lines = []
    failed = summary.get("failedTests") or 0
    lines.append(f"{name}: {summary.get('result')} — passed {summary.get('passedTests')}, "
                 f"failed {failed}, skipped {summary.get('skippedTests')}")
    for ident, text in failures(summary):
        lines.append(f"FAILED {ident}: {text[:300]}")
        lines.append(f"::error title={name} test failed::{ident}: {text[:300]}")
    ok = not failed and summary.get("result") == "Passed" and bool(summary.get("passedTests"))
    return ok, lines


def gate(unit: dict | None, ui: dict | None, retry: dict | None, planned: list[str]) -> tuple[bool, list[str]]:
    ok_unit, out = bundle_ok("unit", unit)
    if ui is None or not planned:
        ok_ui, more = bundle_ok("uitests", ui)
        return ok_unit and ok_ui, out + more
    # The first UI run failed only for simulator reasons; the retry decides.
    first = {only_testing(i) for i, _ in failures(ui)}
    out.append(f"uitests: {ui.get('result')} — passed {ui.get('passedTests')}, "
               f"failed {ui.get('failedTests')}, skipped {ui.get('skippedTests')} (first run)")
    for ident, text in failures(ui):
        out.append(f"::warning title=uitests retried::{ident} failed for a simulator reason "
                   f"({text[:200]}) and was run once more")
    if first != set(planned):
        out.append(f"::error title=uitests::the retry plan {sorted(planned)} does not match the "
                   f"first run's failures {sorted(first)}")
        return False, out
    ok_retry, more = bundle_ok("uitests-retry", retry)
    out += more
    if ok_retry and (retry.get("passedTests") or 0) < len(planned):
        out.append(f"::error title=uitests-retry::ran {retry.get('passedTests')} of {len(planned)} retried tests")
        ok_retry = False
    return ok_unit and ok_retry, out


def _load(path: str) -> dict | None:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None


def main(argv: list[str]) -> int:
    if len(argv) in (3, 4) and argv[0] == "plan":
        summary = _load(argv[1])
        if summary is None:
            print("no readable UI summary: nothing to retry", file=sys.stderr)
            return 1
        ids, reason = plan(summary, Path(argv[2]), Path(argv[3]) if len(argv) == 4 else None)
        print(f"retry plan: {reason}", file=sys.stderr)
        print("\n".join(ids))
        return 0
    if argv[:1] == ["gate"] and len(argv) in (3, 5):
        planned = []
        retry = None
        if len(argv) == 5:
            planned = [ln.strip() for ln in Path(argv[4]).read_text().splitlines() if ln.strip()] \
                if Path(argv[4]).exists() else []
            retry = _load(argv[3])
        ok, lines = gate(_load(argv[1]), _load(argv[2]), retry, planned)
        print("\n".join(lines))
        return 0 if ok else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
