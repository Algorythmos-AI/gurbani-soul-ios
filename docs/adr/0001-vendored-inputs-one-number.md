# ADR-0001: The app builds against pinned inputs and carries the platform's version number

**Status:** accepted (2026-09-24, release 1.3.8)

**Context.** The app is fully offline and bundles its own copy of the scripture. Its Swift search,
verify and reader core must behave exactly like the platform's API, and the App Store version must
equal the version the website and API report — while the app now lives in its own repository.

**Decision.**
- **Inputs arrive pinned.** The database comes from sggs-data by commit and sha256
  (`dataset.lock.json`, `scripts/data/fetch_dataset.py`). The golden contract and contributors
  roster (platform) and the iOS database builder (sggs-data) are vendored at their upstream paths,
  recorded in `vendor.lock.json` with source commit and sha256 per file; CI proves every file equals
  its lock entry and its source (`scripts/vendor_sync.py check --remote`). Vendored files are never
  edited here.
- **One number.** `MARKETING_VERSION` equals the `APP_VERSION` of the platform release whose contract
  is vendored (`scripts/release/check_versions.py`). An App Store upload must be the app's release
  tag `vX.Y.Z` built against platform `vX.Y.Z`; each build records `platform_commit` and
  `dataset_commit` in the ledger, which the platform's release-completeness check reads.

**Consequences.** Parity with the API is proven against exactly the contract that release serves,
and a platform release reaches the app as one reviewable vendor-sync PR. A release is complete only
when web, API and the App Store binary share one version and one platform commit.
