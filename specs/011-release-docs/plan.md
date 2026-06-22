# Implementation Plan: Release Pipeline And Architecture/API Docs

## Technical Context

- Repository: `lambdasistemi/cardano-stake-csmt`.
- Package/executable: `cardano-stake-csmt`, versioned in
  `cardano-stake-csmt.cabal`.
- Current flake systems: `x86_64-linux` and `aarch64-darwin`.
- Current package outputs: `default`, `cardano-stake-csmt`,
  `unit-tests`, and `e2e-tests`.
- Current docs: MkDocs Material scaffold with `index.md`,
  `getting-started.md`, and `architecture.md`.
- Current CI already has a docs build job; `deploy-docs.yml` deploys
  only on `main` and needs PR strict-build coverage.
- Release references: `cardano-utxo-csmt` for docs shape and
  `amaru-treasury-tx` for current flake-owned release artifacts and
  Cabal-owned planner behavior.

## Architecture

The implementation is split into two bisect-safe commits.

The first commit updates only documentation and Pages CI. It replaces
scaffold-era prose with the completed stake CSMT architecture and adds
an API/proof page. It also makes the docs deployment workflow safe for
pull requests by building the site strictly without deploying unless
the ref is `main`.

The second commit adds release automation. Artifact construction lives
in Nix outputs; workflows select PR/dev/release modes and publish only
when the event is a `v*` tag push or an explicit publish-enabled
manual dispatch. The planner script owns Cabal version/changelog PRs
and later tag creation, but this ticket does not run a real release.

## Slice 1: Documentation And Pages Workflow

Owned files:

- `mkdocs.yml`
- `docs/index.md`
- `docs/getting-started.md`
- `docs/architecture.md`
- `docs/api-proofs.md`
- `.github/workflows/deploy-docs.yml`

Work:

- Update MkDocs navigation and Material configuration for the
  architecture and API/proof pages.
- Replace scaffold-era docs with the merged architecture:
  N2C replay from Origin, trusted `reapply`, `ExtLedgerState`,
  epoch-boundary `ssStake` snapshots, credential CSMTs, history roots
  with `totalStake`, rollback, HTTP proofs, and signed latest headers.
- Document API endpoints and the client verification sequence:
  credential proof against stake root, epoch leaf proof against history
  root, and latest signed-header validation.
- Update the docs workflow so PRs run `mkdocs build --strict` and
  `main` deploys via Pages workflow mode. Do not use legacy
  `mkdocs-deploy` or `gh-pages`.

Focused proof command:

```sh
nix develop github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs build --strict --site-dir site
```

Commit subject:

```text
docs: document stake proof architecture and API
```

Tasks trailer: `Tasks: T001-S1, T002-S1, T003-S1, T004-S1`

## Slice 2: Cabal-Owned Release Pipeline And Artifacts

Owned files:

- `flake.nix`
- `flake.lock`
- `nix/linux-release.nix`
- `nix/linux-artifact-smoke.nix`
- `.github/workflows/release-planner.yml`
- `.github/workflows/release.yml`
- `.github/workflows/darwin-release.yml`
- `scripts/release/plan`
- `scripts/release/get-cabal-version`
- `scripts/release/check-version-consistency`
- `scripts/release/extract-notes`
- `CHANGELOG.md`
- `README.md`
- `docs/getting-started.md`

Work:

- Add flake inputs and outputs for Linux release artifacts,
  Linux dev artifacts, Darwin Homebrew artifacts, Darwin dev Homebrew
  artifacts, and the Linux artifact smoke app.
- Wrap the executable when required so NixOS bundlers can discover
  `meta.mainProgram`.
- Stage Linux artifacts as
  `cardano-stake-csmt-<version>-x86_64-linux.{AppImage,deb,rpm}` plus
  `cardano-stake-csmt.AppImage` and `SHA256SUMS`.
- Smoke-test extracted AppImage, DEB, and RPM artifacts by finding the
  installed executable and exercising an offline CLI surface.
- Add release planner scripts following the Cabal-owned pattern.
- Add workflows:
  - release planner on `main`/manual dispatch;
  - Linux release workflow on `v*` tags, PRs touching workflow/Nix
    release files, and manual dispatch;
  - Darwin release workflow on `v*` tags, PRs touching workflow/Nix
    release files, and manual dispatch.
- Document install and release behavior in README/getting started.

Focused proof commands:

```sh
scripts/release/plan
RELEASE_PLAN_DRY_RUN=1 scripts/release/plan
scripts/release/check-version-consistency
nix build --quiet .#linux-dev-release-artifacts
artifact_dir="$(readlink -f result)"
artifact_version="$(scripts/release/get-cabal-version)-$(git rev-parse --short=7 HEAD)"
nix run --quiet .#linux-artifact-smoke -- --artifacts-dir "$artifact_dir" --artifact-version "$artifact_version"
```

The non-dry-run planner command must only be run if the driver confirms
it will not push tags or release branches from the PR worktree. If that
cannot be guaranteed, use dry-run and consistency checks only.

Commit subject:

```text
ci: add cabal-owned release pipeline
```

Tasks trailer: `Tasks: T005-S2, T006-S2, T007-S2, T008-S2, T009-S2, T010-S2`

## Finalization

The ticket owner reruns:

```sh
nix develop -c just ci
nix build .#default .#e2e-tests
nix develop github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs build --strict
```

Then the ticket owner updates PR metadata, runs the finalization audit,
drops `gate.sh` in the ready-for-review commit, pushes, and marks the
PR ready.
