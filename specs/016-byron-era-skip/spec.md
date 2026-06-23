# Feature Specification: Byron-era Boundary Skip

**Feature Branch**: `fix/33-byron-era-skip`
**Issue**: #33
**Created**: 2026-06-23
**Status**: Draft

## P1 User Story

As an operator, I can run `cardano-stake-csmt` against preprod and have the
background indexer replay through Byron-era epoch boundaries that have no stake
distribution, then begin indexing normally from Shelley onward, instead of
crash-looping on `IndexerSnapshotError StakeSnapshotByronEra`.

## Acceptance Criteria

- At an epoch boundary where snapshot extraction returns
  `Left StakeSnapshotByronEra`, the indexer skips that boundary: no store write,
  no hook payload, no exception, and replay continues with the next state.
- Any non-Byron `StakeSnapshotError` remains fatal through
  `IndexerSnapshotError`.
- Post-Shelley epoch boundaries continue to index the extracted
  `StakeSnapshot` exactly as before.
- Regression coverage drives the Byron skip branch without needing a real
  preprod replay and also proves the post-Shelley indexing path still writes.
- Deterministic write ordering and transaction atomicity are unchanged.

## Functional Requirements

- **FR-001**: Keep `stakeSnapshotFromLedgerState` unchanged for Shelley and
  later eras.
- **FR-002**: Treat `StakeSnapshotByronEra` as an expected "no stake
  distribution" result at an epoch boundary.
- **FR-003**: Skip the write and report `Nothing` to the optional boundary hook
  for a Byron boundary.
- **FR-004**: Preserve fail-closed behavior for all other snapshot extraction
  errors.
- **FR-005**: Add focused unit coverage in `IndexerSpec` for Byron skip and
  post-Shelley indexing through the boundary decision seam.

## Non-Goals

- No change to proof/query semantics.
- No change to daemon wiring, ChainSync configuration, checkpoint retention, or
  store opening.
- No change to post-Shelley snapshot extraction.
- No dependency, Nix, or compiler changes.

## Success Criteria

- `nix develop --quiet -c just unit "Indexer"` is green.
- `./gate.sh` is green after the implementation slice.
- Before PR readiness, `just ci` and `nix build .#default` are green.
