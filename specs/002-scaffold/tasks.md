# Tasks: Repository Scaffold

## Slice 1 - Haskell and Nix scaffold

- [X] T001 Create the Cabal package with the agreed component map and `Cardano.StakeCSMT.*` namespace.
- [X] T002 Add minimal health/readiness Haskell modules, executable, unit tests, and e2e smoke tests without domain logic.
- [X] T003 Add `flake.nix`, `nix/project.nix`, `nix/shell.nix`, `cabal.project`, `justfile`, Fourmolu, HLint, and `LICENSE`.
- [X] T004 Run `./gate.sh` and commit with subject `feat: scaffold haskell and nix project`.

## Slice 2 - Docs, Speckit, and CI

- [X] T005 Add MkDocs skeleton and documentation workflow.
- [X] T006 Initialize Spec Kit under `.specify/`, remove per-project agent command copies, and fill the constitution.
- [X] T007 Replace the stub CI with real NixOS jobs named `Build Gate`, `CI build`, `CI format`, `CI hlint`, and `Docs build`.
- [X] T008 Run `./gate.sh` and commit with subject `ci: add docs speckit and real CI`.

## Finalization

- [X] T009 Update `main` branch ruleset required checks to the real CI job names.
- [X] T010 Update the PR body with the component map and verification evidence.
- [X] T011 Run final `./gate.sh`, drop `gate.sh`, and mark the PR ready for review.
