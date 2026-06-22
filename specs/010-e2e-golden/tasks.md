# Tasks: E2E Golden Snapshot And Roots

## Slice 1 - Populated Devnet Epoch Snapshot

- [ ] T001 Add a focused e2e example that runs the existing devnet past an epoch boundary and records the ledger-derived mark snapshot.
- [ ] T002 Ensure the devnet fixture delegates stake into a populated `ssStakeMark`, using only `e2e-test/genesis/*` fixture edits if needed.
- [ ] T003 Assert the observed credential stake map is non-empty and matches the known genesis delegation oracle, with no LSQ.
- [ ] T004 Assert `stakeSnapshotTotalStake` equals the sum of the populated credential stake map, run the focused e2e command and `./gate.sh`, then commit as `test(e2e): assert populated devnet stake snapshot`.

## Slice 2 - Roots And Proof Golden From Real Snapshot

- [ ] T005 Build the epoch CSMT from the real populated snapshot and assert querying the epoch root succeeds.
- [ ] T006 Rebuild the same snapshot in a fresh CSMT database and assert the epoch root is reproducible.
- [ ] T007 Query and verify an inclusion proof for a real observed credential with `verifyCredentialProof`.
- [ ] T008 Finalize the epoch root into history, assert the stored epoch leaf, verify `buildEpochRootProof` with `verifyEpochRootProof`, run the focused e2e command and `./gate.sh`, then commit as `test(e2e): prove devnet stake roots and proofs`.

## Finalization

- [ ] T009 Run `nix develop -c just ci` at HEAD.
- [ ] T010 Run `nix build .#default .#e2e-tests` at HEAD.
- [ ] T011 Update the draft PR body with delivered behavior and verification evidence.
- [ ] T012 Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
