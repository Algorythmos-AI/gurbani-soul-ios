# Runbook: iOS hotfix

iOS has no rollback. The levers, mildest first:

1. **Pause the phased release** — stops new automatic updates; users who already updated keep the
   build. A pause has a time limit (check the current one in App Store Connect). Updates only: a
   first version has no phased release, so for it this lever does not exist — go to step 2.
2. **Ship a fixed build** (below), optionally asking for an **expedited review** through
   App Store Connect → Contact Us → App Review. Use it rarely and say plainly what is broken;
   a scripture-fidelity defect is a legitimate reason.
3. **Remove from sale** — last resort; existing installs keep working (the app is fully offline).

## Procedure
1. Reproduce and write the failing test first. Scripture text is never edited to "fix" anything —
   see the prime directive in the platform's [`docs/engineering/invariants.md`](https://github.com/Algorythmos-AI/sggs-platform/blob/main/docs/engineering/invariants.md).
2. Branch `hotfix/<slug>` **from this app's release tag** (not from a later `main`, which may already
   hold unreleased work): `git worktree add <scratch>/wt-hotfix -b hotfix/<slug> vX.Y.Z`
3. One number, both surfaces: the platform releases `X.Y.(Z+1)` too (never a one-sided hotfix — see
   its release runbook). Once that tag exists, `make vendor-sync-platform REF=vX.Y.(Z+1)` and set
   `MARKETING_VERSION` to `X.Y.(Z+1)`. Build numbers restart at the ledger's `next` for the new version.
4. PR `hotfix/<slug>` → `main` (squash). CI must be green: `gates`, `parity`, `app`.
5. From a worktree at that `main` commit:
   `make testflight TEAM_ID=… BUILD=N CHANNEL=appstore UPLOAD=1`
   The script refuses a dirty tree, an off-trunk commit and red CI, exactly as for a normal release.
6. Commit the ledger row via PR. `make appstore-preflight` must pass. Re-sign Charter S on the new
   build number; re-run only the hardware checks the fix could affect, and say which.
7. Submit. After approval, release and resume (or restart) the phased rollout.
8. Tag the app release `vX.Y.(Z+1)` on that `main` commit (the archive already required it).
9. Write the incident note: what users saw, how it got past the gates, which gate now catches it.
   A hotfix without a new test or gate is not finished.
