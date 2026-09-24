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

## Code
Copyright Algorythmos Pty Ltd. All rights reserved unless separately licensed.

## Attribution line shown in the app
“English translation by Dr. Sant Singh Khalsa (sourced via BaniDB).”
