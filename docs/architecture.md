# Architecture

The scaffold separates pure stake and tree logic from the impure service boundary. The current codebase only provides the package structure and service health surface; the ledger and CSMT flows below describe the intended architecture for later slices.

## Boundaries

- Pure core modules will hold stake snapshots, root calculation, proof construction, and verification-facing types.
- The impure shell will own node connection, scheduling, persistence, logging, and HTTP delivery.
- HTTP endpoints currently cover health and readiness only.

## Planned data flow

1. Follow Cardano ChainSync from Origin over N2C.
2. Apply trusted-chain blocks with ledger `reapply`.
3. At each epoch boundary, read the ledger `ssStake` snapshot.
4. Build a history leaf containing `epoch`, `stakeRoot`, and `totalStake`.
5. Publish CSMT roots and proofs compatible with `mts:csmt` and `aiken-csmt`.

## Finality model

Epoch roots deeper than the Cardano security parameter `k` are treated as immutable. Shallower roots remain subject to chain rollback handling until finalized.
