"""The App Store SDK floor (ITMS-90725): one number, ios/tools/min-sdk-major, enforced everywhere.

1.7.5 (1) was archived on a CI runner with Xcode 26.3 / iphoneos26.2 while every local archive used
Xcode 27, and nothing objected: the floor was 26 in four places kept "in step" by a comment. These
tests pin the single source, the per-bundle check, the CI Xcode selector, and that no copy reappears.
Runs on Linux (no Xcode, no PlistBuddy)."""
import importlib.util, os, plistlib, re, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLOOR_FILE = ROOT / "ios" / "tools" / "min-sdk-major"
SELECT = ROOT / ".github" / "actions" / "select-xcode" / "select.sh"

_spec = importlib.util.spec_from_file_location("check_bundle_sdk", ROOT / "ios" / "tools" / "check_bundle_sdk.py")
cbs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cbs)


class FloorFile(unittest.TestCase):
    def test_floor_is_one_integer_and_at_least_27(self):
        text = FLOOR_FILE.read_text()
        self.assertRegex(text, r"\A[0-9]+\n?\Z")
        self.assertGreaterEqual(int(text), 27, "Apple requires the iOS 27 SDK from April 2027 (ITMS-90725)")

    def test_read_floor_rejects_garbage(self):
        with tempfile.TemporaryDirectory() as d:
            bad = Path(d) / "f"
            bad.write_text("27 # comment\n")
            with self.assertRaises(ValueError):
                cbs.read_floor(bad)


class NoSecondCopyOfTheFloor(unittest.TestCase):
    """Every gate reads the file; none hard-codes a number."""
    GATES = {
        "ios/tools/testflight_archive.sh": "ios/tools/min-sdk-major",
        "ios/tools/appstore_preflight.py": '"min-sdk-major"',
        "ios/tools/check_bundle_sdk.py": '"min-sdk-major"',
        ".github/actions/select-xcode/select.sh": "ios/tools/min-sdk-major",
    }

    def test_each_gate_reads_the_file(self):
        for rel, needle in self.GATES.items():
            self.assertIn(needle, (ROOT / rel).read_text(), rel)

    def test_no_hard_coded_floor_anywhere(self):
        pattern = re.compile(r"MIN_XCODE_MAJOR=[0-9]|MIN_SDK_MAJOR\s*=\s*[0-9]|-ge\s+2[0-9]\b|min-major:\s*\S*[0-9]")
        paths = [ROOT / r for r in self.GATES] + sorted((ROOT / ".github").rglob("*.yml"))
        hits = [f"{p.relative_to(ROOT)}:{n}: {line.strip()}"
                for p in paths for n, line in enumerate(p.read_text().splitlines(), 1) if pattern.search(line)]
        self.assertEqual(hits, [])

    def test_no_macos_job_runs_on_an_image_without_the_floor_xcode(self):
        floor = FLOOR_FILE.read_text().strip()
        for wf in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
            for label in re.findall(r"(?m)^\s*runs-on:\s*([^\s#]+)", wf.read_text()):
                if label.startswith(("macos", "xcode")):
                    self.assertEqual(label, f"xcode-{floor}", f"{wf.name}: runs-on {label}")

    def test_every_macos_job_selects_xcode_through_the_shared_action(self):
        for wf in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
            text = wf.read_text()
            if re.search(r"(?m)^\s*runs-on:\s*(macos|xcode)", text):
                self.assertIn("uses: ./.github/actions/select-xcode", text, wf.name)
                self.assertNotIn("xcode-select -s", text, f"{wf.name}: inline Xcode selection")


def _app(root, sdks):
    """A fake .app: sdks = {"SGGS.app": "iphoneos27.0", "PlugIns/W.appex": "...", ...}; None = no plist."""
    app = Path(root) / "SGGS.app"
    for rel, sdk in sdks.items():
        b = app if rel == "SGGS.app" else app / rel
        b.mkdir(parents=True, exist_ok=True)
        if sdk is not None:
            with (b / "Info.plist").open("wb") as fh:
                plistlib.dump({"DTSDKName": sdk} if sdk else {}, fh)
    return app


class EveryBundleIsChecked(unittest.TestCase):
    def check(self, sdks, floor=27):
        with tempfile.TemporaryDirectory() as d:
            return cbs.problems(_app(d, sdks), floor)

    def test_all_on_the_floor_pass(self):
        self.assertEqual(self.check({"SGGS.app": "iphoneos27.0", "PlugIns/SGGSWidgets.appex": "iphoneos27.2"}), [])

    def test_app_below_floor_fails(self):
        self.assertEqual(len(self.check({"SGGS.app": "iphoneos26.2"})), 1)

    def test_widget_below_floor_fails_even_when_the_app_passes(self):
        found = self.check({"SGGS.app": "iphoneos27.0", "PlugIns/SGGSWidgets.appex": "iphoneos26.2"})
        self.assertEqual(len(found), 1)
        self.assertIn("SGGSWidgets.appex", found[0])
        self.assertIn("ITMS-90725", found[0])

    def test_framework_below_floor_fails(self):
        self.assertEqual(len(self.check({"SGGS.app": "iphoneos27.0", "Frameworks/K.framework": "iphoneos26.0"})), 1)

    def test_unknown_or_missing_sdk_fails_closed(self):
        self.assertEqual(len(self.check({"SGGS.app": ""})), 1)
        self.assertEqual(len(self.check({"SGGS.app": "iphoneos27.0", "PlugIns/X.appex": None})), 1)

    def test_two_digit_minor_and_major_parse(self):
        self.assertEqual(cbs.sdk_major("iphoneos27.10"), 27)
        self.assertEqual(cbs.sdk_major("iphoneos100.0"), 100)
        self.assertIsNone(cbs.sdk_major("27.0"))

    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            app = _app(d, {"SGGS.app": "iphoneos26.2"})
            run = subprocess.run([sys.executable, str(ROOT / "ios/tools/check_bundle_sdk.py"), str(app)],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 1)
            self.assertIn("FAIL: SGGS.app", run.stderr)
            run = subprocess.run([sys.executable, str(ROOT / "ios/tools/check_bundle_sdk.py"), str(app), "26"],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)


@unittest.skipUnless(shutil.which("bash") and shutil.which("sort"), "needs bash")
class SelectXcode(unittest.TestCase):
    def select(self, names, floor=""):
        with tempfile.TemporaryDirectory() as d:
            for n in names:
                (Path(d) / n).mkdir()
            env = dict(os.environ, APPS_DIR=d, MIN_MAJOR=floor, SELECT_XCODE_DRY_RUN="1", GITHUB_WORKSPACE=str(ROOT))
            run = subprocess.run(["bash", str(SELECT)], env=env, capture_output=True, text=True)
            chosen = re.search(r"selected .*/(Xcode_[^/]+\.app)", run.stdout)
            return run.returncode, chosen.group(1) if chosen else None, run.stdout + run.stderr

    def test_newest_released_version_wins_by_version_not_string(self):
        rc, chosen, _ = self.select(["Xcode_26.3.app", "Xcode_27.2.app", "Xcode_27.10.app", "Xcode.app"])
        self.assertEqual((rc, chosen), (0, "Xcode_27.10.app"))

    def test_the_real_xcode_27_image_layout(self):   # actions/runner-images xcode-27-arm64 (2026-11-04)
        rc, chosen, _ = self.select(["Xcode_27.app", "Xcode_27.0.app", "Xcode_27.0.0.app", "Xcode_27.1.app",
                                     "Xcode_27.1.0.app", "Xcode_27.2.app", "Xcode_27.2.0.app", "Xcode.app"])
        self.assertEqual(rc, 0)
        self.assertIn(chosen, ("Xcode_27.2.app", "Xcode_27.2.0.app"))   # the same Xcode (one is a symlink)

    def test_betas_and_release_candidates_are_never_chosen(self):
        rc, chosen, _ = self.select(["Xcode_27.0.app", "Xcode_27.1_beta.app", "Xcode_28.0_RC.app", "Xcode_27.2-beta.app"])
        self.assertEqual((rc, chosen), (0, "Xcode_27.0.app"))

    def test_an_image_without_the_floor_xcode_fails(self):
        rc, chosen, out = self.select(["Xcode_26.3.app", "Xcode_16.4.app", "Xcode_27.1_beta.app"])
        self.assertNotEqual(rc, 0)
        self.assertIsNone(chosen)
        self.assertIn("::error::no released Xcode 27+", out)

    def test_default_floor_is_the_shared_file(self):
        rc, chosen, out = self.select(["Xcode_27.0.app"])
        self.assertIn(f"(floor {FLOOR_FILE.read_text().strip()})", out)

    def test_explicit_floor_input_wins(self):
        rc, chosen, _ = self.select(["Xcode_26.3.app"], floor="26")
        self.assertEqual((rc, chosen), (0, "Xcode_26.3.app"))

    def test_a_non_integer_floor_fails(self):
        rc, _, out = self.select(["Xcode_27.0.app"], floor="27a")
        self.assertNotEqual(rc, 0)
        self.assertIn("must be an integer", out)


if __name__ == "__main__":
    unittest.main()
