# Feature Specification: Daemon Wiring

**Feature Branch**: `feat/25-daemon-wiring`
**Issue**: #25
**Parent Epic**: #27
**Created**: 2026-06-22
**Status**: Draft

## P1 User Story

As an operator, when I launch `cardano-stake-csmt` with a valid runtime
configuration it opens one RocksDB-backed store, syncs the indexer from the
node, atomically commits each finalized epoch's stake CSMT and history root in
one transaction, and serves real proof/query responses over that same live
store instead of unavailable scaffold handlers.

## Acceptance Criteria

- `run` opens one RocksDB instance containing the typed stake CSMT and history
  column families, then shares the resulting live handles between the indexer
  and HTTP query handlers.
- Per-epoch stake CSMT construction and history-root finalization are committed
  in one transaction over that single RocksDB instance; a partial epoch root
  without its matching history finalization is not observable after failure.
- Runtime config and CLI expose one daemon store path, with validation and
  environment fallback remaining fail-closed.
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
- **FR-003**: The stake CSMT and history RocksDB storage layers must be opened
  over one physical RocksDB instance with typed column-family access for both
  domains.
- **FR-004**: `indexStakeSnapshot` must commit `buildEpochCSMT epoch snapshot`
  and `finalizeEpochRoot epoch root` inside one transaction over that unified
  store.
- **FR-005**: Collapse `configStakeDbPath` and `configHistoryDbPath` into one
  daemon store path such as `configDbPath`, update the CLI to one `--db` flag,
  and keep validation/environment fallback fail-closed.
- **FR-006**: Build `ReplayFollowerConfig` from `configNodeSocketPath`,
  `configNetworkMagic`, and `configByronEpochSlots`.
- **FR-007**: Build the ledger config from
  `ledgerConfigPathsFromDirectory configLedgerConfigDir` and
  `loadLedgerConfig`.
- **FR-008**: Build a checkpoint config from `RuntimeConfig` while preserving
  deterministic replay and deterministic roots. If production replay-state
  serialization is not available in the merged API, the implementation must
  document the chosen conservative behavior in code/tests and keep daemon
  wiring usable.
- **FR-009**: Start the indexer with a lifecycle that links failures back to
  the foreground daemon thread. The implementation may use `runIndexer`
  directly from `Run.Main` if `withIndexer` cannot satisfy this failure
  propagation without widening unrelated replay behavior.
- **FR-010**: Keep HTTP proof/root/latest-header/history-root semantics
  unchanged; the wiring only changes which live handles back the existing
  handlers and readiness.
- **FR-011**: Add focused atomicity coverage proving an epoch CSMT build and
  history finalization are written as one unit, ideally with failure injection
  showing no epoch root is visible without its history finalization.
- **FR-012**: Add a controlled unit test that proves readiness flips and at
  least one query returns real data after the injected indexing action writes
  an epoch.
- **FR-013**: Add a concurrent read/write regression test over the unified
  RocksDB-backed handles.

## Non-Goals

- No proof format or query semantics changes.
- No live devnet-to-curl HTTP E2E; #26 owns the over-the-wire devnet smoke.
- No second GHC/toolchain or unrelated dependency changes.
- No migration/backward-compatibility layer for the pre-1.0 two-path store
  layout; the issue may make the CLI/config shape pre-1.0 breaking.

## Success Criteria

- Focused daemon wiring unit tests are green.
- `just ci` is green through `./gate.sh`.
- Before completion, `just ci` and `nix build .#default` are green locally.
  If an e2e component is changed or added, `nix build .#e2e-tests` is also
  green.
