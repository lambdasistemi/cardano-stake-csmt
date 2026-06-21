# Implementation Plan: History Accumulator

## Technical Context

- Language/tooling: Haskell, cabal, Nix dev shell, hspec.
- Existing pattern: `Cardano.StakeCSMT.CSMT.{Codecs,Builder,Columns,RocksDB}`.
- Existing leaf source: `EpochRoot { epochRootHash, epochRootTotalStake }` from `Cardano.StakeCSMT.CSMT.Codecs`.
- Core dependency: `mts:csmt` via `CSMT.Insertion`, `CSMT.Interface`, and `CSMT.Proof.Insertion`.
- Storage dependency: `rocksdb-kv-transactions` typed columns plus `rocksdb-haskell-jprupp`.

## Architecture

Add a separate `Cardano.StakeCSMT.History` namespace rather than extending the credential CSMT storage. The history accumulator has its own typed columns:

- `HistoryLeafCol :: KV EpochNo EpochRoot`
- `HistoryTreeCol :: KV Key (Indirect Hash)`
- `HistoryRootCol :: KV () Hash`

The history tree uses a single namespace prefix for all epoch leaves. Epoch keys are `EpochNo`; values are hashes derived from a stable codec of `EpochRoot`, so both the stake root hash and `totalStake` affect proof verification. The current history root is stored separately so consumers can query it without recomputing from tree nodes.

## Slices

### Slice 1: History codecs and columns

Create the history storage schema and stable codecs:

- `Cardano.StakeCSMT.History.Codecs`
- `Cardano.StakeCSMT.History.Columns`
- codec/column tests
- cabal module listings

This slice should compile and test without exposing builder behavior yet.

### Slice 2: History builder and proof verification

Create the pure transaction-level accumulator API:

- insert/finalize epoch roots into the history CSMT
- query per-epoch leaves and current history root
- build `epochRootProof`
- verify an `EpochNo`/`EpochRoot` leaf against a supplied history root
- unit tests for deterministic roots and proof failure modes

### Slice 3: History RocksDB persistence

Create RocksDB helpers and persistence tests:

- `withHistoryRocksDB`
- `mkHistoryDatabase`
- dedicated column family names for leaf/tree/root
- reopen test proving leaves, tree root node, current root, and proofs survive

## Verification

Every slice runs `./gate.sh`. The final ticket gate is:

```sh
nix develop -c just ci
```

The ticket owner reruns the gate before accepting each implementation commit and again before marking the PR complete.
