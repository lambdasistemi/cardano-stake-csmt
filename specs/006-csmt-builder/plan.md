# Implementation Plan: Per-Epoch Stake CSMT Builder

## Context

Issue #6 builds on the merged ledger replay and stake snapshot extraction.
The input is `Cardano.StakeCSMT.Ledger.StakeSnapshot`, which already exposes
`Map (Credential 'Staking) Coin` and `totalStake`. This ticket adds the CSMT
and RocksDB layer only.

The implementation mirrors the `cardano-utxo-csmt` pattern for:

- CBOR codecs for `CSMT.Interface.Key` and `Indirect`.
- A typed `Columns` GADT with `Database.KV.Transaction.Codecs`.
- Transaction-level CSMT operations using `CSMT.Insertion.insertingBatch`,
  `CSMT.Interface.root`, and `CSMT.Proof.Insertion.buildInclusionProof`.

## Dependencies

- Add `lambdasistemi/haskell-mts` as a `source-repository-package`, mirroring
  the sibling `cardano-utxo-csmt` pin:
  `9a510679075930bae812fea5f56b47789ce497ca` with nix32 hash
  `1cph1rdhyzk323qfxlrnr63mpgqich3rmaixwq1irvnk445ydchz`.
- Add `mts` and `mts:csmt` to the relevant Cabal components.
- Keep the existing `rocksdb-kv-transactions` pin unless implementation proves
  it lacks required API.
- Use nix32 format for any new `--sha256` comment.

## Target Modules

- `Cardano.StakeCSMT.CSMT.Codecs`: CBOR codecs for credentials, coins, epoch
  keys, CSMT keys, indirect nodes, and root records.
- `Cardano.StakeCSMT.CSMT.Columns`: typed RocksDB columns and `Codecs` map.
- `Cardano.StakeCSMT.CSMT.Builder`: pure/transaction API for building epoch
  trees, querying roots, and producing/verifying inclusion proofs.
- `Cardano.StakeCSMT.CSMT.RocksDB`: thin impure shell helpers around
  `rocksdb-kv-transactions`, if needed to prove persistence.

## Slice 1: dependency and schema foundation

Add the `mts` dependency and compile-time schema modules with focused tests for
codec determinism and column identity. This slice should not yet bulk-build a
tree.

Owned behavior:

- Cabal/project dependency wiring.
- Exposed modules under `lib/Cardano/StakeCSMT/CSMT`.
- Unit tests for codec round trips and deterministic encoded bytes.

## Slice 2: pure CSMT builder and proof API

Build an epoch tree from an in-memory `StakeSnapshot` using the CSMT batch API,
persisting through the transaction abstraction. Provide:

- `buildEpochCSMT`
- `queryEpochRoot`
- `buildCredentialProof`
- `verifyCredentialProof`

Tests use deterministic synthetic stake snapshots and assert identical roots
for identical snapshots plus a verifying inclusion proof.

## Slice 3: RocksDB-backed persistence

Use `rocksdb-kv-transactions` to prove the snapshot column, tree column, and
root column persist across close/reopen. Keep this as a library test surface,
not application replay wiring.

Tests create a temporary RocksDB database, build an epoch CSMT, close/reopen,
and verify that root and proof behavior survive.

## Slice 4: finalization and PR metadata

Update the PR body with the final schema contract and verification evidence.
Run `nix develop -c just ci`, drop `gate.sh`, and mark the draft PR ready.

## Gate

Every implementation slice must run:

```bash
./gate.sh
```

Before final `COMPLETE`, the ticket owner must run:

```bash
nix develop -c just ci
```

## Risks

- `Credential 'Staking` inverse decoding from `CSMT.Interface.Key` is partial
  by nature because arbitrary tree paths may not decode to credentials. Keep
  the externally trusted key in snapshot/root/proof APIs and use the inverse
  only where the CSMT library requires an `Iso'`.
- Empty snapshots produce no CSMT root from `CSMT.Interface.root`. Represent
  this explicitly in the root record if tests cover empty snapshots; do not
  invent a fake hash silently.
- The schema is inherited by #7 and #9. Any change to leaf encoding, epoch
  prefixing, or root record shape must be reflected in the PR body.
