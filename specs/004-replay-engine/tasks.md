# Tasks: Replay Engine

## Slice 1 - Pure Replay Core

- [ ] T401 Add `Cardano.StakeCSMT.Ledger.Replay` with the public replay state, epoch transition type, initial state constructor, and `replayBlock` implemented with consensus `tickThenReapply`.
- [ ] T402 Preserve ledger table values after each reapply using the consensus table-diff utilities.
- [ ] T403 Add unit coverage for replay state initialization and epoch callback de-duplication.
- [ ] T404 Expose the module and test module in `cardano-stake-csmt.cabal` / `test/main.hs`.
- [ ] T405 Run the focused replay unit test and `./gate.sh`, then commit with subject `feat: add ledger replay core` and trailer `Tasks: T401, T402, T403, T404, T405`.

## Slice 2 - N2C Replay Follower

- [ ] T406 Add N2C follower configuration and a follower entry point that starts from Origin.
- [ ] T407 Wire `Cardano.Node.Client.N2C.ChainSync` full-block `Fetched` values through a `ChainFollower.Follower` that threads `ReplayState`.
- [ ] T408 Add only the dependency manifest entries needed for `cardano-node-clients`, `chain-follower`, and imported consensus/network support.
- [ ] T409 Add unit coverage using an injectable ChainSync runner or follower constructor so state threading is verified without a live node.
- [ ] T410 Run the focused replay unit test and `./gate.sh`, then commit with subject `feat: wire replay through n2c chainsync` and trailer `Tasks: T406, T407, T408, T409, T410`.

## Slice 3 - Devnet Replay Proof

- [ ] T411 Add a devnet replay e2e proof that replays a chain to tip without error.
- [ ] T412 Assert the proof observed at least one replayed block and did not duplicate epoch-transition callbacks.
- [ ] T413 Keep the proof within replay scope: no snapshot extraction, CSMT, history database, rollback persistence, or HTTP changes.
- [ ] T414 Run `nix develop --quiet -c just e2e` and `./gate.sh`, then commit with subject `test: prove replay against devnet chainsync` and trailer `Tasks: T411, T412, T413, T414`.

## Finalization

- [ ] T415 Run `nix develop -c just ci` at HEAD.
- [ ] T416 Update the draft PR body with delivered behavior, proof commands, and residual risks.
- [ ] T417 Drop `gate.sh` in the final ready-for-review commit and mark PR #14 ready.
