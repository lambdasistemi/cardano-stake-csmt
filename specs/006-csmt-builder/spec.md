# Feature Specification: Per-Epoch Stake CSMT Builder

## P1 User Story

As the service, I bulk-build a Compact Sparse Merkle Tree over an epoch
stake snapshot, persist the snapshot and tree, and expose a deterministic
epoch root plus credential inclusion proofs that verify against that root.

## User Stories

- As replay code, I can hand an `EpochNo` and `StakeSnapshot` to the CSMT
  layer and receive the committed stake root for that epoch.
- As storage code, I can persist the epoch snapshot, CSMT tree nodes, and
  epoch root in RocksDB columns with stable codecs.
- As proof-serving code, I can ask for a stake credential proof and verify it
  against the root persisted for the same epoch.
- As downstream history code, I can read a stable `(epoch, stakeRoot,
  totalStake)` record without reinterpreting the snapshot schema.

## Functional Requirements

- FR-001: Build a CSMT with `mts:csmt` from `StakeSnapshot`, using stake
  credential as the leaf key and `Coin` as the voting-weight value.
- FR-002: Use deterministic credential and coin encodings so identical
  snapshots always produce identical CSMT roots.
- FR-003: Persist per-epoch snapshot entries in a RocksDB KV column keyed by
  `(EpochNo, Credential 'Staking)`.
- FR-004: Persist CSMT tree nodes in a RocksDB KV column using the same CBOR
  encoding pattern as `cardano-utxo-csmt` for `CSMT.Interface.Key` and
  `Indirect`.
- FR-005: Namespace tree nodes by epoch using a deterministic CSMT key prefix
  derived from `EpochNo`, so one tree column can store many epoch trees.
- FR-006: Persist an epoch root record keyed by `EpochNo`; the record includes
  the CSMT root hash and `totalStake` for downstream history accumulation.
- FR-007: Provide an inclusion proof API for a credential at an epoch; the
  proof must verify with `CSMT.Proof.Insertion.verifyInclusionProof` against
  the persisted epoch root.
- FR-008: Include golden coverage for root reproducibility from identical
  snapshots.

## Schema Contract

This ticket owns a shared schema inherited by #7 and #9.

- Snapshot column: key is `(EpochNo, Credential 'Staking)`, value is `Coin`.
- Tree column: key is `CSMT.Interface.Key`; value is `Indirect Hash`.
- Tree namespace: each epoch uses `epochPrefix epoch <> credentialKey
  credential` as the CSMT path, where `epochPrefix` is derived from a stable
  CBOR/word encoding of `EpochNo`.
- Root column: key is `EpochNo`; value is `EpochRoot` containing the CSMT root
  hash for that epoch and `totalStake`.
- Credential and `Coin` storage codecs use Cardano ledger CBOR at
  `natVersion @11`.
- CSMT hash type is `CSMT.Hashes.Hash`; `Coin` values are converted to leaf
  hashes from their canonical CBOR bytes.

## Success Criteria

- The unit suite proves two builds from the same snapshot produce the same
  root.
- The unit suite proves a proof for a credential verifies against the epoch
  root and fails against a different root/value.
- RocksDB-backed tests prove snapshot entries, tree nodes, and root records
  survive a close/reopen cycle.
- `nix develop -c just ci` passes at PR head.

## Non-Goals

- No history accumulator; that belongs to #7.
- No rollback/checkpoint behavior; that belongs to #8.
- No HTTP proof endpoints or signed latest-epoch header; those belong to #9.
- No changes to ledger replay or stake snapshot extraction from #2-#5.
