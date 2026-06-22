# Tasks: Release Pipeline And Architecture/API Docs

## Slice 1 - Documentation And Pages Workflow

- [X] T001-S1 Update `mkdocs.yml` navigation and Material settings for architecture plus API/proof documentation.
- [X] T002-S1 Replace scaffold docs with the completed stake CSMT architecture, including replay, snapshots, CSMTs, history roots, rollback, HTTP proofs, signed latest headers, and voting-proof use case.
- [X] T003-S1 Add API/proof documentation for endpoints, proof response shape, two-level verification, latest signed-header verification, and `totalStake` threshold checks.
- [X] T004-S1 Update `deploy-docs.yml` so pull requests run `mkdocs build --strict`, `main` deploys through Pages workflow mode, run the focused docs build and `./gate.sh`, then commit as `docs: document stake proof architecture and API`.

## Slice 2 - Cabal-Owned Release Pipeline And Artifacts

- [X] T005-S2 Add release planner scripts for Cabal version extraction, Cabal/changelog/tag consistency, changelog note extraction, release PR planning, and later `v<version>` tag creation.
- [X] T006-S2 Add flake-owned Linux AppImage, DEB, RPM, `SHA256SUMS`, development artifact, and Linux artifact smoke outputs.
- [X] T007-S2 Add flake-owned Darwin Homebrew release and development artifact outputs compatible with the shared lambdasistemi tap workflow.
- [X] T008-S2 Add release planner, Linux release, and Darwin release workflows with PR/dev modes that do not publish and tag modes that publish only after consistency checks.
- [X] T009-S2 Document install and release behavior in README/getting-started/CHANGELOG without publishing a real release.
- [X] T010-S2 Run the focused release checks and `./gate.sh`, then commit as `ci: add cabal-owned release pipeline`.

## Finalization

- [ ] T011-F Run `nix develop -c just ci` at HEAD.
- [ ] T012-F Run `nix build .#default .#e2e-tests` at HEAD.
- [ ] T013-F Run strict MkDocs build at HEAD.
- [ ] T014-F Update the draft PR body with delivered behavior, verification evidence, missing-secret follow-ups, and release/docs notes.
- [ ] T015-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
