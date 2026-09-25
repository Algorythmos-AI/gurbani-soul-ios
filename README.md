# Gurbani Soul — iOS

The iPhone and iPad app for reading, searching and studying **Sri Guru Granth Sahib Ji**, fully
offline. Built by Algorythmos.

Every line the app shows is the verbatim Gurmukhi of the Granth, cited by Ang. The app bundles its
own copy of the scripture database and refuses to open one whose checksum does not match the
certified manifest.

## How it fits together

| Input | Owner | How it arrives |
|---|---|---|
| Scripture database | [`sggs-data`](https://github.com/Algorythmos-AI/sggs-data) | `dataset.lock.json` pins a commit + sha256; `make dataset` installs it, verified |
| iOS database builder (`pipeline/build_ios_db.py`) | `sggs-data` | vendored, pinned in `vendor.lock.json` |
| Golden contract (`contract/`), contributors roster, brand tokens (`docs/brand/tokens.json`) | the platform (web + API) | vendored, pinned in `vendor.lock.json` |

The Swift search/verify/reader core is held byte-for-byte to the platform's API behaviour by the
golden contract (`make parity`). The app's `MARKETING_VERSION` always equals the platform release
whose contract it was tested against — one version number across web, API and app.

## Getting started

```bash
make dataset          # the pinned scripture database → db/sggs.sqlite (sha256-verified)
make ios-db-repair    # derive the bundled iOS database and check it against its manifest
make project          # generate ios/App/SGGS.xcodeproj (XcodeGen)
open ios/App/SGGS.xcodeproj
```

`make help` lists everything. `make gates` runs the checks CI runs without a Mac; `make parity` runs
the Swift parity suite.

## Updating an input

- **A new platform release:** `make vendor-sync-platform REF=vX.Y.Z`, set `MARKETING_VERSION` to
  `X.Y.Z` in `ios/App/project.yml`, and open a PR. CI proves every vendored file matches the
  platform at that commit.
- **A new dataset:** update `dataset.lock.json` to the new sggs-data commit, run
  `make vendor-sync-data`, and rebuild the iOS database (`make ios-db`). The manifest change is
  reviewed like any scripture change.

Vendored files are never edited here; CI rejects a local edit.

## Releasing

TestFlight and App Store builds are made only with `make testflight …` (or the manual
`ios-testflight` workflow), which derives the database, runs the licence gate on the exact
artifact, proves the database hash inside the archived app and records the build in
`ios/testflight-builds.json`. See [`docs/ios/`](docs/ios/).

## Licence

See [`NOTICE.md`](NOTICE.md). The English translation layer is not licensed for distribution; the
public build is Gurmukhi-only.
