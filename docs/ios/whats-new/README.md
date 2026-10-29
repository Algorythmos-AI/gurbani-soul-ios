# What's New, version by version

The App Store "What's New" text of every Gurbani Soul version, one file per version
(`<version>.md`), exactly as pasted into App Store Connect. The current version's text also sits in
[`../app-store-listing.md`](../app-store-listing.md#whats-new), which `make asc-diff` compares
against App Store Connect.

## Rules for a new version
- Write `<version>.md` in the release PR (or the release-records PR that follows the tag), and
  copy the same text into the listing's What's New section.
- It covers everything since **the last version on the App Store**, not since the last build: a
  version that was never submitted (1.4.3, 1.4.9, 1.5.0) folds into the next one.
- What changed for the reader, in plain words, and nothing the build does not do. Limit 4000
  characters. It always ends with: "The text of Sri Guru Granth Sahib Ji is unchanged."
- Never edit an older file's text; add a note above the text block if its status changes
  (for example "never submitted").

| Version | Status |
|---|---|
| [1.5.1](1.5.1.md) | ready for submission (covers 1.4.9 and 1.5.0) |
| [1.5.0](1.5.0.md) | never submitted; superseded by 1.5.1 |
| [1.4.7](1.4.7.md) | App Store |
| [1.4.4](1.4.4.md) | App Store |
| [1.4.3](1.4.3.md) | uploaded, never submitted; its text carried into 1.4.4 |
| [1.4.0](1.4.0.md) | App Store (the first update) |
| 1.3.10 | App Store (the first version: App Store Connect has no What's New for it) |
