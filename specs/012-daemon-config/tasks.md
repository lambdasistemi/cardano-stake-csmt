# Tasks: Daemon Config Surface

## Slice 1 - Runtime CLI Config

- [X] T001-S1 Extend `RuntimeConfig` in `application/Cardano/StakeCSMT/Application/Run/Config.hs` with required daemon fields and optional docs/checkpoint/signing-key fields.
- [X] T002-S1 Add `application/Cardano/StakeCSMT/Application/Run/CLI.hs` with argv parsing, environment fallbacks, validation, and Ed25519 signing-key loading.
- [X] T003-S1 Thread the CLI parser into application startup with only the minimal `Run.Main` change required for the executable to use it.
- [X] T004-S1 Add unit tests for parse success, every required-missing failure, invalid required values/paths, API port env fallback, and signing-key loading.
- [X] T005-S1 Register the new module and required application/test dependencies in `cardano-stake-csmt.cabal` without adding a second toolchain or unrelated package changes.
- [X] T006-S1 Run `nix develop --quiet -c just unit "Application.Run"` and `./gate.sh`, then commit as `feat(app): add daemon runtime config`.

## Finalization

- [X] T007-F Run `just ci` at HEAD.
- [X] T008-F Run `nix build .#default` at HEAD.
- [X] T009-F Update PR body with delivered behavior and verification evidence.
- [X] T010-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
