# Specification: E2E Golden Snapshot And Roots

## P1 User Story

As a maintainer, I can run the e2e suite against a local devnet that crosses an epoch boundary and see the complete stake CSMT stack proven from real ledger data: populated credential stake, total stake, reproducible epoch root, accumulated history root, and verifying inclusion proofs.

## Acceptance Criteria

- The e2e devnet boots from controlled genesis fixtures and runs past at least one epoch boundary.
- The test observes a populated `ssStakeMark` snapshot from the replayed ledger state. Empty snapshots do not satisfy this ticket.
- The observed snapshot contains real `Credential Staking -> Coin` entries that match the known devnet genesis delegation oracle, allowing for any deterministic rewards produced by the devnet run.
- `stakeSnapshotTotalStake` equals the sum of the populated credential stake map.
- Building the same epoch snapshot twice produces the same epoch CSMT root.
- Finalizing the epoch root accumulates a history root and stores the same epoch leaf.
- A proof for a real observed credential verifies against the epoch root through `verifyCredentialProof`.
- The epoch root proof verifies against the history root through `verifyEpochRootProof`.
- The test uses no LSQ and makes no production-library changes.

## Non-Goals

- No mainnet replay or long bootstrap tuning.
- No changes to production replay, snapshot, CSMT, history, or HTTP modules.
- No new proof format, hashing format, or on-chain verifier behavior.

## Clarifications

- The devnet genesis is the oracle. The test should assert against the known delegated stake controlled by the fixture instead of querying LSQ.
- The existing synthetic finalized snapshot helper is useful for rollback regression coverage but is not enough for this ticket because it does not prove a populated ledger-derived `ssStakeMark`.
- Prefer extending `e2e-test/Cardano/StakeCSMT/E2E/ReplaySpec.hs` so the cabal test-suite manifest does not need new module entries.
