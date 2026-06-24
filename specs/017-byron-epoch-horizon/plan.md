# Implementation Plan: Byron Replay Epoch Horizon

## Technical Context

- Language/tooling: Haskell, Cabal, Hspec, Fourmolu, Nix flakes with
  `compiler-nix-name = "ghc9123"`.
- Live failure: preprod replay reaches a Byron block at slot 23761, then
  `observedEpochAt` calls `ledgerConfigEpochAt bundle slot`, which queries the
  genesis-derived `EpochInfo` past its first-era horizon and throws
  `PastHorizonException`.
- Existing safe behavior: post-Shelley branches read the epoch from `nesEL` in
  the new epoch state.
- Existing replay configuration already carries `replayFollowerByronEpochSlots`
  and passes it to ChainSync as `EpochSlots`.
- Existing test module: `test/Cardano/StakeCSMT/Ledger/ReplaySpec.hs`.

## Design

Introduce a pure helper in `Cardano.StakeCSMT.Ledger.Replay`:

```haskell
byronEpochAt :: Word64 -> Word64 -> Word64
byronEpochAt byronEpochSlots slot = slot `div` byronEpochSlots
```

Then thread the configured Byron epoch length to the replay hot path so
`observedEpochAt` can use the helper for `LedgerStateByron`. The preferred
shape is to pass the epoch length alongside the bundle where `replayBlock` is
constructed from `ReplayFollowerConfig`; if a smaller local type adjustment is
clearer, the driver may choose it as long as arbitrary Byron slots no longer
query `ledgerConfigEpochAt`.

Keep `initialReplayState` unchanged: the slot 0 genesis epoch lookup is within
the static horizon and is explicitly allowed by the ticket.

Add focused unit coverage around the pure helper or the smallest testability
seam the driver introduces. The test must use a slot greater than 21600, such
as 23761 with an epoch length of 21600, and expect epoch 1 without throwing.

## Slice Breakdown

### Slice 1 - Byron Epoch Derivation

Implement horizon-free Byron epoch derivation in replay and focused regression
coverage.

Owned files:

- `lib/Cardano/StakeCSMT/Ledger/Replay.hs`
- `test/Cardano/StakeCSMT/Ledger/ReplaySpec.hs`
- `lib/Cardano/StakeCSMT/Ledger/Config.hs` only if a small horizon-free helper
  is proven necessary.

Focused gate:

```bash
nix develop --quiet -c just unit "Ledger.Replay"
./gate.sh
```

Commit:

```text
fix(replay): derive Byron epochs without EpochInfo horizon

Tasks: T001, T002, T003, T004, T005
```

### Slice 2 - Finalization

The ticket orchestrator reruns final gates, updates PR metadata, drops
`gate.sh`, marks the PR ready, and reports completion. No driver-owned code
edits belong in this slice.

## Verification

- Slice gate: `nix develop --quiet -c just unit "Ledger.Replay"` and
  `./gate.sh`.
- Completion gates: `just ci` and `nix build .#default`.
- If e2e files are touched, also run `nix build .#e2e-tests`.

## Risks

- Accidentally leaving the Byron branch on `ledgerConfigEpochAt` would preserve
  the live preprod crash.
- Dividing by an invalid epoch length should not be silently introduced; use the
  already validated configured Byron epoch slots.
- Broadening this into snapshot, daemon, or CLI behavior would risk regressing
  unrelated fixes and is out of scope.
