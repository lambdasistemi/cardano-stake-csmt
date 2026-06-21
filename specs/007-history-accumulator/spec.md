# Feature Specification: History Accumulator

## P1 User Story

As the service, I accumulate each finalized epoch's `(epoch, stakeRoot, totalStake)` into a history root, and observe one root committing all past epochs and their totals.

## Scope

Build the library history layer for finalized epoch roots. The history layer consumes the existing #6 `EpochRoot { epochRootHash, epochRootTotalStake }` produced by `Cardano.StakeCSMT.CSMT.Builder`, inserts one leaf per finalized `EpochNo`, exposes the current history root, and produces proofs that a specific `(epoch, stakeRoot, totalStake)` leaf is included in that history root.

## User Stories

1. As an indexer, I can insert a finalized epoch root into the history accumulator and receive the updated history root.
2. As a proof server, I can query the stored history root and build an `epochRootProof` for a persisted finalized epoch.
3. As a verifier, I can verify that an epoch number, stake root hash, and total stake belong to a specific history root.
4. As an operator, I can reopen RocksDB and still query persisted epoch leaves, the CSMT nodes, and the current history root.

## Functional Requirements

- FR-001: The history leaf value MUST encode both `epochRootHash` and `epochRootTotalStake`.
- FR-002: The history tree MUST be keyed by `EpochNo`.
- FR-003: The history accumulator MUST reuse `mts:csmt` and the same typed KV transaction pattern used by `Cardano.StakeCSMT.CSMT.*`.
- FR-004: The library MUST expose functions to insert/finalize an epoch root, query a per-epoch leaf, query the current history root, build an epoch root inclusion proof, and verify that proof.
- FR-005: RocksDB persistence MUST store per-epoch leaves, history tree nodes, and the current history root in dedicated column families under `Cardano.StakeCSMT.History.*`.
- FR-006: Empty history MUST report no history root.
- FR-007: Re-inserting the same epoch/root pair MUST be deterministic and leave proof verification valid.

## Non-Goals

- Rollback/checkpoint logic for mutable recent epochs (#8).
- HTTP endpoints, response encodings, or signed latest headers (#9).
- Changes to the ledger replay or stake snapshot semantics from #3-#6.
- On-chain verifier changes.

## Acceptance Criteria

- AC-001: Unit tests show a history leaf carries `(epoch, stakeRoot, totalStake)` and changing either stake root or total stake invalidates proof verification.
- AC-002: Unit tests show deterministic history roots for identical epoch sequences.
- AC-003: Unit tests show `epochRootProof` verifies a finalized epoch leaf against the history root and fails against the wrong epoch/root/total/history root.
- AC-004: RocksDB tests show per-epoch leaves, tree nodes, and current history root persist across close/reopen.
- AC-005: `nix develop -c just ci` passes before the PR is marked complete.
