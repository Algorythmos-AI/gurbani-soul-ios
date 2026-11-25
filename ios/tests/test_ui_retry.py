"""Tests for ios/tools/ui_retry.py — the app job's test gate and its simulator-only retry."""
import importlib.util
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ui_retry", ROOT / "ios" / "tools" / "ui_retry.py")
ui_retry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ui_retry)

NO_PID = "Application 'org.sggs.app' does not have a process ID"
NOT_RUNNING = "Failed to application org.sggs.app is not running"
RUNNER = "Crash: SGGSUITests-Runner at _XCTRunnerRunTests"
AX = "Application 'org.sggs.app' has not loaded accessibility"

# The shape of XCTest's spindump of the app (1.7.7 attempt 3), trimmed to what the guard reads.
IDLE_MAIN = """\
Process:          SGGS (Gurbani Soul) [28652]
Identifier:       org.sggs.app

  Thread 0x149d8    DispatchQueue "com.apple.main-thread"(1)    271 samples (1-271)
  271  start + 6688 (dyld + 204416) [0x101201e80] 1-271
    271  __debug_main_executable_dylib_entry_point + 12 (SGGSApp.swift in SGGS.debug.dylib + 7410236) [0x1] 1-271
      271  static SGGSApp.$main() + 40 (<compiler-generated> in SGGS.debug.dylib + 7410172) [0x1] 1-271
{extra}        271  mach_msg + 20 (libsystem_kernel.dylib + 3804) [0x101140edc] 1-271

  Thread 0x14c33    DispatchQueue "AXBinaryMonitorQueue"(117)    271 samples (1-271)
  271  start_wqthread + 8 (libsystem_pthread.dylib + 6780) [0x1] 1-271
    271  Helper.run() + 8 (Helper.swift in SGGS.debug.dylib + 99) [0x1] 1-271

  Binary Images:
           0x103a98000 -        0x1046c3fff  SGGS.debug.dylib (0)

Process:          SpringBoard [1838]
"""
STUCK = "        271  ReaderModel.load() + 40 (ReaderModel.swift in SGGS.debug.dylib + 1234) [0x1] 1-271\n"


def summary(*fails, passed=85):
    return {
        "result": "Failed" if fails else "Passed",
        "passedTests": passed, "failedTests": len(fails), "skippedTests": 21,
        "testFailures": [{"testIdentifierString": i, "failureText": t} for i, t in fails],
    }


def crash_report(directory: Path, name: str, frame_images: list[str]) -> None:
    images = sorted(set(frame_images))
    body = {
        "faultingThread": 0,
        "usedImages": [{"name": n} for n in images],
        "threads": [{"frames": [{"imageIndex": images.index(n)} for n in frame_images]}],
    }
    (directory / name).write_text(json.dumps({"bug_type": "309"}) + "\n" + json.dumps(body))


class PlanTests(unittest.TestCase):
    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.diag = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_launch_without_a_process_id_is_retried(self):
        ids, _ = ui_retry.plan(summary(("BenchGuardTests/testBenchIsReadyForADeviceRun()", NO_PID)), self.diag)
        self.assertEqual(ids, ["SGGSUITests/BenchGuardTests/testBenchIsReadyForADeviceRun"])

    def test_an_os_crash_with_no_app_frame_is_retried(self):
        # 1.7.7 attempt 1: AXBinaryMonitor read a bar button's tintColor off the main thread.
        crash_report(self.diag, "SGGS-2026-11-25-112132.ips",
                     ["libobjc.A.dylib", "UIKitCore", "AXCoreUtilities", "libdispatch.dylib"])
        ids, _ = ui_retry.plan(summary(("SGGSUITests/testRapidChevronTapsStayInSync()", NOT_RUNNING),
                                       ("SGGSUITests/testRapidTapsNeverStrandSheets()", RUNNER)), self.diag)
        self.assertEqual(ids, ["SGGSUITests/SGGSUITests/testRapidChevronTapsStayInSync",
                               "SGGSUITests/SGGSUITests/testRapidTapsNeverStrandSheets"])

    def test_a_crash_in_the_apps_own_code_is_never_retried(self):
        for image in ("SGGS", "SGGS.debug.dylib"):
            with self.subTest(image=image):
                crash_report(self.diag, "SGGS-2026-11-25-1.ips", ["libsystem_kernel.dylib", image])
                ids, reason = ui_retry.plan(summary(("SGGSUITests/testX()", NOT_RUNNING)), self.diag)
                self.assertEqual(ids, [])
                self.assertIn("own code", reason)

    def test_an_unreadable_app_crash_report_is_never_retried(self):
        (self.diag / "SGGS-2026-11-25-2.ips").write_text("not json")
        ids, _ = ui_retry.plan(summary(("SGGSUITests/testX()", NOT_RUNNING)), self.diag)
        self.assertEqual(ids, [])

    def test_the_runners_own_crash_report_does_not_block(self):
        crash_report(self.diag, "SGGSUITests-Runner-2026-11-25-3.ips", ["SGGSUITests", "XCTest"])
        ids, _ = ui_retry.plan(summary(("SGGSUITests/testX()", RUNNER)), self.diag)
        self.assertEqual(ids, ["SGGSUITests/SGGSUITests/testX"])

    def test_an_assertion_failure_is_never_retried(self):
        ids, reason = ui_retry.plan(summary(("A/testX()", NO_PID),
                                            ("A/testY()", "XCTAssertEqual failed: (\"Ang 1\") is not equal to (\"Ang 2\")")),
                                    self.diag)
        self.assertEqual(ids, [])
        self.assertIn("testY", reason)

    def test_more_than_three_failures_is_never_retried(self):
        fails = [(f"A/test{i}()", NO_PID) for i in range(4)]
        self.assertEqual(ui_retry.plan(summary(*fails), self.diag)[0], [])

    def spindump(self, ident: str, text: str) -> Path:
        out = self.diag / "spindumps"
        out.mkdir(exist_ok=True)
        (out / "A1.txt").write_text(text)
        (out / "manifest.json").write_text(json.dumps([{"testIdentifier": ident, "attachments": [
            {"exportedFileName": "A1.txt", "suggestedHumanReadableName": "Spindump_0_X.txt"}]}]))
        return out

    def test_accessibility_not_loaded_with_an_idle_main_thread_is_retried(self):
        # 1.7.7 attempt 3: the main thread sat in its run loop; AXBinaryMonitorQueue was starved.
        # An app frame on another thread does not matter; only the main thread is judged.
        sp = self.spindump("SGGSUITests/testX()", IDLE_MAIN.format(extra=""))
        ids, _ = ui_retry.plan(summary(("SGGSUITests/testX()", AX)), self.diag, sp)
        self.assertEqual(ids, ["SGGSUITests/SGGSUITests/testX"])

    def test_accessibility_not_loaded_with_app_code_on_the_main_thread_is_never_retried(self):
        sp = self.spindump("SGGSUITests/testX()", IDLE_MAIN.format(extra=STUCK))
        ids, reason = ui_retry.plan(summary(("SGGSUITests/testX()", AX)), self.diag, sp)
        self.assertEqual(ids, [])
        self.assertIn("main thread", reason)

    def test_accessibility_not_loaded_without_a_spindump_is_never_retried(self):
        for sp in (None, self.diag / "missing"):
            with self.subTest(spindumps=sp):
                self.assertEqual(ui_retry.plan(summary(("SGGSUITests/testX()", AX)), self.diag, sp)[0], [])

    def test_a_spindump_of_another_test_does_not_count(self):
        sp = self.spindump("SGGSUITests/testOther()", IDLE_MAIN.format(extra=""))
        self.assertEqual(ui_retry.plan(summary(("SGGSUITests/testX()", AX)), self.diag, sp)[0], [])

    def test_an_unrecognisable_spindump_is_never_retried(self):
        for text in ("garbage", IDLE_MAIN.replace("com.apple.main-thread", "other"),
                     IDLE_MAIN.replace("SGGS (Gurbani Soul)", "Other (x)")):
            with self.subTest(text=text[:20]):
                sp = self.spindump("SGGSUITests/testX()", text.replace("{extra}", ""))
                self.assertEqual(ui_retry.plan(summary(("SGGSUITests/testX()", AX)), self.diag, sp)[0], [])

    def test_no_failures_means_no_retry(self):
        self.assertEqual(ui_retry.plan(summary(), self.diag)[0], [])


class GateTests(unittest.TestCase):
    UNIT = summary(passed=522)
    FIRST = summary(("BenchGuardTests/testBenchIsReadyForADeviceRun()", NO_PID))
    PLANNED = ["SGGSUITests/BenchGuardTests/testBenchIsReadyForADeviceRun"]

    def test_green_bundles_pass(self):
        self.assertTrue(ui_retry.gate(self.UNIT, summary(), None, [])[0])

    def test_a_ui_failure_without_a_retry_fails(self):
        self.assertFalse(ui_retry.gate(self.UNIT, self.FIRST, None, [])[0])

    def test_a_passing_retry_passes_and_warns(self):
        ok, lines = ui_retry.gate(self.UNIT, self.FIRST, summary(passed=1), self.PLANNED)
        self.assertTrue(ok)
        self.assertTrue(any(ln.startswith("::warning") and "testBenchIsReadyForADeviceRun" in ln for ln in lines))

    def test_a_failing_retry_fails(self):
        retry = summary(("BenchGuardTests/testBenchIsReadyForADeviceRun()", NO_PID), passed=0)
        self.assertFalse(ui_retry.gate(self.UNIT, self.FIRST, retry, self.PLANNED)[0])

    def test_a_missing_retry_bundle_fails(self):
        self.assertFalse(ui_retry.gate(self.UNIT, self.FIRST, None, self.PLANNED)[0])

    def test_a_retry_that_ran_fewer_tests_than_planned_fails(self):
        planned = self.PLANNED + ["SGGSUITests/SGGSUITests/testX"]
        first = summary(("BenchGuardTests/testBenchIsReadyForADeviceRun()", NO_PID), ("SGGSUITests/testX()", NO_PID))
        self.assertFalse(ui_retry.gate(self.UNIT, first, summary(passed=1), planned)[0])

    def test_a_plan_that_does_not_match_the_failures_fails(self):
        self.assertFalse(ui_retry.gate(self.UNIT, self.FIRST, summary(passed=1), ["SGGSUITests/A/testOther"])[0])

    def test_a_failed_unit_bundle_still_fails_after_a_good_retry(self):
        unit = summary(("GurbaniTests/testX()", "XCTAssertTrue failed"), passed=521)
        self.assertFalse(ui_retry.gate(unit, self.FIRST, summary(passed=1), self.PLANNED)[0])

    def test_missing_bundles_fail(self):
        self.assertFalse(ui_retry.gate(None, summary(), None, [])[0])
        self.assertFalse(ui_retry.gate(self.UNIT, None, None, [])[0])


if __name__ == "__main__":
    unittest.main()
