# Implementation Plan: Byron-era Boundary Skip

## Technical Context

- Language/tooling: Haskell, Cabal, Hspec, Fourmolu, Nix flakes with
  `compiler-nix-name = "ghc9123"`.
- Failing live path: `runIndexerWithIndexing` handles an epoch transition,
  calls `stakeSnapshotFromLedgerState`, and currently throws
  `IndexerSnapshotError` for every `Left`.
- Current snapshot errors: `StakeSnapshotError` has one constructor,
  `StakeSnapshotByronEra`. The implementation still must remain fail-closed if
  future constructors are added.
- Existing test module: `test/Cardano/StakeCSMT/IndexerSpec.hs`.

## Design

Add a small pure or IO-light boundary helper in
`Cardano.StakeCSMT.Indexer`. The helper should take the post-boundary epoch,
the snapshot extraction result, and the injected snapshot writer. It returns
`Nothing` when the boundary is Byron, calls the writer and returns its result
for successful snapshots, and throws `IndexerSnapshotError` for any other
snapshot error.

`runIndexerWithIndexing` should use this helper in the existing epoch
transition branch. The replay state returned by `replayBlock` remains the
return value in every branch. The optional hook remains called after boundary
handling; for Byron it receives `Nothing`, matching the "no indexed epoch"
shape already used for empty snapshots.

The helper gives the unit test a narrow seam that can pass
`Left StakeSnapshotByronEra` directly without constructing a Byron
`ExtLedgerState`. The same test module should verify that a successful snapshot
still calls the writer and persists the expected stores.

## Slice Breakdown

### Slice 1 - Boundary Decision

Implement the Byron skip behavior and focused regression coverage.

Owned files:

- `lib/Cardano/StakeCSMT/Indexer.hs`
- `test/Cardano/StakeCSMT/IndexerSpec.hs`

Focused gate:

```bash
nix develop --quiet -c just unit "Indexer"
./gate.sh
```

Commit:

```text
fix(indexer): skip Byron-era epoch boundaries

Tasks: T001, T002, T003, T004, T005
```

### Slice 2 - Finalization

The ticket orchestrator reruns final gates, updates PR metadata, drops
`gate.sh`, marks the PR ready, and reports completion. No driver-owned code
edits belong in this slice.

## Verification

- Baseline before implementation:
  `nix develop --quiet -c just unit "Indexer"` passed on 2026-06-23.
- Slice gate:
  `nix develop --quiet -c just unit "Indexer"` and `./gate.sh`.
- Completion gates:
  `just ci` and `nix build .#default`.

## Risks

- Treating all current errors as skippable would accidentally hide future
  non-Byron ledger extraction problems. Pattern match the Byron constructor
  explicitly and keep a fatal fallback.
- Hook semantics must remain stable for tests and callers. Byron should use the
  existing `Maybe IndexedEpoch` absence shape, not invent a second callback.
- The testability seam should stay internal to `Indexer.hs`; do not widen the
  public API unless the code genuinely requires it.
