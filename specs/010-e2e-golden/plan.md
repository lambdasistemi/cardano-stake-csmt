# Implementation Plan: E2E Golden Snapshot And Roots

## Technical Context

- Language/tooling: Haskell, cabal, Nix dev shell, hspec, `cardano-node-clients:devnet`.
- Test entry point: `e2e-test/main.hs` calls `Cardano.StakeCSMT.E2E.ReplaySpec.spec`.
- Existing devnet fixture root: `e2e-test/genesis`.
- Existing e2e helpers already boot `withCardanoNode`, load the generated node runtime config, replay blocks from origin, and exercise rollback/checkpoint behavior.
- Snapshot API: `stakeSnapshotFromLedgerState` extracts `ssStakeMark` from `ExtLedgerState`.
- Root/proof APIs: `buildEpochCSMT`, `queryEpochRoot`, `buildCredentialProof`, `verifyCredentialProof`, `finalizeEpochRoot`, `queryHistoryRoot`, `queryHistoryLeaf`, `buildEpochRootProof`, and `verifyEpochRootProof`.
- Constraint: do not edit production `lib/`, `http/`, or application modules. This ticket is e2e-only.

## Architecture

Add a live-boundary golden path inside the existing replay e2e spec:

- run the controlled devnet long enough to observe an epoch transition after delegated stake is active;
- capture the replay state at the epoch boundary and extract `StakeSnapshot` from the ledger state;
- assert the snapshot is non-empty and matches the known fixture delegation oracle;
- use that real snapshot to build the epoch CSMT, query an inclusion proof for an observed credential, finalize the history root, and verify the epoch-root proof;
- rebuild the same snapshot in a fresh CSMT database and assert the epoch root is reproducible.

Keep the proof assertions in-process through the existing builders and verifiers. The HTTP `/proof` layer was covered in #9; this ticket must consume the same proof API semantics without changing HTTP code.

## Slice 1: Populated Devnet Epoch Snapshot

Owned files:

- `e2e-test/Cardano/StakeCSMT/E2E/ReplaySpec.hs`
- `e2e-test/genesis/*` only if the existing fixture does not delegate stake into `ssStakeMark`

Work:

- Add a focused e2e example that runs the devnet past an epoch boundary.
- Capture the first replay state whose `ssStakeMark` is populated after the boundary.
- Assert at least one real staking credential is present.
- Assert every expected genesis delegated credential is present with the expected lower-bound or exact coin value justified by the fixture.
- Assert `stakeSnapshotTotalStake` equals the sum of the observed stake map.

Focused proof command:

```sh
nix develop --quiet -c cabal test e2e-tests -O0 --test-show-details=direct --test-options='--match "/Replay devnet proof/populated/"'
```

Commit subject:

```text
test(e2e): assert populated devnet stake snapshot
```

Tasks trailer: `Tasks: T001, T002, T003, T004`

## Slice 2: Roots And Proof Golden From Real Snapshot

Owned files:

- `e2e-test/Cardano/StakeCSMT/E2E/ReplaySpec.hs`

Work:

- Build the epoch CSMT from the real populated snapshot captured in Slice 1.
- Rebuild the same snapshot in a fresh database and assert the epoch root is identical.
- Query a proof for a real observed credential and verify it with `verifyCredentialProof`.
- Finalize the epoch root into history, assert the stored leaf equals the epoch root, and verify `buildEpochRootProof` with `verifyEpochRootProof`.
- Keep the synthetic rollback history helper intact unless the test naturally shares helper code.

Focused proof command:

```sh
nix develop --quiet -c cabal test e2e-tests -O0 --test-show-details=direct --test-options='--match "/Replay devnet proof/golden/"'
```

Commit subject:

```text
test(e2e): prove devnet stake roots and proofs
```

Tasks trailer: `Tasks: T005, T006, T007, T008`

## Finalization

The ticket owner reruns:

```sh
nix develop -c just ci
nix build .#default .#e2e-tests
```

Then the ticket owner updates PR metadata, drops `gate.sh` in the final ready-for-review commit, and marks the PR ready only after all tasks are checked.
