# Snapshot Extraction Tasks

## Slice 1 - Pure Stake Snapshot Extractor

- [ ] T005-S1 Add `Cardano.StakeCSMT.Ledger.StakeSnapshot` with a pure extractor from `ExtLedgerState StakeBlock ValuesMK`.
- [ ] T005-S1 Project the current Cardano hard-fork ledger state and accept Shelley through Dijkstra while rejecting Byron explicitly.
- [ ] T005-S1 Extract `ssStakeMark`, materialize `Credential 'Staking -> Coin`, and compute `totalStake` from the same stake values.
- [ ] T005-S1 Register the module and test in Cabal/test main without changing Nix, SRPs, or project closure files.
- [ ] T005-S1 Add unit coverage against the decoded devnet genesis ledger state.
- [ ] T005-S1 Run `nix develop -c just unit "Ledger.StakeSnapshot"` and `./gate.sh`.
- [ ] T005-S1 Commit as `feat(ledger): extract credential stake snapshots` with trailer `Tasks: T005-S1`.
