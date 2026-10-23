# G3 sensitivity review: Constellation v2 and Hukam of the day (new English copy)

Status: **unreviewed**. This pack was prepared by an engineer (with an AI assistant) so a reviewer can
see every new reader-facing English string in one place. It is not a review. Nothing in it is
"reviewed" until a Granthi or Gurbani scholar signs the block at the end. The flag at the end stays
`REVIEWED: false` until then.

## 1. Purpose and how to review

**What is in scope.** Every English string that a reader sees, hears (VoiceOver, Siri) or receives
(a shared image), and that was added or changed by:

| Work | Repository | Commits |
|---|---|---|
| Constellation v2, web and API | `sggs-platform` | `1cc77d4`, `ea8c9ec`, `f4dfd73`, `a7d27d0` (release `f5aa844`, 1.4.8) |
| Constellation v2, iPhone | `gurbani-soul-ios` | `c430e96`, `bdc5018`, `8223e44` |
| Hukam of the day | `gurbani-soul-ios` | `3b7a52d`, `f112cab`, `29a2e70` and the commit adding this pack (PR #55); items marked *WT* were drafted against the working tree before those commits |

**What is not in scope.** No Gurmukhi verse text is reviewed here. Every verse these surfaces show
comes verbatim from the pinned corpus and is cited by Ang. This pack covers only the words around the
verses: labels, captions, the "why shown" notes, the share card, the widget and Siri copy, and the
privacy and store text. A few existing strings (not new) are listed where the new work puts them in
a new place. They are marked *existing*.

**Line numbers.** `file:line` is the file at the commit named above. For `gurbani-soul-ios` files that
also have uncommitted edits, the line is the working tree, with the `HEAD` line in brackets where it
differs. Strings are copied from the code exactly, including interpolation such as `\(name)` (Swift)
or `${T(st.theme)}` (TypeScript). `T(…)` and `ConceptName.display(…)` turn a theme key into a title
(for example `naam` becomes `Naam` and `ik_onkar` becomes `Ik Onkar`).

**The rules each item is checked against** (the project's own; nothing is added from outside):

- **R1 Verbatim and cited.** Every quotation carries its Ang, written "Sri Guru Granth Sahib Ji · Ang N".
  "Gurbani Soul" names the app, never the text. (Brand book §1 and §9; `docs/engineering/brand.md`;
  reverence checklist "How it is shown and cited")
- **R2 Explanation is labelled.** Explanation, summary or interpretation is always labelled as such and
  kept apart from the quotation. (Brand book §7; Answer Protocol rule 3; reverence checklist)
- **R3 Descriptive, never a ranking of scripture.** The app never interprets. (`webapp/sggs/insights.py`
  notes; `docs/website/constellation.md`; Answer Protocol rule 3: "the app never interprets")
- **R4 Voice.** "Reverent, plain, exact. Short sentences. Say what a thing is. Never playful about the
  text, never promotional inside the reader, never 'AI' as a selling point." (Brand book §7)
- **R5 Endorser.** "Built by Algorythmos" is a credit line only, on the About screen and the store
  listing. (Brand book §1)
- **R6 Not the Darbar Sahib Hukamnama.** "This is not the Darbar Sahib Hukamnama and the copy that
  shows it must never say so." (`ios/Packages/GurbaniSearchKit/Sources/GurbaniSearchKit/HukamOfTheDay.swift:10`).
  An online daily Hukamnama is out of scope (`docs/nitnem/spec.md:82`).
- **R7 No hand-typed Gurmukhi.** "No Gurmukhi was typed by hand anywhere in the diff." (Reverence
  checklist, pre-PR list.) Names and titles may appear.
- **R8 Every keyword names something the app contains.** (`docs/ios/app-store-listing.md:45-47`)

**How to record a decision.** For each item, write one of:

- **OK**: acceptable as written.
- **Change**: give the wording you want. An engineer applies it in a commit and records the commit id
  in the sign-off.
- **Remove**: the string, or the feature it describes, should not ship.
- **Ask**: you need more context. Say what.

"Leave it" is a complete answer. You do not need to fill in the "Pre-review note" column. It is the
engineer's concern, given so you can agree or disagree with it.

---

## 2. Strings by surface

### 2.1 Web: Constellation page (`/constellation`)

Files: `frontend/src/pages/constellation.astro` (`ea8c9ec`), `frontend/src/scripts/constellation.ts`
(`ea8c9ec`), `frontend/src/scripts/themegroups.ts` (`ea8c9ec`, text moved from `themes.ts`), all in `sggs-platform`.

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| W-01 | `Pick one of the 54 themes and see which other themes its verses carry. Near stars appear together more often than chance (PPMI); thicker lines share more shabads (Jaccard). <b>Tap a star</b> to read the verses two themes share, or the centre for the theme itself.` | `constellation.astro:7`, the hint above the chart | Is it right to say a verse "carries" a theme? Is "more often than chance" acceptable wording about where words fall in Gurbani? | "Carry" is used throughout (see Q3). "Chance" is the statistical meaning, but a reader could take it to mean the text was arranged by chance. "PPMI" and "Jaccard" are jargon for a reader (R4, "plain-spoken"). |
| W-02 | `A verse carries a theme when it contains one of that theme's verified Gurmukhi words. A way to explore, never a ranking of scripture.` | `constellation.astro:7`, the hint's note | Is this definition clear and accurate? | This is the key disclaimer. "Verified" means that the word was checked to appear in the verse. It does not mean that the meaning was checked (see Q2 and W-35). |
| W-03 | `Focus` · `See the whole sky` | `constellation.astro:18-19`, the view switch | OK as names for the two views? | none |
| W-04 | `Which companions` (group label) · `Most shared` · `Most distinctive` | `constellation.astro:25-27`, the ranking switch | Does ordering *themes* by "Most shared" / "Most distinctive" read as ranking scripture? | These order theme names, not verses. `docs/website/constellation.md:14` says "nothing is ranked" while line 30 says "Two rankings" (see D-02). |
| W-05 | `Lens` | `constellation.astro:30`, the filter menu | OK? | none |
| W-06 | `Voice` · aria `Filter by voice` · `All voices` | `constellation.astro:32`, `constellation.ts:303` | Is "voice" acceptable for the Gurus, Bhagats and Bhatts whose bani is in the Granth? | "Voice" is the project's existing term (Lineage: "30 voices"). Raised because it is now a filter label. |
| W-07 | Voice names with " Ji" removed: `a.replace(' Ji', '')`, which shows for example `Guru Nanak Dev (M1)`, `Bhagat Kabir`, `Sheikh Farid` | `constellation.ts:303` (picker), `:66` (lens words), `:228` (theme card), `:244` (pair eyebrow) | Is dropping "Ji" from the Gurus' and Bhagats' names acceptable, even in short labels? | Concern (R4, reverence). The stored names carry "Ji" (for example `Guru Nanak Dev Ji (M1)`). This was already done on the v1 page and on iOS Insights. v2 spreads it to more places. |
| W-08 | `Raag` · `All raags` · lens word `Raag ${…}` | `constellation.astro:33`, `constellation.ts:304`, `:67` | OK? | none |
| W-09 | `This hour` · `raags attributed to the current watch (claims, never facts)` | `constellation.astro:34`, lens option | Is "claims, never facts" a respectful way to describe the traditional raag-time attributions? | This matches the Raag Clock's sourcing. "Never facts" might read as dismissive of tradition. A possible alternative: "as attributed by the sources the Raag Clock cites". |
| W-10 | `Refrains only` · `Rahao lines` | `constellation.astro:35` | Is "refrain" an acceptable English gloss for Rahao? | The project already uses "refrain" (the reverence checklist and the reader's margin rule). |
| W-11 | `Brightest stars` · `verses carrying 5 or more themes` | `constellation.astro:36` | Is "brightest" acceptable for verses that match five or more theme words? | **Concern (R3).** "Brightest" is a value word for a subset of verses and can read as "the best verses". A neutral alternative: "Many themes (5 or more)". |
| W-12 | Lens summary words: `this hour` · `refrains` · `5+ themes` · `Angs ${a}–${b}` | `constellation.ts:68-71`, shown after the caption and on "Lens" | OK? | none |
| W-13 | `${nf(d.total)} verses carry ${name}${lw ? ' (' + lw + ')' : ''} · ${nf(d.shared)} also carry another theme · ${nf(d.solo)} carry ${name} alone` | `constellation.ts:346`, the caption under the title | Is "carry ${name} alone" clear? | "Alone" means alone among the 54 tagged themes, not that the verse is about nothing else. A possible alternative: "carry no other tagged theme". |
| W-14 | `No verses of ${name}${lw ? ' for ' + lw : ''} — try a different lens.` | `constellation.ts:347` | OK? | none |
| W-15 | ` · no raag is attributed to this watch` | `constellation.ts:348` | OK? | none |
| W-16 | `These verses carry no other theme.` | `constellation.ts:351` | OK? | none |
| W-17 | `Could not load this theme.` · `Could not load concept data.` · `Concept data is not available in this DB build.` | `constellation.ts:354`, `:380`, `:291` | OK? | "DB build" is engineering language a reader may see (R4). The last string was already there. |
| W-18 | `${nf(d.solo)} alone` | `constellation.ts:107`, the halo label round the centre star | OK? | See W-13. |
| W-19 | aria `${T(st.theme)} and its ${cs.length} most shared/most distinctive companion themes. The same data is listed after the chart.` | `constellation.ts:86`, spoken by screen readers | OK? | none |
| W-20 | aria `${T(p.c.co)}: ${nf(p.c.n)} verses carry both ${T(st.theme)} and ${T(p.c.co)}; together in ${nf(p.c.shabad_count)} shabads` | `constellation.ts:112` | OK? | none |
| W-21 | Star label `${T(p.c.co)} · ${nf(p.c.n)}` · centre aria `${T(st.theme)}: about this theme` | `constellation.ts:120`, `:125` | OK? | none |
| W-22 | List twin: `${nf(c.n)} verses shared · together in ${nf(c.shabad_count)} shabads · PPMI ${c.ppmi.toFixed(2)}` | `constellation.ts:134` | OK? | Jargon ("PPMI"); see W-01. |
| W-23 | List twin: `${T(st.theme)} alone` · `${nf(d.solo)} verses carry no other theme` | `constellation.ts:135` | OK? | See W-13. |
| W-24 | `Where ${T(st.theme)} falls in reading order` · `(verses per 100 Angs; tap a bin to look only there)` | `constellation.ts:144`, the Ang strip | OK? | Uses "Ang" correctly. |
| W-25 | aria `Angs ${a} to ${b}: ${nf(n)} verses` · axis `Ang 1` … `1430` | `constellation.ts:148-149` | OK? | none |
| W-26 | `All ${skyData.nodes.length} themes · lines join themes that share shabads more than chance would give (PPMI 0.7 or more) · tap a star to focus it` | `constellation.ts:331`, the Sky caption | See W-01 on "chance". | Same as W-01. |
| W-27 | aria `All ${nodes.length} themes. Lines join themes that share shabads more than chance (PPMI 0.7 or more). The same themes are listed by group after the chart.` · node aria `${T(n.concept)}: ${nf(n.n)} verses — focus this theme` | `constellation.ts:183`, `:192` | OK? | none |
| W-28 | Group titles, now the colour legend and the picker's sections: `The Divine Reality` · `The Human Condition & Illusions` · `The Five Vices` · `The Path & Praxis` · `Virtues & Divine Attributes` · `Spiritual States` (and `More themes` for any leftover) | `themegroups.ts:9-20`, shown by `constellation.ts:207`, `:297`, `:300` | Are these six groupings, and the placement of each theme, acceptable? Each group now has a colour on every star. | *Existing* text, moved from `themes.ts`. New: `kaal` moved from the Divine Reality to the Human Condition, and the groups are now colour-coded on the chart. Group captions (for example "The panj chor that rob the soul") are shown on `/themes` only. |
| W-29 | Picker option `${T(k)} · ${nf(count[k])} verses` | `constellation.ts:296`, `:300` | OK? | none |
| W-30 | Theme card sub-title: `${g.title} · ${nf(c.n_verses)} verses in ${nf(c.n_shabads)} shabads · ${nf(c.n_rahao)} refrains` | `constellation.ts:223` | OK? | none |
| W-31 | Theme card body: `${esc(c.description)}`, the theme's description from the database (`concepts.description`, owned by sggs-data). All 54 are listed in Appendix A. | `constellation.ts:225` | **Are these 54 descriptions acceptable to show to readers? Should they be labelled as explanation?** | **Concern (R2, R1).** They are explanation, and they are shown with no "explanation" label. Some quote Gurmukhi phrases without an Ang. Some include engineering notes ("1406 hits", "as a single token in the lexicon"). One phrase (`ਮਾਰਗਿ ਚਲਾਏ`, theme `marag_panth`) is not found as a contiguous string in the pinned database. They are new to readers: v1 did not show them. See Q6. |
| W-32 | `The Gurmukhi words that tag it` | `constellation.ts:226`, above the theme's Gurmukhi terms | OK? | The terms are shown verbatim, in ink. |
| W-33 | `Concentrates in` · row `Raag ${…}` · `${x.lift.toFixed(2)}× the Granth's rate — ${rate(x.entity_rate)} of its tagged verses against ${rate(x.corpus_rate)} overall (${nf(x.n_tagged)} verses)` | `constellation.ts:220`, `:227` | Is it acceptable to state that a theme "concentrates" in a raag? Is "the Granth" acceptable shorthand here? | These are descriptive rates. "The Granth" is short for Sri Guru Granth Sahib Ji. The app already uses it ("The full Granth, verbatim"). |
| W-34 | `Voiced most by` · row as in W-33 with the voice's name (" Ji" removed) | `constellation.ts:228` | **Does "Voiced most by" read as ranking the Gurus and Bhagats?** | **Concern (R3).** It lists up to five voices by lift, highest first. A neutral alternative: "More frequent than the Granth's rate in the bani of". See W-07 for the honorific. |
| W-35 | `Rates only where the sample is large enough to be reliable. Descriptive, never a ranking.` | `constellation.ts:229` | OK? | none |
| W-36 | `See all ${nf(c.n_verses)} verses →` | `constellation.ts:230` | OK? | none |
| W-37 | Pair title: `${T(st.theme)} ✦ ${T(st.pair)}` or `${T(st.theme)} alone`, then ` · ${nf(d.total)} verses` and the lens words | `constellation.ts:239`, `:253` | Is "✦" between two theme names acceptable? | Decorative. It is not next to Gurmukhi. |
| W-38 | `Shown because it carries a word of each theme (marked) — a verified word match, not an interpretation.` | `constellation.ts:242`, under every pair list | **Is "a verified word match" clear? Does "verified" suggest more than it means?** | **Concern (R3).** See Q2. Broad themes match ordinary words. For example `ik_onkar` is matched by ਏਕ, ਏਕੁ, ਇਕੁ and ਇਕਿ (1,647 verses). So "Ik Onkar ✦ X" may list verses where the word means "one" or "some", not Ik Onkar. Also, "it" refers to each verse, but the heading above counts many verses. |
| W-39 | `Shown because it carries a word of ${T(st.theme)} and no other theme's word.` | `constellation.ts:241`, the "alone" list | OK? | See W-13. |
| W-40 | Matched words wrapped in `<mark>` inside the Gurmukhi verse | `constellation.ts:211-212`, `:246` | **Is highlighting the matched word inside the verse acceptable?** | The text is unchanged and the highlight covers whole words only (the reverence walker checks this). But it does decorate scripture. iOS deliberately lists the words under the verse and leaves the verse plain. See Q7. |
| W-41 | Pair eyebrow `Raag ${…} · ${author without " Ji"} · Ang ${sh.ang}` · badge `Rahao` · link `Ang ${v.ang} · open in the Reader` | `constellation.ts:244`, `:247` | OK? | See W-07. |
| W-42 | `Together in ${nf(d.bond.shabad_count)} shabads across the Granth · PPMI ${…} · Jaccard ${…}` | `constellation.ts:252` | OK? | Jargon; see W-01. |
| W-43 | `Show ${Math.min(PAGE, d.total - shown)} more (${nf(shown)} of ${nf(d.total)})` · `Loading…` | `constellation.ts:250`, `:216` | OK? | none |

**API notes** (`webapp/sggs/insights.py`, `ea8c9ec`). These are returned in the JSON `note` field.
They are read by developers and by anyone who opens the public API console, not on the page.

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| A-01 | `total = solo + shared: a verse is "shared" when it also carries another theme. A companion's n counts the verses carrying both themes, so companion counts overlap by design (a verse with three themes counts under two companions). PPMI and Jaccard are the corpus bond between the two themes over shabads. Descriptive structure, never a ranking of scripture` | `insights.py:303-307`, `/api/analytics/constellation` | OK? | none |
| A-02 | `every theme with its verse count; edges are theme pairs whose PPMI (co-occurrence within shabads, base-rate controlled) clears min_ppmi. Descriptive only` | `insights.py:328-329`, `/api/analytics/sky` | OK? | none |
| A-03 | `each verse carries one verified Gurmukhi word of each theme (terms, in the order concept, with; alone=1: the one word, and no other theme): a word match, not an interpretation. Text is verbatim` | `insights.py:370-372`, `/api/analytics/pair` | OK? | See W-38. |
| A-04 | `raags and authors where this theme concentrates: lift = the entity's rate over the corpus rate, shown only where the sample is reliable. Descriptive, never a ranking` | `insights.py:403-404`, `/api/analytics/theme` | OK? | Calls a Guru or Bhagat an "entity". This is fine in an API, and it is never shown in the UI. |
| A-05 | `unknown theme` (404) · `pair requires a concept and either a different theme (with) or alone=1` · `theme requires a concept` | `insights.py:385`, `:341`, `:381` | OK? | none |

**Public documentation** (`sggs-platform`, published on the docs site and GitHub).

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| D-01 | `A verse carries a theme when it contains one of that theme's verified Gurmukhi words … It is a word match, not an interpretation, and the pair view says so under every list. Some themes are broad by construction (Ik Onkar matches the common forms of "one") and some are sparse (Akal has 15 verses).` | `docs/website/constellation.md:18-23` | Is it acceptable to keep the theme name "Ik Onkar" for a tag that matches the common forms of "one"? | This states the limitation honestly, but only in engineering docs. Readers of the page and the share card do not see it. See Q2. |
| D-02 | `Nothing is computed by a model and nothing is ranked.` vs `**Two rankings.**` | `docs/website/constellation.md:13-14` vs `:30` | — | **Concern (exactness).** The two lines contradict each other. A suggested fix: "Nothing is computed by a model, and no verse is ranked; companion *themes* can be ordered two ways." |
| D-03 | `The Five Vices form a visibly tight cluster with no label saying so.` | `docs/website/constellation.md:81-82` | OK? | none |
| D-04 | `Constellation v2: the Granth, seen by idea.` | `CHANGELOG.md:8` (`f5aa844`) | Is this phrase acceptable as a public release title? | Slightly promotional (R4), but it is not inside the reader. |

### 2.2 iOS: Constellation (Focus, Sky, theme card, Siri)

Files in `gurbani-soul-ios`: `ios/App/Sources/Screens/ConstellationScreen.swift` (`bdc5018`, `8223e44`),
`ConstellationSkyScreen.swift` and `ThemeCardSheet.swift` (new in `8223e44`),
`ios/App/Sources/Components/ThemeGroups.swift` (`bdc5018`, text moved from `ThemesScreen.swift`),
`ios/App/Sources/Intents/AppIntents.swift` (`8223e44`).

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| I-01 | `Most shared` · `Most distinctive` · picker label `Which companions` | `ConstellationScreen.swift:23`, `:90` | As W-04. | As W-04. |
| I-02 | `See the whole sky` · `Map` / `List` · aria `View as map` / `View as list` | `ConstellationScreen.swift:52`, `:55`, `:57` | OK? | none |
| I-03 | Picker sections: the six group titles (as W-28) · `More Themes` · option `\(ConceptName.display(c.concept)) · \(c.nLines.formatted()) verses` · aria `Theme: \(ConceptName.display(concept))`, hint `Choose the theme at the centre` | `ConstellationScreen.swift:103-126`; titles in `ThemeGroups.swift:28-39` | As W-28. | Titles are *existing* text from `ThemesScreen`. "More Themes" is capitalised differently from the web's "More themes". |
| I-04 | Lens: `Voice` · `All voices` · voice names `a.name.replacingOccurrences(of: " Ji", with: "")` | `ConstellationScreen.swift:132-136` | As W-06 and W-07. | **Concern**, as W-07. On iOS this is new in v2 for the Constellation (Insights already did it). |
| I-05 | Lens: `Raag` · `All raags` | `ConstellationScreen.swift:140-142` | OK? | none |
| I-06 | Lens: section `Time of day` · `This hour` | `ConstellationScreen.swift:149-150` | OK? | The web adds "(claims, never facts)" (W-09). iOS has no such note here, but the alert below gives the context. |
| I-07 | Alert: `No raag is attributed to this watch` · `The timing claims name no raag for the current pahar, so the lens stays off.` · `OK` | `ConstellationScreen.swift:66-69` | Are "watch" and "pahar" used correctly? | none |
| I-08 | `Refrains only (Rahao)` | `ConstellationScreen.swift:156` | As W-10. | none |
| I-09 | `Brightest stars (5+ themes)` | `ConstellationScreen.swift:157` | As W-11. | **Concern**, as W-11. |
| I-10 | `Clear the lens` · `Lens on` / `Lens` · aria `Lens: \(lensWords)` · lens words `Raag …`, `this hour`, `refrains`, `5+ themes` | `ConstellationScreen.swift:161-180` | OK? | none |
| I-11 | `No verses under this lens` · `Try a different voice, raag or filter.` · `These verses carry no other theme` | `ConstellationScreen.swift:200-203` | OK? | none |
| I-12 | `Nearer stars appear together more often than chance (PPMI); thicker lines share more shabads; larger stars share more verses.` | `ConstellationScreen.swift:212`, under the map | As W-01. | As W-01. |
| I-13 | Caption: `\(f.total.formatted()) verses carry \(name)\(lw.isEmpty ? "" : " (\(lw))")` · `\(f.shared.formatted()) also carry another theme · \(f.solo.formatted()) carry \(name) alone` | `ConstellationScreen.swift:222`, `:225` | As W-13. | As W-13. |
| I-14 | Halo: `\(solo.formatted()) alone` · aria `\(solo) verses carry \(ConceptName.display(center)) alone`, hint `Opens them` | `ConstellationScreen.swift:319`, `:325-326` | OK? | none |
| I-15 | Star label `\(ConceptName.display(co.co)) · \(co.n.formatted())` · aria `…: \(co.n) verses carry both \(…) and \(…); together in \(co.shabadCount) shabads` · centre aria `\(ConceptName.display(center)): about this theme` | `ConstellationScreen.swift:333`, `:343`, `:356` | OK? | none |
| I-16 | List twin: `\(co.n.formatted()) verses shared · together in \(co.shabadCount.formatted()) shabads · PPMI \(…)` · `\(ConceptName.display(concept)) alone` · `\(focus.solo.formatted()) verses carry no other theme` | `ConstellationScreen.swift:377`, `:383-384` | OK? | Jargon ("PPMI"). |
| I-17 | Pair sheet title: `\(a) ✦ \(ConceptName.display($0))` or `\(a) alone` | `ConstellationScreen.swift:433` | As W-37. | This title is also printed on the share card (S-03). |
| I-18 | Pair sheet head: `\(total.formatted()) verses` · `Together in \(bond.shabadCount.formatted()) shabads across the Granth` | `ConstellationScreen.swift:442-444` | OK? | none |
| I-19 | `Shown because it carries a word of each theme — a verified word match, not an interpretation.` | `ConstellationScreen.swift:449` | As W-38. | **Concern**, as W-38. |
| I-20 | `Shown because it carries a word of this theme and no other theme's word.` | `ConstellationScreen.swift:448` | As W-39. | none |
| I-21 | Verse meta: `(v.isRahao ? "ਰਹਾਉ · refrain · " : "") + "Ang \(v.ang)"` | `ConstellationScreen.swift:461` | Is "ਰਹਾਉ · refrain" acceptable as a marker beside the Ang? | The word ਰਹਾਉ is typed by hand in the source (R7). It is a label, not verse text, but the checklist asks for none. The web uses the English badge "Rahao" instead (W-41). |
| I-22 | `Carries ` + the matched Gurmukhi words joined by ` · ` (aria `Matched words: …`) | `ConstellationScreen.swift:465-467`, under each verse | Is "Carries ਨਾਮੁ · ਹਉਮੈ" (for example) clear? | The words are shown in muted ink under the verse, and the verse itself is left plain. |
| I-23 | Pair eyebrow: `Raag …` · voice name with " Ji" removed · `Ang \(sh.ang)` | `ConstellationScreen.swift:499-501` | As W-07. | As W-07. |
| I-24 | `Loading…` / `Show \(min(50, total - loaded)) more (\(loaded.formatted()) of \(total.formatted()))` · `No verses` | `ConstellationScreen.swift:480`, `:438` | OK? | none |
| I-25 | Sky: title `The whole sky` · `All \(sky.nodes.count) themes. Lines join themes that share shabads more than chance (PPMI 0.7 or more). Tap a star to focus it.` | `ConstellationSkyScreen.swift:44`, `:60` | As W-26. | none |
| I-26 | Sky: aria `\(…): \(node.n) verses`, hint `Focus this theme` · legend aria `Theme groups: …` · list row `\(n.formatted()) verses` · `More Themes` · `Something went wrong` / `Try again` | `ConstellationSkyScreen.swift:96-97`, `:141`, `:157`, `:170-174`, `:37-38` | OK? | none |
| I-27 | Theme card: header group title · `\(card.nVerses.formatted()) verses in \(card.nShabads.formatted()) shabads · \(card.nRahao.formatted()) refrains` | `ThemeCardSheet.swift:24`, `:27` | OK? | none |
| I-28 | Theme card: `Text(card.description)`, the same 54 database descriptions as W-31 (Appendix A) | `ThemeCardSheet.swift:29-30` | As W-31. | **Concern**, as W-31. It is shown with no "explanation" label. |
| I-29 | `The Gurmukhi words that tag it` | `ThemeCardSheet.swift:36` | OK? | none |
| I-30 | `Concentrates in` · row name `"Raag " + …` · `\(x.lift…)×` · `\(pct(x.entityRate)) of its tagged verses, against \(pct(x.corpusRate)) across the Granth · \(x.nTagged.formatted()) verses` | `ThemeCardSheet.swift:40`, `:66`, `:75`, `:78` | As W-33. | none |
| I-31 | `Voiced most by` (names with " Ji" removed) | `ThemeCardSheet.swift:45-46` | As W-34. | **Concern**, as W-34 and W-07. |
| I-32 | `See all \(card.nVerses.formatted()) verses` · footer `A verse carries this theme when it contains one of these words. Rates appear only where the sample is large enough to be reliable.` · `Unknown theme` · `Done` | `ThemeCardSheet.swift:50`, `:54`, `:17`, `:60` | OK? | Unlike the web (W-35), the footer has no "Descriptive, never a ranking" line. Parity gap. |
| I-33 | Ang strip: `Where \(ConceptName.display(concept)) falls in reading order` · aria `Angs \(…) to \(…): \(n) verses` · `Ang 1` … `1430` | `ThemeCardSheet.swift:123`, `:142`, `:147` | OK? | none |
| I-34 | Siri / Shortcuts: title `Show the constellation` · description `See which themes a theme's verses also carry, matched by each theme's Gurmukhi words.` (changed after pre-review; was "built from the Granth's verified theme words") · parameter `Theme`, `A theme such as Naam, Haumai or Seva.` | `AppIntents.swift:105-109` (HEAD `:91-95`) | Is "the Granth's verified theme words" accurate? | **Concern (exactness).** The tags are the project's word lists (sggs-data `concepts`), not something the Granth itself defines. A possible alternative: "built from verified theme words in Sri Guru Granth Sahib Ji". |
| I-35 | Siri phrases: `Show the constellation in \(.applicationName)` · `Explore themes in \(.applicationName)` · short title `Constellation` | `AppIntents.swift:142-144` (HEAD `:125-127`) | OK? | none |
| I-36 | Explore card caption: `A theme's verses clustered by co-theme` | `ios/App/Sources/Screens/ExploreScreen.swift:36` (*existing*, not changed by v2) | — | Out of date: v2 no longer clusters. A possible alternative: "Which themes a theme's verses also carry". Listed so it is not missed. |

### 2.3 Share card (verse image)

File: `ios/App/Sources/Components/VerseCard.swift` (`8223e44`). The card is rendered as an image and
leaves the app. The Constellation lines appear only when a verse is shared from the pair sheet
(`LineRow` `shareContext: title`, `ConstellationScreen.swift:462`).

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| S-01 | `ੴ` (the mark, above the verse, in the accent colour) | `VerseCard.swift:20` (*existing*) | **Is it right to set ੴ above every shared verse, including verses that do not open a composition?** | *Existing*, not new in v2. It is still open as a G3 question in `docs/ios/production-readiness-audit.md:80` (E-13). Included because every Constellation share carries it. See Q8. |
| S-02 | `Sri Guru Granth Sahib Ji · Ang \(String(ang))` | `VerseCard.swift:35` (*existing*) | — | This matches R1. Included for context. |
| S-03 | `Constellation · \(context) (a verified word match)`, for example `Constellation · Naam ✦ Haumai (a verified word match)` or `Constellation · Naam alone (a verified word match)` | `VerseCard.swift:41` | **Is it acceptable for a shared image of a verse to carry this line, under the citation?** | **Concern.** This line goes outside the app, without the explanation the app gives. A recipient may read "Naam ✦ Haumai (a verified word match)" as a verified statement about the verse's meaning. "Naam alone" on a card is unclear out of context. See Q2. |
| S-04 | `Gurbani Soul · Built by Algorythmos` | `VerseCard.swift:43` | Should a scripture share card carry the app's name and endorser? | **Concern (R5, R4).** The brand book puts "Built by Algorythmos" on the About screen and the store listing only (§1). Its share-card spec (§6) is "paper surface, ink Gurmukhi, gold rule, full citation". This line appears only on Constellation shares, which is inconsistent. This is a brand-owner question as much as a scholar's. |

### 2.4 Hukam of the day: widget, in-app and Siri

Files in `gurbani-soul-ios`: `ios/App/Widgets/SGGSWidgets.swift` (`3b7a52d`, then *WT*),
`ios/App/Sources/Intents/AppIntents.swift` (*existing* at HEAD, changed in *WT*),
`ios/App/Sources/Screens/NitnemScreen.swift` (*WT*), `ios/App/Sources/Components/ShabadSheet.swift` (*WT*).

**What the feature does** (from the code, so the reviewer can judge the words). The app takes the
reader's local calendar date and turns it into a number. A fixed formula (SplitMix64) uses that
number to pick one verse line from all the non-header lines of the Granth, each line equally likely.
The app then expands that line to its whole unit (the shabad, or the salok and pauri group), using
the same rule as the in-app Hukam draw. Every phone on the same date gets the same unit. A new one
starts at local midnight. The widget shows the unit's opening verse with its Ang. Tapping it opens
the whole unit. **It is not the Hukamnama from Sri Harmandir Sahib, and it is not taken the
traditional way, by opening the Granth at the top of the left-hand Ang.** It is a pick made by
arithmetic from the date.

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| H-01 | `Hukam of the day` | Widget name in the widget gallery, `SGGSWidgets.swift:98` (HEAD `:107`) | **Is "Hukam of the day" acceptable for a verse picked by date, which is not the Darbar Sahib Hukamnama?** | **Main question (R6).** The wording does not say "Hukamnama" or "Darbar Sahib". But "of the day", together with everyone getting the same verse on the same date, invites readers to treat it as the day's official Hukamnama. See Q1. |
| H-02 | `One verse of Sri Guru Granth Sahib Ji for the whole day, chosen by date (not the Hukamnama from Sri Harmandir Sahib), verbatim with its Ang.` (changed after pre-review to add the note) | Widget description in the gallery, `SGGSWidgets.swift:99` (HEAD `:108`) | OK? Should it say how the verse is chosen? | Accurate. It does not say "drawn by date in this app, not the Hukamnama of Sri Harmandir Sahib". This is the one place a short note would fit. |
| H-03 | `HUKAM OF THE DAY` (or `HUKAM` when the snapshot is older and the verse is not today's) | Widget eyebrow over the verse, `SGGSWidgets.swift:121` (HEAD `:130`) | As H-01. Is the all-capitals form acceptable on a Home Screen? | The code is careful to never call an old verse today's. |
| H-04 | `Tap to read the shabad` (large) · `Tap to read` (medium) | Widget citation line, `SGGSWidgets.swift:144` (HEAD `:153`) | Is "the shabad" right when the unit is a salok and pauri group rather than a shabad? | *Existing* text. The unit may be a salok and pauri group, a Japji pauri, and so on. |
| H-05 | `Open Gurbani Soul once to bring in the Hukam of the day.` | Widget empty state, `SGGSWidgets.swift:147` (HEAD `:156`) | OK? "Bring in" is informal. | Was "Open Gurbani Soul once to draw a Hukam." |
| H-06 | `Today's Hukam` (title) · `Draw a complete Hukam unit and read it verbatim.` (description) · phrases `Today's Hukam in \(.applicationName)`, `Draw a Hukam in \(.applicationName)` | Siri / Shortcuts at **HEAD** `AppIntents.swift:9-10`, `:109-112` (*existing*) | — | **Concern at HEAD.** "Today's Hukam" runs a random draw, so it gives a different unit each time, while the widget's "Hukam of the day" stays fixed. Two different things are called "today's". The *WT* (H-07, H-08) fixes this. If HEAD ships without the *WT*, this needs a decision. |
| H-07 | *WT*: `Today's Hukam` (title) · `Open the Hukam of the day: one Hukam unit for the whole day, the same as the widget's, read verbatim.` · phrases `Today's Hukam in \(.applicationName)`, `Hukam of the day in \(.applicationName)` · short title `Today's Hukam` | `AppIntents.swift:25-26`, `:124-127` | As H-01. Is "Today's Hukam" acceptable as a Siri phrase? | Spoken aloud, "Today's Hukam" sounds even closer to "today's Hukamnama" than the widget does. |
| H-08 | *WT*: `Draw a Hukam` (title) · `Draw a complete Hukam unit and read it verbatim.` · phrase `Draw a Hukam in \(.applicationName)` · short title `Draw a Hukam` | `AppIntents.swift:10-11`, `:128-130` | Is "draw a Hukam" acceptable wording for a random pick? | "Draw" is the app's existing word for the random Hukam. Raised because it is now a Siri name of its own. |
| H-09 | *WT*: Nitnem card `Hukam of the day` · `One Hukam unit for the whole day, the same as the widget's` | `NitnemScreen.swift:199-200` | As H-01. | The widget says "One verse … for the whole day". This card says "One Hukam unit". Both are true (the widget shows the unit's first verse), but readers may see a mismatch. |
| H-10 | *WT*: Nitnem card `Draw a Hukam` · `A new Hukam unit each time, read verbatim` | `NitnemScreen.swift:219-220` (HEAD: `Hukam` · `A complete Hukam unit, read verbatim`) | OK? | none |
| H-11 | *WT*: sheet title `Hukam of the day · Ang \($0.ang)` (fallback `Hukam of the day`) | `ShabadSheet.swift:148` | OK? | The sheet is a good place for a one-line note (see Q1). |

### 2.5 Privacy policy and App Store text

| # | Exact string | Where it appears | Question for the reviewer | Pre-review note |
|---|---|---|---|---|
| P-01 | `Widgets read a small snapshot the app writes into its App Group container: the raag watch, the Hukam of the day for the next two weeks with their Angs, today's Nitnem progress, and — if you use solar mode — your clock-mode choice and your location rounded to about 1 km. Nothing leaves the device.` | In-app Privacy screen, `ios/App/Sources/Screens/PrivacyPolicyScreen.swift:43` (`3b7a52d`) | OK? | Accurate. It says plainly that the verses are worked out ahead of time, so it cannot be a received Hukamnama. "The Hukam of the day for the next two weeks" is awkward. A possible alternative: "the Hukam of the day for each of the next 14 days, with its Ang". |
| P-02 | HEAD: `• The Hukam of the day widget: one verse for the whole day, verbatim with its Ang, and a new one at midnight.` · *WT*: `• The Hukam of the day: one Hukam unit for the whole day, in the app, by Siri ("Today's Hukam") and on a widget that turns at midnight.` | App Store description, `docs/ios/app-store-listing.md:76` (HEAD `:77`) | As H-01. Should the store text say that this is not the Darbar Sahib Hukamnama? | The store is where a reader decides what the app is, so a short note here matters most. |
| P-03 | `> Widgets: three Home Screen widgets (Hukam of the day, Raag now, Nitnem) read a small snapshot the app …` | App Review notes, `docs/ios/app-store-listing.md:234` (`3b7a52d`) | OK? | For Apple's reviewers, not readers. |
| P-04 | Keyword `hukamnama` in `sikh,gurmukhi,punjabi,shabad,hukamnama,waheguru,…` · alt subtitle `Nitnem, Hukamnama & Gurbani` | `docs/ios/app-store-listing.md:42`, `:24` (*existing*) | **Should the app be found by searching "hukamnama" now that it has a "Hukam of the day"?** | **Concern (R6, R8).** The app does not contain the Darbar Sahib Hukamnama (R6; the spec lists an online daily Hukamnama as out of scope). The listing's own rule is that every keyword must name something the app contains. Someone searching "hukamnama" who then finds "Hukam of the day" may well believe it is the Darbar Sahib Hukamnama. A suggested fix: drop `hukamnama` from the keywords and drop the alternative subtitle. |
| P-05 | `Works with Siri and Shortcuts: "Today's Hukam", "What raag is it now", "Read a bani", "Search Gurbani" …` · `URL scheme sggs:// and App Intents ("Today's Hukam", …)` | `docs/ios/app-store-listing.md:96`, `:240` (*existing*) | As H-07. | With the *WT*, "Today's Hukam" means the Hukam of the day. At HEAD it means a random draw (H-06). |

---

## 3. Open questions for the scholar

1. **"Hukam of the day" (H-01 to H-11, P-02, P-04).** Is "Hukam of the day" acceptable wording for a
   unit picked by arithmetic from the date? It is the same on every phone, and it is not the
   Hukamnama from Sri Harmandir Sahib. If it is acceptable, should the copy say so in one line? Two
   places it could go:
   - the widget gallery description;
   - the Hukam of the day sheet. A possible wording: "Chosen by date in this app. Not the Hukamnama
     from Sri Harmandir Sahib."

   If it is not acceptable, possible alternatives are "Verse of the day", "Today's verse" or
   "Today's shabad". Separately: should the keyword `hukamnama` stay in the App Store listing?
2. **"A verified word match" (W-02, W-38, I-19, S-03).** Is this clear to a reader? Does "verified"
   promise more than it means (the word is there, not that the verse is about the theme)? Some tags
   are broad. For example "Ik Onkar" is matched by ਏਕ, ਏਕੁ, ਇਕੁ and ਇਕਿ, and the engineer believes ਇਕਿ
   often means "some" (for example "some are givers, some beggars"). That is the engineer's
   understanding and needs your confirmation. If so, "Ik Onkar ✦ X" may list verses that are not
   about Ik Onkar. Possible alternatives: "matched by a shared word, not by meaning", or "a word
   match (not a reading of meaning)".
3. **"Carry" (W-01, W-13, I-13, I-22, I-32).** Is it acceptable to say a verse "carries" a theme? Is
   "carry … alone" clear?
4. **Ranking (W-04, W-11, W-34, I-09, I-31, D-02).** Three labels may read as ranking:
   - "Most shared" and "Most distinctive";
   - "Brightest stars", for verses with five or more theme words;
   - "Voiced most by", for up to five Gurus or Bhagats, highest first.

   Do any of these read as ranking scripture or its authors?
5. **Honorifics (W-07, I-04, I-23, I-31).** The Constellation drops "Ji" from voice names in short
   labels (for example "Guru Nanak Dev (M1)", "Bhagat Kabir", "Sheikh Farid"). Is that acceptable,
   or should the full stored name be shown?
6. **Theme descriptions (W-31, I-28, Appendix A).** The 54 descriptions are now shown to readers on
   the theme card, with no "explanation" label. Are they acceptable? Should the card label them, for
   example "About this theme (explanation, not scripture)"? Should the Gurmukhi phrases inside them
   be cited by Ang or removed? Two were found verbatim in the pinned database: ਮਰਿ ਮਰਿ ਜੀਵੈ ਤਾ ਕਿਛੁ ਪਾਏ
   (Angs 123 and 360) and ਜੀਵਨ ਮੁਕਤਿ ਸੋ ਆਖੀਐ ਮਰਿ ਜੀਵੈ ਮਰੀਆ (Ang 449). ਮਾਰਗਿ ਚਲਾਏ was not found as a
   contiguous string. These texts belong to sggs-data, so any change is made there.
7. **Highlighting inside the verse (W-40).** The website marks the matched word inside the Gurmukhi
   line. The app leaves the line plain and lists the words underneath. Which do you prefer, or are
   both acceptable?
8. **ੴ on the share card (S-01).** The card sets ੴ above every shared verse, in the accent colour.
   Is that acceptable, given that most verses do not begin with ੴ in the Granth? This is already an
   open G3 question (audit E-13). The Constellation's share card carries it too.
9. **The share card's extra lines (S-03, S-04).** Should a verse shared as an image carry the
   Constellation line and "Gurbani Soul · Built by Algorythmos"? Or should it carry only the verse
   and "Sri Guru Granth Sahib Ji · Ang N"?
10. **Rahao (W-10, W-41, I-08, I-21).** Is "refrain" acceptable as the English gloss for Rahao? Is the
    iOS marker "ਰਹਾਉ · refrain" acceptable?
11. **Raag timing (W-09, I-07).** Is "claims, never facts" a respectful way to describe the traditional
    raag-time attributions?
12. **"Chance" (W-01, W-26, I-12, I-25).** Is "more often than chance" acceptable wording about where
    themes occur in Gurbani?
13. **Theme groups (W-28, I-03).** Are the six groups, their names and their placements acceptable now
    that each has a colour on every star? (`kaal` moved to the Human Condition; `hukam` is in the
    Divine Reality.)

## 4. Sign-off

Mirror of `ios/Resources/NITNEM-REVIEW.md`. Fill in and commit; flip the flag in the same commit.

| Field | Value |
|---|---|
| Reviewer (name / role) | |
| Date reviewed | |
| Edition / reference used | |
| Build or commits reviewed | sggs-platform `ea8c9ec`/`a7d27d0`; gurbani-soul-ios `bdc5018`, `8223e44`, `3b7a52d` + working tree |
| Corrections applied (commit ids) | |

Decisions (OK / Change / Remove / Ask; for Change, write the wording):

| Item(s) | Decision | Wording or note |
|---|---|---|
| W-01 – W-43 (web) | | |
| A-01 – A-05 (API notes) | | |
| D-01 – D-04 (docs) | | |
| I-01 – I-36 (iOS Constellation) | | |
| S-01 – S-04 (share card) | | |
| H-01 – H-11 (Hukam of the day) | | |
| P-01 – P-05 (privacy, App Store) | | |
| Q1 – Q13 (open questions) | | |
| Appendix A (theme descriptions) | | |

Reviewer's note (optional):

&nbsp;

REVIEWED: false

---

## Appendix A: the 54 theme descriptions shown on the theme card

Source: `concepts.description` in the pinned database (`sggs-platform/db/sggs.sqlite`, owned by
sggs-data). Shown verbatim by `constellation.ts:225` (web) and `ThemeCardSheet.swift:29-30` (iOS).
These are copied here exactly. The Gurmukhi inside them is part of the description text, not a
verse quotation cited by Ang.

| Theme key | Description |
|---|---|
| `ahankar` | Egotistical pride and arrogance — the fifth vice; the puffed-up sense of personal greatness. ਅਭਿਮਾਨ (Sanskrit abhimāna) is used as a near-synonym alongside ਅਹੰਕਾਰ throughout the Bani. |
| `akal` | The Timeless / Eternal (Akāl) — the Divine beyond time and death; the 'Undying' of the Mool Mantar (ਅਕਾਲ ਮੂਰਤਿ). |
| `amrit` | Nectar of Immortality — the ambrosial essence of the divine Name that, when imbibed through naam-simran, grants liberation from death and rebirth. |
| `anand` | Divine bliss — the supreme joy that pervades the soul in union with Waheguru; the subject of Guru Amar Das's celebrated Anand Sahib and a frequent marker of the gurmukh state. |
| `anhad` | The unstruck celestial sound (ਅਨਹਦ/ਅਨਹਤ — both spellings) that reverberates within; ਨਾਦ (primordial sound), ਧੁਨਿ (resonance), ਝੁਣਕਾਰੁ (the ringing tone); ਸੁਰਤਿ (consciousness/attention) is the faculty that tunes in; ਸਬਦੁ/ਸਬਦਿ (the Shabad / Gurbani) is the manifest form of anhad heard through the Guru. |
| `avagavan` | The round of reincarnation — coming and going (ਆਵਣ ਜਾਵਣ / ਆਵਣ ਜਾਣ) — expressed in Gurbani as a phrase rather than the single Sanskrit compound ਆਵਾਗਵਣ (which does not appear as one token in the corpus); cessation of this cycle is mukti. |
| `bani` | Sacred Utterance/Scripture — the Guru's divine speech, both the body of Gurbani compositions and the spiritual sound-current that is the Guru's essential form. |
| `bhagti` | Devotion (ਭਗਤਿ) to the Divine — the path and practice of loving surrender; also ਭਗਤ/ਭਗਤਾ referring to the devotee or saint; Gurbani affirms that bhagti without Nam is incomplete (ਭਗਤਿਹੀਣੁ = devoid of devotion is a reproach). |
| `bhana` | Divine Will/Pleasure — joyful, unconditional acceptance of whatever the Waheguru wills; the spiritual stance of complete surrender to God's pleasure (bhana mannana). |
| `bharam` | Doubt, delusion, and wandering — the state of spiritual confusion where the soul mistakes illusion for reality; both ਭਰਮ (Punjabi form) and ਭ੍ਰਮ (Sanskrit-closer form) are used throughout the SGGS. |
| `bhau` | The reverential Fear of God (ਭਉ/ਭੈ) — not terror but awe-infused surrender; paired with ਭਾਉ (divine love/devotion) in the classic Gurbani couplet ਭੈ ਭਾਉ; the Divine itself is ਨਿਰਭਉ (without fear/feud) — the Mool Mantar attribute; ਭਉਜਲੁ (ocean-of-fear/existence) is a compound form. |
| `bhavjal` | The terrifying world-ocean (ਭਵਜਲੁ / ਭਉਜਲੁ — both spellings co-exist) of existential existence through which the soul must cross; ਦੁਤਰੁ ('difficult to cross') is used as a near-synonym adjective; the Guru's Word (Shabad) is the boat. |
| `charan` | The Lotus Feet — the sacred feet of the Guru/God as a devotional focus and metaphor for humble surrender, refuge, and grace. |
| `darshan` | The Blessed Vision — beholding God or the Guru in His divine form; the transformative spiritual 'seeing' that grants liberation and peace. |
| `daya` | Compassion — both as a divine attribute (God as Dayal, the Compassionate) and as a human virtue to be cultivated; the fifth of the panj gun alongside sat, santokh, dharam, and dhairy. |
| `dukh_sukh` | The paired poles of suffering (dukh) and ease/peace (sukh) — Gurbani presents them as two faces of the same maya-conditioned existence; true liberation lies beyond both in the equipoise of sahaj. |
| `garab` | Worldly pride, arrogance, and ego-inflation (ਗਰਬੁ) arising from attachment to the transient world; closely related to ਹਉਮੈ (the ego-self, the 'I-am-ness'), ਅਭਿਮਾਨੁ (self-conceit), ਅਹੰਕਾਰੁ (ego/arrogance), and ਮਦ/ਮਦੁ (intoxication of pride); the overcoming of ਗਰਬ/ਹਉਮੈ is a prerequisite for liberation. |
| `gurmukh` | The Guru-facing one — the soul oriented toward the Guru/Divine, the ideal spiritual being in Gurbani; contrasted with manmukh at every turn as the one who transcends the five vices through Guru's grace. |
| `haumai` | The ego-self; the primal sense of 'I-ness' (hau = I, mai = I-am) that keeps the soul separate from the Divine — Gurbani's central obstacle on the spiritual path, overcome only by Guru's grace. |
| `hukam` | Divine Command/Order — the sovereign will of the Creator by which all creation exists, moves, and is judged. |
| `ik_onkar` | One Universal Creator (Ik Oankaar) — the foundational declaration of the singular, indivisible, all-pervading Divine Reality that opens the Japji and the entire scripture. |
| `jam` | Yama / the death-messenger (ਜਮ); also ਜਮਕਾਲ (Yama the time-death), ਜਮਕੰਕਰ (Yama's agents), ਜਮਦੂਤ (messengers of death), and ਜਮਪੁਰਿ (the city of Yama); Nam-simran is the recurring remedy against Jam's reach. |
| `janam_maran` | The cycle of birth (ਜਨਮ) and death (ਮਰਣ/ਮਰਨ), the fundamental existential condition from which mukti is sought; escape from this cycle is the central soteriological goal in Gurbani. |
| `jot` | The divine Light (ਜੋਤਿ) that pervades all creation and inheres within every being; Gurbani's most recurring mystical image — the individual soul-flame is identical with the Divine Light; ਦੀਪਕੁ/ਦੀਵਾ (lamp) and ਨੂਰ (Persian: Light) are variant metaphors. |
| `kaal` | Time, Death & Mortality (Kāl) — the Messenger of Death (Jam-kāl), the last moment (ਅੰਤਿ ਕਾਲਿ), and the dark age (ਕਲਿ ਕਾਲ); the temporal/mortal pole that the soul transcends through the Name. |
| `kaam` | Lust and sensual desire — the first of the five thieves (panj chor). |
| `karam_nadar` | Divine grace in multiple registers: ਕਿਰਪਾ (grace/mercy, most frequent), ਨਦਰਿ/ਨਦਰੀ (the Glance of Grace — Guru's transforming look), ਦਇਆ/ਦਇਆਲ (compassion/the Compassionate), ਪ੍ਰਸਾਦਿ (by Grace/blessing, Gur Prasaad in Mool Mantar), ਮਿਹਰ/ਮਿਹਰਵਾਨ (Persian: mercy/the Merciful); grace and personal effort (karam as deed) are both present — Gurbani holds the Glance of Grace (nadar) as the final gateway. |
| `karta` | The Creator — names and verbal forms pointing to God as the sole maker and sustainer of all creation. |
| `krodh` | Anger and wrath — the second of the five vices; its poison destroys inner peace and burns the body-vessel, contrasted with the cool fragrance of Nam. |
| `lobh` | Greed and covetousness — the third vice; the insatiable hunger for wealth and more, which drives the manmukh to endless worldly striving. |
| `man` | The mind — the restless inner faculty that oscillates between attachment and liberation; Gurbani's most frequent single concept-word, serving as both the obstacle (manmukh mind) and the instrument of devotion (man tanu dhan). |
| `manmukh` | The self-willed, mind-facing one — the soul enslaved to its own ego and the five vices, living in maya's delusion; the negative archetype that epitomises the un-awakened human condition. |
| `marag_panth` | The spiritual path or way (ਮਾਰਗੁ, ਪੰਥੁ, ਰਾਹੁ, ਮਗੁ — all synonyms for 'road/path'); in Gurbani, the Guru shows the path (ਮਾਰਗਿ ਚਲਾਏ) and the devotee walks it; the concept emphasizes active wayfaring toward the Divine rather than a fixed sectarian path. |
| `maran_jeevan` | The paradox of dying-while-alive (ਜੀਵਤ ਮਰਣਾ): the spiritual death of the ego while the body lives, leading to true living in God; expressed in lines such as 'ਮਰਿ ਮਰਿ ਜੀਵੈ ਤਾ ਕਿਛੁ ਪਾਏ' and 'ਜੀਵਨ ਮੁਕਤਿ ਸੋ ਆਖੀਐ ਮਰਿ ਜੀਵੈ ਮਰੀਆ'; ਜੀਉ (1406 hits) is the life-breath/soul; ਦੇਹੁਰਾ (the body-temple) is associated with this theme. |
| `maya` | The illusory world of material attachment; the three-guned phenomenal creation that enchants the soul away from the True One — used consistently as the great veil of spiritual forgetfulness. |
| `moh` | Worldly attachment and emotional entanglement — the sticky love for family, possessions, and transient things that binds the soul; closely paired with maya in compound phrases like ਮਾਇਆ ਮੋਹ. |
| `mukti` | Liberation or release from the cycle of transmigration; both ਮੁਕਤਿ (Sanskrit mukti) and ਮੋਖ/ਮੋਖੁ (Sanskrit moksha) are used interchangeably; the highest aspiration is ਜੀਵਨ ਮੁਕਤਿ — liberation while still living. |
| `naam` | The divine Name — the essential Word/identity of the Waheguru whose recitation liberates the soul from the cycle of rebirth. |
| `nimrata` | Humility — expressed through multiple Punjabi/Braj words meaning lowly, poor in spirit, without pride; Gurbani elevates these as the ideal self-perception before the Divine, the opposite of ahankar. |
| `patit_pavan` | The purifier of the fallen/sinful (ਪਤਿਤ ਪਾਵਨ); in Gurbani ਪਤਿਤ ('the fallen/degraded') co-occurs with the Divine's capacity to uplift the most wretched — a key aspect of divine grace; appears as a two-word phrase in lines, not as a single token in the lexicon. |
| `prem_pyar` | Divine love in its various registers — ਪ੍ਰੇਮ/ਪ੍ਰੀਤਿ (spiritual love/longing), ਪਿਆਰ (affection), ਪਿਰ/ਪਿਰੁ (the Beloved Lord cast in the bride-groom metaphor), and ਪ੍ਰੀਤਮ (the Beloved); the soul-bride's longing for the Divine Husband is a central Gurbani trope. |
| `sach` | Eternal Truth as both Divine Name (ਸਚੁ = the True One) and the quality of authenticity/truthfulness; ਸਚਿਆਰੁ/ਸਚਿਆਰਾ = the truth-attuned person; ਸਤਿ as in 'ਸਤਿ ਨਾਮੁ' (the Name is Truth) in the Mool Mantar; ਸਤਿਗੁਰੁ = the True Guru. |
| `sahaj` | Intuitive poise, natural ease, and equipoise of the realised state — the effortless, spontaneous condition of the soul absorbed in the Divine; the antithesis of the five vices' turbulence. |
| `sangat` | Holy company — the congregation of truth-seekers (sangat), the company of the saints (sadhsangat/satsangat/satsangi); one of the most powerful liberating forces in Gurbani alongside Nam and Guru. |
| `sansar` | The phenomenal world (ਸੰਸਾਰੁ, ਜਗਤੁ, ਜਗੁ, ਦੁਨੀਆ) understood in Gurbani as transient, illusion-laden, and governed by Maya; the world is not condemned but is seen as the arena where devotion either binds or liberates. |
| `sant_sadh` | The saint or holy person (ਸੰਤ/ਸਾਧ/ਸਾਧੂ) and the company of saints (ਸਾਧਸੰਗਤਿ/ਸੰਗਤਿ = the congregation/holy assembly); Gurbani holds the ਸਾਧਸੰਗਤਿ as the primary transformative environment — the dust of the saint's feet is a recurring image of liberation. |
| `santokh` | Contentment — the virtue of being satisfied with the Divine will (hukam); one of the five virtues (panj gun) and the antidote to lobh/trishna; paired with sat, daya, dharam, and dhairy in classical Gurbani virtue-lists. |
| `satguru` | The True Guru — the divine preceptor (both as the historical Sikh Gurus and as the eternal inner illuminator) who connects the seeker to the Divine Name. |
| `seva` | Selfless service — devotional service to the Guru and Sangat as the primary praxis of bhakti; the gurmukh who serves without ego earns liberation while the manmukh serves only self-interest. |
| `shabad` | The Divine Word/Hymn — the living utterance of the Guru, both the scriptural compositions and the cosmic vibration of Truth that permeates creation. |
| `sifat_salah` | Praise and Glorification — the laudation of God's qualities and greatness through hymn, speech, and devoted contemplation; together these terms express the Gurbani ethic of perpetual praise. |
| `simran` | Remembrance/Meditation — the practice of continuously contemplating and reciting the divine Name, encompassing simran (remembrance), bhajan (devotional singing), jap (repetition), dhyaan (ਧਿਆਨ, focused meditation) and aradhana (ਅਰਾਧਿ/ਆਰਾਧਿ, adoring contemplation). |
| `trishna` | Craving and insatiable thirst — the restless desire that can never be quenched by worldly objects; closely related to lobh but emphasises the burning thirst-quality of unfulfilled longing. |
| `vahiguru` | Wondrous Enlightener (Waheguru) — the primary Sikh epithet for the Divine, combining wonder (vāh) and the primal Guru. |

Engineer's flags in the descriptions, for the reviewer to confirm or dismiss. None of these is a
finding about the scripture.

- They are interpretive, and the card does not label them (R2).
- They contain Gurmukhi phrases with no Ang:
  - `maran_jeevan`. Its two quoted lines were found verbatim at Angs 123/360 and 449.
  - `marag_panth`. ਮਾਰਗਿ ਚਲਾਏ was not found as a contiguous string.
  - Also `akal`, `bhau`, `sach` and `moh`.
- They contain engineering notes a reader would not expect:
  - `maran_jeevan`: "ਜੀਉ (1406 hits)";
  - `patit_pavan`: "as a single token in the lexicon";
  - `avagavan`: "does not appear as one token in the corpus".
- They make doctrinal claims a scholar may want to check:
  - `daya`, "the fifth of the panj gun";
  - `santokh`, "paired with sat, daya, dharam, and dhairy";
  - `bhau`, "the classic Gurbani couplet ਭੈ ਭਾਉ".
- They use different spellings for the same names: "Nam" and "Naam", "Waheguru" (the theme is
  displayed as "Vahiguru"), and "SGGS" (the project style is "Sri Guru Granth Sahib Ji").
