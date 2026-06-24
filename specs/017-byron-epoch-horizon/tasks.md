# Tasks: Byron Replay Epoch Horizon

## Slice 1 - Byron Epoch Derivation

- [X] T001 Add a narrow helper or testability seam for uniform Byron epoch
  derivation from Byron epoch slots and block slot.
- [X] T002 Replace the `LedgerStateByron` hot-path epoch lookup so arbitrary
  Byron block slots do not call `ledgerConfigEpochAt` or `epochInfoEpoch`.
- [X] T003 Preserve all post-Shelley epoch branches unchanged.
- [X] T004 Add focused `Ledger.ReplaySpec` coverage for a Byron slot greater
  than 21600 deriving the expected epoch without throwing.
- [X] T005 Run `nix develop --quiet -c just unit "Ledger.Replay"` and
  `./gate.sh`, then commit as
  `fix(replay): derive Byron epochs without EpochInfo horizon`.

## Slice 2 - Finalization

- [X] T006 Run `just ci` at HEAD.
- [X] T007 Run `nix build .#default` at HEAD.
- [X] T008 Update PR #36 body with delivered behavior and verification
  evidence.
- [X] T009 Drop `gate.sh` in
  `chore: drop gate.sh (ready for review)`, push, mark PR #36 ready, and report
  `COMPLETE` with PR URL plus head SHA.
