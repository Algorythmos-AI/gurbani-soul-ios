# Device-run evidence

Every release's physical-device run is kept as permanent, checkable proof. The proof is that one
source **tree** passed every planned test and the device checklist (`testflight-test-plan.md` §8)
on a real iPhone. A tree, not a commit, survives a squash merge.

| What | Where | Who can read it |
|---|---|---|
| `summary.json` + `summary.md` for each run (text, ≤ 256 KB) | this repo, `ios/device-runs/<version>/<run-id>/` | everyone |
| `index.json`, `flakes.json`, `trends.json`, `HISTORY.md` | `ios/device-runs/`, derived by `device_run.py rebuild` | everyone |
| the raw `.xcresult` bundles (tar.gz) + `SHA256SUMS` | release `ios-<version>-<run-id>` of the private repo `Algorythmos-AI/gurbani-soul-device-evidence` | the owner, and CI through `SGGS_EVIDENCE_TOKEN` (a fine-grained token: this repository only, Contents read-only) |
| D2, D3 and D11 screens (`checklist-evidence-<run-id>.tar.gz`) | the public iOS release `v<version>`, after the owner has looked at every picture | everyone |

The bundles are private because they hold the device UDID, host paths and screen recordings
(which can catch a notification); none of that can be scrubbed. Never use Actions artifacts (they
expire) or Git LFS (this repo does not use it).

`run-id` is `YYYYMMDDTHHMMZ-<tree7>`: when `begin` ran, in UTC, and the first seven characters of
the tested tree.

## Verdicts

The verdict is recomputed by the tool from the facts every time; it is never typed.

- **PASS**: every planned test passed. A skip is allowed only for the reasons in
  `SKIP_ALLOWLIST`. A test that failed for an environment or unknown cause passed on a rerun of
  the same tree and build stamp (the first failure stays in the record with its cause). Every
  automated checklist row (D2 D3 D6 D10 D11 D12) passed and attached its evidence; D10 is judged
  only by the launches outside XCTest (see "D10" below). Every manual row (D1 D4 D5
  D7 D8 D9) is `pass`, or `deferred` with the owner's note. The restore launch is recorded.
- **INCOMPLETE**: something is missing: a bundle kind (`unit`, `ui`, `checklist`), a planned test
  that never ran, a failure with no rerun yet, a skip outside the allowlist, a row without
  evidence, a manual row not recorded.
- **FAIL**: a test failed twice in a row, or a failure was classified `code`, or a manual row
  failed, or D10 was over budget outside XCTest, or the build stamp's tree is not the tested tree.
- **RECORDED-NO-BUNDLES**: backfilled from documents after the bundles were lost
  (`evidence_lost: true`). It never passes a gate.

Failure causes: `code`, `env:locked`, `env:landscape`, `env:foreground`, `env:tunnel`,
`env:cert`, `unknown`. `summarize` classifies from the failure text and from a landscape failure
screenshot. If `BenchGuardTests` (the probe that runs first) failed, its cause explains the other
unknown failures of that bundle. Only an operator says `code` (`summarize --cause ID=code`).

## D10: how the launch is judged

On the 1.5.0 release candidate, D10 read 5.054 s from process start to the drawn Nitnem home, but
the app's first code ran only at 4.786 s. The app's own work, including the full re-hash, took
0.27 s; the rest was XCTest's bootstrap over the Wi-Fi tunnel, which no user pays. A rerun of the
same build read 1.78 s. So:

1. **Preferred judge, outside XCTest** (`d10_method: out-of-xctest`). `device_bench.sh d10
   <worktree> <run>` launches the installed Debug build with devicectl, first cold (the verified
   fingerprint dropped, so the whole database is re-hashed) and then warm, and copies each launch's
   timeline into `<run>/d10/`. D10 passes when both read process start → `nitnemDrawn` **< 5 s**,
   the cold launch re-hashed (`cached_hash` false) and the warm one used the fingerprint (true).
   5 s or more is **FAIL**; a missing file, a timeline written before `begin` or a wrong
   `cached_hash` is **INCOMPLETE**.
2. **Fallback, in XCTest** (`d10_method: in-xctest`), for a build without the out-of-XCTest hook
   (every build before it shipped, 1.5.0 included). `device_bench.sh d10` then skips with a notice
   and leaves no `d10/`. The app's own timeline from the latest **passing** attempt of
   `testD10ColdAndWarmLaunchTimes` judges, with the same conditions: both < 5 s, the cold launch
   re-hashed, the warm one on the fingerprint. The method is recorded in every summary, the index,
   the trends and the history.
3. **The XCTest test** still runs and its own < 5 s assertion is unchanged. When it fails *only*
   that budget and that launch reached the first app code (`appInit`) after **2 s**, the failure
   is XCTest's bootstrap: `env:tunnel`. Like every env failure it **needs a passing rerun on the
   same tree and build stamp**, and two in a row fail the run. With `appInit` at 2 s or less it is
   the app itself: `code`, so **FAIL**.
4. **Recorded, never the judge**: XCTest's latest attempt split into `pre_main` (process start →
   first app code) and `app_work` (first app code → Nitnem drawn), and XCTest's own clock.

## Pre-run (ask the owner; record their answers with `--attest`)

1. The phone is unlocked and Auto-Lock is **Never** (`unlocked`, `auto-lock-never`).
2. Portrait, with the orientation lock on (`portrait-lock`).
3. Do Not Disturb on (`dnd`), every other app quit (`no-other-apps`), and nobody touches the phone
   until the restore launch (`hands-off`).
4. The developer certificate is trusted: Settings → General → VPN & Device Management
   (`cert-trusted`).
5. `bash ios/tools/device_bench.sh check`: the phone is available, and over USB where possible
   (a Wi-Fi tunnel has dropped mid-run).
6. At least 8 GB free on the Mac (`df -h /System/Volumes/Data`). A full disk stopped a run and
   forced its bundles to be deleted.

The bench reads the phone's identifiers from `~/.config/sggs/device-bench.env` (untracked; mode
600). The App Store Connect key is passed by path only.

## Run

From a clean worktree at the exact commit under test:

```bash
bash ios/tools/device_bench.sh build "$PWD"
```

```bash
python3 ios/tools/device_run.py begin --version 1.5.0 --expect <full sha> \
  --stamp <stamp printed by the build> \
  --attest unlocked,auto-lock-never,portrait-lock,dnd,no-other-apps,hands-off,cert-trusted
```

`begin` refuses the wrong commit, a dirty worktree, a stamp from another tree, a locked phone,
missing attestations, a staging folder under `/tmp` or the scratchpad (they get wiped), and a run
folder that exists. It prints the run folder, `~/SGGS-device-evidence/<version>/<run-id>/`. Write
every bundle into its `bundles/`, one fresh name each:

1. `unit.xcresult`: the unit tests (this also installs the build).
2. `device_bench.sh d10 "$PWD" <run>`: D10's cold and warm launches outside XCTest, into `<run>/d10/`
   (it skips with a notice on a build without the hook; D10 then falls back to the XCTest attempt).
3. `ui-01.xcresult`, `ui-02.xcresult`, …: the UI tests in batches of 12, each in a fresh bundle.
4. `checklist.xcresult`: `DeviceChecklistTests` with `TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1`.
5. The restore launch (one ordinary launch hands the phone's real data back from `UITestVault`),
   then `device_run.py record-manual <run> restore pass --note "<time>"`.

## Summarize, rerun, record

```bash
python3 ios/tools/device_run.py summarize ~/SGGS-device-evidence/1.5.0/<run-id>
```

It refuses a bundle outside the run folder (copy, never link), an unfinished one, one that started
before `begin`, one already recorded by another run (a reused result folder), and one that did not
run on the named phone. Rerun each env or unknown failure on its own into `rerun-1.xcresult`,
`rerun-2.xcresult`, …, then summarize again. A test that fails twice in a row fails the run: fix
the cause and start a new run.

Manual rows, with the owner:

```bash
python3 ios/tools/device_run.py record-manual <run> D7 pass --note "unsaved verse gone after relaunch"
python3 ios/tools/device_run.py record-manual <run> D4 deferred --note "no store build on the phone; after release"
```

A deferred row is printed in capitals in every summary.

## Publish (owner)

The supervisor prepares; the owner approves and runs each upload.

```bash
gh release create ios-1.5.0-<run-id> --repo Algorythmos-AI/gurbani-soul-device-evidence \
  --title "iOS 1.5.0 device run <run-id>" --notes-file <run>/summary.md <run>/upload/*
```

The public screens go to the iOS release only after the owner has looked at every picture; any
picture with a notification or anything else personal is dropped:

```bash
gh release upload v1.5.0 --repo Algorythmos-AI/gurbani-soul-ios <run>/upload-public/checklist-evidence-<run-id>.tar.gz
```

## Verify, then record in git

```bash
python3 ios/tools/device_run.py verify-assets ios/device-runs/1.5.0/<run-id>/summary.json
```

It downloads every asset again and compares sha256. Only after that may the raw files in the
staging folder be pruned. Then:

```bash
python3 ios/tools/device_run.py rebuild && python3 ios/tools/device_run.py check
```

Open a PR with the run folder and the derived files. The evidence never goes into the release
commit: the release commit's tree must be the tree that was tested.

## Why each rule exists

| Rule | What happened |
|---|---|
| `begin` checks HEAD and the stamp's tree | A chain without `set -e` tested the wrong commit after a failed fetch |
| A fresh folder per bundle; reused bundles are refused | A batch reused the previous result path and failed at once |
| Planned tests that never ran ⇒ INCOMPLETE | The Wi-Fi tunnel dropped and about 40 tests never ran |
| Attested bench, `BenchGuardTests` first | Locked phone (CoreDeviceError 10003), landscape (four false failures), another app in front (eleven false failures) |
| D10 judged outside XCTest | XCTest's clock over the tunnel added about 3 s ± 2 s and once 7.4 s of terminate; on 1.5.0 its bootstrap put the app's first code at 4.8 s |
| Staging never in `/tmp`; private release, verified by re-download | The scratchpad was wiped twice and a full disk forced bundles to be deleted |
| Identical images under two names flagged | Checksums ≠ correctness: wrong screens with valid sums, duplicates |
| Full SHAs; trees, not commits | Short SHAs in merges; a squash merge changes the commit, not the tree |
| Device-only failures and flakes are kept | They found real bugs (a card that swallowed taps, a voice page that never loaded) |
| Debug build | The run proves the checks, not the archived binary; the archive has its own gates |
