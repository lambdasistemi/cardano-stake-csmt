# Tasks: History Accumulator

## Slice 1 - History Codecs And Columns

- [ ] T001-S1 Add `Cardano.StakeCSMT.History.Codecs` with a stable history prefix, unit key codec, and epoch-root-to-hash helper covering `EpochRoot` including `totalStake`.
- [ ] T002-S1 Add `Cardano.StakeCSMT.History.Columns` with leaf, tree, and current-root columns plus codecs.
- [ ] T003-S1 Register new history modules and tests in `cardano-stake-csmt.cabal` and `test/main.hs`.
- [ ] T004-S1 Add focused codec/column tests proving deterministic prefixing and total-stake-sensitive leaf hashing.
- [ ] T005-S1 Run `./gate.sh` and commit as `feat(history): add history storage codecs`.

## Slice 2 - History Builder And Proofs

- [ ] T006-S2 Add `Cardano.StakeCSMT.History.Builder` with `finalizeEpochRoot`, `queryHistoryRoot`, `queryHistoryLeaf`, `buildEpochRootProof`, and `verifyEpochRootProof`.
- [ ] T007-S2 Add in-memory builder tests for deterministic history roots, proof success, and failure on wrong epoch, stake root, total stake, and history root.
- [ ] T008-S2 Keep history code isolated from rollback and HTTP scope.
- [ ] T009-S2 Run `./gate.sh` and commit as `feat(history): build epoch root accumulator`.

## Slice 3 - History RocksDB Persistence

- [ ] T010-S3 Add `Cardano.StakeCSMT.History.RocksDB` with history-specific RocksDB column families and typed database adapter.
- [ ] T011-S3 Add a RocksDB test proving leaves, tree nodes, current root, and epoch-root proofs persist across reopen.
- [ ] T012-S3 Register the RocksDB module/test in cabal and `test/main.hs` if not already covered.
- [ ] T013-S3 Run `./gate.sh` and commit as `feat(history): persist history accumulator`.

## Finalization

- [ ] T014-F Run `nix develop -c just ci` at HEAD.
- [ ] T015-F Update PR body with delivered behavior and verification evidence.
- [ ] T016-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
