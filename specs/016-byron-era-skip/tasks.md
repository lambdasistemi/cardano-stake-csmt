# Tasks: Byron-era Boundary Skip

## Slice 1 - Boundary Decision

- [ ] T001 Add a narrow boundary-handling seam in
  `lib/Cardano/StakeCSMT/Indexer.hs` that skips `StakeSnapshotByronEra`.
- [ ] T002 Preserve fatal `IndexerSnapshotError` behavior for any non-Byron
  snapshot extraction error.
- [ ] T003 Add focused `IndexerSpec` coverage proving Byron boundaries skip
  without writes or exceptions.
- [ ] T004 Add focused `IndexerSpec` coverage proving successful post-Shelley
  snapshots still index through the same boundary helper.
- [ ] T005 Run `nix develop --quiet -c just unit "Indexer"` and `./gate.sh`,
  then commit as `fix(indexer): skip Byron-era epoch boundaries`.

## Slice 2 - Finalization

- [ ] T006 Run `just ci` at HEAD.
- [ ] T007 Run `nix build .#default` at HEAD.
- [ ] T008 Update PR #34 body with delivered behavior and verification
  evidence.
- [ ] T009 Drop `gate.sh` in `chore: drop gate.sh (ready for review)`, push,
  mark PR #34 ready, and report `COMPLETE` with PR URL plus head SHA.
