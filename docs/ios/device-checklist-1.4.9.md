# Physical-device checklist run — 1.4.9 release candidate (2026-10-25)

Checklist: `testflight-test-plan.md` §8. Device: iPhone 17 Pro Max ("S-iPhone"), iOS 27.0.1,
connected over the Wi-Fi tunnel (the cable is charge-only), portrait with the orientation lock on.
Build: Debug development build of `release/1.4.9` (dataset 1.1.0, platform v1.4.9) on `main`
`2040eee` (#83 included). It is not the archived candidate, so it proves the checks, not the binary.

Automated rows run with `DeviceChecklistTests` (`TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1`);
screenshots, pasted text and screen recordings are attachments in the result bundles.

| ID | Result | Evidence / notes |
|---|---|---|
| D1 Charter S | NEEDS REFERENCE | Needs a person with a printed Bir (Charter S before testers see the build) |
| D2 Copy fidelity | **PASS** | Ang 1400, saroop on and off: both pastes carry `ਜਲ੍ਯ੍ਯਨ` as stored (U+0A1C U+0A32 U+0A4D U+0A2F U+0A4D U+0A2F U+0A28), no U+0A75 |
| D3 Gurmukhi rendering | **PASS** | Angs 1, 1354, 1359, 1400, light and dark, AX3, plus Ang 1354 at the standard size |
| D4 Update from the store build | NOT RUN | Manual: needs the App Store build installed first |
| D5 Forget location | not re-run | The app half is `testForgetLocationReturnsToTheLocationCard`; the widget half is manual |
| D6 Clear reading history | **PASS** | Cancel changed nothing; confirm cleared the history; the saved verse and the Rehras choice (Damdami Taksal) survived |
| D7 Spotlight | NOT RUN | Manual |
| D8 Widgets | NOT RUN | Manual |
| D9 Airplane Mode | NOT RUN | Manual |
| D10 Launch performance | **PASS** (from the screen recording) | Window opening to the Nitnem screen, read frame by frame (0.25 s) from two runs: cold, with the integrity cache cleared and the whole database re-hashed, 1.25 s and 1.6 s; warm 1.5 s and 4.3 s. The test's own clock still reports 6.8–8.2 s and fails: see below |
| D11 Force quit and relaunch | **PASS** | Resume and a force quit during a held cold verify |
| D12 Hostile links | **PASS** | No crash on the hostile `sggs://` forms |

## D10: why the test's clock is not the launch time on this connection

The xcresult timelines split each reported time:

| Run | XCTest spawning the app (home screen unchanged) | Automation session → Nitnem found | Reported |
|---|---|---|---|
| cold 1 | 4.1 s | 2.7 s | 6.83 s |
| warm 1 | 1.3 s | 3.0 s | 4.29 s |
| cold 2 | 4.8 s | 3.4 s | 8.22 s |
| warm 2 | 2.0 s | 5.0 s | 7.04 s |

About 3 s of every reading is XCTest launching and polling the app over the Wi-Fi tunnel, and it
varies by about ±2 s, so the clock cannot judge a 5 s budget here. On 2026-10-17 (iOS 26, the same
phone) the same test read 2.95 s cold and 2.83 s warm.

An earlier reading of 10.12 s also included 7.4 s for XCTest terminating a copy of the app that was
still running, with the clock already started. The test now terminates any running copy and waits
for it to stop before each clock starts.

The warm 4.3 s run held the ੴ launch screen for about 4 s, while the other three runs held it for
1.25–1.6 s. It is under the budget, but is listed as a follow-up below.

## Test changes in this release

- `testD10ColdAndWarmLaunchTimes`: before each clock starts, the app is terminated and the test
  waits for `.notRunning`.
- `tearDown`: `terminate()` timed out after 60 s over the tunnel once D2 and D6 had passed every
  step, which failed both rows. It is now an expected, non-strict failure (`XCTExpectFailure`), so a
  slow terminate no longer fails a row that has already passed. The next `launch()` terminates any
  copy that is still running anyway.

## Other device runs for this candidate

- The first full XCUITest run failed four tests with the phone in landscape (app window 956×440).
  After setting portrait, five of the six failing tests passed when re-run. The sixth,
  `testLineageAndVaars`, was fixed in #83 and passed twice on the device.
- The full unit and UI suites on the simulator are the `app` job of the release PR.
- The owner's real app data was sealed by `UITestVault` for the runs and restored by an ordinary
  launch afterwards.

## Manual rows for the owner

D4, D7, D8, D9 and the D5 widget half, plus D1 with a printed Bir.

## Follow-ups

- Done after 1.4.9: D10 now reads the launch time from the app itself (below).
- Done after 1.4.9: the warm launch that held the launch screen for about 4 s (below).

## After 1.4.9: D10 measured inside the app

`LaunchClock` (Debug builds only) records a timeline in seconds from the moment the kernel created
the process: `appInit` (the first app code), `containerReady`, `rootShown` (RootView's first
frame, where the launch screen hands over), `integrityStart`, `integrityHashed`, `integrityDone`,
`tabsShown` and `nitnemDrawn`. Each mark is also a Points of Interest signpost for Instruments.
With `SGGS_UITEST_LAUNCH_METRICS=1`, which D10 sets, the Nitnem screen carries the timeline as the
value of an invisible `launchMetrics` element. D10 asserts `nitnemDrawn` < 5 s for the cold and
the warm launch, checks that the cold launch re-hashed and the warm one used the fingerprint, and
records XCTest's own clock beside it without judging it. The process start comes after XCTest
has spawned the app, so the spawn overhead is left out. Any wait for XCTest inside the process
still counts, and a late `appInit` shows it. None of this is in a release build:
`ios/tools/check_no_test_hooks.sh` lists `SGGS_UITEST_LAUNCH_METRICS`, `LaunchClock`,
`launchMetrics` and `nitnemDrawn`, passes on a Release bundle and fails on a Debug one.

## After 1.4.9: the warm launch that held the launch screen for 4 s

The screen recordings of runs `d10b1` and `d10b2`, read every 0.25 s, against each run's xcresult
timeline:

| Launch | ੴ on screen | XCTest "Setting up automation session" |
|---|---|---|
| d10b1 warm | about 1.25 s | 0.77 s |
| d10b2 warm | about 4.0 s | 2.77 s |

- The ੴ shown for those 4 s was the system launch screen. RootView's own verifying state adds a
  spinner and "Verifying scripture integrity…" under the logo, and no frame shows them. So the
  app had not drawn its first frame. The integrity check, which runs only after that frame, did
  not hold the launch, and neither did its structural queries on the corpus actor.
- In both warm runs the Nitnem screen appeared about 0.1–0.2 s after XCTest finished setting up
  its automation session, and the hold grew with that setup (0.77 s → about 1.25 s, 2.77 s → about
  4.0 s). XCTest connects to the app as it starts; over the Wi-Fi tunnel that took 2.8 s in
  `d10b2`. The two move together, which points to the first frame waiting on that connection; an
  install that XCTest did not launch would have no such wait. This is inferred from two runs, not
  yet measured inside the app.
- The app's own launch path has nothing that blocks for seconds. Before the first frame it opens
  the corpus (SQLite, read-only), opens the bookmarks store, and asks Spotlight to reconcile, which
  is asynchronous. A warm launch uses the cached fingerprint, so no hash runs. After the first
  frame, the three structural checks (Ang 1, one FTS query, one verify) are the only work on the
  corpus actor until Nitnem mounts.
- The next device run shows where any long hold goes. If `appInit` is late, the time went before
  the first app code (dyld and XCTest's injected bootstrap). If the gap from `rootShown` to
  `tabsShown` is long, it was the integrity check.
