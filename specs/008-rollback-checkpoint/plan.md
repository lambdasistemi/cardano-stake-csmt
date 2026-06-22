# Implementation Plan: Rollback Checkpoint And Replay Tail

## Technical Context

- Language/tooling: Haskell, cabal, Nix dev shell, hspec.
- Existing replay surface: `Cardano.StakeCSMT.Ledger.Replay` threads `ReplayState` with `ExtLedgerState StakeBlock ValuesMK` and applies blocks via `tickThenReapply` plus `applyDiffs`.
- Existing follower behavior: origin rollback currently progresses; non-origin rollback currently resets the intersector.
- Existing persistence style: small library modules with explicit export lists, focused hspec tests, and RocksDB helpers isolated from core logic.
- Consensus codec discovery: `Ouroboros.Consensus.Ledger.Extended` exposes `encodeExtLedgerState`/`decodeExtLedgerState`; `Ouroboros.Consensus.Storage.Serialisation` exposes disk helpers. Slice 1 attempted the consensus snapshot envelope with the full `CardanoCodecConfig` and the UTxO-HD separate-tables shape; both focused attempts failed at the HFC ledger-state decode boundary.
- Pivot decision (A-002): do not hand-roll ledger-state serialization and do not keep grinding the full-state codec. Treat the checkpoint as the most recent finalized epoch boundary and re-derive volatile in-memory ledger state by replaying retained blocks forward from that immutable boundary.

## Architecture

Add `Cardano.StakeCSMT.Ledger.Checkpoint` as the only new rollback module. It owns:

- finalized-boundary checkpoint metadata for origin/at-block points and last observed/finalized epochs;
- file-backed persistence for finalized-boundary checkpoints and replay-tail blocks, not full `ExtLedgerState` blobs;
- a small file-backed checkpoint store;
- an in-memory replay tail of recent `Fetched` blocks;
- lookup/rewind helpers that choose the nearest finalized boundary at or before the rollback point and replay retained blocks with the caller's `replayBlock` action.

`Ledger.Replay` remains the integration point. The existing `runReplayFollowerWith` stays available for tests and simple callers. A new checkpoint-aware runner or configuration extends follower construction so non-origin rollback can return `Progress` when the rollback point is reachable from the checkpoint/tail store, and `Reset` when it is not.

The replay tail is volatile. It exists only to repair the current in-memory ledger state inside the rollback window. Finalized epoch roots in `Cardano.StakeCSMT.CSMT.*` and finalized history leaves in `Cardano.StakeCSMT.History.*` are not deleted, rewritten, or re-keyed by this ticket.

## Slices

### Slice 1: Checkpoint Store Foundation

Create the checkpoint module and focused unit tests:

- checkpoint point metadata and ordering;
- finalized-boundary checkpoint encode/decode round-trip;
- file-backed save/load/list/nearest-checkpoint helpers;
- bounded replay-tail insertion/truncation helpers;
- cabal module/test registration and any required library dependencies.

This slice makes the A-002 pivot explicit: rollback recovery is proved by finalized-boundary selection plus replay-tail retention, while full `ExtLedgerState` serialization is not used.

### Slice 2a: Checkpoint Tail Continuity Hardening

Harden the checkpoint replay-tail foundation before integrating it into
`Ledger.Replay`:

- add a focused regression for the discovered boundary-before-oldest case;
- make `recoverReplayTail` reject gapped retained tails when the selected
  boundary is not covered by the current tail;
- keep the slice scoped to `Ledger.Checkpoint` and its focused unit tests.

This slice was split out of the original replay-integration slice after the
RED work repeatedly stalled while trying to cover checkpoint continuity and
replay follower integration in the same pass. The landed checkpoint-continuity
RED is kept as the first narrow target; replay follower integration moves to
Slice 2b.

### Slice 2b: Replay Rollback Integration

Wire the checkpoint API into `Ledger.Replay`:

- record checkpoints during roll-forward according to a small cadence/retention config;
- retain fetched blocks in the replay tail;
- on non-origin `rollBackward`, rewind from nearest checkpoint plus tail and return `Progress` when possible;
- fall back to `Reset intersector` when the rollback target is outside checkpoint/tail retention;
- preserve the current origin rollback behavior.

Unit tests use a fake chain-sync runner and synthetic `Fetched` blocks/actions
to prove reachable rollback from the finalized boundary, unreachable rollback,
origin rollback preservation, and post-rollback continuation. This slice starts
only after Slice 2a proves checkpoint tail coverage cannot silently accept a
gap.

### Slice 3a: E2E Replay Recovery Proof

Extend the devnet replay e2e coverage:

- replay a devnet chain to collect a direct state/root baseline;
- simulate a near-tip rollback through the finalized-boundary checkpoint/tail API;
- reapply from the finalized boundary through the retained tail and compare the recovered state/root with a direct replay to the same point.

This slice is intentionally limited to the replay/checkpoint e2e surface. It
was split from the original Slice 3 after the driver crossed from the replay
RED target into the separate CSMT/history proof surface without producing an
artifact, matching the same broad-slice failure pattern found in Slice 2.

### Slice 3b: E2E History Invariance Proof

Extend the e2e recovery proof to cover finalized history invariance:

- create a finalized history root before the volatile rollback;
- recover through the finalized-boundary checkpoint/tail path;
- assert the previously finalized history root/leaf remains unchanged after recovery.

This slice may reuse existing CSMT/history builders as consumers, but must not
change their modules or schemas.

## Verification

Each implementation slice runs the focused test named in the slice brief and then `./gate.sh` before committing.

The final ticket gate is:

```sh
nix develop -c just ci
```

The ticket owner reruns `./gate.sh` before accepting each implementation commit and reruns the final gate at HEAD before marking the PR complete.
