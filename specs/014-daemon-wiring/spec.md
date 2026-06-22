# Feature Specification: Daemon Wiring

**Feature Branch**: `feat/25-daemon-wiring`
**Issue**: #25
**Parent Epic**: #27
**Created**: 2026-06-22
**Status**: Draft

## P1 User Story

As an operator, when I launch `cardano-stake-csmt` with a valid runtime
configuration it opens the stake and history stores once, syncs the indexer
from the node, and serves real proof/query responses over those same live
stores instead of unavailable scaffold handlers.

## Acceptance Criteria

- `run` opens the stake and history RocksDB handles once and shares the
  resulting `Database` handles between the indexer and HTTP query handlers.
- The daemon builds a `LedgerConfigBundle`, `ReplayFollowerConfig`, and
  `ReplayCheckpointConfig` from `RuntimeConfig` and starts the indexer in the
  background while serving HTTP in the foreground.
- `/ready` reports `ready = False` until at least one finalized epoch has been
  indexed, then reports `ready = True`.
- If the indexer thread terminates with an exception or failed result, the
  daemon process fails instead of continuing to serve over stale stores.
- Concurrent in-process indexer writes and HTTP reads over the shared RocksDB
  handles are covered by a regression test.
- The real daemon launch path is fail-closed: valid config always wires live
  stores and indexer; missing or invalid config is rejected by the existing
  config parser rather than silently using unavailable query handlers.

## Functional Requirements

- **FR-001**: Add a runtime readiness signal owned by the daemon wiring and
  read by `QueryHandlers.queryReady`.
- **FR-002**: The epoch-boundary hook supplied to the indexer must set the
  readiness signal after the first successful indexed finalized epoch.
- **FR-003**: Build `ReplayFollowerConfig` from `configNodeSocketPath`,
  `configNetworkMagic`, and `configByronEpochSlots`.
- **FR-004**: Build the ledger config from
  `ledgerConfigPathsFromDirectory configLedgerConfigDir` and
  `loadLedgerConfig`.
- **FR-005**: Build a checkpoint config from `RuntimeConfig` without changing
  #24 indexer/replay logic. If production replay-state serialization is not
  available in the merged API, the implementation must document the chosen
  conservative behavior in code/tests and keep daemon wiring usable.
- **FR-006**: Start the indexer with a lifecycle that links failures back to
  the foreground daemon thread. The implementation may use `runIndexer`
  directly from `Run.Main` if `withIndexer` cannot satisfy this failure
  propagation without changing #24.
- **FR-007**: Keep HTTP proof/root/latest-header/history-root semantics
  unchanged; the wiring only changes which live handles back the existing
  handlers and readiness.
- **FR-008**: Add a controlled unit test that proves readiness flips and at
  least one query returns real data after the injected indexing action writes
  an epoch.
- **FR-009**: Add a concurrent read/write regression test over shared
  RocksDB-backed handles.

## Non-Goals

- No changes to `Cardano.StakeCSMT.Indexer` replay/indexing semantics.
- No changes to CLI parsing or `RuntimeConfig` field shape from #23.
- No proof format or query semantics changes.
- No live devnet-to-curl HTTP E2E; #26 owns the over-the-wire devnet smoke.
- No second GHC/toolchain or unrelated dependency changes.

## Success Criteria

- Focused daemon wiring unit tests are green.
- `just ci` is green through `./gate.sh`.
- Before completion, `just ci` and `nix build .#default` are green locally.
  If an e2e component is changed or added, `nix build .#e2e-tests` is also
  green.
