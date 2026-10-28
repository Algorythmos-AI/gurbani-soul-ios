#!/usr/bin/env python3
"""device_run.py — physical-device test runs as permanent, checkable evidence.

A device run is proof that one source TREE passed every planned test and the device checklist on a
real iPhone. The proof is two text files per run in this repository
(ios/device-runs/<version>/<run-id>/summary.json + summary.md); the raw .xcresult bundles go, as
tar.gz assets, to a release of the private repository EVIDENCE_REPO (they carry UDIDs, host paths and
screen recordings that cannot be scrubbed). docs/ios/device-evidence.md is the runbook.

Commands
  begin --version V --expect SHA --stamp STAMP --attest a,b,…   [--staging DIR] [--device-name N]
      Start a run: HEAD must be SHA (full), its tree must equal the build stamp's, the worktree must
      be clean, the owner's attestations complete and the phone unlocked. Records the planned tests
      (parsed from ios/App/Tests, or --planned FILE) and makes a fresh run folder
      <staging>/<V>/<run-id>/ with bundles/ inside; refuses one that exists. Prints the folder.
  summarize RUN_DIR [--cause TEST=CAUSE …] [--out DIR] [--no-tar]
      Read every bundles/*.xcresult (xcresulttool), merge reruns, classify failures, judge the
      checklist rows, tar + sha256 each bundle into upload/, and write summary.json + summary.md
      (to RUN_DIR and to ios/device-runs/<V>/<run-id>/). Refuses a bundle outside RUN_DIR, an
      unfinished one, one that started before `begin`, or one already recorded by another run.
  record-manual RUN_DIR ROW pass|fail|deferred --note TEXT [--tester owner]
      A manual checklist row (D1 D4 D5 D7 D8 D9) or `restore` (the ordinary launch that hands the
      phone's real data back). `deferred` needs a note and is printed loudly. Re-run summarize after.
  rebuild [--check]
      Recompute index.json, flakes.json, trends.json and HISTORY.md from every summary.json.
      --check exits 1 when the committed files differ (CI).
  verify-assets SUMMARY… [--sizes] [--skip-if-unavailable]
      Re-download every bundle asset and compare its sha256 (default), or compare names and sizes
      through the API (--sizes, CI). Token: SGGS_EVIDENCE_TOKEN (CI: read-only, the evidence repository
      only), else GH_TOKEN / GITHUB_TOKEN (a local gh login).
  check [RUN_DIR…]
      Every run under ios/device-runs (or the given ones): schema, verdict recomputed, the scrub scan,
      text only, ≤ 256 KB per run.

Verdicts: PASS · INCOMPLETE · FAIL · RECORDED / RECORDED-NO-BUNDLES (a record written from notes, with
or without published bundles: a backfill, a pre-tag triage run, a PR's check; never passes a gate). The verdict is always recomputed from the facts, never typed.

Exit codes: 0 ok · 1 refusal / gate / drift · 2 usage or I/O error. Stdlib only.
"""
import argparse
import gzip
import hashlib
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = 1
TOOL_VERSION = "1"
ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "ios" / "device-runs"
EVIDENCE_REPO = "Algorythmos-AI/gurbani-soul-device-evidence"
PUBLIC_REPO = "Algorythmos-AI/gurbani-soul-ios"
DEFAULT_STAGING = Path.home() / "SGGS-device-evidence"
RUN_CAP_BYTES = 256 * 1024
MIN_FREE_GB = 8
LAUNCH_BUDGET_S = 5.0
# D10's rule (docs/ios/device-evidence.md, "D10"). The judge is the bench's launches outside XCTest
# (device_bench.sh d10 → <run>/d10/{cold,warm}.json, d10_method "out-of-xctest"); a build without
# that hook leaves no d10/, and then the app's own timeline from the latest PASSING XCTest D10 attempt
# judges (d10_method "in-xctest"). A failure of only XCTest's 5 s budget while that launch reached the
# first app code after PRE_MAIN_LIMIT_S is XCTest's bootstrap over the connection: env:tunnel, which
# like every env failure needs a passing rerun on the same tree and build stamp. Otherwise it is code.
PRE_MAIN_LIMIT_S = 2.0
D10_BUDGET_RE = re.compile(r"\b(cold|warm) launch must (?:finish verifying in under|be under) 5 s")
RUN_ID_RE = re.compile(r"^\d{8}T\d{4}Z-[0-9a-f]{7}$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
BUNDLE_RE = re.compile(r"^(unit|ui|checklist|rerun|shots)(-[a-z0-9-]+)?\.xcresult$")
REQUIRED_KINDS = ("unit", "ui", "checklist")
VERDICTS = ("PASS", "INCOMPLETE", "FAIL", "RECORDED", "RECORDED-NO-BUNDLES")
# Records written from notes rather than by `summarize`: never a gate. RECORDED when its bundles are
# published (verify-assets checks them like any run's), RECORDED-NO-BUNDLES when there are none.
#   backfill          the result bundles were lost (evidence_lost: true);
#   device-pretag     a release candidate's triage run before its tag;
#   pr-verification   a pull request's check on the device (not a release run).
NOTE_ORIGINS = {"backfill": "backfilled from documents; the result bundles were lost",
                "device-pretag": "a release candidate's pre-tag triage run, recorded from notes; never a release gate",
                "pr-verification": "a pull request's device verification, recorded from notes; never a release gate"}
ASSET_TAG_RE = re.compile(r"^ios-[0-9A-Za-z.]+-\d{8}T\d{4}Z-[0-9a-f]{7}$")

# The owner's word on the bench, given before every run (docs/ios/device-evidence.md, "Pre-run").
ATTESTATIONS = ("unlocked", "auto-lock-never", "portrait-lock", "dnd", "no-other-apps", "hands-off",
                "cert-trusted")

# Checklist rows (docs/ios/testflight-test-plan.md §8). Automated rows name their DeviceChecklistTests
# test; every automated row must attach evidence named for the row ("D2 …").
CHECKLIST = {
    "D1": ("Charter S", None),
    "D2": ("Copy fidelity", "DeviceChecklistTests/testD2CopyIsVerbatimWithSaroopOnAndOff()"),
    "D3": ("Gurmukhi rendering", "DeviceChecklistTests/testD3RenderingLightAndDarkAtAX3()"),
    "D4": ("Update from the store build", None),
    "D5": ("Forget location (widget half)", None),
    "D6": ("Clear reading history",
           "DeviceChecklistTests/testD6ClearHistoryCancelThenConfirmKeepsEverythingElse()"),
    "D7": ("Spotlight", None),
    "D8": ("Widgets", None),
    "D9": ("Airplane Mode", None),
    "D10": ("Launch time (this device)", "DeviceChecklistTests/testD10ColdAndWarmLaunchTimes()"),
    "D11": ("Force quit and relaunch", "DeviceChecklistTests/testD11ResumeAndAnInterruptedVerify()"),
    "D12": ("Hostile links", "DeviceChecklistTests/testD12HostileLinksNeverCrash()"),
}
D5_APP_HALF = "SGGSUITests/testForgetLocationReturnsToTheLocationCard()"
D10_TEST = CHECKLIST["D10"][1]
MANUAL_ROWS = tuple(r for r, (_, t) in CHECKLIST.items() if t is None)
# Screens that may go public (eyeballed first): UI-test data only.
PUBLIC_ROWS = ("D2", "D3", "D11")

# A test that only ever SKIPPED is allowed when its skip message starts with one of these.
SKIP_ALLOWLIST = {
    "capture-only: set TEST_RUNNER_SGGS_SHOT_DIR": "screen captures run as their own `shots` bundles",
    "report-only: set TEST_RUNNER_SGGS_SHOT_DIR": "the accessibility audit is report-only",
    "the bundled roster has no `place` yet": "roster v2 is not vendored",
}

# Failure text → cause. First match wins; anything else is `unknown` until an operator says `code`.
CAUSES = (
    ("env:locked", r"Timed out while enabling automation mode|CoreDeviceError\D{0,20}10003|error 10003|"
                   r"device (?:is|was) locked|could not be,? unlocked|FBSOpenApplicationErrorDomain(?: error)? 7"
                   r"|BENCH: .*locked"),
    ("env:cert", r"not trusted|Untrusted Developer|explicitly trusted"),
    ("env:tunnel", r"lost (?:the )?connection|connection (?:was )?(?:interrupted|invalidated)|tunnel"
                   r"|Test runner exited before starting test execution|device is not connected"
                   r"|Failed to terminate|Failed to launch .{0,120}via Xcode"),
    ("env:landscape", r"\blandscape\b|BENCH: .*orientation"),
    ("env:foreground", r"BENCH: .*foreground|not in the foreground|is not running in the foreground"),
)
CAUSE_VALUES = ("code", "env:locked", "env:landscape", "env:foreground", "env:tunnel", "env:cert",
                "unknown")
BENCH_PROBE = "BenchGuardTests/"

# Never in a tracked evidence file.
SCRUB = (
    ("a device UDID", re.compile(r"0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}")),
    ("a host path", re.compile(r"/Users/")),
    ("an App Store Connect key name", re.compile(r"AuthKey_")),
    ("a .p8 key file", re.compile(r"\.p8\b")),
    ("a private_keys path", re.compile(r"private_keys")),
    ("an email address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")),
)


class Refusal(Exception):
    """A gate said no: print it and exit 1."""


# ---------------------------------------------------------------- small helpers

def utcnow():
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def from_epoch(t):
    return datetime.fromtimestamp(t, tz=timezone.utc).replace(microsecond=0)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
                          encoding="utf-8")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def scrub_text(text):
    """Failure text as it may be published: repo-relative paths, no UDIDs, no addresses."""
    text = re.sub(r"(?:/Users|/private/var|/var/folders|/private/tmp|/tmp)/\S*?/(ios/App/\S+)", r"\1", text)
    text = re.sub(r"(?:/Users|/private/var|/var/folders)/\S+", "<host-path>", text)
    text = re.sub(r"0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}", "<udid>", text)
    text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}", "<email>", text)
    text = re.sub(r"AuthKey_\w+|\S+\.p8\b|\S*private_keys\S*", "<key>", text)
    return text.strip()[:600]


def scrub_findings(text):
    return [label for label, rx in SCRUB if rx.search(text)]


def wiped_roots():
    return ("/tmp", "/private/tmp", "/var/folders", "/private/var/folders",
            os.path.realpath(tempfile.gettempdir()))


def refuse_temp(path):
    """The staging folder must survive: /tmp and the scratchpads under it have been wiped twice."""
    p = os.path.realpath(path)
    for bad in wiped_roots():
        bad = os.path.realpath(bad)
        if p == bad or p.startswith(bad.rstrip("/") + "/"):
            raise Refusal(f"{path} is under {bad}, which gets wiped — stage under {DEFAULT_STAGING}")


def classify(text, failure_shots=()):
    """The cause of one failure. `failure_shots` are (width, height) of screenshots attached to it."""
    for cause, rx in CAUSES:
        if re.search(rx, text or "", re.IGNORECASE):
            return cause
    if any(w > h for w, h in failure_shots):
        return "env:landscape"
    return "unknown"


def png_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    return None


def attachment_name(suggested):
    """xcresulttool's suggested name is "<name>_<n>_<UUID>.<ext>"; the test's own name is <name>."""
    return re.sub(r"_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(\.\w+)?$",
                  "", suggested)


def planned_from_sources(root=ROOT):
    """Every `func testX()` of an XCTestCase class (or its extensions) under ios/App/Tests."""
    ids = set()
    for f in sorted((root / "ios" / "App" / "Tests").rglob("*.swift")):
        owner = None
        for line in f.read_text(encoding="utf-8").splitlines():
            m = re.match(r"(?:(?:final|public|private|internal|open|@MainActor)\s+)*(class|extension)\s+(\w+)", line)
            if m:
                owner = m.group(2)
            m = re.match(r"\s+(?:(?:@MainActor|override|nonisolated|@objc)\s+)*func\s+(test\w*)\(\)", line)
            if m and owner:
                ids.add(f"{owner}/{m.group(1)}()")
    return sorted(ids)


# ---------------------------------------------------------------- the host (git, xcrun, devicectl)

class Host:
    """Everything that touches the machine; tests replace it."""

    def run(self, *cmd, cwd=None):
        out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        if out.returncode != 0:
            raise Refusal(f"{' '.join(cmd[:4])} failed: {out.stderr.strip()[:300]}")
        return out.stdout

    def git(self, *args, cwd=ROOT):
        return self.run("git", *args, cwd=cwd).strip()

    def xcode(self):
        try:
            return self.run("xcodebuild", "-version").splitlines()[0].replace("Xcode ", "")
        except (Refusal, FileNotFoundError, IndexError):
            return None

    def free_gb(self, path):
        return shutil.disk_usage(path).free / 1e9

    def devicectl(self, *args):
        """devicectl's JSON result for the phone named by SGGS_DEVICE_UDID (never recorded)."""
        udid = os.environ.get("SGGS_DEVICE_UDID")
        if not udid:
            raise Refusal("SGGS_DEVICE_UDID is not set — source ~/.config/sggs/device-bench.env")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out.json"
            self.run("xcrun", "devicectl", *args, "--device", udid, "--json-output", str(out))
            return json.loads(out.read_text()).get("result", {})

    def device(self):
        details = self.devicectl("device", "info", "details")
        props = details.get("deviceProperties", {})
        hw = details.get("hardwareProperties", {})
        conn = details.get("connectionProperties", {})
        try:
            lock = self.devicectl("device", "info", "lockState")
            locked = lock.get("passcodeRequired")
        except Refusal:
            locked = None
        return {"name": props.get("name"), "model": hw.get("marketingName"),
                "ios": props.get("osVersionNumber"), "transport": conn.get("transportType"),
                "tunnel": conn.get("tunnelState"), "locked": locked}

    # xcresulttool
    def xcresult(self, *args):
        return self.run("xcrun", "xcresulttool", *args)

    def bundle(self, path, attachments_out):
        """(info, summary, tests, attachment manifest) of one result bundle."""
        info_plist = Path(path) / "Info.plist"
        if not info_plist.is_file():
            raise Refusal(f"{path} is not a finished result bundle (no Info.plist)")
        info = plistlib.loads(info_plist.read_bytes())
        summary = json.loads(self.xcresult("get", "test-results", "summary", "--path", str(path), "--compact"))
        tests = json.loads(self.xcresult("get", "test-results", "tests", "--path", str(path), "--compact"))
        shutil.rmtree(attachments_out, ignore_errors=True)
        Path(attachments_out).mkdir(parents=True)
        self.xcresult("export", "attachments", "--path", str(path), "--output-path", str(attachments_out))
        manifest_path = Path(attachments_out) / "manifest.json"
        manifest = read_json(manifest_path) if manifest_path.exists() else []
        return info, summary, tests, manifest

    def http(self, url, token, accept="application/vnd.github+json", dest=None):
        req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "sggs-device-run",
                                                   **({"Authorization": f"Bearer {token}"} if token else {})})
        with urllib.request.build_opener(_DropAuthOnRedirect).open(req, timeout=120) as r:
            if dest is None:
                return json.loads(r.read().decode())
            with open(dest, "wb") as f:
                shutil.copyfileobj(r, f)
        return dest


class _DropAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """A release asset redirects to signed storage, which rejects a second credential."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.request.urlparse(newurl).netloc != urllib.request.urlparse(req.full_url).netloc:
            new.remove_header("Authorization")
        return new


HOST = Host()


# ---------------------------------------------------------------- begin

def make_run_id(started, tree):
    return f"{started.strftime('%Y%m%dT%H%MZ')}-{tree[:7]}"


def read_pins(root=ROOT):
    pins = {}
    try:
        lock = read_json(root / "dataset.lock.json")
        pins["dataset"] = {"version": lock.get("dataset_version"), "commit": lock.get("commit")}
    except FileNotFoundError:
        pass
    try:
        platform = read_json(root / "vendor.lock.json")["sources"]["platform"]
        pins["platform"] = {"version": platform.get("version"), "commit": platform.get("commit")}
    except (FileNotFoundError, KeyError):
        pass
    try:
        pins["db_sha256"] = read_json(root / "ios" / "Resources" / "sggs-ios.manifest.json").get("db_sha256")
    except FileNotFoundError:
        pass
    return pins


def marketing_version(root=ROOT):
    text = (root / "ios" / "App" / "project.yml").read_text(encoding="utf-8")
    return re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text).group(1)


def cmd_begin(args, host=HOST, root=ROOT, now=None):
    if not SHA_RE.match(args.expect or ""):
        raise Refusal(f"--expect must be a full 40-character commit SHA, got {args.expect!r}")
    head = host.git("rev-parse", "HEAD", cwd=root)
    if head != args.expect:
        raise Refusal(f"HEAD is {head}, not the expected {args.expect} — the wrong commit would be tested")
    tree = host.git("rev-parse", "HEAD^{tree}", cwd=root)
    # Untracked files count: one under an XcodeGen source folder is built, yet HEAD's tree is recorded.
    if host.git("status", "--porcelain", cwd=root):
        raise Refusal("the worktree has uncommitted changes or untracked files — evidence is for a committed "
                      "tree only")
    stamp = read_json(args.stamp)
    if stamp.get("tree") != tree or stamp.get("head") != head:
        raise Refusal(f"the build stamp is for {stamp.get('head')} (tree {stamp.get('tree')}), but HEAD is "
                      f"{head} (tree {tree}) — rebuild with ios/tools/device_bench.sh build")
    if stamp.get("dirty"):
        raise Refusal("the build stamp says the build was made from a dirty worktree")
    version = marketing_version(root)
    if args.version != version:
        raise Refusal(f"--version {args.version} but project.yml says MARKETING_VERSION {version}")
    given = {a.strip() for a in (args.attest or "").split(",") if a.strip()}
    unknown = given - set(ATTESTATIONS)
    missing = [a for a in ATTESTATIONS if a not in given]
    if unknown:
        raise Refusal(f"unknown attestation(s): {', '.join(sorted(unknown))}")
    if missing:
        raise Refusal("the owner has not attested: " + ", ".join(missing) + " (docs/ios/device-evidence.md)")
    staging = Path(os.path.expanduser(args.staging))
    refuse_temp(staging)
    staging.mkdir(parents=True, exist_ok=True)
    free = host.free_gb(staging)
    if free < MIN_FREE_GB:
        raise Refusal(f"{free:.1f} GB free; a device run needs {MIN_FREE_GB} GB (bundles + tarballs)")
    device = host.device()
    if device.get("locked") is True:
        raise Refusal("the phone is locked (passcode required) — unlock it and set Auto-Lock to Never")
    if args.device_name and device.get("name") != args.device_name:
        raise Refusal(f"the connected phone is {device.get('name')!r}, not {args.device_name!r}")
    planned = (Path(args.planned).read_text().split() if args.planned else planned_from_sources(root))
    started = now or utcnow()
    run_id = make_run_id(started, tree)
    run_dir = staging / version / run_id
    if run_dir.exists():
        raise Refusal(f"{run_dir} exists — every run gets a fresh folder")
    (run_dir / "bundles").mkdir(parents=True)
    run = {
        "schema": SCHEMA, "version": version, "run_id": run_id, "started_at": iso(started),
        "source": {"commit": head, "tree": tree,
                   "branch": host.git("rev-parse", "--abbrev-ref", "HEAD", cwd=root),
                   "dirty": False, "stamp_tree": stamp["tree"], "stamp_built_at": stamp.get("built_at")},
        "app": {"version": version, "build": stamp.get("build", "1"),
                "build_config": stamp.get("configuration", "Debug")},
        "pins": read_pins(root),
        "device": {"name": device.get("name"), "model": device.get("model"), "ios": device.get("ios")},
        "connection": {"transport": device.get("transport"), "tunnel": device.get("tunnel")},
        "env": {"attested": sorted(given), "locked_at_begin": device.get("locked"),
                "free_disk_gb": round(free, 1)},
        "planned_tests": planned,
        "xcode": host.xcode(),
        "operator": {"role": args.operator},
    }
    write_json(run_dir / "run.json", run)
    print(run_dir)
    return 0


# ---------------------------------------------------------------- summarize

SYSTEM_SUITE = "System Failures"


def walk_cases(nodes, system=False):
    """Test cases; with system=True, the runner's own failures instead ("System Failures": a test
    runner that crashed or lost its connection). Those are not tests and no rerun can pass them."""
    for n in nodes:
        if n.get("nodeType") == "Test Case":
            if system == is_system_case(n):
                yield n
        elif not (n.get("nodeType") == "Test Suite" and n.get("name") == SYSTEM_SUITE and not system):
            yield from walk_cases(n.get("children", []), system)


def is_system_case(node):
    return not re.match(r"^\w+/\w+\(.*\)$", node.get("nodeIdentifier") or "")


def skip_reason(message):
    """XCTest prefixes the test's own XCTSkip message with "Test skipped - "."""
    return re.sub(r"^Test skipped\s*-\s*", "", message or "")


def messages(node, kind):
    return [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == kind]


def case_attempts(node):
    """One test case → its attempts in order: xcodebuild's own retries are Repetition children."""
    reps = [c for c in node.get("children", []) if c.get("nodeType") == "Repetition"]
    if not reps:
        reps = [node]
    out = []
    for r in reps:
        fails = messages(r, "Failure Message")
        skips = [skip_reason(m) for m in messages(r, "Skip Message") or messages(node, "Skip Message")]
        out.append({"outcome": r.get("result", "unknown"),
                    "repetition": int(r.get("nodeIdentifier") or 1) if r is not node else 1,
                    "duration": round(float(r.get("durationInSeconds") or 0), 3),
                    "failure": fails[0] if fails else None,
                    "skip": skips[0] if skips else None})
    return out


def read_attachments(manifest, att_dir):
    """test id → [{name, sha256, size, image, failure, repetition}] from an export manifest."""
    by_test = {}
    for entry in manifest:
        rows = []
        for a in entry.get("attachments", []):
            f = Path(att_dir) / a["exportedFileName"]
            data = f.read_bytes() if f.exists() else b""
            rows.append({"name": attachment_name(a.get("suggestedHumanReadableName", "")),
                         "file": str(f), "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                         "image": png_size(data), "failure": bool(a.get("isAssociatedWithFailure")),
                         "repetition": a.get("repetitionNumber", 1)})
        by_test[entry["testIdentifier"]] = rows
    return by_test


def deterministic_tar(src_dir, dest, root=None):
    """A reproducible tar.gz of one bundle, byte for byte the format of every published evidence
    asset: file entries only, under `<root>/` (default `<bundle name>.xcresult/`), in os.walk order
    (each folder's files sorted, then its sorted subfolders), mtime 0, uid/gid 0, PAX headers, gzip
    level 9 with mtime 0. xcresulttool's own cache (database.sqlite3*) is left out: it is rebuilt on
    every read. The same input gives the same sha256, so a re-summarize or a re-pack never drifts."""
    src_dir = Path(src_dir)
    root = root or f"{src_dir.stem}.xcresult"
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "wb") as out, \
            gzip.GzipFile(filename="", mode="wb", fileobj=out, mtime=0, compresslevel=9) as gz, \
            tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for here, dirs, files in os.walk(src_dir):
            dirs.sort()
            for f in sorted(files):
                if f.startswith("database.sqlite3"):
                    continue
                path = os.path.join(here, f)
                ti = tar.gettarinfo(path, arcname=os.path.join(root, os.path.relpath(path, src_dir)))
                ti.mtime = 0
                ti.uid = ti.gid = 0
                ti.uname = ti.gname = ""
                with open(path, "rb") as fh:
                    tar.addfile(ti, fh)
    return sha256_file(dest), Path(dest).stat().st_size


def known_root_ids(runs_dir, except_run):
    seen = {}
    for s in sorted(Path(runs_dir).glob("*/*/summary.json")):
        doc = read_json(s)
        if doc.get("run_id") == except_run:
            continue
        for b in doc.get("bundles", []):
            if b.get("root_id"):
                seen[b["root_id"]] = doc.get("run_id")
    return seen


def asset_tag(version, run_id):
    return f"ios-{version}-{run_id}"


def asset_url(version, run_id, name, tag=None):
    return f"https://github.com/{EVIDENCE_REPO}/releases/download/{tag or asset_tag(version, run_id)}/{name}"


def parse_launch(attachments):
    """D10's in-app timeline: the JSON attachment "D10 launch timeline" when present, else the
    `cold {…}` / `warm {…}` lines of the "D10 timings" note."""
    launch = {}
    for a in attachments:
        if a["name"] == "D10 launch timeline" and Path(a["file"]).exists():
            doc = json.loads(Path(a["file"]).read_text(encoding="utf-8"))
            for k in ("cold", "warm"):
                if isinstance(doc.get(k), dict):
                    launch[k] = doc[k].get("since_process_start", doc[k])
                    if "cached_hash" in doc[k]:
                        launch.setdefault("cached_hash", {})[k] = doc[k]["cached_hash"]
            if isinstance(doc.get("xctest_clock"), dict):
                launch["xctest_clock"] = doc["xctest_clock"]
            return launch
    for a in attachments:
        if a["name"] == "D10 timings" and Path(a["file"]).exists():
            text = Path(a["file"]).read_text(encoding="utf-8")
            for k in ("cold", "warm"):
                m = re.search(rf"^\s*{k} (\{{.*\}})\s*$", text, re.M)
                if m:
                    doc = json.loads(m.group(1))
                    launch[k] = doc.get("since_process_start", {})
                    if "cached_hash" in doc:
                        launch.setdefault("cached_hash", {})[k] = doc["cached_hash"]
            m = re.search(r"cold ([\d.]+) s, warm ([\d.]+) s", text)
            if m:
                launch["xctest_clock"] = {"cold": float(m.group(1)), "warm": float(m.group(2))}
    return launch


def d10_evidence(atts, repetition):
    """D10's attachments from one attempt (xcodebuild's own retries number their attachments)."""
    return [a for a in atts.get(D10_TEST, []) if a["name"].startswith("D10 ") and a["repetition"] == repetition]


def judge_timeline(timeline, where):
    """(judged, problem) for a cold + warm timeline: both under budget, the cold launch re-hashed and
    the warm one used the fingerprint. problem is ("incomplete" | "fail", why) or None."""
    judged = {k: timeline.get(k) or {} for k in ("cold", "warm")}
    judged["cached_hash"] = {k: (timeline.get("cached_hash") or {}).get(k) for k in ("cold", "warm")}
    for k in ("cold", "warm"):
        if "nitnemDrawn" not in judged[k]:
            return judged, ("incomplete", f"the {k} launch {where} never drew Nitnem")
    if judged["cached_hash"] != {"cold": False, "warm": True}:
        return judged, ("incomplete", "the cold launch must re-hash and the warm one use the fingerprint "
                                      f"(cached_hash {judged['cached_hash']}, {where})")
    slow = [k for k in ("cold", "warm") if judged[k]["nitnemDrawn"] >= LAUNCH_BUDGET_S]
    if slow:
        return judged, ("fail", ", ".join(f"{k} {judged[k]['nitnemDrawn']:.2f} s" for k in slow)
                        + f" ≥ {LAUNCH_BUDGET_S:.0f} s {where}")
    return judged, None


def read_d10(run_dir, started):
    """The bench's launches outside XCTest (device_bench.sh d10): None when the run has no d10/ (a
    build without the hook), else (judged, problem) as judge_timeline gives them."""
    folder = Path(run_dir) / "d10"
    if not folder.is_dir():
        return None
    timeline = {"cached_hash": {}}
    for k in ("cold", "warm"):
        f = folder / f"{k}.json"
        if not f.exists():
            return {}, ("incomplete", f"d10/ has no {k}.json — run `device_bench.sh d10` again in a new run")
        doc = read_json(f)
        if doc.get("written_at", 0) < started.timestamp():
            return {}, ("incomplete", f"the {k} launch timeline was written before `begin`")
        timeline[k] = doc.get("since_process_start", {})
        timeline["cached_hash"][k] = doc.get("cached_hash")
    return judge_timeline(timeline, "outside XCTest")


def d10_launch(run_dir, started, bundles, attempts, evid):
    """(launch, problem) for D10: the out-of-XCTest launches when the run has them, else the latest
    PASSING XCTest attempt's own timeline; plus what XCTest saw on its latest attempt (recorded only)."""
    def timeline_of(attempt):
        b = next(x for x in bundles if x["name"] == attempt["bundle"])
        return parse_launch(d10_evidence(b["atts"], attempt.get("repetition", 1)))
    launch = {"budget_s": LAUNCH_BUDGET_S}
    out = read_d10(run_dir, started)
    if out is not None:
        launch["d10_method"] = "out-of-xctest"
        judged, problem = out
    else:
        launch["d10_method"] = "in-xctest"
        ok = next((a for a in reversed(attempts) if a["outcome"] in ("Passed", "Expected Failure")), None)
        judged, problem = (judge_timeline(timeline_of(ok), "in XCTest (the app's own clock)") if ok
                           else ({}, ("incomplete", "no passing D10 attempt to read the launch from")))
    launch.update({k: v for k, v in judged.items() if v})
    xctest = parse_launch(evid)
    for k in ("cold", "warm"):
        marks = xctest.get(k) or {}
        if "appInit" in marks and "nitnemDrawn" in marks:
            xctest.setdefault("pre_main", {})[k] = marks["appInit"]
            xctest.setdefault("app_work", {})[k] = round(marks["nitnemDrawn"] - marks["appInit"], 3)
    if xctest:
        launch["xctest"] = xctest
    return launch, problem


def merge_tests(bundles):
    """Every attempt of every test across bundles (in start order) → one record per test."""
    attempts = {}
    for b in bundles:
        for tid, rows in b["cases"].items():
            for a in rows:
                attempts.setdefault(tid, []).append({**a, "bundle": b["name"]})
    return attempts


def judge_test(tid, rows):
    """(record, problem) for one test. problem is None, ("INCOMPLETE", why) or ("FAIL", why)."""
    ran = [a for a in rows if a["outcome"] != "Skipped"]
    if not ran:
        msg = next((a["skip"] for a in rows if a.get("skip")), "") or ""
        rec = {"id": tid, "outcome": "Skipped", "duration": 0, "skip": scrub_text(msg)}
        allowed = next((why for prefix, why in SKIP_ALLOWLIST.items() if msg.startswith(prefix)), None)
        if allowed:
            rec["skip_allowed"] = allowed
            return rec, None
        return rec, ("INCOMPLETE", f"{tid} only skipped ({msg or 'no reason given'})")
    last = ran[-1]
    rec = {"id": tid, "outcome": last["outcome"], "duration": last["duration"]}
    failed = [a for a in ran if a["outcome"] == "Failed"]
    if failed:
        first = failed[0]
        rec["failure"] = scrub_text(first["failure"] or "")
        rec["cause"] = first["cause"]
        later = ran[ran.index(first) + 1:]
        if later:
            rec["reruns"] = [{"bundle": a.get("bundle"), "outcome": a["outcome"],
                              **({"failure": scrub_text(a["failure"] or ""), "cause": a["cause"]}
                                 if a["outcome"] == "Failed" else {})} for a in later]
    if any(a.get("cause") == "code" for a in failed):
        return rec, ("FAIL", f"{tid} failed (cause: code)")
    for x, y in zip(ran, ran[1:]):
        if x["outcome"] == "Failed" and y["outcome"] == "Failed":
            return rec, ("FAIL", f"{tid} failed twice in a row ({x.get('cause')}, {y.get('cause')})")
    if last["outcome"] == "Failed":
        return rec, ("INCOMPLETE", f"{tid} failed ({last.get('cause')}) and has no passing rerun yet")
    return rec, None


def cmd_summarize(args, host=HOST, runs_dir=None):
    run_dir = Path(args.run_dir).resolve()
    refuse_temp(run_dir)
    run = read_json(run_dir / "run.json")
    runs_dir = Path(runs_dir or RUNS)
    started = parse_iso(run["started_at"])
    overrides = {}
    for item in args.cause or []:
        tid, _, cause = item.partition("=")
        if cause not in CAUSE_VALUES:
            raise Refusal(f"--cause {item}: cause must be one of {', '.join(CAUSE_VALUES)}")
        overrides[tid] = cause
    seen = known_root_ids(runs_dir, run["run_id"])
    bundles = []
    for path in sorted((run_dir / "bundles").iterdir()):
        if not path.name.endswith(".xcresult"):
            continue
        real = Path(os.path.realpath(path))
        if run_dir not in real.parents:
            raise Refusal(f"{path.name} resolves outside the run folder ({real}) — copy, never link")
        if not BUNDLE_RE.match(path.name):
            raise Refusal(f"{path.name}: bundles are named unit|ui|checklist|rerun|shots[-suffix].xcresult")
        info, summary, tests, manifest = host.bundle(real, run_dir / "attachments" / path.stem)
        root_id = (info.get("rootId") or {}).get("hash")
        if root_id in seen:
            raise Refusal(f"{path.name} was already recorded by run {seen[root_id]} — a reused result folder")
        if any(b["root_id"] == root_id for b in bundles):
            raise Refusal(f"{path.name} duplicates another bundle of this run")
        b_start = from_epoch(summary["startTime"])
        if b_start < started:
            raise Refusal(f"{path.name} started {iso(b_start)}, before `begin` ({run['started_at']})")
        devs = tests.get("devices", [])
        if not devs or any(d.get("platform") != "iOS" or "Simulator" in (d.get("modelName") or "")
                           or d.get("deviceName") != run["device"]["name"] for d in devs):
            raise Refusal(f"{path.name} did not run on {run['device']['name']} (a physical iOS device)")
        atts = read_attachments(manifest, run_dir / "attachments" / path.stem)
        cases = {}
        for node in walk_cases(tests.get("testNodes", [])):
            tid = node.get("nodeIdentifier") or node.get("name")
            rows = case_attempts(node)
            shots = [a["image"] for a in atts.get(tid, []) if a["failure"] and a["image"]]
            for a in rows:
                if a["outcome"] == "Failed":
                    a["cause"] = overrides.get(tid) or classify(a["failure"], shots)
            cases[tid] = rows
        # The bench probe runs first: if it failed, the bench was wrong for this whole bundle.
        probe = next((a["cause"] for t, rows in cases.items() if t.startswith(BENCH_PROBE)
                      for a in rows if a["outcome"] == "Failed" and a["cause"].startswith("env:")), None)
        if probe:
            for t, rows in cases.items():
                for a in rows:
                    if a["outcome"] == "Failed" and a["cause"] == "unknown" and t not in overrides:
                        a["cause"] = probe
        # D10: a failure of only the 5 s budget, judged by when the app's first code ran
        if D10_TEST in cases and D10_TEST not in overrides:
            for a in cases[D10_TEST]:
                m = a["outcome"] == "Failed" and D10_BUDGET_RE.search(a["failure"] or "")
                pre = m and (parse_launch(d10_evidence(atts, a["repetition"])).get(m.group(1)) or {}).get("appInit")
                if m and pre is not None:
                    # the first app code came late: XCTest's bootstrap over the connection, not the app
                    a["cause"] = "env:tunnel" if pre > PRE_MAIN_LIMIT_S else "code"
        kind = BUNDLE_RE.match(path.name).group(1)
        system = [{"name": scrub_text(n.get("name", "")),
                   "failure": scrub_text((messages(n, "Failure Message") or [""])[0]),
                   "cause": classify((messages(n, "Failure Message") or [""])[0])}
                  for n in walk_cases(tests.get("testNodes", []), system=True)]
        rec = {"name": path.stem, "kind": kind, "started_at": iso(b_start),
               "finished_at": iso(from_epoch(summary["finishTime"])) if summary.get("finishTime") else None,
               "result": summary.get("result"),
               "counts": {k: summary.get(k, 0) for k in ("totalTestCount", "passedTests", "failedTests",
                                                         "skippedTests", "expectedFailures")},
               "root_id": root_id}
        if system:
            rec["system_failures"] = system
        if not args.no_tar:
            name = f"{path.stem}.xcresult.tar.gz"
            digest, size = deterministic_tar(real, run_dir / "upload" / name, root=f"{path.stem}.xcresult")
            rec.update({"asset": name, "tar_sha256": digest, "size": size,
                        "asset_url": asset_url(run["version"], run["run_id"], name)})
        bundles.append({**rec, "cases": cases, "atts": atts, "_start": b_start})
    bundles.sort(key=lambda b: (b["_start"], b["name"]))
    attempts = merge_tests(bundles)
    tests, problems = [], []
    problem_of = {}
    for tid in sorted(attempts):
        rec, problem = judge_test(tid, attempts[tid])
        tests.append(rec)
        problem_of[tid] = problem
        if problem:
            problems.append(problem)
    by_id = {t["id"]: t for t in tests}
    not_run = sorted(set(run.get("planned_tests", [])) - set(by_id))
    # Duplicates: the same image bytes under two names (the "light and dark identical" mistake).
    warnings = []
    for b in bundles:
        by_hash = {}
        for tid, rows in b["atts"].items():
            for a in rows:
                if a["image"]:
                    by_hash.setdefault(a["sha256"], set()).add(a["name"])
        for digest, names in by_hash.items():
            if len(names) > 1:
                warnings.append(f"{b['name']}: identical image under {len(names)} names: "
                                + ", ".join(sorted(names)))
    manual = read_json(run_dir / "manual.json") if (run_dir / "manual.json").exists() else {}
    launch, d10_problem = {}, None
    checklist, public_files = {}, []
    for row, (title, test) in CHECKLIST.items():
        if test is None:
            m = manual.get(row)
            entry = {"mode": "manual", "title": title, "result": m["result"] if m else "pending"}
            if m:
                entry.update({"tester": m.get("tester"), "note": scrub_text(m.get("note") or "")})
            if row == "D5" and D5_APP_HALF in by_id:
                entry["app_half"] = {"test": D5_APP_HALF, "outcome": by_id[D5_APP_HALF]["outcome"]}
            checklist[row] = entry
            continue
        t = by_id.get(test)
        # The evidence of the latest attempt that ran: a passing row's proof, or a failing row's
        # record (a slow D10 still leaves its timeline).
        last = next((a for a in reversed(attempts.get(test, [])) if a["outcome"] != "Skipped"), None)
        evid = []
        if last:
            b = next(x for x in bundles if x["name"] == last["bundle"])
            evid = [a for a in b["atts"].get(test, []) if a["name"].startswith(row + " ")
                    and a["repetition"] == last.get("repetition", 1)]
        entry = {"mode": "auto", "title": title, "test": test,
                 "attachments": [{"name": a["name"], "sha256": a["sha256"]} for a in evid]}
        img = [a["sha256"] for a in evid if a["image"]]
        test_ok = t is not None and t["outcome"] != "Skipped" and problem_of.get(test) is None
        if row == "D10":
            launch, d10_problem = d10_launch(run_dir, started, bundles, attempts.get(test, []), evid)
        if t is None:
            entry["result"] = "missing"
        elif row == "D10" and test_ok and evid and d10_problem:
            entry["result"], entry["note"] = d10_problem
        elif test_ok and evid and len(img) == len(set(img)):
            entry["result"] = "pass"
        elif any(p[0] == "FAIL" and p[1].startswith(test) for p in problems):
            entry["result"] = "fail"
        else:
            entry["result"] = "incomplete"
            if test_ok and not evid:
                entry["note"] = "passed but attached no evidence"
            elif len(img) != len(set(img)):
                entry["note"] = "two evidence images are byte-identical"
        if row in PUBLIC_ROWS and entry["result"] == "pass":
            public_files += [a for a in evid if a["image"]]
        checklist[row] = entry
    summary = {
        "schema": SCHEMA, "tool_version": TOOL_VERSION, "origin": "device",
        "version": run["version"], "run_id": run["run_id"],
        "app": run["app"], "source": run["source"], "pins": run["pins"], "device": run["device"],
        "connection": run["connection"],
        "env": {**run["env"],
                "restore_launch": ({"result": manual["restore"]["result"],
                                    "recorded_at": manual["restore"].get("recorded_at"),
                                    "note": scrub_text(manual["restore"].get("note") or "")}
                                   if manual.get("restore") else None),
                "incidents": sorted({t["cause"] for t in tests if t.get("cause", "unknown") != "unknown"}
                                    | {r["cause"] for t in tests for r in t.get("reruns", []) if r.get("cause")}
                                    | {f["cause"] for b in bundles for f in b.get("system_failures", [])})},
        "started_at": run["started_at"],
        "ended_at": max((b["finished_at"] or b["started_at"] for b in bundles), default=None),
        "xcode": run.get("xcode"), "operator": run.get("operator"),
        "evidence_repo": EVIDENCE_REPO, "asset_tag": asset_tag(run["version"], run["run_id"]),
        "bundles": [{k: v for k, v in b.items() if k not in ("cases", "atts", "_start")} for b in bundles],
        "planned_count": len(run.get("planned_tests", [])), "not_run": not_run,
        "tests": tests, "checklist": checklist, "launch": launch, "warnings": warnings,
    }
    if public_files and not args.no_tar:
        pub = run_dir / "public" / f"checklist-evidence-{run['run_id']}"
        shutil.rmtree(pub, ignore_errors=True)
        pub.mkdir(parents=True)
        for a in public_files:
            shutil.copyfile(a["file"], pub / (re.sub(r"[^\w .-]", "_", a["name"]) + ".png"))
        digest, size = deterministic_tar(pub, run_dir / "upload-public" / f"{pub.name}.tar.gz", root=pub.name)
        summary["public_evidence"] = {"asset": f"{pub.name}.tar.gz", "sha256": digest, "size": size,
                                      "release": f"{PUBLIC_REPO}@v{run['version']}",
                                      "files": sorted(p.name for p in pub.iterdir())}
    summary["verdict"], summary["verdict_reasons"] = compute_verdict(summary)
    leaks = scrub_findings(json.dumps(summary, ensure_ascii=False))
    if leaks:
        raise Refusal("the summary would publish " + ", ".join(leaks) + " — fix the scrub before writing")
    if not args.no_tar:
        lines = [f"{b['tar_sha256']}  {b['asset']}" for b in summary["bundles"]]
        (run_dir / "upload" / "SHA256SUMS").write_text("\n".join(lines) + "\n")
    out = Path(args.out) if args.out else runs_dir / run["version"] / run["run_id"]
    for d in {run_dir, out}:
        write_json(d / "summary.json", summary)
        (d / "summary.md").write_text(render_md(summary), encoding="utf-8")
    print(f"{summary['verdict']}  {run['version']} {run['run_id']}  → {out}")
    for r in summary["verdict_reasons"][:40]:
        print(f"  - {r}")
    for row, e in checklist.items():
        if e["result"] == "deferred":
            print(f"  !! DEFERRED by {e.get('tester') or 'owner'}: {row} {e['title']} — {e.get('note')}")
    for w in warnings:
        print(f"  warning: {w}")
    return 0


# ---------------------------------------------------------------- the verdict (pure)

def compute_verdict(s):
    """(verdict, reasons) from a summary's facts. FAIL beats INCOMPLETE beats PASS."""
    if s.get("origin") in NOTE_ORIGINS or s.get("evidence_lost"):
        why = NOTE_ORIGINS.get(s.get("origin"), NOTE_ORIGINS["backfill"])
        return ("RECORDED", [why + "; its bundles are published"]) if s.get("bundles") else ("RECORDED-NO-BUNDLES", [why])
    fail, incomplete = [], []
    src = s.get("source", {})
    if src.get("dirty") or src.get("stamp_tree") != src.get("tree"):
        fail.append("the build stamp's tree is not the tested tree, or the worktree was dirty")
    kinds = {b.get("kind") for b in s.get("bundles", [])}
    for k in REQUIRED_KINDS:
        if k not in kinds:
            incomplete.append(f"no `{k}` bundle")
    if s.get("not_run"):
        n = s["not_run"]
        incomplete.append(f"{len(n)} planned test(s) never ran: " + ", ".join(n[:8]) + (" …" if len(n) > 8 else ""))
    for t in s.get("tests", []):
        _, problem = judge_test(t["id"], _attempts_from_record(t))
        if problem:
            (fail if problem[0] == "FAIL" else incomplete).append(problem[1])
    for row, e in s.get("checklist", {}).items():
        r = e.get("result")
        if r == "fail":
            fail.append(f"{row} {e.get('title')} failed")
        elif r == "deferred" and e.get("mode") == "manual":
            if not e.get("note"):
                incomplete.append(f"{row} deferred without a note")
        elif r != "pass":
            incomplete.append(f"{row} {e.get('title')}: {r}" + (f" ({e['note']})" if e.get("note") else ""))
    launch = s.get("launch") or {}
    for k in ("cold", "warm"):
        v = (launch.get(k) or {}).get("nitnemDrawn")
        if v is not None and v >= LAUNCH_BUDGET_S:
            fail.append(f"D10 {k} launch {v:.2f} s ≥ {LAUNCH_BUDGET_S:.0f} s (process start → Nitnem, "
                        f"{launch.get('d10_method', 'in-xctest')})")
    restore = (s.get("env") or {}).get("restore_launch")
    if not restore or restore.get("result") != "pass":
        incomplete.append("the restore launch (the phone's real data back) is not recorded")
    if fail:
        return "FAIL", fail + incomplete
    if incomplete:
        return "INCOMPLETE", incomplete
    return "PASS", []


def _attempts_from_record(t):
    """A test record back to its attempts (from the first failure on), so `check` re-judges exactly
    what summarize judged."""
    if t["outcome"] == "Skipped":
        return [{"outcome": "Skipped", "skip": t.get("skip", ""), "duration": 0}]
    if "failure" not in t:
        return [{"outcome": t["outcome"], "duration": t.get("duration", 0)}]
    return [{"outcome": "Failed", "failure": t["failure"], "cause": t.get("cause"), "duration": 0}] + [
        {"outcome": r["outcome"], "failure": r.get("failure"), "cause": r.get("cause"), "duration": 0}
        for r in t.get("reruns", [])]


# ---------------------------------------------------------------- record-manual

def cmd_record_manual(args, now=None):
    run_dir = Path(args.run_dir)
    if not (run_dir / "run.json").exists():
        raise Refusal(f"{run_dir} has no run.json — start the run with `begin`")
    row = args.row
    if row not in MANUAL_ROWS + ("restore",):
        raise Refusal(f"{row} is not a manual row ({', '.join(MANUAL_ROWS)}, restore)")
    if args.result == "deferred" and not (args.note or "").strip():
        raise Refusal("a deferred row needs --note (why, and when it will be done)")
    if row == "restore" and args.result == "deferred":
        raise Refusal("the restore launch cannot be deferred: the phone's real data is still sealed")
    path = run_dir / "manual.json"
    doc = read_json(path) if path.exists() else {}
    doc[row] = {"result": args.result, "tester": args.tester, "note": args.note or "",
                "recorded_at": iso(now or utcnow())}
    write_json(path, doc)
    loud = "  !! DEFERRED — printed in every summary" if args.result == "deferred" else ""
    print(f"{row}: {args.result}{loud}")
    return 0


# ---------------------------------------------------------------- rebuild (derived files)

def load_summaries(runs_dir):
    docs = [read_json(p) for p in sorted(Path(runs_dir).glob("*/*/summary.json"))]
    return sorted(docs, key=lambda d: (d.get("started_at") or "", d.get("run_id")))


def build_index(docs):
    return {"schema": SCHEMA, "_comment": "Derived by `device_run.py rebuild` from every summary.json; never edit.",
            "runs": [{"version": d["version"], "run_id": d["run_id"],
                      "path": f"{d['version']}/{d['run_id']}/summary.json", "verdict": d["verdict"],
                      "origin": d.get("origin", "device"), "commit": d["source"]["commit"],
                      "tree": d["source"].get("tree"), "started_at": d.get("started_at"),
                      "device": (d.get("device") or {}).get("name"), "ios": (d.get("device") or {}).get("ios"),
                      "d10_method": (d.get("launch") or {}).get("d10_method"),
                      "evidence_lost": bool(d.get("evidence_lost"))} for d in docs]}


def build_flakes(docs):
    stats = {}
    for d in docs:
        origin = d.get("origin", "device")
        for t in d.get("tests", []):
            if t["outcome"] == "Skipped":
                continue
            s = stats.setdefault(t["id"], {"runs": 0, "fails": 0, "env_fails": 0, "fail_then_pass": 0,
                                           "flake_events": 0, "sources": set(), "last_failure": None})
            s["runs"] += 1
            if "failure" in t or t["outcome"] == "Failed":
                causes = [t.get("cause")] + [r.get("cause") for r in t.get("reruns", []) if r["outcome"] == "Failed"]
                s["fails"] += 1
                s["env_fails"] += sum(1 for c in causes if (c or "").startswith("env:"))
                if t["outcome"] in ("Passed", "Expected Failure"):
                    s["fail_then_pass"] += 1
                    # A flake is an unexplained failure that passed on a rerun: not the bench (env:*)
                    # and not a bug someone found and fixed (code).
                    if t.get("cause") == "unknown":
                        s["flake_events"] += 1
                s["sources"].add(origin)
                s["last_failure"] = {"run": d["run_id"], "version": d["version"], "cause": t.get("cause"),
                                     "text": t.get("failure", "")[:200]}
    tests = {}
    for tid in sorted(stats):
        s = stats[tid]
        if not s["fails"]:
            continue
        chronic = s["flake_events"] >= 3
        tests[tid] = {**{k: v for k, v in s.items() if k != "sources"}, "sources": sorted(s["sources"]),
                      "chronic": chronic, **({"action": "chronic: fix it"} if chronic else {})}
    return {"schema": SCHEMA, "_comment": "Derived by `device_run.py rebuild`. A flake event is an unexplained "
            "(cause unknown) failure that passed on a rerun; a test with 3 or more is chronic.",
            "tests": tests}


def measured(t):
    """A test with a duration a bundle measured; a record from notes keeps null (unknown), never 0."""
    d = t.get("duration")
    return isinstance(d, (int, float)) and not isinstance(d, bool)


def build_trends(docs):
    rows = []
    for d in docs:
        suites = {}
        for b in d.get("bundles", []):
            if b.get("started_at") and b.get("finished_at"):
                secs = (parse_iso(b["finished_at"]) - parse_iso(b["started_at"])).total_seconds()
                suites[b["kind"]] = suites.get(b["kind"], 0) + int(secs)
        launch = d.get("launch") or {}
        slow = sorted((t for t in d.get("tests", []) if t["outcome"] != "Skipped" and measured(t)),
                      key=lambda t: (-t["duration"], t["id"]))[:20]
        rows.append({"version": d["version"], "run_id": d["run_id"], "verdict": d["verdict"],
                     "d10": {k: (launch.get(k) or {}).get("nitnemDrawn") for k in ("cold", "warm")},
                     "d10_method": launch.get("d10_method"),
                     "d10_xctest_pre_main": (launch.get("xctest") or {}).get("pre_main"),
                     "suite_seconds": suites,
                     "slowest": [[t["id"], t["duration"]] for t in slow]})
    return {"schema": SCHEMA, "_comment": "Derived by `device_run.py rebuild`.", "runs": rows}


def counts(d, kind):
    """passed / failed / skipped for one bundle kind; a record from notes carries its own (— when unknown)."""
    if d.get("origin") in NOTE_ORIGINS:
        c = (d.get("backfill_counts") or {}).get(kind)
        return f"{c['passed']}/{c['failed']}/{c['skipped']}" if c else "—"
    tot = {"passed": 0, "failed": 0, "skipped": 0}
    for b in d.get("bundles", []):
        if b.get("kind") == kind:
            c = b.get("counts", {})
            tot["passed"] += c.get("passedTests", 0)
            tot["failed"] += c.get("failedTests", 0)
            tot["skipped"] += c.get("skippedTests", 0)
    return f"{tot['passed']}/{tot['failed']}/{tot['skipped']}"


def build_history(docs, flakes):
    out = ["# Device-run history", "",
           "Derived by `python3 ios/tools/device_run.py rebuild` from every `summary.json` here; never edit.",
           "Runbook: `docs/ios/device-evidence.md`. `RECORDED` and `RECORDED-NO-BUNDLES` rows were written from",
           "notes (a backfill whose bundles were lost, a pre-tag triage run, a pull request's check); they never",
           "pass a gate. `RECORDED` ones have their bundles published in the evidence repository.", "",
           "| Version | Run | Verdict | Tree | Device | Unit | UI | Checklist | D10 cold / warm (method) |",
           "|---|---|---|---|---|---|---|---|---|"]
    for d in reversed(docs):
        u, ui = counts(d, "unit"), counts(d, "ui")
        cl = d.get("checklist", {})
        passed = sum(1 for e in cl.values() if e.get("result") == "pass")
        launch = d.get("launch") or {}
        d10 = " / ".join(f"{(launch.get(k) or {}).get('nitnemDrawn'):.2f} s"
                         if (launch.get(k) or {}).get("nitnemDrawn") is not None else "—" for k in ("cold", "warm"))
        if launch.get("d10_method"):
            d10 += f" ({launch['d10_method']})"
        dev = d.get("device") or {}
        out.append(f"| {d['version']} | [{d['run_id']}]({d['version']}/{d['run_id']}/summary.md) | "
                   f"{d['verdict']} | `{(d['source'].get('tree') or '')[:7]}` | "
                   f"{dev.get('name') or '—'} · iOS {dev.get('ios') or '?'} | "
                   f"{u} | {ui} | "
                   f"{passed}/{len(cl)} | {d10} |")
    out += ["", "Unit and UI columns are passed / failed / skipped."]
    unmeasured = [f"`{d['version']}/{d['run_id']}`" for d in reversed(docs)
                  if not any(measured(t) for t in d.get("tests", []) if t["outcome"] != "Skipped")]
    if unmeasured:
        out += ["", "No per-test durations recorded for " + ", ".join(unmeasured) +
                " (written from notes); `trends.json` gives them `slowest: []`."]
    out += ["", "## Flaky on the device", ""]
    tests = flakes["tests"]
    if not tests:
        out.append("None recorded.")
    else:
        out += ["Flake events are unexplained failures that passed on a rerun; bench (env) failures and fixed bugs",
                "(code) are counted but are not flakes.", "",
                "| Test | Runs | Fails | Flake events | Env fails | Last | |", "|---|---|---|---|---|---|---|"]
        for tid, s in sorted(tests.items(), key=lambda kv: (-kv[1]["flake_events"], kv[0])):
            last = s.get("last_failure") or {}
            out.append(f"| `{tid}` | {s['runs']} | {s['fails']} | {s['flake_events']} | {s['env_fails']} | "
                       f"{last.get('version', '')} {last.get('cause') or ''} | {'**chronic: fix it**' if s['chronic'] else ''} |")
    return "\n".join(out) + "\n"


def derived(runs_dir):
    docs = load_summaries(runs_dir)
    flakes = build_flakes(docs)
    return {"index.json": json.dumps(build_index(docs), indent=2, ensure_ascii=False) + "\n",
            "flakes.json": json.dumps(flakes, indent=2, ensure_ascii=False) + "\n",
            "trends.json": json.dumps(build_trends(docs), indent=2, ensure_ascii=False) + "\n",
            "HISTORY.md": build_history(docs, flakes)}


def cmd_rebuild(args, runs_dir=None):
    runs_dir = Path(runs_dir or RUNS)
    files = derived(runs_dir)
    if args.check:
        drift = [n for n, text in files.items()
                 if not (runs_dir / n).exists() or (runs_dir / n).read_text(encoding="utf-8") != text]
        if drift:
            print("derived files are stale: " + ", ".join(drift) + " — run `python3 ios/tools/device_run.py rebuild`")
            return 1
        print(f"derived files match {len(load_summaries(runs_dir))} run(s)")
        return 0
    for n, text in files.items():
        (runs_dir / n).write_text(text, encoding="utf-8")
    print(f"rebuilt {', '.join(files)} from {len(load_summaries(runs_dir))} run(s)")
    return 0


# ---------------------------------------------------------------- check

REQUIRED = {"schema": int, "version": str, "run_id": str, "origin": str, "source": dict, "app": dict,
            "device": dict, "started_at": str, "bundles": list, "tests": list, "checklist": dict,
            "verdict": str, "verdict_reasons": list}


def check_run(run_dir):
    """Every problem with one tracked run folder."""
    problems = []
    run_dir = Path(run_dir)
    files = sorted(p for p in run_dir.rglob("*") if p.is_file())
    names = {p.relative_to(run_dir).as_posix() for p in files}
    if names != {"summary.json", "summary.md"}:
        problems.append(f"a run holds summary.json and summary.md only; found {sorted(names)}")
    size = sum(p.stat().st_size for p in files)
    if size > RUN_CAP_BYTES:
        problems.append(f"{size} bytes > {RUN_CAP_BYTES} (raw evidence belongs in {EVIDENCE_REPO})")
    if not (run_dir / "summary.json").exists():
        return problems
    try:
        s = read_json(run_dir / "summary.json")
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        return problems + [f"summary.json is not valid JSON: {e}"]
    shape = [f"summary.json: `{key}` missing or not {typ.__name__}"
             for key, typ in REQUIRED.items() if not isinstance(s.get(key), typ)]
    if shape:
        return problems + shape
    if s["schema"] != SCHEMA:
        problems.append(f"schema {s['schema']} (this tool reads {SCHEMA})")
    if not RUN_ID_RE.match(s["run_id"]) or run_dir.name != s["run_id"]:
        problems.append(f"run id {s['run_id']!r} must be YYYYMMDDTHHMMZ-<tree7> and name its folder")
    if run_dir.parent.name != s["version"] or s["app"].get("version") != s["version"]:
        problems.append(f"version {s['version']} does not match its folder or app.version")
    for k in ("commit", "tree"):
        if not SHA_RE.match(s["source"].get(k) or ""):
            problems.append(f"source.{k} must be a full 40-character SHA")
    if s["source"].get("tree") and not s["run_id"].endswith("-" + s["source"]["tree"][:7]):
        problems.append("the run id's tree7 is not source.tree")
    if s["verdict"] not in VERDICTS:
        problems.append(f"verdict {s['verdict']!r} is not one of {', '.join(VERDICTS)}")
    verdict, reasons = compute_verdict(s)
    if (verdict, reasons) != (s["verdict"], s["verdict_reasons"]):
        problems.append(f"verdict recomputes to {verdict}, the file says {s['verdict']} — never edit a verdict")
    md = run_dir / "summary.md"
    if md.exists() and md.read_text(encoding="utf-8") != render_md(s):
        problems.append("summary.md is not what summary.json renders to — never edit it; re-run summarize")
    if s["origin"] == "backfill" and not s.get("evidence_lost"):
        problems.append("a backfilled run must say evidence_lost: true")
    elif s["origin"] not in NOTE_ORIGINS and s["origin"] != "device":
        problems.append(f"origin {s['origin']!r} is not device, {', '.join(NOTE_ORIGINS)}")
    elif s["origin"] == "device" and not s["bundles"]:
        problems.append("a device run lists its result bundles")
    tag = s.get("asset_tag") or asset_tag(s["version"], s["run_id"])
    if s["origin"] == "device" and tag != asset_tag(s["version"], s["run_id"]):
        problems.append(f"asset_tag {tag!r} is not {asset_tag(s['version'], s['run_id'])!r}")
    if s["bundles"] and not (ASSET_TAG_RE.match(tag) and tag.endswith(s["run_id"])):
        problems.append(f"asset_tag {tag!r} must be ios-<version or label>-<run id>")
    for b in s["bundles"]:
        if not re.match(r"^[0-9a-f]{64}$", b.get("tar_sha256") or ""):
            problems.append(f"bundle {b.get('name')}: tar_sha256 missing")
        if not isinstance(b.get("size"), int) or b["size"] <= 0:
            problems.append(f"bundle {b.get('name')}: size missing")
        if b.get("asset_url") != asset_url(s["version"], s["run_id"], b.get("asset", ""), tag):
            problems.append(f"bundle {b.get('name')}: asset_url is not the evidence release's")
    for t in s["tests"]:
        if t.get("cause") and t["cause"] not in CAUSE_VALUES:
            problems.append(f"{t['id']}: cause {t['cause']!r} is not one of {', '.join(CAUSE_VALUES)}")
        # Unknown is null, never 0, and only in a record from notes: a device run's bundles timed every test.
        if "duration" not in t:
            problems.append(f"{t['id']}: duration missing (seconds, or null when no bundle measured it)")
        elif t["duration"] is None:
            if s["origin"] not in NOTE_ORIGINS:
                problems.append(f"{t['id']}: duration null, but a device run's bundles measured every test")
        elif not measured(t) or t["duration"] < 0:
            problems.append(f"{t['id']}: duration {t['duration']!r} is not seconds (a number ≥ 0) or null")
    return problems


def scan_tree(runs_dir):
    """The scrub scan and the text-only rule over every file under ios/device-runs."""
    problems = []
    for p in sorted(Path(runs_dir).rglob("*")):
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            problems.append(f"{p.relative_to(runs_dir)}: not UTF-8 text (binaries go to {EVIDENCE_REPO})")
            continue
        for label in scrub_findings(text):
            problems.append(f"{p.relative_to(runs_dir)}: contains {label}")
    return problems


def cmd_check(args, runs_dir=None):
    runs_dir = Path(runs_dir or RUNS)
    dirs = [Path(d) for d in args.run_dirs] if args.run_dirs else sorted(
        p for p in runs_dir.glob("*/*") if p.is_dir())
    problems = []
    for d in dirs:
        problems += [f"{d.parent.name}/{d.name}: {p}" for p in check_run(d)]
    if runs_dir.exists():
        problems += scan_tree(runs_dir)
    for p in problems:
        print(f"✗ {p}")
    if problems:
        return 1
    print(f"OK  {len(dirs)} run(s) checked")
    return 0


# ---------------------------------------------------------------- verify-assets

def token():
    return os.environ.get("SGGS_EVIDENCE_TOKEN") or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")


def cmd_verify_assets(args, host=HOST):
    tok = token()
    problems, checked = [], 0
    for path in args.summaries:
        s = read_json(path)
        if not s.get("bundles"):
            continue                     # a record from notes with nothing published
        tag = s.get("asset_tag") or asset_tag(s["version"], s["run_id"])
        api = f"https://api.github.com/repos/{EVIDENCE_REPO}/releases/tags/{tag}"
        try:
            release = host.http(api, tok)
        except (urllib.error.HTTPError, urllib.error.URLError) as e:
            code = getattr(e, "code", None)
            if args.skip_if_unavailable and (not tok or code in (401, 403, 404)):
                print(f"NOTICE: {EVIDENCE_REPO} release {tag} is not readable here "
                      f"({'no token' if not tok else f'HTTP {code}'}); asset check skipped")
                continue
            problems.append(f"{tag}: release not readable ({code or e})")
            continue
        assets = {a["name"]: a for a in release.get("assets", [])}
        for b in s["bundles"]:
            a = assets.get(b["asset"])
            if a is None:
                problems.append(f"{tag}: asset {b['asset']} is missing")
                continue
            if a.get("size") != b["size"]:
                problems.append(f"{tag}: {b['asset']} is {a.get('size')} bytes, the summary says {b['size']}")
                continue
            if not args.sizes:
                with tempfile.TemporaryDirectory() as tmp:
                    dest = Path(tmp) / b["asset"]
                    host.http(a["url"], tok, accept="application/octet-stream", dest=dest)
                    if sha256_file(dest) != b["tar_sha256"]:
                        problems.append(f"{tag}: {b['asset']} downloaded with a different sha256")
                        continue
            checked += 1
        if "SHA256SUMS" not in assets:
            problems.append(f"{tag}: SHA256SUMS is missing")
    for p in problems:
        print(f"✗ {p}")
    if problems:
        return 1
    how = "name + size" if args.sizes else "re-downloaded, sha256 equal"
    print(f"OK  {checked} asset(s) verified ({how})" + ("" if args.sizes else
          " — the raw bundles in the staging folder may now be pruned"))
    return 0


# ---------------------------------------------------------------- summary.md

def render_md(s):
    dev, src, app = s.get("device") or {}, s["source"], s.get("app") or {}
    lines = [f"# Device run {s['version']} · {s['run_id']}", "",
             f"**Verdict: {s['verdict']}**" + (f"  ({NOTE_ORIGINS[s['origin']]})" if s.get("origin") in NOTE_ORIGINS else ""),
             "", "Generated by `ios/tools/device_run.py`; the facts are in `summary.json`. Never edit either file.", "",
             "| | |", "|---|---|",
             f"| Tested tree | `{src.get('tree')}` |",
             f"| Commit | `{src.get('commit')}` ({src.get('branch') or '?'}) |",
             f"| App | {app.get('version')} ({app.get('build')}), {app.get('build_config')} build: proves the checks, not the archived binary |",
             f"| Device | {dev.get('name')} · {dev.get('model')} · iOS {dev.get('ios')} |",
             f"| Connection | {(s.get('connection') or {}).get('transport') or '?'} |",
             f"| Started → ended | {s.get('started_at')} → {s.get('ended_at') or '?'} |",
             f"| Xcode | {s.get('xcode') or '?'} |"]
    pins = s.get("pins") or {}
    if pins:
        lines.append(f"| Pins | dataset {(pins.get('dataset') or {}).get('version')}, platform "
                     f"{(pins.get('platform') or {}).get('version')}, db `{(pins.get('db_sha256') or '')[:12]}` |")
    if s.get("verdict_reasons"):
        lines += ["", "## Why not PASS", ""] + [f"- {r}" for r in s["verdict_reasons"]]
    if s.get("bundles"):
        lines += ["", "## Result bundles", "", f"Assets of `{s.get('evidence_repo')}` release `{s.get('asset_tag')}`.", "",
                  "| Bundle | Started | Result | Passed | Failed | Skipped | sha256 |", "|---|---|---|---|---|---|---|"]
        for b in s["bundles"]:
            c = b.get("counts", {})
            lines.append(f"| {b['name']} | {b.get('started_at')} | {b.get('result')} | {c.get('passedTests')} | "
                         f"{c.get('failedTests')} | {c.get('skippedTests')} | `{(b.get('tar_sha256') or '')[:12]}` |")
    lines += ["", "## Checklist", "", "| Row | | Mode | Result | Evidence / note |", "|---|---|---|---|---|"]
    for row, e in s.get("checklist", {}).items():
        res = e.get("result", "")
        res = f"**{res.upper()}**" if res in ("deferred", "fail") else res
        ev = ", ".join(a["name"] for a in e.get("attachments", [])) or e.get("note") or ""
        if e.get("app_half"):
            ev = (ev + "; " if ev else "") + f"app half: {e['app_half']['outcome']}"
        lines.append(f"| {row} | {e.get('title')} | {e.get('mode')} | {res} | {ev} |")
    launch = s.get("launch") or {}

    def marks_line(label, marks):
        rest = ", ".join(f"{m} {v}" for m, v in sorted(marks.items(), key=lambda kv: kv[1]) if m != "nitnemDrawn")
        return f"- {label}: nitnemDrawn **{marks.get('nitnemDrawn')}** s" + (f" · {rest}" if rest else "")
    xct = launch.get("xctest") or {}
    if launch.get("cold") or launch.get("warm") or xct:
        lines += ["", "## D10 launch (seconds since process start)", ""]
        if launch.get("cold") or launch.get("warm"):
            how = {"out-of-xctest": "the bench's launches outside XCTest",
                   "in-xctest": "the app's own clock in the latest passing XCTest attempt (this build has no "
                                "out-of-XCTest hook)"}.get(launch.get("d10_method"), launch.get("d10_method"))
            lines.append(f"Judged by {how} (`d10_method: {launch.get('d10_method')}`), budget "
                         f"{launch.get('budget_s', LAUNCH_BUDGET_S):.0f} s:")
            lines += [marks_line(k, launch.get(k) or {}) for k in ("cold", "warm")]
        if xct.get("cold") or xct.get("warm"):
            lines += ["", "XCTest's latest attempt (recorded):"]
            lines += [marks_line(k, xct.get(k) or {}) for k in ("cold", "warm") if xct.get(k)]
            if xct.get("pre_main"):
                lines.append(f"- before the first app code (pre_main): {xct['pre_main']}; app work: {xct.get('app_work')}")
        if xct.get("xctest_clock"):
            x = xct["xctest_clock"]
            lines.append(f"- XCTest's clock (recorded, never judged): cold {x.get('cold')} s, warm {x.get('warm')} s")
    sysf = [(b["name"], f) for b in s.get("bundles", []) for f in b.get("system_failures", [])]
    if sysf:
        lines += ["", "## Test-runner failures", "", "Not tests: the runner itself failed, and the tests it had not reached "
                  "are listed under \"Planned but never run\" until a later bundle runs them.", "",
                  "| Bundle | Failure | Cause |", "|---|---|---|"]
        for name, f in sysf:
            lines.append(f"| {name} | {f['failure'][:200].replace('|', '/')} | {f['cause']} |")
    bad = [t for t in s.get("tests", []) if "failure" in t or (t["outcome"] == "Skipped" and not t.get("skip_allowed"))]
    if bad:
        lines += ["", "## Failures and reruns", "", "| Test | First failure | Cause | Reruns | Final |", "|---|---|---|---|---|"]
        for t in bad:
            reruns = ", ".join(f"{r['outcome']} ({r['bundle']})" for r in t.get("reruns", []))
            text = (t.get("failure") or t.get("skip") or "").replace("|", "\\|").replace("\n", " ")[:160]
            lines.append(f"| `{t['id']}` | {text} | {t.get('cause', '')} | {reruns} | {t['outcome']} |")
    if s.get("not_run"):
        lines += ["", f"## Planned but never run ({len(s['not_run'])})", ""] + [f"- `{t}`" for t in s["not_run"]]
    if s.get("warnings"):
        lines += ["", "## Warnings", ""] + [f"- {w}" for w in s["warnings"]]
    if s.get("notes"):
        lines += ["", "## Notes", ""] + [f"- {n}" for n in s["notes"]]
    if s.get("sources"):
        lines += ["", "## Sources", ""] + [f"- {n}" for n in s["sources"]]
    if s.get("origin") not in NOTE_ORIGINS:
        lines += ["", f"{len(s.get('tests', []))} tests recorded; {s.get('planned_count', 0)} planned."]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("begin")
    b.add_argument("--version", required=True)
    b.add_argument("--expect", required=True, help="the full commit SHA that must be HEAD")
    b.add_argument("--stamp", required=True, help="the build stamp written by device_bench.sh build")
    b.add_argument("--attest", default="", help="comma list: " + ",".join(ATTESTATIONS))
    b.add_argument("--staging", default=str(DEFAULT_STAGING))
    b.add_argument("--device-name", default="S-iPhone")
    b.add_argument("--planned", help="file of test ids, one per line (default: parsed from ios/App/Tests)")
    b.add_argument("--operator", default="supervisor")
    b.set_defaults(fn=cmd_begin)
    s = sub.add_parser("summarize")
    s.add_argument("run_dir")
    s.add_argument("--cause", action="append", help="TEST_ID=CAUSE, an operator's classification")
    s.add_argument("--out", help="where the tracked summary goes (default ios/device-runs/<V>/<run-id>)")
    s.add_argument("--no-tar", action="store_true", help="skip the tarballs (a dry look at the results)")
    s.set_defaults(fn=cmd_summarize)
    m = sub.add_parser("record-manual")
    m.add_argument("run_dir")
    m.add_argument("row")
    m.add_argument("result", choices=("pass", "fail", "deferred"))
    m.add_argument("--note", default="")
    m.add_argument("--tester", default="owner")
    m.set_defaults(fn=cmd_record_manual)
    r = sub.add_parser("rebuild")
    r.add_argument("--check", action="store_true")
    r.set_defaults(fn=cmd_rebuild)
    v = sub.add_parser("verify-assets")
    v.add_argument("summaries", nargs="+")
    v.add_argument("--sizes", action="store_true", help="compare names and sizes only (no download)")
    v.add_argument("--skip-if-unavailable", action="store_true",
                   help="a missing token or an unreadable evidence repo is a notice, not a failure")
    v.set_defaults(fn=cmd_verify_assets)
    c = sub.add_parser("check")
    c.add_argument("run_dirs", nargs="*")
    c.set_defaults(fn=cmd_check)
    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except Refusal as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 1
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
