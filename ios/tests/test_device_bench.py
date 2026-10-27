"""Tests for ios/tools/device_bench.sh, run against fake xcodebuild / xcrun / make (no device)."""
import json
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ios" / "tools" / "device_bench.sh"
# Built at run time so no secret scanner reads a device identifier in this file.
UDID = "0000" + "8150" + "-" + "00AA11BB" + "22CC33DD"

FAKE_XCODEBUILD = """#!/usr/bin/env bash
echo "$@" >> "$FAKE_LOG"
case "$1" in
  -version) echo "Xcode 27.0"; echo "Build version 27A266a"; exit 0 ;;
esac
for a in "$@"; do case "$prev" in -resultBundlePath) mkdir -p "$a" ;; esac; prev=$a; done
echo "env checklist=${TEST_RUNNER_SGGS_DEVICE_CHECKLIST:-}" >> "$FAKE_LOG"
echo "${FAKE_OUT:-** TEST EXECUTE SUCCEEDED **}"
exit "${FAKE_RC:-0}"
"""
FAKE_XCRUN = """#!/usr/bin/env bash
echo "xcrun $@" >> "$FAKE_LOG"
if [ "$1 $2 $3" = "devicectl list devices" ]; then echo "S-iPhone   ${FAKE_UDID}   available (paired)   iPhone 17 Pro Max"; fi
exit 0
"""


@unittest.skipUnless(shutil.which("bash") and shutil.which("git"), "needs bash and git")
class DeviceBenchTests(unittest.TestCase):
    def setUp(self):
        # Not under /tmp: the script refuses bundles there (on Linux runners tempfile lives in /tmp).
        self._tmp = TemporaryDirectory(dir=Path.home(), prefix=".sggs-bench-test-")
        self.addCleanup(self._tmp.cleanup)
        t = Path(self._tmp.name)
        self.bin = t / "bin"
        self.bin.mkdir()
        for name, body in (("xcodebuild", FAKE_XCODEBUILD), ("xcrun", FAKE_XCRUN), ("make", "#!/bin/sh\nexit 0\n"),
                           ("sleep", "#!/bin/sh\nexit 0\n")):
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)
        self.wt = t / "wt"
        self.wt.mkdir()
        git = ["git", "-C", str(self.wt), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        (self.wt / "a.txt").write_text("one\n")
        subprocess.run(git + ["add", "a.txt"], check=True)
        subprocess.run(git + ["commit", "-qm", "one"], check=True)
        self.git = git
        self.dd = t / "dd"
        self.env_file = t / "device-bench.env"
        self.env_file.write_text(f"SGGS_DEVICE_UDID={UDID}\nSGGS_TEAM_ID=TEAMID0000\n"
                                 f"SGGS_ASC_KEY_PATH={t}/key-file\nSGGS_ASC_KEY_ID=KEYID00000\n"
                                 f"SGGS_ASC_ISSUER_ID=issuer\nSGGS_DERIVED_DATA={self.dd}\n")
        self.env_file.chmod(0o600)
        self.run_dir = t / "run" / "bundles"
        self.run_dir.mkdir(parents=True)
        self.log = t / "calls.log"

    def bench(self, *args, **env):
        e = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "SGGS_DEVICE_BENCH_ENV": str(self.env_file),
             "FAKE_LOG": str(self.log), "FAKE_UDID": UDID, **env}
        return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, env=e)

    def head_tree(self):
        out = subprocess.run(self.git[:3] + ["rev-parse", "HEAD", "HEAD^{tree}"], capture_output=True, text=True)
        return out.stdout.split()

    def test_build_writes_a_stamp_for_the_worktrees_tree(self):
        r = self.bench("build", str(self.wt))
        self.assertEqual(r.returncode, 0, r.stderr)
        stamp = json.loads((self.dd / "sggs-build-stamp.json").read_text())
        head, tree = self.head_tree()
        self.assertEqual((stamp["head"], stamp["tree"], stamp["dirty"], stamp["xcode"]), (head, tree, False, "27.0"))

    def test_a_failed_build_keeps_its_exit_code_and_leaves_no_stamp(self):
        r = self.bench("build", str(self.wt), FAKE_RC="65", FAKE_OUT="nothing grep would match")
        self.assertEqual(r.returncode, 65)
        self.assertFalse((self.dd / "sggs-build-stamp.json").exists())

    def test_a_dirty_build_is_stamped_dirty(self):
        (self.wt / "a.txt").write_text("changed\n")
        r = self.bench("build", str(self.wt))
        self.assertIn("dirty", r.stdout)
        self.assertTrue(json.loads((self.dd / "sggs-build-stamp.json").read_text())["dirty"])

    def test_tests_keep_xcodebuilds_exit_code(self):
        self.bench("build", str(self.wt))
        ok = self.bench("unit", str(self.wt), str(self.run_dir / "unit.xcresult"))
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertTrue((self.run_dir / "unit.log").exists())
        bad = self.bench("ui", str(self.wt), str(self.run_dir / "ui-01.xcresult"),
                         FAKE_RC="65", FAKE_OUT="no line the summary grep matches")
        self.assertEqual(bad.returncode, 65)
        self.assertIn("xcodebuild exit 65", bad.stdout)

    def test_an_existing_bundle_path_is_refused(self):
        self.bench("build", str(self.wt))
        (self.run_dir / "unit.xcresult").mkdir()
        r = self.bench("unit", str(self.wt), str(self.run_dir / "unit.xcresult"))
        self.assertEqual(r.returncode, 2)
        self.assertIn("fresh path", r.stderr)

    def test_a_build_for_another_tree_is_refused(self):
        self.bench("build", str(self.wt))
        (self.wt / "a.txt").write_text("two\n")
        subprocess.run(self.git + ["commit", "-qam", "two"], check=True)
        r = self.bench("unit", str(self.wt), str(self.run_dir / "unit.xcresult"))
        self.assertEqual(r.returncode, 2)
        self.assertIn("rebuild first", r.stderr)

    def test_checklist_sets_its_runner_variable_and_ui_passes_only_testing(self):
        self.bench("build", str(self.wt))
        self.bench("checklist", str(self.wt), str(self.run_dir / "checklist.xcresult"))
        self.bench("ui", str(self.wt), str(self.run_dir / "ui-02.xcresult"), "-only-testing:SGGSUITests/SGGSUITests/testA")
        calls = self.log.read_text()
        self.assertIn("env checklist=1", calls)
        self.assertIn("-only-testing:SGGSUITests/DeviceChecklistTests", calls)
        self.assertIn("-only-testing:SGGSUITests/SGGSUITests/testA", calls)

    def test_the_env_file_is_required_and_private(self):
        self.env_file.chmod(0o644)
        r = self.bench("check")
        self.assertEqual(r.returncode, 2)
        self.assertIn("600", r.stderr)
        r = self.bench("check", SGGS_DEVICE_BENCH_ENV=str(self.env_file) + ".missing")
        self.assertEqual(r.returncode, 2)

    def test_nothing_identifying_is_printed(self):
        r = self.bench("check")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("AVAILABLE", r.stdout)
        self.bench("build", str(self.wt))
        r2 = self.bench("unit", str(self.wt), str(self.run_dir / "unit.xcresult"))
        for out in (r.stdout + r.stderr, r2.stdout + r2.stderr):
            self.assertNotIn(UDID, out)
            self.assertNotIn("key-file", out)

    def test_tmp_bundle_paths_are_refused(self):
        self.bench("build", str(self.wt))
        r = self.bench("unit", str(self.wt), "/tmp/unit.xcresult")
        self.assertEqual(r.returncode, 2)
        self.assertIn("wiped", r.stderr)


class StaticTests(unittest.TestCase):
    def test_the_script_carries_no_identifiers(self):
        text = SCRIPT.read_text()
        self.assertIn("set -euo pipefail", text)
        self.assertIsNone(re.search(r"0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}", text))
        for bad in ("AuthKey_", "/Users/", "/tmp/dd"):
            self.assertNotIn(bad, text)
        self.assertNotIn("|| true; }", text, "a pipe ending in `|| true` would hide xcodebuild's exit code")


if __name__ == "__main__":
    unittest.main()
