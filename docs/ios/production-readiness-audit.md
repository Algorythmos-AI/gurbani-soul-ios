# Production-readiness audit — Gurbani Soul iOS

**Date:** 2026-10-17 · **Code audited:** `main` @ `bfd41cd` (1.4.2 plus PR #36), fixes on branch
`audit/production-readiness` (PR #37) · **Device:** iPhone 17 Pro Max, iOS 26.6.2 (23G90) ·
**Toolchain:** Xcode 27.0 locally; CI uses Xcode 26.3 / iOS 26.2 simulator.

Statuses: **PASS** executed with evidence · **FAIL** executed, defect confirmed · **BLOCKED** could
not run (blocker named) · **NOT RUN** · **NEEDS REFERENCE** scripture correctness needs an authoritative source.

## 1. Release recommendation: **BLOCKED**

Three gates are open; none of them is a crash in the current App Store build, but each is a release gate:

1. **Scripture fidelity (P0, data):** the corpus is missing an **aunkar** in 145 words on 123 Angs where
   the printed source carries aunkar and hora on one letter (§3.1). Pre-existing since the first
   build; confirmed against the source PDF and an independent second source. Needs a data decision
   (scholar + `sggs-rebuild-db`) — this audit does not change scripture.
2. **CI was not a gate:** the required `app` check passed while tests failed, on every main run checked
   since 2026-09-24, including the 1.4.1 and 1.4.2 releases (§4.1). Fixed in PR #37; the 4 UI
   failures it exposes must be fixed before the next upload.
3. **Scholar review (G3)** of icon v2, the launch screen and the yakash saroop is open, and Charter S
   has not been signed on any build that contains PR #36.

## 2. Scope and method

- Read the reader, navigation, composition sheet, saroop and every export path; persistence
  (SwiftData bookmarks, Nitnem files, `@AppStorage`), the launch integrity cache, widgets, Spotlight,
  deep links, CI workflows, the archive and pre-flight scripts, and the TestFlight test plan.
- Diffed every persisted format from tag `v1.3.10` to HEAD (Charter U risk).
- Cross-checked the scripture against an **independent second source**, the ShabadOS 4.8.7 database
  (`sggs-source` release `shabados-database-4.8.7`, sha256-verified), with
  `ios/tools/scripture_crosscheck.py`; inspected the source PDF where the two disagree.
- Ran the unit-test bundle on a physical iPhone; read the CI logs of the main runs.

## 3. Scripture integrity

### 3.1 Findings

| ID | Sev | Finding | Evidence | Status |
|---|---|---|---|---|
| S-1 | **P0** | **Aunkar dropped where the print has aunkar + hora on one letter** — 145 occurrences, 123 Angs (e.g. ਨਾਮੁੋ Ang 436 stored ਨਾਮੋ; ਗੁੋਪਾਲ Ang 1359 stored ਗੋਪਾਲ; ਸੁੋਹਾਗਣਿ, ਗੁੋਬਿੰਦ…) | The source PDF encodes that ligature as private-use glyph **U+F02B**, exactly 145 times on 123 pages; sggs-data `pipeline/sggs_pipeline.py` step 2 maps `U+F02B → ੋ` ("hora") only. ShabadOS has the same 145 aunkar+hora words on the same 123 Angs; our corpus has 0. Rendered PDF crops (Angs 436, 1359) show the aunkar. `reconcile.py` cannot see it: it proves the corpus against the same text layer. | **FAIL — NEEDS REFERENCE** (scholar confirmation per word, then a logged data correction; the order `ੋੁ` renders correctly in Sant Lipi, `ੁੋ` shows a dotted circle) |
| S-2 | P1 | **9 Sahaskriti words have a halant after a vowel** (an impossible sequence that draws a stray mark): ਇ੍ਸਨਾਨੁ (324, 1402×2), ਪੁ੍ਸਤਕ (1353), ਬੈ੍ਸਨਵਹ, ਅ੍ਸਚਰਜ (1359), ਉ੍ਸਤਤਿ (1386), ਅ੍ਸਤ (1388), ਭਿ੍ਗਤ (1403) | Corpus scan; ShabadOS reads ਇਸ੍ਨਾਨੁ, ਬੈਸ੍ਨਵਹ, ਅਸ੍ਚਰਜ; Sant Lipi render shows the stray halant | **FAIL — NEEDS REFERENCE** (same route as S-1) |
| S-3 | P3 | 21 other private-use glyphs (U+F045–F051) are stripped by the pipeline | each an isolated glyph in its own span; the one inspected is a border ornament (page 262) | NEEDS REFERENCE (likely layout, not text) |

Neither S-1 nor S-2 is caused by the app: the app shows the stored text faithfully. Both live in
`Algorythmos-AI/sggs-data` and need the prime directive's route — flag, scholar review, logged correction.

### 3.2 Charter S, automated against the second source

| Check | Result | Evidence |
|---|---|---|
| Bundled DB == pinned dataset | **PASS** | 60,658 / 60,658 lines byte-identical |
| Whole corpus vs ShabadOS | 97.46 % of lines identical after documented folds; the rest are edition/encoding differences plus S-1/S-2 | `scripture_crosscheck.py` |
| S1 Ang 1 Mool Mantar, Japji follows | **PASS** | first 4 lines identical incl. markers |
| S2 Ang 712 heading | **PASS** (text) | `ਟੋਡੀ ਮਹਲਾ ੫ ਘਰੁ ੨ ਚਉਪਦੇ` then `ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥` open comp 2845; ShabadOS adds a `॥` after the heading — an edition difference |
| S3 Ang 1256 refrain twice | **PASS** | `ਮਲਾਰ ਮਹਲਾ ੧ ॥` ×2 and `ਵੈਦ ਨ ਭੋਲੇ ਦਾਰੂ ਲਾਇ` ×3 in both sources; no dedupe code in reader/sheet/bani paths |
| S4 Ang 1400 storage | **PASS** | `ਜਲ੍ਯ੍ਯਨ` = U+0A1C U+0A32 U+0A4D U+0A2F U+0A4D U+0A2F U+0A28; source prints one subscript ya (yakash) |
| S4 saroop / Copy | **PASS** (unit) / NOT RUN (paste on device) | `SaroopTests` round-trips all 60,658 lines by scalar; every Copy/Share/Save/Spotlight/VoiceOver path uses the verbatim string (code read) |
| S5 Ang 1430 last lines; bounds | **PASS** | last 3 lines identical; Prev/Next bounds in `ReaderScreen` + `ReaderModelTests.testBounds` |
| S6 five Angs (seed 20261017: 63, 375, 575, 897, 1359) | PASS with known differences | 63: 40/40; 375: 48/49; 575: 32/35; 897: 54/56; 1359: 35/39 — every difference is S-1, S-2, a heading `॥`, a pairin-haha edition spelling, or the scholar-flagged `ਓ ੁਂ` row |
| S7 markers | **PASS** on 1, 1430; known heading `॥` / edition differences on 712, 1256, 1400 | strict compare keeps `॥ ੧ ਰਹਾਉ` |
| Manual Charter S on a device | **NOT RUN** for builds containing PR #36 | last signed 2026-10-14 (1.4.0) |

## 4. Engineering findings

| ID | Sev | Feature | Evidence | Fix | Regression test | Status |
|---|---|---|---|---|---|---|
| E-1 | **P0** (process) | CI | `ios.yml` piped `xcodebuild … \| tail` under `bash -e` (no pipefail); run 38936198527 on HEAD: unit 217 run / **2 failed**, UI 57 run / **4 failed**, check green; same on runs back to 2026-09-24 incl. 1.4.1/1.4.2 | `defaults.run.shell: bash` (pipefail), failing tests named from the result bundles, bundles always uploaded | the workflow itself | fixed, PR #37 |
| E-2 | P1 | Deep links | `sggs://shabad/3000000000` → `Int32(compId)` trap in `SQLiteCorpusReader` (and 17 other binds) | router range check; every integer bind `Int32(clamping:)` | `testOutOfRangeShabadLinkIsIgnored`, `testImpossibleCompositionIdReadsEmptyNotACrash` | fixed, PASS on device |
| E-3 | P1 | Saved verses | ladder deleted the store after any two failed opens (disk full included) | move files aside, never delete | `SavedStoreLadderTests.testSecondConsecutiveFailureRecreates` | fixed, PASS |
| E-4 | P2 | Nitnem | unreadable progress/plan file was overwritten by the next write | unreadable → read-only session; undecodable → moved aside | `NitnemTests.testCorruptFileIsEmptyNeverCrashes` | fixed, PASS |
| E-5 | P2 | Hukam widget | showed the unit's first verse, opened the seed's composition (can differ) | snapshot carries the shown verse's comp + line | `testHukamWidgetOpensTheVerseItShows` | fixed, PASS |
| E-6 | P2 | Spotlight | session-only saves indexed; un-index before a failed delete; never reconciled | skip degraded; un-index after save; reconcile at launch | not unit-observable → D7 | fixed; device NOT RUN |
| E-7 | P2 | Tests | `SaroopTests` searched Gurmukhi as `String` (grapheme clusters): vacuous checks, failing count | scalar comparison, exact counts | itself | fixed, PASS |
| E-8 | P1 | Release | archives since 1.4.1 use Xcode 27 / SDK 27; CI builds and tests with Xcode 26.3 / SDK 26.2 | run `app` on the archive's Xcode | — | open |
| E-9 | P1 | Release | CI tests the **personal** DB profile; releases ship **public** | add a public-profile `app` run | — | open |
| E-10 | P1 | Release | the CI "certified manifest" check compares a manifest the step before just rewrote; the archive never checks `db/sggs.sqlite` against `dataset.lock.json` (scripture text is still pinned by `CERTIFIED_SCRIPTURE_SHA`) | `git diff --exit-code` on the manifest; verify the dataset hash at archive time | — | open |
| E-11 | P1 | Versioning | HEAD carries PR #36 under 1.4.2, already shipped | bump with the platform (1.4.3) and re-sign Charter S | — | open |
| E-12 | P2 | Tests | DB-backed tests `XCTSkip` when the bundled DB is missing — a broken resource phase reads as skips | fail instead of skip in CI | — | open |
| E-13 | P3 | Misc | Forget location only in Solar mode; a late location fix can restore a forgotten one; Nitnem widget fraction lags; Hukam widget and share card draw verbatim (no saroop); share card adds a ੴ above every verse (G3 question); Constellation saves empty translit; Gurmukhi digits not accepted by Jump; `!` not covered by the crash gate; iPad has no Explore width cap | — | — | open, reported |

**Correct and covered (evidence from code + tests):** upgrade 1.3.10 → HEAD changes no persisted
format (SavedLine V1, every `@AppStorage` key/default, optional widget snapshot fields); launch
integrity cache keyed by DB sha, manifest sha, size, mtime and app version, failures never cached
(`LaunchCacheTests`); missing/corrupt DB fails closed with plain language; Clear reading history and
Forget location delete exactly what they say (`NitnemTests`, `RaagNowTimelineTests`, UI tests); no
network code (Airplane Mode safe by construction); Ang bounds, Jump validation and resume clamps.

## 5. Verification results

| Area | Status | Evidence |
|---|---|---|
| Build (Debug, device + test targets) | **PASS** | `xcodebuild build-for-testing`, Xcode 27.0, no warnings in changed files |
| Unit tests | **PASS** 220/220 | on iPhone 17 Pro Max iOS 26.6.2 (the first run failed `SaroopTests`, fixed as E-7) |
| Swift package tests (`make parity`) | **PASS** | 36 run, 5 skipped, 0 failed |
| Repo gates (`vendor-check`, `check-versions`, `test_ios_gates.py`) | **PASS** | |
| UI tests | **FAIL** (4) on CI main; this PR's run pending | names to be read from PR #37's new failing-tests step; no simulator runtime on the audit Mac |
| Scripture integrity | **FAIL** S-1, S-2 · otherwise PASS | §3 |
| Upgrade / migration | PASS by code diff; device run by the owner for 1.3.10 → 1.4.0 (2026-10-14 sign-off) | no format change since |
| Offline | PASS by code (no network APIs); device **NOT RUN** | D9 |
| Physical-device checklist D1–D12 | **NOT RUN** | `testflight-test-plan.md` §8 |
| CI/CD | **FAIL** → fixed in PR #37 | E-1 |

## 6. Remaining risks and next actions

1. Fix the UI failures PR #37's CI names; mark the PR ready; merge.
2. Raise S-1 and S-2 with the scholar; if confirmed, correct them in sggs-data through
   `sggs-rebuild-db` (logged editorial corrections, per the prime directive), then re-pin.
3. E-8 to E-12 (release pipeline), then bump to 1.4.3 with the platform.
4. Run §8 D1–D12 on a device and sign Charter S on the candidate.
5. Close G3 (icon v2, launch screen, yakash saroop).

## 7. Adversarial review of this PR (2026-10-17)

The fixes above were reviewed again, assuming they were wrong. What that found and changed:

| ID | Sev | Finding in the first version of this PR | Fix | Test |
|---|---|---|---|---|
| R-1 | P1 | With pipefail on, a failing unit step **skipped the UI tests**, so one run still hid part of the picture | UI tests run whenever the build succeeded; the job still fails | CI run on `5a791fc` |
| R-2 | P1 | The failing-tests step only reported; a missing or unreadable bundle passed silently | It is a second gate: no bundle, an unreadable bundle, or a reported failure fails the job | run locally against failing, passing, missing and corrupt bundles: exit 1 / 0 / 1 / 1 |
| R-3 | P1 | Store move-aside: two recoveries in one second collided, and the fallback **deleted** the store | unique folder per recovery; if any move fails nothing is replaced (in-memory session) | `testRepeatedRecoveriesNeverCollide`, `testAStoreThatCannotBeMovedIsNeverDestroyed`, `testRepeatedFailedLaunchesKeepTheOriginalBytes` |
| R-4 | P2 | -wal/-shm moved after the main file: an interruption could leave a stale WAL beside a new store | -wal, -shm first, main last, into one folder | `testWalAndShmMoveWithTheStore` |
| R-5 | P2 | A newer Nitnem file this build cannot decode was treated as corrupt and moved aside | its declared version is probed first: newer → read-only, left in place | `testNewerUndecodableFileIsLeftInPlace` |
| R-6 | P2 | A failed read of the saved store reconciled Spotlight to **empty** | only a successful read of a persistent store may replace the index (`SpotlightIndex.launchAction`) | `SpotlightAndClipboardTests` |

Other adversarial checks, all passing on the device: truncated and unreadable Nitnem files
(`testTruncatedFileIsKeptAside`, `testUnreadableFileIsNeverOverwritten`), same-second Nitnem
recoveries, malformed shabad links (`testShabadLinkComponentsAreStrict`), nonexistent composition
ids read empty, never a neighbour (`testNonexistentCompositionIdsReadEmpty`), verbatim scripture
through the pasteboard scalar for scalar for the Charter S Angs and all 234 subjoined-ya lines.
The 268-pair fixture is grounded independently: ShabadOS has 268 subjoined-ya marks on the same 78
Angs (on 233 lines; one line is split differently).

### The six historical failures

| # | Test | Cause | Resolution | Latest result |
|---|---|---|---|---|
| 1 | `SaroopTests/testEveryCorpusLineRoundTripsExactly` (unit) | test compared Gurmukhi as `String` (grapheme clusters) | scalar comparison, exact counts | PASS device; PASS CI (`ffcfa75`) |
| 2 | `NitnemJourneyTests/testMonthGridHonoursFirstWeekday` (unit) | **app**: `JourneyDay.dayNumber` read the day with `Calendar.current`, not the grid's calendar (UTC CI numbered Sydney's 15th as 14) | day number from the grid's own key; UTC+14 regression test | PASS device; PASS CI (`ffcfa75`) |
| 3 | `testNitnemOpensJapjiAndCompletes` (UI) | test: Japji steps by pauri, the control is "Next pauri", not "End" | stable `baniForward` id; test steps to the end | PASS device |
| 4 | `testPrivacyPolicyReachableFromMore` (UI) | test: lazy Lists longer than the screen | test scrolls; link matched by identifier | PASS device |
| 5 | `testRehrasVariantPersists` (UI) | **app**: Rehras variant ignored for an uncustomised Nitnem set | variant applied to the default set | PASS device |
| 6 | `testSwipeRunAfterJumpRendersContent` (UI) | **app (diagnostics)**: a jump parked during deceleration was logged as a lost-callback self-heal | heal only when a gesture end never arrived | PASS device |
