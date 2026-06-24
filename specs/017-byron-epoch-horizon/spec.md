# Feature Specification: Byron Replay Epoch Horizon

**Feature Branch**: `fix/35-byron-epoch-horizon`
**Issue**: #35
**Created**: 2026-06-24
**Status**: Draft

## P1 User Story

As an operator, I can run `cardano-stake-csmt` against preprod and replay the
full Byron era without `PastHorizonException`, because Byron block epochs are
derived from the uniform Byron epoch length instead of the genesis
`EpochInfo`.

## Acceptance Criteria

- The Byron branch of replay epoch observation computes `slot div
  byronEpochSlots` with a horizon-free Byron epoch length.
- Replay does not call `ledgerConfigEpochAt` or `epochInfoEpoch` for arbitrary
  Byron block slots on the hot path. The genesis query at slot 0 remains fine.
- Post-Shelley epoch derivation continues to read `nesEL` from the ledger state
  and is otherwise untouched.
- A regression test exercises a Byron-era slot greater than 21600 and asserts
  the uniform epoch result without throwing.
- Replay determinism and checkpoint behavior remain unchanged.

## Functional Requirements

- **FR-001**: Add a narrow, unit-testable helper for uniform Byron epoch
  derivation from a block slot and Byron epoch length.
- **FR-002**: Route the `LedgerStateByron` branch of `observedEpochAt` through
  the horizon-free helper instead of `ledgerConfigEpochAt`.
- **FR-003**: Source the Byron epoch length from existing replay configuration,
  or from an existing horizon-free ledger configuration value if needed.
- **FR-004**: Keep the Shelley, Allegra, Mary, Alonzo, Babbage, Conway, and
  Dijkstra branches byte-for-byte equivalent in behavior.
- **FR-005**: Add focused `Ledger.ReplaySpec` coverage proving a slot beyond
  the first-era horizon derives the expected Byron epoch without IO failure.

## Non-Goals

- No change to post-Shelley epoch derivation.
- No change to snapshot extraction or the #33 Byron boundary skip behavior.
- No change to CLI, daemon wiring, network configuration, or ChainSync setup
  except threading an already configured Byron epoch length into replay epoch
  observation if that is the smallest viable implementation.
- No dependency, Nix, or compiler changes.

## Success Criteria

- `nix develop --quiet -c just unit "Ledger.Replay"` is green after the
  implementation slice.
- `./gate.sh` is green after the implementation slice.
- Before readiness, both `just ci` and `nix build .#default` are green locally.
