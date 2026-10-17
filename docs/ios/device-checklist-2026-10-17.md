# Physical-device checklist run — 2026-10-17

Checklist: `testflight-test-plan.md` §8. Device: iPhone 17 Pro Max ("S-iPhone"), iOS 26.6.2.
Build: Debug development build of `main` at `9000542` plus this PR (`ios/uitest-isolation`,
final run on `021e780`).
This is not a candidate build, so the run does not sign off a release; it proves the checks and
records what still needs a person.

Automated rows run with `DeviceChecklistTests` (skipped unless
`TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1`); screenshots and pasted text are attachments in the
result bundle.

| ID | Result | Evidence / notes |
|---|---|---|
| D1 Charter S | NEEDS REFERENCE | Needs a person with a printed Bir. Automated support: `SaroopTests` and `scripture_crosscheck.py` (ShabadOS) |
| D2 Copy fidelity | **PASS** | Ang 1400, saroop on and off: both pastes are U+0A1C U+0A32 U+0A4D U+0A2F U+0A4D U+0A2F U+0A28, no U+0A75. Copy gives the verse alone and Share adds the citation, as `A11Y_CHECKLIST.md` item 11 specifies (the row's earlier "carry the Ang citation" wording was wrong and is corrected). Mutation check: with Copy writing the display form, D2 **fails** |
| D3 Gurmukhi rendering | **PASS** | Angs 1, 1354, 1359, 1400, light and dark (the app's own Appearance pinned per launch), AX3: Sant Lipi, no dotted circles; ਸਤੵਿੰ and ਜਲੵਨ have the ya under the letter |
| D4 Update from the store build | NOT RUN | Manual: needs the App Store build installed first |
| D5 Forget location | **PASS** (app) | `testForgetLocationReturnsToTheLocationCard` on the device. The widget half is manual |
| D6 Clear reading history | **PASS** (history, saved verse, Rehras) | Cancel (a tap outside: iOS 26 shows the dialog as a popover with no Cancel button) changed nothing; confirm cleared the history; a saved verse and the Rehras choice survived. The Nitnem plan and reminders are not covered by the test (manual) |
| D7 Spotlight | NOT RUN | Manual: the Home Screen (SpringBoard) was not readable from a device test (its hierarchy came back empty) |
| D8 Widgets | NOT RUN | Manual: placing widgets is a Home Screen action |
| D9 Airplane Mode | NOT RUN | Manual: a test cannot switch the radios |
| D10 Launch performance | **PASS** on this device | Cold (integrity cache cleared, full re-hash) 2.95 s, warm 2.83 s to Nitnem; both under 5 s. "Faster" is recorded, not asserted: the full hash takes tens of milliseconds on this phone, inside launch noise. Blocker for the row as written: the oldest supported device is not available, and a true fresh install would delete the device's data |
| D11 Force quit and relaunch | **PASS** | Resumed on Ang 700. A Debug fault injection holds a cold verify open; the force quit landed on "Verifying scripture integrity…" (screenshot) and the next launch verified fully with no failure. (Without it the kill could land after the verify; the test now fails rather than pass unproven) |
| D12 Hostile links | **PASS** | `sggs://shabad/3000000000`, `sggs://shabad/-1`, `sggs://ang/99999`, `sggs://shabad/abc`: no crash, stayed on Ang 500 |

`python3 ios/tools/device_checklist_report.py` on the final run: every automated row PASS with its
evidence (exit 0). The same script fails a run with any failure, skip, missing row, simulator
destination or missing evidence (checked against earlier failing runs).

Also run on the device in the same pass: all 257 unit tests, and `testPageBarStaysOnOneLineAtLargeText`,
`testRehrasVariantPersists`, `testDeepLinkAngBeatsResume`, `testLiveActivityToggleDefaultsOff`,
`testForgetLocationReturnsToTheLocationCard`, `testAccentPickerSwitchesAndPersists`,
`testSavedVerseRoundTrip`, `testChevronsTurnPagesRepeatedly`, `testReaderBoundsAndRubberBand`,
`testRapidChevronTapsStayInSync` — all pass.

## Reader page bar at large text

Reproduced on the device before the fix: at AX3 the Previous control was 96 pt high (a number
wrapped onto a second line) against a one-line 67 pt. The row now steps down — the Hukam word
gives way to its glyph, then the numbers go — and never wraps; VoiceOver still says "Previous
Ang, Ang 1353". Found while testing: the page bar's identifier replaced the identifiers of every
control inside it (all reported `readerPageBar`); it is now a container, as the Bani reader's is.

## Data safety found during this run

UI-test launches (`SGGS_UITEST=1`) deleted the Nitnem progress and plan files and reset reader
settings in the app's real storage. Device UI runs earlier on 2026-10-17 did this to the test phone
(owner confirmed nothing there needed recovery). Fixed with `UITestVault` (Debug only), hardened
after review:

- a manifest with SHA-256 for every item, present or absent; nothing is wiped unless the seal
  verified; built in a staging folder and published with one rename, retired with one rename
  only after the restore verified;
- an unverified, tampered, partial or other-format vault is never restored and never deleted;
- the saved-verses store is copied with SQLite's backup API (pending WAL included) and checked; a
  test's WAL is never replayed onto the restored store;
- a vault older than 30 minutes may predate real use: the live data is archived first;
- every UI test class ends with one ordinary launch, so a finished run hands the data back;
- `ios/tools/check_no_test_hooks.sh` proves no hook is in a Release bundle (wired into the archive;
  negative control: the Debug bundle is flagged in `SGGS.debug.dylib`).

`UITestVaultTests` (18 tests) cover: launch-mode classification, an exact round trip (boundary Ang
1430, nested and binary settings), pending WAL rows, a stale WAL from a crashed test, empty
original data, an unreadable source, an unwritable vault, an interrupted seal, repeated seals, a
tampered vault, another format, an unverified vault, unknown items, a partial restore that
completes on the next launch, an interrupted retire, no vault, a stale vault, bounded archives
and the reset list.

Proven on the device: after the final run (which forgot the stored location, saved and deleted
verses, changed settings and the resume Ang) the class teardown restored everything; read back
from inside the app, every setting, the App Group location, the saved-verse count and the Nitnem
files matched the backup taken before the run, and no vault remained.

## Manual rows for the owner

D4, D7, D8, D9 and the D5 widget half, plus D1 with a printed Bir.
