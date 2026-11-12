# G3 sensitivity review: the Hukamnama from Sri Harmandir Sahib (new English copy)

Status: **unreviewed**. This pack was prepared by an engineer so a reviewer can see every new
reader-facing English string of the Hukamnama push in one place. It is not a review. Nothing in it
is "reviewed" until a Granthi or Gurbani scholar signs the block at the end. The flag at the end
stays `REVIEWED: false` until then, and while it does, `ios/tests/test_ios_gates.py`
(`HukamnamaGates.test_ships_dark_until_the_copy_is_reviewed`) keeps the feature switched off in
Release builds (`HUKAMNAMA_ENABLED: "NO"` in `ios/App/project.yml`).

## 1. Purpose and scope

**What is in scope.** Every English string a reader sees, hears (VoiceOver) or receives (the push)
for the new feature **"Hukamnama · Sri Harmandir Sahib"**: the Hukamnama taken at Sri Harmandir
Sahib, Amritsar, located each morning from SGPC by our server and shown from the app's own corpus.
It is a separate feature from the existing **Hukam of the day**, whose copy is not touched.

| Work | Repository | Where |
|---|---|---|
| iOS push, sheet, card, Reminders section, NSE | `gurbani-soul-ios` | branch `feat/hukamnama-push` |
| Push payload (title, subtitle, body format) | `sggs-platform` | `services/hukamnama/` (sender; built separately) |
| Widget names, descriptions and states | `gurbani-soul-ios` | branch `feat/hukamnama-widget` (§3.6) |

**What is not in scope.** No Gurmukhi verse text is reviewed here. Every verse comes verbatim from
the pinned corpus, proven by `range_sha256` before it is shown, and is cited by Ang. One existing
Gurmukhi label is reused unchanged (the refrain marker on rows, copied byte-for-byte from
`ShabadSheet.swift`); it is marked *existing*.

**Rules** (the project's own, as in `docs/review/g3-constellation-v2-and-hukam-of-the-day.md` §1):
R1 verbatim and cited · R2 explanation labelled · R3 descriptive, never a ranking · R4 voice
("Reverent, plain, exact") · R5 endorser only as a credit · **R6 the Hukam of the day is never called
the Darbar Sahib Hukamnama — and, the other way round, this feature is never called the Hukam of the
day** · R7 no hand-typed Gurmukhi · R8 keywords name something the app contains.

**How to record a decision.** For each item: **OK**, **Change** (give the wording), **Remove**, or
**Ask**. "Leave it" is a complete answer.

## 2. Naming decisions to confirm first

| # | Decision | Pre-review note |
|---|---|---|
| N1 | The feature's name everywhere: **"Hukamnama · Sri Harmandir Sahib"** (card, push title, widget). The sheet adds ", Amritsar". | Owner decision 2026-11-09. Never "Darbar Sahib Hukamnama" in the app's own words? The plan uses "Sri Harmandir Sahib" consistently; please confirm, or give the form you prefer. |
| N2 | The date is always the **Amritsar** date, written **"Mon 9 Nov · Amritsar"** (en_GB style). | A reader in Vancouver receives it the previous local evening; the Amritsar label avoids "today" being wrong. |
| N3 | The source credit: **"Located by Ang from SGPC (sgpc.net). Text from Sri Guru Granth Sahib Ji."** | SGPC's text is used only to locate the shabad; the credit says so. Gate H-src (SGPC courtesy/permission letter) is separate. |
| N4 | The toggle's own label: **"Daily Hukamnama"** under the section header **"Hukamnama from Sri Harmandir Sahib"**. | |

## 3. Strings

`file:line` is `ios/App/…` on `feat/hukamnama-push`. Interpolations are shown as code.

### 3.1 Push notification (sent by the server; format fixed by the plan)

| # | String | Where | Pre-review note |
|---|---|---|---|
| P1 | Title: `Hukamnama · Sri Harmandir Sahib` | server payload `aps.alert.title`; fixture `Tests/Fixtures/hukamnama.apns` | |
| P2 | Subtitle: `Mon 9 Nov · Amritsar` (the Amritsar date) | `aps.alert.subtitle` | |
| P3 | Body: the opening verse (verbatim, from our corpus), a line break, then `Sri Guru Granth Sahib Ji · Ang N` | `aps.alert.body`; parsed by `Shared/HukamnamaShared.swift:59` | The verse is never truncated by the server; iOS may visually truncate a long verse on the lock screen. |

### 3.2 Nitnem home card (`Sources/Screens/HukamnamaCard.swift`)

| # | String | Where | Pre-review note |
|---|---|---|---|
| C1 | `Hukamnama · Sri Harmandir Sahib` | :11 | Sits directly above the existing "Hukam of the day" card; the two must read as different things. |
| C2 | `` `Mon 9 Nov · Amritsar` · Ang `N` `` (published) | :49–50 | Date and Ang only — the card shows no verse. |
| C3 | `` Not yet published · usually around `11:00 am` your time `` | :52 | The time is computed on the device from SGPC's 05:30 IST stamp; the soak will confirm a measured "usually by". |
| C4 | `Delayed today · it will appear here once it has been checked` | :54 | Shown when the server holds the day for the owner's check, or after 14:00 IST with nothing new. |

### 3.3 Hukamnama sheet (`Sources/Screens/HukamnamaSheet.swift`)

| # | String | Where | Pre-review note |
|---|---|---|---|
| S1 | Navigation title: `Hukamnama` | :32 | |
| S2 | Header: `Hukamnama · Sri Harmandir Sahib, Amritsar` | :26 | |
| S3 | Date line: `Mon 9 Nov · Amritsar` | :73 (via `AmritsarDate.label`) | |
| S4 | Citation: `Sri Guru Granth Sahib Ji · Ang N` | :77 | R1. |
| S5 | Footer: `Located by Ang from SGPC (sgpc.net). Text from Sri Guru Granth Sahib Ji.` | :27 | N3. |
| S6 | `` Open Ang `N` in Reader `` | :109 | *Existing pattern* (ShabadSheet). |
| S7 | `Not yet published` / `` `Mon 9 Nov · Amritsar`. Usually around `11:00 am` your time. `` | :47–48 | |
| S8 | `Delayed today` / `` `Mon 9 Nov · Amritsar`. It will appear here once it has been checked. `` | :51–52 | |
| S9 | `Update Gurbani Soul to read this Hukamnama` / `Sri Guru Granth Sahib Ji · Ang N` | :55–56 | Shown when the app's corpus cannot prove the server's range: the Ang only, never a line. |
| S10 | `Connect to the internet` / `The Hukamnama is found online each morning. Its text then comes from Sri Guru Granth Sahib Ji in this app.` | :59–60 | |
| S11 | `No Hukamnama for this date` / the date | :63 | |
| S12 | `Try again`, `Done` | :132, :34 | *Existing* words. |
| S13 | Row refrain marker (Gurmukhi + `· refrain`) | :93 | *Existing*, copied byte-for-byte from `ShabadSheet.swift`. |

### 3.4 Reminders section (`Sources/Screens/NitnemRemindersScreen.swift`)

| # | String | Where | Pre-review note |
|---|---|---|---|
| R-1 | Section header: `Hukamnama from Sri Harmandir Sahib` | :105 | |
| R-2 | Toggle: `Daily Hukamnama` | :106 | |
| R-3 | Mode: `As soon as it's published` | :107 | Default. |
| R-4 | Mode: `At a time I choose`, with a `Time` picker | :108, :149 | |
| R-5 | `` Usually around `11:00 am` your time `` | :145 | Under "As soon as it's published". |
| R-6 | `Notifications are turned off for Gurbani Soul in iOS Settings.` / `Open Settings` | :129, :131 | Mirrors the existing reminders row. |
| R-7 | `Couldn't turn on. Try again.` | `Sources/Data/HukamnamaPush.swift:262` | Permission granted but registration or the server failed; the toggle snaps back. |
| R-8 | Footer: `The Hukamnama is located each morning from SGPC and its text comes from Sri Guru Granth Sahib Ji in this app. When this is on, this device's notification token and your chosen time are sent to Algorythmos to deliver it. Turning it off deletes them.` | :109 | **Also G4** (privacy). The existing Nitnem footer below it still says "Everything stays on this device — no account, no network", which remains true of those reminders but now sits under a section that does use the network: please judge whether the two read clearly together. |
| R-9 | `Turn it on again on this iPhone.` (`iPad` on iPad) | `Sources/Data/HukamnamaPush.swift` (`turnOnAgain`) | A restored backup or a new phone: the setting came over, the notification permission did not. Only the toggle may prompt. |
| R-10 | `The Hukamnama couldn't be set up for this device. Turn it off and on again.` | `Sources/Data/HukamnamaPush.swift` (`refused`) | The server refused this device (4xx, not 429) on a routine re-registration. |
| R-11 | `If it isn't published by then, it arrives as soon as it is.` | under the `Time` picker | "At a time I choose" only. |
| R-12 | `` Today's Hukamnama was delivered at `1:54 PM`. `` (+ `Your new time starts tomorrow.` after a later change) | `HukamnamaDeliveryCopy` | From the server's delivery status (PUT answer), the reader's locale and zone. |
| R-13 | `Today's Hukamnama is already out — open it from the Nitnem page. Notifications start tomorrow.` | `HukamnamaDeliveryCopy` | Turned on after today's was sent. |
| R-14 | `` Your time has passed for today. Notifications start tomorrow at `2:13 PM`. `` | `HukamnamaDeliveryCopy` | |
| R-15 | `` Today's arrives at `2:13 PM`. `` / `Today's arrives as soon as it's published.` | `HukamnamaDeliveryCopy` | |
| R-16 | `Will update when you're online.` | `HukamnamaDeliveryCopy` | A mode/time change has not reached the server yet. |

### 3.5 VoiceOver

The card and the sheet speak the strings above; lines speak their verbatim Gurmukhi first (the
existing `LineRow` behaviour). No new VoiceOver-only text.

### 3.6 Widget (`Shared/HukamnamaWidgetViews.swift`, `Widgets/HukamnamaWidgetProvider.swift`)

Compiled only where `HUKAMNAMA_WIDGET` is set, so it is not in Release builds until this pack is
signed. The verse is the entry's opening verse (copied by the server from our corpus), shown whole
or not at all; a corpus-fingerprint mismatch shows the Ang and date only.

**Redesign (widget v2, 2026-11-12).** The faces read like the letter: name and Amritsar date at the
head, the verse, the citation at the foot (the sheet's order). The large size adds the opening
verse's transliteration and the shabad's ਰਹਾਉ couplet under a gold rule (`rahao_gurmukhi`, copied by
the server from our corpus; present only when the shabad has exactly one ਰਹਾਉ). Every layout steps
down whole (smaller type → no transliteration → no ਰਹਾਉ → no verse), never cuts a line, and binds a
closing ॥ to the word before it for display only (`VerseTypography`, as the reader does).

| # | String | Where | Pre-review note |
|---|---|---|---|
| W1 | Widget name and eyebrow: `Hukamnama · Sri Harmandir Sahib` | `HukamnamaWidgetView.name` | N1. The small widget splits it: `Hukamnama` over `Sri Harmandir Sahib`. |
| W2 | Description (widget gallery): `The Hukamnama taken at Sri Harmandir Sahib, Amritsar, located by Ang from SGPC. Text from Sri Guru Granth Sahib Ji (not the Hukam of the day).` | provider | R6, both ways round. |
| W3 | Date `Mon 9 Nov · Amritsar` under the name (medium, large); citation `Sri Guru Granth Sahib Ji · Ang N` at the foot | Home Screen families | The plan's comma form ("Ang 673 · Mon 9 Nov, Amritsar") was dropped for the app's own " · Amritsar" (N2), so every surface writes the date one way. **v2:** the small widget writes `Mon 9 Nov` alone under its citation, because `Sri Harmandir Sahib` above already names the place and the full form does not fit beside a whole verse. Please confirm. |
| W4 | `Not yet published today` | 05:30–14:00 IST with nothing new | The previous Hukamnama stays, dimmed, with its own date. |
| W5 | `Delayed today` | held for the owner's check, or after 14:00 IST | The card's word (C4), so the two agree. The plan's "Not available today. Open the app" was not used. |
| W6 | `Turn on the Hukamnama in Gurbani Soul.` | no Hukamnama has reached this device | |
| W7 | `Tap to read` (medium) / `Tap to read the shabad` (large) | beside the citation | *Existing* words (Hukam of the day widget). |
| W8 | Lock Screen: `Hukamnama · Ang 673` (rectangular, inline); `Ang` over the number (circular); `Hukamnama` with no Ang yet | accessory families | The rectangular widget adds the verse only when it fits whole, otherwise the date or the status. |
| W10 | `ਰਹਾਉ · refrain` under the ਰਹਾਉ couplet (large) | `HukamnamaWidgetView.rahaoLabel` | *Existing* words: the reader's and the sheet's label for a rahao line. |
| W11 | The opening verse's transliteration, italic, under it (large, when it fits whole) | `opening_translit` | The corpus's rule-based transliteration, as the Hukam of the day widget shows it. Not a translation. |
| W9 | Before 05:30 IST, yesterday's Hukamnama is shown with its date and no status line (it is still the current one) | | Never called today's. |

## 4. Sign-off

Reviewer name: ______________________ Role: ______________________ Date: ____________

Decisions recorded above, and any changes applied in commit: ____________

REVIEWED: false
