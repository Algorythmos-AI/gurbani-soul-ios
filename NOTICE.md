# Licensing & Attribution Notice

## The scripture
Sri Guru Granth Sahib Ji is sacred scripture. The Gurmukhi text bundled in the app comes from the
`sggs-data` repository, where it was extracted verbatim, with documented and reviewed corrections
only, from a freely circulated Unicode Gurmukhi edition. It is treated with reverence: verbatim,
always cited by Ang, never paraphrased.

## English translation layer
The English translation by Dr. Sant Singh Khalsa is used with attribution for personal,
non-commercial study only. **It is not licensed for distribution.**

TestFlight and App Store builds are distribution. The `personal` database profile embeds the
English layer, so `pipeline/check_release_license.sh` blocks such a build **until** a written
distribution licence is recorded in `ios/Resources/TRANSLATION-LICENSE.md` (fields filled in and
`LICENSED: true`). Until then only the Gurmukhi-only `public` profile ships. CI tests the gate in
both directions.

## Nitnem bani layer

- **Bani membership** (which lines make up Japji Sahib, Rehras Sahib, Sukhmani Sahib, … and in
  what order) comes from the **ShabadOS open database** (github.com/shabados/database, release
  4.8.7). Every Sri Guru Granth Sahib Ji line is resolved to the verified corpus's own line and
  rendered from it; the ShabadOS text is used only as a match key, never displayed.
- **Non-SGGS text** — Sri Dasam Granth banis (Jaap Sahib, Tav-Prasad Savaiye, Benti Chaupai,
  Shabad Hazare Patshahi 10, the Dasam portions of Rehras Sahib) and Ardaas — comes from the same
  ShabadOS dataset, unfolded and labelled by source. It is a separate layer: never mixed into the
  SGGS lines, never cited as an Ang, and it carries no English translation. It ships in a public
  build only after the scholar review recorded in `ios/Resources/NITNEM-REVIEW.md`
  (`REVIEWED: true`).
- **Licence (release 4.8.7, the pinned input).** At tag `4.8.7` the ShabadOS README ("Gurbani and
  Panthic Compositions") states that the texts in its `data` folder, its `build` output and its
  releases — the SQLite this app's Nitnem layer is built from — are "free of known copyright
  restrictions" and identifies them as being in the **public domain**
  ([Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/)), on the condition
  that "derogatory treatments (including adding to, deleting from, altering of, or adapting) the
  words in a way that distorts or mutilates the original work" are not made. This app renders
  those words verbatim and never edits them. The repository's *code* (not used here) was licensed
  separately at that tag (its README names GPL v3 and its `LICENSE.md` holds CC BY-SA 4.0; the
  project moved to MIT on 2025-01-14). Checked against `github.com/shabados/database` at tag
  `4.8.7` on 2026-09-26. The Ardaas wording follows the SGPC Sikh Rehat Maryada.
- Required in-app attribution: "Bani ordering and Sri Dasam Granth / Ardaas text via the ShabadOS
  open database. Sri Guru Granth Sahib Ji text is this project's own verified corpus."

## Bundled in the app (public build)

- **Sant Lipi** (Gurmukhi typeface) — © Shabad OS, SIL Open Font License 1.1; shipped as
  `ios/App/Resources/OFL.txt`.
- **Source Serif 4** (headings) — © Adobe, SIL Open Font License 1.1; shipped as
  `ios/App/Resources/OFL-SourceSerif4.txt`.
- **SQLite** — public domain (vendored amalgamation; provenance in
  `ios/Packages/GurbaniSearchKit/Sources/CSQLite/PROVENANCE.md`).
- **Bani ordering and Sri Dasam Granth / Ardaas text** — via the ShabadOS open database
  (release 4.8.7). Scholar review recorded in `ios/Resources/NITNEM-REVIEW.md`.

## Code
Copyright Algorythmos Pty Ltd. All rights reserved unless separately licensed.

## Attribution line shown in the app
“English translation by Dr. Sant Singh Khalsa (sourced via BaniDB).”
