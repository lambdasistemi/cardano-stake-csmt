# Implementation Plan: Indexer Engine

## Technical Context

- Language/tooling: Haskell, Cabal, Fourmolu, Hspec, Nix flakes with
  `compiler-nix-name = "ghc9123"`.
- Existing replay entry point:
  `Cardano.StakeCSMT.Ledger.Replay.runReplayFollowerWithCheckpoints`.
- Existing writer primitives:
  `stakeSnapshotFromLedgerState`, `buildEpochCSMT`, `finalizeEpochRoot`,
  and `runTransactionUnguarded`.
- Existing store ownership: #24 writes through supplied stake/history
  `Database` handles only. Opening RocksDB handles belongs to #25.

## Design

Add `Cardano.StakeCSMT.Indexer` to the public library.

The module will expose:

- `IndexedEpoch`, carrying the indexed `EpochNo`, `EpochRoot`, and history
  root hash.
- `EpochBoundaryHook`, called after each observed epoch transition and after
  the store write for that boundary has completed.
- `indexStakeSnapshot`, a deterministic writer primitive used by tests and by
  the replay integration.
- `runIndexer`, using `defaultReplayChainSyncRunner`.
- `runIndexerWith`, a runner-injection variant for captured-block tests.
- `withIndexer`, a bracket-style helper that starts the indexer over supplied
  handles for #25 without owning store opening.

For each block, the indexer replay action will call `replayBlock` and capture
whether that block observed an epoch transition. If a transition was observed,
it indexes the snapshot from the post-block `ReplayState`. The persisted epoch
is `EpochNo (replayStateLastEpoch nextState)`, matching the replay checkpoint
state after the transition. The hook receives the original `EpochTransition`
and the optional indexed result.

`buildEpochCSMT` can return `Nothing` for an empty snapshot. In that case the
indexer does not call `finalizeEpochRoot` and reports `Nothing` through the
hook. Snapshot extraction errors are converted into indexer failure so the
caller cannot observe silently incomplete stores.

## Slice Breakdown

### Slice 1 - Writer Primitive

Add the module, result types, and `indexStakeSnapshot`. Unit tests use
in-memory stake/history databases to prove that a non-empty snapshot writes
the epoch root, finalizes the history root, and leaves verifiable credential
and history proofs. The same slice registers the module and unit test.

Focused gate:

```bash
nix develop --quiet -c just unit "Indexer"
./gate.sh
```

### Slice 2 - Replay/Checkpoint Indexer

Add `runIndexer`, `runIndexerWith`, and `withIndexer`. Add an e2e spec that
captures devnet blocks, replays the captured blocks through the indexer twice,
and asserts identical epoch/history roots plus verifying credential and
history proofs. The controlled runner must exercise the checkpoint recovery
path instead of bypassing `runReplayFollowerWithCheckpoints`.

Focused gate:

```bash
nix develop --quiet -c just e2e
./gate.sh
```

### Slice 3 - Finalization

The ticket orchestrator reruns final local gates, updates the PR body with
verification evidence, drops `gate.sh`, marks the PR ready, and reports the
PR URL plus head SHA to the epic owner. No implementation worker is used for
this orchestrator-owned slice.

## Verification

- Slice 1: `nix develop --quiet -c just unit "Indexer"` and `./gate.sh`.
- Slice 2: `nix develop --quiet -c just e2e` and `./gate.sh`.
- Completion: `just ci`, `nix build .#default`, and `nix build .#e2e-tests`.

## Risks

- Epoch numbering must stay aligned with replay checkpoint state. The plan
  writes the post-transition `replayStateLastEpoch`.
- The devnet boundary test can be slow; the e2e spec should stop through the
  hook once it has enough indexed evidence.
- `withIndexer` must not hide ownership of RocksDB handles. It receives
  handles and starts/stops only the indexer thread.
