# Tasks: Per-Epoch Stake CSMT Builder

## Slice 1 - Dependency And Schema Foundation

- [X] T006-S1 Add `mts` / `mts:csmt` dependency wiring and expose CSMT schema modules.
- [X] T007-S1 Implement stable codecs for credentials, coins, epoch prefixes, CSMT nodes, and epoch root records.
- [X] T008-S1 Add focused unit tests for codec determinism and round trips.
- [X] T009-S1 Run `./gate.sh`, commit as `feat(csmt): add stake csmt schema foundation`, and stop for orchestration review.

## Slice 2 - Epoch Builder And Proofs

- [x] T010-S2 Implement the epoch CSMT builder over `StakeSnapshot`.
- [x] T011-S2 Implement root lookup and credential inclusion proof functions.
- [x] T012-S2 Add golden/determinism and proof verification tests over synthetic non-empty snapshots.
- [x] T013-S2 Run `./gate.sh`, commit as `feat(csmt): build epoch stake roots and proofs`, and stop for orchestration review.

## Slice 3 - RocksDB Persistence

- [x] T014-S3 Implement RocksDB-backed helpers or test harness for the CSMT columns.
- [x] T015-S3 Add close/reopen tests proving snapshot, tree, and root persistence.
- [x] T016-S3 Run `./gate.sh`, commit as `feat(csmt): persist epoch stake trees in rocksdb`, and stop for orchestration review.

## Slice 4 - Finalization

- [x] T017-S4 Update PR body with final schema contract and verification evidence.
- [x] T018-S4 Run `nix develop -c just ci`.
- [x] T019-S4 Drop `gate.sh`, commit `chore: drop gate.sh (ready for review)`, push, and mark PR ready.
