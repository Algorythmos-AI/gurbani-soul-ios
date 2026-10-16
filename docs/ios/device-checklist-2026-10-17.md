# Physical-device checklist run — 2026-10-17

Checklist: `testflight-test-plan.md` §8. Device: iPhone 17 Pro Max ("S-iPhone"), iOS 26.6.2.
Build: Debug development build of `main` at `9000542` plus this PR (`ios/uitest-isolation`).
This is not a candidate build, so the run does not sign off a release; it proves the checks and
records what still needs a person.

Automated rows run with `DeviceChecklistTests` (skipped unless
`TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1`); screenshots and pasted text are attachments in the
result bundle.

| ID | Result | Evidence / notes |
|---|---|---|
| D1 Charter S | NEEDS REFERENCE | Needs a person with a printed Bir. Automated support: `SaroopTests` and `scripture_crosscheck.py` (ShabadOS) |
| D2 Copy fidelity | **PASS** | Ang 1400, saroop on and off: both pastes are `ਗੋਬਿੰਦ ਵਾਲੁ … ਜਲ੍ਯ੍ਯਨ …` with U+0A1C U+0A32 U+0A4D U+0A2F U+0A4D U+0A2F U+0A28, no U+0A75. **Open question:** Copy verse gives the bare verse with no Ang citation (by design: Share carries the citation). The row's "carry the Ang citation" expectation and the design disagree; owner decision |
| D3 Gurmukhi rendering | **PASS** | Angs 1, 1354, 1359, 1400, light and dark, AX3: Sant Lipi, no dotted circles. ਸਤੵਿੰ (Ang 1354) has the sihari before ਤ and the ya under it; ਜਲੵਨ (Ang 1400) likewise. **Finding (P3):** at AX3 the page bar's previous/next Ang numbers wrap onto two lines ("135 / 3") |
| D4 Update from the store build | NOT RUN | Needs the App Store build installed first (manual) |
| D5 Forget location | **PASS** (app) | `testForgetLocationReturnsToTheLocationCard` on the device. The widget half is manual |
| D6 Clear reading history | **PASS** | Cancel (a tap outside: iOS 26 shows the dialog as a popover with no Cancel button) changed nothing; confirm cleared the history; a saved verse and the Rehras choice survived. Reminders and the Nitnem plan were not checked |
| D7 Spotlight | NOT RUN | Manual: the Home Screen is not readable from a device test |
| D8 Widgets | NOT RUN | Manual |
| D9 Airplane Mode | NOT RUN | Manual |
| D10 Launch performance | PARTIAL | This device (the newest, not the oldest supported): relaunch to tabs 2.69 s; relaunch after an interrupted verify 2.99 s. Fresh install not measured (it would delete the device's data) |
| D11 Force quit and relaunch | **PASS** | Resumed on Ang 700; killed 0.3 s into launch, the next launch verified and opened with no integrity failure |
| D12 Hostile links | **PASS** | `sggs://shabad/3000000000`, `sggs://shabad/-1`, `sggs://ang/99999`, `sggs://shabad/abc`: no crash, stayed on Ang 500 |

## Data safety found during this run

UI-test launches (`SGGS_UITEST=1`) deleted the Nitnem progress and plan files and reset reader
settings in the app's real storage. On a simulator that is harmless; on a developer's own iPhone
it is their data. Device UI runs earlier on 2026-10-17 did this to the test phone (owner confirmed
nothing there needed recovery). Fixed in this PR with `UITestVault` (Debug only):

- the first UI-test launch copies the real data (both defaults domains, the Nitnem files and the
  saved-verses store) into a vault before anything is wiped; a seal that fails wipes nothing;
- the next ordinary launch restores it exactly (files the tests created are removed) and deletes
  the vault; a restore that cannot finish keeps the vault for the next launch;
- a test's own relaunch (`SGGS_UITEST_RELAUNCH=1`) keeps the test state.

Proven on the device: after the run (which forgot the stored Solar location and moved the
resume Ang), an ordinary launch brought back the Solar location, the resume Ang and the
appearance setting. `UITestVaultTests` covers the round trip, a second seal, no vault, a failed
restore and a failed seal.

Two smaller test fixes from the run: UI-test launches now also reset the saroop toggle (a test
that switched it off leaked into the next one), and a Gurmukhi predicate must match whole
grapheme clusters (`ਸਤ੍ਯ` alone never matches `ਸਤ੍ਯ੍ਯਿੰ`).

## Manual rows for the owner

D4, D7, D8, D9 and the D5 widget half, plus D1 with a printed Bir.
