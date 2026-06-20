# Feature Specification: Repository Scaffold

## User Story

As a maintainer, I can clone `cardano-stake-csmt`, enter the Nix
development shell, and run `just ci` to build, test, format-check, lint,
and validate documentation for the initial multi-component Haskell
project.

## Acceptance Criteria

- The repository has a Cabal package named `cardano-stake-csmt` with the
  same component shape as `cardano-utxo-csmt`: thin main library,
  public `library`, public `http`, public `application`, one executable,
  `unit-tests`, and `e2e-tests`.
- The public Haskell namespace is `Cardano.StakeCSMT.*`.
- The scaffold exposes only health/readiness behavior; it does not
  implement ledger replay, stake extraction, CSMT construction, storage,
  history roots, rollback handling, or proof generation.
- `flake.nix`, `nix/project.nix`, and `nix/shell.nix` use haskell.nix
  with `compiler-nix-name = "ghc9123"` and build `.#default` and
  `.#unit-tests`.
- `justfile` exposes `build`, `unit`, `e2e`, `format`, `format-check`,
  `hlint`, and `ci` recipes.
- Fourmolu and HLint configuration are present, and the gate verifies
  formatting and linting.
- MkDocs documentation is initialized with a small skeleton and a docs
  build/deploy workflow.
- Spec Kit is initialized under `.specify/`, per-project command/skill
  copies are removed, and `.specify/memory/constitution.md` is filled
  from the parent epic invariants and workflow conventions.
- The GitHub Actions CI stub on `main` is replaced by real NixOS jobs:
  `Build Gate`, `CI build`, `CI format`, `CI hlint`, and `Docs build`.
- After the real CI workflow is present on the PR branch, the `main`
  branch ruleset requires the real job names.

## Non-Goals

- No production ledger, ChainSync, CSMT, RocksDB, history-root, rollback,
  or proof logic.
- No non-health HTTP API beyond `/health` and `/ready`.
- No release packaging beyond the basic scaffold CI/docs setup.

## Success Signals

- `./gate.sh` passes at PR head.
- `nix develop --quiet -c just ci` passes locally.
- `nix build --quiet .#default .#unit-tests` succeeds.
- The draft PR body records the final component and namespace map.
