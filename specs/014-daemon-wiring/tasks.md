# Tasks: Daemon Wiring

## Slice 1 - Readiness Signal

- [X] T001-S1 Add a daemon readiness signal in
  `application/Cardano/StakeCSMT/Application/Run/Main.hs` and thread it into
  `runtimeHandlers` / `QueryHandlers.queryReady`.
- [X] T002-S1 Update focused readiness coverage in
  `test/Cardano/StakeCSMT/Application/RunSpec.hs` and, only if needed,
  `test/Cardano/StakeCSMT/HTTP/ServerSpec.hs`.
- [X] T003-S1 Run `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`, then commit as
  `feat(app): add daemon readiness signal`.

## Slice 2 - Daemon Indexer Lifecycle

- [ ] T004-S2 Extend `application/Cardano/StakeCSMT/Application/Run/Main.hs`
  to build ledger/replay/checkpoint config from `RuntimeConfig`, open
  stake/history RocksDB once, start the indexer with linked failure
  propagation, and serve HTTP over the same handles.
- [ ] T005-S2 Add controlled lifecycle tests in
  `test/Cardano/StakeCSMT/Application/RunSpec.hs` proving readiness flips and
  an existing query returns real data after an injected indexer action writes
  an epoch over the shared handles.
- [ ] T006-S2 Add a focused indexer-death test proving the daemon lifecycle
  fails closed when the background indexer fails.
- [ ] T007-S2 Run `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`, then commit as
  `feat(app): wire indexer into daemon runtime`.

## Slice 3 - Concurrent Shared Store Regression

- [ ] T008-S3 Add a real RocksDB shared-handle read/write regression in
  `test/Cardano/StakeCSMT/Application/RunSpec.hs` or the closest focused
  existing spec, without changing proof semantics.
- [ ] T009-S3 Run `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`, then commit as
  `test(app): cover concurrent daemon store access`.

## Slice 4 - Finalization

- [ ] T010-F Run `just ci` at HEAD.
- [ ] T011-F Run `nix build .#default` at HEAD.
- [ ] T012-F Run `nix build .#e2e-tests` at HEAD if this ticket changes or
  adds e2e coverage.
- [ ] T013-F Update the draft PR body with delivered behavior and
  verification evidence.
- [ ] T014-F Drop `gate.sh` in
  `chore: drop gate.sh (ready for review)`, push, and report COMPLETE with
  PR URL and head SHA.
