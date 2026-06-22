# Specification: Release Pipeline And Architecture/API Docs

## P1 User Story

As a maintainer, I can cut a Cabal-owned release for
`cardano-stake-csmt`, publish nix-built Linux and Darwin artifacts from
tag workflows, and point users at architecture and API/proof
documentation that describes the merged stake CSMT stack.

## Scope

This ticket finishes the epic by adding release automation and
documentation. The release path follows the lambdasistemi Cabal-owned
binary pattern:

- the `.cabal` file is the version source of truth;
- a release planner opens or updates a release PR that bumps the Cabal
  version and writes `CHANGELOG.md`;
- a later main-branch planner run creates the `v<version>` tag when the
  Cabal version and changelog are already aligned;
- tag-push workflows publish artifacts, while pull-request mode only
  builds and smoke-tests development artifacts.

The docs path uses MkDocs Material and GitHub Pages workflow mode.
Pull requests build the site with `mkdocs build --strict`; `main`
deploys the Pages artifact.

## Functional Requirements

- FR-001: The release planner MUST read the package version from
  `cardano-stake-csmt.cabal` and MUST reject release-please manifests or
  any separate version file.
- FR-002: The planner MUST create or update a `release/cabal-release`
  PR with a Cabal version bump and generated changelog section based on
  conventional commits.
- FR-003: If `CHANGELOG.md` already contains the current Cabal version
  and `v<version>` does not exist, the planner MUST tag and push
  `v<version>` instead of publishing artifacts itself.
- FR-004: Linux release artifacts MUST be exposed as flake outputs for
  AppImage, DEB, RPM, and `SHA256SUMS`.
- FR-005: Linux PR/dev mode MUST build and smoke-test development
  artifacts without mutating GitHub releases.
- FR-006: Darwin release artifacts MUST be exposed as flake outputs for
  a Homebrew tarball and formula compatible with the shared
  `lambdasistemi/homebrew-tap` workflow.
- FR-007: Darwin PR/dev mode MUST build and smoke-test development
  artifacts without updating the production formula unless an explicit
  dev mode requests it.
- FR-008: Tag-push workflows MUST publish only from `v*` tags. Pull
  requests MUST never mutate GitHub releases or the Homebrew tap.
- FR-009: The docs site MUST include architecture coverage for N2C
  replay, `ExtLedgerState`, `ssStake` snapshots, per-epoch credential
  CSMTs, history roots, rollback, HTTP proofs, signed latest headers,
  and voting-proof verification.
- FR-010: The docs site MUST include API/proof coverage for `/proof`,
  `/roots`, `/history-root`, `/ready`, `/metrics`, Swagger UI, proof
  shapes, two-level proofs, and client verification using `totalStake`.
- FR-011: The docs deploy workflow MUST build strictly on pull requests
  and deploy through GitHub Pages workflow mode on `main`.

## Non-Goals

- No production `lib/`, `http/`, application, test, fixture, replay,
  snapshot, CSMT, history, rollback, or proof-format changes.
- No immediate release publication from this PR.
- No requirement to prove production Homebrew publication locally when
  `TAP_TOKEN` or release deploy-key secrets are unavailable.
- No branch-protection or repository-settings changes. Pages is already
  enabled in workflow mode.

## Acceptance Criteria

- AC-001: `mkdocs build --strict` succeeds with architecture and
  API/proof pages in the navigation.
- AC-002: The docs workflow runs on pull requests, builds strictly, and
  deploys on `main` through `actions/upload-pages-artifact` and
  `actions/deploy-pages`.
- AC-003: Release planner scripts are committed, executable, and have a
  dry-run mode suitable for PR verification without tagging.
- AC-004: Linux release workflow builds `linux-dev-release-artifacts` on
  PRs and smoke-tests AppImage/DEB/RPM with the flake app.
- AC-005: Tag-push release mode validates Cabal/changelog/tag
  consistency before uploading GitHub release artifacts.
- AC-006: Darwin workflow builds `darwin-dev-homebrew-artifacts` on PRs
  and reserves tap mutation for tag or explicit dev dispatch modes.
- AC-007: The final branch passes `nix develop -c just ci`,
  `nix build .#default .#e2e-tests`, and strict MkDocs build.
