# Snapshot Extraction: ssStake Credential Stake + totalStake

## P1 User Story

As the stake CSMT service, at each epoch boundary I can extract the ledger's mark stake snapshot as `credential -> Coin` and compute `totalStake = sum ssStake`, so later tickets can commit the epoch's voting denominator with the stake root.

## Acceptance Criteria

- The library exposes `Cardano.StakeCSMT.Ledger.StakeSnapshot`.
- The extractor is pure over `ExtLedgerState StakeBlock ValuesMK`; it does not perform IO, network access, LSQ, replay, persistence, or CSMT construction.
- The extractor projects the current era from the Cardano hard-fork ledger state and accepts every Shelley-based era from Shelley through Dijkstra.
- The extractor rejects Byron current-era ledger state explicitly.
- The snapshot source is the mark snapshot: `ssStakeMark` from `esSnapshots (nesEs newEpochState)`.
- The credential map is materialized as `Credential 'Staking -> Coin`, converting compact stake values to `Coin`.
- `totalStake` is computed from exactly the extracted mark stake values, not reconstructed from certificates and not read from pool distribution.
- Unit coverage loads the known devnet genesis ledger state and asserts the extracted stake snapshot and total against the configured genesis delegation/funds.

## Functional Requirements

- FR-001: Provide a data type carrying the credential stake map and `totalStake`.
- FR-002: Provide a public pure function from `ExtLedgerState StakeBlock ValuesMK` to either a snapshot or an explicit extraction error.
- FR-003: Use consensus Cardano `LedgerState*` pattern synonyms to inspect the current era of the hard-fork ledger state.
- FR-004: Use Shelley ledger `NewEpochState` accessors and `ssStakeMark`/`ssStake`/`unStake` for extraction.
- FR-005: Register the module in the public library and register its unit test.

## Non-Goals

- No CSMT root/proof construction.
- No history accumulator or `(epoch, stakeRoot, totalStake)` leaf.
- No rollback/checkpoint work.
- No HTTP API.
- No Nix, CHaP, SRP, or closure changes inherited from issue #4.
