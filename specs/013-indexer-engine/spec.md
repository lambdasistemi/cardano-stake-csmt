# Feature Specification: Indexer Engine

**Feature Branch**: `feat/24-indexer-engine`
**Issue**: #24
**Parent Epic**: #27
**Created**: 2026-06-22
**Status**: Draft

## P1 User Story

As the daemon, I can run a library indexer from genesis over the local node
ChainSync interface and, at every finalized epoch boundary, persist the
credential-stake CSMT root and finalized history root into the shared stores
that the HTTP server reads.

## Acceptance Criteria

- A new library indexer module exposes `runIndexer` and `withIndexer`.
- The public indexer API accepts a `LedgerConfigBundle`, shared stake and
  history `Database` handles, `ReplayFollowerConfig`, `ReplayCheckpointConfig`,
  and an optional epoch-boundary hook.
- The indexer reuses `runReplayFollowerWithCheckpoints` and starts from the
  nearest recoverable checkpoint plus retained tail when recovering from a
  rollback.
- Writes happen only after an observed epoch transition, not on every block.
- At each indexed boundary, the indexer extracts a `StakeSnapshot` from the
  replay state's ledger state, builds the epoch CSMT in the stake store, and
  finalizes the epoch root into the history store.
- Replaying the same captured devnet blocks twice yields identical stored
  epoch roots and history roots.
- Captured devnet replay tests assert the stored epoch root, current history
  root, credential inclusion proof, and epoch-root history proof verify.

## Functional Requirements

- **FR-001**: Add `Cardano.StakeCSMT.Indexer` under the public library.
- **FR-002**: Define a small indexed-boundary result type that includes the
  indexed epoch, epoch root, and current history root.
- **FR-003**: Provide a writer primitive for indexing a non-empty
  `StakeSnapshot` into the stake and history databases in deterministic order.
- **FR-004**: `runIndexer` must compose `replayBlock` with
  `runReplayFollowerWithCheckpoints`, `defaultReplayChainSyncRunner`, and the
  supplied checkpoint configuration.
- **FR-005**: `withIndexer` must start the same indexer over the supplied
  handles for use by later daemon wiring, without opening stores itself.
- **FR-006**: The optional epoch-boundary hook must run after a successful
  boundary write and must receive enough information to observe or stop test
  runs deterministically.
- **FR-007**: Snapshot extraction failures must fail the indexer rather than
  silently producing partial stores.
- **FR-008**: Empty snapshots must not finalize an absent epoch root.

## Non-Goals

- No CLI/config changes; #23 owns the config surface.
- No changes to `Application.Run.Main` or executable daemon wiring; #25 owns
  process wiring and HTTP/indexer concurrency.
- No HTTP query semantics or proof format changes.
- No new toolchain, second GHC, or unrelated dependency updates.

## Success Criteria

- Focused unit tests for the writer primitive are green.
- E2E devnet replay tests for the indexer are green.
- `just ci`, `nix build .#default`, and `nix build .#e2e-tests` are green
  before completion.
