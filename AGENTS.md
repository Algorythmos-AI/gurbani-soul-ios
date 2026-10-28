# Notes for AI agents working in gurbani-soul-ios

Read `README.md` and `CONTRIBUTING.md` first. The text of Sri Guru Granth Sahib Ji is never edited:
it arrives verbatim in the pinned dataset (`dataset.lock.json`) and is shown as stored.

## Release records — keep every one, in its place
| Record | Where | When |
|---|---|---|
| App Store "What's New" | `docs/ios/whats-new/<version>.md` + the What's New section of `docs/ios/app-store-listing.md` | every version, before submission (rules in `docs/ios/whats-new/README.md`) |
| Physical-device test run | bundles: a release in the private evidence repository; text: `ios/device-runs/<version>/<run-id>/` (`ios/tools/device_run.py`, runbook `docs/ios/device-evidence.md`) | every phone run; the release run at the tag gates submission |
| App Store / TestFlight uploads | `ios/testflight-builds.json` | every upload |

- Commits and PRs carry the owner's authorship only: no AI attribution trailers or footers.
- Never print, copy or upload signing keys; pass key paths only.
- An App Store submission needs `make appstore-preflight <version>` to pass on `main`.
