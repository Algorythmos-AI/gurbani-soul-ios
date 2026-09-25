# App Store screenshots

Masters live in `ios/AppStore/screenshots/<device>/` (git-ignored; multi-MB PNGs). The
`contact-sheet/` thumbnails are committed so the set can be reviewed in the repo.

| Set | Size | Source | Shots |
|---|---|---|---|
| `iphone-6.9` (mandatory) | 1320 × 2868 | iPhone 17 Pro Max simulator | Reader Ang 1 · Search "naam" · Hukam sheet · Raag Clock · Explore · Themes · Home Screen widgets |
| `iphone-6.5` (recommended) | 1284 × 2778 | derived from 6.9 (resample + centre crop) | same seven |
| `ipad-13` (mandatory) | 2064 × 2752 | iPad Pro 13" simulator | Reader · Search · Hukam · Clock · Themes |

How they were made (2026-09-18, `integration` after PRs #33/#34):

- **Public profile only.** The shots come from the Gurmukhi-only `public` DB profile (the
  only profile eligible for the store), never the personal build that bundles the English layer.
  The public DB + its manifest were swapped into a throwaway copy of the built `.app`; the app's
  own integrity check passed on it.
- Light mode, clean status bar (`simctl status_bar override --time 9:41`), fresh install so the
  default Soul Gold accent shows.
- Raag Clock pinned to 9:41 with the test-only `SGGS_CLOCK_NOW=581` launch env (otherwise the
  shot shows whatever pahar it is when captured).
- Deep links used to land screens: `sggs://ang/1`, `sggs://search?q=naam`.

- **Widgets shot** (`07-widgets`): both widgets (Hukam verse, medium; Raag now, medium) added to
  the Home Screen through the widget gallery. Captured on the iPhone 17 simulator (1206 × 2622)
  and resampled to 1320 × 2868 (+9%, aspect ratios match to 0.1%) because the widget gallery
  needs an interactive session on a device the tooling can drive. On a **signed** build the
  widget reads the App Group snapshot the app writes at launch; an unsigned simulator build
  works too, but only after the app has been launched once with the widget already placed.
  Other simulator apps (Wassup, the XCUITest runner) are visible on that Home Screen — retake
  on a clean device for the release candidate.

Not yet captured: iPad Reader in landscape.
Retake after any visual change before the release candidate (the listing doc asks for RC shots).

## How the set is made (scripted, reproducible)

```bash
make dataset && make ios-db-repair                       # the pinned DB + the personal pair the project builds with
bash ios/AppStore/capture_store_shots.sh ../store-shots  # RC app sources, public DB, fresh simulators
uv run --with pillow python3 ios/AppStore/compose_store_shots.py --captures ../store-shots
```

- `capture_store_shots.sh` builds the app at HEAD (its sources must equal the release tag), swaps the
  **public** DB into the *built* `.app` (never `ios/Resources`), and runs `testCaptureScreens` on a fresh
  iPhone 17 Pro Max and iPad Pro 13" (M5) simulator: light mode, 9:41 status bar, the Raag Clock pinned
  (`SGGS_CLOCK_NOW=581`, Debug-only), portrait on both (an XCUITest screenshot after rotating to landscape
  comes back rotated and not filling the frame). It also captures Ang 1400 with the
  traditional saroop on and off for the scholar's sensitivity review (`testCaptureSaroopReview`). The
  simulators are deleted afterwards.
- `compose_store_shots.py` frames each capture on warm paper with one English caption from
  `captions.json` (Source Serif 4, a bordered Soul Gold rule, ink text ≥ 4.5:1), at Apple's exact sizes
  (6.9": 1320 × 2868; 13": 2064 × 2752 or landscape 2752 × 2064), RGB without alpha. The app's pixels
  are only scaled; no Gurmukhi is ever typeset. Masters go to `screenshots/` (git-ignored), thumbnails
  to `contact-sheet/` (committed).
- `ios/tests/test_store_shots.py` keeps the captions short, English, true to the listing, and naming
  only screens the capture test produces.

## Retake before submission (required — the 2026-09-18 set is not submittable)

The current set predates Nitnem (the subtitle's headline feature), the widgets shot shows other apps
on the Home Screen, and there is no iPad landscape Reader. App Review compares screenshots with the
binary (2.3.3), so retake **all three sets** from the release candidate:

- [ ] Build: the exact RC commit, built with the required Xcode (26+), so the system UI in the shots
      matches what reviewers and users see.
- [ ] Data: the **public** DB, swapped into a *copy* of the built `.app` — never into `ios/Resources`.
- [ ] Device: a freshly created simulator per size class (clean Home Screen, no other apps, no
      XCUITest runner icon); status bar overridden to 9:41, full battery, full signal.
- [ ] Clock pinned with `SIMCTL_CHILD_SGGS_CLOCK_NOW=581` (Debug hook — never present in Release).
- [ ] Shots, in listing order: Reader Ang 1 · Search (Roman query) · Hukam · Raag Clock · **Nitnem**
      · **three widgets** (optional) · Themes or Lineage · iPad Reader (portrait).
- [ ] Nothing reads "beta", "TestFlight", "Under scholarly review" or shows a debug surface.
- [ ] Light mode throughout, or dark throughout — not mixed within a set.
- [ ] Record below: date, RC commit, build number, Xcode version.

| Retaken on | RC commit | Build | Xcode |
|---|---|---|---|
| 2026-09-26 | `e7a0d8a` (tag v1.3.10; captured from `702ce91`, whose app sources are identical to the tag) | 1.3.10 (1) | 26.5 (iOS 26.5 simulators) |
