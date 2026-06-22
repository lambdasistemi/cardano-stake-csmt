# Tasks: Indexer Engine

## Slice 1 - Writer Primitive

- [X] T001-S1 Add `lib/Cardano/StakeCSMT/Indexer.hs` with `IndexedEpoch`,
  `EpochBoundaryHook`, and `indexStakeSnapshot`.
- [X] T002-S1 Add `test/Cardano/StakeCSMT/IndexerSpec.hs` covering non-empty
  snapshot writes, stored epoch root, current history root, credential proof
  verification, and epoch-root history proof verification.
- [X] T003-S1 Register the library module and unit spec in
  `cardano-stake-csmt.cabal` and `test/main.hs`.
- [X] T004-S1 Run `nix develop --quiet -c just unit "Indexer"` and
  `./gate.sh`, then commit as `feat(indexer): add epoch snapshot writer`.

## Slice 2 - Replay Checkpoint Indexer

- [ ] T005-S2 Extend `lib/Cardano/StakeCSMT/Indexer.hs` with `runIndexer`,
  `runIndexerWith`, and `withIndexer` over supplied database handles,
  replay config, checkpoint config, and optional epoch-boundary hook.
- [ ] T006-S2 Add `e2e-test/Cardano/StakeCSMT/E2E/IndexerSpec.hs` that
  captures devnet blocks, replays them through the indexer twice, asserts
  deterministic roots, verifies credential and history proofs, and exercises
  checkpoint recovery.
- [ ] T007-S2 Register the e2e spec in `cardano-stake-csmt.cabal` and
  `e2e-test/main.hs` without changing config, daemon wiring, or HTTP
  semantics.
- [ ] T008-S2 Run `nix develop --quiet -c just e2e` and `./gate.sh`, then
  commit as `feat(indexer): replay finalized epoch boundaries`.

## Slice 3 - Finalization

- [ ] T009-F Run `just ci` at HEAD.
- [ ] T010-F Run `nix build .#default` and `nix build .#e2e-tests` at HEAD.
- [ ] T011-F Update PR #30 body with delivered behavior and verification
  evidence.
- [ ] T012-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)`,
  push, mark the PR ready, and report COMPLETE with PR URL and head SHA.
