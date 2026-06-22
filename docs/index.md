# Cardano Stake CSMT

Cardano Stake CSMT is an HTTP service that follows Cardano from
Origin and publishes verifiable commitments to per-epoch stake
distribution. Each completed epoch is represented as a credential-level
Compact Sparse Merkle Tree (CSMT), and each epoch root is accumulated
into a history tree so clients can verify current and historical voting
power without trusting an indexer response.

The service is designed for stake-weighted voting systems that need a
compact off-chain proof of "this staking credential had this much active
stake in this epoch" plus a stable denominator for threshold checks.

## What the service publishes

- `/proof/{credential}` for the latest persisted epoch and
  `/proof/{epoch}/{credential}` for a selected epoch.
- `/roots`, the ordered list of persisted `(epoch, stakeRoot,
  totalStake)` records.
- `/latest-header`, a signed latest `(epoch, stakeRoot, totalStake)`
  header for clients that pin the service signing key.
- `/history-root`, the root that commits to all finalized epoch-root
  leaves.
- `/ready`, `/metrics`, and `/health` for operational checks.
- Swagger UI and OpenAPI JSON when the docs server is enabled.

See [API and proofs](api-proofs.md) for endpoint shapes and client
verification steps.

## Architecture summary

1. The replay worker connects to a local Cardano node over node-to-client
   ChainSync and starts from Origin. Production stake extraction does
   not use Local State Query; it derives state by replaying trusted
   blocks.
2. Blocks are applied to an `ExtLedgerState` with the consensus ledger
   `reapply` path (`tickThenReapply` in the implementation).
3. At epoch boundaries, the service reads the ledger mark snapshot
   (`ssStake`) and projects it to `credential -> stake`.
4. The snapshot becomes a per-epoch CSMT. The root record stores both
   `stakeRoot` and `totalStake`.
5. A history tree stores leaves for `(epoch, stakeRoot, totalStake)` and
   exposes the latest history root.
6. Rollback recovery resumes from the nearest checkpoint at or before
   the rollback target, then replays the retained tail back to the
   target before following the node again.

## Repository layout

- `lib/`: ledger replay, stake snapshots, CSMT builders, history tree
  builders, codecs, and RocksDB column schemas.
- `http/`: Servant API, JSON codecs, query adapters, latest-header
  signing, and Swagger generation.
- `application/`: runtime wiring for API, optional docs server, RocksDB
  databases, and optional signing key.
- `executables/`: service executable entry point.
- `test/` and `e2e-test/`: unit and devnet coverage for replay,
  snapshots, roots, proofs, history, HTTP, and Swagger.
- `nix/`: Haskell.nix project and shell definitions.
- `docs/`: MkDocs documentation.
- `.specify/`: Spec Kit templates, scripts, and project constitution.
