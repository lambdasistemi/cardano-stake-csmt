# Tasks: Rollback Checkpoint And Replay Tail

## Slice 1 - Checkpoint Store Foundation

- [x] T001-S1 Add `Cardano.StakeCSMT.Ledger.Checkpoint` with checkpoint point metadata, nearest-at-or-before lookup, and bounded replay-tail helpers.
- [x] T002-S1 Add checkpoint encode/decode and file-backed save/load/list helpers for finalized-boundary checkpoint metadata, explicitly avoiding hand-rolled full `ExtLedgerState` serialization.
- [x] T003-S1 Register the checkpoint module, unit test module, and required library/test dependencies in `cardano-stake-csmt.cabal` and `test/main.hs`.
- [x] T004-S1 Add focused unit tests proving finalized-boundary checkpoint round-trip, nearest checkpoint selection, and replay-tail truncation/recovery behavior.
- [x] T005-S1 Run `./gate.sh` and commit as `feat(ledger): add replay checkpoint store`.

## Slice 2a - Checkpoint Tail Continuity Hardening

- [x] T006-S2A Add a focused checkpoint regression for the boundary-before-oldest retained-tail case.
- [x] T007-S2A Harden `recoverReplayTail` so it rejects gapped retained tails when the selected boundary is not covered.
- [x] T008-S2A Run `./gate.sh` and commit as `fix(ledger): reject gapped replay tails`.

## Slice 2b - Replay Rollback Integration

- [X] T009-S2B Extend `Cardano.StakeCSMT.Ledger.Replay` with checkpoint-aware follower configuration while preserving the existing runner API.
- [X] T010-S2B On roll-forward, save checkpoints at the configured cadence and retain fetched blocks in the checkpoint replay tail.
- [X] T011-S2B On reachable non-origin rollback, re-derive from the finalized-boundary checkpoint plus tail, truncate volatile tail state, and continue with `Progress`.
- [X] T012-S2B On unreachable non-origin rollback, return `Reset intersector` rather than fabricating ledger state.
- [X] T013-S2B Add replay unit tests for reachable rollback, unreachable rollback, origin rollback, and post-rollback continuation.
- [X] T014-S2B Run `./gate.sh` and commit as `feat(ledger): rewind replay state on rollback`.

## Slice 3a - E2E Replay Recovery Proof

- [X] T015-S3A Extend e2e replay coverage with a devnet finalized-boundary checkpoint/rollback/replay-tail recovery proof.
- [X] T016-S3A Verify ledger state re-derived from the finalized boundary and recovered replay observation matches direct replay to the same point.
- [X] T017-S3A Run `./gate.sh` and commit as `test(e2e): prove checkpoint rollback recovery`.

## Slice 3b - E2E History Invariance Proof

- [ ] T018-S3B Verify a finalized history root/leaf written before the volatile rollback remains unchanged after recovery.
- [ ] T019-S3B Register any e2e-only dependency needed by the test, without changing CSMT or history modules.
- [ ] T020-S3B Run `./gate.sh` and commit as `test(e2e): prove rollback preserves history`.

## Finalization

- [ ] T021-F Run `nix develop -c just ci` at HEAD.
- [ ] T022-F Update PR body with delivered behavior and verification evidence.
- [ ] T023-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
