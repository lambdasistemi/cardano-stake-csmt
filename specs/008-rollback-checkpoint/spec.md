# Feature Specification: Rollback Checkpoint And Replay Tail

## P1 User Story

As the service, on a near-tip rollback I rewind the in-memory ledger state and re-apply forward, and observe state and the latest tree consistent with the new chain while finalized epoch roots stay untouched.

## Scope

Build rollback support for the library replay state. The replay layer stores finalized-boundary checkpoints, keeps enough recent fetched blocks to replay from the nearest finalized boundary to a rollback point, and rewinds non-origin rollbacks without discarding finalized epoch history.

A-002 pivot note: full `ExtLedgerState` snapshot serialization was attempted with the consensus snapshot envelope, the full `CardanoCodecConfig`, and the UTxO-HD separate-tables shape. Both focused attempts failed at the HFC ledger-state decode boundary, and the parent authorized the finalized-boundary replay design instead of hand-rolled serialization. This is not a weakening of rollback safety: the checkpoint is the immutable finalized boundary, and the volatile ledger state is re-derived by replaying retained blocks.

The feature is limited to ledger-state checkpoint and rewind behavior. It consumes the #4 replay API, #6 epoch CSMT root model, and #7 history invariant, but does not change the CSMT or history schemas.

## User Stories

1. As a replay worker, I can persist a finalized-boundary checkpoint and later use it as the deterministic replay base for volatile recovery.
2. As a chain follower, I can handle a near-tip rollback by loading the nearest finalized-boundary checkpoint at or before the rollback point, replaying retained blocks forward to that point, and continuing from the rewound state.
3. As an operator, I can configure checkpoint cadence and tail retention so rollback support is bounded and predictable.
4. As a proof service, I can trust that finalized epoch roots already committed to the history accumulator are not mutated by a near-tip rollback.

## Functional Requirements

- FR-001: The library MUST expose a `Cardano.StakeCSMT.Ledger.Checkpoint` module for checkpoint encoding, decoding, persistence, lookup, and replay-tail management.
- FR-002: Checkpoints MUST persist finalized-boundary metadata and replay-tail state sufficient to re-derive volatile `ReplayState` from the immutable boundary; they MUST NOT hand-roll full `ExtLedgerState` serialization.
- FR-003: Checkpoint lookup MUST choose the nearest checkpoint whose point is at or before the rollback point.
- FR-004: Rewind MUST replay retained blocks after the checkpoint and up to the rollback point by reusing the existing trusted `replayBlock` path.
- FR-005: If no checkpoint/tail combination can reach the requested non-origin rollback point, the replay follower MUST reset through its intersector rather than silently using the wrong state.
- FR-006: The replay follower MUST retain only near-tip volatile block state; finalized epoch CSMT roots and history leaves remain immutable and outside rollback mutation.
- FR-007: The checkpoint/tail API MUST be testable without a live node, and the e2e test MUST exercise the real devnet replay path.

## Non-Goals

- HTTP API or proof endpoints (#9).
- Changing `Cardano.StakeCSMT.CSMT.*` or `Cardano.StakeCSMT.History.*` schemas.
- Re-validating blocks; replay continues to use trusted `reapply`.
- Rolling back already-finalized history.
- Mainnet bootstrap tuning or production retention policy tuning.

## Acceptance Criteria

- AC-001: Unit tests prove finalized-boundary checkpoint persistence round-trips boundary point/epoch metadata and supports deterministic replay-tail recovery.
- AC-002: Unit tests prove rollback chooses the nearest checkpoint at or before the target point and replays only the required tail.
- AC-003: Replay follower tests prove a non-origin rollback rewinds via checkpoint/tail and continues without resetting when the rollback is within retention.
- AC-004: Replay follower tests prove a non-origin rollback outside retention resets rather than fabricating state.
- AC-005: E2E recovery test replays the devnet, simulates a near-tip rollback, verifies the recomputed state/tree is consistent, and verifies finalized roots already in history remain unchanged.
- AC-006: `nix develop -c just ci` passes before the PR is marked complete.
