# Device-run history

Derived by `python3 ios/tools/device_run.py rebuild` from every `summary.json` here; never edit.
Runbook: `docs/ios/device-evidence.md`. `RECORDED` and `RECORDED-NO-BUNDLES` rows were written from
notes (a backfill whose bundles were lost, a pre-tag triage run, a pull request's check); they never
pass a gate. `RECORDED` ones have their bundles published in the evidence repository.

| Version | Run | Verdict | Tree | Device | Unit | UI | Checklist | D10 cold / warm (method) |
|---|---|---|---|---|---|---|---|---|
| 1.5.2 | [20261030T0936Z-807c055](1.5.2/20261030T0936Z-807c055/summary.md) | PASS | `807c055` | iPhone-11 · iOS 27.0.1 | 451/0/0 | 83/0/14 | 7/12 | 1.59 s / 0.59 s (out-of-xctest) |
| 1.5.2 | [20261030T0750Z-807c055](1.5.2/20261030T0750Z-807c055/summary.md) | FAIL | `807c055` | iPhone-11 · iOS 27.0.1 | 451/0/0 | 82/1/14 | 5/12 | — / — (out-of-xctest) |
| 1.5.1 | [20261028T2026Z-a4e2570](1.5.1/20261028T2026Z-a4e2570/summary.md) | PASS | `a4e2570` | iPhone-11 · iOS 27.0.1 | 446/0/0 | 83/0/14 | 10/12 | 1.68 s / 0.57 s (out-of-xctest) |
| 1.4.9 | [20261027T1750Z-79b5f96](1.4.9/20261027T1750Z-79b5f96/summary.md) | RECORDED | `79b5f96` | S-iPhone · iOS 27.0.1 | — | 2/0/0 | 1/12 | 0.56 s / 0.52 s (in-xctest) |
| 1.5.0 | [20261027T1605Z-63d7386](1.5.0/20261027T1605Z-63d7386/summary.md) | RECORDED | `63d7386` | S-iPhone · iOS 27.0.1 | 445/0/0 | 82/0/3 | 6/12 | 1.78 s / 1.76 s (in-xctest) |
| 1.4.9 | [20261026T0024Z-bc36c9b](1.4.9/20261026T0024Z-bc36c9b/summary.md) | RECORDED-NO-BUNDLES | `bc36c9b` | S-iPhone · iOS 27.0.1 | 408/0/0 | 76/2/9 | 5/12 | — / — |
| 1.4.9 | [20261025T0822Z-844e172](1.4.9/20261025T0822Z-844e172/summary.md) | RECORDED-NO-BUNDLES | `844e172` | S-iPhone · iOS 27.0.1 | — | — | 6/12 | — / — |
| 1.4.8 | [20261024T1705Z-0fd2439](1.4.8/20261024T1705Z-0fd2439/summary.md) | RECORDED-NO-BUNDLES | `0fd2439` | S-iPhone · iOS 27.0.1 | 372/0/0 | 66/8/2 | 0/12 | — / — |
| 1.4.2 | [20261017T0020Z-ee0c379](1.4.2/20261017T0020Z-ee0c379/summary.md) | RECORDED-NO-BUNDLES | `ee0c379` | S-iPhone · iOS 26.6.2 | 257/0/0 | — | 7/12 | — / — |

Unit and UI columns are passed / failed / skipped.

No per-test durations recorded for `1.4.9/20261027T1750Z-79b5f96`, `1.5.0/20261027T1605Z-63d7386`, `1.4.9/20261026T0024Z-bc36c9b`, `1.4.9/20261025T0822Z-844e172`, `1.4.8/20261024T1705Z-0fd2439`, `1.4.2/20261017T0020Z-ee0c379` (written from notes); `trends.json` gives them `slowest: []`.

## Flaky on the device

Flake events are unexplained failures that passed on a rerun; bench (env) failures and fixed bugs
(code) are counted but are not flakes.

| Test | Runs | Fails | Flake events | Env fails | Last | |
|---|---|---|---|---|---|---|
| `SGGSUITests/testBaniContentsJumpsToPauri()` | 4 | 1 | 1 | 0 | 1.5.0 unknown |  |
| `SGGSUITests/testCaptureJaapPauri79()` | 4 | 1 | 1 | 0 | 1.5.0 unknown |  |
| `SGGSUITests/testGutkaSwitchTogglesTheLayout()` | 4 | 1 | 1 | 0 | 1.4.8 unknown |  |
| `SGGSUITests/testIndexContinueCardResumes()` | 4 | 1 | 1 | 0 | 1.5.0 unknown |  |
| `SGGSUITests/testInsights()` | 4 | 1 | 1 | 0 | 1.4.8 unknown |  |
| `SGGSUITests/testRaagPageFromTheIndex()` | 4 | 1 | 1 | 0 | 1.4.9 unknown |  |
| `SGGSUITests/testReaderChromeReturnsOnScrollUp()` | 4 | 1 | 1 | 0 | 1.4.8 unknown |  |
| `SGGSUITests/testReaderJumpAndSwipe()` | 4 | 1 | 1 | 0 | 1.4.9 unknown |  |
| `SGGSUITests/testSavedVerseRoundTrip()` | 5 | 2 | 1 | 0 | 1.5.2 unknown |  |
| `SGGSUITests/testSehajFocusHidesChromeAndExits()` | 4 | 1 | 1 | 0 | 1.5.0 unknown |  |
| `SGGSUITests/testThemesIndexSearchFindsByMeaningAndGurmukhi()` | 5 | 2 | 1 | 1 | 1.4.9 env:landscape |  |
| `DeviceChecklistTests/testD10ColdAndWarmLaunchTimes()` | 8 | 3 | 0 | 2 | 1.5.0 env:tunnel |  |
| `DeviceChecklistTests/testD2CopyIsVerbatimWithSaroopOnAndOff()` | 7 | 1 | 0 | 1 | 1.4.9 code |  |
| `DeviceChecklistTests/testD6ClearHistoryCancelThenConfirmKeepsEverythingElse()` | 7 | 1 | 0 | 1 | 1.4.9 env:tunnel |  |
| `SGGSUITests/testCaptureScreens()` | 4 | 1 | 0 | 1 | 1.4.9 env:landscape |  |
| `SGGSUITests/testForgetLocationReturnsToTheLocationCard()` | 5 | 1 | 0 | 0 | 1.4.8 code |  |
| `SGGSUITests/testLineageAndVaars()` | 5 | 2 | 0 | 1 | 1.4.9 env:landscape |  |
| `SGGSUITests/testNitnemOpensJapjiAndCompletes()` | 4 | 1 | 0 | 1 | 1.5.0 env:tunnel |  |
| `SGGSUITests/testNitnemRemindersScreenOpens()` | 4 | 1 | 0 | 1 | 1.5.0 env:tunnel |  |
| `SGGSUITests/testPrivacyPolicyReachableFromMore()` | 4 | 1 | 0 | 0 | 1.4.8 code |  |
| `SGGSUITests/testSearchOpensShabad()` | 4 | 1 | 0 | 1 | 1.4.9 env:landscape |  |
| `SGGSUITests/testThemeListStatesItsTrueTotal()` | 4 | 1 | 0 | 1 | 1.4.9 env:landscape |  |
| `SGGSUITests/testVerifyShowsVerdict()` | 5 | 2 | 0 | 1 | 1.4.9 env:landscape |  |
