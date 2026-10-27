"""Tests for ios/tools/device_run.py — device runs as checkable evidence.

CI has no device and no xcrun: every xcresulttool call is answered from captured JSON under
fixtures/device_run/ (`unit` is the real 1.5.0 RC unit bundle from S-iPhone, scrubbed; `ui`,
`checklist` and `rerun-1` follow xcresulttool 3.60's output for UI-test bundles).
"""
import argparse
import importlib.util
import io
import json
import os
import plistlib
import shutil
import tarfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("device_run", ROOT / "ios" / "tools" / "device_run.py")
dr = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dr)
FIX = Path(__file__).resolve().parent / "fixtures" / "device_run"

HEAD = "a" * 40
TREE = "b" * 40
T0 = 1793117105.632                      # the unit fixture's start: 2026-10-27T16:05:05Z
BEGIN = dr.from_epoch(T0 - 60)
# Built at run time so no secret scanner reads a device identifier in this file.
UDID = "0000" + "8150" + "-" + "00081CEE" + "2238401C"


def fixture_ids():
    ids = set()
    for name in ("unit", "ui", "checklist", "rerun-1"):
        ids |= {c["nodeIdentifier"] for c in dr.walk_cases(json.loads((FIX / name / "tests.json").read_text())["testNodes"])}
    return sorted(ids)


class FixtureHost(dr.Host):
    """git, devicectl and xcresulttool answered from fixtures; `mutate[stem]` edits a bundle's JSON."""

    def __init__(self, head=HEAD, tree=TREE, dirty="", locked=False, free=50.0, name="S-iPhone"):
        self.head, self.tree, self.dirty, self.free = head, tree, dirty, free
        self.dev = {"name": name, "model": "iPhone 17 Pro Max", "ios": "27.0.1", "transport": "wired",
                    "tunnel": "connected", "locked": locked}
        self.mutate = {}
        self.http_calls = []

    def git(self, *args, cwd=None):
        return {("rev-parse", "HEAD"): self.head, ("rev-parse", "HEAD^{tree}"): self.tree,
                ("rev-parse", "--abbrev-ref", "HEAD"): "release/1.5.0"}.get(args, self.dirty)

    def xcode(self):
        return "27.0"

    def free_gb(self, path):
        return self.free

    def device(self):
        return dict(self.dev)

    def xcresult(self, *args):
        path = Path(args[args.index("--path") + 1])
        src = FIX / path.stem
        if args[0] == "export":
            out = Path(args[args.index("--output-path") + 1])
            manifest = json.loads((src / "manifest.json").read_text())
            if "manifest" in self.mutate.get(path.stem, {}):
                manifest = self.mutate[path.stem]["manifest"](manifest)
            if manifest:
                (out / "manifest.json").write_text(json.dumps(manifest))
            if (src / "attachments").exists():
                for f in (src / "attachments").iterdir():
                    shutil.copyfile(f, out / f.name)
            for name, text in self.mutate.get(path.stem, {}).get("files", {}).items():
                (out / name).write_text(text)
            return ""
        kind = args[2]
        doc = json.loads((src / f"{kind}.json").read_text())
        fn = self.mutate.get(path.stem, {}).get(kind)
        return json.dumps(fn(doc) if fn else doc)


def make_bundle(run_dir, name, root_id=None, finished=True):
    b = Path(run_dir) / "bundles" / f"{name}.xcresult"
    (b / "Data").mkdir(parents=True)
    (b / "Data" / "data.0").write_bytes(f"payload of {name}".encode())
    if finished:
        (b / "Info.plist").write_bytes(plistlib.dumps({"rootId": {"hash": root_id or f"0~{name}-root"},
                                                       "version": {"major": 3, "minor": 60}}))
    return b


def ns(**kw):
    return argparse.Namespace(**kw)


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.runs = self.tmp / "device-runs"
        self.runs.mkdir()
        self.staging = self.tmp / "staging"
        self.stamp = self.tmp / "stamp.json"
        self.stamp.write_text(json.dumps({"head": HEAD, "tree": TREE, "dirty": False, "configuration": "Debug",
                                          "built_at": "2026-10-27T15:50:00Z"}))
        self.planned = self.tmp / "planned.txt"
        self.planned.write_text("\n".join(fixture_ids()) + "\n")
        self.version = dr.marketing_version(ROOT)
        self.host = FixtureHost()
        for patcher in (mock.patch.object(dr, "wiped_roots", lambda: ()),   # tests live in the temp dir
                        mock.patch("sys.stdout", new_callable=io.StringIO)):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.addCleanup(self._tmp.cleanup)

    def begin(self, host=None, **over):
        args = dict(version=self.version, expect=HEAD, stamp=str(self.stamp), attest=",".join(dr.ATTESTATIONS),
                    staging=str(self.staging), device_name="S-iPhone", planned=str(self.planned),
                    operator="supervisor")
        args.update(over)
        return dr.cmd_begin(ns(**args), host=host or self.host, root=ROOT, now=BEGIN)

    def run_dir(self):
        return next((self.staging / self.version).iterdir())

    def full_run(self, bundles=("unit", "ui", "checklist", "rerun-1"), manual=True):
        self.assertEqual(self.begin(), 0)
        rd = self.run_dir()
        for b in bundles:
            make_bundle(rd, b)
        if manual:
            for row in dr.MANUAL_ROWS:
                dr.cmd_record_manual(ns(run_dir=str(rd), row=row, result="pass", note="checked by hand",
                                        tester="owner"))
            dr.cmd_record_manual(ns(run_dir=str(rd), row="restore", result="pass", note="ordinary launch",
                                    tester="supervisor"))
        return rd

    def summarize(self, rd, cause=None, no_tar=False):
        return dr.cmd_summarize(ns(run_dir=str(rd), cause=cause, out=None, no_tar=no_tar),
                                host=self.host, runs_dir=self.runs)

    def summary(self, rd):
        return json.loads((rd / "summary.json").read_text())


# ---------------------------------------------------------------- pure helpers

class HelperTests(unittest.TestCase):
    def test_classify_every_bench_cause(self):
        cases = {
            "Timed out while enabling automation mode.": "env:locked",
            "CoreDeviceError error 10003 (the device is locked)": "env:locked",
            "Failed to launch app: The request was denied by service delegate (FBSOpenApplicationErrorDomain error 7)": "env:locked",
            "Could not launch “SGGS”: Developer App Certificate is not trusted": "env:cert",
            "Lost connection to the test runner": "env:tunnel",
            "BENCH: the device orientation is landscape": "env:landscape",
            "BENCH: org.sggs.app is not in the foreground (another app is)": "env:foreground",
            "XCTAssertTrue failed - Saved verses row missing": "unknown",
        }
        for text, cause in cases.items():
            self.assertEqual(dr.classify(text), cause, text)

    def test_a_landscape_failure_screenshot_names_the_cause(self):
        self.assertEqual(dr.classify("XCTAssertTrue failed", [(956, 440)]), "env:landscape")
        self.assertEqual(dr.classify("XCTAssertTrue failed", [(440, 956)]), "unknown")

    def test_attachment_names_lose_xcresulttools_suffix(self):
        self.assertEqual(dr.attachment_name("D2 paste with saroop on_0_63D03733-C535-415A-B880-DC601EEE9AD4.txt"),
                         "D2 paste with saroop on")
        self.assertEqual(dr.attachment_name("plain"), "plain")

    def test_scrub_text_removes_what_must_not_be_published(self):
        text = (f"/Users/someone/dev/x/ios/App/Tests/UI/SGGSUITests.swift:812: device {UDID} "
                "mail a@b.org key ~/.appstoreconnect/private_keys/AuthKey_X.p8 /Users/someone/elsewhere")
        out = dr.scrub_text(text)
        self.assertIn("ios/App/Tests/UI/SGGSUITests.swift:812", out)
        self.assertEqual(dr.scrub_findings(out), [])
        self.assertEqual(set(dr.scrub_findings(text)), {"a device UDID", "a host path", "an App Store Connect key name",
                                                        "a .p8 key file", "a private_keys path", "an email address"})

    def test_refuse_temp(self):
        for bad in ("/tmp/x", "/private/tmp/claude-501/scratchpad/run"):
            with self.assertRaises(dr.Refusal):
                dr.refuse_temp(bad)
        dr.refuse_temp(str(Path.home() / "SGGS-device-evidence"))

    def test_png_size(self):
        data = (FIX / "ui" / "attachments").iterdir().__next__().read_bytes()
        self.assertEqual(dr.png_size(data), (4, 2))
        self.assertIsNone(dr.png_size(b"not a png"))

    def test_planned_from_sources_reads_classes_and_extensions(self):
        with TemporaryDirectory() as t:
            d = Path(t) / "ios" / "App" / "Tests" / "UI"
            d.mkdir(parents=True)
            (d / "A.swift").write_text(
                "final class ATests: XCTestCase {\n    func testOne() {}\n    func helper() {}\n"
                "    @MainActor func testTwo() async throws {}\n    func testWithArg(_ x: Int) {}\n}\n"
                "extension ATests {\n    func testThree() throws {}\n}\n")
            self.assertEqual(dr.planned_from_sources(Path(t)),
                             ["ATests/testOne()", "ATests/testThree()", "ATests/testTwo()"])

    def test_every_automated_checklist_row_names_a_real_test(self):
        planned = set(dr.planned_from_sources(ROOT))
        for row, (_, test) in dr.CHECKLIST.items():
            if test:
                self.assertIn(test, planned, row)
        self.assertIn(dr.D5_APP_HALF, planned)

    def test_the_checklist_report_reads_the_same_rows(self):
        spec = importlib.util.spec_from_file_location("report", ROOT / "ios" / "tools" / "device_checklist_report.py")
        report = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(report)
        self.assertEqual(sorted(report.ROWS.values()),
                         sorted(t.split("/", 1)[1] for _, t in dr.CHECKLIST.values() if t))

    def test_deterministic_tar_ignores_times_and_the_query_cache(self):
        with TemporaryDirectory() as t:
            b = make_bundle(t, "unit")
            one = dr.deterministic_tar(b, Path(t) / "one.tar.gz")
            os.utime(b / "Data" / "data.0", (1, 1))
            (b / "database.sqlite3").write_bytes(b"cache written by xcresulttool on read")
            two = dr.deterministic_tar(b, Path(t) / "two.tar.gz")
            self.assertEqual(one, two)
            with tarfile.open(Path(t) / "two.tar.gz") as tar:
                names = tar.getnames()
            self.assertIn("unit.xcresult/Info.plist", names)
            self.assertNotIn("unit.xcresult/database.sqlite3", names)

    def test_parse_launch_from_the_timings_note(self):
        f = next(p for p in (FIX / "checklist" / "attachments").iterdir() if p.suffix == ".txt"
                 and "process start" in p.read_text())
        launch = dr.parse_launch([{"name": "D10 timings", "file": str(f)}])
        self.assertEqual(launch["cold"]["nitnemDrawn"], 1.31)
        self.assertEqual(launch["warm"]["nitnemDrawn"], 0.88)
        self.assertEqual(launch["xctest_clock"], {"cold": 4.02, "warm": 2.11})

    def test_parse_launch_prefers_the_json_attachment(self):
        with TemporaryDirectory() as t:
            f = Path(t) / "t.json"
            f.write_text(json.dumps({"cold": {"since_process_start": {"nitnemDrawn": 2.5}, "cached_hash": False},
                                     "warm": {"since_process_start": {"nitnemDrawn": 1.0}, "cached_hash": True},
                                     "xctest_clock": {"cold": 6.8, "warm": 4.3}}))
            launch = dr.parse_launch([{"name": "D10 launch timeline", "file": str(f)}])
        self.assertEqual((launch["cold"]["nitnemDrawn"], launch["warm"]["nitnemDrawn"]), (2.5, 1.0))
        self.assertEqual(launch["xctest_clock"]["cold"], 6.8)


class JudgeTests(unittest.TestCase):
    def a(self, outcome, cause=None, bundle="ui", skip=None):
        return {"outcome": outcome, "duration": 1.0, "failure": "boom" if outcome == "Failed" else None,
                "cause": cause, "bundle": bundle, "skip": skip}

    def test_pass(self):
        self.assertIsNone(dr.judge_test("T/t()", [self.a("Passed")])[1])

    def test_an_env_failure_with_a_passing_rerun_is_a_recorded_flake(self):
        rec, problem = dr.judge_test("T/t()", [self.a("Failed", "env:locked"), self.a("Passed", bundle="rerun-1")])
        self.assertIsNone(problem)
        self.assertEqual((rec["outcome"], rec["cause"], rec["reruns"][0]["outcome"]), ("Passed", "env:locked", "Passed"))

    def test_a_failure_without_a_rerun_is_incomplete(self):
        self.assertEqual(dr.judge_test("T/t()", [self.a("Failed", "unknown")])[1][0], "INCOMPLETE")

    def test_two_failures_in_a_row_fail_the_run(self):
        problem = dr.judge_test("T/t()", [self.a("Failed", "env:tunnel"), self.a("Failed", "unknown"),
                                          self.a("Passed")])[1]
        self.assertEqual(problem[0], "FAIL")

    def test_a_code_failure_fails_even_when_a_rerun_passes(self):
        self.assertEqual(dr.judge_test("T/t()", [self.a("Failed", "code"), self.a("Passed")])[1][0], "FAIL")

    def test_skips(self):
        allowed = self.a("Skipped", skip="capture-only: set TEST_RUNNER_SGGS_SHOT_DIR")
        self.assertIsNone(dr.judge_test("T/t()", [allowed])[1])
        other = self.a("Skipped", skip="bundled DB not found in host app")
        self.assertEqual(dr.judge_test("T/t()", [other])[1][0], "INCOMPLETE")
        rec, problem = dr.judge_test("T/t()", [other, self.a("Passed", bundle="checklist")])
        self.assertEqual((rec["outcome"], problem), ("Passed", None))

    def test_expected_failure_counts_as_passed(self):
        self.assertIsNone(dr.judge_test("T/t()", [self.a("Expected Failure")])[1])


# ---------------------------------------------------------------- begin

class BeginTests(Base):
    def test_begin_records_the_run_without_the_udid(self):
        with mock.patch.dict(os.environ, {"SGGS_DEVICE_UDID": UDID}):
            self.assertEqual(self.begin(), 0)
        rd = self.run_dir()
        self.assertEqual(rd.name, f"20261027T1604Z-{TREE[:7]}")
        self.assertTrue((rd / "bundles").is_dir())
        run = json.loads((rd / "run.json").read_text())
        self.assertEqual((run["source"]["commit"], run["source"]["tree"], run["source"]["stamp_tree"]),
                         (HEAD, TREE, TREE))
        self.assertEqual(run["device"], {"name": "S-iPhone", "model": "iPhone 17 Pro Max", "ios": "27.0.1"})
        self.assertEqual(run["connection"]["transport"], "wired")
        self.assertEqual(run["planned_tests"], fixture_ids())
        self.assertNotIn(UDID, (rd / "run.json").read_text())

    def refused(self, host=None, **over):
        with self.assertRaises(dr.Refusal) as e:
            self.begin(host=host, **over)
        return str(e.exception)

    def test_refusals(self):
        self.assertIn("full 40-character", self.refused(expect=HEAD[:7]))
        self.assertIn("wrong commit", self.refused(expect="c" * 40))
        self.assertIn("uncommitted", self.refused(host=FixtureHost(dirty=" M ios/App/x.swift")))
        self.assertIn("build stamp", self.refused(host=FixtureHost(tree="d" * 40)))
        self.assertIn("has not attested", self.refused(attest="unlocked,dnd"))
        self.assertIn("unknown attestation", self.refused(attest=",".join(dr.ATTESTATIONS) + ",trust-me"))
        self.assertIn("locked", self.refused(host=FixtureHost(locked=True)))
        self.assertIn("GB free", self.refused(host=FixtureHost(free=3.0)))
        self.assertIn("not 'S-iPhone'", self.refused(host=FixtureHost(name="Other iPhone")))
        self.assertIn("MARKETING_VERSION", self.refused(version="0.0.1"))
        self.assertFalse(self.staging.joinpath(self.version).exists() and any(self.staging.joinpath(self.version).iterdir()))

    def test_a_dirty_stamp_is_refused(self):
        self.stamp.write_text(json.dumps({"head": HEAD, "tree": TREE, "dirty": True}))
        self.assertIn("dirty", self.refused())

    def test_an_existing_run_folder_is_refused(self):
        self.assertEqual(self.begin(), 0)
        self.assertIn("fresh folder", self.refused())

    def test_staging_under_tmp_is_refused(self):
        with mock.patch.object(dr, "wiped_roots", lambda: (str(self.tmp),)):
            self.assertIn("wiped", self.refused())


# ---------------------------------------------------------------- summarize

class SummarizeTests(Base):
    def test_a_complete_run_passes(self):
        rd = self.full_run()
        self.assertEqual(self.summarize(rd), 0)
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "PASS", s["verdict_reasons"])
        self.assertEqual([b["name"] for b in s["bundles"]], ["unit", "ui", "checklist", "rerun-1"])
        tests = {t["id"]: t for t in s["tests"]}
        self.assertEqual(len(tests), len(fixture_ids()))
        self.assertEqual(sum(1 for t in tests.values() if t["outcome"] == "Passed"), len(tests) - 1)
        jump = tests["SGGSUITests/testReaderJumpAndSwipe()"]
        self.assertEqual((jump["cause"], jump["reruns"][0]["bundle"], jump["outcome"]), ("env:locked", "rerun-1", "Passed"))
        self.assertEqual(jump["failure"], "SGGSUITests.swift:812: Timed out while enabling automation mode.")
        self.assertEqual(tests["SGGSUITests/testThemesIndexSearch()"]["cause"], "env:landscape")
        nitnem = tests["SGGSUITests/testNitnemOpensJapjiAndCompletes()"]
        self.assertEqual((nitnem["cause"], nitnem["reruns"][0]["bundle"]), ("env:locked", "ui"))
        self.assertTrue(tests["SGGSUITests/testCaptureScreens()"]["skip_allowed"])
        self.assertEqual(tests["DeviceChecklistTests/testD2CopyIsVerbatimWithSaroopOnAndOff()"]["outcome"], "Passed")
        for row in ("D2", "D3", "D6", "D10", "D11", "D12"):
            self.assertEqual(s["checklist"][row]["result"], "pass", row)
        self.assertEqual(len(s["checklist"]["D3"]["attachments"]), 8)
        self.assertEqual(s["checklist"]["D5"]["app_half"]["outcome"], "Passed")
        self.assertEqual(s["launch"]["cold"]["nitnemDrawn"], 1.31)
        self.assertEqual(s["env"]["incidents"], ["env:landscape", "env:locked"])
        self.assertEqual(s["env"]["restore_launch"]["result"], "pass")
        # the tracked copy, its sums and the public screens
        out = self.runs / self.version / rd.name
        self.assertEqual((out / "summary.json").read_text(), (rd / "summary.json").read_text())
        sums = (rd / "upload" / "SHA256SUMS").read_text().split("\n")
        self.assertEqual(len([x for x in sums if x]), 4)
        for b in s["bundles"]:
            self.assertEqual(dr.sha256_file(rd / "upload" / b["asset"]), b["tar_sha256"])
            self.assertEqual(b["asset_url"], f"https://github.com/{dr.EVIDENCE_REPO}/releases/download/"
                                             f"ios-{self.version}-{rd.name}/{b['name']}.tar.gz")
        self.assertEqual(len(s["public_evidence"]["files"]), 10)    # D2 has no images; D3 8, D11 2
        self.assertEqual(dr.cmd_check(ns(run_dirs=[]), runs_dir=self.runs), 0)

    def test_summarize_is_repeatable(self):
        rd = self.full_run()
        self.summarize(rd)
        first = (rd / "summary.json").read_bytes()
        self.summarize(rd)
        self.assertEqual((rd / "summary.json").read_bytes(), first)

    def test_without_the_rerun_the_run_is_incomplete(self):
        rd = self.full_run(bundles=("unit", "ui", "checklist"))
        self.summarize(rd)
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "INCOMPLETE")
        self.assertEqual(len([r for r in s["verdict_reasons"] if "no passing rerun" in r]), 2)

    def test_a_rerun_that_fails_again_fails_the_run(self):
        rd = self.full_run()

        def again(doc):
            for c in dr.walk_cases(doc["testNodes"]):
                if c["name"] == "testReaderJumpAndSwipe()":
                    c["result"] = "Failed"
                    c["children"] = [{"nodeType": "Failure Message", "name": "Timed out while enabling automation mode."}]
            return doc
        self.host.mutate["rerun-1"] = {"tests": again}
        self.summarize(rd)
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "FAIL")
        self.assertTrue(any("twice in a row" in r for r in s["verdict_reasons"]))

    def test_an_operator_can_call_a_failure_code(self):
        rd = self.full_run()
        self.summarize(rd, cause=["SGGSUITests/testThemesIndexSearch()=code"])
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "FAIL")
        with self.assertRaises(dr.Refusal):
            self.summarize(rd, cause=["SGGSUITests/testThemesIndexSearch()=flaky"])

    def test_manual_rows_and_the_restore_launch_are_required(self):
        rd = self.full_run(manual=False)
        self.summarize(rd)
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "INCOMPLETE")
        for row in dr.MANUAL_ROWS:
            self.assertTrue(any(r.startswith(f"{row} ") and "pending" in r for r in s["verdict_reasons"]), row)
        self.assertTrue(any("restore launch" in r for r in s["verdict_reasons"]))

    def test_a_deferred_manual_row_passes_loudly_and_a_failed_one_fails(self):
        rd = self.full_run()
        dr.cmd_record_manual(ns(run_dir=str(rd), row="D4", result="deferred",
                                note="no App Store build on the phone; owner checks after release", tester="owner"))
        with mock.patch("sys.stdout") as out:
            self.summarize(rd)
        self.assertEqual(self.summary(rd)["verdict"], "PASS")
        self.assertIn("DEFERRED", "".join(str(c) for c in out.write.call_args_list))
        self.assertIn("**DEFERRED**", (rd / "summary.md").read_text())
        dr.cmd_record_manual(ns(run_dir=str(rd), row="D9", result="fail", note="asked for network", tester="owner"))
        self.summarize(rd)
        self.assertEqual(self.summary(rd)["verdict"], "FAIL")

    def test_a_slow_in_app_launch_fails_d10(self):
        rd = self.full_run()
        note = next(p for p in (FIX / "checklist" / "attachments").iterdir()
                    if p.suffix == ".txt" and "process start" in p.read_text())
        self.host.mutate["checklist"] = {"files": {note.name: note.read_text().replace('"nitnemDrawn":1.31',
                                                                                       '"nitnemDrawn":5.4')}}
        self.summarize(rd, no_tar=True)
        s = self.summary(rd)
        self.assertEqual(s["verdict"], "FAIL")
        self.assertTrue(any("D10 cold launch 5.40 s" in r for r in s["verdict_reasons"]))

    def test_identical_screens_under_two_names_do_not_pass_a_row(self):
        rd = self.full_run()

        def twin(manifest):
            for entry in manifest:
                if entry["testIdentifier"].endswith("testD3RenderingLightAndDarkAtAX3()"):
                    entry["attachments"][1]["exportedFileName"] = entry["attachments"][0]["exportedFileName"]
            return manifest
        self.host.mutate["checklist"] = {"manifest": twin}
        self.summarize(rd)
        s = self.summary(rd)
        self.assertEqual(s["checklist"]["D3"]["result"], "incomplete")
        self.assertTrue(any("identical image" in w for w in s["warnings"]))

    def test_planned_tests_that_never_ran_make_it_incomplete(self):
        self.planned.write_text("\n".join(fixture_ids() + ["SGGSUITests/testNeverRan()"]) + "\n")
        rd = self.full_run()
        self.summarize(rd)
        s = self.summary(rd)
        self.assertEqual((s["verdict"], s["not_run"]), ("INCOMPLETE", ["SGGSUITests/testNeverRan()"]))

    def test_a_failed_bench_probe_explains_the_bundles_unknown_failures(self):
        rd = self.full_run()

        def probe(doc):
            for c in dr.walk_cases(doc["testNodes"]):
                if c["name"].startswith("testBenchIsReady"):
                    c["result"] = "Failed"
                    c["children"] = [{"nodeType": "Failure Message",
                                      "name": "BENCH: org.sggs.app is not in the foreground (AlgoMinutes is)"}]
            return doc
        self.host.mutate["ui"] = {"tests": probe, "manifest": lambda m: []}
        self.summarize(rd)
        tests = {t["id"]: t for t in self.summary(rd)["tests"]}
        self.assertEqual(tests["SGGSUITests/testThemesIndexSearch()"]["cause"], "env:foreground")
        self.assertEqual(tests["SGGSUITests/testReaderJumpAndSwipe()"]["cause"], "env:locked")

    def test_nothing_identifying_reaches_the_summary(self):
        rd = self.full_run()

        def leak(doc):
            for d in doc["devices"]:
                d["deviceId"] = UDID
            for c in dr.walk_cases(doc["testNodes"]):
                for k in c.get("children", []):
                    if k["nodeType"] == "Failure Message":
                        k["name"] = f"/Users/someone/dev/w/ios/App/Tests/UI/{k['name']} on {UDID}"
            return doc
        self.host.mutate["ui"] = {"tests": leak}
        self.summarize(rd)
        for name in ("summary.json", "summary.md"):
            text = (self.runs / self.version / rd.name / name).read_text()
            self.assertEqual(dr.scrub_findings(text), [], name)
        jump = next(t for t in self.summary(rd)["tests"] if t["id"] == "SGGSUITests/testReaderJumpAndSwipe()")
        self.assertTrue(jump["failure"].startswith("ios/App/Tests/UI/SGGSUITests.swift:812"))

    def test_bundle_refusals(self):
        def refused(setup):
            with TemporaryDirectory() as t:
                staging = Path(t) / "s"
                self.staging = staging
                self.begin()
                rd = self.run_dir()
                make_bundle(rd, "unit")
                setup(rd)
                with self.assertRaises(dr.Refusal) as e:
                    self.summarize(rd, no_tar=True)
                self.host.mutate.clear()
                return str(e.exception)

        self.assertIn("not a finished result bundle", refused(lambda rd: make_bundle(rd, "ui", finished=False)))
        self.assertIn("are named", refused(lambda rd: make_bundle(rd, "random")))
        self.assertIn("duplicates", refused(lambda rd: make_bundle(rd, "ui", root_id="0~unit-root")))

        def outside(rd):
            elsewhere = make_bundle(self.tmp / "elsewhere", "ui")
            (rd / "bundles" / "ui.xcresult").symlink_to(elsewhere)
        self.assertIn("outside the run folder", refused(outside))

        def early(rd):
            make_bundle(rd, "ui")
            self.host.mutate["ui"] = {"summary": lambda d: {**d, "startTime": T0 - 3600}}
        self.assertIn("before `begin`", refused(early))

        def simulator(rd):
            make_bundle(rd, "ui")
            self.host.mutate["ui"] = {"tests": lambda d: {**d, "devices": [{**d["devices"][0],
                                                                               "platform": "iOS Simulator"}]}}
        self.assertIn("physical iOS device", refused(simulator))

        def reused(rd):
            make_bundle(rd, "ui", root_id="0~seen-before")
            old = self.runs / "1.4.9" / "20261025T1200Z-1234567"
            old.mkdir(parents=True)
            (old / "summary.json").write_text(json.dumps({"run_id": old.name, "bundles": [{"root_id": "0~seen-before"}]}))
        self.assertIn("reused result folder", refused(reused))


# ---------------------------------------------------------------- record-manual

class RecordManualTests(Base):
    def test_rules(self):
        self.begin()
        rd = self.run_dir()
        rec = lambda row, result, note="": dr.cmd_record_manual(ns(run_dir=str(rd), row=row, result=result,
                                                                    note=note, tester="owner"))
        with self.assertRaises(dr.Refusal):
            rec("D2", "pass")                         # automated rows are not typed in
        with self.assertRaises(dr.Refusal):
            rec("D4", "deferred")                     # deferral needs a reason
        with self.assertRaises(dr.Refusal):
            rec("restore", "deferred", "later")       # real data stays sealed: never deferred
        self.assertEqual(rec("D4", "deferred", "after the store update"), 0)
        self.assertEqual(json.loads((rd / "manual.json").read_text())["D4"]["result"], "deferred")
        with self.assertRaises(dr.Refusal):
            dr.cmd_record_manual(ns(run_dir=str(self.tmp), row="D4", result="pass", note="", tester="owner"))


# ---------------------------------------------------------------- the verdict

class VerdictTests(unittest.TestCase):
    def base(self):
        return {"origin": "device", "source": {"tree": TREE, "stamp_tree": TREE, "dirty": False},
                "bundles": [{"kind": k} for k in dr.REQUIRED_KINDS], "not_run": [],
                "tests": [{"id": "A/t()", "outcome": "Passed", "duration": 1}],
                "checklist": {r: ({"mode": "manual", "result": "pass", "title": r} if t is None
                                  else {"mode": "auto", "result": "pass", "title": r})
                              for r, (_, t) in dr.CHECKLIST.items()},
                "launch": {"cold": {"nitnemDrawn": 1.2}, "warm": {"nitnemDrawn": 0.8}},
                "env": {"restore_launch": {"result": "pass"}}}

    def test_pass_and_each_way_out(self):
        self.assertEqual(dr.compute_verdict(self.base()), ("PASS", []))
        s = self.base(); s["bundles"] = s["bundles"][:1]
        self.assertEqual(dr.compute_verdict(s)[0], "INCOMPLETE")
        s = self.base(); s["source"]["stamp_tree"] = "c" * 40
        self.assertEqual(dr.compute_verdict(s)[0], "FAIL")
        s = self.base(); s["launch"]["warm"]["nitnemDrawn"] = 5.0
        self.assertEqual(dr.compute_verdict(s)[0], "FAIL")
        s = self.base(); s["checklist"]["D2"]["result"] = "missing"
        self.assertEqual(dr.compute_verdict(s)[0], "INCOMPLETE")
        s = self.base(); s["checklist"]["D7"].update(result="deferred", note="")
        self.assertEqual(dr.compute_verdict(s)[0], "INCOMPLETE")
        s = self.base(); s["env"]["restore_launch"] = None
        self.assertEqual(dr.compute_verdict(s)[0], "INCOMPLETE")
        s = self.base(); s["tests"].append({"id": "B/t()", "outcome": "Failed", "failure": "x", "cause": "unknown"})
        self.assertEqual(dr.compute_verdict(s)[0], "INCOMPLETE")

    def test_a_backfill_never_passes(self):
        s = self.base(); s.update(origin="backfill", evidence_lost=True)
        self.assertEqual(dr.compute_verdict(s)[0], "RECORDED-NO-BUNDLES")


# ---------------------------------------------------------------- check, rebuild, verify-assets

class CheckAndRebuildTests(Base):
    def passed_run(self):
        rd = self.full_run()
        self.summarize(rd)
        return self.runs / self.version / rd.name

    def test_check_catches_edits_and_leaks(self):
        out = self.passed_run()
        self.assertEqual(dr.check_run(out), [])
        s = json.loads((out / "summary.json").read_text())
        s["verdict"], s["verdict_reasons"] = "PASS", []
        s["tests"][0].update(outcome="Failed", failure="x", cause="unknown")
        (out / "summary.json").write_text(json.dumps(s))
        self.assertTrue(any("recomputes" in p for p in dr.check_run(out)))
        self.summarize(self.run_dir())
        (out / "extra.png").write_bytes(b"\x89PNG")
        problems = dr.check_run(out) + dr.scan_tree(self.runs)
        self.assertTrue(any("summary.json and summary.md only" in p for p in problems))
        self.assertTrue(any("not UTF-8" in p for p in problems))
        (out / "extra.png").unlink()
        (out / "summary.md").write_text((out / "summary.md").read_text() + f"\n{UDID}\n")
        self.assertTrue(any("UDID" in p for p in dr.scan_tree(self.runs)))
        self.assertEqual(dr.cmd_check(ns(run_dirs=[]), runs_dir=self.runs), 1)

    def test_check_size_cap_and_identity(self):
        out = self.passed_run()
        s = json.loads((out / "summary.json").read_text())
        s["source"]["commit"] = HEAD[:7]
        s["notes"] = ["x" * dr.RUN_CAP_BYTES]
        (out / "summary.json").write_text(json.dumps(s))
        problems = dr.check_run(out)
        self.assertTrue(any("bytes >" in p for p in problems))
        self.assertTrue(any("source.commit" in p for p in problems))

    def backfill(self, version, run_id, tests):
        d = self.runs / version / run_id
        d.mkdir(parents=True)
        s = {"schema": 1, "tool_version": "1", "origin": "backfill", "evidence_lost": True, "version": version,
             "run_id": run_id, "app": {"version": version}, "source": {"commit": "e" * 40, "tree": run_id[-7:] + "f" * 33},
             "device": {"name": "S-iPhone", "ios": "27.0.1"}, "started_at": "2026-10-25T12:00:00Z",
             "bundles": [], "tests": tests, "checklist": {}, "launch": {}}
        s["verdict"], s["verdict_reasons"] = dr.compute_verdict(s)
        (d / "summary.json").write_text(json.dumps(s, indent=2))
        (d / "summary.md").write_text(dr.render_md(s))

    def test_rebuild_and_check(self):
        self.passed_run()
        flake = {"id": "SGGSUITests/testReaderJumpAndSwipe()", "outcome": "Passed", "duration": 0,
                 "failure": "angField missing", "cause": "unknown", "reruns": [{"bundle": "rerun", "outcome": "Passed"}]}
        self.backfill("1.4.9", "20261025T1200Z-abcdef0", [flake])
        self.backfill("1.4.9", "20261026T0130Z-abcdef1", [flake])
        self.assertEqual(dr.cmd_rebuild(ns(check=False), runs_dir=self.runs), 0)
        self.assertNotIn("chronic: fix it", (self.runs / "HISTORY.md").read_text())
        self.backfill("1.4.9", "20261026T0230Z-abcdef2", [flake])
        self.assertEqual(dr.cmd_check(ns(run_dirs=[]), runs_dir=self.runs), 0)
        self.assertEqual(dr.cmd_rebuild(ns(check=True), runs_dir=self.runs), 1)
        self.assertEqual(dr.cmd_rebuild(ns(check=False), runs_dir=self.runs), 0)
        self.assertEqual(dr.cmd_rebuild(ns(check=True), runs_dir=self.runs), 0)
        index = json.loads((self.runs / "index.json").read_text())
        self.assertEqual([r["verdict"] for r in index["runs"]], ["RECORDED-NO-BUNDLES"] * 3 + ["PASS"])
        flakes = json.loads((self.runs / "flakes.json").read_text())["tests"]
        jump = flakes["SGGSUITests/testReaderJumpAndSwipe()"]
        self.assertEqual((jump["fails"], jump["fail_then_pass"], jump["flake_events"], jump["chronic"]), (4, 4, 3, True))
        themes = flakes["SGGSUITests/testThemesIndexSearch()"]       # a landscape failure: the bench, not a flake
        self.assertEqual((themes["env_fails"], themes["flake_events"], themes["chronic"]), (1, 0, False))
        self.assertEqual(jump["sources"], ["backfill", "device"])
        trends = json.loads((self.runs / "trends.json").read_text())["runs"]
        self.assertEqual(trends[-1]["d10"], {"cold": 1.31, "warm": 0.88})
        self.assertLessEqual(len(trends[-1]["slowest"]), 20)
        history = (self.runs / "HISTORY.md").read_text()
        self.assertIn("chronic: fix it", history)
        self.assertIn("| 1.4.9 | [20261025T1200Z-abcdef0](1.4.9/20261025T1200Z-abcdef0/summary.md) | RECORDED-NO-BUNDLES | `abcdef0` | S-iPhone · iOS 27.0.1 | — | — |", history)
        self.assertEqual(dr.cmd_check(ns(run_dirs=[]), runs_dir=self.runs), 0)
        (self.runs / "HISTORY.md").write_text(history + "edited\n")
        self.assertEqual(dr.cmd_rebuild(ns(check=True), runs_dir=self.runs), 1)


class VerifyAssetsTests(Base):
    def setUp(self):
        super().setUp()
        rd = self.full_run()
        self.summarize(rd)
        self.rd = rd
        self.path = str(self.runs / self.version / rd.name / "summary.json")
        self.s = json.loads(Path(self.path).read_text())

    def release(self, drop=None, resize=None):
        assets = [{"name": b["asset"], "size": b["size"] + (1 if b["asset"] == resize else 0),
                   "url": f"api://{b['asset']}"} for b in self.s["bundles"] if b["asset"] != drop]
        return {"assets": assets + [{"name": "SHA256SUMS", "size": 10, "url": "api://SHA256SUMS"}]}

    def host_with(self, release, corrupt=None, error=None):
        host = self.host
        rd = self.rd

        def http(url, token, accept=None, dest=None):
            if error:
                raise error
            if dest is None:
                return release
            name = url.split("//", 1)[1]
            data = (rd / "upload" / name).read_bytes()
            Path(dest).write_bytes(data + (b"x" if name == corrupt else b""))
            return dest
        host.http = http
        return host

    def verify(self, host, **kw):
        args = ns(summaries=[self.path], sizes=kw.get("sizes", False), skip_if_unavailable=kw.get("skip", False))
        with mock.patch.dict(os.environ, {"SGGS_READ_TOKEN": "t"}):
            return dr.cmd_verify_assets(args, host=host)

    def test_verify(self):
        self.assertEqual(self.verify(self.host_with(self.release())), 0)
        self.assertEqual(self.verify(self.host_with(self.release()), sizes=True), 0)
        self.assertEqual(self.verify(self.host_with(self.release(drop="ui.tar.gz")), sizes=True), 1)
        self.assertEqual(self.verify(self.host_with(self.release(resize="unit.tar.gz")), sizes=True), 1)
        self.assertEqual(self.verify(self.host_with(self.release(), corrupt="checklist.tar.gz")), 1)

    def test_an_unreadable_evidence_repo_is_a_notice_only_when_asked(self):
        err = dr.urllib.error.HTTPError("u", 404, "Not Found", {}, None)
        self.assertEqual(self.verify(self.host_with(None, error=err), sizes=True, skip=True), 0)
        self.assertEqual(self.verify(self.host_with(None, error=err), sizes=True), 1)


if __name__ == "__main__":
    unittest.main()
