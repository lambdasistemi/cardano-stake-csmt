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

## Slice 2 - Atomic Epoch Write

- [X] T004-S2 Unify stake CSMT and history RocksDB opening so both typed
  stores live under one physical RocksDB instance and one transaction context.
- [X] T005-S2 Collapse daemon config and CLI from `configStakeDbPath` plus
  `configHistoryDbPath` to one store path such as `configDbPath`, with one
  `--db` flag and fail-closed validation/environment fallback.
- [X] T006-S2 Refactor `indexStakeSnapshot` so `buildEpochCSMT epoch snapshot`
  and `finalizeEpochRoot epoch root` commit in one transaction over the unified
  store.
- [X] T007-S2 Add focused atomicity coverage proving an epoch CSMT build and
  history-root finalization are one write unit, ideally with failure injection
  showing no epoch root is visible without its history finalization.
- [X] T008-S2 Run `nix develop --quiet -c just unit "Indexer"`,
  `nix develop --quiet -c just unit "Application.Run"`, and `./gate.sh`, then
  commit as `feat(indexer): make epoch writes atomic`.

## Slice 3 - Daemon Indexer Lifecycle

- [X] T009-S3 Extend `application/Cardano/StakeCSMT/Application/Run/Main.hs`
  to build ledger/replay/checkpoint config from `RuntimeConfig`, open the
  unified store once, start the indexer with linked failure propagation, and
  serve HTTP over the same handles.
- [X] T010-S3 Add controlled lifecycle tests in
  `test/Cardano/StakeCSMT/Application/RunSpec.hs` proving readiness flips and
  an existing query returns real data after an injected indexer action writes
  an epoch over the shared handle.
- [X] T011-S3 Add a focused indexer-death test proving the daemon lifecycle
  fails closed when the background indexer fails.
- [X] T012-S3 Add a real RocksDB shared-handle read/write regression in
  `test/Cardano/StakeCSMT/Application/RunSpec.hs` or the closest focused
  existing spec, without changing proof semantics.
- [X] T013-S3 Run `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`, then commit as
  `feat(app): wire indexer into daemon runtime`.

## Slice 4 - Finalization

- [X] T014-F Run `just ci` at HEAD.
- [X] T015-F Run `nix build .#default` at HEAD.
- [X] T016-F Run `nix build .#e2e-tests` at HEAD if this ticket changes or
  adds e2e coverage.
- [X] T017-F Update the draft PR body with delivered behavior and
  verification evidence.
- [X] T018-F Drop `gate.sh` in
  `chore: drop gate.sh (ready for review)`, push, and report COMPLETE with
  PR URL and head SHA.
