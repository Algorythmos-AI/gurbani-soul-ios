# Contributing

## Ground rule

This app presents sacred scripture. Never alter, normalise or paraphrase Gurmukhi text. Display
transforms (such as the traditional saroop rendering) stay display-only: copy, share and search
always use the verbatim text. If something in the text looks wrong, open a `scripture-fidelity`
issue; never fix it here.

## Workflow

1. Branch from `main` (`feat/…`, `fix/…`, `chore/…`).
2. `make gates` and, for any change under `ios/Packages`, `make parity`.
3. UI changes: add a `shot("…")` to `testCaptureScreens` for any new surface and attach screenshots.
4. Open a PR. `ci`, `parity`, `app` and `secrets` must be green. PRs are squash-merged.

## Conventions

- Bundle ids `org.sggs.*`, App Group `group.org.sggs` and the `sggs://` URL scheme are internal
  identifiers and do not change with the brand.
- `CURRENT_PROJECT_VERSION` stays `1`; each upload passes `BUILD=N`.
- `ios/Resources/sggs-ios.sqlite` is derived and git-ignored; its manifest is tracked. After a
  branch switch run `make ios-db-check` (and `make ios-db-repair` if it fails).
- Commit messages use the imperative mood and explain why.
