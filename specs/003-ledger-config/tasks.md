# Tasks: Ledger Config

## Slice 1 - Ledger Config Vertical

- [X] T301 Add `Cardano.StakeCSMT.Ledger.Config` with a project-level block alias, input paths, and loader bundle exposing `ProtocolInfo`, genesis `ExtLedgerState`, `LedgerConfig`, `TopLevelConfig`, era history, and `EpochInfo`.
- [X] T302 Add the minimum consensus and ledger dependencies to the public `library` component and unit-test component.
- [X] T303 Vendor the devnet genesis fixture under `test/fixtures/devnet-genesis/`.
- [X] T304 Add a unit spec that loads the fixture, asserts the genesis ledger state can be obtained, and queries epoch `0` without LSQ or networking.
- [X] T305 Run `./gate.sh`, commit the slice with subject `feat: add ledger config loader`, and include trailer `Tasks: T301, T302, T303, T304, T305`.

## Slice 2 - Fresh Cabal CI CHaP Access

- [ ] T306 Make the CI build job use flake-owned Haskell outputs so it does not depend on runner-global Cabal indexes for CHaP.
