# Implementation Plan: Rollback Checkpoint And Replay Tail

## Technical Context

- Language/tooling: Haskell, cabal, Nix dev shell, hspec.
- Existing replay surface: `Cardano.StakeCSMT.Ledger.Replay` threads `ReplayState` with `ExtLedgerState StakeBlock ValuesMK` and applies blocks via `tickThenReapply` plus `applyDiffs`.
- Existing follower behavior: origin rollback currently progresses; non-origin rollback currently resets the intersector.
- Existing persistence style: small library modules with explicit export lists, focused hspec tests, and RocksDB helpers isolated from core logic.
- Consensus codec discovery: `Ouroboros.Consensus.Ledger.Extended` exposes `encodeExtLedgerState`/`decodeExtLedgerState`; `Ouroboros.Consensus.Storage.Serialisation` exposes disk helpers. The implementation must prove the selected codec in a RED/GREEN checkpoint round-trip test before depending on it.

## Architecture

Add `Cardano.StakeCSMT.Ledger.Checkpoint` as the only new rollback module. It owns:

- checkpoint metadata for origin/at-block points and last observed epoch;
- `ReplayState` checkpoint encode/decode helpers;
- a small file-backed checkpoint store;
- an in-memory replay tail of recent `Fetched` blocks;
- lookup/rewind helpers that restore a checkpoint and replay retained blocks with the caller's `replayBlock` action.

`Ledger.Replay` remains the integration point. The existing `runReplayFollowerWith` stays available for tests and simple callers. A new checkpoint-aware runner or configuration extends follower construction so non-origin rollback can return `Progress` when the rollback point is reachable from the checkpoint/tail store, and `Reset` when it is not.

The replay tail is volatile. It exists only to repair the current in-memory ledger state inside the rollback window. Finalized epoch roots in `Cardano.StakeCSMT.CSMT.*` and finalized history leaves in `Cardano.StakeCSMT.History.*` are not deleted, rewritten, or re-keyed by this ticket.

## Slices

### Slice 1: Checkpoint Store Foundation

Create the checkpoint module and focused unit tests:

- checkpoint point metadata and ordering;
- checkpoint encode/decode round-trip for `ReplayState`;
- file-backed save/load/list/nearest-checkpoint helpers;
- bounded replay-tail insertion/truncation helpers;
- cabal module/test registration and any required library dependencies.

This slice proves the consensus codec works before replay integration depends on it.

### Slice 2: Replay Rollback Integration

Wire the checkpoint API into `Ledger.Replay`:

- record checkpoints during roll-forward according to a small cadence/retention config;
- retain fetched blocks in the replay tail;
- on non-origin `rollBackward`, rewind from nearest checkpoint plus tail and return `Progress` when possible;
- fall back to `Reset intersector` when the rollback target is outside checkpoint/tail retention;
- preserve the current origin rollback behavior.

Unit tests use a fake chain-sync runner and synthetic `Fetched` blocks/actions to prove reachable rollback, unreachable rollback, and post-rollback continuation.

### Slice 3: E2E Recovery Proof

Extend the devnet replay e2e coverage:

- replay a devnet chain to collect a direct state/root baseline;
- simulate a near-tip rollback through the checkpoint/tail API;
- reapply the retained tail and compare the recovered state/root with a direct replay to the same point;
- create a finalized history root before the volatile rollback and assert it is unchanged after recovery.

This test may reuse existing CSMT/history builders as consumers, but must not change their modules or schemas.

## Verification

Each implementation slice runs the focused test named in the slice brief and then `./gate.sh` before committing.

The final ticket gate is:

```sh
nix develop -c just ci
```

The ticket owner reruns `./gate.sh` before accepting each implementation commit and reruns the final gate at HEAD before marking the PR complete.
