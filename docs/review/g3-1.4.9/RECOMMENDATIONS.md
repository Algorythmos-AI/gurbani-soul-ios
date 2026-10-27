# G3 review pack 1.4.9: editorial recommendations for the reviewer

**Status: recommendations only. Nothing here is a ruling.** This page sits beside the review pack
(`README.md` in this folder) and follows its order. For every item it sets out the scholarly evidence and
an editorial recommendation. The G3 reviewer (a Granthi or Gurbani scholar) decides every item, either by
ticking the boxes in the pull request that adds this page or by replying to the review email with item
numbers.

- No decision line in `README.md` is ticked.
- Section 10 is not signed, and `REVIEWED: false` stands.
- Nothing in the app changes.
- Recorded on 2026-10-27 · Algorythmos · Gurbani Soul editorial.

Two companion pages hold the parts of this review that live in other repositories:

- **The four dataset decisions** (A-07, A-08, A-10, A-11) are in sggs-data, beside the held pull request #17:
  [`validation/attribution-g3-review/RECOMMENDATIONS.md`](https://github.com/Algorythmos-AI/sggs-data/pull/18).
- **The 36 life paragraphs (R-01 to R-36) and the roster pack's six questions** are in sggs-platform:
  [`docs/review/lineage-roster-v2-recommendations.md`](https://github.com/Algorythmos-AI/sggs-platform/pull/321).

## How the evidence was gathered

- **The text.** Every Gurmukhi verse quoted here was read from the dataset `db/sggs.sqlite` by line id
  and carries its Ang. A script checks each quote against the database. None was typed by hand.
- **The commentaries.** These were read line by line from the ShabadOS 4.8.7 database, the release
  that sggs-data pins (sha256 `d8e07134…`, verified). It carries:
  - Prof. Sahib Singh, *Sri Guru Granth Sahib Darpan*: the arth, the word meanings and his notes;
  - the *Faridkot Teeka*;
  - Bhai Vir Singh, *Santhya*;
  - Bhai Manmohan Singh;
  - Dr. Sant Singh Khalsa;
  - each line's BaniDB / SikhiToTheMax shabad id.

  Excerpts are quoted verbatim, each followed by a short English gist. A gist is editorial.
- **The Encyclopaedia of Sikhism (EoS).** Its online edition could not be opened while this page was
  prepared. Where a fact rests on the EoS, it is cited "as in the roster", meaning the entry that the
  roster (`contributors.json`) names. Nothing is quoted from an EoS page that was not read.
- **Web searches.** A fact seen only in a web search result is marked **"search snippet only — Granthi
  to verify"**, with its URL. It is never presented as a source that was read.
- **Labels used below.** "SS" means Prof. Sahib Singh (Darpan). "FDK" means the Faridkot Teeka.
  "Confidence" is editorial: *high*, *medium*, or *Granthi to verify*.
- **Which dataset was read.** The evidence was read from the held dataset 1.3.0 build (sggs-data
  `fix/attribution-g3-held`). It differs from the 1.2.0 that the platform pins only in the lines that
  A-07, A-08, A-10 and A-11 change.

## All recommendations at a glance

| Item | Recommendation | Confidence |
|---|---|---|
| V-01 ਧੁਨੀ About line | **Change:** say the tune is that of an older vaar, and use the "Explanation:" label | high |
| V-02 to V-05 labelled pauris | **Approve:** show each under the Guru the label names | high |
| V-02a pauris ॥੨੭॥ to ॥੨੯॥ (Ang 315) | **Change:** show them under Guru Arjan Dev Ji, as every source reads the bare `ਪਉੜੀ ੫ ॥` | high |
| T-01 Rahao note | **Change (light):** use Sahib Singh's own gloss of ਰਹਾਉ | high |
| T-02 word-family note | **Approve** | high |
| T-03 rate note | **Change:** plainer, adding "not a measure of importance" | high |
| T-04 ਕਰਮ in Karam Nadar | **Other:** (a) now; later remove bare ਕਰਮ with a hand-kept grace list; keep ਕਰਮਿ and ਕਰਮੈ; review ਕਰਮੁ and ਕਰਮਾ verse by verse | medium |
| T-V9 label the theme description | **Yes** | high |
| L-01 Rahao on a voice's page | **Change:** say the same thing as T-01 | high |
| L-02 Gurus' signature | **Change:** a statement about the pen-name; "Not every composition is signed." | high |
| L-03 other voices' signature | **Change:** not for voices with no printed signature; drop "closing verse" | high |
| L-04 In dialogue | **Approve** (optional wording that names the two collections) | high |
| L-05a 1604 | **Change:** "The Adi Granth is installed in the Harimandar", with an EoS source | high (year) |
| L-05b c. 1705–06 | **Change** the wording, and attach a tier-2 source before it ships | medium |
| L-05c 1708 | **Approve**, with a source attached | high |
| M-01 map title | **Change:** "Where the voices lived" | high |
| M-02 to M-04, M-06 to M-08 | **Approve** (M-08: use "1 voice" in the singular) | high |
| M-05 map footnote | **Change:** say that place and year come from different moments of a life | high |
| M-P01 to M-P24 pins | **Approve, except:** relabel M-P08, M-P13, M-P16 and M-P18; adjust the era for M-P22; verify the source for M-P20 | high / Granthi to verify |
| R-01 to R-36 life paragraphs | **14 Change, the rest Approve.** See the platform page. One factual error (R-16 Dhanna). | per item |
| G-01 to G-23 form glosses | **Approve 15. Change 8:** G-02, G-05, G-08, G-18, G-19, G-20, G-21, G-23 | high, except G-21 (medium) and G-23 (Granthi to verify) |
| A-01 to A-06, A-09 | **Confirm all** (A-04 checked line by line) | high |
| A-07 Surdas line (Ang 1253) | **Surdas:** author only (see the sggs-data page) | high |
| A-08 Salok sections | **Split as proposed** | high |
| A-10 Ang 695 labels | **Fix as proposed** | high |
| A-11 Bhagat-run heading author | **The first Bhagat of the run** (and the same for line 14771, Ang 323) | high |

---

## 2. Vaars

### V-01 · The About line on the ਧੁਨੀ sheet
**Finding.** The meaning is accurate. Sahib Singh reads every ਧੁਨੀ/ਧੁਨਿ heading the same way: the
Vaar is to be sung to the tune (ਸੁਰ, ਧੁਨ) of a named older vaar. The existing line does not say that
the tune is *another vaar's* tune, and that is the whole content of these headings. The sheet labels
the line "About:". Theme pages label their notes "Explanation:". One label used everywhere would follow
R2 more consistently.

**Evidence.**
- Sahib Singh on `ਵਾਰ ਮਾਝ ਕੀ ਤਥਾ ਸਲੋਕ ਮਹਲਾ ੧ ਮਲਕ ਮੁਰੀਦ ਤਥਾ ਚੰਦ੍ਰਹੜਾ ਸੋਹੀਆ ਕੀ ਧੁਨੀ ਗਾਵਣੀ` (Ang 137): "ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਨੇ ਉਪਰ ਲਿਖਿਆਂ ਸਿਰ-ਲੇਖ ਦੇ ਕੇ ਆਗਿਆ ਕੀਤੀ ਹੈ ਕਿ ਗੁਰੂ ਨਾਨਕ ਦੇਵ ਜੀ ਦੀ ਇਹ ਮਾਝ ਦੀ ਵਾਰ ਉਸ ਧੁਨੀ (ਸੁਰ) ਵਿਚ ਗਾਉਣੀ ਹੈ ਜਿਸ ਵਿਚ ਮੁਰੀਦ ਖਾਂ ਵਾਲੀ ਗਾਵੀਂ ਜਾਂਦੀ ਸੀ।" Gist: Guru Arjan gave this heading as an instruction that the Vaar be sung in the tune (ਸੁਰ) in which the vaar of Murid Khan was sung.
- Sahib Singh, Gujri ki Vaar M3 (Ang 508): "ਇਸ ਨੂੰ ਸਿਕੰਦਰ ਬਿਰਾਹਿਮ ਦੀ 'ਵਾਰ' ਦੀ ਧੁਨ ਨਾਲ ਗਾਉਣਾ ਹੈ।" Gist: to be sung to the tune of the vaar of Sikandar and Ibrahim.
- Sahib Singh, Ramkali ki Vaar M3 (Ang 947): "ਇਸ ਵਾਰ ਦੀਆਂ ਪਉੜੀਆਂ ਉਸੇ ਸੁਰ (ਧੁਨਿ) ਤੇ ਗਾਣੀਆਂ ਹਨ ਜਿਸ ਸੁਰ ਤੇ ਜੋਧੇ ਤੇ ਵੀਰੇ ਦੀ ਵਾਰ ਦੀਆਂ ਪਉੜੀਆਂ ਗਾਵੀਆਂ ਜਾਂਦੀਆਂ ਸਨ।" Gist: the pauris are sung to the tune of the pauris of the vaar of Jodha and Vira. He reads the headings at Angs 318, 585, 1237, 1278 and 1312 the same way.
- Faridkot Teeka (Ang 137): "…ਤਿਨ ਮੇਂ ਸੇ ਨਉ ਧੁਨਾ ਪਸਿੰਦ ਕਰ ਕੇ ਨਉ ਵਾਰਾਂ ਮੇਂ ਰਖ ਦਈਆਂ।" Gist: nine tunes were chosen and set on nine Vaars. This agrees with the pack's count of 9 ਧੁਨੀ rubrics.

**Where sources differ.** The sources disagree on who added the ਧੁਨੀ headings. Sahib Singh credits
Guru Arjan, who gave the heading as a singing instruction. Faridkot (Ang 137) tells a tradition in
which Guru Hargobind chose the nine tunes ("ਗੁਰੂ ਹਰਿ ਗੋਬਿੰਦ ਜੀ ਨੇ … ਨਉ ਧੁਨਾ ਪਸਿੰਦ ਕਰ ਕੇ"). Neither
claim belongs in the app, and the suggested wording below avoids both.

**Recommended ruling.** Change. The present line is accurate but incomplete. Saying "the tune of an
older vaar" is what these headings literally state, and an explicit label is better.

**Suggested wording (if Change).** `Explanation: the heading names the tune (ਧੁਨੀ) of an older vaar; this Vaar is to be sung to that tune.`

**Confidence.** high

### V-02 · Gauri ki Vaar (M4), pauri ॥੩੦॥, Ang 316, label `ਪਉੜੀ ਮਃ ੫ ॥` (line 14429)

**Finding.** The printed label names Mahalla 5. Every source checked credits this pauri (lines 14429–14434) to Guru Arjan Dev Ji, which is how 1.4.9 shows it.

**Evidence.**
- **Corpus.** `author` is Guru Arjan Dev Ji (M5) on all 6 lines, comp 1116. The saloks before it are `ਸਲੋਕ ਮਃ ੪ ॥` (line 14405) and `ਮਃ ੪ ॥` (line 14420), both Guru Ram Das Ji.
- **ShabadOS 4.8.7.** BaniDB id 1212, writer **Guru Arjan Dev Ji**. The label line is typed "Sirlekh".
- **Translations of the label (via ShabadOS 4.8.7).** Bhai Manmohan Singh: "ਪਉੜੀ ਪੰਜਵੀਂ ਪਾਤਸ਼ਾਹੀ।" Dr. Sant Singh Khalsa: "Pauree, Fifth Mehl:".
- **Faridkot Teeka, line 14374, at the first M5 pauri of this run.** "☬ਪੀਛੇ ਚਉਥੀ ਪਾਤਸ਼ਾਹੀ ਕੀਆਂ ਪਉੜੀਆਂ ਥੀਆਂ। ਅਬ ਪੰਜਵੀਂ ਅਪਨੀ ਨਵੀਨ ਪਉੜੀ ਬਨਾਇ ਕਰ ਲਿਖਤੇ ਹੈਂ।"
  - Gist: the earlier pauris were the Fourth Guru's; from here the Fifth writes new pauris of his own.
- **Prof. Sahib Singh.** No note on these Angs appears in the ShabadOS data. Silence, not dissent.
- **The closing verse signs ਨਾਨਕ:** `ਜਨ ਨਾਨਕ ਕਾ ਖਸਮੁ ਵਡਾ ਹੈ ਸਭਨਾ ਦਾ ਧਣੀਐ ॥੩੦॥` (line 14434, Ang 316).

**Where sources differ.** None found.

**Recommended ruling.** Approve (show it under the Guru the label names, as 1.4.9 does). The printed ਮਃ ੫, the dataset, ShabadOS and the Faridkot Teeka all agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### V-03 · Gauri ki Vaar (M4), pauri ॥੩੧॥, Angs 316–317, label `ਪਉੜੀ ਮਃ ੫ ॥` (line 14448)

**Finding.** As for V-02, the label names Mahalla 5, and every source checked credits lines 14448–14458 to Guru Arjan Dev Ji.

**Evidence.**
- **Corpus.** `author` is Guru Arjan Dev Ji (M5) on all 11 lines, comp 1119. The saloks before it are M4 (lines 14435, 14441).
- **ShabadOS 4.8.7.** BaniDB id 1215, writer **Guru Arjan Dev Ji**. The label line is typed "Sirlekh".
- **Translations of the label.** Bhai Manmohan Singh: "ਪਉੜੀ ਪੰਜਵੀਂ ਪਾਤਸ਼ਾਹੀ।" Dr. Sant Singh Khalsa: "Pauree, Fifth Mehl:".
- **Faridkot Teeka.** Its note at line 14374 (quoted under V-02) opens this run of M5 pauris.
- **The opening verse:** `ਨਾਨਕ ਵੀਚਾਰਹਿ ਸੰਤ ਮੁਨਿ ਜਨਾਂ ਚਾਰਿ ਵੇਦ ਕਹੰਦੇ ॥` (line 14449, Ang 316).

**Where sources differ.** None found.

**Recommended ruling.** Approve (show it under the Guru the label names, as 1.4.9 does). Same grounds as V-02.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### V-04 · Sarang ki Vaar (M4), pauri ॥੩੫॥, Ang 1251, label `ਪਉੜੀ ਮਃ ੫ ॥` (line 53845)

**Finding.** The label names Mahalla 5. Sahib Singh and the Faridkot Teeka both say in so many words that this pauri is Guru Arjan Dev Ji's.

**Evidence.**
- **Prof. Sahib Singh, Darpan, note at line 53850 (via ShabadOS 4.8.7).** "ਇਹ ਪਉੜੀ ਗੁਰੂ ਅਰਜੁਨ ਸਾਹਿਬ ਦੀ ਹੈ, ਜੋ ਪਉੜੀ ਨੰ: ੩੪ ਦੀ ਹੋਰ ਵਧੀਕ ਵਿਆਖਿਆ ਕਰਨ ਲਈ ਹੈ (ਵੇਖੋ ਮਲਾਰ ਕੀ ਵਾਰ ਮ: ੧ ਪਉੜੀ ਨੰ: ੨੭)।"
  - Gist: this pauri is Guru Arjan's, added to expand on pauri 34. Compare Malar ki Vaar M1, pauri 27, which is V-05.
- **Faridkot Teeka, line 53844.** "☬ਇਹ ਪੌੜੀ ਸ੍ਰੀ ਗੁਰੂ ਅਰਜਨ ਦੇਵ ਜੀ ਮਹਾਰਾਜ ਨੇ ਰਚੀ ਹੈ:"
  - Gist: "This pauri was composed by Sri Guru Arjan Dev Ji."
- **ShabadOS 4.8.7.** BaniDB id 4522, writer **Guru Arjan Dev Ji**.
- **Corpus.** Lines 53845–53850 carry Guru Arjan Dev Ji (M5), comp 4836. The closing verse is `ਨਾਨਕ ਸਿਫਤਿ ਸਲਾਹ ਕਰਿ ਪ੍ਰਭ ਕਾ ਜੈਕਾਰੁ ॥੩੫॥` (line 53850, Ang 1251).

**Where sources differ.** None found.

**Recommended ruling.** Approve (show it under the Guru the label names, as 1.4.9 does). The print, Sahib Singh, Faridkot and ShabadOS all name Guru Arjan Dev Ji.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### V-05 · Malar ki Vaar (M1), pauri ॥੨੭॥, Ang 1291, label `ਪਉੜੀ ਨਵੀ ਮਃ ੫ ॥` (line 55493)

**Finding.** The label marks this as a "new" pauri by Mahalla 5. Sahib Singh and Faridkot both say it is Guru Arjan Dev Ji's, added to Guru Nanak's Vaar.

**Evidence.**
- **Prof. Sahib Singh, Darpan, note at line 55501 (via ShabadOS 4.8.7).** "ਗੁਰੂ ਨਾਨਕ ਦੇਵ ਜੀ ਦੀਆਂ ਕੁੱਲ ਪਉੜੀਆਂ ੨੭ ਹਨ, ਪਰ ਇਹ ਪਉੜੀ ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਨੇ "ਨਵੀ" ਰਲਾਈ, ਇਸ ਦੇ ਨਾਲ ਦੇ ਸ਼ਲੋਕ ਗੁਰੂ ਨਾਨਕ ਸਾਹਿਬ ਦੇ ਹੀ ਹਨ;"
  - Gist: Guru Arjan added this pauri as "new"; the saloks with it are Guru Nanak's own.
- **Faridkot Teeka, line 55492.** "☬ਹੋਰ ਪਉੜੀਆਂ ਪਹਲੀ ਪਾਤਸ਼ਾਹੀ ਦੀਆਂ ਹੈਂ ਏਹੁ ਪਉੜੀ ਪੰਜਵੀਂ ਪਾਤਸ਼ਾਹੀ ਦੀ ਹੈ।"
  - Gist: "The other pauris are the First Guru's; this pauri is the Fifth Guru's."
- **Translations of the label.** Bhai Manmohan Singh: "ਨਵੀ ਪਉੜੀ। ਪੰਜਵੀਂ ਪਾਤਿਸ਼ਾਹੀ।" Dr. Sant Singh Khalsa: "New Pauree, Fifth Mehl:".
- **ShabadOS 4.8.7.** BaniDB id 4685, writer **Guru Arjan Dev Ji**.
- **Corpus.** Lines 55493–55501 carry Guru Arjan Dev Ji (M5), comp 5027. The saloks on either side (lines 55484, 55502) are M1.

**Where sources differ.** None found.

**Recommended ruling.** Approve (show it under the Guru the label names, as 1.4.9 does). The print says ਨਵੀ ਮਃ ੫, and Sahib Singh, Faridkot and ShabadOS agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### V-02a · Gauri ki Vaar (M4), pauris ॥੨੭॥ to ॥੨੯॥, Ang 315, bare label `ਪਉੜੀ ੫ ॥` (lines 14375, 14387, 14399)

**Finding.** Every source available reads the bare label `ਪਉੜੀ ੫ ॥` as "pauri, Fifth Mahalla", the same as `ਪਉੜੀ ਮਃ ੫ ॥`. The numeral ੫ is not a pauri number: these pauris are numbered ॥੨੭॥, ॥੨੮॥ and ॥੨੯॥ at their close. 1.4.9 shows them under Guru Ram Das Ji only because the display rule needs `ਮਃ` or `ਮਹਲਾ` before the numeral. As a result, the app splits an unbroken run of five M5 pauris (27 to 31) between two Gurus.

**Evidence.**
- **Corpus.** `author` is Guru Arjan Dev Ji (M5) on every line of all three pauris (comps 1107, 1110, 1113). The saloks between them are `ਸਲੋਕ ਮਃ ੫ ॥` and `ਮਃ ੫ ॥` (for example lines 14369, 14372, 14381, 14384, 14393, 14396).
- **ShabadOS 4.8.7.** BaniDB ids 1203, 1206 and 1209, writer **Guru Arjan Dev Ji** for all three.
- **Translations of each bare label (lines 14375, 14387, 14399; via ShabadOS 4.8.7).** Bhai Manmohan Singh: "ਪਉੜੀ ਪੰਜਵੀਂ ਪਾਤਸ਼ਾਹੀ।" Dr. Sant Singh Khalsa: "Pauree, Fifth Mehl:". These are word for word what both give for the `ਪਉੜੀ ਮਃ ੫ ॥` labels of V-02 and V-03.
- **Faridkot Teeka, line 14374, immediately before pauri 27.** "☬ਪੀਛੇ ਚਉਥੀ ਪਾਤਸ਼ਾਹੀ ਕੀਆਂ ਪਉੜੀਆਂ ਥੀਆਂ। ਅਬ ਪੰਜਵੀਂ ਅਪਨੀ ਨਵੀਨ ਪਉੜੀ ਬਨਾਇ ਕਰ ਲਿਖਤੇ ਹੈਂ। ਇਸ ਵਾਸਤੇ ਮਹਲਾ ਪੰਜਵਾਂ ਵਾ ਪਉੜੀ ਨਵੀਂ ਲਿਖੀ ਜਾਤੀ ਹੈ।"
  - Gist: the pauris before were the Fourth Guru's; the Fifth now writes his own new pauri, which is why "Mahalla 5" or "new pauri" is written on it.
- **The closing verses sign ਨਾਨਕ:**
  - `ਨਾਨਕ ਤਿਸੁ ਸਰਣਾਗਤੀ ਜੋ ਪੁਰਖੁ ਅਲਖੈ ॥੨੮॥` (line 14392, Ang 315)
  - `ਨਾਨਕ ਕਉ ਗੁਰਿ ਬਖਸਿਆ ਨਾਮੈ ਸੰਗਿ ਜੁਟੁ ॥੨੯॥` (line 14404, Ang 315)
- **Prof. Sahib Singh.** No note on Angs 315–317 appears in the ShabadOS data. Silence, not dissent.

**Where sources differ.** None found among the sources. The only disagreement is between the app's display rule and the data.

**Recommended ruling.** Change (show under: Guru Arjan Dev Ji). The bare `ਪਉੜੀ ੫ ॥` is read as Mahalla 5 by the dataset, ShabadOS, both translations and the Faridkot Teeka, and treating it the same way keeps pauris 27 to 31 under one Guru.

**Suggested wording (if Change).** Engineering note, not reader copy: "Treat a pauri label of the form `ਪਉੜੀ N ॥`, where N is a Gurmukhi numeral and the pauri's closing number differs from N, the same as `ਪਉੜੀ ਮਃ N ॥` (Gauri ki Vaar M4, Ang 315, lines 14375, 14387, 14399)."

**Confidence.** high

---

## 3. Themes

### T-01 · The Rahao note (above *Heart-lines*)
**Finding.** Sahib Singh supports the claim strongly and states it many times. He says the Rahao line
holds the shabad's central idea (ਕੇਂਦਰੀ ਭਾਵ / ਮੁੱਖ-ਭਾਵ) and calls it the axis (ਧੁਰਾ) of the
shabad. Two points need care:
- He glosses ਰਹਾਉ as "stop / stay" (ਠਹਿਰ ਜਾਓ), not as "the line a shabad returns to". Returning to the line is a kirtan practice, not the word's meaning.
- He sometimes qualifies the rule with "usually" (ਆਮ ਤੌਰ ਤੇ). Some shabads have no Rahao, and some have two (ਰਹਾਉ ਦੂਜਾ).

"Traditionally read as the shabad's central thought" is therefore fair.

**Evidence.**
- Sahib Singh, note at Sukhmani heading (Ang 262): "'ਰਹਾਉ' ਦਾ ਅਰਥ ਹੈ 'ਠਹਿਰ ਜਾਓ', ਭਾਵ ਕਿ ਜੇ ਇਸ ਸਾਰੇ ਸ਼ਬਦ ਦਾ ਕੇਂਦਰੀ ਭਾਵ ਸਮਝਣਾ ਹੈ ਤਾਂ 'ਰਹਾਉ' ਦੀਆਂ ਤੁਕਾਂ ਤੇ 'ਅਟਕ ਜਾਓ', ਇਹਨਾਂ ਵਿਚ ਹੀ ਸਾਰੇ ਸ਼ਬਦ ਦਾ 'ਸਾਰ' ਹੈ।" Gist: Rahao means "stop"; to grasp the central idea of the shabad, stop at the Rahao lines, because its essence is there.
- Sahib Singh, note (Ang 479): "'ਰਹਾਉ' ਦੀ ਤੁਕ, ਮਾਨੋ, ਸ਼ਬਦ ਦਾ ਧੁਰਾ ਹੈ, ਜਿਸ ਦੇ ਦੁਆਲੇ ਸ਼ਬਦ ਦੇ ਸਾਰੇ ਬੰਦ ਭੌਂਦੇ ਹਨ।" Gist: the Rahao line is, as it were, the axis around which all the stanzas turn.
- Sahib Singh, note (Ang 476): "ਹਰੇਕ ਸ਼ਬਦ ਦੀ 'ਰਹਾਉ' ਵਾਲੀ ਤੁਕ ਵਿਚ ਆਮ ਤੌਰ ਤੇ ਸ਼ਬਦ ਦਾ ਮੁੱਖ-ਭਾਵ ਹੁੰਦਾ ਹੈ।" Gist: the Rahao line *usually* carries the main idea.
- Sahib Singh, arth (Ang 250): "ਰਹਾਉ = ਕੇਂਦਰੀ ਭਾਵ।" Gist: Rahao is the central idea.
- The corpus marks 2,676 lines `is_rahao`.

**Where sources differ.** No source among those checked disagrees. Faridkot does not discuss Rahao in
these entries.

**Recommended ruling.** Change (light). Keep the substance, use Sahib Singh's own gloss of the word,
and drop "the line a shabad returns to".

**Suggested wording (if Change).** `Explanation: Rahao means "pause" or "stay". The Rahao line is traditionally read as holding the shabad's central thought. These Rahao lines carry \(name).`

**Confidence.** high

### T-02 · The word-family note (above the matra forms)
**Finding.** The forms shown (for example ਸਹਜ / ਸਹਜਿ / ਸਹਜੇ, ਕਰਮ / ਕਰਮੁ / ਕਰਮਿ) are one word with
different endings. In Gurbani grammar the ending often changes the meaning. T-04 shows
this directly: in the sample, bare ਕਰਮ always means "deeds", while ਕਰਮਿ almost always means "by grace".
Calling them "the forms of its words" is accurate and neutral. The second sentence is a UI instruction,
not explanation.

**Evidence.** The T-04 counts below, and Sahib Singh's grammatical arth, for example "ਥਿਤੀ = {ਲਫ਼ਜ਼ 'ਥਿਤਿ' ਤੋਂ ਬਹੁ-ਵਚਨ…}" (Ang 296). Gist: he treats endings as grammatical forms of one word.

**Where sources differ.** None.

**Recommended ruling.** Approve. Optionally the Granthi could add "Each form is shown as printed." No
change is needed.

**Confidence.** high

### T-03 · The rate note
**Finding.** The note is accurate, but "tagged verses" is jargon. The note does not say outright that
a higher rate is not a ranking (R3). T-V2 already uses the good phrase "not a measure of importance".
The two headings it explains ("…carry it at a higher rate") are visible in 1.4.9. The note helps R3
only if it is shown.

**Evidence.** Project copy T-V2: `A count of verses that carry each theme's words — not a measure of importance.`

**Where sources differ.** n/a (copy item).

**Recommended ruling.** Change. Plainer wording, and the same disclaimer as T-V2.

**Suggested wording (if Change).** `Explanation: a rate is the share of a raag's or a voice's verses that carry \(name), set beside its share across the whole Granth. It is a count, not a measure of importance. It is shown only where there are enough verses to compare.`

**Confidence.** high (copy). Whether to show per-voice rates at all is a separate R3 question for the
Granthi.

### T-04 · ਕਰਮ in the theme *Karam Nadar*: data flag
**Finding.**
- The forms ਕਰਮ, ਕਰਮੁ, ਕਰਮਿ, ਕਰਮਾ and ਕਰਮੈ tag **613 distinct verses** of the 2,492 in `karam_nadar` (382 + 94 + 90 + 44 + 3).
- A reproducible sample was drawn (seed 1604, stratified by form, 62 verses: ਕਰਮ 37, ਕਰਮੁ 9, ਕਰਮਿ 9, ਕਰਮਾ 4, ਕਰਮੈ all 3) and aligned it to ShabadOS.
- Each verse was classified from Sahib Singh's arth, or from his translation where he gives no arth for the word. Result: **GRACE 18 · DEED/RITUAL 43 · OTHER 1**.

| Form | Tagged | Sampled | GRACE | DEED/RITUAL | OTHER |
|---|---|---|---|---|---|
| ਕਰਮ | 382 | 37 | 0 | 37 | 0 |
| ਕਰਮੁ | 94 | 9 | 5 | 4 | 0 |
| ਕਰਮਿ | 90 | 9 | 8 | 0 | 1 (ਕਿਸਮਤਿ, destiny) |
| ਕਰਮਾ | 44 | 4 | 2 | 2 | 0 |
| ਕਰਮੈ | 3 | 3 | 3 | 0 | 0 |

- Weighting each stratum by its size gives a rough estimate of about **157 grace and about 445 deed/ritual** among the 613 ਕਰਮ-tagged verses. In other words, roughly 7 in 10 ਕਰਮ-tagged verses under "Divine grace" use the word in the sense of deeds or ritual acts.
- Bare ਕਰਮ is overwhelmingly "deed" (0/37 grace in the sample; even so, an upper bound of about 8% grace, or about 30 verses, is possible).
- ਕਰਮਿ and ਕਰਮੈ are overwhelmingly "grace".
- ਕਰਮੁ and ਕਰਮਾ are mixed.

Two further findings:
1. Bare ਕਰਮ is **not always** "deed". The pack's own example, `ਕਰਮ ਖੰਡ ਕੀ ਬਾਣੀ ਜੋਰੁ ॥` (line 354, Ang 8), is *grace* for both Sahib Singh and Faridkot. If ਕਰਮ is removed wholesale (option b), this verse and others like it would drop out.
2. The theme's term list does not include ਕਰਮੀ, the grace form in `ਕਰਮੀ ਆਵੈ ਕਪੜਾ ਨਦਰੀ ਮੋਖੁ ਦੁਆਰੁ ॥` (line 36, Ang 2). That verse reaches the theme only through ਨਦਰੀ. This is noted for the data owner and is not part of the ruling.

**Evidence.**
- GRACE examples:
  - `ਕਰਮੁ ਹੋਵੈ ਸਤਿਗੁਰੂ ਮਿਲਾਏ ॥` (line 4438, Ang 109). Sahib Singh arth: "ਕਰਮੁ = ਬਖ਼ਸ਼ਸ਼". Gist: when there is grace, the True Guru is met.
  - `ਕਰਮਿ ਮਿਲੈ ਨਾਹੀ ਠਾਕਿ ਰਹਾਈਆ ॥੩॥` (line 424, Ang 9). Arth: "ਕਰਮਿ = (ਤੇਰੀ) ਮਿਹਰ ਨਾਲ, ਬਖ਼ਸ਼ਸ਼ ਦੀ ਰਾਹੀਂ". Gist: by Your grace.
  - `ਜੇ ਬਹੁਤੇਰਾ ਲੋਚੀਐ ਵਿਣੁ ਕਰਮੈ ਨ ਪਾਇਆ ਜਾਇ ॥` (line 23064, Ang 516). Translation: "ਮੇਹਰ ਤੋਂ ਬਿਨਾ ਪ੍ਰਭੂ ਦੀ ਪ੍ਰਾਪਤੀ ਨਹੀਂ ਹੋ ਸਕਦੀ". Gist: without grace God is not attained.
- DEED/RITUAL examples:
  - `ਬਹੁ ਬਿਧਿ ਕਰਮ ਕਮਾਵਦੇ ਦੂਣੀ ਮਲੁ ਲਾਗੀ ਆਇ ॥` (line 1601, Ang 39). Arth: "ਕਰਮ = ਧਾਰਮਿਕ ਕੰਮ". Gist: religious acts.
  - `ਕਰਮ ਕਰਤ ਬਧੇ ਅਹੰਮੇਵ ॥` (line 14835, Ang 324). Arth: "ਕਰਮ = ਕਰਮ-ਕਾਂਡ, ਧਾਰਮਿਕ ਰਸਮਾਂ". Gist: ritualism, religious rites.
  - `ਕੋਟਿ ਕਰਮ ਕਰਿ ਦੇਹ ਨ ਸੋਧਾ ॥` (line 55735, Ang 1298). Arth: "ਕਰਮ = ਮਿਥੇ ਹੋਏ ਧਾਰਮਿਕ ਕੰਮ". Gist: prescribed religious acts.
- OTHER example: `ਜਿਸ ਕੈ ਕਰਮਿ ਲਿਖਿਆ ਧੁਰਿ ਕਰਤੈ ਨਾਨਕ ਜਨ ਕੇ ਪੂਰਨ ਕਾਮ ॥੨॥੨੦॥੫੧॥` (line 29608, Ang 683). Arth: "ਜਿਸ ਕੈ ਕਰਮਿ = ਜਿਸ ਦੀ ਕਿਸਮਤਿ ਵਿਚ". Gist: in whose destiny.
- Mixed verse: `ਧੁਰਿ ਕਰਮੁ ਨ ਪਾਇਓ ਪਰਾਣੀ ਵਿਣੁ ਕਰਮਾ ਕਿਆ ਪਾਏ ॥` (line 24343, Ang 550). Sahib Singh reads ਕਰਮੁ as grace ("ਪਰਮਾਤਮਾ ਦੀ ਬਖ਼ਸ਼ਸ਼") and ਕਰਮਾ in the same line as past deeds ("ਕੰਮਾਂ ਤੋਂ ਬਿਨਾ"). One verse can hold both senses.
- The pack's examples: line 354 `ਕਰਮ ਖੰਡ ਕੀ ਬਾਣੀ ਜੋਰੁ ॥` has Sahib Singh arth "ਕਰਮ = ਬਖਸ਼ਸ਼" and Faridkot "(ਕਰਮ) ਕ੍ਰਿਪਾ"; it is grace. Line 340 `ਕੇਤੀਆ ਕਰਮ ਭੂਮੀ…` has arth "ਕਰਮ ਭੂਮੀ = ਕੰਮ ਕਰਨ ਦੀਆਂ ਭੂਮੀਆਂ"; it is deed. Line 490 `…ਖਟੁ ਕਰਮ ਕਰੰਤਾ ॥` has "ਖਟੁ ਕਰਮ" (the six prescribed acts); it is ritual.

**Where sources differ.** On `ਕਰਮੀ ਆਵੈ ਕਪੜਾ` (line 36, Ang 2), Sahib Singh reads ਕਰਮੀ as grace
("ਕਰਮ = ਬਖਸ਼ਸ਼, ਮਿਹਰ"). Faridkot reads it partly as the doer of deeds: "ਐਸੇ ਉਪਾਸਨਾ ਰੂਪੁ ਕਰਮ ਕੇ ਕਰਨ
ਹਾਰਾ ਜਬ ਜੀਉ ਕਰਮੀ ਹੋਤਾ ਹੈ" (gist: when the being becomes a doer of such devotional deeds). The
classification above follows Sahib Singh throughout.

**Recommended ruling.** Other: a staged mix of the pack's options.
1. Now, apply **(a)**. Label the theme page with the stored description, which already says "grace and personal effort (karam as deed) are both present". See T-V9.
2. In the next `sggs-data` release, apply **(b) for bare ਕਰਮ only**, with a hand-kept allow-list (**c**) for the grace uses of ਕਰਮ such as ਕਰਮ ਖੰਡ.
3. Keep ਕਰਮਿ and ਕਰਮੈ.
4. Apply **(c)**, verse by verse, for ਕਰਮੁ and ਕਰਮਾ.

Reason: removing all forms (b) would drop about 90 grace verses carried by ਕਰਮਿ/ਕਰਮੈ, and some carried
by ਕਰਮ itself. Keeping everything leaves an estimated ~445 deed or ritual verses under "Divine grace".

**Confidence.** medium. The sample is small for ਕਰਮੁ and ਕਰਮਾ. The Granthi should check the 62 rows in
`t04_karam_sample.csv`, beside this page; the `class` column is editable.

### T-V9 · Label the theme description on the theme page
**Finding.** `concepts.description` is editorial explanation. On the theme page it is shown without a
label, which conflicts with R2. The Constellation already shows the same text under **About this
theme** with *An editorial note, not scripture.* For `karam_nadar` the description itself carries the
caution T-04 needs ("grace and personal effort (karam as deed) are both present").

**Evidence.** `concepts.description` for karam_nadar, verbatim: "…grace and personal effort (karam as deed) are both present — Gurbani holds the Glance of Grace (nadar) as the final gateway."

**Recommended ruling.** Yes: label it as the Constellation does.

**Suggested wording.** Eyebrow `About this theme`, then the description, then `An editorial note, not scripture.`

**Confidence.** high

---

## 4. Voices of the Granth

### L-01 · *The heart of each shabad · Rahao*
**Finding.** The substance matches Sahib Singh (see T-01). The line states as fact what Sahib Singh
calls the usual case ("ਆਮ ਤੌਰ ਤੇ"), and it carries no explanation label (R2). It should say the same
thing as T-01.

**Evidence.** As for T-01. Also Sahib Singh (Ang 794): "ਗੁਰੂ ਗ੍ਰੰਥ ਸਾਹਿਬ ਜੀ ਦੇ ਸ਼ਬਦਾਂ ਨੂੰ ਸਮਝਣ ਦਾ ਮੂਲ-ਨਿਯਮ ਇਹੀ ਹੈ ਕਿ ਪਹਿਲਾਂ 'ਰਹਾਉ' ਦੀ ਤੁਕ ਨੂੰ … ਚੰਗੀ ਤਰ੍ਹਾਂ ਸਮਝ ਲਿਆ ਜਾਏ।" Gist: the basic rule for understanding a shabad is to first understand its Rahao line.

**Recommended ruling.** Change.

**Suggested wording (if Change).** `Explanation: the Rahao verse is traditionally read as holding a shabad's central thought.`

**Confidence.** high

### L-02 · *How they sign* (Guru page)
**Finding.** The claim is true as a statement about the pen-name (ਛਾਪ). Every Guru whose Bani is in the
Granth uses "ਨਾਨਕ", and the Mahala number in the heading tells the Gurus apart. Read literally, though,
"Every Guru signs the Bani with the name Nanak" overstates it in three ways.
1. **Not every composition carries ਨਾਨਕ.** Many vaar pauris and some saloks are unsigned. For example, the first pauri of Asa di Vaar ends `ਕਰਿ ਆਸਣੁ ਡਿਠੋ ਚਾਉ ॥੧॥` (line 20902, Ang 463), with no name.
2. **One shabad of Guru Arjan names ਸੂਰਦਾਸ in its closing line and not ਨਾਨਕ.** The heading is `ਸਾਰੰਗ ਮਹਲਾ ੫ ਸੂਰਦਾਸ ॥` (line 53936, Ang 1253). The shabad closes `ਸੂਰਦਾਸ ਮਨੁ ਪ੍ਰਭਿ ਹਥਿ ਲੀਨੋ ਦੀਨੋ ਇਹੁ ਪਰਲੋਕ ॥੨॥੧॥੮॥` (line 53943, Ang 1253). Sahib Singh holds that the shabad is Guru Arjan's and that ਸੂਰਦਾਸ is the person addressed: "(ਹੇ ਸੂਰਦਾਸ!)". The app's chhap count for Guru Arjan does not include this name.
3. **In the salok collections of Kabir and Farid, saloks under a Guru's heading open with the Bhagat's name.** Examples: `ਮਹਲਾ ੫ ॥` / `ਕਬੀਰ ਕੂਕਰੁ ਭਉਕਨਾ ਕਰੰਗ ਪਿਛੈ ਉਠਿ ਧਾਇ ॥` (lines 58715–58716, Ang 1375), and `ਮਃ ੩ ॥` / `ਫਰੀਦਾ ਕਾਲੀ ਧਉਲੀ ਸਾਹਿਬੁ ਸਦਾ ਹੈ ਜੇ ਕੋ ਚਿਤਿ ਕਰੇ ॥` (lines 58823–58824, Ang 1378). Sahib Singh reads these names as vocatives ("ਹੇ ਕਬੀਰ!", "ਹੇ ਫਰੀਦ!"), not as signatures.

**Evidence.**
- Sahib Singh, note on line 53943: "ਲਫ਼ਜ਼ 'ਮਹਲਾ ੫' ਤੋਂ ਜ਼ਾਹਰ ਹੁੰਦਾ ਹੈ ਕਿ ਇਹ ਸ਼ਬਦ ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਜੀ ਦਾ ਹੈ। ਲਫ਼ਜ਼ 'ਸੂਰਦਾਸ' ਦੱਸਦਾ ਹੈ ਕਿ ਸਤਿਗੁਰੂ ਜੀ ਨੇ ਸੂਰਦਾਸ ਜੀ ਦੀ ਉਚਾਰੀ ਪਿਛਲੀ ਤੁਕ ਦੇ ਸੰਬੰਧ ਵਿਚ ਇਹ ਸ਼ਬਦ ਉਚਾਰਿਆ ਹੈ। … ਇਹ ਸ਼ਬਦ ਸਤਿਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਜੀ ਦਾ ਆਪਣਾ ਹੈ। ਸੂਰਦਾਸ ਦਾ ਨਹੀਂ।" Gist: "Mahala 5" shows that the shabad is Guru Arjan's. "Surdas" shows that it was uttered in reference to the preceding line by Surdas. It is the Guru's own shabad, not Surdas's.
- Sahib Singh on line 58716: "ਹੇ ਕਬੀਰ! ਭੌਂਕਣ ਵਾਲਾ … ਕੁੱਤਾ…". Gist: "O Kabir!", a vocative. On line 58824: "ਹੇ ਫਰੀਦ! …".
- ShabadOS files the Surdas shabad (53936–53943) under writer "Bhagat Surdas Ji". The corpus credits it to Guru Arjan Dev Ji (M5). Sahib Singh agrees with the corpus.

**Where sources differ.** ShabadOS's writer field and Sahib Singh disagree on the Ang 1253 shabad. Sahib
Singh also reports that some scholars think there were two poets named Surdas ("ਕਈ ਵਿਦਵਾਨਾਂ ਦਾ ਖ਼ਿਆਲ
ਹੈ ਕਿ ਦੋ ਸੂਰਦਾਸ ਹੋਏ ਹਨ").

**Recommended ruling.** Change. Make it a statement about the pen-name, not about every composition.

**Suggested wording (if Change).** `Each Guru uses the name Nanak as the pen-name in the Bani; the Mahala number in the heading tells the Gurus apart. Not every composition is signed.`

**Confidence.** high on the facts. The Granthi should decide whether to note the Ang 1253 case.

### L-03 · *How they sign* (every voice that is not a Guru)
**Finding.** The claim fails for several non-Guru voices, and "usually in a shabad's closing verse"
fails for the salok collections and the Bhatts.

The roster `chhap` data (sggs-platform `frontend/public/contributors.json`) and a check of the corpus
give the following.

| Voice | Roster `chhap` | Corpus check | Signs own name? |
|---|---|---|---|
| Bhagats (Kabir, Farid, Namdev, Ravidas, Jaidev, Trilochan, Beni, Bhikhan, Dhanna, Sain, Pipa, Sadhna, Parmanand, Ramanand) | own name | yes, for example `ਸੈਨੁ ਭਣੈ ਭਜੁ ਪਰਮਾਨੰਦੇ ॥੪॥੨॥` (line 30091, Ang 695), `ਪੀਪਾ ਪ੍ਰਣਵੈ…` (line 30098, Ang 695), `ਜਨੁ ਧੰਨਾ ਲੇਵੈ ਮੰਗੀ ॥੨॥੪॥` (line 30109, Ang 695) | **yes** |
| Kabir and Farid saloks | own name | the name usually **opens** the salok (`ਕਬੀਰ…`, `ਫਰੀਦਾ…`); it does not close it | yes, but not "closing verse" |
| Bhagat Surdas | `[]` | the single line `ਛਾਡਿ ਮਨ ਹਰਿ ਬਿਮੁਖਨ ਕੋ ਸੰਗੁ ॥` (line 53935, Ang 1253) is unsigned and has no heading; Sahib Singh: "ਇਸ ਦੇ ਸ਼ੁਰੂ ਵਿਚ ਇਸ ਦੇ ਉੱਚਾਰਨ ਵਾਲੇ ਭਗਤ ਦਾ ਨਾਮ ਭੀ ਨਹੀਂ ਦਿੱਤਾ ਗਿਆ" (gist: not even the Bhagat's name is given) | **no** |
| Bhai Mardana | `[]` | the three saloks headed `ਸਲੋਕੁ ਮਰਦਾਨਾ ੧ ॥` (line 24461, Ang 553) sign **ਨਾਨਕ**, for example `ਗੁਰਮੁਖਿ ਪਾਈਐ ਨਾਨਕਾ ਖਾਧੈ ਜਾਹਿ ਬਿਕਾਰ ॥੧॥` (line 24467, Ang 553). Sahib Singh: "ਭਾ: ਮਰਦਾਨਾ ਆਪਣੀ ਕਿਸੇ ਰਚਨਾ ਵਿਚ ਲਫ਼ਜ਼ 'ਨਾਨਕ' ਨਹੀਂ ਸੀ ਵਰਤ ਸਕਦਾ। ਸਲੋਕ ਮ: ੧ ਹੈ ਅਤੇ ਮਰਦਾਨੇ ਨੂੰ ਸੰਬੋਧਨ ਕੀਤਾ ਹੈ।" Gist: Mardana could not have used "Nanak"; these are saloks of Mahala 1, addressed to Mardana. ShabadOS also files them under Guru Nanak | **no** (attribution itself disputed) |
| Satta & Balwand | `['ਬਲਵੰਡ']` | Balwand: `ਬਲਵੰਡ ਖੀਵੀ ਨੇਕ ਜਨ…` (line 41580, Ang 967). Satta: `ਦਾਨੁ ਜਿ ਸਤਿਗੁਰ ਭਾਵਸੀ ਸੋ ਸਤੇ ਦਾਣੁ ॥` (line 41619, Ang 968). Sahib Singh: "ਮੈਨੂੰ ਸੱਤੇ ਨੂੰ…"; Faridkot: "ਮੈਂ ਸਤੇ ਕੋ ਦੀਜੀਏ". The signatures sit mid-pauri. **The roster misses ਸਤੇ** | yes, mid-pauri |
| Baba Sundar | `['ਸੁੰਦਰੁ']` | `ਕਹੈ ਸੁੰਦਰੁ ਸੁਣਹੁ ਸੰਤਹੁ ਸਭੁ ਜਗਤੁ ਪੈਰੀ ਪਾਇ ਜੀਉ ॥੬॥੧॥` (line 39580, Ang 924) | yes, closing verse |
| The 11 named Bhatts | own names (ਕਲ੍ਯ੍ਯ, ਨਲ੍ਯ੍ਯ, ਮਥੁਰਾ, ਕੀਰਤੁ, …) | the name sits **mid-savaiya** or at its close; one Kirat set (from line 59735, Ang 1405) carries no ਕੀਰਤੁ by the roster spellings. Sahib Singh names each Bhatt from the signature ("ਇਹਨਾਂ ੧੫ ਸਵਈਆਂ ਦਾ ਕਰਤਾ ਭੱਟ 'ਕਲ੍ਯ੍ਯਸਹਾਰ' ਹੈ", Ang 1392) | yes, mostly; not always closing |
| "The Bhatts" (collective, 54 lines) | `[]` | unsigned, for example `ਸਿਰੀ ਗੁਰੂ ਸਾਹਿਬੁ ਸਭ ਊਪਰਿ ॥` (line 59599, Ang 1401) | **no** |

**Where sources differ.**
- Mardana: the corpus and the roster say Bhai Mardana. Sahib Singh and the ShabadOS writer field say Guru Nanak.
- Surdas line: ShabadOS says Bhagat Surdas. The dataset the app ships (1.2.0) still credits Bhagat Namdev Ji, as the roster note says; the held dataset 1.3.0 (A-07) credits Bhagat Surdas Ji.

**Recommended ruling.** Change. The sentence must not appear for voices with an empty `chhap`
(Surdas, Mardana, "The Bhatts"). For the rest, drop "usually in a shabad's closing verse".

**Suggested wording (if Change).**
- Voices with a `chhap`: `This voice names itself in the Bani, often in a shabad's closing verse.`
- Voices with an empty `chhap`: no sentence, or `No signature of this voice is printed in the Granth.`

Separate data note: add `ਸਤੇ` to Satta & Balwand's `chhap`.

**Confidence.** high (corpus facts). Granthi to verify the Mardana and Surdas attributions, which
belong to the A- items.

### L-04 · *In dialogue*
**Finding.** The claim is accurate. In Salok Bhagat Kabir Ji and Salok Sheikh Farid Ji, saloks headed
ਮਹਲਾ ੫ or ਮਃ ੩ are set among the Bhagat's saloks. The corpus table `author_dialogues` holds 17 such
pairs: 6 with Kabir (Angs 1375–1376) and 11 with Farid (Angs 1378–1383). Sahib Singh treats them as
responses ("ਦੇ ਪਰਥਾਇ", in reference to). The present wording, "set beside", is neutral and does not
rank anyone (R3). It could name the two collections.

**Evidence.**
- Sahib Singh (Ang 965 note): "ਕਬੀਰ ਜੀ ਦੇ ਸ਼ਲੋਕ ਨੰ: ੨੦੮ ਦੇ ਪਰਥਾਇ ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਦੇ ੩ ਸ਼ਲੋਕ ਹਨ". Gist: Guru Arjan has 3 saloks in reference to Kabir's salok 208.
- Example in the corpus: line 58714 `ਨਾ ਹਰਿ ਭਜਿਓ ਨ ਖਤੁ ਫਟਿਓ ਕਾਲੁ ਪਹੂੰਚੋ ਆਇ ॥੨੦੮॥` (Ang 1375), followed by `ਮਹਲਾ ੫ ॥` (line 58715).

**Where sources differ.** None.

**Recommended ruling.** Approve. A Change naming the collections is optional:

**Suggested wording (if Change).** `In the saloks of Bhagat Kabir Ji and Sheikh Farid Ji, saloks of the Gurus are set beside theirs, each under its own Mahala heading.`

**Confidence.** high

### L-05 · The Granth's milestones on the River timeline

**General recommendation for all three.** Cite a source for each, in the same way the roster does (`sources`
with `supports`). The code comment ("Historical claims without a reviewed source yet") is right: today none of
the three has a source attached. R-05 already cites the EoS entry on Guru Arjan for the 1604 date, so L-05a can
reuse that citation.

### L-05a · 1604 · "The Adi Granth is compiled"

**Finding.** The year is sound. The event drawn is better described as the *installation* of the Adi Granth in
the Harimandar (the compilation took several years before it). The day differs between sources, which matters
only if a day is ever shown; the milestone shows the year only.

**Evidence.**
- EoS (Arjan Dev, Guru) as cited in the roster, R-05 context: "He compiled the Adi Granth, installed in the
  Harimandar on 16 August 1604".
- Search snippet only — Granthi to verify: sources split between 16 August 1604 and 1 September 1604
  (the commonly observed Gurpurab date); one gives completion on 30 August and installation the next day.
  https://www.reonline.org.uk/festival_event/installation-of-the-guru-granth-sahib-in-the-harmandir-sahib/ ;
  https://www.allaboutsikhs.com/today-in-sikh-history-16th-august/ ; https://sikhri.org/inspiration/celebrating-the-eternal-light-first-prakash-of-guru-granth-sahib
- The Bikrami form (Bhadon sudi 1, Sammat 1661) could not be confirmed from any source read. Granthi to verify.

**Where sources differ.** Day only: 16 August (EoS, per roster) vs 1 September (common observance; the
difference is the Julian/Gregorian and lunar-calendar reckoning). Year 1604 is agreed.

**Recommended ruling.** Change (wording only).

**Suggested wording (if Change).** Title: `The Adi Granth is installed in the Harimandar`. Keep label `1604`.
Source: EoS, Arjan Dev, Guru (the entry already cited for R-05). If a day is ever added, name both
("16 August 1604 by the EoS; observed on 1 September").

**Confidence.** high (year); Granthi to verify (day and Bikrami date).

### L-05b · c. 1705–06 · "The Damdama Sahib Bir adds Guru Tegh Bahadur Ji's Bani"

**Finding.** The fact (Guru Gobind Singh had the Bani of Guru Tegh Bahadur entered in the recension prepared at
Damdama Sahib, Talwandi Sabo, with Bhai Mani Singh as scribe) is the standard account. The year is genuinely
uncertain between 1705 and 1706, which the `c. 1705–06` label already handles well. The title, though, reads as
if the Bir itself acted. The Bir is also commonly called the Damdami Bir.

**Evidence.**
- Corpus: the Granth carries Guru Tegh Bahadur's Bani and Saloks Mahala 9 (roster R-06 notable Bani:
  `ਸਲੋਕ ਮਹਲਾ ੯`, comp 5372, Ang 1426), which the 1604 recension could not have held.
- Search snippet only — Granthi to verify: Talwandi Sabo, hymns of Guru Tegh Bahadur added, Bhai Mani Singh as
  transcriber; SikhiWiki pages give 1705 in one place and a nine-month stay in 1706 in another.
  https://en.wikipedia.org/wiki/Takht_Sri_Damdama_Sahib ; https://www.sikhiwiki.org/index.php/Takhat_Sri_Damdama_Sahib
- No tier-2 source (EoS, Darpan) was read for this item. The EoS has entries on Damdama Sahib and on the Guru
  Granth Sahib that should be cited once reachable.

**Where sources differ.** 1705 vs 1706. Some accounts say the Granth was rewritten from memory at Damdama; that is
a tradition and is best not stated.

**Recommended ruling.** Change (wording), and attach a tier-2 source before switching on.

**Suggested wording (if Change).** Label `c. 1705–06`. Title: `At Damdama Sahib, Guru Tegh Bahadur Ji's Bani is entered in the Granth`.
(Shorter alternative: `Guru Tegh Bahadur Ji's Bani is added at Damdama Sahib`.)

**Confidence.** medium (fact); Granthi to verify (year and the source to cite).

### L-05c · 1708 · "Guruship passes to the Granth"

**Finding.** Correct and well worded. Guru Gobind Singh conferred Guruship on the Granth at Nanded in 1708,
shortly before his passing. Sources disagree on the day (6/7 October, 20/21 October, 3 November are all in
circulation, from different calendars and from the Bhatt Vahi record). The milestone shows the year only, which
avoids the disagreement.

**Evidence.**
- Search snippet only — Granthi to verify: Nanded is consistent across sources; days differ.
  https://en.wikipedia.org/wiki/Guru_Gaddi ; https://en.wikipedia.org/wiki/Guru_Maneyo_Granth ;
  https://www.reonline.org.uk/?p=2074 ; https://www.sikhiwiki.org/index.php/Nanded_1708
- No tier-2 source read. Granthi to name the source to cite (e.g. the EoS entry on Guru Granth Sahib or on
  Guru Gobind Singh).

**Where sources differ.** The day only.

**Recommended ruling.** Approve as written, with a source attached. Optional: add the place.

**Suggested wording (if Change).** Optional: `Guruship passes to the Granth at Nanded`.

**Confidence.** high (fact, year, place); Granthi to verify (source).

### The Insights map (M-01 to M-08, M-P01 to M-P24)

#### M-01 · Section header "From Multan to Banaras"

**Finding.** The title does not describe the map. No pin is at Multan (Farid is pinned at Ajodhan/Pakpattan; his
birthplace Kothewal is "near Multan", R-07). The map runs well past both ends: west to Sehwan in Sindh (M-P16,
lon 67.86), east to Kenduli in Bengal (M-P08, lon 87.4), and south to Pandharpur and Barsi in Maharashtra
(M-P10, M-P09, M-P17, lat 17.68–18.23). Banaras is near the middle, not an end. A reader would take the title as a
claim about where the voices lived, and it is inexact.

**Evidence.** Pin table in README §4 (coordinates as listed); roster `place` fields.

**Where sources differ.** n/a (editorial).

**Recommended ruling.** Change.

**Suggested wording (if Change).** `Where the voices lived` (plain, descriptive). If a span is wanted:
`From Sindh to Bengal`.

**Confidence.** high.

#### M-02, M-03, M-04, M-06, M-07, M-08 · counters, tapped line, VoiceOver

**Finding.** Plain and accurate. M-06 already says "approximate", which is good. Two small points:
M-02 "dated voices" is fine; M-08's "`\(n) voices`" should agree in number ("1 voice").

**Recommended ruling.** Approve (M-08: Change only to handle the singular, `1 voice`).

**Confidence.** high.

#### M-05 · The map's footnote

**Finding.** The footnote is honest, but it hides one real problem: **the place and the year often belong to
different moments of a life.** Pins are mostly the voice's later seat, while the slider uses the birth year.
The result is anachronism on screen: at 1469 Guru Nanak appears at Kartarpur (settled c. 1521, R-01); at 1563 Guru
Arjan appears at Amritsar (the settlement founded by Guru Ram Das, R-04); at 1621 Guru Tegh Bahadur appears at
Chakk Nanaki, which he himself founded later (R-06). Surdas is pinned where he died (Banaras) at his birth year.
Ramanand is pinned at Kashi though born at Prayag (roster `birthplace`).

**Evidence.** Roster `place` vs `birthplace` and `born` fields (R-01, R-04, R-05, R-06, R-11, R-21); README pin table.

**Recommended ruling.** Change. Either (a) state the rule, or (b) change the scrubber so a pin appears at the
place the voice is tied to, not at birth. (a) is the smaller change.

**Suggested wording (if Change).** `Each voice is shown at one place tied to their life, often where they settled, not always where they were born. Years are birth years (or death years), often traditional. Places are approximate and cited in the roster. Voices without a known place are not mapped. Coastline: Natural Earth.`

**Confidence.** high (the finding); the choice between (a) and (b) is the Granthi's and the engineer's.

#### On the question "Is placing each voice at one town and one year acceptable at all?"

Recommendation: acceptable **only** with M-05 changed as above, and with disputed places labelled as disputed on
the pin itself (Trilochan already is; Jaidev, Dhanna and Sadhna are not, see the pin table). If the Granthi
prefers no map until a fuller treatment exists, "Reject the map" keeps it off and costs nothing in 1.4.9.

#### M-P01 to M-P24 · The pins

General: every pin needs the M-05 change (place and year from different moments of a life). Several coordinates
are shared: Varanasi 25.32, 83.01 holds four voices (Ramanand, Kabir, Ravidas, Surdas); Amritsar holds three
(Ram Das, Arjan, Mathura); Goindval three (Amar Das, Sundar, Jalap); Barsi two (Trilochan, Parmanand). Check that
the pins do not hide each other. The same city is labelled three ways: "Kashi (Varanasi)", "Varanasi", "Banaras
(Varanasi)"; recommend one form, e.g. `Kashi (Varanasi)` for all four.
| Pin | Recommendation | Note |
|---|---|---|
| M-P01 Guru Nanak · Kartarpur | Approve, with M-05 change | Kartarpur from c. 1521; year shown is birth 1469 (see R-01 variant) |
| M-P02 Guru Angad · Khadur | Approve | Seat; born Matte di Sarai |
| M-P03 Guru Amar Das · Goindval | Approve, with M-05 change | Born Basarke 1479; Goindval founded later |
| M-P04 Guru Ram Das · Amritsar | Approve, with M-05 change | Born Lahore 1534; founded the Amritsar settlement |
| M-P05 Guru Arjan · Amritsar | Approve, with M-05 change | Born Goindval 1563 |
| M-P06 Guru Tegh Bahadur · Chakk Nanaki | Approve, with M-05 change | Born Amritsar 1621; founded Chakk Nanaki much later |
| M-P07 Farid · Ajodhan (Pakpattan) | Approve | Born Kothewal near Multan, 1173 per EoS (1175 in some works) |
| M-P08 Jaidev · Kenduli (Birbhum) | Change label | Disputed (Kenduli-Sasan near Puri); label `Kenduli (one of two traditions)`, as Trilochan's pin does |
| M-P09 Trilochan · Barsi | Approve | Barsi also named by the writer Sahib Singh quotes (Ang 92). Year 1267: Granthi to verify (EoS 1267 vs "ਸੰਮਤ ੧੨੬੭ ਬਿਕਰਮੀ", see R-09) |
| M-P10 Namdev · Pandharpur | Approve | Born Narasi-Vamani; Pandharpur later seat |
| M-P11 Ramanand · Kashi | Approve, with M-05 change | Born Prayag; year c. 1300 (EoS 1299/1300 variants in roster) |
| M-P12 Kabir · Kashi | Approve | 1398 per EoS; c. 1440 in some works |
| M-P13 Ravidas · Varanasi | Change label | Unify with "Kashi (Varanasi)" |
| M-P14 Dhanna · Dhuan | Approve; Granthi to rule on variants | Dhuan Kalan / Chauru named by discovery sources (roster note) |
| M-P15 Pipa · Gagraun | Approve | Born c. 1425 |
| M-P16 Sadhna · Sehwan | Change label | "as believed" (EoS per roster): label `Sehwan (Sindh), as believed` |
| M-P17 Parmanand · Barsi | Approve | Same point as Trilochan; check overlap |
| M-P18 Surdas · Banaras | Change label; M-05 change | Place of death shown at birth year 1529; unify city label |
| M-P19 Mardana · Talwandi | Approve | Birthplace and birth year agree |
| M-P20 Sundar · Goindval | Granthi to verify | Pin source is the EoS entry on Guru Amar Das, not on Sundar; place is inferred from the family seat |
| M-P21 Satta & Balwand · Lahore | Approve | Place of burial; no year (listed under "Dates uncertain") |
| M-P22 Mathura · Amritsar 1634 | Approve; small era change | Era `Court bard · late 16th c.` but he fell in 1634; suggest `Court bard · late 16th–early 17th c.` |
| M-P23 Jalap · Goindval | Approve | EoS (Bhatt Bani) as cited |
| M-P24 Bhikha · Sultanpur Lodhi | Approve | EoS (Bhikhā) as cited |

### R-01 to R-36 · The 36-voice roster

The full evidence for each life paragraph, and for the roster pack's six questions, is on the platform page:
[`docs/review/lineage-roster-v2-recommendations.md`](https://github.com/Algorythmos-AI/sggs-platform/pull/321).
In short:

- **One factual error.** R-16 (Bhagat Dhanna Ji) says that Dhanna himself, in a hymn in Asa, tells how
  Namdev, Kabir, Ravidas and Sain drew him to God. That hymn is headed `ਮਹਲਾ ੫ ॥` (line 22053, Ang 487). It
  is Guru Arjan's and speaks of Dhanna in the third person. SS says so in his note on line 22063. R-17
  already treats it as Guru Arjan's, so the two paragraphs contradict each other.
- **Change recommended, mostly to name a variant or remove a ranking word:** R-01, R-05, R-07, R-09, R-13,
  R-14, R-15, R-16, R-17, R-18, R-19, R-20, R-25 and R-32. The romanisation of four Bhatts also needs to
  agree: R-26, R-31, R-33 and R-35.
- **Approve as written:** every other R item.
- **The roster pack's questions:**
  - **The Bhatts:** keep 11 named Bhatts. SS reads ਟਲ as another name of Kalsahar.
  - **Mardana:** show the Ang 553 saloks under Guru Nanak Dev Ji.
  - **Surdas:** confirm.
  - **Raagmala:** no author.
  - **Japji:** Guru Nanak Dev Ji.
  - **Gurmukhi names:** approve the Gurmukhi forms; make the romanisation agree.

---

## 5. Index › Forms: the glosses (G-01 to G-23)

"SS" = Prof. Sahib Singh (Darpan); "FDK" = Faridkot Teeka. A heading's line id refers to the corpus.
| Item | Form (heading, line, Ang) | Recommended gloss | Ruling | Source | Confidence |
|---|---|---|---|---|---|
| G-01 | Pahare (`ਸਿਰੀਰਾਗੁ ਮਹਲਾ ੧ ਪਹਰੇ ਘਰੁ ੧ ॥`, 3027, 74) | "watches": the four watches of the night, as the stages of a life | Approve | SS note, line 3033: "ਜੀਵ … ਜ਼ਿੰਦਗੀ ਦੀ ਚਾਰ-ਪਹਰੀ ਰਾਤ ਇਥੇ ਗੁਜ਼ਾਰਦਾ ਹੈ" (the being spends life's four-watch night here); FDK, Ang 77: "ਚੌਥੇ ਪਹਰੇ, ਭਾਵ ਬ੍ਰਿਧ ਅਵਸਥਾ" (the fourth watch, i.e. old age) | high |
| G-02 | Vanjara (`ਸਿਰੀਰਾਗੁ ਮਹਲਾ ੪ ਵਣਜਾਰਾ`, 3255, 81) | "the trader": the soul as a travelling trader | Change (add "travelling") | SS arth, Ang 140: "ਵਣਜਾਰਾ = ਫੇਰੀ ਲਾ ਕੇ ਸਉਦਾ ਵੇਚਣ ਵਾਲਾ" (one who trades going from place to place); Ang 1238: "ਵਪਾਰੀ (ਜੀਵ)" | likely→high |
| G-03 | Barah Maha (5451, 133; 47556, 1107) | "twelve months" | Approve | heading words; SS: "'ਬਾਰਹ ਮਾਹਾ ਛੰਤ'" (Ang 1107) | high |
| G-04 | Din Raini (`ਮਾਝ ਮਹਲਾ ੫ ਦਿਨ ਰੈਣਿ`, 5580, 136) | "day and night" | Approve | heading words (no SS note found) | high |
| G-05 | Karhale (`…ਮਹਲਾ ੪ ਕਰਹਲੇ`, 10215, 234) | "O camel": the wandering mind addressed as a young camel | Change ("camels" → address to the camel) | SS arth, Ang 234: "ਕਰਹਲੇ = ਹੇ ਕਰਹਲਾ! ਹੇ ਊਠ ਦੇ ਬੱਚੇ ਵਾਂਗ ਬੇ-ਮੁਹਾਰ!" (O unbridled one, like a young camel); FDK: "ਮਨ ਰੂਪਿ (ਕਰਹਲੇ) ਊਟ ਕੇ ਤਾਈਂ ਉਪਦੇਸ" (counsel to the mind as camel), also "ਛੰਤ ਕੀ ਜਾਤਿ" (a kind of verse) | high |
| G-06 | Bavan Akhri (10902, 250; 15547, 340) | "fifty-two letters": an acrostic on the letters | Approve | SS: "੫੨ ਅੱਖਰਾਂ ਵਾਲੀ ਬਾਣੀ" (a Bani of 52 letters); FDK explains 52 by the Sanskrit alphabet | high |
| G-07 | Thitti (13617, 296; 15716, 343; 35733, 838) | "lunar days" | Approve | SS arth, Ang 296: "ਥਿਤੀ = … ਚੰਦ੍ਰਮਾ ਦੇ ਵਧਣ ਘਟਣ ਦੇ ਹਿਸਾਬ ਦਿਹਾੜਾ" (a day reckoned by the moon's waxing and waning) | high |
| G-08 | Dakhne (14733, 322; 46991, 1094) | "southern": saloks in the speech of the Multan region | Change | full section below | high |
| G-09 | Birhare (`ਆਸਾ ਮਹਲਾ ੫ ਬਿਰਹੜੇ ਘਰੁ ੪ ਛੰਤਾ ਕੀ ਜਤਿ`, 19822, 431) | "songs of separation", in the gait of chhants | Approve | SS note, Ang 431: "ਬਿਰਹੜੇ-ਬਿਰਹੁ-ਭਰੇ। … ਇਹਨਾਂ ਦੀ ਚਾਲ ਛੰਤਾਂ ਵਾਲੀ ਹੈ" (full of separation; their gait is that of chhants); FDK: "ਜੋ ਵਿਯੋਗ ਦਸਾ ਮੇਂ ਵਾਕ ਕਹੇ" (words spoken in separation) | high |
| G-10 | Patti (`ਰਾਗੁ ਆਸਾ ਮਹਲਾ ੧ ਪਟੀ ਲਿਖੀ`, 19848, 432; 19922, 434) | "the writing tablet": an alphabet acrostic | Approve | heading `ਪਟੀ ਲਿਖੀ`; FDK, first line: "ਸਸੈ ਅਖਰ ਕਾ ਇਹ ਬੀਚਾਰੁ ਹੈ" (each stanza reflects on a letter); no SS gloss of the word found | likely |
| G-11 | Ghorian (`ਵਡਹੰਸੁ ਮਹਲਾ ੪ ਘੋੜੀਆ`, 25307, 575) | "mares": wedding songs | Approve | FDK: "ਜੈਸੇ ਬਿਆਹ ਮੇਂ ਇਸਤ੍ਰੀਆਂ ਘੋੜੀਆਂ ਨਾਮਕ ਗੀਤ ਗਾਉਤੀਆਂ ਹੈਂ" (songs called ghorian that women sing at weddings); SS: "ਘੋੜੀਆ = ਘੋੜੀਆਂ" | high |
| G-12 | Alahunian (25449, 578) | "dirges": songs of mourning | Approve | SS note, Ang 579: "ਅਲਾਹਣੀਆ ਬਾਰੇ ਨੋਟ: ਕਿਸੇ ਦੇ ਮਰਨ ਤੇ ਗਾਏ ਜਾਣ ਵਾਲੇ ਗੀਤ" (songs sung at a death); FDK: "ਮਰੇ ਹੂਏ ਪੁਰਸੋਂ ਕੇ ਗੁਣ ਕਹ ਕਰ ਰੋਣਾ" (weeping while telling the virtues of the dead) | high |
| G-13 | Kuchaji (32706, 762) | "the bride without good ways" | Approve (or "unrefined") | FDK: "(ਕੁਚਜੀ) ਸੁਭ ਅਚਾਰ ਰਹਿਤ" (lacking good conduct); SS: "'ਕੁਚੱਜੀ'" | high |
| G-14 | Suchaji (32724, 762) | "the bride of good ways" | Approve (or "refined") | SS arth: "ਸੁਚਜੀ = ਸੁ-ਚੱਜੀ, ਜਿਸ ਨੇ ਜੀਵਨ ਦੀ ਚੰਗੀ ਜਾਚ ਸਿੱਖੀ ਹੋਈ ਹੈ" (one who has learned the good way to live); FDK: "ਸ੍ਰੇਸਟ ਆਚਾਰ ਵਾਲੀ" (of excellent conduct) | high |
| G-15 | Gunvanti (32735, 763) | "the virtuous one" | Approve | SS arth: "ਗੁਣਵੰਤੀ = ਗੁਣਾਂ ਵਾਲੀ" (possessed of virtues); FDK: "ਪ੍ਰੇਮ ਗੁਨ ਵਾਲੀ ਉਤਮ ਜਗ੍ਯਾਸੀ" (an excellent seeker with the virtue of love) | high |
| G-16 | Sadd (`ਰਾਮਕਲੀ ਸਦੁ`, 39543, 923) | "the call": here, the Divine call to Guru Amar Das | Approve, optionally with the qualifier | SS note, line 39550: "'ਸਦੁ' … ਇਸ ਦਾ ਅਰਥ ਹੈ 'ਵਾਜ' … ਇਥੇ ਇਸ ਦਾ ਭਾਵ ਹੈ 'ਰੱਬ ਵੱਲੋਂ ਗੁਰੂ ਅਮਰਦਾਸ ਜੀ ਨੂੰ ਆਇਆ ਹੋਇਆ ਸੱਦਾ'" (sadd means a call; here, the summons from God to Guru Amar Das) | high |
| G-17 | Ruti (`ਰਾਮਕਲੀ ਮਹਲਾ ੫ ਰੁਤੀ ਸਲੋਕੁ`, 39701, 927) | "seasons" | Approve | SS arth, Ang 1015: "ਰੁਤੀ = ਰੁਤਾਂ {'ਰੁਤਿ' ਤੋਂ … ਬਹੁ-ਵਚਨ}" (seasons, plural of ਰੁਤਿ); FDK: "ਖਟ ਰੁਤੋਂ ਮੇਂ" (in the six seasons) | high |
| G-18 | Anjulian (43114, 1007; 43558, 1019) | "cupped hands": a petition made with joined palms | Change | full section below | high |
| G-19 | Gatha (`ਮਹਲਾ ੫ ਗਾਥਾ`, 58118, 1360) | "a verse of praise", in an old literary language mixing Sanskrit and Prakrit | Change | full section below | high |
| G-20 | Funhe (`ਫੁਨਹੇ ਮਹਲਾ ੫`, 58179, 1361) | "again and again": verses in which a word recurs, here ਹਰਿਹਾਂ | Change | full section below | high |
| G-21 | Chaubole (`ਚਉਬੋਲੇ ਮਹਲਾ ੫`, 58273, 1363) | the name of a metre (chhant) | Change | full section below | medium |
| G-22 | Savaiye (59089, 1385) | the savaiya metre: verses of praise | Approve | SS: "ਗੁਰੂ ਅਰਜਨਦੇਵ ਜੀ ਦੇ ਉਚਾਰੇ ਹੋਏ ਸਵਯੇ" (savaiyas uttered by Guru Arjan); "ਗੁਰੂ ਨਾਨਕ ਸਾਹਿਬ ਦੀ ਉਸਤਤਿ ਵਿਚ ਉਚਾਰੇ ਹੋਏ ਸਵਈਏ" (savaiyas in praise of Guru Nanak, Ang 1389); no SS gloss of the metre found | high |
| G-23 | Mundavani (`ਮੁੰਦਾਵਣੀ ਮਹਲਾ ੫ ॥`, 60586, 1429) | "the seal": a closing riddle that gladdens, likened to a covered dish | Change; sources differ | FDK: "(ਮੁੰਦਾਵਣੀ) ਸਰਪੋਸ ਕੋ ਕਹਿਤੇ ਹੈਂ … ਕੋਈ ਔਰ ਬਾਣੀ ਨ ਚਢਾਈ ਜਾਏ" (a cover or lid; a rule that no further Bani be added); SS arth: "ਮੁੰਦਾਵਣੀ = … ਆਤਮਕ ਪ੍ਰਸੰਨਤਾ ਦੇਣ ਵਾਲੀ ਵਸਤ" (from mud, "to please": a thing that gives spiritual delight), and his note ties it to the ਮੁਦਾਵਣੀ (riddle on a dish) of Sorath ki Vaar M3, Ang 645 | Granthi to verify |

### G-08 · Dakhne
**Finding.** "Of the south" is right, but it is incomplete. Sahib Singh and Faridkot agree that
ਡਖਣਾ = ਦੱਖਣਾ ("southern") and that it names verses in the speech of the south-west Punjab (Multan,
Lahnda), where ਡ is spoken in place of ਦ. Faridkot also calls it a kind of chhant.

**Evidence.**
- SS arth on `ਡਖਣਾ ॥` (Ang 80): "ਡਖਣਾ = ਦੱਖਣਾ, ਮੁਲਤਾਨ ਦੇ ਇਲਾਕੇ ਦੀ ਬੋਲੀ ਵਿਚ ਉਚਾਰਿਆ ਹੋਇਆ ਸਲੋਕ ਜਾਂ ਦੋਹਰਾ। ਇਸ ਵਿਚ ਅੱਖਰ 'ਦ' ਦੇ ਥਾਂ ਅੱਖਰ 'ਡ' ਪਰਧਾਨ ਹੈ।" Gist: "southern"; a salok or doha in the speech of the Multan region, where ਡ stands for ਦ.
- FDK (Ang 80): "ਡਖਣਾ ਛੰਤ ਕੀ ਜਾਤੀ ਹੈ। ਲੰਮੇ ਦੇਸ ਮੇਂ ਦਕਾਰ ਦੀ ਥਾਂ ਡਡਾ ਅਖਰ ਬੋਲਤੇ ਹੈਂ…" Gist: a kind of chhant; in the Lahnda country ਡ is spoken for ਦ.
- FDK, end of Maru Vaar M5 (Ang 1094): "ਇਸ ਮੇਂ ਲੰਮੇ ਦੇਸ ਕੀ ਬੋਲੀ ਹੈ … ਇਸੀ ਕਰ ਡਖਣੇ ਕੀ ਵਾਰ ਕਹੀਤੀ ਹੈ।" Gist: it is in the speech of the Lahnda country, hence "the Vaar of Dakhne".
- Search snippet only — Granthi to verify: the Encyclopaedia of Sikhism (via SikhiWiki) says the 69 Dakhne saloks of Guru Arjan are set three to each of the 23 pauris of the Maru Vaar, and that "Ḍakhaṇe is not the name of any language but of a style of song-verse of that region". [sikhiwiki.org/index.php/Dakhane](https://www.sikhiwiki.org/index.php/Dakhane), [eos.learnpunjabi.org/DAKHANE.html](https://eos.learnpunjabi.org/DAKHANE.html)

**Where sources differ.** Sahib Singh frames it as speech ("ਬੋਲੀ"). Faridkot frames it as both a
chhant type and a dialect. The encyclopaedia snippet frames it as a song style of that region, not a
language. The suggested gloss covers both readings.

**Recommended ruling.** Change.

**Suggested wording.** `"southern": saloks in the speech of the Multan region, where ਡ is said for ਦ`

**Confidence.** high

### G-18 · Anjulian
**Finding.** "Cupped hands" is right as the literal sense. "(offering)" turns it the wrong way: Sahib
Singh reads the cupped palms as held out to *ask*, a petition made with joined hands. Faridkot calls it
a type of metre.

**Evidence.**
- SS on `ਮਾਰੂ ਅੰਜੁਲੀ ਮਹਲਾ ੫ ਘਰੁ ੭` (Ang 1007): "ਅੰਜੁਲੀ = ਬੁੱਕ, (ਆਪਣੇ ਇਸ਼ਟ ਪਾਸੋਂ ਖ਼ੈਰ ਮੰਗਣ ਲਈ ਅੱਡਿਆ ਹੋਇਆ ਬੁੱਕ), ਦੋਵੇਂ ਹੱਥ ਜੋੜ ਕੇ ਕੀਤੀ ਹੋਈ ਅਰਜ਼ੋਈ।" Gist: cupped palms held out to beg alms of the Beloved; a petition with both hands joined.
- SS elsewhere (Ang 171): "ਅੰਜੁਲੀ = {अंजलिः ਬੁੱਕ। …} ਹੱਥ ਜੋੜ ਕੇ ਅਰਦਾਸ।" Gist: prayer with joined hands.
- FDK (Ang 1007): "ਅੰਜੁਲੀ ਏਹ ਇਕ ਛੰਦ ਕੀ ਜਾਤੀ ਹੈ।" Gist: a kind of metre. FDK (`ਮਾਰੂ ਮਹਲਾ ੫ ਘਰੁ ੮ ਅੰਜੁਲੀਆ`, Ang 1019): "ਅੰਜੁਲੀਆ ਏਹ ਭੀ ਏਕ ਛੰਦ ਕੀ ਚਾਲ ਹੈ।" Gist: also a metrical gait.

**Where sources differ.** Sahib Singh gives the meaning (a petition). Faridkot gives the form (a metre).

**Recommended ruling.** Change.

**Suggested wording.** `"cupped hands": a petition made with joined palms`

**Confidence.** high

### G-19 · Gatha
**Finding.** Sahib Singh gives two senses: (1) an ancient literary Prakrit that mixes Sanskrit, Pali and
other speech, and (2) "praise" or "a religious verse" (Sanskrit गाथा, from गै "to sing"). The Bani uses
the word in sense (2) inside its own text. "A form in the Gatha/Sahaskriti register" is opaque.

**Evidence.**
- SS arth on `ਮਹਲਾ ੫ ਗਾਥਾ` (line 58118, Ang 1360): "ਗਾਥਾ = ਇਕ ਪ੍ਰਾਚੀਨ ਪ੍ਰਾਕ੍ਰਿਤ ਭਾਸ਼ਾ ਜਿਸ ਵਿਚ ਸੰਸਕ੍ਰਿਤ ਪਾਲੀ ਅਤੇ ਹੋਰ ਬੋਲੀਆਂ ਦੇ ਸ਼ਬਦ ਲਿਖੇ ਹੋਏ ਮਿਲਦੇ ਹਨ। … ਗਾਥਾ = ਉਸਤਤ, ਸਿਫ਼ਤ-ਸਾਲਾਹ (गाथा = a religious verse. गै = to sing)।" Gist: an ancient Prakrit with Sanskrit, Pali and other words; also "praise".
- SS translation of the heading: "ਗੁਰੂ ਅਰਜਨਦੇਵ ਜੀ ਦੀ ਬਾਣੀ 'ਗਾਥਾ' (ਕਥਾ)". Gist: the Bani "Gatha" (a telling).
- Use inside the Bani: `ਗਾਥਾ ਗਾਵੰਤਿ ਨਾਨਕ…` (Ang 1361), with SS arth "ਗਾਥਾ = ਸਿਫ਼ਤ-ਸਾਲਾਹ" (praise).

**Where sources differ.** None among those checked. Faridkot has no gloss on the heading.

**Recommended ruling.** Change.

**Suggested wording.** `"a song of praise", in an old literary tongue mixing Sanskrit and Prakrit`

**Confidence.** high

### G-20 · Funhe
**Finding.** Sahib Singh gives the meaning directly. ਫੁਨਹੇ comes from Sanskrit पुनः ("again, again
and again"; Prakrit ਫੁਨਿ). It names a chhant in which one word recurs in every stanza; here the word is
ਹਰਿਹਾਂ. The corpus confirms this: 19 lines of the section open with ਹਰਿਹਾਂ, for example
`ਹਰਿਹਾਂ ਮਸਤਕਿ ਹੋਵੈ ਭਾਗੁ ਤ ਸਾਜਨੁ ਪਾਈਐ ॥੨॥` (line 58188, Ang 1361).

**Evidence.**
- SS arth on `ਫੁਨਹੇ ਮਹਲਾ ੫` (line 58179, Ang 1361): "ਫੁਨਹੇ = (पुनः ਪੁਨਹ, ਮੁੜ ਮੁੜ, ਫਿਰ। ਇਸ ਦਾ ਪ੍ਰਾਕ੍ਰਿਤ-ਰੂਪ ਬਾਣੀ ਵਿਚ 'ਫੁਨਿ' ਆਇਆ ਹੈ) ਉਹ 'ਛੰਤ' ਜਿਸ ਦੇ ਹਰੇਕ 'ਬੰਦ' ਵਿਚ ਕੋਈ ਇਕੋ ਲਫ਼ਜ਼ 'ਫੁਨਿ' (ਮੁੜ ਮੁੜ) ਆਇਆ ਹੈ। ਇਸ ਛੰਤ ਦੇ ਬੰਦਾਂ ਵਿਚ ਲਫ਼ਜ਼ 'ਹਰਿਹਾਂ' ਮੁੜ ਮੁੜ ਆਉਂਦਾ ਹੈ।" Gist: from "again"; a chhant in each stanza of which one word recurs; here ਹਰਿਹਾਂ.
- SS (Ang 1104 arth) calls ਹਰਿਹਾਂ a metrical filler: "…ਜਿਵੇਂ 'ਫੁਨਹੇ' ਦੀ ਬਾਣੀ ਵਿਚ ਲਫ਼ਜ਼ 'ਹਰਿਹਾਂ' ਹੈ". Gist: like ਹਰਿਹਾਂ in Funhe, a word that fills the metre.
- FDK (end of Gatha, Ang 1361): "ਇਸ ਛੰਦ ਕਾ ਨਾਮੁ ਫੁਨਹੇ ਹੈ।" Gist: the metre is named Funhe. It also tells that Guru Arjan recited it at a wedding at the village of Mau ("ਮੌ ਨਾਮ ਨਗਰ ਮੇਂ ਬਿਵਾਹ ਕੇ ਸਮੇਂ").

**Where sources differ.** They agree that it is a metre or chhant. Only Faridkot gives the occasion. That
story should not appear in the gloss.

**Recommended ruling.** Change.

**Suggested wording.** `"again and again": verses in which one word recurs, here ਹਰਿਹਾਂ`

**Confidence.** high

### G-21 · Chaubole
**Finding.** Sahib Singh says only that ਚਉਬੋਲਾ is the name of a chhant (11 stanzas here). Faridkot
offers two readings: "a particular metre", or "spoken to/by four" (Samman, Musan, Jamal, Patang, the
names that appear in the stanzas). The draft "four-word/four-voiced verses?" half-echoes Faridkot's
second reading. Sahib Singh does not support it: he reads ਸੰਮਨ in the first line as "O generous-hearted
one", not as a person's name.

**Evidence.**
- SS arth on `ਚਉਬੋਲੇ ਮਹਲਾ ੫` (line 58273, Ang 1363): "ਚਉਬੋਲਾ = ਇਕ ਛੰਤ ਦਾ ਨਾਮ ਹੈ। ਇਥੇ 'ਚਉਬੋਲਾ' ਛੰਤ ਦੇ ੧੧ ਬੰਦ ਹਨ।" Gist: the name of a chhant; 11 stanzas here.
- FDK (Ang 1363): "ਚਉਬੋਲੇ ਛੰਦ ਵਸੇਸ ਹੈਂ; ਵਾ ਜੋ ਚਾਰ ਭਗਤੋਂ ਨੇ ਬੋਲੇ ਹੈਂ ਸੋਈ ਸ੍ਰੀ ਗੁਰੂ ਜੀ ਨੇ ਉਚਾਰਨ ਕੀਏ ਹੈਂ।" Gist: a particular metre; or, what four devotees said, the Guru uttered. FDK (Ang 1364): "ਸੰਮਨ ੧, ਮੂਸਨ ੨, ਜਮਾਲ ੩, ਪਤੰਗ ੪, ਇਨ ਚਾਰੋਂ ਭਗਤੋਂ ਕੇ ਬਚਨ…" Gist: the words of these four devotees.
- SS on `ਸੰਮਨ ਜਉ ਇਸ ਪ੍ਰੇਮ ਕੀ ਦਮ ਕ੍ਯ੍ਯਿਹੁ ਹੋਤੀ ਸਾਟ ॥` (line 58275, Ang 1363): "ਸੰਮਨ = ਹੇ ਸੰਮਨ! ਹੇ ਮਨ ਵਾਲੇ ਬੰਦੇ! … ਹੇ ਦਾਨੀ ਮਨੁੱਖ!" Gist: he gives both "O Samman" and "O generous one", and translates with the second.
- Search snippet only — Granthi to verify: the Encyclopaedia of Sikhism entries for Samman, Musan and Patang describe the first couplets as addressed to Bhai Samman and name the four. [eos.learnpunjabi.org/SAMMAN%20BHAI.html](https://eos.learnpunjabi.org/SAMMAN%20BHAI.html), [sikhiwiki.org/index.php/Chauboley](https://www.sikhiwiki.org/index.php/Chauboley)

**Where sources differ.** Sahib Singh: only a metre, and ਸੰਮਨ may be a vocative of quality. Faridkot
and the encyclopaedia snippets: four named persons. "Four" is literally in the word (ਚਉ + ਬੋਲ), but
what it counts is disputed.

**Recommended ruling.** Change. Gloss only the agreed point.

**Suggested wording.** `the name of a metre (chhant)`. If the Granthi wants more: `the name of a metre; some commentators connect the "four" (ਚਉ) with four persons named in it`

**Confidence.** medium

---

## 6. Bhagat attribution findings

The four items still open in the dataset are set out, with their evidence, on the sggs-data page:
[`RECOMMENDATIONS.md`](https://github.com/Algorythmos-AI/sggs-data/pull/18).

- **A-07:** credit line 53935 to Bhagat Surdas Ji. SS says the line is Surdas's, and that it is counted as a whole
  shabad, which is why the printed count reaches ੮.
- **A-08:** split the sections, as proposed.
- **A-10:** fix the three labels, as proposed.
- **A-11:** credit the heading to the first Bhagat of the run, and give line 14771 the same ruling.

The changes that 1.1.0 already made are confirmed below.

### A-01 · Ang 695, lines 30081–30091: Bhagat Sain Ji

**Finding.** The dataset credits these lines to Bhagat Sain Ji (before 1.1.0 they carried Bhagat Trilochan Ji). That credit is right.

- The lines open with their own label: `ਸ੍ਰੀ ਸੈਣੁ ॥` (line 30081, Ang 695).
- They close with Sain's signature: `ਸੈਨੁ ਭਣੈ ਭਜੁ ਪਰਮਾਨੰਦੇ ॥੪॥੨॥` (line 30091, Ang 695).
- Trilochan's own shabad ends earlier, at `ਬਦਤਿ ਤ੍ਰਿਲੋਚਨ ਰਾਮ ਜੀ ॥੬॥੧॥` (line 30080, Ang 695).

**Evidence.**
- **ShabadOS 4.8.7.**
  - Lines 30081–30091 form one shabad (BaniDB id 2640), writer **Bhagat Sain Ji**.
  - Line 30081 has line type "Sirlekh" (heading).
  - Trilochan's shabad is a separate record (BaniDB id 2639).
- **Prof. Sahib Singh, Darpan, note at line 30091 (via ShabadOS 4.8.7).** "ਜਿਸ ਦੀ ਉਸਤਤਿ ਇੱਥੇ ਕਰ ਰਹੇ ਹਨ, ਉਸ ਵਾਸਤੇ ਸੈਣ ਜੀ ਨੇ ਹੇਠ-ਲਿਖੇ ਲਫ਼ਜ਼ ਵਰਤੇ ਹਨ-ਕਮਲਾਪਤੀ, ਹਰਿ, ਰਾਜਾ ਰਾਮ, ਨਿਰੰਜਨ, ਪੂਰਨ, ਪਰਮਾਨੰਦ, ਮਦਨ-ਮੂਰਤਿ, ਭੈ-ਤਾਰਿ, ਗੋਬਿੰਦ।"
  - Gist: Sahib Singh treats the shabad as Sain's own. He lists the names Sain uses for the One he praises, to answer a critic who claimed the hymn was an aarti to Ramanand.
- **Prof. Sahib Singh, note at line 30080.** "ਭਗਤ ਤ੍ਰਿਲੋਚਨ ਜੀ ਜਾਤਿ ਦੇ ਬ੍ਰਾਹਮਣ ਸਨ।"
  - Gist: his Trilochan note sits on line 30080. That is, he closes Trilochan's shabad there.
- **Faridkot Teeka, line 30080 (via ShabadOS 4.8.7).** "☬ਸ੍ਰੀ ਸੈਣ ਭਗਤ ਜੀ ਸ੍ਰੀ ਅਕਾਲ ਪੁਰਖ ਜੀ ਕੇ ਸਨਮੁਖ ਆਰਤੀ ਕਰ ਕੇ ਬੇਨਤੀ ਕਰਤੇ ਹੈਂ:"
  - Gist: the Teeka introduces the next shabad as Bhagat Sain's prayer, offered as an aarti.
- **Faridkot Teeka, line 30091.** "ਸ੍ਰੀ ਸੈਣ ਜੀ ਕਹਤੇ ਹੈਂ:"
  - Gist: "Sri Sain Ji says".
- **Corpus facts.**
  - All 11 lines carry `author` Bhagat Sain Ji.
  - In the held 1.3.0 build they also have their own comp 5381, and line 30081 is a heading. This is the A-10 fix; in 1.1.0 the lines are still in comp 2749.
  - The running total ॥੪॥੨॥ counts this shabad as the second in the Dhanasri Bhagat-bani run that begins with Trilochan.

**Where sources differ.** None found on authorship.

**Recommended ruling.** Confirm. The printed label, the signature ਸੈਨੁ ਭਣੈ, ShabadOS, Sahib Singh and the Faridkot Teeka all agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### A-02 · Ang 695, lines 30092–30098: Bhagat Pipa Ji

**Finding.** The dataset credits these lines to Bhagat Pipa Ji (before 1.1.0 they carried Bhagat Trilochan Ji). That credit is right.

- Label: `ਪੀਪਾ ॥` (line 30092, Ang 695).
- Signature: `ਪੀਪਾ ਪ੍ਰਣਵੈ ਪਰਮ ਤਤੁ ਹੈ ਸਤਿਗੁਰੁ ਹੋਇ ਲਖਾਵੈ ॥੨॥੩॥` (line 30098, Ang 695).

**Evidence.**
- **ShabadOS 4.8.7.** One shabad (BaniDB id 2641), writer **Bhagat Pipa Ji**. ShabadOS types the label line `ਪੀਪਾ ॥` as "Pankti", not "Sirlekh"; the Sain and Dhanna labels are typed "Sirlekh".
- **Prof. Sahib Singh, Darpan, note at line 30098 (via ShabadOS 4.8.7).** "ਇਸ ਸ਼ਬਦ ਵਿਚ ਭਗਤ ਪੀਪਾ ਜੀ ਮੂਰਤੀ-ਪੂਜਾ ਦਾ ਖੰਡਨ ਕਰਦੇ ਹਨ"
  - Gist: "In this shabad Bhagat Pipa Ji refutes idol-worship."
- **Faridkot Teeka, line 30091.** "☬ਸ੍ਰੀ ਪੀਪਾ ਭਗਤ ਟੋਡਰਪੁਰ ਕੇ ਰਾਜਾ ਸੇ ਪੁਨਾ ਰਾਮਾਨੰਦ ਜੀ ਕੇ ਸਿਖ ਭਏ।"
  - Gist: the Teeka introduces the next shabad as Bhagat Pipa's, calling him a king of Todarpur who became Ramanand's disciple.
- **Faridkot Teeka, line 30098.** "ਸ੍ਰੀ ਪੀਪਾ ਜੀ ਕਹਤੇ ਹੈਂ:"
  - Gist: "Sri Pipa Ji says".
- **Corpus facts.** All 7 lines carry Bhagat Pipa Ji. In the held build they have comp 5382 and line 30092 is a heading (the A-10 fix).

**Where sources differ.** None on authorship. One point outside this item, for R-18: the Faridkot Teeka calls Pipa a king of "ਟੋਡਰਪੁਰ", while the roster's life paragraph (from the EoS) names Gagraun.

**Recommended ruling.** Confirm. The label, the signature ਪੀਪਾ ਪ੍ਰਣਵੈ, ShabadOS, Sahib Singh and Faridkot all agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### A-03 · Ang 695, lines 30099–30109: Bhagat Dhanna Ji

**Finding.** The dataset credits these lines to Bhagat Dhanna Ji (before 1.1.0 they carried Bhagat Trilochan Ji). That credit is right.

- Label: `ਧੰਨਾ ॥` (line 30099, Ang 695).
- Signature: `ਜਨੁ ਧੰਨਾ ਲੇਵੈ ਮੰਗੀ ॥੨॥੪॥` (line 30109, Ang 695).

**Evidence.**
- **ShabadOS 4.8.7.** One shabad (BaniDB id 2642), writer **Bhagat Dhanna Ji**. The label line is typed "Sirlekh".
- **Prof. Sahib Singh, Darpan, note at line 30109 (via ShabadOS 4.8.7).** "'ਰਹਾਉ' ਦੀ ਤੁਕ ਅਤੇ ਬਾਕੀ ਦੇ ਸਾਰੇ ਸ਼ਬਦ ਨੂੰ ਗਹੁ ਨਾਲ ਪੜ੍ਹਿਆਂ ਭੀ ਇਹੀ ਗੱਲ ਸਿੱਧ ਹੁੰਦੀ ਹੈ ਕਿ ਪ੍ਰਭੂ ਦੇ ਦਰ ਤੋਂ ਰੋਜ਼ਾਨਾ ਜੀਵਨ ਦੀਆਂ ਲੋੜਾਂ ਹੀ ਮੰਗ ਰਹੇ ਹਨ।"
  - Gist: the shabad asks the Lord for the needs of daily life.
  - The same note goes on: "ਭਗਤ-ਬਾਣੀ ਨੂੰ ਗੁਰਮਤਿ ਦੇ ਵਿਰੁੱਧ ਸਮਝਣ ਵਾਲਾ ਵੀਰ ਭਗਤ ਧੰਨਾ ਜੀ ਬਾਰੇ ਇਉਂ ਲਿਖਦਾ ਹੈ". That is, he discusses the shabad as Bhagat Dhanna's.
- **Faridkot Teeka, line 30098.** "☬ਸ੍ਰੀ ਧੰਨਾ ਭਗਤ ਜੀ ਸ੍ਰੀ ਅਕਾਲ ਪੁਰਖ ਜੀ ਕੇ ਸਨਮੁਖ ਆਰਤੀ ਕਰ ਕੇ ਜਾਚਨਾ ਕਰਤੇ ਹੈਂ:"
  - Gist: the Teeka introduces Bhagat Dhanna's petition.
- **Faridkot Teeka, line 30109.** "ਸ੍ਰੀ ਧੰਨਾ ਜੀ ਕਹਤੇ ਹੈਂ:"
  - Gist: "Sri Dhanna Ji says".
- **Corpus facts.** All 11 lines carry Bhagat Dhanna Ji. In the held build they have comp 5383 and line 30099 is a heading (the A-10 fix).

**Where sources differ.** None found.

**Recommended ruling.** Confirm. The label, the signature ਜਨੁ ਧੰਨਾ, ShabadOS, Sahib Singh and Faridkot all agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### A-04 · Angs 487–488, comps 1824 and 1825: Bhagat Dhanna Ji and Guru Arjan Dev Ji (M5)

**Finding.** Three shabads stand under one printed heading, `ਆਸਾ ਬਾਣੀ ਭਗਤ ਧੰਨੇ ਜੀ ਕੀ` (line 22041, Ang 487).

- The first and third are Bhagat Dhanna Ji's.
- The second carries its own heading, `ਮਹਲਾ ੫ ॥` (line 22053, Ang 487), and is Guru Arjan Dev Ji's.

Comp 1824 (12 lines, 22041–22052) is all Dhanna's; before 1.1.0 it carried Bhagat Ravidas Ji. Comp 1825 (19 lines) holds **two** shabads. The line-by-line check of comp 1825 finds every line's `author` correct:

| Lines | Ang | First and last line, verbatim | `author` in the dataset | ShabadOS writer (BaniDB id) | Verdict |
|---|---|---|---|---|---|
| 22053–22063 (11 lines) | 487–488 | `ਮਹਲਾ ੫ ॥` … `ਮਿਲੇ ਪ੍ਰਤਖਿ ਗੁਸਾਈਆ ਧੰਨਾ ਵਡਭਾਗਾ ॥੪॥੨॥` | Guru Arjan Dev Ji (M5) | Guru Arjan Dev Ji (1816) | correct |
| 22064–22071 (8 lines) | 488 | `ਰੇ ਚਿਤ ਚੇਤਸਿ ਕੀ ਨ ਦਯਾਲ ਦਮੋਦਰ ਬਿਬਹਿ ਨ ਜਾਨਸਿ ਕੋਈ ॥` … `ਕਹੈ ਧੰਨਾ ਪੂਰਨ ਤਾਹੂ ਕੋ ਮਤ ਰੇ ਜੀਅ ਡਰਾਂਹੀ ॥੩॥੩॥` | Bhagat Dhanna Ji | Bhagat Dhanna Ji (1817) | correct |

The split falls exactly between line 22063 (॥੪॥੨॥) and line 22064 (the third shabad's opening Rahao line). The pack's count ("8 lines Bhagat Dhanna Ji and 11 lines Guru Arjan Dev Ji") matches.

**Evidence.**
- **The first shabad is Dhanna's.**
  - Heading (line 22041), and the closing signature `ਧੰਨੈ ਧਨੁ ਪਾਇਆ ਧਰਣੀਧਰੁ ਮਿਲਿ ਜਨ ਸੰਤ ਸਮਾਨਿਆ ॥੪॥੧॥` (line 22052, Ang 487).
  - ShabadOS: BaniDB id 1815, writer Bhagat Dhanna Ji.
- **Prof. Sahib Singh, Darpan, note at line 22063 (via ShabadOS 4.8.7).** "ਇਸ ਦਾ ਭਾਵ ਇਹ ਹੈ ਕਿ ਇਹਨਾਂ ਤਿੰਨਾਂ ਸ਼ਬਦਾਂ ਵਿਚੋਂ ਇਹ ਦੂਜਾ ਸ਼ਬਦ ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਦਾ ਆਪਣਾ ਉਚਾਰਿਆ ਹੋਇਆ ਹੈ। ਇਸ ਵਿਚ ਉਹਨਾਂ ਨੇ ਲਫ਼ਜ਼ 'ਨਾਨਕ' ਅਖ਼ੀਰ ਤੇ ਨਹੀਂ ਵਰਤਿਆ।"
  - Gist: of the three shabads, the second is Guru Arjan's own. He did not sign it ਨਾਨਕ.
  - The same note adds: "ਸਿਰ-ਲੇਖ "ਮਹਲਾ ੫" ਇਸ ਖ਼ਿਆਲ ਬਾਰੇ ਕਿਸੇ ਸ਼ੱਕ ਦੀ ਗੁੰਜਾਇਸ਼ ਨਹੀਂ ਰਹਿਣ ਦੇਂਦਾ". That is, the ਮਹਲਾ ੫ heading leaves no room for doubt.
- **Prof. Sahib Singh, note at line 22071.** "ਇਹ ਤਿੰਨੇ ਸ਼ਬਦ ਰਾਗ ਆਸਾ ਵਿਚ ਹਨ। ਪਹਿਲਾ ਤੇ ਤੀਜਾ ਸ਼ਬਦ ਧੰਨਾ ਜੀ ਦੇ ਹਨ।"
  - Gist: the first and third shabads are Dhanna's.
- **Prof. Sahib Singh, note at line 22052.** "ਗੁਰੂ ਅਰਜਨ ਸਾਹਿਬ ਜੀ ਨੇ ਅਗਲਾ ਸ਼ਬਦ ਆਪਣੇ ਵਲੋਂ ਉਚਾਰ ਕੇ ਦਰਜ ਕੀਤਾ ਹੈ।"
  - Gist: Guru Arjan composed the next shabad himself and entered it here, to make plain the sense of Dhanna's closing line.
- **Faridkot Teeka, line 22052.** "☬ਸ੍ਰੀ ਗੁਰੂ ਜੀ ਭਗਤੋਂ ਕੀ ਬਾਣੀ ਸੇ ਅਪਨੀ ਬਾਣੀ ਕੀ ਅਭੇਦਤਾ ਜਨਾਉਤੇ ਹੂਏ ਧੰਨੇ ਕੋ ਸਿਰੋਪਾਉ ਰੂਪ ਸਬਦ ਬਾਣੀ ਮੇਂ ਦੇਤੇ ਭਏ।"
  - Gist: the Guru gives Dhanna a shabad as a robe of honour, showing the oneness of his bani with the Bhagats'. The Teeka also reads the second shabad as the Guru's.
- **Corpus facts.**
  - The second shabad names Namdev, Kabir, Ravidas and Sain, then Dhanna: `ਇਹ ਬਿਧਿ ਸੁਨਿ ਕੈ ਜਾਟਰੋ ਉਠਿ ਭਗਤੀ ਲਾਗਾ ॥` (line 22062, Ang 488).
  - Its use of ਧੰਨਾ in the last line is a name, not a signature. Sahib Singh's note says so.
  - The running totals ॥੪॥੧॥, ॥੪॥੨॥ and ॥੩॥੩॥ number the three shabads in one series.
  - **Grouping observation (not authorship).** Comp 1825 spans two ShabadOS shabads (BaniDB 1816 and 1817). The third shabad has no heading of its own, so it was grouped with the M5 shabad before it. This is the same kind of grouping matter as A-10, for engineering.

**Where sources differ.** None found on any line's authorship.

**Recommended ruling.** Confirm. Comp 1824 (12 lines) is Bhagat Dhanna Ji's. In comp 1825, lines 22053–22063 are Guru Arjan Dev Ji's and lines 22064–22071 are Bhagat Dhanna Ji's. The printed ਮਹਲਾ ੫ heading, ShabadOS, Sahib Singh and Faridkot agree line for line.

**Suggested wording (if Change).** Not applicable to authorship. If the Granthi wishes, add a note for engineering: "comp 1825 holds two shabads (BaniDB 1816 and 1817); split at line 22064, as A-10 does at Ang 695."

**Confidence.** high

### A-05 · Ang 858, lines 36567–36578 (comp 3457): Bhagat Sadhna Ji

**Finding.** The dataset credits this shabad to Bhagat Sadhna Ji (before 1.1.0 it carried Bhagat Ravidas Ji). That credit is right.

- It has its own heading: `ਬਾਣੀ ਸਧਨੇ ਕੀ ਰਾਗੁ ਬਿਲਾਵਲੁ` (line 36567, Ang 858).
- It closes with Sadhna's signature: `ਅਉਸਰ ਲਜਾ ਰਾਖਿ ਲੇਹੁ ਸਧਨਾ ਜਨੁ ਤੋਰਾ ॥੪॥੧॥` (line 36578, Ang 858).
- Ravidas's preceding shabad ends at `ਜੈਸੇ ਪੁਰੈਨ ਪਾਤ ਰਹੈ ਜਲ ਸਮੀਪ ਭਨਿ ਰਵਿਦਾਸ ਜਨਮੇ ਜਗਿ ਓਇ ॥੩॥੨॥` (line 36566, Ang 858).

**Evidence.**
- **ShabadOS 4.8.7.** Lines 36567–36578 form one shabad (BaniDB id 3219), writer **Bhagat Sadhna Ji**. Ravidas's shabad is BaniDB id 3218.
- **Prof. Sahib Singh, Darpan, note at line 36578 (via ShabadOS 4.8.7).** "ਸ਼ਬਦ ਦਾ ਭਾਵ ਤਾਂ ਬੜਾ ਸਾਫ਼ ਸਿੱਧਾ ਹੈ ਕਿ ਭਗਤ ਸਧਨਾ ਜੀ ਪਰਮਾਤਮਾ ਅੱਗੇ ਅਰਦਾਸ ਕਰ ਕੇ ਆਖਦੇ ਹਨ-ਹੇ ਪ੍ਰਭੂ!"
  - Gist: the meaning is plain; Bhagat Sadhna Ji prays to God.
- **Faridkot Teeka, line 36566.** "☬ਪ੍ਰਯਾਗ ਮੇਂ ਕਸਾਈ ਜਾਤੀ ਕੇ ਭਗਤ ਸਧਨਾ ਜੀ ਕੋ ਠਾਕੁਰ ਪੂਜਾ ਕਰਤੇ ਦੇਖ ਕਰ"
  - Gist: the Teeka opens the next shabad with the story of Bhagat Sadhna.
- **Faridkot Teeka, line 36578.** "ਸ੍ਰੀ ਸਧਨਾਂ ਜੀ ਕਹਤੇ ਹੈਂ:"
  - Gist: "Sri Sadhna Ji says".
- **Corpus facts.** All 12 lines (2 heading lines and 10 verses) carry Bhagat Sadhna Ji in comp 3457, which is separate from Ravidas's comp 3455.

**Where sources differ.** None on authorship. The background story differs, but that does not touch this ruling. Faridkot places Sadhna at Prayag and tells the tower story. Sahib Singh quotes that story from Pandit Tara Singh and the modern teekas, and then questions it. The roster (R-19) follows the EoS (Sehwan, Sirhind).

**Recommended ruling.** Confirm. The printed heading names Sadhna, the shabad signs ਸਧਨਾ, and ShabadOS, Sahib Singh and Faridkot all agree.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### A-06 · Ang 1253, lines 53925–53934 (comp 4846): Bhagat Parmanand Ji

**Finding.** The dataset credits lines 53925–53934 to Bhagat Parmanand Ji (before 1.1.0 they carried Bhagat Namdev Ji). That credit is right.

- The shabad is headed only `ਸਾਰੰਗ ॥` (line 53925, Ang 1253).
- It signs `ਪਰਮਾਨੰਦ ਸਾਧਸੰਗਤਿ ਮਿਲਿ ਕਥਾ ਪੁਨੀਤ ਨ ਚਾਲੀ ॥੩॥੧॥੬॥` (line 53934, Ang 1253).
- Namdev's last shabad closes before it: `ਨਾਮਦੇਵ ਜਾ ਕੇ ਜੀਅ ਐਸੀ ਤੈਸੋ ਤਾ ਕੈ ਪ੍ਰੇਮ ਪ੍ਰਗਾਸ ॥੨॥੩॥` (line 53924, Ang 1253).

**Evidence.**
- **ShabadOS 4.8.7.** Lines 53925–53934 belong to BaniDB id 4531, writer **Bhagat Parmanand Ji**. Namdev's shabad is BaniDB id 4530.
- **Faridkot Teeka, line 53934 (via ShabadOS 4.8.7).** "ਰਾਮਾਨੰਦ ਜੀ ਕੇ ਗੁਰ ਭਾਈ ਪਰਮਾਨੰਦ ਜੀ ਕਹਿਤੇ ਹੈਂ:"
  - Gist: "Parmanand Ji, Ramanand's fellow disciple, says".
- **Prof. Sahib Singh, Darpan, note at line 53934.** "ਭਗਤ-ਬਾਣੀ ਦੇ ਵਿਰੋਧੀ ਵੀਰ ਨੇ ਪਰਮਾਨੰਦ ਜੀ ਅਤੇ ਉਹਨਾਂ ਦੇ ਇਸ ਸ਼ਬਦ ਬਾਰੇ ਇਉਂ ਲਿਖਿਆ ਹੈ:"
  - Gist: Sahib Singh discusses "Parmanand Ji and this shabad of his", answering a critic of the Bhagat-bani.
- **Corpus facts.**
  - The ਪਰਮਾਨੰਦ signature is in line 53934.
  - The running total ॥੩॥੧॥੬॥ marks the first shabad of this Bhagat and the sixth of the Sarang Bhagat-bani run.
  - Comp 4846 also contains line 53935 (`ਛਾਡਿ ਮਨ ਹਰਿ ਬਿਮੁਖਨ ਕੋ ਸੰਗੁ ॥`). That line is item A-07 and is outside this item's range.

**Where sources differ.** None on authorship. One point outside this item, for R-20: Faridkot calls Parmanand Ramanand's fellow disciple. The critic whom Sahib Singh quotes says he was a disciple of Vallabhacharya.

**Recommended ruling.** Confirm. The signature ਪਰਮਾਨੰਦ, ShabadOS and both commentaries name Parmanand for lines 53925–53934.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

### A-09 · Angs 923–924, comp 3645 (Ramkali Sadd, 38 lines): Baba Sundar Ji

**Finding.** The dataset credits the Sadd to Baba Sundar Ji (before 1.1.0 it carried Guru Amar Das Ji, M3). That credit is right.

- The heading `ਰਾਮਕਲੀ ਸਦੁ` (line 39543, Ang 923) names no Mahalla.
- The last pauri signs `ਕਹੈ ਸੁੰਦਰੁ ਸੁਣਹੁ ਸੰਤਹੁ ਸਭੁ ਜਗਤੁ ਪੈਰੀ ਪਾਇ ਜੀਉ ॥੬॥੧॥` (line 39580, Ang 924).
- The poem speaks of Guru Amar Das in the third person, for example `ਅੰਤੇ ਸਤਿਗੁਰੁ ਬੋਲਿਆ ਮੈ ਪਿਛੈ ਕੀਰਤਨੁ ਕਰਿਅਹੁ ਨਿਰਬਾਣੁ ਜੀਉ ॥` (line 39569, Ang 923).

**Evidence.**
- **ShabadOS 4.8.7.** BaniDB id 3376, writer **Baba Sundar**, for all aligned lines. Line 39574 did not align, which is a technical gap only.
- **Prof. Sahib Singh, Darpan arth, line 39580 (via ShabadOS 4.8.7).** "ਸੁੰਦਰ ਆਖਦਾ ਹੈ ਕਿ ਹੇ ਸੰਤਹੁ! ਸੁਣੋ, (ਇਸ ਵਾਸਤੇ) ਸਾਰਾ ਜਗਤ (ਗੁਰੂ ਰਾਮਦਾਸ ਜੀ ਦੀ) ਪੈਰੀਂ ਪਿਆ ॥੬॥੧॥"
  - Gist: "Sundar says, hear O saints: the whole world fell at Guru Ram Das Ji's feet."
- **Prof. Sahib Singh, note at line 39550.** "ਇਥੇ ਇਸ ਦਾ ਭਾਵ ਹੈ 'ਰੱਬ ਵੱਲੋਂ ਗੁਰੂ ਅਮਰਦਾਸ ਜੀ ਨੂੰ ਆਇਆ ਹੋਇਆ ਸੱਦਾ'।"
  - Gist: the Sadd is the call that came from God to Guru Amar Das. He is its subject, not its speaker.
- **Faridkot Teeka, line 39580.** "ਸੁੰਦ੍ਰ ਜੀ ਕਹਿਤੇ ਹੈਂ: ਹੇ ਸੰਤੋ ਸੁਣੋਂ!"
  - Gist: "Sundar Ji says: hear, O saints!"
- **Repo.** `sggs-data/pipeline/attribution_ledger.json`, entry `sadu`, records lines 39543–39580 moving from Guru Amar Das Ji (M3) to Baba Sundar Ji. It gives the reason as a tag that "had bled from Guru Amar Das Ji's Anand Sahib".
- **Corpus facts.** 38 lines, comp 3645, all Baba Sundar Ji. Line 39576 names the poet's grandfather's line: `ਮੋਹਰੀ ਪੁਤੁ ਸਨਮੁਖੁ ਹੋਇਆ ਰਾਮਦਾਸੈ ਪੈਰੀ ਪਾਇ ਜੀਉ ॥`.

**Where sources differ.** None found.

**Recommended ruling.** Confirm. The signature ਕਹੈ ਸੁੰਦਰੁ, ShabadOS, Sahib Singh and Faridkot all name Sundar, and the heading names no Mahalla.

**Suggested wording (if Change).** Not applicable.

**Confidence.** high

---

## For the reviewer

The pull request that adds this page lists every item with three boxes: **Approve as recommended**,
**Change** (write the wording you want in a comment, starting with the item number) and **Reject**. Tick
one box per item. A blank item stays undecided, and nothing is switched on for it.

When you have finished, write your name, your role and the date in the sign-off block of the pull request.
An engineer then copies your rulings into the decision lines of `README.md` and records your signature in
its section 10. Each ruling reaches readers only by the route `README.md` section 9 describes.

The T-04 sample of 62 verses is in `t04_karam_sample.csv`, beside this page. Its `class` column holds the
reading from Sahib Singh's arth, and you can correct any row.
